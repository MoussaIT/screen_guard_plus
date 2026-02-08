import 'package:flutter_test/flutter_test.dart';
import 'package:screen_guard_plus/screen_guard_plus.dart';
import 'package:screen_guard_plus/screen_guard_plus_platform_interface.dart';
import 'package:screen_guard_plus/screen_guard_plus_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// 1. تحديث الـ Mock ليشمل كل الدوال الجديدة
class MockScreenGuardPlusPlatform
    with MockPlatformInterfaceMixin
    implements ScreenGuardPlusPlatform {

  // متغيرات للتحقق من الاستدعاء
  bool isStarted = false;
  bool isStopped = false;
  String? watermarkText;

  @override
  Future<String?> getPlatformVersion() => Future.value('42');

  @override
  Future<void> start() {
    isStarted = true;
    return Future.value();
  }

  @override
  Future<void> stop() {
    isStopped = true;
    return Future.value();
  }

  @override
  Future<void> addWatermark({required String text, required String hexColor, double size = 45.0}) {
    watermarkText = text;
    return Future.value();
  }

  @override
  Future<void> removeWatermark() => Future.value();

  @override
  Future<void> forceShield(bool on) => Future.value();

  @override
  Future<void> allowScreenshots(bool allow) => Future.value();

  @override
  Future<void> setShieldStyle(String styleName) => Future.value();
}

void main() {
  final ScreenGuardPlusPlatform initialPlatform = ScreenGuardPlusPlatform.instance;

  test('$MethodChannelScreenGuardPlus is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelScreenGuardPlus>());
  });

  test('start calls platform implementation', () async {
    MockScreenGuardPlusPlatform fakePlatform = MockScreenGuardPlusPlatform();
    ScreenGuardPlusPlatform.instance = fakePlatform;

    // Act: استدعاء الدالة الـ static
    await ScreenGuardPlus.start();

    // Assert: التأكد أن الدالة تم استدعاؤها في الـ Mock
    expect(fakePlatform.isStarted, true);
  });

  test('stop calls platform implementation', () async {
    MockScreenGuardPlusPlatform fakePlatform = MockScreenGuardPlusPlatform();
    ScreenGuardPlusPlatform.instance = fakePlatform;

    await ScreenGuardPlus.stop();

    expect(fakePlatform.isStopped, true);
  });
}