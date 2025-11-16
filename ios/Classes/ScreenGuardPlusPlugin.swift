import Flutter
import UIKit
import WebKit
import AVFoundation
import AVKit

public class ScreenGuardPlusPlugin: NSObject, FlutterPlugin {
  // ===== Policy (ثابتة) =====
  private let maskOnCapture: Bool = true      // اعرض شيلد أثناء التسجيل/الإخراجات
  private let muteOnCapture: Bool = true      // اختياري: كتم الصوت أثناء التسجيل
  private var maskOnScreenshot: Bool = true   // اعرض شيلد وقت لقطة الشاشة

  // ===== Shield Style =====
  private enum ShieldStyle: String { case blur, black }
  /// الستايل الافتراضي لما "مفيش تسجيل"
  private var defaultShieldStyle: ShieldStyle = .blur
  /// الستايل الحالي المعروض فعليًا
  private var currentVisibleStyle: ShieldStyle?

  // ===== Forced Overlay (لأوضاع صارمة) =====
  private var forcedShield: Bool = false

  // ===== Shield Window =====
  private var shieldWindow: UIWindow?
  private var isRunning = false

  // Audio session backup/restore
  private var lastAudioCategory: AVAudioSession.Category?
  private var lastAudioOptions: AVAudioSession.CategoryOptions = []
  private var lastAudioMode: AVAudioSession.Mode?

