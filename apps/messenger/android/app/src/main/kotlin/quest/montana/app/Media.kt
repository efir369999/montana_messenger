package quest.montana.app

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.media.ThumbnailUtils
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import android.util.Base64
import android.util.Log
import android.util.Size
import android.webkit.MimeTypeMap
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File

/**
 * PICTURES, FILMS AND FILES (iOS MontanaMedia / MontanaMediaKit), byte for byte:
 *   the file is cut into 512 KiB pieces; each piece is padded (mt_e2e_pad_len), sealed under the letter's blob key with a
 *   nonce DERIVED from the key, its number and its bytes, and laid on the node under SHA-256 of the seal;
 *   the manifest {k, e, bk, sz, chunks:[{bid, cs}], n?, th?, cap?} rides in the letter as MD:<json> — or, when it outgrows
 *   the letter, sealed under a key of its own as a blob and the letter carries MD:{mref, mk, sz}.
 * The receiver fetches every piece, checks its name against its bytes, opens it, cuts the padding, appends it in order —
 * and only an assembled file is answered «delivered»; the pieces are then dropped from the node.
 */
object Media {
    const val CHUNK = 512 * 1024
    private const val LIMIT = 200L * 1024 * 1024   // what this phone carries in one letter for now
    private val inFlight = HashSet<String>()
    private val lastTry = HashMap<String, Long>()   // a piece still missing is asked again a minute later, not every round

    fun dir(c: Context) = File(c.filesDir, "media").apply { mkdirs() }
    fun file(c: Context, mid: String, ext: String) = File(dir(c), "$mid.${ext.ifEmpty { "bin" }.take(8)}")

    /** The core's padding (mt_messenger_e2e::media::pad_len): 256 floor, then 1/16 of the bit length's step. */
    fun padLen(n: Int): Int {
        if (n < 256) return 256
        val bl = 32 - Integer.numberOfLeadingZeros(n)
        val step = 1 shl (bl - 5)
        return ((n + step - 1) / step) * step
    }

    /** What a media letter says of itself, whole, when its manifest rides inside it; null for the sealed shape. */
    fun inline(text: String): JSONObject? =
        runCatching { JSONObject(text.removePrefix(Marks.MEDIA)) }.getOrNull()?.takeIf { !it.has("mref") }

    /** The manifest behind a media letter: inside it, or sealed as a blob of its own (iOS mref/mk). */
    fun manifest(text: String): JSONObject? {
        val o = runCatching { JSONObject(text.removePrefix(Marks.MEDIA)) }.getOrNull() ?: return null
        if (!o.has("mref")) return o
        val mk = runCatching { Base64.decode(o.getString("mk"), Base64.DEFAULT) }.getOrNull() ?: return null
        val sealed = Wire.getBlob(o.getString("mref")) ?: return null
        val plain = Wire.open(mk, sealed) ?: return null
        return runCatching { JSONObject(String(plain, Charsets.UTF_8)) }.getOrNull()
    }

    /** What a media letter says of itself as known here: the manifest kept with the row, or the one inside the letter. */
    fun manifestOf(m: Msg): JSONObject? = m.meta?.let { runCatching { JSONObject(it) }.getOrNull() } ?: inline(m.text)
    /** A picture's or a film's caption, the person's words under it ("" — none); a round note carries none. */
    fun captionOf(m: Msg): String = manifestOf(m)?.optString("cap").orEmpty()
    /**
     * THE LETTER WHOSE CAPTION IS EDITED (iOS rowLetters, MontanaConversation.swift:2210-2213 at 2155, atom 3a5fc9f43b48): of a bubble
     * of my own pictures and films -- one, or a media group's plate -- the one letter that carries the caption, or the first when none
     * does. Null: the bubble holds anything else (a voice, a file, a round note, a sticker, the peer's letter).
     */
    fun captionLetter(row: List<Msg>): Msg? {
        if (row.isEmpty() || row.any { !it.mine || !it.text.startsWith(Marks.MEDIA) }) return null
        val mans = row.map { manifestOf(it) ?: return null }
        if (mans.any { (it.optString("k") != "img" && it.optString("k") != "vid") || it.optBoolean("r") }) return null
        return row.firstOrNull { captionOf(it).isNotEmpty() } ?: row.first()
    }

    // ── sending ──

    class Picked(val bytes: ByteArray, val kind: String, val ext: String, val name: String?, val du: Double? = null, val wave: FloatArray? = null, val round: Boolean = false,
                 val badge: String? = null)

    /** What was picked, read whole, with its kind as iOS names kinds (img · vid · doc). */
    fun read(c: Context, uri: Uri, asDoc: Boolean): Picked? {
        val cr = c.contentResolver
        val mime = cr.getType(uri) ?: ""
        var name: String? = null
        var size = -1L
        runCatching {
            cr.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { cur ->
                if (cur.moveToFirst()) { name = cur.getString(0); size = cur.getLong(1) }
            }
        }
        if (size > LIMIT) return null
        val bytes = runCatching { cr.openInputStream(uri)?.use { it.readBytes() } }.getOrNull() ?: return null
        val ext = (name?.substringAfterLast('.', "")?.takeIf { it.isNotEmpty() && it.length <= 8 }
            ?: MimeTypeMap.getSingleton().getExtensionFromMimeType(mime) ?: "bin").lowercase()
        val kind = when {
            asDoc -> "doc"
            mime.startsWith("image/") -> "img"
            mime.startsWith("video/") -> "vid"
            else -> "doc"
        }
        // a picture leaves in the one shape of a photo on its way out; a moving one keeps its frames
        if (kind == "img" && ext != "gif") photoForSend(bytes)?.let { return Picked(it, kind, "jpg", name) }
        return Picked(bytes, kind, if (kind == "img" && ext == "jpeg") "jpg" else ext, name)
    }

