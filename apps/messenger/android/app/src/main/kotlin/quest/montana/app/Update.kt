package quest.montana.app

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.graphics.Color
import android.view.Gravity
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.os.Build
import android.util.Log
import android.widget.Toast
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

/**
 * A NEWER MONTANA ON THE SITE (the word of 07.10.2026 23:28: a person on Android hears of a new version from the system and
 * updates inside the app at once). No store stands between the site and the phone: scripts/lauterbourg.py lays every build
 * with latest.json naming the newest, the app reads that small file when it opens and on each box round, and a build above
 * its own rings one system notice per build. The notice's tap brings the APK into the app's own cache, holds it to the
 * digest latest.json names, and hands it to the system's installer, which itself refuses an APK not signed with the key
 * the installed app carries: the site cannot hand the phone a stranger's app.
 */
object Update {
    private const val SITE = "https://montana.quest/download/android/"
    private const val CHANNEL = "updates"
    private const val NOTICE = 7304
    private const val EVERY = 60 * 60 * 1000L
    const val ACTION = "quest.montana.app.UPDATE"

    class Site(val number: Long, val version: String, val file: String, val sha256: String, val size: Long,
               val notes: JSONArray = JSONArray(), val l10n: JSONObject? = null)

    @Volatile private var busy = false

    fun own(c: Context): Long = runCatching { c.packageManager.getPackageInfo(c.packageName, 0).longVersionCode }.getOrDefault(0L)

    /** The site's newest, asked without a word about this phone: the agent is the plain name, not the model. */
    fun newest(): Site? = runCatching {
        val conn = URL(SITE + "latest.json").openConnection() as HttpURLConnection
        conn.connectTimeout = 8000; conn.readTimeout = 8000
        conn.useCaches = false
        conn.setRequestProperty("User-Agent", "Montana")
        conn.setRequestProperty("Cache-Control", "no-cache")
        val text = if (conn.responseCode == 200) conn.inputStream.use { it.readBytes().toString(Charsets.UTF_8) } else null
        conn.disconnect()
        val j = JSONObject(text ?: return null)
        // only a plain file of the site's own folder is followed, and only a whole digest is held to
        val file = j.optString("file")
        val sha = j.optString("sha256")
        if (!Regex("[A-Za-z0-9._-]+[.]apk").matches(file) || !Regex("[0-9a-f]{64}").matches(sha)) return null
        // what changed, as the publishing road wrote it, and in the languages it brought (iOS MTClientRelease notes, l10n)
        Site(j.optLong("build"), j.optString("name").substringBefore(" "), file, sha, j.optLong("size"),
            j.optJSONArray("notes") ?: JSONArray(), j.optJSONObject("l"))
    }.getOrNull()

    /** Asked when the app comes to the front and on each box round, at most once an hour: a newer build rings once. */
    fun look(c: Context, force: Boolean = false) {
        val now = System.currentTimeMillis()
        // a build that never told the Montana room of itself asks at once (the room's row for the build now running)
        val roomTold = (Prefs.str("mt.release.row", "0").toLongOrNull() ?: 0L) >= own(c)
        if (!force && roomTold && now - (Prefs.str("mt.update.lookedAt", "0").toLongOrNull() ?: 0L) < EVERY) return
        Prefs.setStr("mt.update.lookedAt", now.toString())
        val s = newest() ?: return
        // THE ROOM HEARS THE BUILD (iOS MTReleaseState.deliver: release.build >= ownBuild): the newest and the one running alike, once
        if (own(c) <= s.number) {
            if (Book.appendRelease(s.number, s.version, s.notes, s.l10n, SITE)) Log.d("Montana", "release told build=" + s.number)
            Prefs.setStr("mt.release.row", s.number.toString())
        }
        if (s.number <= own(c)) { if (!busy) clear(c); return }
        if (Prefs.str("mt.update.told", "") == s.number.toString()) return
        Prefs.setStr("mt.update.told", s.number.toString())
        tell(c, s)
    }

    private fun channel(c: Context): NotificationManager? {
        val nm = c.getSystemService(NotificationManager::class.java) ?: return null
        nm.createNotificationChannel(NotificationChannel(CHANNEL, c.getString(R.string.update_channel), NotificationManager.IMPORTANCE_DEFAULT))
        return nm
    }

