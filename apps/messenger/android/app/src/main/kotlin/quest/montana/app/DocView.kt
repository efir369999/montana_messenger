package quest.montana.app

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import org.json.JSONObject
import java.io.File

// ─────────────────────────── a document, full screen (iOS DocPreview: the platform's viewer in a page of ours) ───────────────────────────

/** The name the person gave a document (the manifest's «n»), found by its file among the book's letters; else the file's own. */
fun docName(f: File): String {
    for (ch in Book.all()) for (m in ch.msgs) if (m.file == f.path) {
        val man = m.meta?.let { runCatching { JSONObject(it) }.getOrNull() } ?: Media.inline(m.text)
        man?.optString("n")?.takeIf { it.isNotBlank() }?.let { return it }   // USER-DATA: the document's name
    }
    return f.name
}

private val TEXT_KINDS = setOf("txt", "md", "csv", "json", "log", "xml", "yaml", "yml", "ini", "conf", "srt", "tsv")

/**
 * THE DOCUMENT PAGE (iOS DocPreview, the author's word 19.09: «the whole screen; out by the edge swipe or the platform's own
 * cross»): the bar — the close on the left, the document's own name as the title, the share on the right; under it the
 * document as the platform draws it here: a PDF page after page (PdfRenderer), words as words. What Android cannot draw by
 * itself stands as its name with «Open», which hands it to the apps of the phone. A file that is not here says so.
 */
fun openDocument(act: MainActivity, f: File) {
    val c: Context = act
    val name = docName(f)
    lateinit var close: () -> Unit
    val body = c.vstack(Gravity.CENTER_HORIZONTAL) { setPadding(dp(12), dp(8), dp(12), dp(24)) }
    fun say(words: String) = body.addView(c.text(words, 15f, MT.gray, center = true).apply { setPadding(c.dp(24), c.dp(60), c.dp(24), c.dp(16)) }, lp())
    val uri = Media.uri(c, f)
    fun handOn() {
        val view = Intent(Intent.ACTION_VIEW).setDataAndType(uri, c.contentResolver.getType(uri) ?: "*/*").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        runCatching { act.startActivity(Intent.createChooser(view, name)) }
    }
    val ext = name.substringAfterLast('.', f.extension).lowercase()
    when {
        !f.exists() -> say(c.getString(R.string.dv_missing))
        ext == "pdf" || f.extension.lowercase() == "pdf" -> {
            // the pages are drawn off the main thread, one by one, to the page's width
            act.background {
                val pages = mutableListOf<Bitmap>()
                runCatching {
                    ParcelFileDescriptor.open(f, ParcelFileDescriptor.MODE_READ_ONLY).use { fd ->
                        PdfRenderer(fd).use { pdf ->
                            val w = c.resources.displayMetrics.widthPixels
                            for (i in 0 until minOf(pdf.pageCount, 60)) pdf.openPage(i).use { p ->
                                val b = Bitmap.createBitmap(w, (w.toFloat() * p.height / p.width).toInt().coerceAtLeast(1), Bitmap.Config.ARGB_8888)
                                b.eraseColor(Color.WHITE)
                                p.render(b, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                                pages += b
                            }
                        }
                    }
                }
                act.onMain {
                    if (pages.isEmpty()) { say(name); body.addView(openButton(c) { handOn() }, lp(WRAP, WRAP)) }
                    pages.forEach { b ->
                        body.addView(ImageView(c).apply { setImageBitmap(b); adjustViewBounds = true }, lp().apply { bottomMargin = c.dp(8) })
                    }
                }
            }
        }
        ext in TEXT_KINDS && f.length() <= 2_000_000 ->
            body.addView(c.text(runCatching { f.readText() }.getOrDefault(""), 14f, Color.WHITE).apply { setTextIsSelectable(true) }, lp())   // USER-DATA: the document
        else -> {
            say(name)
            body.addView(openButton(c) { handOn() }, lp(WRAP, WRAP))
        }
    }
    val bar = FrameLayout(c).apply {
        setPadding(dp(8), 0, dp(8), 0)
        addView(c.icon(R.drawable.ic_close, Color.WHITE).apply { setPadding(dp(10), dp(10), dp(10), dp(10)); pressable { close() } },
            FrameLayout.LayoutParams(dp(44), dp(44), Gravity.CENTER_VERTICAL or Gravity.START))
        addView(c.text(name, 17f, Color.WHITE, bold = true, center = true).apply { singleLineEllipsis() },   // USER-DATA: the document's name
            FrameLayout.LayoutParams(WRAP, WRAP, Gravity.CENTER).apply { marginStart = dp(56); marginEnd = dp(56) })
        if (f.exists()) addView(c.icon(R.drawable.ic_share, Color.WHITE).apply {
            setPadding(dp(10), dp(10), dp(10), dp(10))
            pressable {
                val send = Intent(Intent.ACTION_SEND).setType(c.contentResolver.getType(uri) ?: "*/*")
                    .putExtra(Intent.EXTRA_STREAM, uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                act.startActivity(Intent.createChooser(send, name))
            }
        }, FrameLayout.LayoutParams(dp(44), dp(44), Gravity.CENTER_VERTICAL or Gravity.END))
    }
    val page = c.vstack(Gravity.NO_GRAVITY) {
        setBackgroundColor(Color.BLACK)
        isClickable = true
        addView(bar, lp(MATCH, dp(52)))
        addView(ScrollView(c).apply { addView(body) }, lp(MATCH, 0, 1f))
    }
    close = act.overlay(page)
}

/** «Open»: the document handed to the phone's apps that can read it. */
private fun openButton(c: Context, work: () -> Unit): View = c.text(c.getString(R.string.open_word), 17f, MT.gold, bold = true, center = true).apply {
    background = c.glassPlate()
    setPadding(c.dp(24), c.dp(12), c.dp(24), c.dp(12))
    pressable(work)
}