    /**
     * THE ONE SHAPE OF A PHOTO ON ITS WAY OUT (iOS MontanaMedia.photoForSend, MontanaMediaKit 984-1005, the author's word 09.09; fork
     * atom 1420): 1600 points on the long side, JPEG 0.85, sampled down at decode so the original never stands whole in memory, its
     * orientation honoured. The original's own record — the camera, the moment, the place it was taken — does not ride: the new JPEG
     * carries none. Android sent the gallery's and the camera's originals whole, twelve megapixels and the place with them. Null:
     * a picture this road cannot read (a HEIF before Android 9), which then leaves as it came.
     */
    fun photoForSend(bytes: ByteArray, maxDim: Int = 1600, quality: Int = 85): ByteArray? = runCatching {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        val big = maxOf(bounds.outWidth, bounds.outHeight)
        if (big <= 0) return null
        var sample = 1
        while (maxDim <= big / (sample * 2)) sample *= 2
        val raw = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample }) ?: return null
        val turn = when (android.media.ExifInterface(java.io.ByteArrayInputStream(bytes)).getAttributeInt(android.media.ExifInterface.TAG_ORIENTATION, 1)) {
            6 -> 90f; 3 -> 180f; 8 -> 270f; else -> 0f
        }
        val scale = minOf(1f, maxDim.toFloat() / maxOf(raw.width, raw.height))
        val m = android.graphics.Matrix().apply { postScale(scale, scale); if (turn != 0f) postRotate(turn) }
        val shaped = Bitmap.createBitmap(raw, 0, 0, raw.width, raw.height, m, true)
        val out = ByteArrayOutputStream()
        shaped.compress(Bitmap.CompressFormat.JPEG, quality, out)
        if (shaped !== raw) shaped.recycle()
        raw.recycle()
        out.toByteArray()
    }.getOrNull()

    private const val SEE_THROUGH_FLOOR = 16   // the last rung of a see-through preview, its side in pixels (iOS seeThroughFloor)
    /**
     * The picture's small face that rides the manifest (iOS thumbBase64): 120 points, at most 16 KB.
     * A SEE-THROUGH PICTURE KEEPS ITS GROUND (iOS MontanaE2E.swift:1094-1106 at 2155, the author's word 22.09:
     * "the sticker loads as a photo on a white ground"): this mini-frame rides in the letter and stands in the
     * receiver's row while the file is still on its way, and JPEG has no transparency at all -- a picture with
     * an alpha channel is written PNG instead, held down by its own side rather than a quality it does not have.
     */
    private fun thumb(b0: Bitmap): String? {
        // THE PREVIEW'S PIXELS ARE OURS (iOS 8150c61c, the iPhone 17 17.10.2026): drawn in the standard range -- a wide-colour or HDR
        // picture decoded in 16-bit float is brought to 8 bits first -- and see-through only when the SOURCE is
        val b = if (b0.config == Bitmap.Config.RGBA_F16) b0.copy(Bitmap.Config.ARGB_8888, false) ?: b0 else b0
        val scale = minOf(1f, 120f / maxOf(b.width, b.height))
        val small = Bitmap.createScaledBitmap(b, maxOf(1, (b.width * scale).toInt()), maxOf(1, (b.height * scale).toInt()), true)
        if (small.hasAlpha()) {
            fun shot(side: Int): ByteArray {
                val k = side.toFloat() / maxOf(small.width, small.height)
                val bm = if (k >= 1f) small else Bitmap.createScaledBitmap(small, maxOf(1, (small.width * k).toInt()), maxOf(1, (small.height * k).toInt()), true)
                return ByteArrayOutputStream().also { bm.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
            }
            var side = maxOf(small.width, small.height)
            while (side > SEE_THROUGH_FLOOR) {
                val out = shot(side)
                if (out.size <= 16000) return Base64.encodeToString(out, Base64.NO_WRAP)
                side = maxOf(SEE_THROUGH_FLOOR, (side * 0.7f).toInt())
            }
            // the last rung (iOS seeThroughFloor): 16 x 16 pixels of 8-bit RGBA are 1 KiB raw, under the budget by arithmetic
            return Base64.encodeToString(shot(SEE_THROUGH_FLOOR), Base64.NO_WRAP)
        }
        var q = 70
        while (q >= 20) {
            val out = ByteArrayOutputStream(); small.compress(Bitmap.CompressFormat.JPEG, q, out)
            if (out.size() <= 16000) return Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
            q -= 15
        }
        return null
    }

    /**
     * THE ONE ROAD OF A SENT FILE: the row stands at once with the local copy, the pieces are sealed and laid on the node,
     * then the letter with the manifest leaves by the ordinary post (the pieces first — the receiver must find them).
     */
    fun send(c: Context, ref: String, picked: Picked, caption: String, qt: String? = null, group: MediaGroup.Slot? = null,
             swap: (() -> ByteArray?)? = null, gate: Boolean = true, turn: String? = null, named: String? = null,
             plate: Pair<String, String>? = null) {   // the quote the row shows and the letter does not carry: a sticker's rides its passport
        // A MEDIA LETTER OF A GROUP IS ASKED OF THE GROUP FIRST (iOS sendGatedMedia, G.5): a right the group took from its members, or
        // slow mode's wait, is said and no row is laid; every other letter goes on by the one road
        if (gate && Groups.isKey(ref)) refusal(c, ref, picked, caption)?.let { Groups.tellRefusal(it); return }
        var p = picked
        val mid = named ?: Marks.mintMid()   // a sticker names its letter first: its passport rides under the same name (iOS letterMidFor)
        val local = file(c, mid, p.ext)
        local.writeBytes(p.bytes)
        val provisional = Marks.MEDIA + JSONObject().put("k", p.kind).put("e", p.ext).put("sz", p.bytes.size).apply {
            p.name?.let { put("n", it) }; if (caption.isNotEmpty()) put("cap", caption); p.du?.let { put("du", it) }
            if (p.round) put("r", true)
            p.badge?.let { put("rb", it) }   // the dual note's badge corner (iOS «rb», MontanaMediaKit.swift:1093)
            MediaGroup.stamp(this, group)
            p.wave?.takeIf { it.isNotEmpty() }?.let { w -> put("wv", Base64.encodeToString(ByteArray(w.size) { (w[it] * 255).toInt().coerceIn(0, 255).toByte() }, Base64.NO_WRAP)) }
        }
        Book.edit(ref) { it.msgs.add(Msg(mid, provisional, true, Marks.birthMs(mid) ?: System.currentTimeMillis(), qt = qt ?: plate?.first, qm = plate?.second, file = local.path)) }
        if (!Book.isLocal(ref)) Transfers.set(mid, 0.01f)   // the ring stands at the tap (iOS setUploadProgress(fileName, 0.01), MontanaConversation.swift:4609)
        val work: () -> Unit = work@{
            // A ROW TAKEN OFF THE FEED BEFORE ITS TURN (its cross, a deletion) is not sent after all (iOS MTSendLine's guard, 2312)
            if (turn != null && Book.chat(ref)?.msgs?.toList()?.none { it.mid == mid } == true) {
                Transfers.set(mid, null); Log.i("Montana", "send_line turn=$turn kind=${p.kind} skipped -- the row left before its turn"); return@work
            }
            if (turn != null) Log.i("Montana", "send_line turn=$turn kind=${p.kind} waiting=${SendLine.pending(ref)}")
            // THE ROW STANDS AT THE TAP, THE FULL FILE TAKES ITS PLACE BEFORE A BYTE LEAVES (iOS sendGifFound, MontanaConversation.swift
            // 3822-3846 at 2155): `swap` brings the full bytes behind the standing row; the file's name never changes, only what lies
            // under it, and the picture plays its three cycles again in its full shape (iOS MTGifPlay.renew)
            swap?.invoke()?.let { full ->
                local.writeBytes(full)
                p = Picked(full, p.kind, p.ext, p.name, p.du, p.wave, p.round, p.badge)
                GifPlay.renew(local.name)
                Book.edit(ref) { ch -> ch.msgs.find { it.mid == mid && it.file == local.path }?.let { it.text = it.text } }
            }
            // THE TRACK'S WAVE IS BORN WITH THE LETTER (iOS MTWaveform, MontanaMediaKit 53-103, 1101-1107, atom bdee948c8ba1): a track
            // sent as a file is probed once -- sixty points -- and the manifest carries them, so the bars stand at the send and at the
            // receipt before a byte of the file has arrived; the sender's own row wears the same points
            val wave = p.wave ?: if (p.kind == "aud" || (p.kind == "doc" && Waveform.isAudio(p.name ?: ("x." + p.ext)))) Waveform.compute(local) else null
            val pw = if (wave != null && p.wave == null) Picked(p.bytes, p.kind, p.ext, p.name, p.du, wave, p.round) else p
            var told = provisional
            if (pw !== p) {
                told = Marks.MEDIA + JSONObject(provisional.removePrefix(Marks.MEDIA))
                    .put("wv", Base64.encodeToString(ByteArray(wave!!.size) { (wave[it] * 255).toInt().coerceIn(0, 255).toByte() }, Base64.NO_WRAP))
                Book.edit(ref) { ch -> ch.msgs.find { it.mid == mid && it.file == local.path }?.let { it.text = told } }
            }
            // THE LOCAL ROOM KEEPS ITS FILE (iOS isLocalRoom): nothing is sealed or laid -- the letter is settled with the file beside it
            if (Book.isLocal(ref)) { Book.edit(ref) { ch -> ch.msgs.find { it.mid == mid }?.advance(2) }; return@work }
            if (deliver(c, ref, mid, pw, caption, local, qt, group)) return@work
            // THE INTENT SURVIVES ITS BROKEN UPLOAD (iOS 1675, 1677): the bubble stands at the clock and the upload waits for the drain
            keepIntent(ref, mid, local, told, caption, qt)
            Log.w("Montana", "media: the pieces did not reach the node — the intent waits for the drain mid=" + mid.take(8))
        }
        // a tray's file waits in its conversation's one line (SendLine): its network work starts when the one before it is over
        if (turn != null) SendLine.enqueue(ref, work) else Thread(work).start()
    }

    /** The pieces laid, the row given its letter, the letter posted; false — the node took nothing, the intent stands. */
    private fun deliver(c: Context, ref: String, mid: String, p: Picked, caption: String, local: File, qt: String?, group: MediaGroup.Slot?): Boolean {
        // the ring leaves when the pieces are laid or broken (iOS finish: setUploadProgress(k, nil)); a broken one waits for the drain without it
        val (letter, man) = (try { seal(c, p, caption, local, group, mid) } finally { Transfers.set(mid, null) }) ?: return false
        Book.edit(ref) { ch -> ch.msgs.find { it.mid == mid }?.let { it.text = letter; it.meta = man } }
        // a group's manifest rides the group's carrier, a copy to everyone it carries to (iOS sendMediaToPeer → MTGroup.carryMedia)
        if (Groups.isKey(ref)) { if (!Groups.carryMedia(ref, mid, letter)) Book.edit(ref) { ch -> ch.msgs.find { it.mid == mid }?.advance(-1) } }
        else Post.send(ref, mid, letter, qt)   // a forwarded file carries the forwarded quote (iOS forwardedQuote)
        return true
    }

    // ── the intents that wait (iOS: a media intent rides the drain) ──
    private const val INTENTS = "mediaIntents"
    private val intentLock = Any()
    /** The person forgotten: every file of every chat and every picture still waiting to leave go with them (Book.wipe). */
    fun wipe(c: Context) {
        synchronized(intentLock) { DeviceVault.delete(INTENTS) }
        File(c.filesDir, "media").deleteRecursively()
    }
    private fun intents(): JSONArray = DeviceVault.get(INTENTS)?.let { runCatching { JSONArray(String(it, Charsets.UTF_8)) }.getOrNull() } ?: JSONArray()
    private fun keepIntent(ref: String, mid: String, local: File, provisional: String, caption: String, qt: String?) = synchronized(intentLock) {
        val a = intents().put(JSONObject().put("ref", ref).put("mid", mid).put("f", local.path).put("p", provisional).put("cap", caption).put("qt", qt ?: ""))
        DeviceVault.set(INTENTS, a.toString().toByteArray())
    }
    private fun dropIntent(mid: String) = synchronized(intentLock) {
        val a = intents(); val keep = JSONArray()
        for (i in 0 until a.length()) a.optJSONObject(i)?.let { if (it.optString("mid") != mid) keep.put(it) }
        DeviceVault.set(INTENTS, keep.toString().toByteArray())
    }
    /** The files an unsent letter still names (iOS MontanaMediaStore.held): the cache never clears them. */
    fun inHand(): Set<String> = synchronized(intentLock) { intents().let { a -> (0 until a.length()).mapNotNull { a.optJSONObject(it)?.optString("f") }.toSet() } }
    /** The letters whose intent waits for the drain: the queue holds them (iOS queueHolds), their clock is honest. */
    fun intentMids(): Set<String> = synchronized(intentLock) { intents().let { a -> (0 until a.length()).mapNotNull { a.optJSONObject(it)?.optString("mid") }.toSet() } }
    /**
     * A RED FILE TAPPED (iOS resendMedia): THE SAME ROAD AS THE FIRST SEND under the row's own name -- the pieces sealed and laid
     * again from the file beside the row, the letter posted again; the row back at the clock with its ring. A file gone is no retry.
     */
    fun resend(c: Context, ref: String, m: Msg) {
        val f = m.file?.let { File(it) }?.takeIf { it.exists() } ?: return
        val man = manifestOf(m) ?: return
        var back = false
        Book.edit(ref) { ch -> ch.msgs.find { it.mid == m.mid && it.mine }?.let { back = it.restart() } }
        if (!back) return
        if (!Book.isLocal(ref)) Transfers.set(m.mid, 0.01f)
        Log.i("Montana", "resend_tap m=" + m.mid.take(8) + " kind=" + man.optString("k") + " human retry")
        Thread {
            val wave = man.optString("wv").takeIf { it.isNotEmpty() }?.let { w ->
                runCatching { Base64.decode(w, Base64.NO_WRAP) }.getOrNull()?.let { b -> FloatArray(b.size) { (b[it].toInt() and 0xFF) / 255f } }
            }
            val p = Picked(f.readBytes(), man.optString("k").ifEmpty { "doc" }, man.optString("e").ifEmpty { f.extension }, man.optString("n").ifEmpty { null },
                man.optDouble("du").takeIf { !it.isNaN() }, wave, man.optBoolean("r"))
            val caption = man.optString("cap")
            if (!deliver(c, ref, m.mid, p, caption, f, m.qt, MediaGroup.read(man))) keepIntent(ref, m.mid, f, Marks.MEDIA + man.toString(), caption, m.qt)
        }.start()
    }
    @Volatile private var draining = false
    /** The intents still waiting go out again, oldest first, one at a time, at every pickup of the box; while the node takes nothing the rest wait too. */
    fun drainIntents(c: Context) {
        if (draining) return
        draining = true
        try {
            val a = synchronized(intentLock) { intents() }
            for (i in 0 until a.length()) {
                val o = a.optJSONObject(i) ?: continue
                val mid = o.optString("mid")
                val f = File(o.optString("f")).takeIf { it.exists() } ?: run { dropIntent(mid); null } ?: continue
                val man = runCatching { JSONObject(o.optString("p").removePrefix(Marks.MEDIA)) }.getOrNull() ?: run { dropIntent(mid); null } ?: continue
                val wave = man.optString("wv").takeIf { it.isNotEmpty() }?.let { w ->
                    runCatching { Base64.decode(w, Base64.NO_WRAP) }.getOrNull()?.let { b -> FloatArray(b.size) { (b[it].toInt() and 0xFF) / 255f } }
                }
                val p = Picked(f.readBytes(), man.optString("k").ifEmpty { "doc" }, man.optString("e").ifEmpty { f.extension }, man.optString("n").ifEmpty { null },
                    man.optDouble("du").takeIf { !it.isNaN() }, wave, man.optBoolean("r"))
                if (!deliver(c, o.optString("ref"), mid, p, o.optString("cap"), f, o.optString("qt").ifEmpty { null }, MediaGroup.read(man))) return
                dropIntent(mid)
                Log.i("Montana", "media: a waiting intent went out mid=" + mid.take(8))
            }
        } finally { draining = false }
    }

    /**
     * PICTURES PICKED TOGETHER LEAVE AS ONE GROUP (iOS sendAssets / sendPasted, MontanaConversation 3160-3206, 3568-3577): one
     * key for the pick, the pick's order, the words with the first letter only; one picture is no group.
     */
    fun sendAll(c: Context, ref: String, picks: List<Picked>, caption: String) {
        // an album is asked of the group whole, before its first row (G.5): its own rows are not the slow mode's last letter
        if (Groups.isKey(ref)) picks.firstNotNullOfOrNull { p -> refusal(c, ref, p, if (p === picks.firstOrNull()) caption else "") }
            ?.let { Groups.tellRefusal(it); return }
        // A FILE BETWEEN PICTURES ENDS THEIR PLATE (iOS MTStagedOrder.plates, 2312): pictures side by side fold, a file stands alone
        val slots = arrayOfNulls<MediaGroup.Slot>(picks.size)
        for (run in StagedOrder.plates(picks.map { it.kind == "doc" })) MediaGroup.slots(run.count()).forEachIndexed { j, s -> slots[run.first + j] = s }
        // THE TRAY LEAVES IN ITS ORDER, ONE AFTER ANOTHER (iOS MTSendLine, 2312, the author's word 25.10.2026 17:40 UTC): every row is
        // laid now, in the tray's order; the network work of each waits in the conversation's one line, so no file overtakes an earlier one
        picks.forEachIndexed { i, p -> send(c, ref, p, if (i == 0) caption else "", group = slots[i], gate = false, turn = "${i + 1}/${picks.size}") }
        Log.i("Montana", "tray_send n=${picks.size} files=${picks.count { it.kind == "doc" }} plates=${slots.filterNotNull().map { it.key }.toSet().size}")
    }
    /** What the group says to this media letter (Groups.mediaRefusal): by its kind, roundness, file name -- its extension at least -- and caption. */
    private fun refusal(c: Context, ref: String, p: Picked, caption: String): String? =
        Groups.mediaRefusal(c, ref, p.kind, p.round, p.name ?: ("." + p.ext), caption)

    /** The letter and the manifest it stands for (the sender keeps its own manifest: its row draws from it). */
    private fun seal(c: Context, p: Picked, caption: String, local: File, group: MediaGroup.Slot? = null, mid: String? = null): Pair<String, String>? {
        val bk = MtBindings.nativeRandom(32) ?: return null
        val total = p.bytes.size
        val count = maxOf(1, (total + CHUNK - 1) / CHUNK)
        val sealedPieces = ArrayList<Pair<String, ByteArray>>(count)
        val chunks = JSONArray()
        for (i in 0 until count) {
            val off = i * CHUNK
            val len = minOf(CHUNK, total - off)
            val piece = p.bytes.copyOfRange(off, off + len)
            val padded = piece.copyOf(padLen(len))
            val nonce = Wire.sha(bk, Wire.le8(i.toLong()), padded).copyOf(12)
            val sealed = MtBindings.nativeSealBlob(bk, nonce, padded) ?: return null
            val bid = Wire.hex(Wire.sha(sealed))
            sealedPieces.add(bid to sealed)
            chunks.put(JSONObject().put("bid", bid).put("cs", len))
        }
        // THE CARGO MARK (iOS uploadChunks): a function of the pieces' names, and «last» on the final piece.
        val cargo = Wire.hex(Wire.sha(sealedPieces.joinToString("") { it.first }.toByteArray())).take(32)
        sealedPieces.forEachIndexed { i, (bid, sealed) ->
            var ok = false
            for (attempt in 0 until 3) { if (Wire.putBlob(bid, sealed, cargo, i == sealedPieces.size - 1, assumeAbsent = attempt == 0)) { ok = true; break }; Thread.sleep(1500L shl attempt) }   // the key is this moment's: new at the first try, asked at a retry
            if (!ok) return null
            // EVERY PIECE THE NODE TOOK MOVES THE RING (iOS report, MontanaChatStore.swift:5163-5169): the share and the megabytes
            if (mid != null) ((i + 1f) / sealedPieces.size).let { Transfers.set(mid, it, Transfers.megabytes(it, total.toLong())) }
        }
        val m = JSONObject().put("k", p.kind).put("e", p.ext).put("bk", Base64.encodeToString(bk, Base64.NO_WRAP)).put("sz", total).put("chunks", chunks)
        p.name?.let { if (p.kind == "doc" || it == Stickers.CARD) m.put("n", it) }   // a sticker's picture names itself (iOS docName)
        if (caption.isNotEmpty()) m.put("cap", caption)
        p.du?.let { m.put("du", Math.round(it * 10) / 10.0) }   // the tape's length is the sender's word (iOS «du»)
        if (p.round) m.put("r", true)   // a round video note (iOS «r»)
        p.badge?.let { m.put("rb", it) }   // the dual note's badge corner -- tl, tr, bl or br (iOS «rb», MontanaMediaKit.swift:1093); old readers skip it
        // THE WAVE RIDES WITH THE LETTER (iOS «wv», MTWaveform.pack): one byte per line, 0…255.
        p.wave?.takeIf { it.isNotEmpty() }?.let { w -> m.put("wv", Base64.encodeToString(ByteArray(w.size) { (w[it] * 255).toInt().coerceIn(0, 255).toByte() }, Base64.NO_WRAP)) }
        preview(c, local, p.kind)?.let { b -> thumb(b)?.let { m.put("th", it) } }
        MediaGroup.stamp(m, group)   // the sender's word on the group, so the receiver folds the plate in the sender's order
        val json = m.toString()
        if ((Marks.MEDIA + json).toByteArray().size <= 1900) return (Marks.MEDIA + json) to json
        val mk = MtBindings.nativeRandom(32) ?: return null
        val sealed = Wire.seal(mk, json.toByteArray()) ?: return null
        val mbid = Wire.hex(Wire.sha(sealed))
        if (!Wire.putBlob(mbid, sealed, assumeAbsent = true, bulk = true)) return null   // sealed under a key drawn this moment: new by construction
        return (Marks.MEDIA + JSONObject().put("mref", mbid).put("mk", Base64.encodeToString(mk, Base64.NO_WRAP)).put("sz", total)) to json
    }

    // ── a file of a post on the node (iOS MTBoard.seal, MontanaBoard 2033-2052) ──
    private const val BLOB_SEED = "blobKeySeed"
    private val seedLock = Any()
    /**
     * THE LETTER'S KEY FROM ITS NAME (iOS letterBlobKey, MontanaMediaKit 146-161): SHA-256 of «mt-blob-key», the letter's name and this
     * phone's own seed -- the same file under the same name gives the same pieces, so a try again goes on where the node left it; the
     * node never sees the seed, so one file in two letters cannot be linked.
     */
    fun letterKey(letter: String): ByteArray? {
        val seed = synchronized(seedLock) {
            DeviceVault.get(BLOB_SEED)?.takeIf { it.size == 32 } ?: (MtBindings.nativeRandom(32) ?: return null).also { DeviceVault.set(BLOB_SEED, it) }
        }
        return Wire.sha("mt-blob-key".toByteArray(), letter.toByteArray(), seed)
    }
    /**
     * ONE FILE ON THE NODE, PIECE BY PIECE (iOS sealAndUpload and uploadChunks, MontanaMediaKit 233-276, MontanaWakePush 1705-1800):
     * sealed under its letter's key with the nonce drawn from the key, the piece's number and its bytes; the node asked what it holds
     * already when the cargo is more than two pieces; the rest laid under the cargo mark, «last» on the final piece, each piece counted
     * as the node confirms it. The key in base64 and the chunks a post's manifest carries; null -- a piece the node did not take.
     * A KEEPER'S KEY (iOS sealAndUpload 238-240, MontanaMediaKit): a post's keeper lays the same file under the post's own key -- the
     * same bytes, the same key, the same pieces give the same chunk names the post's manifest already carries.
     */
    fun layFile(f: File, letter: String, key: ByteArray? = null, confirmed: (Int) -> Unit): Pair<String, JSONArray>? {
        val bk = key ?: letterKey(letter) ?: return null
        val total = f.length()
        if (total <= 0L || Int.MAX_VALUE.toLong() < total) return null
        val count = ((total + CHUNK - 1) / CHUNK).toInt()
        return java.io.RandomAccessFile(f, "r").use { raf ->
            val bids = ArrayList<String>(count)
            val chunks = JSONArray()
            for (i in 0 until count) {
                val bid = sealPiece(raf, bk, i, total)?.first ?: return null
                bids.add(bid)
                chunks.put(JSONObject().put("bid", bid).put("cs", minOf(CHUNK.toLong(), total - i.toLong() * CHUNK).toInt()))
            }
            val cargo = Wire.hex(Wire.sha(bids.joinToString("").toByteArray())).take(32)
            // a cargo of a couple of pieces is put at once: the put is idempotent by name (iOS 1734-1736)
            val known = if (2 < count) Wire.blobsHave(bids) ?: emptySet() else emptySet()
            var done = known.size
            confirmed(done)
            for (i in 0 until count) {
                if (bids[i] in known) continue
                val sealed = sealPiece(raf, bk, i, total)?.second ?: return null
                var ok = false
                for (attempt in 0 until 4) {
                    if (Wire.putBlob(bids[i], sealed, cargo, i == count - 1, assumeAbsent = true)) { ok = true; break }
                    if (attempt < 3) Thread.sleep(1500L shl attempt)
                }
                if (!ok) return null
                done++
                confirmed(done)
            }
            Base64.encodeToString(bk, Base64.NO_WRAP) to chunks
        }
    }
    private fun sealPiece(raf: java.io.RandomAccessFile, bk: ByteArray, i: Int, total: Long): Pair<String, ByteArray>? {
        val off = i.toLong() * CHUNK
        val len = minOf(CHUNK.toLong(), total - off).toInt()
        val piece = ByteArray(len)
        raf.seek(off)
        raf.readFully(piece)
        val padded = piece.copyOf(padLen(len))
        val nonce = Wire.sha(bk, Wire.le8(i.toLong()), padded).copyOf(12)
        val sealed = MtBindings.nativeSealBlob(bk, nonce, padded) ?: return null
        return Wire.hex(Wire.sha(sealed)) to sealed
    }

    // ── receiving ──

    /** Every media letter of theirs still without its file is asked for (once at a time), and «delivered» follows the file. */
    fun fetchPending(c: Context) {
        val auto = autoAllowed(c)
        for (ch in Book.all()) for (m in ch.msgs) if (!m.mine && m.text.startsWith(Marks.MEDIA) && m.file == null) {
            // a file that waits for a tap still has its manifest read: its small face, its kind and its group stand at once
            if (auto) fetch(c, ch.ref, m.mid, m.text) else if (m.meta == null) learn(ch.ref, m.mid, m.text)
        }
    }

    /** The manifest alone (a small sealed blob, or the letter itself): kept with the row before any piece of the file. */
    private fun learn(ref: String, mid: String, text: String) {
        val key = "m:" + mid
        synchronized(inFlight) {
            val now = System.currentTimeMillis()
            if ((lastTry[key] ?: 0) > now - 60_000 || !inFlight.add(key)) return
            lastTry[key] = now
        }
        Thread {
            try { manifest(text)?.let { man -> keepManifest(ref, mid, man) } }
            catch (e: Exception) { Log.w("Montana", "media manifest: " + e.javaClass.simpleName) }
            finally { synchronized(inFlight) { inFlight.remove(key) } }
        }.start()
    }
    private fun keepManifest(ref: String, mid: String, man: JSONObject) =
        Book.edit(ref) { ch -> ch.msgs.find { it.mid == mid }?.let { if (it.meta == null) it.meta = man.toString() } }

    /**
     * AUTOMATIC DOWNLOAD FOR THE CONNECTION THE PHONE IS ON (iOS MontanaNet.autoDownloadAllowed): the mobile or the Wi-Fi switch of
     * «Data and storage», on by default. Off, an attachment waits for a tap (iOS queuePendingMedia: queued, so there is a tap).
     */
    fun autoAllowed(c: Context): Boolean {
        val cm = c.getSystemService(android.net.ConnectivityManager::class.java)
        val caps = cm?.getNetworkCapabilities(cm.activeNetwork)
        val cellular = caps?.hasTransport(android.net.NetworkCapabilities.TRANSPORT_CELLULAR) == true
        return Prefs.bool(if (cellular) "autoDownloadCellular" else "autoDownloadWiFi", true)
    }
    /** A letter of theirs whose file waits for a tap: no file here, and the switch of this connection is off. */
    fun waiting(c: Context, m: Msg): Boolean {
        // A FILE YOUR NODE KEEPS (iOS MTHomeKeep.want, 6f24f091): the cache cleared it, a look brings it back by the download
        // setting, else it waits for a tap as a letter's attachment does -- mine as well as theirs
        if (HomeKeep.kept(m.file)) { HomeKeep.want(c, m); return !autoAllowed(c) }
        return !m.mine && m.file?.let { File(it).exists() } != true && !autoAllowed(c)
    }
    /** The tap on a waiting attachment: its file is asked for now, whatever the switch (iOS: a tap starts the queued download). */
    fun tapped(c: Context, m: Msg) {
        if (HomeKeep.kept(m.file)) return HomeKeep.bring(c, m, force = true)   // iOS retryOneMedia: a file your node keeps comes back from it
        val ref = Book.rooms().firstOrNull { ch -> ch.msgs.any { it.mid == m.mid } }?.ref ?: return
        fetch(c, ref, m.mid, m.text, manual = true)
    }

    fun fetch(c: Context, ref: String, mid: String, text: String, manual: Boolean = false, own: Boolean = false) {
        if (!manual && !autoAllowed(c)) { Log.d("Montana", "media: automatic download is off -- the attachment waits for a tap"); return }
        synchronized(inFlight) {
            val now = System.currentTimeMillis()
            if ((lastTry[mid] ?: 0) > now - 60_000 || !inFlight.add(mid)) return
            lastTry[mid] = now
        }
        Thread {
            try {
                val man = manifest(text) ?: return@Thread
                // THE MANIFEST LANDS BEFORE THE FILE: the row folds into its group and shows its small face while the pieces travel
                keepManifest(ref, mid, man)
                val dest = file(c, mid, man.optString("e"))
                // HONEST RECEPTION (iOS MontanaChatStore.swift:4800-4813): the ring at once, then every piece that came moves it
                val size = man.optLong("sz")
                Transfers.set(mid, 0.01f)
                if (!download(man, dest) { f -> Transfers.set(mid, 0.01f + 0.99f * f, Transfers.megabytes(f, size)) }) {
                    // THE ROW STAYS, THE SENDER IS TOLD (iOS MontanaChatStore 4635-4649, atom aeabdc576605): a cargo every store called
                    // gone is knowledge -- the bubble stands without its file and the sender hears it once; a silent store is no verdict
                    val chunks = man.optJSONArray("chunks")
                    if (!own && !Groups.isKey(ref) && chunks != null && (0 until chunks.length()).any { Wire.isGone(chunks.getJSONObject(it).optString("bid")) }) Post.cargoLost(ref, mid)
                    return@Thread
                }
                landed(c, ref, mid, man, dest, own)
            } catch (e: Exception) { Log.w("Montana", "media fetch: ${e.javaClass.simpleName}") }
            finally { Transfers.set(mid, null); synchronized(inFlight) { inFlight.remove(mid) } }
        }.start()
    }

    /**
     * THE ONE «FILE IS WHOLE» POINT OF A LETTER (iOS mediaLanded): the download's end and a player's last piece (Streams) land here,
     * once -- the row takes its file, a sticker is kept, the receipt and the drop follow.
     */
    fun landed(c: Context, ref: String, mid: String, man: JSONObject, dest: File, own: Boolean) {
        var fresh = false
        synchronized(landing) {
            Book.edit(ref) { ch -> ch.msgs.find { it.mid == mid }?.let { fresh = it.file != dest.path; it.file = dest.path; it.meta = man.toString() } }
        }
        if (!fresh) return   // the other road landed it already
        // A STICKER THAT ARRIVED IS KEPT (iOS MontanaChatStore.swift:3608-3620 at 2155, atom 0d501f110022): the
        // receiver's panel holds what was used in the conversation, exactly as the sender's does -- one copy per
        // picture, since Stickers.add names a sticker by its own bytes and moves a known one to the front.
        if (man.optString("n") == Stickers.CARD) {
            runCatching { Stickers.add(c, dest.readBytes(), dest.extension) }
            StickerWire.enrich(ref, mid)   // the passport may have come before the picture: its quote settles here (iOS mediaLanded)
        }
        // a group's copy was receipted by the group (Groups.handle), and its pieces serve every other member of it
        // my other device's letter (Post.landOwn): the correspondent still fetches these pieces, the receipt is theirs to give
        if (!own && !Groups.isKey(ref)) { Post.receiptFor(ref, mid); drop(man) }
    }
    private val landing = Any()

    /**
     * THE FILE PIECE BY PIECE THROUGH ITS ONE LOADER (iOS MTStreamLoader, MontanaStream.swift): the pieces are laid where they
     * belong in «name.part» and counted in «name.have», so a download and a player reading the same file from its first pieces
     * (Streams) share every piece, and a download that stopped half-way goes on from what it already laid.
     */
    fun download(man: JSONObject, dest: File, came: (Float) -> Unit = {}): Boolean {
        val l = Streams.loader(dest, man) ?: return false
        for (i in 0 until l.count) {
            l.piece(i) ?: return false
            came((i + 1f) / l.count)
        }
        return dest.exists()
    }

    /**
     * One piece of a file, opened with its key, or null. WHEN it is asked is the lane's (Lane, iOS MTCargoLane): three pieces in
     * flight for the whole phone, the one a player waits for first.
     */
    fun bring(bid: String, bk: ByteArray, cs: Int, need: Lane.Need = Lane.Need.LOOK): ByteArray? {
        val sealed = Lane.bring(bid, need) ?: return null
        return Wire.open(bk, sealed)?.let { if (cs <= it.size) it.copyOf(cs) else it }
    }

    /** One sealed piece, its name checked against its bytes, or null -- every road tried with its own patience (iOS bringChunk). */
    fun fetch(bid: String): ByteArray? {
        // A PIECE OF ONE'S OWN NODE IS ASKED THERE AND ONLY THERE (iOS bringChunk, 6f24f091): the book names it (HomeBook);
        // the doors never carried it, and they never hear its name
        if (HomeBook.holds(bid)) {
            val sealed = Blobs.get(bid) ?: HomeShelf.get(bid)?.also { Blobs.put(bid, it) }
            if (sealed == null || Wire.hex(Wire.sha(sealed)) != bid) { Log.i("Montana", "home_get FAIL id=" + bid.take(8) + " -- your node did not give it"); return null }
            return sealed
        }
        // ONE PIECE WITH THE DOORS' OWN PATIENCE (iOS bringChunk, MontanaWakePush 2458-2487; atom aeabdc576605): a busy door is
        // waited for on a growing pause (0.7 s doubling, six tries); a silent road gets three quick tries; neither is «gone»
        var silentTries = 0; var busyTries = 0
        while (silentTries < 3 && busyTries < 6) {
            // an answer can finish exactly as a call begins: every retry stands behind the call (iOS bringChunk, MontanaCall.isBusy)
            var held = false
            while (Calls.busy()) {
                if (!held) { held = true; Log.d("Montana", "blob_dl held=call id=" + bid.take(8)) }
                Thread.sleep(1000)
            }
            // a piece a neighbour brought ahead of its manifest is assembled from this phone's own store (iOS MontanaBlobStore)
            val near = Blobs.get(bid)
            if (near == null && Wire.isGone(bid)) break   // every door called it gone: asked once, not every opening of the chat (iOS 2438)
            val busy = BooleanArray(1)
            val sealed = near ?: Wire.getChunk(bid, busy)
            if (sealed != null && Wire.hex(Wire.sha(sealed)) == bid) return sealed   // the name is the bytes: integrity
            if (Wire.isGone(bid)) break
            if (busy[0]) {
                val pause = 700L shl busyTries
                busyTries++
                Log.d("Montana", "blob_dl BUSY id=" + bid.take(8) + " — the node refuses this moment, pause=" + pause / 1000 + "s")
                Thread.sleep(pause)
            } else if (++silentTries < 3) Thread.sleep(700L)
        }
        return null
    }

    /** The file is assembled — the node's pieces serve nobody (iOS dropChunks), nor the ones a neighbour brought. */
    private fun drop(man: JSONObject) {
        val a = man.optJSONArray("chunks") ?: return
        val bids = JSONArray(); for (i in 0 until a.length()) bids.put(a.getJSONObject(i).optString("bid"))
        Blobs.drop((0 until bids.length()).map { bids.optString(it) })
        for (door in Doors.ordered("blob")) Wire.post(door, "/blob-drop", JSONObject().put("bids", bids), 8000)   // the drop goes to every store (iOS 1638)
    }

    // ── showing ──

    /**
     * THE PIECES A NEIGHBOUR BROUGHT (iOS MontanaBlobStore, MontanaP2PTelemetry 183-259): a manifest sent over the mesh rides with its
     * sealed pieces and the recipient assembles from its own store — a phone with no node at all still opens a neighbour's picture.
     * A piece lies under its name, the digest of its bytes; it is packaging: dropped once its file is whole, and any piece older than
     * a quarter hour goes at the next arrival (iOS graceSeconds 900, the bound of what nobody named).
     */
    object Blobs {
        private const val GRACE_MS = 900_000L
        private fun dir(): File? = runCatching { File(Book.ctx.filesDir, "Montana/Blobs").apply { mkdirs() } }.getOrNull()

        fun put(id: String, sealed: ByteArray) {
            if (id.length != 64 || Wire.hex(Wire.sha(sealed)) != id) return   // the name is the bytes
            val d = dir() ?: return
            val edge = System.currentTimeMillis() - GRACE_MS
            d.listFiles()?.forEach { if (it.lastModified() < edge) it.delete() }
            val f = File(d, id)
            if (!f.exists()) runCatching { f.writeBytes(sealed) }
        }

        fun get(id: String): ByteArray? {
            if (id.length != 64) return null
            val f = File(dir() ?: return null, id)
            return if (f.exists()) runCatching { f.readBytes() }.getOrNull() else null
        }

        fun drop(ids: List<String>) {
            val d = dir() ?: return
            for (id in ids) if (id.length == 64) File(d, id).delete()
        }
    }

    /** A picture fit for a bubble: the file sampled down, the first frame of a film, or null. */
    fun preview(c: Context, f: File, kind: String, maxPx: Int = 900): Bitmap? = runCatching {
        when (kind) {
            "img" -> {
                val o = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeFile(f.path, o)
                var s = 1; while (o.outWidth / (s * 2) >= maxPx || o.outHeight / (s * 2) >= maxPx) s *= 2
                // THE CAMERA'S TURN (EXIF orientation): a phone photo lies on its side in its bytes and says how to stand it up.
                BitmapFactory.decodeFile(f.path, BitmapFactory.Options().apply { inSampleSize = s })?.let { upright(f, it) }
            }
            "vid" -> ThumbnailUtils.createVideoThumbnail(f, Size(maxPx, maxPx), null)
            else -> null
        }
    }.getOrNull()

    /**
     * THE PICTURE STANDS AS IT WAS TAKEN: a camera writes the pixels as the sensor lies and the turn in the EXIF tag beside
     * them (iOS UIImage honours it by itself); the decoder here does not, so the turn — and a mirror — is applied here.
     */
    private fun upright(f: File, b: Bitmap): Bitmap {
        val o = runCatching { ExifInterface(f.path).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL) }
            .getOrDefault(ExifInterface.ORIENTATION_NORMAL)
        val m = Matrix()
        when (o) {
            ExifInterface.ORIENTATION_ROTATE_90 -> m.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> m.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> m.postRotate(270f)
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> m.postScale(-1f, 1f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> m.postScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> { m.postRotate(90f); m.postScale(-1f, 1f) }
            ExifInterface.ORIENTATION_TRANSVERSE -> { m.postRotate(270f); m.postScale(-1f, 1f) }
            else -> return b
        }
        return Bitmap.createBitmap(b, 0, 0, b.width, b.height, m, true)
    }

    fun thumbOf(man: JSONObject?): Bitmap? = man?.optString("th")?.takeIf { it.isNotEmpty() }?.let {
        runCatching { Base64.decode(it, Base64.DEFAULT) }.getOrNull()?.let { b -> BitmapFactory.decodeByteArray(b, 0, b.size) }
    }

    fun uri(c: Context, f: File): Uri = Uri.parse("content://${c.packageName}.media/${f.name}")
}

