package quest.montana.app

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.icu.util.Measure
import android.icu.util.MeasureUnit
import android.icu.text.MeasureFormat
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.net.Uri
import android.os.Build
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import java.util.Locale

// ─────────────────────────── a place as a letter (iOS MTPlaceLetter, MTLocationPicker) ───────────────────────────

/**
 * A PLACE AS A LETTER CARRIES IT (iOS MTPlaceLetter, [P2P-COMPAT]): the pin and the name, the street when there is one, the map
 * link — the same words every living build already reads as text; a build that knows the shape draws the place instead.
 */
object PlaceLetter {
    private const val PIN = "\uD83D\uDCCD"
    private const val ROAD = "https://maps.apple.com/?ll="

    class Place(val lat: Double, val lon: Double, val name: String?, val street: String?)

    /** The words a place leaves as (iOS words): «My location» stands where a place has no name of its own. */
    fun words(c: Context, lat: Double, lon: Double, name: String?, street: String?): String {
        val shown = name ?: c.getString(R.string.pl_mine)
        var w = PIN + " " + shown
        if (!street.isNullOrEmpty()) w += "\n" + street
        return w + "\n" + ROAD + String.format(Locale.US, "%s,%s", lat.toString(), lon.toString()) + "&q=" + Uri.encode(shown)
    }

    /** The same words read back (iOS parse): only the exact shape is a place; a letter that merely carries a map link stays words. */
    fun parse(c: Context, text: String): Place? {
        if (!text.startsWith(PIN) || text.length >= 600) return null
        val lines = text.split("\n")
        if (lines.size !in 2..3 || !lines.last().startsWith(ROAD)) return null
        val pair = lines.last().removePrefix(ROAD).substringBefore("&").split(",")
        if (pair.size != 2) return null
        val lat = pair[0].toDoubleOrNull() ?: return null
        val lon = pair[1].toDoubleOrNull() ?: return null
        if (kotlin.math.abs(lat) > 90 || kotlin.math.abs(lon) > 180) return null
        val shown = lines[0].removePrefix(PIN).trim()
        val street = if (lines.size == 3) lines[1].trim() else ""
        val own = shown.isEmpty() || shown == "My location" || shown == c.getString(R.string.pl_mine)
        return Place(lat, lon, if (own) null else shown, street.ifEmpty { null })
    }

    /** A length as a person reads it, by the platform's own measure (iOS lengthWords): metres, kilometres past a thousand. */
    fun length(metres: Float): String {
        val m = maxOf(1f, metres)
        val f = MeasureFormat.getInstance(Locale.getDefault(), MeasureFormat.FormatWidth.SHORT)
        return if (m < 1000f) f.format(Measure(Math.round(m), MeasureUnit.METER)) else f.format(Measure(Math.round(m / 1000f), MeasureUnit.KILOMETER))
    }
}

/**
 * THE PLACE OF A LETTER IN ITS BUBBLE (iOS MTPlaceMapPlate): the pin on its round, the place's name, its street and the spot. iOS
 * draws the map by the platform's own snapshotter; Android's system has no map of its own, and a map from a third party would
 * be told the spot — the plate stands without one, and a tap opens the spot in the maps the person chooses (geo:).
 */
fun Context.placePlate(p: PlaceLetter.Place, mine: Boolean): View = hstack {
    gravity = Gravity.CENTER_VERTICAL
    addView(FrameLayout(context).apply {
        background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(SysColor.red) }
        addView(icon(R.drawable.ic_compose_location, Color.WHITE, 20), FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER))
    }, lp(dp(40), dp(40)).apply { marginEnd = dp(10) })
    addView(vstack(Gravity.NO_GRAVITY) {
        addView(text(p.name ?: getString(R.string.location), 16f, BubbleStyle.text(mine), bold = true), lp(WRAP, WRAP))   // USER-DATA: the place's name
        p.street?.let { addView(text(it, 13f, BubbleStyle.text(mine)), lp(WRAP, WRAP)) }   // USER-DATA: the street
        addView(text(String.format(Locale.US, "%.5f, %.5f", p.lat, p.lon), 12f, BubbleStyle.time(mine)), lp(WRAP, WRAP))
    }, lp(WRAP, WRAP))
    pressable {
        val title = p.name ?: getString(R.string.location)
        val geo = Uri.parse(String.format(Locale.US, "geo:%f,%f?q=%f,%f", p.lat, p.lon, p.lat, p.lon) + "(" + Uri.encode(title) + ")")
        runCatching { startActivity(Intent(Intent.ACTION_VIEW, geo)) }
            .onFailure { android.widget.Toast.makeText(this@placePlate, R.string.pl_no_maps, android.widget.Toast.LENGTH_LONG).show() }
    }
}

