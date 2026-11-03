package io.github.nt_f.echowall

import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import java.io.ByteArrayOutputStream

/* The apps the owner installed beside the screen app (a YouTube client, a music app; echo-dot-assist
 * docs/screen-apps.md "Other apps"): every launchable activity that is no system app's (Amazon's own, hassmic's kiosk and
 * home) and not this app.  Android 7 has no package visibility rules; <queries> in the manifest covers newer ones. */
object Launchable {
    data class App(val pkg: String, val label: String, val icon: Drawable)

    /* hassmic's own screen app (tools/kiosk): installed beside this one, but a screen app, not an app to open */
    private const val KIOSK = "io.github.gamer92000.echodotassist.kiosk"

    fun list(ctx: Context): List<App> {
        val pm = ctx.packageManager
        val main = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return pm.queryIntentActivities(main, 0)
            .map { it.activityInfo }
            .filter { it.packageName != ctx.packageName && it.packageName != KIOSK }
            .filter { it.applicationInfo.flags and (ApplicationInfo.FLAG_SYSTEM or ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) == 0 }
            .distinctBy { it.packageName }
            .map { App(it.packageName, it.loadLabel(pm).toString(), it.loadIcon(pm)) }
            .sortedBy { it.label.lowercase() }
    }

    /* the launcher's own way in: an app already running comes back where it was */
    fun intent(ctx: Context, pkg: String): Intent? =
        ctx.packageManager.getLaunchIntentForPackage(pkg)?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)

    fun png(d: Drawable, px: Int): ByteArray {
        val b = Bitmap.createBitmap(px, px, Bitmap.Config.ARGB_8888)
        val c = Canvas(b)
        d.setBounds(0, 0, px, px)
        d.draw(c)
        val o = ByteArrayOutputStream()
        b.compress(Bitmap.CompressFormat.PNG, 100, o)
        b.recycle()
        return o.toByteArray()
    }
}
