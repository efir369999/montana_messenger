package quest.montana.app

import android.app.AlertDialog
import android.content.Context
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.drawable.Drawable
import android.os.Build
import android.text.Editable
import android.text.TextWatcher
import android.util.Base64
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.AbsListView
import android.widget.BaseAdapter
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ListView
import android.widget.TextView
import org.json.JSONObject
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * THE EMOJI, CATEGORY BY CATEGORY (iOS emojiCategories, MontanaConversation.swift 36-104 at 2155): the icon a category wears on
 * the panel's strip and every glyph of it, in iOS's own order. One vocabulary for the panel and the reactions ([C-1]).
 */
val EMOJI_CATEGORIES: List<Pair<String, List<String>>> = listOf(
    "😀" to listOf(
        "😀","😃","😄","😁","😆","😅","🤣","😂","🙂","🙃","🫠","😉","😊","😇","🥰","😍",
        "🤩","😘","😗","☺️","😚","😙","🥲","😋","😛","😜","🤪","😝","🤑","🤗","🤭","🫢",
        "🤫","🤔","🫡","🤐","🤨","😐","😑","😶","🫥","😏","😒","🙄","😬","🤥","😌","😔",
        "😪","🤤","😴","😷","🤒","🤕","🤢","🤮","🤧","🥵","🥶","🥴","😵","🤯","🤠","🥳",
        "🥸","😎","🤓","🧐","😕","🫤","😟","🙁","☹️","😮","😯","😲","😳","🥺","🥹","😦",
        "😧","😨","😰","😥","😢","😭","😱","😖","😣","😞","😓","😩","😫","🥱","😤","😡",
        "😠","🤬","😈","👿","💀","💩","🤡","👻","👽","🤖"
    ),
    "👍" to listOf(
        "👍","👎","👌","🤌","🤏","✌️","🤞","🫰","🤟","🤘","🤙","👈","👉","👆","👇","☝️",
        "🫵","✋","🤚","🖐️","🖖","👋","🤝","🙏","✍️","💅","🤳","💪","🦾","👏","🙌","🫶",
        "👐","🤲","🫱","🫲","🫳","🫴","👊","✊","🤛","🤜","🦵","🦶","👂","🦻","👃","🧠",
        "🫀","🫁","🦷","🦴","👀","👁️","👅","👄","🫦"
    ),
    "❤️" to listOf(
        "❤️","🧡","💛","💚","💙","💜","🖤","🤍","🤎","💔","❣️","💕","💞","💓","💗","💖",
        "💘","💝","💟","♥️","💋","💌","💐","🌹","🌷","🌸","🌺","🌻","🌼","💮","🏵️","🌈",
        "✨","⭐","🌟","💫","⚡","🔥","💥","💯","🎉","🎊","🎁"
    ),
    "🐶" to listOf(
        "🐶","🐱","🐭","🐹","🐰","🦊","🐻","🐼","🐻‍❄️","🐨","🐯","🦁","🐮","🐷","🐸","🐵",
        "🙈","🙉","🙊","🐒","🐔","🐧","🐦","🐤","🐣","🦆","🦅","🦉","🦇","🐺","🐗","🐴",
        "🦄","🐝","🪲","🐛","🦋","🐌","🐞","🐜","🦗","🕷️","🦂","🐢","🐍","🦎","🐙","🦑",
        "🦐","🦀","🐡","🐠","🐟","🐬","🐳","🐋","🦈","🐊","🐅","🐆","🦓","🦍","🐘","🦛",
        "🐪","🐫","🦒","🦘","🐃","🐄","🐎","🐖","🐏","🐑","🐐","🦌","🐕","🐩","🐈","🐓",
        "🦃","🕊️","🐇","🐿️","🦔"
    ),
    "🍔" to listOf(
        "🍏","🍎","🍐","🍊","🍋","🍌","🍉","🍇","🍓","🫐","🍈","🍒","🍑","🥭","🍍","🥥",
        "🥝","🍅","🍆","🥑","🥦","🥬","🥒","🌶️","🫑","🌽","🥕","🫒","🧄","🧅","🥔","🍠",
        "🥐","🥯","🍞","🥖","🥨","🧀","🥚","🍳","🧈","🥞","🧇","🥓","🥩","🍗","🍖","🌭",
        "🍔","🍟","🍕","🥪","🌮","🌯","🫔","🥙","🧆","🥗","🍝","🍜","🍲","🍛","🍣","🍱",
        "🍤","🍙","🍚","🍘","🍥","🥟","🦪","🍦","🍰","🎂","🧁","🍫","🍬","🍭","🍮","🍯",
        "☕","🍵","🧃","🥤","🍺","🍻","🥂","🍷","🥃","🍸","🍹","🍾"
    ),
    "⚽" to listOf(
        "⚽","🏀","🏈","⚾","🥎","🎾","🏐","🏉","🥏","🎱","🪀","🏓","🏸","🏒","🏑","🥍",
        "🏏","🥅","⛳","🪁","🎣","🤿","🥊","🥋","🎽","🛹","🛼","🛷","⛸️","🥌","🎿","⛷️",
        "🏂","🏋️","🤼","🤸","⛹️","🤾","🏌️","🏇","🧘","🏄","🏊","🤽","🚣","🧗","🚴","🚵",
        "🏆","🥇","🥈","🥉","🏅","🎖️","🎗️","🎫","🎟️","🎪","🤹","🎭","🎨","🎬","🎤","🎧",
        "🎼","🎹","🥁","🎷","🎺","🎸","🪕","🎻","🎲","♟️","🎯","🎳","🎮","🎰","🧩"
    ),
    "🚗" to listOf(
        "🚗","🚕","🚙","🚌","🚎","🏎️","🚓","🚑","🚒","🚐","🛻","🚚","🚛","🚜","🛵","🏍️",
        "🛺","🚲","🛴","🚨","🚔","🚍","🚘","🚖","✈️","🛫","🛬","🛩️","💺","🚁","🚀","🛸",
        "🚉","🚊","🚝","🚄","🚅","🚈","🚂","🚆","🚇","🚢","⛴️","🚤","🛥️","⛵","🚧","⛽",
        "🗺️","🗿","🗽","🗼","🏰","🏯","🏟️","🎡","🎢","🎠","⛲","⛱️","🏖️","🏝️","🏜️","🌋",
        "⛰️","🏔️","🗻","🏕️","⛺","🏠","🏡","🏘️","🏢","🏬","🏣","🏤","🏥","🏦","🏨","🌃",
        "🌆","🌇","🌉","🌁"
    ),
    "💡" to listOf(
        "⌚","📱","💻","⌨️","🖥️","🖨️","🖱️","💽","💾","💿","📀","📷","📸","📹","🎥","📞",
        "☎️","📟","📠","📺","📻","🧭","⏰","⏱️","⌛","⏳","🔋","🔌","💡","🔦","🕯️","🧯",
        "💸","💵","💴","💶","💷","🪙","💰","💳","💎","⚖️","🧰","🔧","🔨","⚙️","🧲","🔫",
        "💣","🧨","🔪","🛡️","🚬","⚰️","🔮","🧿","🪬","💈","🔭","🔬","🩺","💊","💉","🩸",
        "🌡️","🧹","🧺","🧻","🚽","🚿","🛁","🧼","🪥","🔑","🗝️","🚪","🛋️","🛏️","🖼️","🎁",
        "🎈","🎀","🎊","🎉","📦","📫","✉️","📝","📚","📖","🔖","📌","📍","✂️","🖊️","📎"
    ),
    "🔣" to listOf(
        "❤️","💯","✅","❌","⭕","🚫","❗","❓","❕","❔","‼️","⁉️","💢","♨️","🔅","🔆",
        "✔️","☑️","🔘","⚪","⚫","🔴","🟠","🟡","🟢","🔵","🟣","🟤","🔺","🔻","🔸","🔹",
        "🔶","🔷","🔳","🔲","▪️","▫️","◾","◽","◼️","◻️","⬛","⬜","🟥","🟧","🟨","🟩",
        "🟦","🟪","🟫","🔈","🔉","🔊","🔇","📢","📣","🔔","🔕","➕","➖","➗","✖️","♾️",
        "💲","💱","™️","©️","®️","🔝","🔚","🔙","🔛","🔜","✳️","✴️","❇️","🔟","🆗",
        "🆕","🆒","🆓","🆙","🆖","🅰️","🅱️","🆎","🅾️","🔠","🔡","🔢","🔣","🔤"
    ),
)

