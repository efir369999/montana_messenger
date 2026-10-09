package quest.montana.app

import android.content.Context
import android.util.Base64
import android.util.Log
import org.json.JSONObject

/**
 * THE ONE MEETING RESOLVER (iOS MontanaMeeting + MontanaCard.expand/meet + MontanaFirstContact.meet), the scanner's side:
 *   a link names an invitation → the card is fetched from the node under it and opened (or it answers «spent») →
 *   one encapsulation to the card's key, the first secret, the pipe born, the chat standing with the card's name and face →
 *   the pipe's own face laid beside it → the first letter the person writes rides the invitation's box carrying the
 *   ciphertext (iOS wakeRdv), and every letter after it does too, until the other side answers under the pipe.
 * One link, one conversation: a repeated scan returns to the chat it opened (the scan book), one card root, one pipe.
 */
object Meeting {
    sealed class Outcome {
        class Opened(val ref: String) : Outcome()
        object Spent : Outcome()
        object Refused : Outcome()
        object Nameless : Outcome()
        object OwnName : Outcome()   // one's own name opens nothing: a correspondence with oneself is a ghost in both books
    }
    /** The words a meeting that did not open says — the scanner's and the link road's alike (iOS ScanMeetingView 519-522). */
    fun verdict(o: Outcome): Int = when (o) {
        Outcome.Spent -> R.string.invite_spent
        Outcome.Nameless -> R.string.invite_nameless
        Outcome.OwnName -> R.string.invite_own_name
        else -> R.string.invite_refused
    }

    private const val FIRSTS = "pipeFirst"     // ref → {ct, inv}: the introduction still unanswered
    private const val SCANS = "rdvScanned"     // invitation → ref (iOS scanBook)
    private const val CARDS = "cardMetByRoot"  // card root → ref (iOS cardBook)
    private val gate = Any()

    private fun jmap(name: String): JSONObject = DeviceVault.get(name)?.let { runCatching { JSONObject(String(it, Charsets.UTF_8)) }.getOrNull() } ?: JSONObject()
    private fun jsave(name: String, o: JSONObject) = DeviceVault.set(name, o.toString().toByteArray())

    /** The ciphertext and the invitation the next letter to `ref` must carry, while the introduction is unanswered. */
    fun first(ref: String): Pair<ByteArray, ByteArray>? = synchronized(gate) {
        val o = jmap(FIRSTS).optJSONObject(ref) ?: return null
        val ct = runCatching { Base64.decode(o.getString("ct"), Base64.NO_WRAP) }.getOrNull() ?: return null
        val inv = runCatching { Base64.decode(o.getString("inv"), Base64.NO_WRAP) }.getOrNull() ?: return null
        ct to inv
    }

    /** The card root an unanswered introduction knocks at (iOS MTPipeBook.root(for:)): the card book read backwards. */
    fun root(ref: String): ByteArray? = synchronized(gate) {
        if (!jmap(FIRSTS).has(ref)) return null
        val m = jmap(CARDS)
        m.keys().asSequence().firstOrNull { m.optString(it) == ref }?.let { MontanaCard.unb64url(it) }?.takeIf { it.size == 1184 }
    }

    /** The roots of every introduction still unanswered (iOS MTPipeBook.roots): points this phone listens at too. */
    fun awaitingRoots(): List<ByteArray> = synchronized(gate) {
        val f = jmap(FIRSTS); val m = jmap(CARDS)
        m.keys().asSequence().filter { f.has(m.optString(it)) }.mapNotNull { MontanaCard.unb64url(it) }.filter { it.size == 1184 }.toList()
    }

    /** The other side wrote under the pipe: the introduction is over, the ciphertext is spent (iOS firstContactDone). */
    /**
     * A WORD OF THEIRS ENDS THE INTRODUCTION ON EVERY ROAD (iOS build 1961, 26.09: T3 kept a peer in the introduction while their name
     * and face kept arriving, and held its letters behind it): the box's letter and the lane's word alike; the queue that waited for
     * the pipe leaves at once. True when this word ended it.
     */
    fun firstDone(ref: String): Boolean {
        val ended = synchronized(gate) { val m = jmap(FIRSTS); m.has(ref).also { if (it) { m.remove(ref); jsave(FIRSTS, m) } } }
        if (ended) { Log.i("Montana", "first_done the pipe stands — the queue leaves now"); Thread { Post.flush() }.start() }
        return ended
    }

