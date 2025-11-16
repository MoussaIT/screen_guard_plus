import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

enum ShieldStyle { blur, black }

class ScreenGuardPlus {
  static const _ch = MethodChannel('screen_guard_plus');

  static Future<void> start() => _ch.invokeMethod('start');
  static Future<void> stop()  => _ch.invokeMethod('stop');

  // iOS only
  static Future<void> setShieldStyle(ShieldStyle style) async {
    if (kIsWeb || !Platform.isIOS) return;
    await _ch.invokeMethod('setShieldStyle', {'style': style.name});
  }

  // iOS only
  static Future<void> allowScreenshots(bool allow) async {
    if (kIsWeb || !Platform.isIOS) return;
    await _ch.invokeMethod('setPolicy', {'maskOnScreenshot': !allow});
  }

  // iOS only
  static Future<void> forceShield(bool on) async {
    if (kIsWeb || !Platform.isIOS) return;
    await _ch.invokeMethod('forceShield', {'on': on});
  }
}
