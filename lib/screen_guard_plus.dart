import 'dart:async';
import 'package:flutter/services.dart';

enum ShieldStyle { blur, black }

class ScreenGuardPlus {
  static const MethodChannel _ch = MethodChannel('screen_guard_plus');

  /// فعّل الحماية الدائمة
  static Future<void> start() => _ch.invokeMethod('start');

  /// أوقف الحماية (نادراً)
  static Future<void> stop() => _ch.invokeMethod('stop');

  /// اسمح/امنع لقطات الشاشة:
  /// allow = true  => يسمح بالسكرين شوت
  /// allow = false => يمنع/يسوّد السكرين شوت
  static Future<void> allowScreenshots(bool allow) {
    return _ch.invokeMethod('setPolicy', {
      'maskOnScreenshot': !allow,
    });
  }

  /// غيّر ستايل الشيلد أثناء التشغيل: Blur أو Black
  static Future<void> setShieldStyle(ShieldStyle style) {
    return _ch.invokeMethod('setShieldStyle', {
      'style': style.name, // 'blur' | 'black'
    });
  }
}