    fun forget(ref: String) = synchronized(gate) {
        for (name in listOf(SCANS, CARDS)) {
            val m = jmap(name); val dead = m.keys().asSequence().filter { m.optString(it) == ref }.toList()
            if (dead.isNotEmpty()) { dead.forEach { m.remove(it) }; jsave(name, m) }
        }
        firstDone(ref)
    }
    fun wipe() { listOf(FIRSTS, SCANS, CARDS).forEach(DeviceVault::delete) }
    /** A root this phone met a person by (iOS MontanaMeeting.cardMet(root:)): a name heard before may stand from memory. */
    fun metAtRoot(root: ByteArray): Boolean = synchronized(gate) { jmap(CARDS).optString(MontanaCard.b64url(root)).isNotEmpty() }

    /** A folded conversation's cards and links open the older one (iOS MontanaMeeting.repoint). */
    fun repoint(newer: String, older: String) = synchronized(gate) {
        for (name in listOf(SCANS, CARDS)) {
            val m = jmap(name); val moved = m.keys().asSequence().filter { m.optString(it) == newer }.toList()
            if (moved.isNotEmpty()) { moved.forEach { m.put(it, older) }; jsave(name, m) }
        }
    }
    /** The pipes this phone begot by a scan (the card book's conversations). */
    fun metByScan(): Set<String> = synchronized(gate) { jmap(CARDS).let { m -> m.keys().asSequence().map { m.optString(it) }.filter { it.isNotEmpty() }.toSet() } }

    // ── the link ──

    /** The link as a messenger may have mangled it: percent bytes, glued punctuation, a capitalised scheme (iOS normalizeLink). */
    fun normalize(s: String): String {
        var raw = s.trim()
        if (raw.contains('%')) raw = runCatching { java.net.URLDecoder.decode(raw, "UTF-8") }.getOrDefault(raw)
        while (raw.isNotEmpty() && ".,;:!?)]}>»›\"'’”…".contains(raw.last())) raw = raw.dropLast(1)
        val i = raw.indexOf("://")
        if (i > 0) raw = raw.substring(0, i).lowercase() + raw.substring(i)
        return raw
    }

    /** ONE CARD, ONE NODE, TWO SITES (iOS MontanaCard.linkHosts / readPrefixes, 07.10.2026): the Business writes its invitations
     *  on montana.xxx; this app writes montana.quest and reads the /r/, /perp/ and /temp/ forms of both sites. */
    private val linkHosts = setOf("montana.quest", "montana.xxx", "www.montana.xxx")
    private val shortForms = linkHosts.sorted().flatMap { h -> listOf("r", "perp", "temp").map { "https://" + h + "/" + it + "/" } } + "montana://r/"
    /** The 32-byte invitation inside a short link, or null (iOS MontanaCard.invite(inShort:)). */
    fun invite(link: String): ByteArray? {
        val t = normalize(link)
        val form = shortForms.firstOrNull { t.startsWith(it) } ?: return null
        val code = t.removePrefix(form).substringBefore('?').substringBefore('#').trimEnd('/')
        return MontanaCard.unb64url(code)?.takeIf { it.size == 32 }
    }
    /**
     * A FACE IS FETCHED FROM THE NODE, NOT WAITED FOR (iOS healFacesFromCards → MontanaCard.refaceFromCard, atom
     * 796a76a34ae0): the same blob the first meeting fetches (face(inv) below), asked again for a correspondent
     * already met but still faceless, by their last daily link (Book.healFacesFromCards) -- off the main thread, as
     * every network ask here is.
     */
    fun healFace(ref: String, link: String) {
        val inv = invite(link) ?: return
        Thread { face(inv)?.let { Book.face(ref).writeBytes(it); Book.edit(ref) {} } }.start()
    }
    /** A whole card in the link (the old long form montana://c/…): the key and the name themselves. */
    private fun longCard(link: String): ByteArray? {
        val t = normalize(link)
        if (!t.startsWith("montana://c/")) return null
        return MontanaCard.unb64url(t.removePrefix("montana://c/"))?.takeIf { it.size in 1184..(1184 + 64) }
    }
    /**
     * THE NAME INSIDE AN INVITATION (iOS name(inInvitation:), MontanaFirstContact.swift 154-164): pzr.me and the name, in every shape
     * a link takes on the way — or the scheme form; a query, a fragment or a closing slash are no part of a name, and a second path
     * segment means it is not one. Normalized as the set normalizes it, or null.
     */
    fun nameIn(link: String): String? {
        var t = link.trim()
        val low = t.lowercase()
        val form = listOf("https://pzr.me/", "https://www.pzr.me/", "http://pzr.me/", "http://www.pzr.me/", "pzr.me/", "www.pzr.me/", "montana://")
            .firstOrNull { low.startsWith(it) } ?: return null
        t = t.substring(form.length).substringBefore('?').substringBefore('#').removeSuffix("/")
        if (t.isEmpty() || '/' in t) return null
        return Names.normalize(t)
    }
    private fun isName(link: String): Boolean = nameIn(link) != null
    fun looksLikeInvitation(text: String) = invite(text) != null || longCard(text) != null || isName(text)

