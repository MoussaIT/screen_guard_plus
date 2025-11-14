import 'package:flutter_test/flutter_test.dart';
import 'package:screen_guard_plus/screen_guard_plus.dart';
import 'package:screen_guard_plus/screen_guard_plus_platform_interface.dart';
import 'package:screen_guard_plus/screen_guard_plus_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockScreenGuardPlusPlatform
    with MockPlatformInterfaceMixin
    implements ScreenGuardPlusPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final ScreenGuardPlusPlatform initialPlatform = ScreenGuardPlusPlatform.instance;

  test('$MethodChannelScreenGuardPlus is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelScreenGuardPlus>());
  });

  test('getPlatformVersion', () async {
    ScreenGuardPlus screenGuardPlusPlugin = ScreenGuardPlus();
    MockScreenGuardPlusPlatform fakePlatform = MockScreenGuardPlusPlatform();
    ScreenGuardPlusPlatform.instance = fakePlatform;

    expect(await screenGuardPlusPlugin.getPlatformVersion(), '42');
  });
}
