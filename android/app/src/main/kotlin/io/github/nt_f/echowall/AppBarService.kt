package io.github.nt_f.echowall

import android.animation.ValueAnimator
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.text.TextUtils
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import java.net.HttpURLConnection
import java.net.URL

/* The app bar over an app the screen app started (echo-dot-assist docs/screen-apps.md "Other apps"): the Echo has no
 * navigation bar, so a strip along the middle of the top edge, pulled down (or tapped), drops a bar of the apps -
 * Home (this app) first - and a tap goes there.  Android's own status bar works the same way: a window of its own
 * along the edge, which here takes the top 18 dp of the middle 40 % from the app under it.
 *
 * In a process of its own (":bar", a few MB): the Echo Show 5 has 190 MB free with hassmic and this app, and a video
 * client wants most of it; if Android takes the Flutter process back, the strip and the bar stay, Home starts it
 * again.  For the same reason this process tells hassmic that the screen is lent (GET /kiosk/config/lent/<package>,
 * this app's uid): hassmic's own layer stays off the other app, and hassmic does not start the screen app over it.
 * MainActivity stops this service whenever it is in front again.
 *
 * Drawing over other apps needs SYSTEM_ALERT_WINDOW's app op: root's main.sh (screen_grants) allows it for the screen
 * app.  Without it there is no strip; Back in the other app still comes back here. */
class AppBarService : Service() {
    companion object {
        private const val EXTRA = "lent"
        fun start(ctx: Context, pkg: String) { ctx.startService(Intent(ctx, AppBarService::class.java).putExtra(EXTRA, pkg)) }
        fun stop(ctx: Context) { ctx.stopService(Intent(ctx, AppBarService::class.java)) }
        private const val POLL_MS = 20000L      // hassmic keeps a lent screen 90 s from the last poll
        private const val SHOWN_MS = 8000L
    }

    private lateinit var wm: WindowManager
    private val ui = Handler(Looper.getMainLooper())
    private var strip: View? = null
    private var bar: View? = null
    @Volatile private var lent = ""
    @Volatile private var running = false
    private val dp get() = resources.displayMetrics.density
    private val hide = Runnable { collapse() }

    override fun onBind(i: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        wm = getSystemService(WINDOW_SERVICE) as WindowManager
    }

    override fun onStartCommand(i: Intent?, flags: Int, id: Int): Int {
        i?.getStringExtra(EXTRA)?.let { lent = it }
        if (strip == null && Settings.canDrawOverlays(this)) addStrip()
        if (!running) { running = true; Thread(::poll, "lent").start() }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        running = false
        ui.removeCallbacks(hide)
        bar?.let { wm.removeView(it) }; bar = null
        strip?.let { wm.removeView(it) }; strip = null
        super.onDestroy()
    }

    private fun poll() {
        while (running) {
            val p = lent
            if (p.isNotEmpty()) try {
                val c = URL("http://127.0.0.1:28931/kiosk/config/lent/$p").openConnection() as HttpURLConnection
                c.connectTimeout = 2000; c.readTimeout = 3000
                c.inputStream.use { it.readBytes() }        // the config: this app's own, not looked at here
                c.disconnect()
            } catch (_: Exception) {}                       // hassmic restarting: the next look
            try { Thread.sleep(POLL_MS) } catch (_: InterruptedException) { return }
        }
    }

    @Suppress("DEPRECATION")
    private fun params(w: Int, h: Int, flags: Int) = WindowManager.LayoutParams(
        w, h,
        if (Build.VERSION.SDK_INT >= 26) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY else WindowManager.LayoutParams.TYPE_PHONE,
        flags or WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
        PixelFormat.TRANSLUCENT,
    ).apply { gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL }

    // ---------------------------------------------------------------- the strip

