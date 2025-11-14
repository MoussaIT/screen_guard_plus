package com.moussait.screen_guard_plus

import android.app.Activity
import android.view.WindowManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** ScreenGuardPlusPlugin */
class ScreenGuardPlusPlugin :
  FlutterPlugin,
  MethodChannel.MethodCallHandler,
  ActivityAware {

  private lateinit var channel: MethodChannel
  private var activity: Activity? = null

  // == FlutterPlugin ==
  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(binding.binaryMessenger, "screen_guard_plus")
    channel.setMethodCallHandler(this)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }

  // == ActivityAware (نحتاجه علشان نمسك الـwindow ونحط FLAG_SECURE) ==
  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activity = binding.activity
  }

  override fun onDetachedFromActivityForConfigChanges() { activity = null }
  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) { activity = binding.activity }
  override fun onDetachedFromActivity() { activity = null }

  // == MethodChannel ==
  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "start" -> {
        activity?.window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        result.success(null)
      }
      "stop" -> {
        activity?.window?.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        result.success(null)
      }
      "enableWebViewSafety" -> result.success(null) // مش مطلوب على أندرويد
      "disableWebViewSafety" -> result.success(null)
      else -> result.notImplemented()
    }
  }
}