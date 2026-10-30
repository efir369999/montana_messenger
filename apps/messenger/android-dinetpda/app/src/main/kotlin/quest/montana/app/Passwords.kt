package quest.montana.app

import android.app.AlertDialog
import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Color
import android.os.Build
import android.os.PersistableBundle
import android.text.Editable
import android.text.InputType
import android.text.TextWatcher
import android.util.Base64
import android.view.Gravity
import android.view.View
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import org.json.JSONArray
import org.json.JSONObject
import java.security.SecureRandom
import java.util.UUID
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

// ─────────────────────────── passwords (iOS MTPasswords.swift, the author's word 06.10.2026 17:4x MSK) ───────────────────────────

/**
 * ONE SECRET (iOS MTSecretItem): a sign-in, a one-time code or a note. Every field rides the wire, as iOS's Codable writes and
 * reads it — a key missing is a letter iOS cannot read.
 */
class SecretItem(var id: String = UUID.randomUUID().toString().uppercase(), var kind: String = LOGIN, var title: String = "",
                 var site: String = "", var login: String = "", var password: String = "", var otp: String = "",
                 var note: String = "", var at: Double = System.currentTimeMillis() / 1000.0) {
    fun json(): JSONObject = JSONObject().put("id", id).put("kind", kind).put("title", title).put("site", site).put("login", login)
        .put("password", password).put("otp", otp).put("note", note).put("at", at)
    fun copy() = SecretItem(id, kind, title, site, login, password, otp, note, at)
    companion object {
        const val LOGIN = "login"; const val CODE = "code"; const val NOTE = "note"
        val KINDS = listOf(LOGIN, CODE, NOTE)
        fun of(o: JSONObject) = SecretItem(o.optString("id"), o.optString("kind", LOGIN).takeIf { it in KINDS } ?: LOGIN, o.optString("title"),
            o.optString("site"), o.optString("login"), o.optString("password"), o.optString("otp"), o.optString("note"), o.optDouble("at", 0.0))
        fun kindWord(kind: String) = when (kind) { CODE -> R.string.pw_code_kind; NOTE -> R.string.pw_note_kind; else -> R.string.pw_login_kind }
        fun kindGlyph(kind: String) = when (kind) { CODE -> R.drawable.ic_otp; NOTE -> R.drawable.ic_set_doc; else -> R.drawable.ic_key }
    }
}

/**
 * THE ONE OWNER OF THE SECRETS on this phone (iOS MTPasswordVault): read and written whole, sealed by the device's own key
 * (DeviceVault), shown only after the device owner's own check (OwnerCheck) — an absent check is a failed one.
 */
object PasswordVault {
    private const val KEY = "mt.passwords"
    var items: List<SecretItem> = emptyList(); private set
    var unlocked = false; private set
    var refused = false; private set
    private val listeners = mutableListOf<() -> Unit>()
    fun listen(l: () -> Unit) { listeners.add(l) }
    fun unlisten(l: () -> Unit) { listeners.remove(l) }
    private fun changed() = listeners.toList().forEach { it() }

    fun unlock(act: MainActivity, then: (() -> Unit)? = null) {
        if (unlocked) { then?.invoke(); return }
        OwnerCheck.ask(act, act.getString(R.string.pw_reason)) { word ->
            act.onMain {
                when (word) {
                    OwnerWord.CONFIRMED -> { items = read().sortedBy { it.title.lowercase() }; unlocked = true; refused = false; changed(); then?.invoke() }
                    OwnerWord.NO_LOCK -> { refused = true; changed() }
                    OwnerWord.FAILED -> changed()
                }
            }
        }
    }
    fun lock() { items = emptyList(); unlocked = false }
    fun save(item: SecretItem) {
        if (!unlocked) return
        val kept = item.copy().apply { at = System.currentTimeMillis() / 1000.0 }
        write(items.filter { it.id != kept.id } + kept)
    }
    fun remove(id: String) { if (unlocked) write(items.filter { it.id != id }) }
    private fun write(all: List<SecretItem>) {
        val a = JSONArray(); all.forEach { a.put(it.json()) }
        if (!DeviceVault.set(KEY, a.toString().toByteArray(Charsets.UTF_8))) return
        items = all.sortedBy { it.title.lowercase() }
        changed()
    }
    private fun read(): List<SecretItem> = DeviceVault.get(KEY)?.let { raw ->
        runCatching { JSONArray(String(raw, Charsets.UTF_8)).let { a -> List(a.length()) { SecretItem.of(a.getJSONObject(it)) } } }.getOrNull()
    } ?: emptyList()
    fun wipe() { lock(); DeviceVault.delete(KEY) }
}