  // (اختياري) قناة أحداث لو محتاج
  private var eventsChannel: FlutterEventChannel?
  private var eventsSink: FlutterEventSink?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "screen_guard_plus",
                                       binaryMessenger: registrar.messenger())
    let instance = ScreenGuardPlusPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)

    // (اختياري) لو عايز تبعت أحداث
    instance.eventsChannel = FlutterEventChannel(name: "screen_guard_plus/events",
                                                 binaryMessenger: registrar.messenger())
    instance.eventsChannel?.setStreamHandler(instance)
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
         let st = ShieldStyle(rawValue: s) {
        setDefaultShieldStyle(st)
      }
      result(nil)

    case "forceShield":
      if let args = call.arguments as? [String: Any],
         let on = args["on"] as? Bool {
        forcedShield = on
        evaluateCaptureAndReact() // يقرر Black لو Recording أو default otherwise
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

    ensureShieldReady()

    // تسجيل الشاشة (عند تغيّر الحالة)
    NotificationCenter.default.addObserver(self, selector: #selector(capturedChanged),
      name: UIScreen.capturedDidChangeNotification, object: nil)

    // لقطة الشاشة
    NotificationCenter.default.addObserver(self, selector: #selector(userDidScreenshot),
      name: UIApplication.userDidTakeScreenshotNotification, object: nil)

    // حماية Snapshot الـApp Switcher (خلفية/قفل)
    NotificationCenter.default.addObserver(self, selector: #selector(appWillResignActive),
      name: UIApplication.willResignActiveNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive),
      name: UIApplication.didBecomeActiveNotification, object: nil)

    // تغيّر مسار الصوت (AirPlay/HDMI/LineOut…)
    NotificationCenter.default.addObserver(self, selector: #selector(audioRouteChanged(_:)),
      name: AVAudioSession.routeChangeNotification, object: nil)

    // PiP: استخدم أسماء نصّية لتوافق SDK قديم
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

    // ابنِ بالمبدئي (مش هيبان إلا عند showShield)
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
    currentVisibleStyle = style
  }

  /// غيّر الستايل الافتراضي (يستخدم فقط لما مفيش تسجيل/إخراجات/لقطة شاشة)
  private func setDefaultShieldStyle(_ style: ShieldStyle) {
    defaultShieldStyle = style
    // لو الشيلد ظاهر بأسلوب آخر بسبب تسجيل/لقطة، نسيبه كما هو.
    if let w = shieldWindow, !w.isHidden, currentVisibleStyle != style {
      return
    }
    // لو مخفي، حضّر المحتوى بالستايل الجديد
    if let w = shieldWindow, w.isHidden {
      CATransaction.begin(); CATransaction.setDisableActions(true)
      buildShieldContent(in: w, style: style)
      w.layoutIfNeeded()
      CATransaction.commit()
    }
  }

  /// إظهار الشيلد بستایل معين (مع إعادة بناء المحتوى لو مختلف)
  private func showShield(as style: ShieldStyle) {
    ensureShieldReady()
    guard let w = shieldWindow else { return }

    if currentVisibleStyle != style {
      CATransaction.begin(); CATransaction.setDisableActions(true)
      buildShieldContent(in: w, style: style)
      CATransaction.commit()
    }

    CATransaction.begin(); CATransaction.setDisableActions(true)
    w.isHidden = false
    CATransaction.commit()
  }

  private func showShield() { showShield(as: defaultShieldStyle) }

  private func hideShield() {
    // لو مجبَر (forceShield)، ما نخبّيش الشيلد
    guard !forcedShield else { return }
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
      // .airPlay غالبًا متاح، HDMI/LINE قد تغيب في SDK قديم — فحص بالنص
      if o.portType == .airPlay { return true }
      if o.portType.rawValue.uppercased().contains("HDMI") { return true }
      if o.portType.rawValue.uppercased().contains("LINE") { return true }
    }
    return false
  }

  /// الحالة العامة / واحترام forceShield:
  /// - لو forcedShield=true: نُظهر الشيلد دائمًا (Black لو في تسجيل، وإلا default).
  /// - لو false: نظهر الشيلد فقط عند التسجيل/الإخراجات، ونخفيه غير ذلك.
  private func evaluateCaptureAndReact() {
    let captured = UIScreen.main.isCaptured || hasExternalDisplay() || isAirPlayActive()

    if forcedShield {
      if captured {
        showShield(as: .black)        // تسجيل/إخراجات ⇒ أسود
        if muteOnCapture { muteIfNeeded() }
      } else {
        unmuteIfNeeded()
        showShield(as: defaultShieldStyle)
      }
      return
    }

    // الوضع العادي
    if captured {
      if maskOnCapture { showShield(as: .black) }  // تسجيل/إخراجات ⇒ أسود
      if muteOnCapture { muteIfNeeded() }
    } else {
      unmuteIfNeeded()
      hideShield()
    }
  }

  // MARK: - Notifications
  @objc private func capturedChanged() {
    evaluateCaptureAndReact()
    // (اختياري) eventsSink?("recording_" + (UIScreen.main.isCaptured ? "start" : "stop"))
  }

  @objc private func userDidScreenshot() {
    guard maskOnScreenshot else { return }
    // لقطة الشاشة: اعرض Blur لحظيًّا
    showShield(as: .blur)
    // ثم ارجع للوضع المناسب بعد 1 ثانية
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
      self?.evaluateCaptureAndReact()
    }
    // (اختياري) eventsSink?("screenshot")
  }

  @objc private func appWillResignActive() {
    // Snapshot الـApp Switcher: استخدم الافتراضي (blur أو black حسب اختيارك)
    showShield(as: defaultShieldStyle)
  }

  @objc private func appDidBecomeActive() { evaluateCaptureAndReact() }

  @objc private func audioRouteChanged(_ note: Notification) { evaluateCaptureAndReact() }

  @objc private func stopPiPIfStarts(_ note: Notification) {
    // SDKs قديمة قد تفتقد PiP symbols — نغطي مباشرة
    showShield(as: .black)  // احترازيًا خليها أسود مع أي محاولة PiP
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

// (اختياري) دعم قناة الأحداث
extension ScreenGuardPlusPlugin: FlutterStreamHandler {
  public func onListen(withArguments args: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventsSink = events; return nil
  }
  public func onCancel(withArguments args: Any?) -> FlutterError? {
    eventsSink = nil; return nil
  }
}
