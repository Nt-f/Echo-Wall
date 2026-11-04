package io.github.nt_f.echowall

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
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
    private var apps: MethodChannel? = null
    private var installs: BroadcastReceiver? = null

    private var nav: MethodChannel? = null

    /* hassmic's shell (its bar over every app, echo-dot-assist docs/screen-apps.md "The shell") starts this activity by
     * the SCREEN intent with an extra: "screen" (one of the screens, by name) or "home"; Dart shows it */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        tellNav(intent)
    }

    private fun tellNav(i: Intent?) {
        val ch = nav ?: return
        i?.getStringExtra("screen")?.let { ch.invokeMethod("screen", it); i.removeExtra("screen"); return }
        if (i?.getBooleanExtra("home", false) == true) { ch.invokeMethod("home", null); i.removeExtra("home") }
    }

    override fun onDestroy() {
        installs?.let { unregisterReceiver(it) }
        super.onDestroy()
    }

    /* The apps the owner installed beside this one (Launchable.kt): listed for Home's cards and started from them (hassmic's
     * shell has the bar back), and the list told again when one comes or goes */
    private fun appsChannel(engine: FlutterEngine) {
        val ch = MethodChannel(engine.dartExecutor.binaryMessenger, "echo_screen/apps")
        apps = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "list" -> {
                    val px = (64 * resources.displayMetrics.density).toInt()
                    result.success(Launchable.list(this).map { mapOf("package" to it.pkg, "label" to it.label, "icon" to Launchable.png(it.icon, px)) })
                }
                "launch" -> {
                    val pkg = call.arguments as String
                    val i = Launchable.intent(this, pkg)
                    if (i == null) result.success(false)
                    else { startActivity(i); result.success(true) }
                }
                else -> result.notImplemented()
            }
        }
        installs = object : BroadcastReceiver() {
            override fun onReceive(c: Context, i: Intent) { apps?.invokeMethod("changed", null) }
        }
        registerReceiver(installs, IntentFilter().apply {
            addAction(Intent.ACTION_PACKAGE_ADDED); addAction(Intent.ACTION_PACKAGE_REMOVED); addAction(Intent.ACTION_PACKAGE_CHANGED)
            addDataScheme("package")
        })
    }

    private fun findWeb(v: View?): WebView? {
        if (v is WebView) return v
        if (v is ViewGroup) for (i in 0 until v.childCount) findWeb(v.getChildAt(i))?.let { return it }
        return null
    }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        appsChannel(engine)
        nav = MethodChannel(engine.dartExecutor.binaryMessenger, "echo_screen/nav")
        tellNav(intent)
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
            if (call.method == "device") {              // what the Echo-Wall integration lists the device as
                // android_id: Android's id for this app (Android 8 on: per signing key and user; 7: the device's),
                // the same after a reinstall, unlike a file of the app's: lib/device.dart
                val aid = android.provider.Settings.Secure.getString(contentResolver, android.provider.Settings.Secure.ANDROID_ID) ?: ""
                result.success(mapOf("manufacturer" to android.os.Build.MANUFACTURER, "model" to android.os.Build.MODEL,
                    "product" to android.os.Build.PRODUCT, "android_id" to aid)); return@setMethodCallHandler
            }
            if (call.method == "hasInputMethod") {      // an Echo: none; elsewhere the device's own keyboard types
                // hassmic's shell's keyboard counts: it types into this app's pages too
                val imm = getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager
                result.success(imm.enabledInputMethodList.any { it.packageName != packageName }); return@setMethodCallHandler
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
