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
  private var defaultShieldStyle: ShieldStyle = .blur
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

  // ===== NEW: Secure & Watermark Variables =====
  private var secureField: UITextField?
  private weak var originalWindow: UIWindow?
  private weak var flutterView: UIView?
  private var watermarkLabel: UILabel?

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
      startProtect()
      result(nil)

    case "stop":
      stopProtect()
      result(nil)

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
        evaluateCaptureAndReact()
      }
      result(nil)
        
    // ===== NEW: Watermark Methods =====
    case "addWatermark":
      if let args = call.arguments as? [String: Any],
         let text = args["text"] as? String,
         let colorHex = args["color"] as? String {
          let size = args["size"] as? CGFloat ?? 45.0
          addWatermark(text: text, hexColor: colorHex, fontSize: size)
      }
      result(nil)
        
    case "removeWatermark":
      removeWatermark()
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
    
    // تفعيل الحماية الجذرية (الاسكرين شوت الأسود)
    enableSecureMode()

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
    
    disableSecureMode()
    removeWatermark()
    unmuteIfNeeded()
    hideShield()
  }

  // MARK: - NEW: Secure Field Trick (Screenshot Blocker)
  private func enableSecureMode() {
      // التأكد من عدم تشغيلها مرتين
      guard secureField == nil else { return }
      
      DispatchQueue.main.async { [weak self] in
          guard let self = self else { return }
          guard let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }),
                let rootVC = window.rootViewController,
                let fView = rootVC.view else { return }
          
          self.originalWindow = window
          self.flutterView = fView
          
          // 1. إنشاء الحقل المخفي
          let field = UITextField()
          field.isSecureTextEntry = true
          field.backgroundColor = .clear
          field.isUserInteractionEnabled = false // لضمان مرور التاتش
          
          window.addSubview(field)
          field.translatesAutoresizingMaskIntoConstraints = false
          NSLayoutConstraint.activate([
              field.topAnchor.constraint(equalTo: window.topAnchor),
              field.bottomAnchor.constraint(equalTo: window.bottomAnchor),
              field.leadingAnchor.constraint(equalTo: window.leadingAnchor),
              field.trailingAnchor.constraint(equalTo: window.trailingAnchor)
          ])
          
          // 2. الحصول على الطبقة الآمنة (Secure Container)
          guard let secureContainer = field.layer.sublayers?.first?.delegate as? UIView else {
              field.removeFromSuperview()
              return
          }
          
          // 3. نقل عرض فلاتر للداخل
          fView.removeFromSuperview()
          secureContainer.addSubview(fView)
          
          fView.translatesAutoresizingMaskIntoConstraints = false
          NSLayoutConstraint.activate([
              fView.topAnchor.constraint(equalTo: secureContainer.topAnchor),
              fView.bottomAnchor.constraint(equalTo: secureContainer.bottomAnchor),
              fView.leadingAnchor.constraint(equalTo: secureContainer.leadingAnchor),
              fView.trailingAnchor.constraint(equalTo: secureContainer.trailingAnchor)
          ])
          
          secureContainer.isUserInteractionEnabled = true
          fView.isUserInteractionEnabled = true
          
          self.secureField = field
      }
  }

  private func disableSecureMode() {
      DispatchQueue.main.async { [weak self] in
          guard let self = self,
                let field = self.secureField,
                let window = self.originalWindow,
                let fView = self.flutterView else { return }
          
          // إرجاع الفيو للنافذة الرئيسية
          fView.removeFromSuperview()
          window.addSubview(fView)
          
          fView.translatesAutoresizingMaskIntoConstraints = false
          NSLayoutConstraint.activate([
              fView.topAnchor.constraint(equalTo: window.topAnchor),
              fView.bottomAnchor.constraint(equalTo: window.bottomAnchor),
              fView.leadingAnchor.constraint(equalTo: window.leadingAnchor),
              fView.trailingAnchor.constraint(equalTo: window.trailingAnchor)
          ])
          
          window.rootViewController?.view = fView
          field.removeFromSuperview()
          self.secureField = nil
      }
  }

  // MARK: - NEW: Watermark Logic
  private func addWatermark(text: String, hexColor: String, fontSize: CGFloat) {
      removeWatermark() // تنظيف لو فيه ووترمارك قديمة
      
      DispatchQueue.main.async { [weak self] in
          guard let self = self else { return }
          // نجيب الـ Flutter View سواء كنا في الوضع الآمن أو العادي
          guard let fView = self.flutterView ?? UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.rootViewController?.view else { return }
          
          let label = UILabel()
          label.text = text
          label.textColor = UIColor(hex: hexColor)
          label.font = UIFont.boldSystemFont(ofSize: fontSize)
          label.alpha = 0.4 // الشفافية 0.4 حسب طلبك
          label.textAlignment = .center
          label.numberOfLines = 0
          
          // التدوير
          label.transform = CGAffineTransform(rotationAngle: -CGFloat.pi / 4)
          label.isUserInteractionEnabled = false // عشان التاتش يعدي للمحتوى
          
          fView.addSubview(label)
          fView.bringSubviewToFront(label)
          
          label.translatesAutoresizingMaskIntoConstraints = false
          NSLayoutConstraint.activate([
              label.centerXAnchor.constraint(equalTo: fView.centerXAnchor),
              label.centerYAnchor.constraint(equalTo: fView.centerYAnchor),
              // بنكبر العرض والارتفاع عشان لما نلفها تغطي نص الشاشة زي ما طلبت
              label.widthAnchor.constraint(equalTo: fView.widthAnchor, multiplier: 1.5),
              label.heightAnchor.constraint(equalTo: fView.heightAnchor, multiplier: 0.5)
          ])
          
          self.watermarkLabel = label
      }
  }

  private func removeWatermark() {
      DispatchQueue.main.async { [weak self] in
          self?.watermarkLabel?.removeFromSuperview()
          self?.watermarkLabel = nil
      }
  }

  // MARK: - Shield build/update (القديم بتاعك كما هو)
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

  private func setDefaultShieldStyle(_ style: ShieldStyle) {
    defaultShieldStyle = style
    if let w = shieldWindow, !w.isHidden, currentVisibleStyle != style {
      return
    }
    if let w = shieldWindow, w.isHidden {
      CATransaction.begin(); CATransaction.setDisableActions(true)
      buildShieldContent(in: w, style: style)
      w.layoutIfNeeded()
      CATransaction.commit()
    }
  }

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
      if o.portType == .airPlay { return true }
      if o.portType.rawValue.uppercased().contains("HDMI") { return true }
      if o.portType.rawValue.uppercased().contains("LINE") { return true }
    }
    return false
  }

  private func evaluateCaptureAndReact() {
    let captured = UIScreen.main.isCaptured || hasExternalDisplay() || isAirPlayActive()

    if forcedShield {
      if captured {
        showShield(as: .black)
        if muteOnCapture { muteIfNeeded() }
      } else {
        unmuteIfNeeded()
        showShield(as: defaultShieldStyle)
      }
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

  // MARK: - Notifications
  @objc private func capturedChanged() {
    evaluateCaptureAndReact()
  }

  @objc private func userDidScreenshot() {
    guard maskOnScreenshot else { return }
    // الاسكرين شوت كده كده هتبقى سودة بسبب الـ SecureMode
    // بس ده بيعمل Blur للمستخدم لمدة ثانية كنوع من التنبيه
    showShield(as: .blur)
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
      self?.evaluateCaptureAndReact()
    }
  }

  @objc private func appWillResignActive() {
    showShield(as: defaultShieldStyle)
  }

  @objc private func appDidBecomeActive() { evaluateCaptureAndReact() }

  @objc private func audioRouteChanged(_ note: Notification) { evaluateCaptureAndReact() }

  @objc private func stopPiPIfStarts(_ note: Notification) {
    showShield(as: .black)
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

// MARK: - Streams
extension ScreenGuardPlusPlugin: FlutterStreamHandler {
  public func onListen(withArguments args: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventsSink = events; return nil
  }
  public func onCancel(withArguments args: Any?) -> FlutterError? {
    eventsSink = nil; return nil
  }
}

// MARK: - Helpers (Hex Color)
extension UIColor {
    convenience init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}