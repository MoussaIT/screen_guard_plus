import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'screen_guard_plus_platform_interface.dart';

class MethodChannelScreenGuardPlus extends ScreenGuardPlusPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('screen_guard_plus');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }

  @override
  Future<void> start() async {
    await methodChannel.invokeMethod('start');
  }

  @override
  Future<void> stop() async {
    await methodChannel.invokeMethod('stop');
  }

  @override
  Future<void> addWatermark({
    required String text,
    required String hexColor,
    double size = 45.0,
  }) async {
    await methodChannel.invokeMethod('addWatermark', {
      'text': text,
      'color': hexColor,
      'size': size,
    });
  }

  @override
  Future<void> removeWatermark() async {
    await methodChannel.invokeMethod('removeWatermark');
  }

  @override
  Future<void> setShieldStyle(String styleName) async {
    await methodChannel.invokeMethod('setShieldStyle', {'style': styleName});
  }

  @override
  Future<void> allowScreenshots(bool allow) async {
    await methodChannel.invokeMethod('setPolicy', {'maskOnScreenshot': !allow});
  }

  @override
  Future<void> forceShield(bool on) async {
    await methodChannel.invokeMethod('forceShield', {'on': on});
  }
}