/** ONE-TIME CODES (iOS MTOneTimeCode, RFC 6238 over RFC 4226): the key as base32 or an otpauth:// link, the code of the window now. */
object OneTimeCode {
    class Spec(val key: ByteArray, val digits: Int, val period: Int, val algorithm: String)
    fun spec(raw: String): Spec? {
        val text = raw.trim()
        if (text.lowercase().startsWith("otpauth://")) {
            val u = runCatching { android.net.Uri.parse(text) }.getOrNull() ?: return null
            val q = u.queryParameterNames.associateBy({ it.lowercase() }, { u.getQueryParameter(it) ?: "" })
            val key = base32(q["secret"] ?: "") ?: return null
            return Spec(key, q["digits"]?.toIntOrNull() ?: 6, q["period"]?.toIntOrNull() ?: 30, (q["algorithm"] ?: "SHA1").uppercase())
        }
        return base32(text)?.let { Spec(it, 6, 30, "SHA1") }
    }
    /** RFC 4648, as iOS reads it (the same window of bits, signs and spaces skipped). */
    private fun base32(text: String): ByteArray? {
        val alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        var value = 0; var bits = 0
        val out = java.io.ByteArrayOutputStream()
        for (ch in text.uppercase()) {
            if (ch == '=' || ch == ' ' || ch == '-') continue
            val i = alphabet.indexOf(ch).takeIf { it >= 0 } ?: return null
            value = ((value shl 5) or i) and 0xFFFF
            bits += 5
            if (bits >= 8) { out.write((value shr (bits - 8)) and 0xFF); bits -= 8 }
        }
        return out.toByteArray().takeIf { it.isNotEmpty() }
    }
    fun code(s: Spec, nowSec: Long = System.currentTimeMillis() / 1000): String {
        val counter = nowSec / maxOf(1, s.period)
        val msg = ByteArray(8) { i -> (counter ushr (8 * (7 - i))).toByte() }
        val name = when (s.algorithm) { "SHA256" -> "HmacSHA256"; "SHA512" -> "HmacSHA512"; else -> "HmacSHA1" }
        val mac = Mac.getInstance(name).apply { init(SecretKeySpec(s.key, name)) }.doFinal(msg)
        val at = mac[mac.size - 1].toInt() and 0x0F
        val bin = ((mac[at].toInt() and 0x7F) shl 24) or ((mac[at + 1].toInt() and 0xFF) shl 16) or ((mac[at + 2].toInt() and 0xFF) shl 8) or (mac[at + 3].toInt() and 0xFF)
        val digits = s.digits.coerceIn(6, 8)
        var modulus = 1; repeat(digits) { modulus *= 10 }
        return (bin % modulus).toString().padStart(digits, '0')
    }
    fun left(s: Spec, nowSec: Long = System.currentTimeMillis() / 1000) = s.period - (nowSec % maxOf(1, s.period)).toInt()
}

/** iOS MTPasswordGenerator: twenty characters drawn without bias; a copy for this device alone, gone in ninety seconds. */
object PasswordGenerator {
    private const val ALPHABET = "abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789-_.!?#"
    fun fresh(length: Int = 20): String {
        val limit = 256 - 256 % ALPHABET.length
        val r = SecureRandom()
        val out = StringBuilder()
        while (out.length < length) { val b = r.nextInt(256); if (b < limit) out.append(ALPHABET[b % ALPHABET.length]) }
        return out.toString()
    }
    fun copy(c: Context, value: String) {
        val cm = c.getSystemService(ClipboardManager::class.java) ?: return
        val clip = ClipData.newPlainText("", value)
        // the platform keeps a sensitive copy out of its own previews (Android 13); the copy leaves the board after ninety seconds
        if (Build.VERSION.SDK_INT >= 33) clip.description.extras = PersistableBundle().apply { putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true) }
        cm.setPrimaryClip(clip)
        MainThread.later(90_000, Runnable {
            val now = runCatching { cm.primaryClip?.getItemAt(0)?.text?.toString() }.getOrNull()
            if (now == value) runCatching { if (Build.VERSION.SDK_INT >= 28) cm.clearPrimaryClip() else cm.setPrimaryClip(ClipData.newPlainText("", "")) }
        })
    }
}