/**
 * THE APP'S OWN DOOR TO ITS FILES (the platform's ContentProvider, no library): a received file is handed to the system's
 * viewer or share sheet by a content address; only the media folder answers, read-only, and only with a granted address.
 */
class MediaProvider : ContentProvider() {
    override fun onCreate() = true
    private fun fileOf(uri: Uri): File? {
        val c = context ?: return null
        val name = uri.lastPathSegment ?: return null
        if (name.contains('/') || name.startsWith(".")) return null
        // A WALL'S FILE GOES BY THE SAME DOOR (iOS MTBoardDocPresenter, MontanaBoardViews.swift:1635-1650, and MTBoardMediaPage.share
        // 3100-3104 at 2155: the post's own file): it lies in the wall's store or in the look's folder, never among the chats' media --
        // «Open» and the share of a post's file found nothing here
        if (name.startsWith("wall_")) return listOf(MyWall.storeDir(c), Board.lookIn(c)).map { File(it, name) }.firstOrNull { it.exists() }
        return File(Media.dir(c), name).takeIf { it.exists() }
    }
    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor? {
        // A FILM NOT YET WHOLE (iOS MTStreamLoader's «montana-stream://» address): «stream/NAME» reads through the file's loader
        val seg = uri.pathSegments
        if (seg.size == 2 && seg[0] == "stream") {
            val c = context ?: return null
            File(Media.dir(c), seg[1]).takeIf { it.exists() }?.let { return ParcelFileDescriptor.open(it, ParcelFileDescriptor.MODE_READ_ONLY) }
            return Streams.descriptor(c, seg[1])
        }
        return fileOf(uri)?.let { ParcelFileDescriptor.open(it, ParcelFileDescriptor.MODE_READ_ONLY) }
    }
    override fun getType(uri: Uri): String? =
        uri.lastPathSegment?.substringAfterLast('.', "")?.let { MimeTypeMap.getSingleton().getMimeTypeFromExtension(it.lowercase()) }
    override fun query(uri: Uri, p: Array<out String>?, s: String?, a: Array<out String>?, o: String?): Cursor? {
        val f = fileOf(uri) ?: return null
        return android.database.MatrixCursor(arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)).apply { addRow(arrayOf<Any>(f.name, f.length())) }
    }
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, s: String?, a: Array<out String>?) = 0
    override fun update(uri: Uri, v: ContentValues?, s: String?, a: Array<out String>?) = 0
}