/**
 * THE MOVING PICTURES THIS PHONE KEEPS (iOS MontanaGifBook, MontanaGif.swift 312-353 at 2155): the sticker book's own shape — a
 * list of names over the app's private files, newest first, a ceiling of sixty, one copy per picture (named by its own bytes,
 * so the same picture sent twice moves to the front instead of lying twice).
 */
object GifBook {
    private const val SHELF = "montana.gifs.mine"   // iOS MontanaGifBook.shelf
    private const val CEILING = 60                  // iOS MontanaGifBook.ceiling
    private fun dir(c: Context) = File(c.filesDir, "gifs").apply { mkdirs() }
    fun file(c: Context, name: String) = File(dir(c), name)
    fun names(c: Context): List<String> = Prefs.str(SHELF, "").split('\n').filter { it.isNotEmpty() && file(c, it).exists() }
    private fun keep(list: List<String>) = Prefs.setStr(SHELF, list.joinToString("\n"))
    /** The person forgotten: their moving pictures leave with them (Book.wipe, beside Stickers.wipe). */
    fun wipe(c: Context) = File(c.filesDir, "gifs").deleteRecursively()

    @Synchronized fun add(c: Context, bytes: ByteArray): String {
        val name = "gif_" + Wire.hex(Wire.sha(bytes)).take(16) + ".gif"
        val f = file(c, name)
        if (!f.exists()) f.writeBytes(bytes)
        val list = listOf(name) + names(c).filter { it != name }
        list.drop(CEILING).forEach { file(c, it).delete() }   // the oldest leaves with its file
        keep(list.take(CEILING))
        Log.d("Montana", "gif_book add n=" + minOf(list.size, CEILING) + " bytes=" + bytes.size)
        return name
    }
    @Synchronized fun forget(c: Context, name: String) { keep(names(c).filter { it != name }); file(c, name).delete() }
}

/**
 * THE SEARCH FOR MOVING PICTURES GOES THROUGH OUR OWN NODE (iOS MontanaGifSearch, MontanaGif.swift 355-526 at 2155; the author's
 * word 22.09, road B): the node holds the house's key and asks the house; the house learns the node and the word, never who
 * asked. The phone opens no road outside our own doors — the doors that announce the «gif» capability, waited for, not guessed.
 * An empty word is what is popular (23.09); the two shelves of the house — moving pictures and stickers — are one road, one
 * word apart; a set of the house is asked for by its own name.
 */
object GifSearch {
    class Found(val id: String, val w: Int, val h: Int)
    class Pack(val id: String, val title: String)
    /** The full picture's term (iOS fullTerm, 8 s): past it the light one of the tile leaves, so the row neither hangs nor vanishes. */
    private const val FULL_TERM_MS = 8_000L
    private val race = Executors.newCachedThreadPool()

    private fun host(door: String) = android.net.Uri.parse(door).host ?: "-"

    /** ONE QUESTION TO THE DOORS (iOS ask, [C-1]): what is asked differs by the words inside, never by the road. The refusal names
     * each door's answer (iOS 23.09, the critic: «no door» was written while a door had answered). */
    private fun ask(body: JSONObject): List<JSONObject> {
        val doors = Doors.waited("gif")
        val said = ArrayList<String>()
        for (door in doors) {
            val (code, text) = Wire.post(door, "/gif-search", body, 15_000)
            val items = if (code == 200 && text != null) runCatching { JSONObject(text).getJSONArray("items") }.getOrNull() else null
            if (items == null) { said.add(host(door) + "=" + code); continue }
            return (0 until items.length()).mapNotNull { items.optJSONObject(it) }
        }
        Log.d("Montana", "gif_search " + if (doors.isEmpty()) "no door with this capability" else "every door refused: " + said.joinToString(" "))
        return emptyList()
    }

    fun find(q: String = "", limit: Int = 30, kind: String = "gif", offset: Int = 0): List<Found> {
        val rows = ask(JSONObject().put("q", q.trim()).put("limit", limit).put("kind", kind).put("offset", offset))
        Log.d("Montana", "gif_search kind=" + kind + " at=" + offset + " found n=" + rows.size)
        return found(rows)
    }

    /** The sets the house keeps, a page at a time (iOS packs). */
    fun packs(limit: Int = 12, offset: Int = 0): List<Pack> =
        ask(JSONObject().put("kind", "packs").put("limit", limit).put("offset", offset)).mapNotNull { r ->
            val id = r.optString("pack")
            if (id.isEmpty() || !r.has("title")) null else Pack(id, r.optString("title"))
        }

    /** The pictures of one set, a page at a time (iOS inPack). */
    fun inPack(pack: String, limit: Int = 24, offset: Int = 0): List<Found> =
        found(ask(JSONObject().put("pack", pack).put("limit", limit).put("offset", offset)))

    private fun found(rows: List<JSONObject>) = rows.mapNotNull { r ->
        r.optString("id").takeIf { it.isNotEmpty() }?.let { Found(it, r.optInt("w", 1), r.optInt("h", 1)) }
    }

