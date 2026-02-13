import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:no_screenshot/no_screenshot.dart'; // استيراد الباكيدج الجديدة
import 'screen_guard_plus_platform_interface.dart';

enum ShieldStyle { blur, black }

class ScreenGuardPlus {
  // تعريف متغير الـ NoScreenshot
  static final NoScreenshot _noScreenshot = NoScreenshot.instance;
  
  static bool get _isMobilePlatform {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  // === Common Methods ===
  static Future<void> start() async {
    if (!_isMobilePlatform) return;
    
    // 1. تشغيل الحماية الخاصة بنا (منع الفيديو في iOS + حماية أندرويد)
    await ScreenGuardPlusPlatform.instance.start();
    
    // 2. تشغيل منع السكرين شوت (باستخدام الباكيدج الخارجية)
    if (Platform.isIOS) {
      await _noScreenshot.screenshotOff();
    }
  }

  static Future<void> stop() async {
    if (!_isMobilePlatform) return;
    
    // 1. إيقاف حماية الفيديو والـ Secure Mode
    await ScreenGuardPlusPlatform.instance.stop();
    
    // 2. السماح بالسكرين شوت مرة أخرى
    if (Platform.isIOS) {
      await _noScreenshot.screenshotOn();
    }
  }

  // === iOS Only Methods ===
  static Future<void> setShieldStyle(ShieldStyle style) async {
    if (kIsWeb || !Platform.isIOS) return;
    await ScreenGuardPlusPlatform.instance.setShieldStyle(style.name);
  }

  static Future<void> forceShield(bool on) async {
    if (kIsWeb || !Platform.isIOS) return;
    await ScreenGuardPlusPlatform.instance.forceShield(on);
  }
}