/**
 * A SECRET SHARED INTO A CHAT (iOS MTSecretLetter): the key glyph and the title on the first line, the machine line under it;
 * it rides the chat's own letter road, end to end, and every preview of it names no title and no content.
 */
object SecretLetter {
    private const val LINK = "montana://secret/1/"
    private const val KEY = "\uD83D\uDD11 "
    fun text(item: SecretItem): String {
        val shared = item.copy().apply { id = "" }
        val code = Base64.encodeToString(shared.json().toString().toByteArray(Charsets.UTF_8), Base64.NO_WRAP).replace('+', '-').replace('/', '_')
        return KEY + item.title + "\n" + LINK + code
    }
    fun parse(text: String): SecretItem? {
        if (!text.startsWith(KEY) || text.toByteArray().size > 65_536) return null
        val line = text.split("\n").last().takeIf { it.startsWith(LINK) } ?: return null
        val code = line.removePrefix(LINK).replace('-', '+').replace('_', '/')
        val o = runCatching { JSONObject(String(Base64.decode(code, Base64.DEFAULT), Charsets.UTF_8)) }.getOrNull() ?: return null
        return SecretItem.of(o).apply { id = UUID.randomUUID().toString().uppercase() }
    }
    /** The list's and the banner's words for it (iOS MTRowLetter.preview): no title, no content. */
    fun isOne(text: String) = text.startsWith(KEY) && text.contains(LINK)
}

// ── the pages ──

private fun barOf(c: Context, title: String, lead: Int, onLead: () -> Unit, vararg marks: Pair<Int, () -> Unit>): FrameLayout = FrameLayout(c).apply {
    setPadding(c.dp(8), 0, c.dp(8), 0)
    addView(c.icon(lead, Color.WHITE).apply { setPadding(c.dp(10), c.dp(10), c.dp(10), c.dp(10)); pressable(onLead) },
        FrameLayout.LayoutParams(c.dp(44), c.dp(44), Gravity.CENTER_VERTICAL or Gravity.START))
    addView(c.text(title, 17f, Color.WHITE, bold = true, center = true).apply { singleLineEllipsis() },   // USER-DATA: a secret's title may stand here
        FrameLayout.LayoutParams(WRAP, WRAP, Gravity.CENTER).apply { marginStart = c.dp(100); marginEnd = c.dp(100) })
    addView(c.hstack { marks.forEach { (g, work) -> addView(c.icon(g, Color.WHITE).apply { setPadding(c.dp(10), c.dp(10), c.dp(10), c.dp(10)); pressable(work) }, lp(c.dp(44), c.dp(44))) } },
        FrameLayout.LayoutParams(WRAP, WRAP, Gravity.CENTER_VERTICAL or Gravity.END))
}
private fun frameOf(c: Context, bar: View, body: View): View = FrameLayout(c).apply {
    setBackgroundColor(Color.BLACK)
    addView(c.chatGround(ChatWall.PAGE), FrameLayout.LayoutParams(MATCH, MATCH))
    addView(c.vstack(Gravity.NO_GRAVITY) { addView(bar, lp(MATCH, c.dp(52))); addView(ScrollView(c).apply { addView(body) }, lp(MATCH, 0, 1f)) },
        FrameLayout.LayoutParams(MATCH, MATCH))
}.keepsSecret()   // no screenshot, no recording, black in the recent apps while a secret stands

/** The code of the window now, turning with its period, and the seconds left (iOS MTCodeLive). */
private fun codeLive(c: Context, s: OneTimeCode.Spec, size: Float): TextView {
    val t = c.text("", size, Color.WHITE, bold = true).apply { typeface = android.graphics.Typeface.MONOSPACE }
    val tick = object : Runnable {
        override fun run() {
            if (!t.isAttachedToWindow && t.tag == "gone") return
            t.text = OneTimeCode.code(s) + "  " + OneTimeCode.left(s)   // USER-DATA: the one-time code of this moment
            MainThread.later(1000, this)
        }
    }
    t.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(v: View) { t.tag = null; tick.run() }
        override fun onViewDetachedFromWindow(v: View) { t.tag = "gone" }
    })
    return t
}

