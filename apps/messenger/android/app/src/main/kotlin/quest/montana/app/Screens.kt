package quest.montana.app

import android.app.AlertDialog
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.ImageDecoder
import android.net.Uri
import android.text.Editable
import android.text.InputFilter
import android.text.TextWatcher
import android.view.Gravity
import android.view.View
import android.view.animation.DecelerateInterpolator
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.PopupMenu
import android.widget.ScrollView
import android.widget.TextView
import java.io.File

// ─────────────────────────── the face (iOS MontanaSelfFace) ───────────────────────────

object SelfFace {
    private fun file(ctx: Context) = File(ctx.filesDir, "avatar.jpg")
    fun load(ctx: Context): Bitmap? = file(ctx).takeIf { it.exists() }?.let { BitmapFactory.decodeFile(it.path) }
    fun clear(ctx: Context) { file(ctx).delete() }
    /** The face as it travels (iOS avatarData): the JPEG itself, or null when there is none. */
    fun bytes(ctx: Context): ByteArray? = file(ctx).takeIf { it.exists() }?.readBytes()

    /** The picked photo, read for the crop: no side past 2048 pixels, so a camera original fits in memory. */
    fun decode(ctx: Context, uri: Uri): Bitmap? = try {
        ImageDecoder.decodeBitmap(ImageDecoder.createSource(ctx.contentResolver, uri)) { d, info, _ ->
            d.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            val big = maxOf(info.size.width, info.size.height)
            if (big > 2048) d.setTargetSampleSize((big + 2047) / 2048)
        }
    } catch (e: Exception) { null }

    /** The face the crop rendered (640×640 JPEG) becomes the face. */
    fun set(ctx: Context, jpeg: ByteArray): Boolean = try {
        file(ctx).writeBytes(jpeg); true
    } catch (e: Exception) { false }
}

/** A page's top bar: an optional back mark on the left, a title, an optional mark on the right. */
fun Context.topBar(title: String? = null, onBack: (() -> Unit)? = null, trailing: View? = null) = FrameLayout(this).apply {
    setPadding(dp(8), 0, dp(8), 0)
    if (onBack != null) addView(icon(R.drawable.ic_arrow_back_ios_new, Color.WHITE).apply {
        setPadding(dp(10), dp(10), dp(10), dp(10)); pressable(onBack)
    }, FrameLayout.LayoutParams(dp(44), dp(44), Gravity.CENTER_VERTICAL or Gravity.START))
    if (title != null) addView(text(title, 17f, Color.WHITE, bold = true, center = true),
        FrameLayout.LayoutParams(WRAP, WRAP, Gravity.CENTER))
    if (trailing != null) addView(trailing, FrameLayout.LayoutParams(WRAP, WRAP, Gravity.CENTER_VERTICAL or Gravity.END))
    layoutParams = LinearLayout.LayoutParams(MATCH, dp(52))
}

// ─────────────────────────── the name (iOS ProfileView) ───────────────────────────

class Profile(private val act: MainActivity, private val onboarding: Boolean, private val onFinish: () -> Unit) {
    val view = FrameLayout(act)
    private var name = Prefs.userName
    private lateinit var nameField: EditText
    private lateinit var faceSlot: FrameLayout
    private lateinit var photoRowText: TextView
    private var bioField: EditText? = null
    private var linkField: EditText? = null

    init { showEditor() }

