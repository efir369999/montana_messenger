package quest.montana.app

import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.SecureRandom

/**
 * THE SETS OF OTHER PEOPLE (iOS MontanaStickerBook, MontanaSticker.swift:124-360): my set's own name, minted once from my
 * reference and sixteen random bytes; the sets met through a sticker's passport, a link or a page; what each sticker letter
 * says about itself; and who gave each set, the one it is asked of. A sticker is known by its bytes (SHA-256, iOS blobIdHex),
 * so two phones holding the same picture hold the same sticker. The pictures of a set lie beside my own, in «stickers».
 */
object StickerBook {
    private const val ID = "stickers.packid"
    private const val PACKS = "stickers.packs"
    private const val PORTS = "stickers.passports"
    private const val GIVERS = "stickers.givers"
    private const val PORT_LIMIT = 512                // iOS: the passports of the last 512 sticker letters
    private val lock = Any()

    class Pack(val id: String, var title: String, var owner: String, val names: MutableList<String>, var expected: Int) {
        fun json(): JSONObject = JSONObject().put("id", id).put("title", title).put("owner", owner)
            .put("names", JSONArray(names)).put("expected", expected)
    }
    class Passport(val pack: String, val sticker: String, val emoji: String, val title: String, val owner: String,
                   val quote: String, val quoteMid: String) {
        fun json(): JSONObject = JSONObject().put("pack", pack).put("sticker", sticker).put("emoji", emoji).put("title", title)
            .put("owner", owner).put("quote", quote).put("quoteMid", quoteMid)
    }

    private fun obj(key: String) = runCatching { JSONObject(Prefs.str(key, "{}")) }.getOrElse { JSONObject() }

    /** The name of this phone's set, minted once and never moved (iOS mineId, MontanaStickerPack.mint). */
    val mineId: String get() = synchronized(lock) {
        Prefs.str(ID, "").ifEmpty {
            val seed = (MontanaSeed.twin ?: "").toByteArray() + ByteArray(16).also { SecureRandom().nextBytes(it) }
            Wire.hex(Wire.sha(seed)).also { Prefs.setStr(ID, it) }
        }
    }

    /** The sticker's own name inside a set: its bytes' SHA-256 (iOS stickerId(of:)). */
    fun stickerId(bytes: ByteArray) = Wire.hex(Wire.sha(bytes))

    fun packs(): List<Pack> = synchronized(lock) {
        val a = runCatching { JSONArray(Prefs.str(PACKS, "[]")) }.getOrElse { JSONArray() }
        (0 until a.length()).mapNotNull { i ->
            a.optJSONObject(i)?.let { o ->
                val n = o.optJSONArray("names") ?: JSONArray()
                Pack(o.optString("id"), o.optString("title"), o.optString("owner"),
                    MutableList(n.length()) { n.optString(it) }, o.optInt("expected"))
            }
        }
    }
    private fun keep(list: List<Pack>) = Prefs.setStr(PACKS, JSONArray(list.map { it.json() }).toString())
    fun pack(id: String): Pack? = packs().firstOrNull { it.id == id }
    fun holds(id: String) = id == mineId || pack(id) != null

    /** The one page watching a set fill (Stickers.setPage): told on the main thread whenever a set is met or a page lands. */
    @Volatile var onChange: (() -> Unit)? = null
    private val main = Handler(Looper.getMainLooper())
    fun changed() { main.post { onChange?.invoke() } }

    /**
     * A SET REMOVED FROM THIS PHONE (iOS drop(pack:)): the set leaves the book and its pictures leave the disk — all but those
     * my own set or another set still names, since a sticker is one file whoever holds it.
     */
    fun drop(id: String) {
        synchronized(lock) {
            val list = packs().toMutableList()
            val p = list.firstOrNull { it.id == id } ?: return
            list.remove(p)
            keep(list)
            val kept = Stickers.names(Book.ctx).toSet() + list.flatMap { it.names }
            p.names.filter { it !in kept }.forEach { File(File(Book.ctx.filesDir, "stickers"), it).delete() }
            Log.d("Montana", "sticker_book drop pack=" + id.take(8) + " n=" + p.names.size)
        }
    }