    /** The bytes of a picture through the same doors (iOS fetch): the light one fills a tile; the full one — three times the bytes —
     * only when a picture actually leaves. The road of a full one is written door by door (iOS 23.09, the critic). */
    fun fetch(f: Found, full: Boolean = false): ByteArray? {
        for (door in Doors.waited("gif")) {
            if (Thread.currentThread().isInterrupted) return null
            val t0 = System.currentTimeMillis()
            val (code, text) = Wire.post(door, "/gif-get", JSONObject().put("id", f.id).apply { if (full) put("full", true) }, 25_000)
            val bytes = if (code == 200 && text != null) runCatching {
                Base64.decode(JSONObject(text).optString("data"), Base64.DEFAULT)
            }.getOrNull()?.takeIf { it.isNotEmpty() } else null
            if (full) Log.d("Montana", "gif_get full at=" + host(door) + " code=" + code + " bytes=" + (bytes?.size ?: 0) + " ms=" + (System.currentTimeMillis() - t0))
            if (bytes != null) return bytes
        }
        return null
    }

    /** THE LETTER DOES NOT WAIT ON A ROAD WITHOUT A TERM (iOS fetchFull, 23.09): the full one within its term, else nothing. */
    fun fetchFull(f: Found): ByteArray? {
        val t0 = System.currentTimeMillis()
        val job = race.submit<ByteArray?> { fetch(f, full = true) }
        return try { job.get(FULL_TERM_MS, TimeUnit.MILLISECONDS) } catch (_: java.util.concurrent.TimeoutException) {
            job.cancel(true)
            Log.d("Montana", "gif_get full past its term of " + FULL_TERM_MS / 1000 + " s — the light one leaves ms=" + (System.currentTimeMillis() - t0))
            null
        } catch (_: Exception) { null }
    }
}

/**
 * THE PICTURES ALREADY SEEN ARE NOT ASKED FOR TWICE (iOS MontanaGifArt, MontanaGif.swift 528-560 at 2155): a tile's light picture
 * is kept as its file in the app's cache, the panel and the page show the same popular list, and a tile plays that file.
 */
object GifArt {
    private fun tile(c: Context, id: String): File {
        val safe = if (id.matches(Regex("[A-Za-z0-9_-]{1,80}"))) id else Wire.hex(Wire.sha(id.toByteArray())).take(32)
        return File(File(c.cacheDir, "gif").apply { mkdirs() }, "$safe.gif")
    }
    /** The light bytes a tile already brought down, if it has (the row at the tap wears them). */
    fun light(c: Context, f: GifSearch.Found): ByteArray? = tile(c, f.id).takeIf { it.isFile }?.readBytes()
    /** The light picture of a tile, as its file — asked of the node once. */
    fun art(c: Context, f: GifSearch.Found): File? {
        val u = tile(c, f.id)
        if (u.isFile) return u
        val d = GifSearch.fetch(f) ?: return null
        val tmp = File(u.path + ".part")
        return runCatching { tmp.writeBytes(d); tmp.renameTo(u); u }.getOrNull()?.takeIf { it.isFile }
    }
}

/**
 * A MOVING PICTURE OF MY BOOK LEAVES AS A FILE (iOS sendGifFile, MontanaConversation.swift 3807-3820 at 2155): the picture road
 * re-encodes to a still frame, so a GIF rides the document road, which touches no byte of it. The name says which of the two it
 * is: «stick_» — a sticker of the house, drawn bare on both sides; «gif_» — a moving picture in its own plate.
 */
fun sendGifFile(c: Context, ref: String, book: String) {
    val f = GifBook.file(c, book).takeIf { it.exists() } ?: return
    val mark = if (book.startsWith("stick_")) "stick_" else "gif_"
    Thread { Media.send(c, ref, Media.Picked(f.readBytes(), "doc", "gif", mark + UUID.randomUUID() + ".gif"), "") }.start()
}

/**
 * A MOVING PICTURE OF THE HOUSE STANDS IN THE CHAT AT THE TAP (iOS sendGifFound, MontanaConversation.swift 3822-3846 at 2155; the
 * author's word 23.09 «first into the chat, then let it load»): the row is born at once wearing the light picture the tile already
 * holds; the full one is brought down behind it, within its term, and takes the same file's place before a byte leaves. The book
 * keeps the full one. A tile never seen has no light picture: then the full one is waited for first, and with neither nothing leaves.
 */
fun sendGifFound(c: Context, ref: String, f: GifSearch.Found) {
    val name = "gif_" + UUID.randomUUID() + ".gif"
    Thread {
        val light = GifArt.light(c, f)
        Log.d("Montana", "gif_send row at the tap light=" + (light?.size ?: 0))
        if (light != null) {
            Media.send(c, ref, Media.Picked(light, "doc", "gif", name), "", swap = { GifSearch.fetchFull(f)?.also { GifBook.add(c, it) } })
            return@Thread
        }
        val full = GifSearch.fetchFull(f) ?: run { Log.d("Montana", "gif_send neither the full nor the light one is in hand — nothing leaves"); return@Thread }
        GifBook.add(c, full)
        Media.send(c, ref, Media.Picked(full, "doc", "gif", name), "")
    }.start()
}

/**
 * A STICKER OF THE HOUSE LEAVES AS THE MOVING PICTURE IT IS (iOS takeStick, MontanaBubble.swift 2947-2960 at 2155): the document
 * road under a name that says «sticker», so both sides draw it bare at a sticker's size; the full one within its term, else the
 * tile's light one.
 */
fun sendHouseSticker(c: Context, ref: String, f: GifSearch.Found) {
    Thread {
        val d = GifSearch.fetchFull(f) ?: GifArt.light(c, f)
            ?: run { Log.d("Montana", "gif_send sticker: neither the full nor the light one is in hand — nothing leaves"); return@Thread }
        Media.send(c, ref, Media.Picked(d, "doc", "gif", "stick_" + UUID.randomUUID() + ".gif"), "")
    }.start()
}

/**
 * A TILE THAT PLAYS ITS PICTURE OVER AND OVER (iOS MTGifLoop, MontanaGif.swift 255-310 at 2155): the platform's own animator reads
 * the file a frame at a time (ImageDecoder → AnimatedImageDrawable); nothing of ours decodes frames ahead. It plays while it stands
 * in a window and stops when it leaves; the decoding is off the screen's thread. Below API 28 the first frame stands still.
 */
class GifLoop(c: Context, fill: Boolean) : ImageView(c) {
    private var want: File? = null
    init { scaleType = if (fill) ScaleType.CENTER_CROP else ScaleType.FIT_CENTER; isClickable = false; isFocusable = false }

    fun show(f: File?) {
        if (f == want) return
        want = f
        (drawable as? android.graphics.drawable.Animatable)?.stop()
        setImageDrawable(null)
        f ?: return
        Picker.decoder.execute {
            val d = decode(f)
            post { if (want == f && d != null) { setImageDrawable(d); if (isAttachedToWindow) (d as? android.graphics.drawable.Animatable)?.start() } }
        }
    }

    private fun decode(f: File): Drawable? = runCatching {
        if (Build.VERSION.SDK_INT >= 28) {
            val d = android.graphics.ImageDecoder.decodeDrawable(android.graphics.ImageDecoder.createSource(f))
            (d as? android.graphics.drawable.AnimatedImageDrawable)?.repeatCount = android.graphics.drawable.AnimatedImageDrawable.REPEAT_INFINITE
            d
        } else BitmapFactory.decodeFile(f.path)?.let { android.graphics.drawable.BitmapDrawable(resources, it) }
    }.getOrNull()