/**
 * THE ORDER CHOSEN IS THE ORDER SENT (iOS MTStagedOrder, 2312; the author's word 25.10.2026 17:40 UTC, council link 8089): what waits
 * above the field wears its place, 1, 2, 3; a cross takes one out and the numbers close up, because the number IS the place.
 */
object StagedOrder {
    /** The number a place wears: one more than its index. */
    fun number(index: Int) = index + 1
    /**
     * THE PERSON SETS THE ORDER (iOS MTStagedOrder.moved, 2315; the author's words 27.10.2026 09:16 UTC): a plate carried from `from`
     * stands at `to`, every other keeps its turn, and the numbers follow by construction. A place outside the tray changes nothing.
     */
    fun <T> moved(items: List<T>, from: Int, to: Int): List<T> {
        if (from !in items.indices || to !in items.indices || from == to) return items
        val a = items.toMutableList()
        a.add(to, a.removeAt(from))
        return a
    }
    /** The plates of a tray: a run of two or more pictures folds into one; a file (`true`) ends the run and stands alone. */
    fun plates(files: List<Boolean>): List<IntRange> {
        val out = ArrayList<IntRange>()
        var start = -1
        for ((i, file) in files.withIndex()) {
            if (!file) { if (start < 0) start = i }
            else if (0 <= start) { if (1 < i - start) out.add(start until i); start = -1 }
        }
        if (0 <= start && 1 < files.size - start) out.add(start until files.size)
        return out
    }
}

