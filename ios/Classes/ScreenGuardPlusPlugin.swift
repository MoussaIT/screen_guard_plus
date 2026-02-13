import Flutter
import UIKit
import WebKit
import AVFoundation
import AVKit

public class ScreenGuardPlusPlugin: NSObject, FlutterPlugin {
  
  // MARK: - Properties
    
  // ===== Policy =====
  private let maskOnCapture: Bool = true
  private let muteOnCapture: Bool = true
  private var maskOnScreenshot: Bool = false // تم تعطيله افتراضياً

  // ===== Shield Style =====
  private enum ShieldStyle: String { case blur, black }
  private var defaultShieldStyle: ShieldStyle = .blur
  private var currentVisibleStyle: ShieldStyle?

  // ===== Forced Overlay =====
  private var forcedShield: Bool = false

  // ===== Shield Window =====
  private var shieldWindow: UIWindow?
  private var isRunning = false

  // Audio session
  private var lastAudioCategory: AVAudioSession.Category?
  private var lastAudioOptions: AVAudioSession.CategoryOptions = []
  private var lastAudioMode: AVAudioSession.Mode?

  // ===== Secure Variables =====
  private var secureField: UITextField?
  private weak var originalWindow: UIWindow?
  private weak var flutterView: UIView?

  // Events
  private var eventsChannel: FlutterEventChannel?
  private var eventsSink: FlutterEventSink?