    override fun onAttachedToWindow() { super.onAttachedToWindow(); (drawable as? android.graphics.drawable.Animatable)?.start() }
    override fun onDetachedFromWindow() { (drawable as? android.graphics.drawable.Animatable)?.stop(); super.onDetachedFromWindow() }
}

/**
 * THE FIELD'S OWN PANEL (iOS EmojiInputPanel, MontanaBubble.swift 2651-3098 at 2155; MTPanelSwitch.swift; the author's words 22.09,
 * 23.09, 24.09): three tabs — GIF, stickers, emoji — each with the same line at the top (the search and the arrow), and at the bottom,
 * where the thumb is, the switch: one glass pill with the three words, the chosen one on a lens of its own, and the settings glass
 * beside it. No ground: the chat's own ground shows through.
 *
 * Two places, one panel ([C-1]): in the keyboard's place under the field (`expanded` false) its search line is the field's picture
 * and a touch opens the page on that tab with the search awake; on the PAGE over the whole screen (`expanded` true, iOS MTPickerPage)
 * the line types, and the arrow points down and gives the screen back.
 *
 * Android cannot make a panel the field's own input view: the keyboard's place is a view under the field, the same height the
 * keyboard last had (Conversation.kt). A picture that leaves from the page closes the page (iOS MTPickerPage onClose).
 */
