package quest.montana.app

import android.content.Context
import android.graphics.Color
import android.text.Editable
import android.text.InputType
import android.text.TextWatcher
import android.view.Gravity
import android.view.View
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ProgressBar

/**
 * THE NAME'S OWN PAGE (iOS NameSheet, MontanaProfile.swift 473-610 at 2155; the author's word 24.09: «bind pzr.me and assign the
 * names by it»). A person types the name after pzr.me/ exactly as the link will read; the consequence is said before the act; the
 * check mark takes it at the keeper of the order, and the page answers back only with a name the keeper recorded.
 */
object NameRules {
    /** Only whitespace trimmed, lowercased and the «@» dropped: a sign outside the set is NOT discarded — the refusal is said. */
    fun normalized(raw: String): String = raw.trim().lowercase().removePrefix("@")
    /** STRICTLY ASCII Latin: look-alike glyphs of other alphabets make visually identical yet different names (iOS rejection 506-517). */
    fun rejection(n: String): Int? {
        if (n.isEmpty()) return null
        if (!n.all { (it in 'a'..'z') || (it in '0'..'9') || it == '_' || it == '-' }) return R.string.name_latin
        if (n.length < 4) return R.string.name_short
        if (n.length > 32) return R.string.name_long
        if (n.first() !in 'a'..'z') return R.string.name_letter_first
        if (n.endsWith("_") || n.endsWith("-")) return R.string.name_sign_end
        if (listOf("__", "--", "_-", "-_").any { it in n }) return R.string.name_two_signs
        return null
    }
}

fun namePage(act: MainActivity, onTaken: (String) -> Unit, onClose: () -> Unit): View {
    val c: Context = act
    var busy = false
    var verdict: String? = null
    val footer = c.text("", 12f, MT.gray).apply { setPadding(c.dp(16), c.dp(8), c.dp(16), 0) }
    val field = EditText(c).apply {
        hint = c.getString(R.string.name_hint)
        setTextColor(Color.WHITE); setHintTextColor(MT.gray); background = null
        isSingleLine = true
        inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS or InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD
        imeOptions = EditorInfo.IME_ACTION_DONE
        setPadding(0, c.dp(12), c.dp(16), c.dp(12))
    }
    val done = c.icon(R.drawable.ic_check, Color.WHITE).apply { setPadding(c.dp(10), c.dp(10), c.dp(10), c.dp(10)) }
    val spinner = ProgressBar(c).apply { indeterminateTintList = android.content.res.ColorStateList.valueOf(MT.gray); visibility = View.GONE }
    val mark = android.widget.FrameLayout(c).apply {
        addView(done, android.widget.FrameLayout.LayoutParams(MATCH, MATCH))
        addView(spinner, android.widget.FrameLayout.LayoutParams(c.dp(22), c.dp(22), Gravity.CENTER))
    }
    fun drawFoot() {
        val held = Names.heldName
        val lapsed = if (held == null) Names.currentName else null
        footer.text = when {
            !verdict.isNullOrEmpty() -> verdict
            held != null -> Names.heldUntil?.let { u ->
                c.getString(R.string.name_held_until, held, java.text.DateFormat.getDateInstance(java.text.DateFormat.MEDIUM).format(java.util.Date((u * 1000).toLong())))
            } ?: c.getString(R.string.name_held, held)   // USER-DATA: my own name
            lapsed != null -> c.getString(R.string.name_lapsed, lapsed)
            else -> ""
        }
        footer.visibility = if (footer.text.isNullOrEmpty()) View.GONE else View.VISIBLE
        val can = !busy && NameRules.normalized(field.text.toString()).isNotEmpty()
        done.alpha = if (can) 1f else 0.4f
        done.visibility = if (busy) View.INVISIBLE else View.VISIBLE
        spinner.visibility = if (busy) View.VISIBLE else View.GONE
    }
    fun take() {
        val n = NameRules.normalized(field.text.toString())
        if (n.isEmpty() || busy) return
        NameRules.rejection(n)?.let { verdict = c.getString(it); drawFoot(); return }
        busy = true
        verdict = c.getString(R.string.name_taking)
        drawFoot()
        act.background {
            val out = NamePlane.take(n)
            act.onMain {
                busy = false
                verdict = when (out) {
                    is NamePlane.Taking.Taken -> null
                    NamePlane.Taking.Held -> c.getString(R.string.name_is_taken)
                    NamePlane.Taking.Full -> c.getString(R.string.name_full)
                    NamePlane.Taking.Busy -> c.getString(R.string.name_busy)
                    NamePlane.Taking.Unreachable -> c.getString(R.string.name_unreachable)
                    NamePlane.Taking.Refused -> c.getString(R.string.name_refused)
                }
                drawFoot()
                if (out is NamePlane.Taking.Taken) onTaken(out.name)
            }
        }
    }
    done.pressable { take() }
    field.setOnEditorActionListener { _, a, _ -> if (a == EditorInfo.IME_ACTION_DONE) { take(); true } else false }
    field.addTextChangedListener(object : TextWatcher {
        override fun afterTextChanged(s: Editable?) { drawFoot() }
        override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
        override fun onTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
    })
    // a section of words alone: its header over nothing and its footer under it (iOS Section {} header: footer:)
    fun LinearLayout.words(header: Int, foot: Int) {
        addView(c.text(c.getString(header), 13f, MT.gray).apply { setPadding(dp(16), dp(22), dp(16), dp(6)) }, lp())
        addView(c.text(c.getString(foot), 12f, MT.gray).apply { setPadding(dp(16), 0, dp(16), 0) }, lp())
    }
    val page = settingsPage(act, c.getString(R.string.name_title), onClose, cross = true, trailing = mark) {
        val row = c.hstack {
            gravity = Gravity.CENTER_VERTICAL
            minimumHeight = dp(44)
            setPadding(dp(16), 0, 0, 0)
            addView(c.text("pzr.me/", 17f, MT.gray))   // USER-DATA: the domain of the name's link — the same letters in every language
            addView(field, lp(0, WRAP, 1f))
        }
        section(null, null, row)
        addView(footer, lp())
        words(R.string.name_does_h, R.string.name_does_f)
        words(R.string.name_rules_h, R.string.name_rules_f)
        words(R.string.name_rights_h, R.string.name_rights_f)
        words(R.string.privacy, R.string.name_privacy_f)
    }
    drawFoot()
    field.post {
        field.requestFocus()
        c.getSystemService(InputMethodManager::class.java).showSoftInput(field, InputMethodManager.SHOW_IMPLICIT)
    }
    return page
}
