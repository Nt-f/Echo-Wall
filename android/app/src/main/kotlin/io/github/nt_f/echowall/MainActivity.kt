package io.github.nt_f.echowall

import android.os.SystemClock
import android.view.KeyCharacterMap
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.view.inputmethod.InputMethodManager
import android.webkit.WebView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/* The Echo has no input method, so the app's own keyboard (lib/keyboard.dart) types into the WebView the way a USB
 * keyboard would: real key events into the platform view's android.webkit.WebView, found in the window's views.
 * Characters the virtual keyboard map lacks come back false, and Dart inserts them by script. */
class MainActivity : FlutterActivity() {
    private val map by lazy { KeyCharacterMap.load(KeyCharacterMap.VIRTUAL_KEYBOARD) }

    private fun findWeb(v: View?): WebView? {
        if (v is WebView) return v
        if (v is ViewGroup) for (i in 0 until v.childCount) findWeb(v.getChildAt(i))?.let { return it }
        return null
    }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "echo_screen/keys").setMethodCallHandler { call, result ->
            if (call.method == "isRound") {             // the Echo Spot's round glass (and debug.echoscreen.round=1 for screenshots)
                val prop = try {
                    Class.forName("android.os.SystemProperties").getMethod("get", String::class.java).invoke(null, "debug.echoscreen.round") as String
                } catch (e: Exception) { "" }
                result.success(resources.configuration.isScreenRound || prop == "1"); return@setMethodCallHandler
            }
            if (call.method == "prop") {                // debug.echoscreen.* for screenshots (an idle clock sooner)
                val v = try {
                    Class.forName("android.os.SystemProperties").getMethod("get", String::class.java).invoke(null, call.arguments as String) as String
                } catch (e: Exception) { "" }
                result.success(v); return@setMethodCallHandler
            }
            if (call.method == "keepOn") {              // hassmic's "always on": the screen never sleeps while the app shows
                if (call.arguments as Boolean) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                result.success(true); return@setMethodCallHandler
            }
            if (call.method == "hasInputMethod") {      // an Echo: none; elsewhere the device's own keyboard types
                val imm = getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager
                result.success(imm.enabledInputMethodList.isNotEmpty()); return@setMethodCallHandler
            }
            val web = findWeb(window.decorView)
            if (web == null) { result.success(false); return@setMethodCallHandler }
            when (call.method) {
                "text" -> {
                    val evs = map.getEvents((call.arguments as String).toCharArray())
                    if (evs == null) result.success(false) else { evs.forEach { web.dispatchKeyEvent(it) }; result.success(true) }
                }
                "key" -> {
                    val code = when (call.arguments as String) { "backspace" -> KeyEvent.KEYCODE_DEL; "enter" -> KeyEvent.KEYCODE_ENTER; "tab" -> KeyEvent.KEYCODE_TAB; else -> 0 }
                    val t = SystemClock.uptimeMillis()
                    web.dispatchKeyEvent(KeyEvent(t, t, KeyEvent.ACTION_DOWN, code, 0))
                    web.dispatchKeyEvent(KeyEvent(t, t, KeyEvent.ACTION_UP, code, 0))
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}
