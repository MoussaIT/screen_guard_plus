import 'dart:io' show Platform;
import 'dart:ui'; 
import 'package:flutter/foundation.dart' show kIsWeb;
import 'screen_guard_plus_platform_interface.dart';

export 'dart:ui' show Color; 

enum ShieldStyle { blur, black }

class ScreenGuardPlus {
  
  // تحقق من المنصة لمنع الـ Crash على غير الموبايل
  static bool get _isMobilePlatform {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  // === Common Methods ===
  static Future<void> start() async {
    if (!_isMobilePlatform) return;
    await ScreenGuardPlusPlatform.instance.start();
  }

  static Future<void> stop() async {
    if (!_isMobilePlatform) return;
    await ScreenGuardPlusPlatform.instance.stop();
  }

  static Future<void> addWatermark({
    required String text,
    required Color color,
    double size = 45.0,
  }) async {
    if (!_isMobilePlatform) return;

    // تحويل اللون لـ Hex
    String hexColor = '#${color.value.toRadixString(16).padLeft(8, '0')}';
    if (hexColor.length > 7) {
      hexColor = '#${hexColor.substring(hexColor.length - 6)}';
    }

    await ScreenGuardPlusPlatform.instance.addWatermark(
      text: text,
      hexColor: hexColor,
      size: size,
    );
  }

  static Future<void> removeWatermark() async {
    if (!_isMobilePlatform) return;
    await ScreenGuardPlusPlatform.instance.removeWatermark();
  }

  // === iOS Only Methods ===
  static Future<void> setShieldStyle(ShieldStyle style) async {
    if (kIsWeb || !Platform.isIOS) return;
    await ScreenGuardPlusPlatform.instance.setShieldStyle(style.name);
  }

  static Future<void> allowScreenshots(bool allow) async {
    if (kIsWeb || !Platform.isIOS) return;
    await ScreenGuardPlusPlatform.instance.allowScreenshots(allow);
  }

  static Future<void> forceShield(bool on) async {
    if (kIsWeb || !Platform.isIOS) return;
    await ScreenGuardPlusPlatform.instance.forceShield(on);
  }
}