    /** A picture another set names (iOS allFiles): forgotten from my set, its file stays for that set. */
    fun othersHold(name: String) = packs().any { name in it.names }

    /** A set's word arrived: the set is known by name before a single sticker of it has landed (iOS meet). */
    fun meet(id: String, title: String, owner: String, expected: Int) = synchronized(lock) {
        val list = packs().toMutableList()
        val p = list.firstOrNull { it.id == id }
        if (p != null) { p.title = title; p.owner = owner; if (expected > 0) p.expected = expected }
        else list.add(0, Pack(id, title, owner, mutableListOf(), expected))
        keep(list)
    }

    /** A sticker of another person's set landed: filed under its own name, once (iOS land). */
    fun land(id: String, sticker: String, png: ByteArray): String? = synchronized(lock) {
        val list = packs()
        val p = list.firstOrNull { it.id == id } ?: return null
        if (sticker.length != 64 || stickerId(png) != sticker) return null   // the bytes are the sticker's name, or it is not that sticker
        val name = "stk_" + sticker.take(16) + "." + suffix(png)
        if (name in p.names) return name
        File(File(Book.ctx.filesDir, "stickers").apply { mkdirs() }, name).writeBytes(png)
        p.names.add(name)
        keep(list)
        name
    }

    /** What the bytes are, for the file's suffix (iOS MontanaStickerCut.suffix). */
    private fun suffix(b: ByteArray): String = when {
        b.size > 3 && b[0] == 0x89.toByte() && b[1] == 'P'.code.toByte() -> "png"
        b.size > 11 && String(b, 8, 4, Charsets.US_ASCII) == "WEBP" -> "webp"
        b.size > 11 && String(b, 4, 4, Charsets.US_ASCII) == "ftyp" -> "heic"
        else -> "jpg"
    }

    /** THE LETTER'S NAME HAS ONE SPELLING HERE (iOS bare): the wire's names wear no «mid:». */
    fun bare(letter: String) = letter.removePrefix("mid:")

    fun note(passport: Passport, letter: String) = synchronized(lock) {
        val l = bare(letter).ifEmpty { return }
        val o = obj(PORTS)
        o.put(l, passport.json())
        while (o.length() > PORT_LIMIT) o.remove(o.keys().next())
        Prefs.setStr(PORTS, o.toString())
    }
    fun passport(letter: String): Passport? = obj(PORTS).optJSONObject(bare(letter))?.let {
        Passport(it.optString("pack"), it.optString("sticker"), it.optString("emoji"), it.optString("title"),
            it.optString("owner"), it.optString("quote"), it.optString("quoteMid"))
    }

    /** WHO GAVE THE SET (iOS note(giver:)): the one it is asked of; the set's owner first. */
    fun note(giver: String, pack: String) = synchronized(lock) {
        if (giver.isEmpty() || pack.isEmpty()) return
        val o = obj(GIVERS)
        if (o.optString(pack) != giver) Prefs.setStr(GIVERS, o.put(pack, giver).toString())
    }
    fun giver(pack: String): String? = pack(pack)?.owner?.takeIf { it.isNotEmpty() } ?: obj(GIVERS).optString(pack).ifEmpty { null }

    /** The person forgotten: the sets met and the passports leave with them (their files leave with Stickers.wipe). */
    fun wipe() = Prefs.remove(ID, PACKS, PORTS, GIVERS)
}

/**
 * THE SET'S WORD ON THE WIRE (iOS MontanaStickerWire): a service word of its own, «SP:», that every build reads or buries unread —
 * nothing touches the picture road. Three shapes, told apart by «t»: «id» the passport of a sticker letter (its set, its sticker,
 * the letter it answers), «ask» send me that set, «pack» a page of a set with up to six stickers and their bytes. A page rides the
 * long-letter road of Post.send, so a set of any size needs no road of its own.
 */
object StickerWire {
    const val MARK = "​​SP:"
    private const val PAGE = 6                        // iOS page: six pictures stay well inside the node's body