    /* the top edge's middle, drawn as nothing (no pill over the other apps, as none over the screen app's pages): a
     * swipe down opens the bar; a tap does nothing */
    private inner class Strip : View(this@AppBarService) {
        private var y0 = 0f
        private var opened = false
        override fun onTouchEvent(e: MotionEvent): Boolean {
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> { y0 = e.rawY; opened = false }
                MotionEvent.ACTION_MOVE -> if (!opened && e.rawY - y0 > 24 * dp) { opened = true; expand() }
            }
            return true
        }
    }

    private fun addStrip() {
        val s = Strip()
        wm.addView(s, params((resources.displayMetrics.widthPixels * .4f).toInt(), (18 * dp).toInt(), 0))
        strip = s
    }

    // ---------------------------------------------------------------- the bar

    private fun expand() {
        if (bar != null) { ui.removeCallbacks(hide); ui.postDelayed(hide, SHOWN_MS); return }
        val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        row.addView(item(getPackageName(), "Home", applicationInfo.loadIcon(packageManager), false) { home() })
        for (a in Launchable.list(this)) row.addView(item(a.pkg, a.label, a.icon, a.pkg == lent) { open(a.pkg) })
        val glass = HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            background = GradientDrawable().apply { setColor(0xe6202124.toInt()); cornerRadius = 22 * dp }
            setPadding((8 * dp).toInt(), (8 * dp).toInt(), (8 * dp).toInt(), (8 * dp).toInt())
            addView(row)
        }
        // put away by a touch anywhere else (ACTION_OUTSIDE) or a swipe up on it (seen before the icons take it)
        val root = object : FrameLayout(this) {
            private var y0 = 0f
            override fun onInterceptTouchEvent(e: MotionEvent): Boolean {
                when (e.actionMasked) {
                    MotionEvent.ACTION_DOWN -> y0 = e.rawY
                    MotionEvent.ACTION_MOVE -> if (y0 - e.rawY > 24 * dp) { collapse(); return true }
                }
                return false
            }
            override fun onTouchEvent(e: MotionEvent): Boolean {
                when (e.actionMasked) {
                    MotionEvent.ACTION_OUTSIDE -> { collapse(); return true }
                    MotionEvent.ACTION_DOWN -> { y0 = e.rawY; return true }
                    MotionEvent.ACTION_MOVE -> if (y0 - e.rawY > 24 * dp) { collapse(); return true }
                }
                return super.onTouchEvent(e)
            }
        }
        val m = (16 * dp).toInt()
        root.setPadding(m, (12 * dp).toInt(), m, 0)
        root.addView(glass, FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.CENTER_HORIZONTAL))
        wm.addView(root, params(WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH))
        bar = root
        // dropped from the edge
        root.translationY = -120 * dp
        ValueAnimator.ofFloat(-120 * dp, 0f).apply { duration = 180; addUpdateListener { root.translationY = it.animatedValue as Float }; start() }
        ui.postDelayed(hide, SHOWN_MS)
    }

    private fun collapse() {
        ui.removeCallbacks(hide)
        bar?.let { wm.removeView(it) }
        bar = null
    }

    private fun item(pkg: String, label: String, icon: android.graphics.drawable.Drawable, current: Boolean, go: () -> Unit): View {
        val w = (84 * dp).toInt()
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(0, (8 * dp).toInt(), 0, (6 * dp).toInt())
            if (current) background = GradientDrawable().apply { setColor(0x33ffffff); cornerRadius = 14 * dp }
            contentDescription = pkg
            addView(ImageView(context).apply { setImageDrawable(icon) }, LinearLayout.LayoutParams((48 * dp).toInt(), (48 * dp).toInt()))
            addView(TextView(context).apply {
                text = label; setTextColor(Color.WHITE); textSize = 12f; maxLines = 1; ellipsize = TextUtils.TruncateAt.END
                gravity = Gravity.CENTER_HORIZONTAL; setPadding((4 * dp).toInt(), (4 * dp).toInt(), (4 * dp).toInt(), 0)
            }, LinearLayout.LayoutParams(w, LinearLayout.LayoutParams.WRAP_CONTENT))
            setOnClickListener { go() }
            layoutParams = LinearLayout.LayoutParams(w, LinearLayout.LayoutParams.WRAP_CONTENT).apply { marginStart = (2 * dp).toInt(); marginEnd = (2 * dp).toInt() }
        }
    }

    private fun open(pkg: String) {
        collapse()
        val i = Launchable.intent(this, pkg) ?: return
        lent = pkg
        startActivity(i)
    }

    /* the screen app: brought back (singleTask), or started again if Android took it; it stops this service */
    private fun home() {
        collapse()
        startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT))
    }
}
