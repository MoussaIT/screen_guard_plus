import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'screen_guard_plus_platform_interface.dart';

class MethodChannelScreenGuardPlus extends ScreenGuardPlusPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('screen_guard_plus');

  @override
  Future<void> start() async {
    await methodChannel.invokeMethod('start');
  }

  @override
  Future<void> stop() async {
    await methodChannel.invokeMethod('stop');
  }

  @override
  Future<void> setShieldStyle(String styleName) async {
    await methodChannel.invokeMethod('setShieldStyle', {'style': styleName});
  }

  @override
  Future<void> forceShield(bool on) async {
    await methodChannel.invokeMethod('forceShield', {'on': on});
  }

  @override
  Future<String?> getPlatformVersion() async {
    return await methodChannel.invokeMethod<String>('getPlatformVersion');
  }
}