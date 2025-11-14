import 'dart:async';
import 'package:flutter/services.dart';

class ScreenGuardPlus {
  static const MethodChannel _ch = MethodChannel('screen_guard_plus');

  static Future<void> start() => _ch.invokeMethod('start');
  static Future<void> stop() => _ch.invokeMethod('stop');

  static Future<void> enableWebViewSafety() => _ch.invokeMethod('enableWebViewSafety');
  static Future<void> disableWebViewSafety() => _ch.invokeMethod('disableWebViewSafety');
}