    private fun tell(c: Context, s: Site) {
        val nm = channel(c) ?: return
        val open = PendingIntent.getActivity(c, NOTICE, Intent(c, MainActivity::class.java).setAction(ACTION),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val n = Notification.Builder(c, CHANNEL)
            .setSmallIcon(R.drawable.ic_launcher_monochrome)
            .setContentTitle(c.getString(R.string.update_title))
            .setContentText(c.getString(R.string.update_text, s.version, s.number))
            .setAutoCancel(true)
            .setContentIntent(open)
            .addAction(Notification.Action.Builder(null, c.getString(R.string.update_now), open).build())
            .build()
        runCatching { nm.notify(NOTICE, n) }
    }

    private fun progress(c: Context, s: Site, pct: Int) {
        val nm = channel(c) ?: return
        val n = Notification.Builder(c, CHANNEL)
            .setSmallIcon(R.drawable.ic_launcher_monochrome)
            .setContentTitle(c.getString(R.string.update_loading, s.version, s.number))
            .setProgress(100, pct, pct == 0)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()
        runCatching { nm.notify(NOTICE, n) }
    }

    fun clear(c: Context) { c.getSystemService(NotificationManager::class.java)?.cancel(NOTICE) }

    /** The notice's tap (MainActivity): the newest is brought, held to its digest, and handed to the system's installer. */
    fun take(act: Activity) {
        if (busy) return
        busy = true
        val c = act.applicationContext
        Thread {
            var handed = false
            try {
                val s = newest()
                if (s == null) say(act, R.string.update_failed)
                else if (s.number <= own(c)) { clear(c); say(act, R.string.update_current) }
                else {
                    progress(c, s, 0)
                    val apk = bring(c, s)
                    if (apk == null) { clear(c); say(act, R.string.update_failed) }
                    else { hand(c, apk); handed = true }
                }
            } catch (e: Exception) {
                Log.w("Montana", "update: " + e.javaClass.simpleName)
                clear(c); say(act, R.string.update_failed)
            } finally { if (!handed) busy = false }
        }.start()
    }

    private fun say(act: Activity, what: Int) = act.runOnUiThread { Toast.makeText(act, what, Toast.LENGTH_LONG).show() }

    private fun bring(c: Context, s: Site): File? {
        val apk = File(File(c.cacheDir, "update").apply { mkdirs() }, "Montana.apk")
        val conn = URL(SITE + s.file).openConnection() as HttpURLConnection
        conn.connectTimeout = 15000; conn.readTimeout = 30000
        conn.setRequestProperty("User-Agent", "Montana")
        if (conn.responseCode != 200) { conn.disconnect(); return null }
        val total = if (0L < conn.contentLengthLong) conn.contentLengthLong else s.size
        val md = MessageDigest.getInstance("SHA-256")
        val input = conn.inputStream
        val out = apk.outputStream()
        var got = 0L
        var shown = 0
        try {
            val buf = ByteArray(64 * 1024)
            while (true) {
                val n = input.read(buf)
                if (n < 0) break
                md.update(buf, 0, n); out.write(buf, 0, n); got += n
                val pct = if (0L < total) (got * 100 / total).toInt() else 0
                if (shown + 5 <= pct) { shown = pct; progress(c, s, pct) }
            }
        } finally { out.close(); input.close(); conn.disconnect() }
        val sum = md.digest().joinToString("") { "%02x".format(it) }
        if (sum != s.sha256) { Log.w("Montana", "update: the digest is not the site's"); return null }
        return apk
    }

    private fun hand(c: Context, apk: File) {
        val pi = c.packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
        params.setAppPackageName(c.packageName)
        params.setSize(apk.length())
        // once the app has installed itself, the system lets it update itself after without asking again (Android 12)
        if (31 <= Build.VERSION.SDK_INT) params.setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
        val id = pi.createSession(params)
        val session = pi.openSession(id)
        try {
            val out = session.openWrite("Montana.apk", 0, apk.length())
            apk.inputStream().use { it.copyTo(out) }
            session.fsync(out)
            out.close()
            val back = PendingIntent.getBroadcast(c, id, Intent(c, UpdateDone::class.java),
                PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            session.commit(back.intentSender)
        } catch (e: Exception) {
            session.abandon()
            throw e
        } finally { session.close() }
    }

    /** The installer's word back (UpdateDone): its own question stands, or the round ends and may be asked again. */
    fun done(c: Context, status: Int, why: String?) {
        busy = false
        clear(c)
        if (status != PackageInstaller.STATUS_SUCCESS) {
            Log.w("Montana", "update: installer status " + status + " " + (why ?: ""))
            // not taken (refused, cancelled): the next look tells the same build again
            Prefs.remove("mt.update.told", "mt.update.lookedAt")
        }
    }

    /** The system's confirmation could not stand from the back: it waits as the notice's tap instead. */
    fun askLater(c: Context, ask: Intent) {
        val nm = channel(c) ?: return
        val open = PendingIntent.getActivity(c, NOTICE, ask, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val n = Notification.Builder(c, CHANNEL)
            .setSmallIcon(R.drawable.ic_launcher_monochrome)
            .setContentTitle(c.getString(R.string.update_title))
            .setContentText(c.getString(R.string.update_tap_install))
            .setAutoCancel(true)
            .setContentIntent(open)
            .build()
        runCatching { nm.notify(NOTICE, n) }
    }
}

/** The system installer's answer to Update.hand: its own confirmation (the first time also its question whether Montana may install apps), or the end. */
class UpdateDone : BroadcastReceiver() {
    override fun onReceive(c: Context, i: Intent) {
        val status = i.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
        if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
            @Suppress("DEPRECATION")
            val ask: Intent = i.getParcelableExtra(Intent.EXTRA_INTENT) ?: return
            ask.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            runCatching { c.startActivity(ask) }.onFailure { Update.askLater(c, ask) }
            return
        }
        Update.done(c, status, i.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE))
    }
}

/**
 * A NEW BUILD'S WORD, AS THE MONTANA ROOM KEEPS IT (iOS releaseInfoOf, releaseLanguages, ContentView.swift:4066-4085): the build, the
 * version, what changed, the site. What changed speaks the phone's language when the road brought that language, else as the road
 * wrote it; the row keeps every language, so a phone switched later reads its own.
 */
object Release {
    class Info(val build: Long, val version: String, val notes: List<String>, val url: String)