/** THE APP'S PAGE (iOS MTPasswordsPage): the secrets by kind, searched, each with its own page; the plus writes a new one. */
fun passwordsPage(act: MainActivity, onClose: () -> Unit): View {
    val c: Context = act
    val body = c.vstack(Gravity.NO_GRAVITY) { setPadding(dp(16), 0, dp(16), dp(32)) }
    var query = ""
    lateinit var draw: () -> Unit
    val search = EditText(c).apply {
        hint = c.getString(R.string.search); setTextColor(Color.WHITE); setHintTextColor(MT.gray)
        background = c.rounded(Color.argb(61, 118, 118, 128), 10); setPadding(c.dp(12), c.dp(8), c.dp(12), c.dp(8)); isSingleLine = true
        addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
            override fun onTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
            override fun afterTextChanged(s: Editable?) { query = s?.toString()?.trim() ?: ""; draw() }
        })
    }
    val plus = c.icon(R.drawable.ic_plus, Color.WHITE).apply {
        setPadding(c.dp(10), c.dp(10), c.dp(10), c.dp(10))
        contentDescription = c.getString(R.string.pw_new)
        pressable { act.push { close -> secretEditor(act, SecretItem(), close) } }
    }
    val bar = barOf(c, c.getString(R.string.pw_title), R.drawable.ic_close, { PasswordVault.lock(); onClose() })
    bar.addView(plus, FrameLayout.LayoutParams(c.dp(44), c.dp(44), Gravity.CENTER_VERTICAL or Gravity.END))
    draw = {
        body.removeAllViews()
        plus.visibility = if (PasswordVault.unlocked) View.VISIBLE else View.GONE
        if (!PasswordVault.unlocked) {
            body.addView(c.vstack(Gravity.CENTER_HORIZONTAL) {
                setPadding(dp(16), dp(40), dp(16), dp(24))
                addView(c.icon(R.drawable.ic_set_lock, MT.gray, 44), lp(dp(44), dp(44)))
                gap(14)
                addView(c.text(c.getString(if (PasswordVault.refused) R.string.pw_no_lock else R.string.pw_locked), 13f, MT.gray, center = true), lp())
                if (!PasswordVault.refused) {
                    gap(14)
                    addView(c.text(c.getString(R.string.pw_unlock), 17f, Color.WHITE, bold = true, center = true).apply {
                        background = c.rounded(SysColor.blue, 12); setPadding(dp(20), dp(12), dp(20), dp(12))
                        pressable { PasswordVault.unlock(act) }
                    }, lp(WRAP, WRAP))
                }
            }, lp())
        } else {
            body.addView(search, lp()); body.gap(8)
            val shown = PasswordVault.items.filter { e -> query.isEmpty() || listOf(e.title, e.site, e.login, e.note).any { it.contains(query, ignoreCase = true) } }
            if (PasswordVault.items.isEmpty()) body.section(null, null, c.text(c.getString(R.string.pw_none), 15f, MT.gray).apply { setPadding(dp(16), dp(14), dp(16), dp(14)) })
            for (kind in SecretItem.KINDS) {
                val rows = shown.filter { it.kind == kind }
                if (rows.isEmpty()) continue
                body.section(c.getString(SecretItem.kindWord(kind)), null, *rows.map { e ->
                    val row = c.hstack {
                        gravity = Gravity.CENTER_VERTICAL
                        setPadding(dp(16), dp(8), dp(16), dp(8)); minimumHeight = dp(52)
                        addView(c.icon(SecretItem.kindGlyph(e.kind), Color.WHITE, 22), lp(dp(30), dp(22)).apply { marginEnd = dp(12) })
                        addView(c.vstack(Gravity.NO_GRAVITY) {
                            addView(c.text(e.title.ifEmpty { e.site.ifEmpty { "—" } }, 16f, Color.WHITE).apply { singleLineEllipsis() }, lp())   // USER-DATA: the secret's title
                            if (e.login.isNotEmpty()) addView(c.text(e.login, 12f, MT.gray).apply { singleLineEllipsis() }, lp())   // USER-DATA: the login
                        }, lp(0, WRAP, 1f))
                        if (e.kind == SecretItem.CODE) OneTimeCode.spec(e.otp)?.let { addView(codeLive(c, it, 15f), lp(WRAP, WRAP)) }
                        pressable { act.push { close -> secretDetail(act, e.id, close) } }
                    }
                    SwipeRow(act, row, listOf(Tile(R.drawable.ic_delete, red = true) { PasswordVault.remove(e.id) }))
                }.toTypedArray())
            }
        }
    }
    val again: () -> Unit = { draw() }
    val page = frameOf(c, bar, body)
    page.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(v: View) { PasswordVault.listen(again); draw(); PasswordVault.unlock(act) }
        override fun onViewDetachedFromWindow(v: View) { PasswordVault.unlisten(again) }
    })
    return page
}