    private fun showEditor() {
        val c = act
        view.removeAllViews()
        view.setBackgroundColor(Color.BLACK)   // the editor's own ground (iOS: black under the page), over the first screens' picture
        act.back = if (onboarding) null else ({ done() })
        val col = c.vstack(Gravity.NO_GRAVITY) {
            addView(c.topBar(trailing = c.icon(R.drawable.ic_check, Color.rgb(204, 204, 204)).apply {
                setPadding(dp(10), dp(10), dp(10), dp(10)); pressable { done() }
            }.also { it.layoutParams = FrameLayout.LayoutParams(dp(44), dp(44)) }))
            val body = c.vstack(Gravity.NO_GRAVITY) {
                setPadding(dp(16), 0, dp(16), dp(16))
                // ── the face ──
                faceSlot = FrameLayout(c)
                addView(faceSlot, lp(MATCH, dp(122)))
                refreshFace()
                gap(16)
                // ── the photo, in the page's own plate ──
                addView(c.plate {
                    val row = c.hstack {
                        setPadding(dp(16), dp(14), dp(16), dp(14))
                        addView(c.icon(R.drawable.ic_photo, Color.WHITE), lp(dp(26), dp(24)).apply { marginEnd = dp(12) })
                        photoRowText = c.text("", 17f, Color.WHITE)
                        addView(photoRowText, lp(0, WRAP, 1f))
                    }
                    row.pressable { pickFace() }
                    addView(row, lp())
                    // MY PAGE'S GROUND (iOS «Change page background», the author's word 25.09): the chat's own chooser with the
                    // page's task; the page's ground is every page's and every chat's on «Same as my page»
                    if (!onboarding) {
                        divider()
                        addView(c.hstack {
                            setPadding(dp(16), dp(14), dp(16), dp(14))
                            addView(c.icon(R.drawable.ic_photo, Color.WHITE), lp(dp(26), dp(24)).apply { marginEnd = dp(12) })
                            addView(c.text(c.getString(R.string.pg_change), 17f, Color.WHITE), lp(0, WRAP, 1f))
                            pressable { act.push { close -> wallpaperPicker(act, ChatWall.PAGE, close) } }
                        }, lp())
                    }
                }, lp())
                refreshPhotoRow()
                gap(16)
                // ── first name + the call sign ──
                addView(c.plate {
                    nameField = EditText(c).apply {
                        setText(name); hint = c.getString(R.string.first_name)
                        setTextColor(Color.WHITE); setHintTextColor(MT.gray); background = null
                        isSingleLine = true
                        filters = arrayOf(InputFilter.LengthFilter(64))   // first name: 64 characters (iOS)
                        setPadding(dp(16), dp(14), dp(16), dp(14))
                        addTextChangedListener(object : TextWatcher {
                            override fun afterTextChanged(s: Editable?) { name = s.toString(); refreshFace() }
                            override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
                            override fun onTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
                        })
                    }
                    addView(nameField, lp())
                    divider()
                    val row = c.hstack {
                        setPadding(dp(16), dp(14), dp(16), dp(14))
                        addView(c.icon(R.drawable.ic_badge, Color.WHITE), lp(dp(26), dp(24)).apply { marginEnd = dp(12) })
                        addView(c.text(c.getString(R.string.choose_callsign), 17f), lp(0, WRAP, 1f))
                        addView(c.icon(R.drawable.ic_chevron_right, MT.gray))
                    }
                    row.pressable { showCallsigns() }
                    addView(row, lp())
                }, lp())
                // ── BIO AND LINK (iOS ProfileView, the author's word 24.09): the platform's own fields in the page's own rows ──
                if (!onboarding) {
                    gap(16)
                    addView(c.plate {
                        bioField = EditText(c).apply {
                            setText(Prefs.str("profileBio", "")); hint = c.getString(R.string.pf_bio)
                            setTextColor(Color.WHITE); setHintTextColor(MT.gray); background = null
                            inputType = android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_FLAG_MULTI_LINE or android.text.InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
                            maxLines = 4
                            filters = arrayOf(InputFilter.LengthFilter(MyAbout.BIO_LIMIT))
                            setPadding(dp(16), dp(14), dp(16), dp(14))
                        }
                        addView(bioField, lp())
                        divider()
                        linkField = EditText(c).apply {
                            setText(Prefs.str("profileLink", "")); hint = c.getString(R.string.pf_link)
                            setTextColor(Color.WHITE); setHintTextColor(MT.gray); background = null
                            isSingleLine = true
                            inputType = android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_VARIATION_URI
                            filters = arrayOf(InputFilter.LengthFilter(PeerAbout.LINK_LIMIT))
                            setPadding(dp(16), dp(14), dp(16), dp(14))
                        }
                        addView(linkField, lp())
                    }, lp())
                    addView(c.text(c.getString(R.string.pf_about_footer), 13f, MT.gray).apply { setPadding(dp(16), dp(8), dp(16), 0) })
                }
                if (onboarding) {
                    addView(c.text(c.getString(R.string.profile_onboarding_footer), 13f, MT.gray).apply {
                        setPadding(dp(16), dp(8), dp(16), 0)
                    })
                }
            }
            addView(ScrollView(c).apply { addView(body) }, lp(MATCH, 0, 1f))
        }
        view.addView(col, FrameLayout.LayoutParams(MATCH, MATCH))
    }

    private fun refreshFace() {
        faceSlot.removeAllViews()
        val a = act.avatar(SelfFace.load(act), name, 110)
        a.pressable { if (SelfFace.load(act) == null) pickFace() else faceMenu(a) }
        faceSlot.addView(a, FrameLayout.LayoutParams(act.dp(110), act.dp(110), Gravity.CENTER))
    }