    fun of(t: String): Info? {
        if (!t.startsWith(Marks.RELEASE)) return null
        val o = runCatching { JSONObject(t.removePrefix(Marks.RELEASE)) }.getOrNull() ?: return null
        if (!o.has("b")) return null
        fun list(a: JSONArray?) = (0 until (a?.length() ?: 0)).mapNotNull { a!!.optString(it).trim().ifEmpty { null } }
        val own = list(o.optJSONObject("l")?.optJSONArray(java.util.Locale.getDefault().language))
        return Info(o.optLong("b"), o.optString("v"), own.ifEmpty { list(o.optJSONArray("n")) }, o.optString("u"))
    }

    /** Every language a row carries (null -- a row born before the translations rode). */
    fun languages(t: String): JSONObject? = runCatching { JSONObject(t.removePrefix(Marks.RELEASE)).optJSONObject("l") }.getOrNull()

    /** The scroll's head and the row's words in the list (iOS: «New version» and the build). */
    fun title(c: Context, i: Info) = c.getString(R.string.release_new) + " " + (if (i.version.isEmpty()) "" else i.version + " ") + "(" + i.build + ")"
    fun words(c: Context, i: Info) = c.getString(R.string.release_new) + " " + i.build

    /** The changes a rolled scroll shows; one change more is shown whole -- a fold that hides one line hides nothing. */
    private const val ROLLED = 2