/** ONE SECRET'S OWN PAGE (iOS MTSecretDetail): every field copied by a tap, the password shown on asking, the code live. */
private fun secretDetail(act: MainActivity, id: String, onBack: () -> Unit): View {
    val c: Context = act
    val body = c.vstack(Gravity.NO_GRAVITY) { setPadding(dp(16), 0, dp(16), dp(32)) }
    var shown = false
    lateinit var draw: () -> Unit
    fun field(label: Int, value: String, mono: Boolean = false) = c.hstack {
        gravity = Gravity.CENTER_VERTICAL; setPadding(dp(16), dp(12), dp(16), dp(12))
        addView(c.text(c.getString(label), 16f, Color.WHITE), lp(0, WRAP, 1f))
        addView(c.text(value, 16f, MT.gray).apply { singleLineEllipsis(); if (mono) typeface = android.graphics.Typeface.MONOSPACE }, lp(WRAP, WRAP))   // USER-DATA: a field of the secret
        pressable { PasswordGenerator.copy(c, value) }
    }
    val title = c.text("", 17f, Color.WHITE, bold = true, center = true)
    val bar = barOf(c, "", R.drawable.ic_arrow_back_ios_new, onBack,
        R.drawable.ic_share to { PasswordVault.items.firstOrNull { it.id == id }?.let { e -> act.push { close -> secretShare(act, e, close) } } },
        R.drawable.ic_pencil to { PasswordVault.items.firstOrNull { it.id == id }?.let { e -> act.push { close -> secretEditor(act, e.copy(), close) } } })
    draw = {
        body.removeAllViews()
        val e = PasswordVault.items.firstOrNull { it.id == id }
        (bar.getChildAt(1) as TextView).text = e?.title ?: ""
        if (e != null) {
            val rows = mutableListOf<View>()
            if (e.site.isNotEmpty()) rows += field(R.string.pw_site, e.site)
            if (e.login.isNotEmpty()) rows += field(R.string.pw_login, e.login)
            if (e.password.isNotEmpty()) {
                rows += c.hstack {
                    gravity = Gravity.CENTER_VERTICAL; setPadding(dp(16), dp(12), dp(16), dp(12))
                    addView(c.text(c.getString(R.string.pw_password), 16f, Color.WHITE), lp(0, WRAP, 1f))
                    addView(c.text(if (shown) e.password else "••••••••••", 16f, MT.gray).apply { typeface = android.graphics.Typeface.MONOSPACE }, lp(WRAP, WRAP))   // USER-DATA: the password, shown on asking
                    pressable { PasswordGenerator.copy(c, e.password) }
                }
                rows += c.hstack {
                    gravity = Gravity.CENTER_VERTICAL; setPadding(dp(16), dp(12), dp(16), dp(12))
                    addView(c.icon(if (shown) R.drawable.ic_set_eye_slash else R.drawable.ic_set_eye, SysColor.blue, 20), lp(dp(20), dp(20)).apply { marginEnd = dp(10) })
                    addView(c.text(c.getString(if (shown) R.string.pw_hide else R.string.pw_show), 16f, SysColor.blue), lp(0, WRAP, 1f))
                    pressable { shown = !shown; draw() }
                }
            }
            OneTimeCode.spec(e.otp)?.let { s ->
                rows += c.hstack {
                    gravity = Gravity.CENTER_VERTICAL; setPadding(dp(16), dp(12), dp(16), dp(12))
                    addView(c.text(c.getString(R.string.pw_code), 16f, Color.WHITE), lp(0, WRAP, 1f))
                    addView(codeLive(c, s, 20f), lp(WRAP, WRAP))
                    pressable { PasswordGenerator.copy(c, OneTimeCode.code(s)) }
                }
            }
            if (e.note.isNotEmpty()) rows += c.vstack(Gravity.NO_GRAVITY) {
                setPadding(dp(16), dp(12), dp(16), dp(12))
                addView(c.text(c.getString(R.string.pw_note_kind), 14f, Color.WHITE), lp())
                addView(c.text(e.note, 16f, MT.gray).apply { setTextIsSelectable(true) }, lp())   // USER-DATA: the note its owner wrote
            }
            body.section(null, c.getString(R.string.pw_copy_note), *rows.toTypedArray())
            body.section(null, null, c.text(c.getString(R.string.delete), 16f, SysColor.red).apply {
                setPadding(dp(16), dp(14), dp(16), dp(14))
                pressable {
                    AlertDialog.Builder(c).setTitle(R.string.pw_delete_q)
                        .setPositiveButton(R.string.delete) { _, _ -> PasswordVault.remove(id); onBack() }
                        .setNegativeButton(R.string.cancel, null).show()
                }
            })
        }
    }
    val again: () -> Unit = { draw() }
    val page = frameOf(c, bar, body)
    page.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(v: View) { PasswordVault.listen(again); draw() }
        override fun onViewDetachedFromWindow(v: View) { PasswordVault.unlisten(again) }
    })
    return page
}