    // ── the meeting ──

    /** Meets whatever was handed over; the network is asked, so this runs off the main thread. */
    fun meet(c: Context, link: String): Outcome {
        nameIn(link)?.let { return meetName(it) }
        val inv = invite(link)
        val payload: ByteArray = if (inv != null) {
            val inv64 = MontanaCard.b64url(inv)
            // A REPEATED SCAN OF THE SAME CODE returns into the conversation it opened (iOS meet_rescan).
            synchronized(gate) { jmap(SCANS).optString(inv64).takeIf { it.isNotEmpty() && Book.secret(it) != null } }?.let { known ->
                // THE CARD BEHIND A REPEATED LINK IS RE-READ (iOS MontanaFirstContact.swift fc367faf0575 meet_rescan/
                // renameFromCard:1166, fea4e68ea0da refaceFromCard:1174; measured 16:35: the same link opened the same
                // empty chat under the callsign of the first scan, and the card behind it — by then wearing the
                // person's current name and face — was never looked at again). The chat opens at once; the name and
                // the face are fetched beside, as the weakest witness (never past a dated word).
                Thread {
                    expand(inv)?.takeIf { p -> !p.contentEquals(SPENT) && p.size > 1184 }?.let { p ->
                        val nm = String(p, 1184, p.size - 1184, Charsets.UTF_8).trim()
                        if (nm.isNotEmpty() && Book.admitState(known, "name", 0L)) Book.edit(known) { it.name = stripCrown(nm) }
                    }
                    face(inv)?.let { Book.face(known).writeBytes(it); Book.edit(known) {} }
                }.start()
                return Outcome.Opened(known)
            }
            // The card's own invitations are not a meeting with oneself.
            if (MontanaCard.outstandingInvites().any { it.contentEquals(inv) }) return Outcome.Refused
            expand(inv) ?: return Outcome.Refused
        } else longCard(link) ?: return Outcome.Refused
        if (payload.contentEquals(SPENT)) return Outcome.Spent
        val root = payload.copyOf(1184)
        val name = if (payload.size > 1184) String(payload, 1184, payload.size - 1184, Charsets.UTF_8).trim() else ""
        // ONE ROOT, ONE TUNNEL (iOS cardBook): whatever door the same card came by, the same chat.
        val root64 = MontanaCard.b64url(root)
        synchronized(gate) { jmap(CARDS).optString(root64).takeIf { it.isNotEmpty() && Book.secret(it) != null } }?.let { known ->
            if (inv != null) synchronized(gate) { jsave(SCANS, jmap(SCANS).put(MontanaCard.b64url(inv), known)) }
            if (name.isNotEmpty() && Book.admitState(known, "name", 0L)) Book.edit(known) { it.name = stripCrown(name) }   // a card is undated: never over the peer's dated word
            // THE FACE RIDES BESIDE THE NAME ON THIS ROOT TOO (iOS fea4e68ea0da refaceFromCard:1174, the «card-book»/«root» branches).
            if (inv != null) Thread { face(inv)?.let { Book.face(known).writeBytes(it); Book.edit(known) {} } }.start()
            return Outcome.Opened(known)
        }
        // One encapsulation, and the correspondence exists; the ciphertext waits for the first letter (iOS MontanaCard.meet).
        val o = MtBindings.nativeMlkemEncaps(root) ?: return Outcome.Refused
        val ct = o.copyOf(1088); val ss = o.copyOfRange(1088, 1120)
        val secret = MtBindings.nativeFirstSecret(ss, root, ct) ?: return Outcome.Refused
        ss.fill(0); o.fill(0)
        val ref = Book.establish(secret) ?: return Outcome.Refused
        synchronized(gate) {
            if (inv != null) jsave(FIRSTS, jmap(FIRSTS).put(ref, JSONObject().put("ct", Base64.encodeToString(ct, Base64.NO_WRAP)).put("inv", Base64.encodeToString(inv, Base64.NO_WRAP))))
            if (inv != null) jsave(SCANS, jmap(SCANS).put(MontanaCard.b64url(inv), ref))
            jsave(CARDS, jmap(CARDS).put(root64, ref))
        }
        val perm = inv != null && isPermanent(inv)
        Book.open(ref, stripCrown(name), perm)
        if (inv != null) Thread { face(inv)?.let { Book.face(ref).writeBytes(it); Book.edit(ref) {} } }.start()
        Thread { layPipeFace(secret) }.start()
        // ONE PERSON, ONE CONVERSATION (iOS MTSamePair.ask): whether we already share a pipe is asked at once — the silent
        // first letter, which carries the card's ciphertext to its owner.
        SamePair.ask(ref)
        return Outcome.Opened(ref)
    }