    /**
     * THE ROOM'S LETTER IS A SCROLL (iOS MTReleaseScroll, MontanaBubble.swift:3595-3680): the app's glass icon and the version at its
     * head, the room's crowned name under them, a fading rule, the changes as points; past three the chevron unrolls the rest in
     * place; the one act is the path's door, «Update», which brings the newest from the site (Update.take). The plate is the room's
     * own: a dark fall from white 0.22 to 0.09 under the accent's rim.
     */
    fun body(c: Context, m: Msg, into: LinearLayout) {
        val i = of(m.text) ?: return
        into.background = android.graphics.drawable.GradientDrawable(android.graphics.drawable.GradientDrawable.Orientation.TOP_BOTTOM,
            intArrayOf(Color.argb(235, 56, 56, 56), Color.argb(235, 23, 23, 23))).apply { cornerRadius = c.dp(18).toFloat(); setStroke(c.dp(1), Color.WHITE) }
        into.setPadding(c.dp(14), c.dp(14), c.dp(14), c.dp(9))
        val col = c.vstack(Gravity.NO_GRAVITY) {}
        col.addView(c.hstack {
            gravity = Gravity.CENTER_VERTICAL
            addView(ImageView(c).apply {
                setImageResource(R.drawable.app_icon_glass_art); scaleType = ImageView.ScaleType.CENTER_CROP
                outlineProvider = object : android.view.ViewOutlineProvider() {
                    override fun getOutline(v: android.view.View, o: android.graphics.Outline) = o.setRoundRect(0, 0, v.width, v.height, v.dp(9).toFloat())
                }
                clipToOutline = true
            }, LinearLayout.LayoutParams(c.dp(40), c.dp(40)).apply { marginEnd = c.dp(10) })
            addView(c.vstack(Gravity.NO_GRAVITY) {
                addView(c.text(title(c, i), 17f, Color.WHITE, bold = true), LinearLayout.LayoutParams(WRAP, WRAP))   // USER-DATA: the build's version and number
                addView(c.text(Book.MONTANA_TITLE, 13f, Color.argb(173, 255, 255, 255)), LinearLayout.LayoutParams(WRAP, WRAP).apply { topMargin = c.dp(2) })   // a name, not a word
            }, LinearLayout.LayoutParams(0, WRAP, 1f))
        }, LinearLayout.LayoutParams(MATCH, WRAP))
        col.addView(android.view.View(c).apply {
            background = android.graphics.drawable.GradientDrawable(android.graphics.drawable.GradientDrawable.Orientation.LEFT_RIGHT,
                intArrayOf(Color.TRANSPARENT, Color.argb(153, 255, 255, 255), Color.TRANSPARENT))
        }, LinearLayout.LayoutParams(MATCH, c.dp(1)).apply { topMargin = c.dp(10); bottomMargin = c.dp(10) })
        val points = c.vstack(Gravity.NO_GRAVITY) {}
        val folds = i.notes.size > ROLLED + 1
        var open = false
        fun lay() {
            points.removeAllViews()
            for (n in if (folds && !open) i.notes.take(ROLLED) else i.notes) points.addView(c.hstack {
                gravity = Gravity.TOP
                addView(android.view.View(c).apply { background = android.graphics.drawable.GradientDrawable().apply { shape = android.graphics.drawable.GradientDrawable.OVAL; setColor(Color.WHITE) } },
                    LinearLayout.LayoutParams(c.dp(5), c.dp(5)).apply { topMargin = c.dp(8); marginEnd = c.dp(9) })
                addView(c.text(n, 15f, Color.argb(237, 255, 255, 255)), LinearLayout.LayoutParams(0, WRAP, 1f))   // USER-DATA: what changed, as the road wrote it
            }, LinearLayout.LayoutParams(MATCH, WRAP).apply { bottomMargin = c.dp(7) })
        }
        lay()
        col.addView(points, LinearLayout.LayoutParams(MATCH, WRAP))
        if (folds) {
            val chevron = c.icon(R.drawable.ic_chevron_down, Color.argb(204, 255, 255, 255), 14)
            col.addView(FrameLayout(c).apply {
                addView(chevron, FrameLayout.LayoutParams(c.dp(14), c.dp(14), Gravity.CENTER))
                contentDescription = c.getString(R.string.release_expand)
                pressable {
                    open = !open; lay(); chevron.rotation = if (open) 180f else 0f
                    contentDescription = c.getString(if (open) R.string.release_collapse else R.string.release_expand)
                }
            }, LinearLayout.LayoutParams(MATCH, c.dp(44)))
        }
        col.addView(PathDoor(c, c.getString(R.string.update_now)) {
            Log.d("Montana", "release tap build=" + i.build)
            (c as? Activity)?.let { Update.take(it) }
        }, LinearLayout.LayoutParams(MATCH, WRAP).apply { topMargin = c.dp(3) })
        // the scroll is as wide as its head: a column that wraps would measure each point once at its own width and keep that height
        into.addView(col, LinearLayout.LayoutParams(c.dp(250), WRAP))
    }
}