/**
 * THE LOCATION PAGE (iOS MTLocationPicker): THIS spot — the pin on its round, «Send This Location», and the accuracy the phone has
 * right now; where the phone is not allowed to say, the same row says so and leads to where that is changed. The spot is the
 * platform's own locating (LocationManager); iOS's «or choose a place» asks the map's search for what stands around, and
 * Android's system has no such search of its own — the page sends this spot.
 */
fun placePage(act: MainActivity, onClose: () -> Unit, onPick: (String) -> Unit): View {
    val c: Context = act
    val lm = c.getSystemService(LocationManager::class.java)
    var best: Location? = null
    fun allowed() = c.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
        c.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
    // THE PHONE'S OWN SWITCH (iOS: location off for the whole phone reads as .denied, «disabled globally in Settings»): the app's
    // yes is worth nothing while it is off, and the row says so instead of locating forever
    fun systemOn() = lm != null && (if (28 <= Build.VERSION.SDK_INT) lm.isLocationEnabled else
        listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER).any { runCatching { lm.isProviderEnabled(it) }.getOrDefault(false) })
    fun off() = allowed() && !systemOn()
    val glyphRound = FrameLayout(c)
    val title = c.text("", 17f, Color.WHITE)
    val state = c.text("", 13f, MT.gray)
    val chevron = c.icon(R.drawable.ic_chevron_right, Color.rgb(89, 89, 89), 18)
    fun refused() = (!allowed() && Prefs.bool("locAsked", false)) || off()
    fun draw() {
        val no = refused()
        chevron.visibility = if (no) View.VISIBLE else View.GONE
        glyphRound.background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(if (no) Color.rgb(115, 115, 115) else SysColor.blue) }
        title.text = c.getString(if (no) R.string.pl_turn_on else R.string.pl_send)
        state.text = when {
            no -> c.getString(R.string.pl_no_access)
            best == null -> c.getString(R.string.pl_locating)
            else -> c.getString(R.string.pl_accurate, PlaceLetter.length(best!!.accuracy))
        }
    }
    val listener = LocationListener { loc -> if (best == null || loc.accuracy <= best!!.accuracy || loc.time - best!!.time > 10_000) { best = loc; draw() } }
    var watching = false
    fun watch() {
        if (watching || !allowed() || lm == null) return
        val providers = buildList {
            if (Build.VERSION.SDK_INT >= 31) add(LocationManager.FUSED_PROVIDER)
            add(LocationManager.GPS_PROVIDER); add(LocationManager.NETWORK_PROVIDER)
        }.filter { runCatching { lm.isProviderEnabled(it) }.getOrDefault(false) }
        // nothing to listen to while the phone's location is off: no latch — the beat asks again and catches the switch turned on
        if (providers.isEmpty()) return
        watching = true
        for (p in providers) runCatching {
            lm.getLastKnownLocation(p)?.takeIf { System.currentTimeMillis() - it.time < 120_000 }?.let { listener.onLocationChanged(it) }
            lm.requestLocationUpdates(p, 1000L, 0f, listener, Looper.getMainLooper())
        }
    }
    val row = c.hstack {
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(16), dp(10), dp(16), dp(10))
        minimumHeight = dp(56)
        glyphRound.addView(c.icon(R.drawable.ic_compose_location, Color.WHITE, 20), FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER))
        addView(glyphRound, lp(dp(40), dp(40)).apply { marginEnd = dp(14) })
        addView(c.vstack(Gravity.NO_GRAVITY) { addView(title, lp()); addView(state, lp()) }, lp(0, WRAP, 1f))
        addView(chevron, lp(dp(18), dp(18)).apply { marginStart = dp(6) })
        pressable {
            when {
                // where it is changed: the phone's own switch while that is off, the app's page when the app was refused
                refused() -> runCatching { act.startActivity(if (off()) Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)
                    else Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:" + c.packageName))) }
                !allowed() -> { Prefs.setBool("locAsked", true); act.requestPermissions(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION), 7) }
                else -> best?.let { b -> onPick(PlaceLetter.words(c, b.latitude, b.longitude, null, null)); onClose() }
            }
        }
    }
    // the platform's answer to the question, and a return from the system's settings, are read again while the page stands
    lateinit var beat: Runnable
    var live = false
    beat = Runnable { if (live) { if (allowed()) watch(); draw(); MainThread.later(1000, beat) } }
    val page = settingsPage(act, c.getString(R.string.location), onClose, cross = true) { section(null, null, row) }
    page.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(v: View) {
            live = true
            if (!allowed() && !Prefs.bool("locAsked", false)) {
                Prefs.setBool("locAsked", true)
                act.requestPermissions(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION), 7)
            }
            beat.run()
        }
        override fun onViewDetachedFromWindow(v: View) { live = false; watching = false; runCatching { lm?.removeUpdates(listener) } }
    })
    draw()
    return page
}