class Picker(
    private val act: MainActivity,
    private val ref: String?,
    private val expanded: Boolean,
    private val startTab: Int,
    private val focusSearch: Boolean,
    private val onEmoji: (String) -> Unit,
    private val onSent: () -> Unit,
    private val onLift: (tab: Int, search: Boolean) -> Unit,
    private val onSettings: () -> Unit,
) {
    companion object {
        const val EMOJI = 0
        const val STICKERS = 1
        const val GIF = 2
        /** One decoder for every tile's frames, and three roads for the tiles' light pictures — the panel never floods the node. */
        val decoder = Executors.newSingleThreadExecutor()
        private val tiles = Executors.newFixedThreadPool(3)
        private val names = HashMap<String, String>()
        /** The platform's own name of a glyph holds the word (iOS named: every scalar's name, joined — «face with tears of joy»). */
        fun named(e: String, q: String): Boolean = synchronized(names) {
            names.getOrPut(e) {
                val out = StringBuilder()
                var i = 0
                while (i < e.length) { val cp = e.codePointAt(i); Character.getName(cp)?.let { out.append(it.lowercase()).append(' ') }; i += Character.charCount(cp) }
                out.toString()
            }
        }.contains(q)
    }

    private val c: Context = act
    var tab = startTab
        private set
    private val body = FrameLayout(c)
    private val switchWords = HashMap<Int, TextView>()
    private val tabViews = HashMap<Int, View>()
    private var searchWoke = false
    val view: LinearLayout = c.vstack(Gravity.NO_GRAVITY) {
        addView(body, lp(MATCH, 0, 1f))
        addView(switchRow(), lp(MATCH, WRAP).apply { topMargin = dp(4); bottomMargin = dp(8) })
    }

    /** The tab the switch shows; each tab is built once and keeps its scroll and its word while the panel lives. */
    fun show(t: Int) {
        tab = t
        body.removeAllViews()
        body.addView(tabViews.getOrPut(t) { when (t) { EMOJI -> emojiTab(); STICKERS -> stickerTab(); else -> gifTab() } }, FrameLayout.LayoutParams(MATCH, MATCH))
        for ((k, w) in switchWords) {
            val on = k == t
            w.setTypeface(null, if (on) android.graphics.Typeface.BOLD else android.graphics.Typeface.NORMAL)
            w.setTextColor(if (on) Color.WHITE else Color.argb(166, 255, 255, 255))
            w.background = if (on) c.rounded(Color.argb(41, 255, 255, 255), 18) else null
        }
    }

    // ── the switch (iOS MTPanelSwitch): GIF, stickers, emoji — the example's order — and the settings glass ──

    private fun switchRow(): View = c.hstack {
        gravity = Gravity.CENTER
        addView(c.hstack {
            background = c.glassPlate()
            setPadding(dp(4), dp(4), dp(4), dp(4))
            for ((t, label) in listOf(GIF to R.string.picker_gif, STICKERS to R.string.stickers, EMOJI to R.string.emoji)) {
                addView(c.text(c.getString(label), 15f, Color.WHITE, center = true).apply {
                    gravity = Gravity.CENTER
                    setPadding(dp(14), 0, dp(14), 0)
                    switchWords[t] = this
                    pressable { show(t) }
                }, lp(WRAP, dp(36)).apply { if (t != GIF) marginStart = dp(2) })
            }
        }, lp(WRAP, WRAP))
        addView(FrameLayout(c).apply {
            background = c.glassPlate(oval = true)
            contentDescription = c.getString(R.string.settings)
            addView(c.icon(R.drawable.ic_settings, Color.argb(217, 255, 255, 255), 20), FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER))
            pressable { onSettings() }
        }, lp(dp(44), dp(44)).apply { marginStart = dp(10) })
    }

    // ── the line at the top of every tab (iOS searchLine + liftArrow) ──

    private fun searchLine(tabIndex: Int, hint: Int, onChange: (String) -> Unit, onSubmit: (String) -> Unit): View = c.hstack {
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(12), dp(8), dp(4), 0)
        val field = EditText(c).apply {
            this.hint = c.getString(hint)
            setHintTextColor(Color.argb(153, 235, 235, 245)); setTextColor(Color.WHITE)
            textSize = 17f
            isSingleLine = true
            imeOptions = EditorInfo.IME_ACTION_SEARCH
            background = c.rounded(Color.argb(61, 118, 118, 128), 10)
            setPadding(dp(8), 0, dp(8), 0)
            compoundDrawablePadding = dp(6)
            c.getDrawable(R.drawable.ic_search)?.mutate()?.let { g ->
                g.setTint(Color.argb(153, 235, 235, 245)); g.setBounds(0, 0, dp(18), dp(18))
                setCompoundDrawablesRelative(g, null, null, null)
            }
            contentDescription = this.hint
        }
        if (expanded) {
            field.addTextChangedListener(object : TextWatcher {
                override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
                override fun onTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
                override fun afterTextChanged(s: Editable?) { onChange(s?.toString().orEmpty()) }
            })
            field.setOnEditorActionListener { v, action, _ ->
                if (action != EditorInfo.IME_ACTION_SEARCH) return@setOnEditorActionListener false
                onSubmit(v.text.toString())
                c.getSystemService(InputMethodManager::class.java).hideSoftInputFromWindow(v.windowToken, 0)   // the word is asked; the answer is in view
                true
            }
            // ASKED TO WAKE, IT TAKES THE KEYS ONCE, the moment it stands in a window (iOS wakeWhenShown, tried three times)
            if (focusSearch && !searchWoke && tabIndex == startTab) {
                searchWoke = true
                fun wake(tries: Int) {
                    field.postDelayed({
                        if (field.requestFocus()) c.getSystemService(InputMethodManager::class.java).showSoftInput(field, 0)
                        else if (tries > 1) wake(tries - 1)
                    }, if (tries == 3) 0L else 330L)
                }
                field.post { wake(3) }
            }
        } else {
            // STILL, IT IS ITS OWN PICTURE: a touch opens the page on this tab with the search awake (iOS onLift(.search true))
            field.isFocusable = false; field.isFocusableInTouchMode = false; field.isCursorVisible = false
            field.setOnClickListener { onLift(tabIndex, true) }
        }
        addView(field, lp(0, dp(36), 1f))
        // THE ARROW BESIDE THE LINE (iOS liftArrow): up opens the choosing as a page; down, on the page, gives the screen back
        addView(FrameLayout(c).apply {
            background = c.glassPlate(oval = true)
            contentDescription = c.getString(if (expanded) R.string.compose_fold else R.string.compose_open)
            addView(c.icon(if (expanded) R.drawable.ic_chevron_down else R.drawable.ic_chevron_up, Color.argb(217, 255, 255, 255), 18),
                FrameLayout.LayoutParams(dp(18), dp(18), Gravity.CENTER))
            pressable { onLift(tab, false) }
        }, lp(dp(44), dp(44)).apply { marginStart = dp(2) })
    }

    /** The house is named where its pictures are shown (iOS MTGiphyMark): the house's own condition for the search. */
    private fun giphyMark(): View = c.text(c.getString(R.string.powered_by_giphy), 10f, Color.argb(115, 255, 255, 255), bold = true, center = true)
        .apply { setPadding(0, dp(5), 0, dp(5)) }

    // ── the rows of a tab: one list owner for all three ([C-1]) — the platform's ListView keeps only the rows on screen ──

    private abstract class Row(val type: Int) { abstract fun make(c: Context, old: View?): View }

    private inner class Shelf : BaseAdapter() {
        var rows: List<Row> = emptyList()
            set(v) { field = v; notifyDataSetChanged() }
        var nearEnd: () -> Unit = {}
        var shown: (Int) -> Unit = {}
        override fun getCount() = rows.size
        override fun getItem(p: Int): Any = rows[p]
        override fun getItemId(p: Int) = p.toLong()
        override fun getViewTypeCount() = 8
        override fun getItemViewType(p: Int) = rows[p].type
        override fun areAllItemsEnabled() = false
        override fun isEnabled(p: Int) = false
        override fun getView(p: Int, old: View?, parent: ViewGroup): View {
            // THE FEED NEVER STOPS (iOS 23.09): the rows near the end ask for what comes after them
            if (rows.size - 3 <= p) parent.post { nearEnd() }
            shown(p)
            return rows[p].make(c, old)
        }
    }

    private fun shelfList(shelf: Shelf): ListView = ListView(c).apply {
        adapter = shelf
        divider = null; dividerHeight = 0
        selector = android.graphics.drawable.ColorDrawable(Color.TRANSPARENT)
        isVerticalScrollBarEnabled = false
        overScrollMode = View.OVER_SCROLL_NEVER
        clipToPadding = false
    }

    private class Header(val text: String, val size: Float, val color: Int, val top: Int) : Row(0) {
        override fun make(c: Context, old: View?): View = ((old as? TextView) ?: c.text("", size, color, bold = true)).apply {
            this.text = this@Header.text   // USER-DATA: a set's own name, as its house wrote it
            textSize = size; setTextColor(color)
            setPadding(c.dp(16), c.dp(top), c.dp(16), c.dp(6))
        }
    }

    private class Divider : Row(1) {
        override fun make(c: Context, old: View?): View = old ?: FrameLayout(c).apply {
            addView(View(c).apply { setBackgroundColor(Color.argb(26, 255, 255, 255)) }, FrameLayout.LayoutParams(MATCH, 1, Gravity.CENTER_VERTICAL))
            layoutParams = AbsListView.LayoutParams(MATCH, c.dp(24))
        }
    }

    /** A row of equal cells, each made by its own owner; a recycled row of another width of cells is made anew. */
    private class Cells(type: Int, val cols: Int, val rowDp: Int, val gapDp: Int, val sideDp: Int, val cells: List<(FrameLayout) -> Unit>) : Row(type) {
        override fun make(c: Context, old: View?): View {
            val row = (old as? LinearLayout)?.takeIf { it.tag == cols } ?: LinearLayout(c).apply {
                tag = cols
                orientation = LinearLayout.HORIZONTAL
                for (i in 0 until cols) addView(FrameLayout(c), LinearLayout.LayoutParams(0, c.dp(rowDp), 1f).apply { if (i > 0) marginStart = c.dp(gapDp) })
            }
            row.setPadding(c.dp(sideDp), c.dp(gapDp / 2), c.dp(sideDp), c.dp(gapDp / 2))
            for (i in 0 until cols) {
                val cell = row.getChildAt(i) as FrameLayout
                val fill = cells.getOrNull(i)
                cell.visibility = if (fill == null) View.INVISIBLE else View.VISIBLE
                if (fill != null) fill(cell)
            }
            return row
        }
    }

    private class Holder(val view: View) : Row(5) {
        override fun make(c: Context, old: View?): View = view
    }

    // ── a cell's faces ──

    private fun loopIn(cell: FrameLayout, fill: Boolean): GifLoop {
        (cell.getChildAt(0) as? GifLoop)?.let { return it }
        cell.removeAllViews()
        return GifLoop(c, fill).also { cell.addView(it, FrameLayout.LayoutParams(MATCH, MATCH)) }
    }

    private fun stillIn(cell: FrameLayout): ImageView {
        (cell.getChildAt(0) as? ImageView)?.takeIf { it !is GifLoop }?.let { return it }
        cell.removeAllViews()
        return ImageView(c).apply { scaleType = ImageView.ScaleType.FIT_CENTER }.also { cell.addView(it, FrameLayout.LayoutParams(MATCH, MATCH)) }
    }

    private fun bindTap(cell: FrameLayout, onTap: () -> Unit, onHold: (() -> Unit)?) {
        cell.pressable(onTap)
        if (onHold != null) cell.setOnLongClickListener { onHold(); true } else { cell.setOnLongClickListener(null); cell.isLongClickable = false }
    }

    private val art = HashMap<String, File>()
    private val asking = HashSet<String>()
    /** A tile of the house: its light picture once brought, else asked of the node — once, on three roads. */
    private fun houseCell(cell: FrameLayout, f: GifSearch.Found, fill: Boolean, onTap: () -> Unit) {
        val loop = loopIn(cell, fill)
        cell.tag = f.id
        loop.show(art[f.id])
        if (art[f.id] == null && asking.add(f.id)) tiles.execute {
            val file = GifArt.art(c, f)
            act.onMain {
                asking.remove(f.id)
                if (file != null) { art[f.id] = file; if (cell.tag == f.id) loop.show(file) }
                else Log.d("Montana", "gif_get tile code=none id=" + f.id.take(6))
            }
        }
        bindTap(cell, onTap, null)
    }

    /** A picture leaves into this chat and the page gives the screen back; a room that keeps words only says «not yet». */
    private fun send(work: (String) -> Unit) {
        val r = ref ?: run { android.widget.Toast.makeText(c, R.string.compose_not_yet, android.widget.Toast.LENGTH_SHORT).show(); return }
        work(r)
        onSent()
    }

    private fun confirmDelete(onYes: () -> Unit) {
        AlertDialog.Builder(c).setMessage(R.string.sticker_delete_q)
            .setPositiveButton(R.string.delete) { _, _ -> onYes() }
            .setNegativeButton(R.string.cancel, null).show()
    }

    // ── EMOJI (iOS emoji): the same line at the top as the other two tabs; the categories under it with the strip on glass ──

    private var emojiQuery = ""

    private fun emojiTab(): View {
        val shelf = Shelf()
        val list = shelfList(shelf)
        val heads = ArrayList<Int>()
        val strip = c.hstack {
            background = c.glassPlate()
            setPadding(dp(4), dp(4), dp(4), dp(4))
        }
        val stripWords = ArrayList<TextView>()
        fun mark(active: Int) = stripWords.forEachIndexed { i, w -> w.background = if (i == active) c.rounded(Color.argb(41, 255, 255, 255), 18) else null }
        EMOJI_CATEGORIES.forEachIndexed { i, (icon, _) ->
            strip.addView(c.text(icon, 20f, center = true).apply {
                gravity = Gravity.CENTER
                stripWords.add(this)
                pressable { heads.getOrNull(i)?.let { list.setSelectionFromTop(it, 0) }; mark(i) }
            }, lp(0, c.dp(36), 1f))
        }
        mark(0)
        fun keys(e: List<String>): List<Row> = e.chunked(8).map { chunk ->
            Cells(2, 8, 44, 0, 10, chunk.map { glyph -> { cell: FrameLayout ->
                val t = (cell.getChildAt(0) as? TextView) ?: c.text("", 28f, center = true).apply { gravity = Gravity.CENTER }.also { cell.removeAllViews(); cell.addView(it, FrameLayout.LayoutParams(MATCH, MATCH)) }
                t.text = glyph
                bindTap(cell, { Log.d("Montana", "emoji_tap key"); onEmoji(glyph) }, null)
            } })
        }
        fun draw() {
            val q = emojiQuery.trim().lowercase()
            heads.clear()
            val rows = ArrayList<Row>()
            if (q.isEmpty()) {
                EMOJI_CATEGORIES.forEach { (icon, glyphs) ->
                    heads.add(rows.size)
                    rows.add(Header(icon, 12f, Color.argb(179, 142, 142, 147), 8))
                    rows.addAll(keys(glyphs))
                }
            } else rows.addAll(keys(EMOJI_CATEGORIES.flatMap { it.second }.distinct().filter { named(it, q) }))
            shelf.rows = rows
            strip.visibility = if (q.isEmpty()) View.VISIBLE else View.GONE
        }
        list.setOnScrollListener(object : AbsListView.OnScrollListener {
            override fun onScrollStateChanged(v: AbsListView?, s: Int) {}
            override fun onScroll(v: AbsListView?, first: Int, count: Int, total: Int) {
                if (emojiQuery.isNotBlank() || heads.isEmpty()) return
                mark(heads.indexOfLast { it <= first }.coerceAtLeast(0))
            }
        })
        draw()
        return c.vstack(Gravity.NO_GRAVITY) {
            addView(searchLine(EMOJI, R.string.search_emoji, { q -> emojiQuery = q; draw() }, { q -> emojiQuery = q; draw() }), lp())
            addView(list, lp(MATCH, 0, 1f).apply { topMargin = dp(4) })
            addView(strip, lp(MATCH, WRAP).apply { setMargins(dp(12), dp(6), dp(12), 0) })
        }
    }

    // ── STICKERS (iOS stickers + stickerBody): my set first, then the house's shelf in sets; a word narrows the shelf ──

    private var stickQuery = ""
    private val stickPacks = ArrayList<GifSearch.Pack>()
    private val stickInPack = HashMap<String, List<GifSearch.Found>>()
    private val packEnded = HashSet<String>()
    private var packAsking: String? = null
    private var packPage = 0
    private var packsEnded = false
    private var packsAsking = false
    private var stickFound: List<GifSearch.Found> = emptyList()
    private var stickEnded = false
    private var stickAsking = false
    private lateinit var drawStickers: () -> Unit

    private fun stickerTab(): View {
        val shelf = Shelf()
        val list = shelfList(shelf)
        val packAt = HashMap<Int, String>()   // a pack's header row → its name: the eye reaching it asks for its pictures
        val stripRow = android.widget.HorizontalScrollView(c).apply { isHorizontalScrollBarEnabled = false }
        fun mineCell(n: String, side: Int) = { cell: FrameLayout ->
            val iv = stillIn(cell)
            iv.setPadding(c.dp(side / 10), c.dp(side / 10), c.dp(side / 10), c.dp(side / 10))
            iv.tag = n
            iv.setImageDrawable(null)
            act.background {
                val b = BitmapFactory.decodeFile(Stickers.file(c, n).path, BitmapFactory.Options().apply { inSampleSize = 2 })
                act.onMain { if (iv.tag == n && b != null) iv.setImageBitmap(b) }
            }
            bindTap(cell, { send { r -> Stickers.sendPicture(c, r, n) } }, { confirmDelete { Stickers.forget(c, n); drawStickers() } })
        }
        drawStickers = {
            val mine = Stickers.names(c)
            val rows = ArrayList<Row>()
            packAt.clear()
            // THE STRIP AT THE TOP IS WHAT THE HAND REACHES FOR (iOS 22.09): every sticker used, newest first
            if (mine.isNotEmpty()) {
                stripRow.removeAllViews()
                stripRow.addView(c.hstack {
                    setPadding(dp(12), 0, dp(12), 0)
                    for (n in mine.take(24)) addView(FrameLayout(c).also { mineCell(n, 44)(it) }, lp(dp(44), dp(44)).apply { marginEnd = dp(10) })
                })
                // the one strip leaves the holder of the last pass first: a second pass (a sticker sent, a pack come) laid it in a
                // new holder while the old one still held it, and the app fell (A1 446, 18.10.2026 14:31 MSK, Picker.kt:691)
                (stripRow.parent as? android.view.ViewGroup)?.removeView(stripRow)
                rows.add(Holder(c.vstack(Gravity.NO_GRAVITY) {
                    addView(stripRow, lp(MATCH, dp(54)).apply { topMargin = dp(6) })
                    addView(View(c).apply { setBackgroundColor(Color.argb(20, 255, 255, 255)) }, lp(MATCH, 1))
                }))
                mine.chunked(4).forEach { chunk -> rows.add(Cells(3, 4, 72, 12, 14, chunk.map { mineCell(it, 72) })) }
            }
            fun house(found: List<GifSearch.Found>) = found.chunked(4).map { chunk ->
                Cells(4, 4, 78, 6, 14, chunk.map { f -> { cell: FrameLayout -> houseCell(cell, f, fill = false) { send { r -> sendHouseSticker(c, r, f) } } } })
            }
            if (stickQuery.isEmpty()) {
                for (pack in stickPacks) {
                    rows.add(Divider())
                    packAt[rows.size] = pack.id
                    rows.add(Header(pack.title, 12f, MT.gray, 0))
                    rows.addAll(house(stickInPack[pack.id].orEmpty()))
                }
            } else if (stickFound.isNotEmpty()) {
                rows.add(Divider())
                rows.addAll(house(stickFound))
            }
            shelf.rows = rows
        }
        fun loadPack(id: String) {
            if (stickInPack.containsKey(id) || packAsking == id) return
            packAsking = id
            act.background { val got = GifSearch.inPack(id); act.onMain { packAsking = null; stickInPack[id] = got; drawStickers() } }
        }
        fun morePacks() {
            if (packsEnded || packsAsking) return
            packsAsking = true
            act.background {
                val got = GifSearch.packs(offset = (packPage + 1) * 12)
                act.onMain {
                    val known = stickPacks.map { it.id }.toSet()
                    val fresh = got.filter { it.id !in known }
                    stickPacks.addAll(fresh); packPage += 1; packsEnded = fresh.isEmpty(); packsAsking = false
                    drawStickers()
                }
            }
        }
        // one page more inside the last set the eye reached, or of the word across the shelves — appended, never a duplicate
        fun morePack(id: String) {
            val have = stickInPack[id] ?: return
            if (packAsking == id || have.isEmpty() || id in packEnded) return
            packAsking = id
            act.background {
                val got = GifSearch.inPack(id, offset = have.size)
                act.onMain {
                    val known = have.map { it.id }.toSet()
                    val fresh = got.filter { it.id !in known }
                    stickInPack[id] = have + fresh
                    if (fresh.isEmpty()) packEnded.add(id)
                    packAsking = null
                    drawStickers()
                }
            }
        }
        fun moreFound() {
            if (stickEnded || stickAsking) return
            stickAsking = true
            act.background {
                val got = GifSearch.find(stickQuery, kind = "sticker", offset = stickFound.size)
                act.onMain {
                    val known = stickFound.map { it.id }.toSet()
                    val fresh = got.filter { it.id !in known }
                    stickFound = stickFound + fresh; stickEnded = fresh.isEmpty(); stickAsking = false
                    drawStickers()
                }
            }
        }
        fun run(word: String) {
            act.background { val got = GifSearch.find(word, kind = "sticker"); act.onMain { stickFound = got; stickEnded = got.isEmpty(); drawStickers() } }
        }
        shelf.shown = { p -> packAt[p]?.let { id -> loadPack(id); if (id == stickPacks.lastOrNull()?.id) morePacks() } }
        shelf.nearEnd = {
            if (stickQuery.isNotEmpty()) moreFound()
            else stickPacks.lastOrNull { stickInPack.containsKey(it.id) }?.let { morePack(it.id) }
        }
        drawStickers()
        // THE SHELF ARRIVES WITH THE TAB (iOS 23.09: «let both the stickers and the gifs load on the touch, at once»)
        if (stickPacks.isEmpty()) act.background {
            val got = GifSearch.packs()
            act.onMain { stickPacks.addAll(got); drawStickers() }
        }
        return c.vstack(Gravity.NO_GRAVITY) {
            addView(searchLine(STICKERS, R.string.search_stickers, { q -> stickQuery = q; if (q.isEmpty()) run("") else drawStickers() }, { q -> stickQuery = q; run(q) }), lp())
            addView(list, lp(MATCH, 0, 1f))
            addView(giphyMark(), lp())
        }
    }

    // ── GIF (iOS gifs): the popular ones the moment the tab opens; what this phone sent stands ahead of them ──

    private var gifQuery = ""
    private var gifFound: List<GifSearch.Found> = emptyList()
    private var gifPage = 1
    private var gifEnded = false
    private var gifAsking = false

    private fun gifTab(): View {
        val shelf = Shelf()
        val list = shelfList(shelf)
        val empty = c.vstack(Gravity.CENTER) {
            addView(c.icon(R.drawable.ic_set_doc, MT.gray, 34), lp(dp(34), dp(34)))
            addView(c.text(c.getString(R.string.gifs_none), 17f, Color.WHITE, bold = true, center = true), lp(WRAP, WRAP).apply { topMargin = dp(10) })
        }
        val room = FrameLayout(c).apply {
            addView(list, FrameLayout.LayoutParams(MATCH, MATCH))
            addView(empty, FrameLayout.LayoutParams(MATCH, MATCH))
        }
        lateinit var draw: () -> Unit
        fun bookCell(n: String) = { cell: FrameLayout ->
            cell.tag = n
            loopIn(cell, true).show(GifBook.file(c, n))
            bindTap(cell, { send { r -> sendGifFile(c, r, n) } }, { confirmDelete { GifBook.forget(c, n); draw() } })
        }
        draw = {
            val book = GifBook.names(c)
            val cells: List<(FrameLayout) -> Unit> = book.map { bookCell(it) } + gifFound.map { f -> { cell: FrameLayout -> houseCell(cell, f, fill = true) { send { r -> sendGifFound(c, r, f) } } } }
            shelf.rows = cells.chunked(3).map { Cells(6, 3, 86, 6, 12, it.map { fill -> { cell: FrameLayout ->
                cell.background = c.rounded(Color.argb(15, 255, 255, 255), 10)
                cell.clipToOutline = true
                fill(cell)
            } }) }
            empty.visibility = if (cells.isEmpty()) View.VISIBLE else View.GONE
            list.visibility = if (cells.isEmpty()) View.GONE else View.VISIBLE
        }
        fun run(word: String) {
            act.background { val got = GifSearch.find(word); act.onMain { gifFound = got; gifPage = 1; gifEnded = got.isEmpty(); draw() } }
        }
        shelf.nearEnd = {
            if (!gifEnded && !gifAsking && gifFound.isNotEmpty()) {
                gifAsking = true
                act.background {
                    val got = GifSearch.find(gifQuery, offset = gifPage * 30)
                    act.onMain {
                        val known = gifFound.map { it.id }.toSet()
                        gifFound = gifFound + got.filter { it.id !in known }
                        gifPage += 1
                        gifEnded = got.isEmpty()   // the end is the house saying nothing; a page of repeats only moves the offset on
                        gifAsking = false
                        draw()
                    }
                }
            }
        }
        list.setPadding(0, c.dp(10), 0, 0)
        draw()
        if (gifFound.isEmpty()) run("")   // THE POPULAR ARRIVE ON OPENING (the node keeps its answer ten minutes)
        return c.vstack(Gravity.NO_GRAVITY) {
            addView(searchLine(GIF, R.string.search_gifs, { q -> gifQuery = q; if (q.isEmpty()) run("") }, { q -> gifQuery = q; run(q) }), lp())
            addView(room, lp(MATCH, 0, 1f))
            addView(giphyMark(), lp())
        }
    }

    // LAST IN THE CLASS ON PURPOSE: a tab is drawn only after every field above it stands (Kotlin runs the class's lines in order;
    // drawn earlier, the first tab met its words and lists still null -- 412 fell on the first touch of the emoji key, 13.10)
    init { show(startTab) }
}

