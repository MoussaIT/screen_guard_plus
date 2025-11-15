import Flutter
import UIKit
import WebKit
import AVFoundation
import AVKit

public class ScreenGuardPlusPlugin: NSObject, FlutterPlugin {
  // ===== Policy (مقفولة) =====
  private let maskOnCapture: Bool = true       // دايمًا تسويد أثناء التسجيل/شاشة خارجية
  private let muteOnCapture: Bool = true       // دايمًا كتم للصوت أثناء التسجيل
  private var maskOnScreenshot: Bool = true    // قابل للتعديل من دارت

  // ===== Shield Style =====
  private enum ShieldStyle: String { case blur, black }
  private var shieldStyle: ShieldStyle = .blur

  // ===== Shield (window) =====
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
      startProtect()
      result(nil)

    case "stop":
      stopProtect()
      result(nil)

    case "setPolicy":
      if let args = call.arguments as? [String: Any] {
        if let v = args["maskOnScreenshot"] as? Bool { maskOnScreenshot = v }
      }
      result(nil)

    case "setShieldStyle":
      if let args = call.arguments as? [String: Any],
         let s = args["style"] as? String,
         let st = ShieldStyle(rawValue: s) {
        setShieldStyle(st)
      }
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Core
  private func startProtect() {
    guard !isRunning else { return }
    isRunning = true

    ensureShieldReady() // جهّز الشيلد مسبقًا (Instant toggle)

    // تسجيل الشاشة
    NotificationCenter.default.addObserver(self, selector: #selector(capturedChanged),
      name: UIScreen.capturedDidChangeNotification, object: nil)

    // لقطة الشاشة (يوصل بعد الالتقاط—نقفل بأسرع toggle)
    NotificationCenter.default.addObserver(self, selector: #selector(userDidScreenshot),
      name: UIApplication.userDidTakeScreenshotNotification, object: nil)

    // حماية Snapshot الـApp Switcher
    NotificationCenter.default.addObserver(self, selector: #selector(appWillResignActive),
      name: UIApplication.willResignActiveNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive),
      name: UIApplication.didBecomeActiveNotification, object: nil)

    // تغيّر مسار الصوت (AirPlay/HDMI/LineOut…)
    NotificationCenter.default.addObserver(self, selector: #selector(audioRouteChanged(_:)),
      name: AVAudioSession.routeChangeNotification, object: nil)

    // PiP: امنعه لو حاول يبدأ
    if #available(iOS 14.2, *) {
      NotificationCenter.default.addObserver(self, selector: #selector(stopPiPIfStarts(_:)),
        name: AVPictureInPictureController.willStartPictureInPictureNotification, object: nil)
      NotificationCenter.default.addObserver(self, selector: #selector(stopPiPIfStarts(_:)),
        name: AVPictureInPictureController.didStartPictureInPictureNotification, object: nil)
    }

    evaluateCaptureAndReact() // حالة أولية
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
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      buildShieldContent(in: w, style: style)
      w.layoutIfNeeded()
      CATransaction.commit()
      // حافظ على الحالة (مكشوف/مخفي)
      w.isHidden = !wasVisible
    }
  }

  private func showShield() {
    ensureShieldReady()
    guard let w = shieldWindow else { return }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    w.isHidden = false
    CATransaction.commit()
  }

  private func hideShield() {
    guard let w = shieldWindow else { return }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    w.isHidden = true
    CATransaction.commit()
  }

  // MARK: - Capture evaluation
  private func hasExternalDisplay() -> Bool { UIScreen.screens.count > 1 }

  private func isAirPlayActive() -> Bool {
    let route = AVAudioSession.sharedInstance().currentRoute
    for o in route.outputs {
      if o.portType == .airPlay || o.portType == .hdmi || o.portType == .lineOut {
        return true
      }
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

  @objc private func appWillResignActive() { showShield() } // Snapshot الـApp Switcher

  @objc private func appDidBecomeActive() { evaluateCaptureAndReact() }

  @objc private func audioRouteChanged(_ note: Notification) { evaluateCaptureAndReact() }

  @objc private func stopPiPIfStarts(_ note: Notification) {
    if #available(iOS 14.2, *) {
      if let pip = note.object as? AVPictureInPictureController, pip.isPictureInPictureActive {
        pip.stopPictureInPicture()
      }
    }
    showShield() // احترازيًا
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
      // لو عندك AVPlayer محدد، الأفضل تكتمه مباشرة: player.isMuted = true
      // لو فيديو داخل WKWebView: تحتاج حقن JS لكتم/إيقاف <video> لو عايز ميوت مؤكد
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
