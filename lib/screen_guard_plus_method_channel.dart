import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'screen_guard_plus_platform_interface.dart';

/// An implementation of [ScreenGuardPlusPlatform] that uses method channels.
class MethodChannelScreenGuardPlus extends ScreenGuardPlusPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('screen_guard_plus');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