/**
 * THE CHOOSING AS A PAGE OVER THE WHOLE SCREEN (iOS MTPickerPage, MontanaBubble.swift 3296-3334 at 2155; the author's word 23.09):
 * the same panel inside, on the platform's dark — the field and its buttons covered by it; the arrow down or a picture sent gives
 * the screen back. The page stands over the keyboard: its foot rises with the keys.
 */
fun pickerPage(act: MainActivity, ref: String?, tab: Int, search: Boolean, onEmoji: (String) -> Unit, onSent: () -> Unit) {
    val c: Context = act
    lateinit var close: () -> Unit
    val panel = Picker(act, ref, expanded = true, startTab = tab, focusSearch = search, onEmoji = onEmoji,
        onSent = { close(); onSent() }, onLift = { _, _ -> close() }, onSettings = { settings(act, ref) })
    val page = FrameLayout(c).apply {
        setBackgroundColor(Color.rgb(20, 20, 20))
        isClickable = true
        addView(panel.view, FrameLayout.LayoutParams(MATCH, MATCH))
        setOnApplyWindowInsetsListener { v, insets ->
            val b = insets.getInsets(WindowInsets.Type.systemBars() or WindowInsets.Type.ime())
            v.setPadding(b.left, b.top, b.right, b.bottom)
            insets
        }
        addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
            override fun onViewAttachedToWindow(v: View) { v.requestApplyInsets() }
            override fun onViewDetachedFromWindow(v: View) {
                c.getSystemService(InputMethodManager::class.java).hideSoftInputFromWindow(v.windowToken, 0)
            }
        })
    }
    close = act.overlay(page)
}