/**
 * ONE LINE OUT PER CONVERSATION (iOS MTSendLine, 2312): a file never overtakes an earlier one, whatever their sizes. Every send of a
 * tray stands in its conversation's line and starts when the one before it is over -- uploaded, refused, or left to the drain. The
 * rows are laid at once; only the network work waits its turn. Every other road keeps its own thread, as before.
 */
object SendLine {
    private val lines = HashMap<String, ArrayDeque<() -> Unit>>()
    fun enqueue(line: String, turn: () -> Unit) {
        val start = synchronized(lines) {
            val q = lines[line]
            if (q == null) { lines[line] = ArrayDeque(listOf(turn)); true } else { q.add(turn); false }
        }
        // one runner per line: it takes the turns from the head and leaves when the line is empty -- the next turn starts a new one
        if (start) Thread {
            var next: (() -> Unit)? = turn
            while (next != null) {
                val now = next
                runCatching { now() }.onFailure { Log.w("Montana", "send_line: a turn failed", it) }
                next = synchronized(lines) {
                    val q = lines.getValue(line)
                    q.removeFirst()
                    if (q.isEmpty()) { lines.remove(line); null } else q.first()
                }
            }
        }.start()
    }
    /** How many sends of the line are not over yet, the running one with them (the trace's word). */
    fun pending(line: String): Int = synchronized(lines) { lines[line]?.size ?: 0 }
}