/** A NEW SECRET OR A CHANGED ONE (iOS MTSecretEditor): the kind, and the fields the kind holds; the die draws a password. */
private fun secretEditor(act: MainActivity, item: SecretItem, onBack: () -> Unit): View {
    val c: Context = act
    val body = c.vstack(Gravity.NO_GRAVITY) { setPadding(dp(16), dp(8), dp(16), dp(32)) }
    fun input(hint: Int, value: String, type: Int, lines: Int = 1, set: (String) -> Unit) = EditText(c).apply {
        setText(value)   // USER-DATA: a field of the secret
        this.hint = c.getString(hint); setTextColor(Color.WHITE); setHintTextColor(MT.gray); background = null
        inputType = type; if (lines > 1) { minLines = 3; maxLines = lines } else isSingleLine = true
        setPadding(c.dp(16), c.dp(12), c.dp(16), c.dp(12))
        addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
            override fun onTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
            override fun afterTextChanged(s: Editable?) { set(s?.toString() ?: "") }
        })
    }
    lateinit var draw: () -> Unit
    draw = {
        body.removeAllViews()
        // the kind as the platform's segmented choice (iOS Picker .segmented)
        body.addView(c.hstack {
            background = c.rounded(Color.argb(61, 118, 118, 128), 9); setPadding(dp(2), dp(2), dp(2), dp(2))
            for (k in SecretItem.KINDS) addView(c.text(c.getString(SecretItem.kindWord(k)), 13f, Color.WHITE, bold = item.kind == k, center = true).apply {
                if (item.kind == k) background = c.rounded(Color.argb(110, 118, 118, 128), 7)
                setPadding(dp(6), dp(7), dp(6), dp(7))
                pressable { item.kind = k; draw() }
            }, lp(0, WRAP, 1f))
        }, lp())
        body.gap(12)
        val rows = mutableListOf<View>()
        val plain = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
        rows += input(R.string.pw_name, item.title, InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES) { item.title = it }
        if (item.kind == SecretItem.LOGIN) {
            rows += input(R.string.pw_site, item.site, InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_URI) { item.site = it }
            rows += input(R.string.pw_login, item.login, plain) { item.login = it }
            val pw = input(R.string.pw_password, item.password, InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD) { item.password = it }
            rows += c.hstack {
                gravity = Gravity.CENTER_VERTICAL
                addView(pw, lp(0, WRAP, 1f))
                addView(c.icon(R.drawable.ic_dice, Color.WHITE, 22).apply {
                    setPadding(dp(11), dp(11), dp(11), dp(11)); contentDescription = c.getString(R.string.pw_generate)
                    pressable { item.password = PasswordGenerator.fresh(); pw.setText(item.password) }
                }, lp(dp(44), dp(44)).apply { marginEnd = dp(8) })
            }
        }
        if (item.kind != SecretItem.NOTE) rows += input(R.string.pw_otp_key, item.otp, plain) { item.otp = it }
        rows += input(R.string.pw_note_kind, item.note, InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES, lines = 8) { item.note = it }
        body.section(null, if (item.kind != SecretItem.NOTE) c.getString(R.string.pw_otp_note) else null, *rows.toTypedArray())
    }
    draw()
    val bar = barOf(c, c.getString(R.string.pw_new), R.drawable.ic_close, onBack, R.drawable.ic_check to { PasswordVault.save(item); onBack() })
    return frameOf(c, bar, body)
}