    /**
     * A MEETING BY NAME (iOS MontanaMeeting meetOnce .name, MontanaFirstContact.swift 1767-1814): the plane of names answers the contact
     * key, ONE ROOT ONE TUNNEL as for a card, then one encapsulation; the correspondence wears the name, stays in the book as a
     * permanent link does, and its first letters go to the point of the name's root — a name has no invitation's box (iOS outgoingTag).
     */
    private fun meetName(n: String): Outcome {
        if (n == Names.currentName) { Log.d("Montana", "meet_refused why=own-name"); return Outcome.OwnName }
        val root = when (val a = NamePlane.resolve(n)) {
            is NamePlane.Answer.Found -> a.root
            NamePlane.Answer.Unknown -> { Log.d("Montana", "meet_refused why=name-unknown"); return Outcome.Nameless }
            NamePlane.Answer.Unreachable -> { Log.d("Montana", "meet_refused why=name-unreachable"); return Outcome.Refused }
        }
        val root64 = MontanaCard.b64url(root)
        synchronized(gate) { jmap(CARDS).optString(root64).takeIf { it.isNotEmpty() && Book.secret(it) != null } }?.let { known ->
            Log.d("Montana", "meet_rescan name-book")
            return Outcome.Opened(known)
        }
        val o = MtBindings.nativeMlkemEncaps(root) ?: return Outcome.Refused
        val ct = o.copyOf(1088); val ss = o.copyOfRange(1088, 1120)
        val secret = MtBindings.nativeFirstSecret(ss, root, ct) ?: return Outcome.Refused
        ss.fill(0); o.fill(0)
        val ref = Book.establish(secret) ?: return Outcome.Refused
        synchronized(gate) {
            jsave(FIRSTS, jmap(FIRSTS).put(ref, JSONObject().put("ct", Base64.encodeToString(ct, Base64.NO_WRAP)).put("inv", "")))
            jsave(CARDS, jmap(CARDS).put(root64, ref))
        }
        Book.open(ref, n, true)   // the name's link keeps the person in the book, as the permanent link it stands in for does
        Thread { layPipeFace(secret) }.start()
        SamePair.ask(ref)   // one person, one conversation: the same question, by name
        return Outcome.Opened(ref)
    }

    private val SPENT = "mt-rdv-spent".toByteArray()

