import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

/// ستايلات الشيلد المتاحة
enum ShieldStyle { blur, black }

/// ScreenGuardPlus — API مبسّط لإدارة الحماية
class ScreenGuardPlus {
  static const MethodChannel _ch = MethodChannel('screen_guard_plus');
  static const EventChannel _events = EventChannel('screen_guard_plus/events'); // اختياري لو أضفت الأحداث

  /// فعّل الحماية العامة.
  /// - iOS: يجهّز شيلد نافذة عليا + يراقب التسجيل/الإخراجات + لقطة الشاشة + App Switcher
  /// - Android: يضيف FLAG_SECURE على النافذة الحالية (داخل البلجن)
  static Future<void> start() => _ch.invokeMethod('start');

  /// أوقف الحماية (نادراً ما تحتاجها).
  static Future<void> stop() => _ch.invokeMethod('stop');

  /// اسمح/امنع لقطات الشاشة على iOS.
  /// - allow = true  => النظام هيسمح بلقطة (الشيلد مش هيغطي غير عند الأحداث).
  /// - allow = false => هنسوّد النتيجة وقت لقطة الشاشة (Blur يظهر لحظيًّا، ثم يعود للوضع الطبيعي).
  static Future<void> allowScreenshots(bool allow) {
    return _ch.invokeMethod('setPolicy', {
      'maskOnScreenshot': !allow,
    });
  }

  /// غيّر الستايل الافتراضي للشيلد لما "مفيش" تسجيل/إخراجات.
  /// (أثناء التسجيل نفرض Black، وأثناء لقطة الشاشة نفرض Blur مؤقتًا بغض النظر عن الافتراضي)
  static Future<void> setShieldStyle(ShieldStyle style) {
    return _ch.invokeMethod('setShieldStyle', {
      'style': style.name, // 'blur' | 'black'
    });
  }

  /// إجبار ظهور الشيلد طول ما الصفحة الحساسة مفتوحة.
  /// - لما on=true:
  ///   - لو في Recording/AirPlay/HDMI → نعرض الشيلد Black.
  ///   - لو مفيش → نعرض الشيلد بالستايل الافتراضي (اللي اخترته بـ setShieldStyle).
  /// - لما on=false: نرجع للوضع الطبيعي (إخفاء الشيلد مالم يكن هناك تسجيل/إخراجات).
  static Future<void> forceShield(bool on) {
    return _ch.invokeMethod('forceShield', {'on': on});
  }

  /// (اختياري) ستريم للأحداث لو فعّلتها في البلجن (screenshot/recording_start/stop).
  static Stream<String> get events =>
      _events.receiveBroadcastStream().map((e) => e?.toString() ?? '');

  // ======= مساعدات سريعة لاستخدامات شائعة =======

  /// وضع "Smart": تجربة مريحة للمستخدم — ما يظهرش الشيلد إلا وقت الخطر (تسجيل/إخراجات/خلفية).
  static Future<void> startSmart({ShieldStyle defaultStyle = ShieldStyle.blur}) async {
    await start();
    await setShieldStyle(defaultStyle);
    if (Platform.isIOS) {
      await allowScreenshots(false);
      // متخلّيش forceShield هنا
    }
  }

  /// وضع "Strict": مضمون — الشيلد دايمًا ظاهر، Black أثناء التسجيل وBlur للسكرين شوت.
  static Future<void> startStrict({ShieldStyle defaultStyle = ShieldStyle.blur}) async {
    await start();
    await setShieldStyle(defaultStyle);
    if (Platform.isIOS) {
      await allowScreenshots(false);
      await forceShield(true);
    }
  }

  /// أوقف الوضع الصارم وارجع للإعدادات الافتراضية (اسمح بلقطات الشاشة تاني إن حبيت).
  static Future<void> stopStrict({bool reAllowScreenshots = true}) async {
    if (Platform.isIOS) {
      await forceShield(false);
      if (reAllowScreenshots) {
        await allowScreenshots(true);
      }
    }
  }
}