/** SHARING INTO A CHAT (iOS MTSecretShareSheet): the person's own chats with a pipe; a tap sends the secret as a letter of that chat. */
private fun secretShare(act: MainActivity, item: SecretItem, onBack: () -> Unit): View {
    val c: Context = act
    val chats = chatRows().filter { Book.secret(SamePair.root(it.ref)) != null }
    val rows = chats.map { ch ->
        c.hstack {
            gravity = Gravity.CENTER_VERTICAL; setPadding(dp(16), dp(8), dp(16), dp(8)); minimumHeight = dp(52)
            addView(c.peerFace(ch.ref, ch.shown, 40), lp(dp(40), dp(40)).apply { marginEnd = dp(12) })
            addView(c.text(ch.shown.ifBlank { c.getString(R.string.peer) }, 17f, Color.WHITE).apply { singleLineEllipsis() }, lp(0, WRAP, 1f))   // USER-DATA: the name
            pressable { sendWords(ch.ref, SecretLetter.text(item)); onBack() }
        }
    }.ifEmpty { listOf(c.text(c.getString(R.string.pw_no_chats), 15f, MT.gray).apply { setPadding(c.dp(16), c.dp(14), c.dp(16), c.dp(14)) }) }
    val body = c.vstack(Gravity.NO_GRAVITY) { setPadding(dp(16), 0, dp(16), dp(32)) }
    body.section(c.getString(R.string.pw_share_with), c.getString(R.string.pw_share_note), *rows.toTypedArray())
    return frameOf(c, barOf(c, c.getString(R.string.share), R.drawable.ic_close, onBack), body)
}

/** A SECRET A CORRESPONDENT SHARED (iOS MTSecretSaveSheet): what it holds, saved into the person's own Passwords after the owner's check. */
fun secretSavePage(act: MainActivity, item: SecretItem, onBack: () -> Unit): View {
    val c: Context = act
    fun line(label: Int, value: String) = c.hstack {
        gravity = Gravity.CENTER_VERTICAL; setPadding(dp(16), dp(12), dp(16), dp(12))
        addView(c.text(c.getString(label), 16f, Color.WHITE), lp(0, WRAP, 1f))
        addView(c.text(value, 16f, MT.gray).apply { singleLineEllipsis() }, lp(WRAP, WRAP))   // USER-DATA: the shared secret's field
    }
    val rows = listOfNotNull(line(R.string.pw_name, item.title), item.site.takeIf { it.isNotEmpty() }?.let { line(R.string.pw_site, it) },
        item.login.takeIf { it.isNotEmpty() }?.let { line(R.string.pw_login, it) })
    val body = c.vstack(Gravity.NO_GRAVITY) { setPadding(dp(16), dp(8), dp(16), dp(32)) }
    body.section(null, null, *rows.toTypedArray())
    val bar = barOf(c, c.getString(R.string.pw_save), R.drawable.ic_close, onBack,
        R.drawable.ic_check to { PasswordVault.unlock(act) { PasswordVault.save(item); onBack() } })
    return frameOf(c, bar, body)
}

/** THE SECRET'S BUBBLE (iOS MontanaBubble 711-729): the key and the title; the receiver's tap takes it into their own Passwords. */
fun Context.secretPlate(act: MainActivity?, item: SecretItem, mine: Boolean): View = hstack {
    gravity = Gravity.CENTER_VERTICAL
    addView(icon(R.drawable.ic_key, BubbleStyle.text(mine), 26), lp(dp(26), dp(26)).apply { marginEnd = dp(12) })
    addView(vstack(Gravity.NO_GRAVITY) {
        addView(text(item.title, 16f, BubbleStyle.text(mine), bold = true).apply { maxLines = 2 }, lp(WRAP, WRAP))   // USER-DATA: the shared secret's title
        addView(text(getString(if (mine) R.string.pw_shared_from else R.string.pw_tap_save), 14f, BubbleStyle.text(mine)), lp(WRAP, WRAP))
    }, lp(WRAP, WRAP))
    if (!mine && act != null) pressable { act.push { close -> secretSavePage(act, item, close) } }
}
