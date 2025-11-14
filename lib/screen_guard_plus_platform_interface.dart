import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'screen_guard_plus_method_channel.dart';

abstract class ScreenGuardPlusPlatform extends PlatformInterface {
  /// Constructs a ScreenGuardPlusPlatform.
  ScreenGuardPlusPlatform() : super(token: _token);

  static final Object _token = Object();

  static ScreenGuardPlusPlatform _instance = MethodChannelScreenGuardPlus();

  /// The default instance of [ScreenGuardPlusPlatform] to use.
  ///
  /// Defaults to [MethodChannelScreenGuardPlus].
  static ScreenGuardPlusPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [ScreenGuardPlusPlatform] when
  /// they register themselves.
  static set instance(ScreenGuardPlusPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