/**
 * THE GROUP OF ONE PICK (iOS MTMediaGroup, MontanaMediaKit 1043-1076): pictures and films picked together leave under one key —
 * every letter carries the key, its place and the group's size (gk, gi, gn in the manifest); the caption rides with the first
 * letter only. Ten is the ceiling of a group; the eleventh picture of a pick opens the next key. Old readers skip the keys and
 * draw the letters one by one.
 */
object MediaGroup {
    const val CEILING = 10
    class Slot(val key: String, val index: Int, val count: Int)
    /** One key for the letters of one pick: sixteen hex digits of the phone's own randomness. */
    private fun mintKey(): String = Wire.hex(MtBindings.nativeRandom(8) ?: ByteArray(8).also { java.security.SecureRandom().nextBytes(it) })
    /** The slots of a whole pick under one fresh key; a pick of one is no group (every slot null). */
    fun slots(total: Int): List<Slot?> {
        if (total < 2) return List(total) { null }
        val key = mintKey()
        return List(total) { i ->
            val chunk = i / CEILING
            Slot(if (chunk == 0) key else key + "-" + chunk, i % CEILING, minOf(CEILING, total - chunk * CEILING))
        }
    }
    fun stamp(o: JSONObject, g: Slot?) { if (g != null) o.put("gk", g.key).put("gi", g.index).put("gn", g.count) }
    fun read(o: JSONObject?): Slot? = o?.optString("gk")?.takeIf { it.isNotEmpty() }?.let { Slot(it, o.optInt("gi"), o.optInt("gn")) }
    fun of(m: Msg): Slot? = read(Media.manifestOf(m))
}

