import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'screen_guard_plus_method_channel.dart';

abstract class ScreenGuardPlusPlatform extends PlatformInterface {
  ScreenGuardPlusPlatform() : super(token: _token);

  static final Object _token = Object();
  static ScreenGuardPlusPlatform _instance = MethodChannelScreenGuardPlus();
  static ScreenGuardPlusPlatform get instance => _instance;

  static set instance(ScreenGuardPlusPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  // === Core ===
  Future<void> start() {
    throw UnimplementedError('start() has not been implemented.');
  }

  Future<void> stop() {
    throw UnimplementedError('stop() has not been implemented.');
  }

  // === iOS Specific ===
  Future<void> setShieldStyle(String styleName) {
    throw UnimplementedError('setShieldStyle() has not been implemented.');
  }

  Future<void> forceShield(bool on) {
    throw UnimplementedError('forceShield() has not been implemented.');
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}