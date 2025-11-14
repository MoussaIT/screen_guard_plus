import Flutter
import UIKit
import WebKit

public class ScreenGuardPlusPlugin: NSObject, FlutterPlugin {
  private var shieldWindow: UIWindow?
  private var isRunning = false
  private var webViewSafetyEnabled = false

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

    case "enableWebViewSafety":
      webViewSafetyEnabled = true
      // لو عندك WKWebView مخصص، وقت إنشائه استخدم إعدادات تمنع AirPlay/PiP
      result(nil)

    case "disableWebViewSafety":
      webViewSafetyEnabled = false
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Core

  private func startProtect() {
    guard !isRunning else { return }
    isRunning = true

    // مراقبة تسجيل الشاشة
    NotificationCenter.default.addObserver(
      self, selector: #selector(capturedChanged),
      name: UIScreen.capturedDidChangeNotification, object: nil
    )
    // لقطة الشاشة
    NotificationCenter.default.addObserver(
      self, selector: #selector(userDidScreenshot),
      name: UIApplication.userDidTakeScreenshotNotification, object: nil
    )
    // حماية Snapshot الـApp Switcher
    NotificationCenter.default.addObserver(
      self, selector: #selector(appWillResignActive),
      name: UIApplication.willResignActiveNotification, object: nil
    )
    NotificationCenter.default.addObserver(
      self, selector: #selector(appDidBecomeActive),
      name: UIApplication.didBecomeActiveNotification, object: nil
    )

    // فحص أولي للحالة الحالية + شاشة خارجية
    let externalDisplay = UIScreen.screens.count > 1
    handleCapture(UIScreen.main.isCaptured || externalDisplay)
  }

  private func stopProtect() {
    isRunning = false
    NotificationCenter.default.removeObserver(self)
    hideShield()
  }

  // MARK: - Notifications

  @objc private func capturedChanged() {
    let externalDisplay = UIScreen.screens.count > 1
    handleCapture(UIScreen.main.isCaptured || externalDisplay)
  }

  @objc private func userDidScreenshot() {
    // غطّي المحتوى لحظيًا عشان اللقطة تطلع سودا
    showShield()
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
      guard let self = self else { return }
      let externalDisplay = UIScreen.screens.count > 1
      self.handleCapture(UIScreen.main.isCaptured || externalDisplay)
    }
  }

  @objc private func appWillResignActive() {
    // قبل الذهاب للخلفية: غطّي علشان Snapshot الـApp Switcher
    showShield()
  }

  @objc private func appDidBecomeActive() {
    let externalDisplay = UIScreen.screens.count > 1
    handleCapture(UIScreen.main.isCaptured || externalDisplay)
  }

  // MARK: - Shield helpers

  private func handleCapture(_ captured: Bool) {
    if captured {
      showShield()
    } else {
      hideShield()
    }
  }

  private func showShield() {
    guard shieldWindow == nil else { return }

    guard let scene = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .first(where: { $0.activationState == .foregroundActive }) else { return }

    let w = UIWindow(windowScene: scene)
    w.frame = UIScreen.main.bounds
    // مستوى عالي جدًا لتغطية أي VC fullscreen (حتى WebKit/AVPlayer)
    if #available(iOS 13.0, *) {
      w.windowLevel = UIWindow.Level.statusBar + 1
    } else {
      w.windowLevel = UIWindow.Level.alert + 1
    }

    let v = UIView(frame: w.bounds)
    v.backgroundColor = .black // لو عايز Blur: استخدم UIBlurEffect بدلاً من السواد

    w.isHidden = false
    w.addSubview(v)
    shieldWindow = w
  }

  private func hideShield() {
    shieldWindow?.isHidden = true
    shieldWindow = nil
  }
}