/**
 * THE TRACK'S WAVE (iOS MTWaveform.compute, MontanaMediaKit 78-102): sixty point probes across the file -- only the probes are
 * decoded, never the whole file -- each the mean of every eighth sample of the first channel; scaled to a loud probe (the 92nd
 * percentile, not the loudest one clap), lifted by a soft curve (0.7). One definition of «this name is music» (mtIsAudioName).
 */
object Waveform {
    private const val BARS = 60
    fun isAudio(name: String) = name.substringAfterLast('.', "").lowercase() in setOf("mp3", "m4a", "aac", "wav", "flac", "aif", "aiff", "caf")
    fun compute(f: java.io.File): FloatArray? = runCatching {
        val ex = android.media.MediaExtractor()
        ex.setDataSource(f.path)
        val track = (0 until ex.trackCount).firstOrNull { ex.getTrackFormat(it).getString(android.media.MediaFormat.KEY_MIME)?.startsWith("audio/") == true }
            ?: return@runCatching null.also { ex.release() }
        ex.selectTrack(track)
        val fmt = ex.getTrackFormat(track)
        val durUs = if (fmt.containsKey(android.media.MediaFormat.KEY_DURATION)) fmt.getLong(android.media.MediaFormat.KEY_DURATION) else 0L
        if (durUs <= 0L) { ex.release(); return@runCatching null }
        val channels = if (fmt.containsKey(android.media.MediaFormat.KEY_CHANNEL_COUNT)) maxOf(1, fmt.getInteger(android.media.MediaFormat.KEY_CHANNEL_COUNT)) else 1
        val codec = android.media.MediaCodec.createDecoderByType(fmt.getString(android.media.MediaFormat.KEY_MIME)!!)
        codec.configure(fmt, null, null, 0)
        codec.start()
        val raw = FloatArray(BARS)
        val info = android.media.MediaCodec.BufferInfo()
        for (i in 0 until BARS) {
            ex.seekTo(durUs * i / BARS, android.media.MediaExtractor.SEEK_TO_CLOSEST_SYNC)
            codec.flush()
            var acc = 0.0; var cnt = 0; var frames = 0; var spins = 0
            while (frames < 4096 && spins < 64) {
                spins++
                val inIx = codec.dequeueInputBuffer(5_000)
                if (0 <= inIx) {
                    val buf = codec.getInputBuffer(inIx)!!
                    val n = ex.readSampleData(buf, 0)
                    if (n < 0) codec.queueInputBuffer(inIx, 0, 0, 0, android.media.MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                    else { codec.queueInputBuffer(inIx, 0, n, ex.sampleTime, 0); ex.advance() }
                }
                val outIx = codec.dequeueOutputBuffer(info, 5_000)
                if (0 <= outIx) {
                    val out = codec.getOutputBuffer(outIx)!!.order(java.nio.ByteOrder.LITTLE_ENDIAN).asShortBuffer()
                    val total = out.remaining() / channels
                    var j = 0
                    while (j < total && frames < 4096) {
                        if (j % 8 == 0) { acc += Math.abs(out.get(j * channels) / 32768.0); cnt++ }
                        j++; frames++
                    }
                    codec.releaseOutputBuffer(outIx, false)
                    if (info.flags and android.media.MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
                }
            }
            raw[i] = if (0 < cnt) (acc / cnt).toFloat() else 0f
        }
        codec.stop(); codec.release(); ex.release()
        val sorted = raw.sorted()
        val loud = maxOf(sorted[((sorted.size - 1) * 0.92).toInt()], 1e-6f)
        FloatArray(BARS) { Math.pow(minOf(1f, raw[it] / loud).toDouble(), 0.7).toFloat() }
    }.getOrNull()
}
