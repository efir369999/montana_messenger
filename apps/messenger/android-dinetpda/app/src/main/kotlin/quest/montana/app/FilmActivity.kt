package quest.montana.app

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.Rational
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.widget.FrameLayout
import android.widget.MediaController
import android.widget.VideoView
import java.io.File
import kotlin.math.abs

/**
 * A FILM WHOLE (iOS VideoPresenter, MontanaMedia 2997-3063: the platform's own player, modal): the platform's player on black —
 * its own controls for the play, the pause and the seek — the close top left, the fold and the share top right. THE FOLD IS
 * THE PLATFORM'S OWN PICTURE-IN-PICTURE (iOS allowsPictureInPicturePlayback): the film shrinks into a window of its own over
 * the chat and plays on there; the window's own expand brings it back, its close ends it. Leaving for home folds it the same
 * way (iOS canStartPictureInPictureAutomaticallyFromInline); a pull down closes it, as on the iPhone. One film at a time: a
 * new one takes the window's place (iOS VideoKeeper).
 */
class FilmActivity : Activity() {
    override fun attachBaseContext(base: android.content.Context) = super.attachBaseContext(pinnedText(AppLanguage.wrap(base)))
    companion object {
        private const val EXTRA_FILE = "montana.film.file"
        private const val EXTRA_URL = "montana.film.url"
        fun open(c: Context, f: File) {
            runCatching { c.startActivity(Intent(c, FilmActivity::class.java).putExtra(EXTRA_FILE, f.path).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
        }
        /** A media file at its address, the post's link (iOS VideoPresenter.present(remote:), MontanaMedia.swift:3026-3029): read
         * only now, at the person's own tap. */
        fun openRemote(c: Context, url: String) {
            runCatching { c.startActivity(Intent(c, FilmActivity::class.java).putExtra(EXTRA_URL, url).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
        }
    }

    private lateinit var video: VideoView
    private lateinit var chrome: View
    private var ctl: MediaController? = null
    private var film: File? = null
    private var link: String? = null
    private var shape = Rational(16, 9)
    private var folded = false
    private var x0 = 0f
    private var y0 = 0f
    private var pulling = false

    override fun onCreate(b: Bundle?) {
        super.onCreate(b)
        val root = FrameLayout(this).apply { setBackgroundColor(Color.BLACK) }
        video = VideoView(this)
        root.addView(video, FrameLayout.LayoutParams(MATCH, MATCH, Gravity.CENTER))
        fun mark(glyph: Int, label: Int, work: () -> Unit) = FrameLayout(this).apply {
            background = glassPlate(oval = true)
            contentDescription = getString(label)
            addView(icon(glyph, Color.WHITE, 22), FrameLayout.LayoutParams(dp(22), dp(22), Gravity.CENTER))
            pressable(work)
        }
        val bar = FrameLayout(this).apply {
            addView(mark(R.drawable.ic_close, R.string.film_close) { finish() }, FrameLayout.LayoutParams(dp(44), dp(44), Gravity.START).apply { leftMargin = dp(16) })
            addView(hstack {
                addView(mark(R.drawable.ic_pip, R.string.film_fold) { fold() }, lp(dp(44), dp(44)))
                gap(10)
                addView(mark(R.drawable.ic_share, R.string.share) { share() }, lp(dp(44), dp(44)))
            }, FrameLayout.LayoutParams(WRAP, WRAP, Gravity.END).apply { rightMargin = dp(16) })
        }
        chrome = bar
        root.addView(bar, FrameLayout.LayoutParams(MATCH, WRAP, Gravity.TOP).apply { topMargin = dp(8) })
        // the page runs under the system's bars; the marks stand under the status bar
        root.setOnApplyWindowInsetsListener { _, ins ->
            @Suppress("DEPRECATION") val top = ins.systemWindowInsetTop
            (bar.layoutParams as FrameLayout.LayoutParams).topMargin = top + dp(8)
            bar.requestLayout()
            ins
        }
        setContentView(root)
        play(intent)
    }

    override fun onNewIntent(i: Intent) {
        super.onNewIntent(i)
        setIntent(i)
        play(i)
    }

    private fun play(i: Intent?) {
        val url = i?.getStringExtra(EXTRA_URL)?.takeIf { it.startsWith("https://") || it.startsWith("http://") }
        val f = if (url != null) null else i?.getStringExtra(EXTRA_FILE)?.let { File(it) }?.takeIf { it.exists() } ?: return finish()
        film = f; link = url
        ctl = MediaController(this).also { it.setAnchorView(video); video.setMediaController(it) }
        video.setOnPreparedListener { mp ->
            if (mp.videoWidth > 0 && mp.videoHeight > 0) shape = fit(mp.videoWidth, mp.videoHeight)
            params()
            video.start()
        }
        video.setVideoURI(if (f != null) Uri.fromFile(f) else Uri.parse(url))
    }

    // the platform's window takes shapes between 1 to 2.39 and 2.39 to 1
    private fun fit(w: Int, h: Int): Rational {
        val r = w.toDouble() / h
        return when {
            r > 2.39 -> Rational(239, 100)
            r < 1 / 2.39 -> Rational(100, 239)
            else -> Rational(w, h)
        }
    }

    private fun params() {
        val b = PictureInPictureParams.Builder().setAspectRatio(shape)
        if (Build.VERSION.SDK_INT >= 31) b.setAutoEnterEnabled(true).setSeamlessResizeEnabled(true)
        runCatching { setPictureInPictureParams(b.build()) }
    }

    private fun fold() { runCatching { enterPictureInPictureMode(PictureInPictureParams.Builder().setAspectRatio(shape).build()) } }

    // home folds the playing film (from 31 the platform does it itself: setAutoEnterEnabled)
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (Build.VERSION.SDK_INT < 31 && video.isPlaying) fold()
    }

    override fun onPictureInPictureModeChanged(inPip: Boolean, cfg: Configuration) {
        super.onPictureInPictureModeChanged(inPip, cfg)
        folded = inPip
        chrome.visibility = if (inPip) View.GONE else View.VISIBLE
        if (inPip) ctl?.hide()
    }

    // the window's own close stops the folded film: nothing plays where nothing is seen
    override fun onStop() {
        super.onStop()
        if (folded) finish()
    }

    private fun share() {
        // a film at its address shares the address: there is no file of it here
        link?.let { u -> runCatching { startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, u), null)) }; return }
        val f = film ?: return
        val uri = Media.uri(this, f)
        val send = Intent(Intent.ACTION_SEND).setType(contentResolver.getType(uri) ?: "video/*")
            .putExtra(Intent.EXTRA_STREAM, uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        runCatching { startActivity(Intent.createChooser(send, null)) }
    }

    // A PULL DOWN CLOSES THE FILM (iOS: the player's own swipe-down): the picture follows the finger and goes past a third
    override fun dispatchTouchEvent(e: MotionEvent): Boolean {
        if (!folded) when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> { x0 = e.rawX; y0 = e.rawY; pulling = false }
            MotionEvent.ACTION_MOVE -> {
                val dy = e.rawY - y0
                if (!pulling && dy > dp(24) && dy > 2 * abs(e.rawX - x0)) { pulling = true; ctl?.hide() }
                if (pulling) { video.translationY = maxOf(0f, dy); return true }
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> if (pulling) {
                pulling = false
                if (e.rawY - y0 > dp(120)) finish() else video.animate().translationY(0f).setDuration(200).start()
                return true
            }
        }
        return super.dispatchTouchEvent(e)
    }
}