    /**
     * The passport of a sticker letter of my set, sent right behind it under the SAME name the picture rides (iOS sendPassport).
     * A group's passport rides the group's own word «sp» and names no address (Groups.carryPassport).
     */
    fun sendPassport(ref: String, letter: String, bytes: ByteArray, quote: Pair<String, String>? = null) {
        if (ref.isEmpty() || letter.isEmpty()) return
        val w = JSONObject().put("t", "id").put("m", StickerBook.bare(letter)).put("p", StickerBook.mineId)
            .put("s", StickerBook.stickerId(bytes)).put("n", "Montana").put("c", Stickers.names(Book.ctx).size)
        // THE QUOTE OF A STICKER RIDES HERE (iOS sendPassport rq/rm, MontanaStickerWire.swift:41-43 at 2316): the picture road
        // carries no reply, so the letter it answers is named in its passport and the receiver's row grows the plate
        quote?.takeIf { it.first.isNotEmpty() }?.let { (q, m) -> w.put("rq", q).put("rm", StickerBook.bare(m)) }
        if (Groups.isKey(ref)) { Groups.carryPassport(ref, StickerBook.bare(letter), w.toString()); return }
        MontanaSeed.twin?.let { w.put("o", it) }
        send(ref, w)
        Log.d("Montana", "sticker_wire passport letter=" + letter.take(12) + " pack=" + StickerBook.mineId.take(8))
    }

    /** «Send me that set» — asked of the one who gave it, never of a stranger (iOS ask). */
    fun ask(pack: String, of: String) {
        if (of.isEmpty() || pack.isEmpty()) return
        send(of, JSONObject().put("t", "ask").put("p", pack))
        Log.d("Montana", "sticker_wire ask pack=" + pack.take(8) + " of=" + of.take(10))
    }

    /** The set itself, in pages. Only my own set is answered: what I hold of another's is theirs to give (iOS answer). */
    private fun answer(pack: String, to: String) {
        if (pack != StickerBook.mineId) { Log.d("Montana", "sticker_wire ask refused: not this phone's set"); return }
        val names = Stickers.names(Book.ctx)
        val pages = maxOf(1, (names.size + PAGE - 1) / PAGE)
        for (i in 0 until pages) {
            val items = JSONArray()
            for (name in names.drop(i * PAGE).take(PAGE)) {
                val b = Stickers.file(Book.ctx, name).takeIf { it.exists() }?.readBytes() ?: continue
                items.put(JSONObject().put("s", StickerBook.stickerId(b)).put("d", Base64.encodeToString(b, Base64.NO_WRAP)))
            }
            val w = JSONObject().put("t", "pack").put("p", pack).put("n", "Montana").put("i", i).put("of", pages)
                .put("c", names.size).put("items", items)
            MontanaSeed.twin?.let { w.put("o", it) }
            send(to, w)
        }
        Log.d("Montana", "sticker_wire answer pack=" + pack.take(8) + " pages=$pages n=" + names.size)
    }

    private fun send(ref: String, w: JSONObject) {
        if (Groups.isKey(ref) || PeerSafety.isBlocked(ref) || Book.secret(ref) == null) return
        Post.send(ref, Marks.mintMid(), MARK + w.toString(), quiet = true)
    }

    /**
     * A LATE QUOTE SETTLES ON ITS ROW (iOS enrichQuote, MontanaChatStore.swift:2151-2157 at 2316): a sticker letter's passport names
     * the letter it answers; the row takes it when it has none -- whichever of the two, the passport or the picture, came last.
     */
    fun enrich(chat: String, letter: String) {
        val port = StickerBook.passport(letter)?.takeIf { it.quote.isNotEmpty() } ?: return
        val mid = StickerBook.bare(letter)
        if (Book.chat(chat)?.msgs?.any { it.mid == mid && it.qt == null } != true) return
        Book.edit(chat) { ch -> ch.msgs.find { it.mid == mid && it.qt == null }?.let { it.qt = port.quote; it.qm = port.quoteMid.ifEmpty { null } } }
        Log.d("Montana", "quote_enriched mid=" + mid.take(8))
    }