    private fun refreshPhotoRow() {
        photoRowText.text = act.getString(if (SelfFace.load(act) == null) R.string.choose_photo else R.string.change_photo)
    }

    /** No photo — the system photo picker; a photo — the system menu with two outcomes. */
    private fun faceMenu(anchor: View) {
        PopupMenu(act, anchor).apply {
            menu.add(0, 1, 0, R.string.change_photo)
            menu.add(0, 2, 1, R.string.remove_photo)
            setOnMenuItemClickListener {
                if (it.itemId == 1) pickFace() else { SelfFace.clear(act); refreshFace(); refreshPhotoRow() }
                true
            }
            show()
        }
    }

    /** The system picker, then the crop: the circle decides what the face keeps (iOS: PhotosPicker → MTAvatarCropView). */
    private fun pickFace() = act.pickPhoto { uri ->
        val image = uri?.let { SelfFace.decode(act, it) } ?: return@pickPhoto
        lateinit var close: () -> Unit
        close = act.overlay(cropPage(act, image) { jpeg ->
            close()
            if (jpeg != null && SelfFace.set(act, jpeg)) { refreshFace(); refreshPhotoRow() }
        })
    }

    /** iOS MontanaCallsignPicker: every row of the table, searchable; the choice becomes the name. */
    private fun showCallsigns() {
        val c = act
        view.removeAllViews()
        act.back = { showEditor() }
        val rows = Callsign.all(c)
        val list = c.vstack(Gravity.NO_GRAVITY)
        fun fill(q: String) {
            list.removeAllViews()
            rows.filter { q.isEmpty() || it.lowercase().contains(q) }.forEach { row ->
                list.addView(c.hstack {
                    setPadding(dp(20), dp(14), dp(20), dp(14))
                    addView(c.text(row, 17f), lp(0, WRAP, 1f))
                    if (row == name) addView(c.icon(R.drawable.ic_check, Color.WHITE))
                    pressable { name = row; Prefs.userName = row; showEditor() }
                }, lp())
            }
        }
        val search = EditText(c).apply {
            background = c.rounded(MT.plate, 10); setTextColor(Color.WHITE); isSingleLine = true
            setCompoundDrawablesRelativeWithIntrinsicBounds(R.drawable.ic_search, 0, 0, 0)
            compoundDrawableTintList = android.content.res.ColorStateList.valueOf(MT.gray)
            compoundDrawablePadding = dp(8)
            setPadding(dp(12), dp(10), dp(12), dp(10))
            addTextChangedListener(object : TextWatcher {
                override fun afterTextChanged(s: Editable?) { fill(s.toString().trim().lowercase()) }
                override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
                override fun onTextChanged(s: CharSequence?, a: Int, b: Int, d: Int) {}
            })
        }
        fill("")
        view.addView(c.vstack(Gravity.NO_GRAVITY) {
            addView(c.topBar(onBack = { showEditor() }))
            addView(search, lp().apply { setMargins(dp(16), 0, dp(16), dp(8)) })
            addView(ScrollView(c).apply { addView(list) }, lp(MATCH, 0, 1f))
        }, FrameLayout.LayoutParams(MATCH, MATCH))
    }

    /** The person leaves here NAMED: no name written — the call sign lands in the name itself. */
    private fun done() {
        if (name.isBlank()) {
            val sign = Callsign.of(act, MontanaSeed.twin ?: "")
            if (sign.isNotEmpty()) name = sign
        }
        if (name.isNotBlank()) Prefs.userName = stripCrown(name.trim())   // my own name never carries a crown (iOS MTCrown.plain, atom d4142dd38143)
        // the bio and the link are kept as typed; what leaves is the bio trimmed and the link only when it is one (iOS keepAbout)
        bioField?.let { Prefs.setStr("profileBio", it.text.toString()) }
        linkField?.let { Prefs.setStr("profileLink", it.text.toString().trim()) }
        if (bioField != null) Thread { MyAbout.broadcast() }.start()
        act.back = null
        onFinish()
    }
}

// ─────────────────────────── the terms (iOS MontanaTermsGate) ───────────────────────────

/**
 * The terms. [onAgree] set — the gate after the identity: no way past without «I agree».
 * [onAgree] null — the page opened from the doors' footer (iOS: a sheet), closed by its back mark.
 */
