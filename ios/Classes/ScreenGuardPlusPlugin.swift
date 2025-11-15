import Flutter
import UIKit
import WebKit
import AVFoundation
import AVKit

public class ScreenGuardPlusPlugin: NSObject, FlutterPlugin {
  // ===== Policy (ثابتة) =====
  private let maskOnCapture: Bool = true
  private let muteOnCapture: Bool = true
  private var maskOnScreenshot: Bool = true

  // ===== Shield Style =====
  private enum ShieldStyle: String { case blur, black }
  private var shieldStyle: ShieldStyle = .blur

  // ===== Shield =====
  private var shieldWindow: UIWindow?
  private var isRunning = false

  // Audio session backup/restore
  private var lastAudioCategory: AVAudioSession.Category?
  private var lastAudioOptions: AVAudioSession.CategoryOptions = []
  private var lastAudioMode: AVAudioSession.Mode?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "screen_guard_plus",
                                       binaryMessenger: registrar.messenger())
    let instance = ScreenGuardPlusPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "start":
      startProtect(); result(nil)
    case "stop":
      stopProtect(); result(nil)
    case "setPolicy":
      if let args = call.arguments as? [String: Any],
         let v = args["maskOnScreenshot"] as? Bool { maskOnScreenshot = v }
      result(nil)
    case "setShieldStyle":
      if let args = call.arguments as? [String: Any],
         let s = args["style"] as? String,
         let st = ShieldStyle(rawValue: s) { setShieldStyle(st) }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Core
  private func startProtect() {
    guard !isRunning else { return }
    isRunning = true

    ensureShieldReady()

    // تسجيل الشاشة
    NotificationCenter.default.addObserver(self, selector: #selector(capturedChanged),
      name: UIScreen.capturedDidChangeNotification, object: nil)

    // لقطة الشاشة
    NotificationCenter.default.addObserver(self, selector: #selector(userDidScreenshot),
      name: UIApplication.userDidTakeScreenshotNotification, object: nil)

    // حماية Snapshot
    NotificationCenter.default.addObserver(self, selector: #selector(appWillResignActive),
      name: UIApplication.willResignActiveNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive),
      name: UIApplication.didBecomeActiveNotification, object: nil)

    // تغيّر مسار الصوت (AirPlay/HDMI/LineOut…)
    NotificationCenter.default.addObserver(self, selector: #selector(audioRouteChanged(_:)),
      name: AVAudioSession.routeChangeNotification, object: nil)

    // PiP: استخدم أسماء نصّية للـnotifications لتفادي غياب الـsymbols في SDK قديم
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
    unmuteIfNeeded()
    hideShield()
  }

  // MARK: - Shield build/update
  private func ensureShieldReady() {
    guard shieldWindow == nil else { return }
    guard let scene = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .first(where: { $0.activationState == .foregroundActive }) else { return }

    let w = UIWindow(windowScene: scene)
    w.frame = UIScreen.main.bounds
    if #available(iOS 13.0, *) {
      w.windowLevel = UIWindow.Level.statusBar + 2
    } else {
      w.windowLevel = UIWindow.Level.alert + 1
    }
    w.isHidden = true
    w.isUserInteractionEnabled = false
    w.backgroundColor = .clear

    buildShieldContent(in: w, style: shieldStyle)
    shieldWindow = w
  }

  private func buildShieldContent(in window: UIWindow, style: ShieldStyle) {
    window.subviews.forEach { $0.removeFromSuperview() }
    switch style {
    case .black:
      let v = UIView(frame: window.bounds)
      v.backgroundColor = .black
      v.isUserInteractionEnabled = false
      v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      window.addSubview(v)
    case .blur:
      let effect = UIBlurEffect(style: .systemUltraThinMaterialDark)
      let blurView = UIVisualEffectView(effect: effect)
      blurView.frame = window.bounds
      blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      blurView.isUserInteractionEnabled = false

      let dim = UIView(frame: window.bounds)
      dim.backgroundColor = UIColor.black.withAlphaComponent(0.35)
      dim.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      dim.isUserInteractionEnabled = false

      window.addSubview(blurView)
      window.addSubview(dim)
    }
  }

  private func setShieldStyle(_ style: ShieldStyle) {
    shieldStyle = style
    if let w = shieldWindow {
      let wasVisible = !w.isHidden
      CATransaction.begin(); CATransaction.setDisableActions(true)
      buildShieldContent(in: w, style: style)
      w.layoutIfNeeded()
      CATransaction.commit()
      w.isHidden = !wasVisible
    }
  }

  private func showShield() {
    ensureShieldReady()
    guard let w = shieldWindow else { return }
    CATransaction.begin(); CATransaction.setDisableActions(true)
    w.isHidden = false
    CATransaction.commit()
  }

  private func hideShield() {
    guard let w = shieldWindow else { return }
    CATransaction.begin(); CATransaction.setDisableActions(true)
    w.isHidden = true
    CATransaction.commit()
  }

  // MARK: - Capture evaluation
  private func hasExternalDisplay() -> Bool { UIScreen.screens.count > 1 }

  private func isAirPlayActive() -> Bool {
    let route = AVAudioSession.sharedInstance().currentRoute
    for o in route.outputs {
      // .airPlay متاح غالبًا، HDMI قد لا يكون متاحًا في SDK قديم — فحص بالنص
      if o.portType == .airPlay { return true }
      if o.portType.rawValue.uppercased().contains("HDMI") { return true }
      if o.portType.rawValue.uppercased().contains("LINE") { return true }
    }
    return false
  }

  private func evaluateCaptureAndReact() {
    let captured = UIScreen.main.isCaptured || hasExternalDisplay() || isAirPlayActive()
    if captured {
      if maskOnCapture { showShield() }
      if muteOnCapture { muteIfNeeded() }
    } else {
      unmuteIfNeeded()
      hideShield()
    }
  }

  // MARK: - Notifications
  @objc private func capturedChanged() { evaluateCaptureAndReact() }

  @objc private func userDidScreenshot() {
    guard maskOnScreenshot else { return }
    showShield()
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
      self?.evaluateCaptureAndReact()
    }
  }

  @objc private func appWillResignActive() { showShield() }
  @objc private func appDidBecomeActive() { evaluateCaptureAndReact() }
  @objc private func audioRouteChanged(_ note: Notification) { evaluateCaptureAndReact() }

  @objc private func stopPiPIfStarts(_ note: Notification) {
    // ما نحاولش نلمس AVPictureInPictureController هنا عشان SDK قديم ممكن يفتقده
    // كحل عملي: بس أظهر الشيلد فورًا لتعتيم المشهد
    showShield()
  }

  // MARK: - Audio mute/unmute
  private func muteIfNeeded() {
    let session = AVAudioSession.sharedInstance()
    if lastAudioCategory == nil {
      lastAudioCategory = session.category
      lastAudioMode = session.mode
      lastAudioOptions = session.categoryOptions
    }
    do {
      try session.setCategory(.playback, options: [])
      try session.setActive(true)
    } catch { /* ignore */ }
  }

  private func unmuteIfNeeded() {
    guard let cat = lastAudioCategory else { return }
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(cat, mode: lastAudioMode ?? .default, options: lastAudioOptions)
      try session.setActive(true)
    } catch { /* ignore */ }
    lastAudioCategory = nil
    lastAudioMode = nil
    lastAudioOptions = []
  }
}