    /** A word of a set arrived (iOS handle): read here, never a row. `from` is the pipe it came by — the giver when it names none;
     *  `chat` the feed its letter stands in (a group's key when the group carried it). */
    fun handle(text: String, from: String, chat: String = from) {
        val o = runCatching { JSONObject(text.removePrefix(MARK)) }.getOrNull() ?: return
        when (o.optString("t")) {
            "id" -> {
                val letter = o.optString("m"); val pack = o.optString("p")
                if (letter.isEmpty() || pack.isEmpty()) return
                val title = o.optString("n").ifEmpty { "Montana" }
                val owner = o.optString("o").ifEmpty { from }
                StickerBook.note(StickerBook.Passport(pack, o.optString("s"), o.optString("e"), title, owner,
                    o.optString("rq"), o.optString("rm")), letter)
                if (!StickerBook.holds(pack)) StickerBook.meet(pack, title, owner, o.optInt("c"))
                StickerBook.note(owner, pack)
                enrich(chat, letter)   // the letter may already stand: its plate grows here
                Log.d("Montana", "sticker_wire passport in letter=" + letter.take(12))
            }
            "ask" -> o.optString("p").takeIf { it.isNotEmpty() }?.let { answer(it, from) }
            "pack" -> {
                val pack = o.optString("p").ifEmpty { return }
                StickerBook.meet(pack, o.optString("n").ifEmpty { "Montana" }, o.optString("o").ifEmpty { from }, o.optInt("c"))
                val items = o.optJSONArray("items") ?: JSONArray()
                var landed = 0
                for (i in 0 until items.length()) {
                    val it = items.optJSONObject(i) ?: continue
                    val png = runCatching { Base64.decode(it.optString("d"), Base64.DEFAULT) }.getOrNull() ?: continue
                    if (StickerBook.land(pack, it.optString("s"), png) != null) landed++
                }
                Log.d("Montana", "sticker_wire page " + (o.optInt("i") + 1) + "/" + o.optInt("of", 1) + " landed=$landed")
            }
            else -> {}   // a shape from a newer build: buried in silence
        }
        StickerBook.changed()
    }

    /**
     * A LETTER CARRYING A SET'S LINK NAMES ITS GIVER (iOS noteLink): the link holds no address of anybody, so the one who handed
     * it over is remembered at the moment the letter lands — that is whom the set is asked of when the link is tapped.
     */
    fun noteLink(text: String, peer: String) {
        val (id, title) = StickerPack.idIn(text) ?: return
        if (peer.isEmpty()) return
        if (!StickerBook.holds(id)) StickerBook.meet(id, title.ifEmpty { "Montana" }, peer, 0)
        StickerBook.note(peer, id)
        Log.d("Montana", "sticker_wire link noted pack=" + id.take(8) + " giver=" + peer.take(10))
    }
}

/**
 * THE SET'S LINK (iOS MontanaStickerPack.link / idIn, MontanaSticker.swift:361-391): the set's name and its title, and not one
 * address of anybody — montana://pack/<64 hex>?n=<title>. Found wherever it stands among a letter's words.
 */
object StickerPack {
    private const val HEAD = "montana://pack/"   // NOT-UI

    fun link(id: String, title: String): String = HEAD + id + if (title.isEmpty()) "" else "?n=" + Uri.encode(title)

    fun idIn(text: String): Pair<String, String>? {
        val at = text.indexOf(HEAD, ignoreCase = true).takeIf { it >= 0 } ?: return null
        val tail = text.substring(at + HEAD.length)
        val id = tail.takeWhile { it in '0'..'9' || it.lowercaseChar() in 'a'..'f' }
        if (id.length != 64) return null
        val q = tail.indexOf("?n=")
        val title = if (q < 0) "" else runCatching { Uri.decode(tail.substring(q + 3).takeWhile { !it.isWhitespace() }) }.getOrDefault("")
        return id.lowercase() to title
    }
}