/** The settings glass (iOS onSettings → the set's page): my stickers' page; a room that keeps words only has none to send into. */
private fun settings(act: MainActivity, ref: String?) {
    if (ref != null) Stickers.setPage(act, ref)
    else android.widget.Toast.makeText(act, R.string.compose_not_yet, android.widget.Toast.LENGTH_SHORT).show()
}

/**
 * THE PANEL IN THE KEYBOARD'S PLACE, ONE OWNER FOR EVERY FIELD ([C-1]: the chat and the saved room): the emoji key swaps the
 * keyboard for the panel and back (iOS emojiKey: showEmoji.toggle(), the glyph «keyboard» while it stands; MontanaConversation.swift
 * 803-813 at 2155), a hold opens it on the stickers. Android lets no app view be the field's input view, so the panel stands under
 * the bar, as tall as the keyboard last stood; the keyboard rising takes its place back, and every other deed of the bar puts it
 * away (iOS showEmoji = false). The page calls `insets` from its own insets listener and `away` from its own hideKeys.
 */
class FieldPanel(private val act: MainActivity, private val ref: String?, private val bar: ChatInputBar, private val field: EditText,
                 private val hideKeys: () -> Unit, private val showKeys: () -> Unit, private val toBottom: () -> Unit) {
    private val c: Context = act
    /** THE PAGE TURNS (iOS 3121f6a6 MTKeyboard.turning, viewWillTransition): the activity outlives a turn, so the panel standing
     *  in the keys' place is laid again at the keys' height of the orientation the page turned to. */
    val host = object : FrameLayout(c) {
        override fun onConfigurationChanged(cfg: android.content.res.Configuration) {
            super.onConfigurationChanged(cfg)
            if (!up) return
            val h = keysHeight()
            Log.d("Montana", "rotate sideways=" + sideways() + " keys=" + h)
            if (layoutParams.height != h) layoutParams = layoutParams.apply { height = h }
        }
    }.apply { visibility = View.GONE }
    private var picker: Picker? = null
    private var keysWere = false
    val up: Boolean get() = host.visibility == View.VISIBLE

    private fun insert(e: String) {
        val a = field.selectionStart.coerceAtLeast(0); val b = field.selectionEnd.coerceAtLeast(0)
        field.text.replace(minOf(a, b), maxOf(a, b), e)
    }

    fun away() { if (up) { host.visibility = View.GONE; bar.panelShown(false) } }

    fun show(tab: Int?) {
        hideKeys()
        val p = picker ?: Picker(act, ref, expanded = false, startTab = tab ?: Picker.EMOJI, focusSearch = false, onEmoji = { insert(it) },
            onSent = { toBottom() },
            onLift = { t, search -> pickerPage(act, ref, t, search, onEmoji = { insert(it) }, onSent = { away(); toBottom() }) },
            onSettings = { settings(act, ref) }).also { picker = it; host.addView(it.view, FrameLayout.LayoutParams(MATCH, MATCH)) }
        if (tab != null && p.tab != tab) p.show(tab)
        host.layoutParams = host.layoutParams.apply { height = keysHeight() }
        host.visibility = View.VISIBLE
        bar.panelShown(true)
        toBottom()
        Log.d("Montana", "emoji_panel shown tab=" + p.tab)
    }

    /** The keyboard's height is the panel's; the keyboard rising takes the panel's place. */
    fun insets(insets: WindowInsets) {
        val keys = insets.isVisible(WindowInsets.Type.ime())
        if (keys) {
            val h = insets.getInsets(WindowInsets.Type.ime()).bottom - insets.getInsets(WindowInsets.Type.systemBars()).bottom
            if (h > c.dp(120)) Prefs.setDbl(key(), h.toDouble())
            if (!keysWere) away()
        }
        keysWere = keys
    }

    init {
        bar.onEmojiKey = { if (up) { away(); showKeys() } else show(null) }
        bar.onStickers = { show(Picker.STICKERS) }
    }

    /** THE KEYS' HEIGHT PER ORIENTATION (iOS MTKeyboard heights[sideways], fallback 336 upright, 200 sideways): one number for both
     *  put a sideways-sized panel under upright keys after every turn. Each orientation keeps the height its keys last stood at. */
    private fun sideways() = c.resources.configuration.orientation == android.content.res.Configuration.ORIENTATION_LANDSCAPE
    private fun key() = if (sideways()) KEYS_HEIGHT_SIDE else KEYS_HEIGHT
    private fun keysHeight() = Prefs.dbl(key(), c.dp(if (sideways()) 200 else 300).toDouble()).toInt()

    private companion object { const val KEYS_HEIGHT = "keys.height"; const val KEYS_HEIGHT_SIDE = "keys.height.side" }
}
