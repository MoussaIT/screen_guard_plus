package com.moussait.screen_guard_plus

import android.app.Activity
import android.app.Application
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.TextView
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** ScreenGuardPlusPlugin */
class ScreenGuardPlusPlugin :
  FlutterPlugin,
  MethodChannel.MethodCallHandler,
  ActivityAware,
  Application.ActivityLifecycleCallbacks {

  private lateinit var channel: MethodChannel
  private var activity: Activity? = null
  private var application: Application? = null
  private var wantEnabled: Boolean = false   // هنعتبر الحماية on طول ما التطبيق شغال
  
  // متغير للووتر مارك عشان نعرف نشيله
  private var watermarkView: TextView? = null

  // == FlutterPlugin ==
  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(binding.binaryMessenger, "screen_guard_plus")
    channel.setMethodCallHandler(this)
    application = binding.applicationContext as? Application
    application?.registerActivityLifecycleCallbacks(this)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    application?.unregisterActivityLifecycleCallbacks(this)
    application = null
    channel.setMethodCallHandler(null)
  }

  // == ActivityAware ==
  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activity = binding.activity
    // طبّق العلم أول ما نمسك الأكتيفيتي
    if (wantEnabled) applyFlagSecure(true)
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    activity = binding.activity
    if (wantEnabled) applyFlagSecure(true)
  }

  override fun onDetachedFromActivityForConfigChanges() { activity = null }
  override fun onDetachedFromActivity() { activity = null }

  // == MethodChannel ==
  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "start" -> {
        wantEnabled = true
        applyFlagSecure(true)
        result.success(null)
      }
      "stop" -> {
        wantEnabled = false
        applyFlagSecure(false)
        removeWatermarkImpl() // نشيل الووتر مارك كمان مع الستوب
        result.success(null)
      }
      // === NEW: Watermark Methods ===
      "addWatermark" -> {
        val text = call.argument<String>("text") ?: ""
        val colorHex = call.argument<String>("color") ?: "#FF0000"
        val size = call.argument<Double>("size") ?: 45.0
        
        addWatermarkImpl(text, colorHex, size.toFloat())
        result.success(null)
      }
      "removeWatermark" -> {
        removeWatermarkImpl()
        result.success(null)
      }
      // تجاهل ميثودز الـ iOS عشان ميعملش Crash
      "setShieldStyle", "setPolicy", "forceShield" -> {
        result.success(null)
      }
      else -> result.notImplemented()
    }
  }

  // == Helpers ==
  private fun applyFlagSecure(enable: Boolean) {
    val act = activity ?: return
    act.runOnUiThread {
      val win = act.window ?: return@runOnUiThread
      if (enable) {
        win.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
      } else {
        win.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
      }
    }
  }

  // === NEW: Watermark Implementation ===
  private fun addWatermarkImpl(text: String, hexColor: String, fontSize: Float) {
    val act = activity ?: return
    
    act.runOnUiThread {
      // لو موجود قبل كدا شيله الأول
      removeWatermarkImpl()

      val textView = TextView(act).apply {
        this.text = text
        this.textSize = fontSize
        this.setTextColor(Color.parseColor(hexColor))
        this.alpha = 0.4f // الشفافية 0.4
        this.rotation = -45f // تدوير النص
        this.gravity = Gravity.CENTER
        
        // مهم جداً: نلغي التفاعل عشان التاتش يعدي للعناصر اللي تحته
        this.isClickable = false
        this.isFocusable = false

        layoutParams = FrameLayout.LayoutParams(
          ViewGroup.LayoutParams.MATCH_PARENT,
          ViewGroup.LayoutParams.MATCH_PARENT
        )
      }

      // إضافة الـ View للـ Root Content بتاع الأكتيفيتي
      val rootView = act.window.decorView.findViewById<ViewGroup>(android.R.id.content)
      rootView.addView(textView)
      
      watermarkView = textView
    }
  }

  private fun removeWatermarkImpl() {
    val act = activity ?: return
    act.runOnUiThread {
      watermarkView?.let { view ->
        (view.parent as? ViewGroup)?.removeView(view)
        watermarkView = null
      }
    }
  }

  // == ActivityLifecycleCallbacks: نضمن إعادة التطبيق بعد الرجوع للفوكَس ==
  override fun onActivityResumed(act: Activity) {
    // لو المستخدم مفعّل الحماية، نضمن العلم موجود على أي Activity حالية
    if (wantEnabled && act == activity) {
      applyFlagSecure(true)
    }
  }

  // باقي الكولباكس مش محتاجينها
  override fun onActivityCreated(a: Activity, b: Bundle?) {}
  override fun onActivityStarted(a: Activity) {}
  override fun onActivityPaused(a: Activity) {}
  override fun onActivityStopped(a: Activity) {}
  override fun onActivitySaveInstanceState(a: Activity, b: Bundle) {}
  override fun onActivityDestroyed(a: Activity) {
      // تنظيف الميموري لو الأكتيفيتي ماتت
      if (a == activity) {
          activity = null
      }
  }
}