fun termsGate(act: MainActivity, onAgree: (() -> Unit)?, onClose: (() -> Unit)? = null): View {
    val c = act
    fun header(res: Int) = c.text(c.getString(res).uppercase(), 13f, MT.gray).apply { setPadding(dp(16), dp(20), dp(16), dp(6)) }
    fun section(vararg lines: Int) = c.plate {
        lines.forEachIndexed { i, l ->
            if (i > 0) divider()
            addView(c.text(c.getString(l), 16f).apply { setPadding(dp(16), dp(12), dp(16), dp(12)) })
        }
    }
    fun link(iconRes: Int, label: String, intent: Intent) = c.hstack {
        setPadding(dp(16), dp(14), dp(16), dp(14))
        addView(c.icon(iconRes, Color.WHITE), lp(dp(24), dp(24)).apply { marginEnd = dp(12) })   // iOS Color.accentColor: white in the dark
        addView(c.text(label, 17f, Color.WHITE))
        pressable { runCatching { c.startActivity(intent) } }
    }
    val body = c.vstack(Gravity.NO_GRAVITY) {
        setPadding(dp(16), 0, dp(16), dp(16))
        addView(section(R.string.terms_intro, R.string.terms_agree_line), lp())
        addView(header(R.string.terms_abuse_h))
        addView(section(R.string.terms_abuse_1, R.string.terms_abuse_2, R.string.terms_abuse_3), lp())
        addView(header(R.string.terms_tools_h))
        addView(section(R.string.terms_tools_1, R.string.terms_tools_2, R.string.terms_tools_3, R.string.terms_tools_4), lp())
        addView(header(R.string.terms_reach_h))
        addView(c.plate {
            addView(link(R.drawable.ic_email, "contact@montana.quest", Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:contact@montana.quest"))), lp())
            divider()
            addView(link(R.drawable.ic_language, "https://montana.quest", Intent(Intent.ACTION_VIEW, Uri.parse("https://montana.quest"))), lp())
        }, lp())
    }
    // the terms stand on my page's ground, as the drawer and my page wear it (iOS MontanaTermsView 118)
    return FrameLayout(c).apply { addView(c.chatGround(ChatWall.PAGE), FrameLayout.LayoutParams(MATCH, MATCH)) }.also { root -> root.addView(c.vstack(Gravity.NO_GRAVITY) {
        addView(c.topBar(c.getString(R.string.terms_title), onBack = onClose))
        addView(ScrollView(c).apply { addView(body) }, lp(MATCH, 0, 1f))
        // agreeing to the terms is the path's door too (iOS MTLoginDoorStyle 2653-2655), the page's main act
        if (onAgree != null) addView(PathDoor(c, c.getString(R.string.i_agree), MT.blue, onAgree), lp().apply { setMargins(dp(20), dp(12), dp(20), dp(12)) })
    }, FrameLayout.LayoutParams(MATCH, MATCH)) }
}

// ─────────────────────────── the sign lights up (iOS WelcomeView) ───────────────────────────

fun welcome(act: MainActivity, onFinish: () -> Unit): View {
    val c = act
    val logo = ImageView(c).apply { setImageResource(R.drawable.logo); scaleX = 0.6f; scaleY = 0.6f; alpha = 0f }
    // iOS WelcomeView: the sign and the word in the accent — white in the dark (AccentColor)
    val title = c.text("Montana", 40f, Color.WHITE, bold = true, center = true).apply {
        alpha = 0f; setShadowLayer(dp(18).toFloat(), 0f, 0f, Color.WHITE)
    }
    val col = c.vstack(Gravity.CENTER) {
        addView(c.glowingLogo(87, 260, 700).also { g -> g.removeViewAt(1); g.addView(logo, FrameLayout.LayoutParams(dp(87), dp(87), Gravity.CENTER)) },
            lp(MATCH, dp(200)))
        gap(22)
        addView(title)
    }
    logo.animate().scaleX(1f).scaleY(1f).alpha(1f).setDuration(400).setInterpolator(DecelerateInterpolator()).start()
    title.animate().alpha(1f).setDuration(400).start()
    col.postDelayed(onFinish, 600)   // the splash dismisses fast (iOS: 0.6 s)
    // the ground of the terms before it and the chats after it: no black between (iOS 2732, montanaPageGround)
    return FrameLayout(c).apply {
        addView(c.chatGround(ChatWall.PAGE), FrameLayout.LayoutParams(MATCH, MATCH))
        addView(col, FrameLayout.LayoutParams(MATCH, MATCH))
    }
}