    /** The card under an invitation, opened; SPENT for a tombstone; null when no door gave it (iOS expand, four tries). */
    private fun expand(inv: ByteArray): ByteArray? {
        val bid = MontanaCard.rdvBid(inv); val key = MontanaCard.rdvKey(inv)
        repeat(4) { attempt ->
            Wire.getBlob(bid)?.let { sealed ->
                Wire.open(key, sealed)?.let { p ->
                    if (p.contentEquals(SPENT)) return SPENT
                    if (p.size in 1184..(1184 + 64)) return p
                }
            }
            if (attempt < 3) Thread.sleep(900)
        }
        Log.w("Montana", "meet: the invitation did not unfold")
        return null
    }
    /** The face the inviter laid beside the card (iOS MontanaCard.face). */
    private fun face(inv: ByteArray): ByteArray? {
        val sealed = Wire.getBlob(MontanaCard.faceBid(inv)) ?: return null
        return Wire.open(MontanaCard.faceKey(inv), sealed)?.takeIf { it.isNotEmpty() && it.size <= 262_144 }
    }
    /** Was the link a permanent one? The mark beside the card says so (iOS isPermanent). */
    private fun isPermanent(inv: ByteArray): Boolean {
        val sealed = Wire.getBlob(MontanaCard.permBid(inv)) ?: return false
        return Wire.open(MontanaCard.rdvKey(inv), sealed)?.contentEquals("mt-rdv-perm".toByteArray()) == true
    }
    /** THE FACE BESIDE THE PIPE (iOS layPipeFace): under a name and a seal only the two of them derive; empty says «no face». */
    private fun layPipeFace(secret: ByteArray) {
        val face = SelfFace.bytes(Book.ctx) ?: ByteArray(0)
        val bid = Wire.hex(Wire.sha("mt-pipe-f".toByteArray() + byteArrayOf(0), secret))
        val key = Wire.sha("mt-pipe-fk".toByteArray() + byteArrayOf(0), secret)
        Wire.seal(key, face)?.let { sealed -> Signal.writeOrder("blob").any { d ->
            Wire.post(d, "/blob-put", JSONObject().put("bid", bid).put("data", Base64.encodeToString(sealed, Base64.NO_WRAP)).put("over", true), 30_000).first == 200
        } }
    }

    // ── the first letter ──

    /**
     * THE FIRST-MEETING LETTER (iOS wakeRdv): [ct 1088][mid‖0 text‖0 name‖0 glyph‖0 conf‖0], padded to 1536, sealed under the
     * invitation's letter key of this minute, boxed under the invitation's daily label. `conf` is the key confirmation the
     * owner's box road demands (MontanaFirstContact.firstConfirm).
     */
    fun knockFirst(secret: ByteArray, ct: ByteArray, inv: ByteArray, mid: String, text: String, silent: Boolean = false): Boolean {
        val twin = MontanaSeed.twin ?: return false
        val conf = MontanaCard.b64url(Wire.sha("mt-first-conf".toByteArray() + byteArrayOf(0), secret, ct).copyOf(16))
        var body = ct
        for (f in listOf(mid, text, Prefs.userName.trim(), "", conf)) body += f.toByteArray() + byteArrayOf(0)
        if (body.size > 1536) return false
        body += ByteArray(1536 - body.size)
        val letterKey = Wire.rdvLetterSecret(inv)
        val cw = Wire.rdvConvW(inv, Wire.day())
        for (door in Signal.writeOrder("box")) {   // the elected door first (iOS 1638)
            val env = Wire.seal(Wire.bodyKey(letterKey, Wire.minute()), body) ?: return false
            val (code, _) = Wire.post(door, "/wake", JSONObject().put("conv", cw).put("from_id", Wire.subId(cw, twin)).put("mid", mid)
                .put("env", Base64.encodeToString(env, Base64.NO_WRAP)).apply { if (silent) put("silent", true) })   // a service word: no banner
            if (code == 200) { Signal.doorAnswered(door); return true }
            Signal.doorFailed(door, code)
        }
        return false
    }
}


/** The person handed a link in: the meeting runs off the main thread, and the person is answered aloud (iOS resolveInvite, verdict). */
fun openInvitation(act: MainActivity, link: String) {
    act.background {
        val o = Meeting.meet(act, link)
        act.onMain {
            when (o) {
                // a pipe folded into a conversation is never opened as a page of its own (iOS meet → MTSamePair.root)
                is Meeting.Outcome.Opened -> act.push { close -> conversationPage(act, SamePair.root(o.ref), close) }
                else -> sayVerdict(act, Meeting.verdict(o))
            }
        }
    }
}

/** THE VERDICT STANDS UNTIL IT IS READ (iOS montanaMeetVerdict: an alert with its OK over the whole app): a passing word was gone before
 *  a person who looked away from the screen had read why the meeting did not open. */
fun sayVerdict(act: MainActivity, words: Int) {
    android.app.AlertDialog.Builder(act).setMessage(words).setPositiveButton(R.string.ok, null).show()
}