  // MARK: - Registration
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "screen_guard_plus",
                                       binaryMessenger: registrar.messenger())
    let instance = ScreenGuardPlusPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)

    instance.eventsChannel = FlutterEventChannel(name: "screen_guard_plus/events",
                                                 binaryMessenger: registrar.messenger())
    instance.eventsChannel?.setStreamHandler(instance)
  }

  // MARK: - Handle Methods
  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "start":
      startProtect()
      result(nil)

    case "stop":
      stopProtect()
      result(nil)

    case "setPolicy":
        // تركناها للتوافق مع Flutter ولكنها لن تؤثر على الـ UI الآن
      if let args = call.arguments as? [String: Any],
         let v = args["maskOnScreenshot"] as? Bool { maskOnScreenshot = v }
      result(nil)

    case "setShieldStyle":
      if let args = call.arguments as? [String: Any],
         let s = args["style"] as? String,
         let st = ShieldStyle(rawValue: s) {
        setDefaultShieldStyle(st)
      }
      result(nil)

    case "forceShield":
      if let args = call.arguments as? [String: Any],
         let on = args["on"] as? Bool {
        forcedShield = on
        evaluateCaptureAndReact()
      }
      result(nil)
        
    case "addWatermark", "removeWatermark":
      // تم تعطيل الووتر مارك تماماً بناءً على طلبك
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Core Logic
  private func startProtect() {
    guard !isRunning else { return }
    isRunning = true

    ensureShieldReady()
    
    // الحفاظ على منع تسجيل الفيديو كما هو (Secure Field Trick)
    enableSecureMode()

    // Observers
    NotificationCenter.default.addObserver(self, selector: #selector(capturedChanged),
      name: UIScreen.capturedDidChangeNotification, object: nil)

    // تم تعطيل مراقب السكرين شوت لضمان عدم تأثر الـ UI
    // NotificationCenter.default.addObserver(self, selector: #selector(userDidScreenshot), ...)

    NotificationCenter.default.addObserver(self, selector: #selector(appWillResignActive),
      name: UIApplication.willResignActiveNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive),
      name: UIApplication.didBecomeActiveNotification, object: nil)

    NotificationCenter.default.addObserver(self, selector: #selector(audioRouteChanged(_:)),
      name: AVAudioSession.routeChangeNotification, object: nil)

    if #available(iOS 14.0, *) {
      let willStart = Notification.Name("AVPictureInPictureControllerWillStartPictureInPicture")
      let didStart  = Notification.Name("AVPictureInPictureControllerDidStartPictureInPicture")
      NotificationCenter.default.addObserver(self, selector: #selector(stopPiPIfStarts(_:)),
        name: willStart, object: nil)
      NotificationCenter.default.addObserver(self, selector: #selector(stopPiPIfStarts(_:)),
        name: didStart, object: nil)
    }

    evaluateCaptureAndReact()
  }

  private func stopProtect() {
    isRunning = false
    NotificationCenter.default.removeObserver(self)
    
    disableSecureMode()
    unmuteIfNeeded()
    hideShield()
  }

  // MARK: - Secure Field Trick (بقيت كما هي تماماً لمنع تسجيل الفيديو)
  private func enableSecureMode() {
      guard secureField == nil else { return }
      
      DispatchQueue.main.async { [weak self] in
          guard let self = self else { return }
          guard let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }) ?? UIApplication.shared.delegate?.window as? UIWindow else { return }
          guard let rootVC = window.rootViewController, let fView = rootVC.view else { return }
          
          self.originalWindow = window
          self.flutterView = fView
          
          let field = UITextField()
          field.isSecureTextEntry = true
          field.isUserInteractionEnabled = true
          field.backgroundColor = .clear
          field.frame = window.bounds
          field.autoresizingMask = [.flexibleWidth, .flexibleHeight]
          
          window.addSubview(field)
          window.sendSubviewToBack(field)
          field.layoutIfNeeded()
          
          var secureContainer: UIView?
          if let layers = field.layer.sublayers {
              for layer in layers {
                  if let view = layer.delegate as? UIView {
                      secureContainer = view
                      break 
                  }
              }
          }
          
          if secureContainer == nil {
              secureContainer = field.subviews.first
          }
          
          guard let finalContainer = secureContainer else {
              field.removeFromSuperview()
              return
          }
          
          finalContainer.frame = window.bounds
          finalContainer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
          finalContainer.isUserInteractionEnabled = true 
          
          fView.removeFromSuperview()
          finalContainer.addSubview(fView)
          
          fView.frame = finalContainer.bounds
          fView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
          
          self.secureField = field
          window.layoutIfNeeded()
          rootVC.view.becomeFirstResponder()
      }
  }

  private func disableSecureMode() {
      DispatchQueue.main.async { [weak self] in
          guard let self = self,
                let field = self.secureField,
                let window = self.originalWindow,
                let fView = self.flutterView else { return }
          
          fView.removeFromSuperview()
          window.addSubview(fView)
          window.rootViewController?.view = fView 
          
          fView.frame = window.bounds
          fView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
          
          field.removeFromSuperview()
          self.secureField = nil
      }
  }

  // MARK: - Shield Logic
  private func ensureShieldReady() {
    guard shieldWindow == nil else { return }
    guard let scene = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .first(where: { $0.activationState == .foregroundActive }) else { return }

    let w = UIWindow(windowScene: scene)
    w.frame = UIScreen.main.bounds
    w.windowLevel = UIWindow.Level.statusBar + 2
    w.isHidden = true
    w.isUserInteractionEnabled = false
    w.backgroundColor = .clear

    buildShieldContent(in: w, style: defaultShieldStyle)
    shieldWindow = w
    currentVisibleStyle = defaultShieldStyle
  }

  private func buildShieldContent(in window: UIWindow, style: ShieldStyle) {
    window.subviews.forEach { $0.removeFromSuperview() }
    switch style {
    case .black:
      let v = UIView(frame: window.bounds)
      v.backgroundColor = .black
      v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      window.addSubview(v)
    case .blur:
      let effect = UIBlurEffect(style: .systemUltraThinMaterialDark)
      let blurView = UIVisualEffectView(effect: effect)
      blurView.frame = window.bounds
      blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      window.addSubview(blurView)
    }
    currentVisibleStyle = style
  }

  private func setDefaultShieldStyle(_ style: ShieldStyle) {
    defaultShieldStyle = style
    if let w = shieldWindow, w.isHidden {
      buildShieldContent(in: w, style: style)
    }
  }

  private func showShield(as style: ShieldStyle) {
    ensureShieldReady()
    guard let w = shieldWindow else { return }
    if currentVisibleStyle != style {
      buildShieldContent(in: w, style: style)
    }
    w.isHidden = false
  }

  private func hideShield() {
    guard !forcedShield else { return }
    shieldWindow?.isHidden = true
  }

  private func evaluateCaptureAndReact() {
    let captured = UIScreen.main.isCaptured || (UIScreen.screens.count > 1) 

    if forcedShield {
      captured ? showShield(as: .black) : showShield(as: defaultShieldStyle)
      return
    }

    if captured {
      if maskOnCapture { showShield(as: .black) }
      if muteOnCapture { muteIfNeeded() }
    } else {
      unmuteIfNeeded()
      hideShield()
    }
  }

  // MARK: - Selectors
  @objc private func capturedChanged() { evaluateCaptureAndReact() }
  
  // دالة تصوير الشاشة أصبحت فارغة ولا تؤثر على الـ UI
  @objc private func userDidScreenshot() { }

  @objc private func appWillResignActive() { showShield(as: defaultShieldStyle) }
  @objc private func appDidBecomeActive() { evaluateCaptureAndReact() }
  @objc private func audioRouteChanged(_ note: Notification) { evaluateCaptureAndReact() }
  @objc private func stopPiPIfStarts(_ note: Notification) { showShield(as: .black) }

  // MARK: - Audio Logic (بقيت كما هي)
  private func muteIfNeeded() {
    let session = AVAudioSession.sharedInstance()
    if lastAudioCategory == nil {
      lastAudioCategory = session.category
      lastAudioMode = session.mode
      lastAudioOptions = session.categoryOptions
    }
    try? session.setCategory(.playback, options: [])
    try? session.setActive(true)
  }

  private func unmuteIfNeeded() {
    guard let cat = lastAudioCategory else { return }
    let session = AVAudioSession.sharedInstance()
    try? session.setCategory(cat, mode: lastAudioMode ?? .default, options: lastAudioOptions)
    try? session.setActive(true)
    lastAudioCategory = nil
  }
}

extension ScreenGuardPlusPlugin: FlutterStreamHandler {
  public func onListen(withArguments args: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventsSink = events; return nil
  }
  public func onCancel(withArguments args: Any?) -> FlutterError? {
    eventsSink = nil; return nil
  }
}