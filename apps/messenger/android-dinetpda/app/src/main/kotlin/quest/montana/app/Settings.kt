package quest.montana.app

import android.app.AlertDialog
import android.app.LocaleManager
import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.LocaleList
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.widget.CheckBox
import android.widget.FrameLayout
import android.widget.GridLayout
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.Switch
import android.widget.TextView
import java.io.File

// ─────────────────────────── the settings' own parts (iOS settingsToggleLabel, MTGlassRowPlate) ───────────────────────────

/** The iOS system colours the settings' glyph plates wear (dark appearance). */
object SysColor {
    val red = MT.red
    val indigo = Color.rgb(94, 92, 230)
    val gray = Color.rgb(142, 142, 147)
    val cyan = Color.rgb(100, 210, 255)
    val blue = MT.blue
    val pink = Color.rgb(255, 55, 95)
    val orange = MT.orange
    val green = MT.green
    val teal = Color.rgb(64, 200, 224)
    val purple = Color.rgb(191, 90, 242)
}

/** The glyph on its coloured plate: 29 points, corner 7, the glyph white (iOS settingsToggleLabel). */
fun Context.settingsGlyph(res: Int, color: Int): View = FrameLayout(this).apply {
    background = rounded(color, 7)
    addView(icon(res, Color.WHITE), FrameLayout.LayoutParams(dp(17), dp(17), Gravity.CENTER))
}

/** A row that leads somewhere: the glyph, the words, the value, the chevron; the whole row is the target. */
fun Context.settingsRow(res: Int?, color: Int, title: String, value: View? = null, chevron: Boolean = true, words: Int = Color.WHITE,
                        onTap: () -> Unit): View = hstack {
    setPadding(dp(16), dp(10), dp(14), dp(10))
    minimumHeight = dp(48)
    if (res != null) { addView(settingsGlyph(res, color), lp(dp(29), dp(29))); gap(12) }
    addView(text(title, 17f, words), lp(0, WRAP, 1f))   // iOS settings rows: 17 (body), MontanaSettings.swift:1608-1618
    if (value != null) addView(value, lp(WRAP, WRAP).apply { marginStart = dp(8) })
    if (chevron) addView(icon(R.drawable.ic_chevron_right, Color.rgb(89, 89, 89), 18), lp(dp(18), dp(18)).apply { marginStart = dp(6) })
    pressable(onTap)
}

/** A row with the system switch (iOS Toggle): the glyph, the words, the switch, and a line under it when it says more. */
fun Context.switchLine(res: Int, color: Int, title: String, on: Boolean, caption: String? = null, tint: Int = MT.green,
                       onChange: (Boolean) -> Unit): View = vstack(Gravity.NO_GRAVITY) {
    setPadding(dp(16), dp(8), dp(14), dp(8))
    val sw = Switch(context).apply {
        isChecked = on
        thumbTintList = ColorStateList.valueOf(Color.WHITE)
        trackTintList = ColorStateList(arrayOf(intArrayOf(android.R.attr.state_checked), intArrayOf()), intArrayOf(tint, Color.rgb(57, 57, 61)))
        setOnCheckedChangeListener { _, v -> onChange(v) }
        contentDescription = title
    }
    addView(hstack {
        addView(settingsGlyph(res, color), lp(dp(29), dp(29))); gap(12)
        addView(text(title, 16f), lp(0, WRAP, 1f))
        addView(sw)
        setOnClickListener { sw.toggle() }
    }, lp())
    if (caption != null) addView(text(caption, 12f, MT.gray).apply { setPadding(0, dp(4), 0, dp(2)) }, lp())
}

/** A section: the words over it, the rows on one plate with the list's separators, the words under it. */
fun LinearLayout.section(header: String? = null, footer: String? = null, vararg rows: View) {
    val c = context
    addView(c.text(header ?: "", 13f, MT.gray).apply { setPadding(dp(16), dp(if (header == null) 12 else 22), dp(16), dp(if (header == null) 0 else 6)) }, lp())
    addView(c.plate {
        rows.forEachIndexed { i, r ->
            if (i > 0) addView(View(c).apply { setBackgroundColor(MT.hairline) }, lp(MATCH, 1).apply { marginStart = dp(16) })
            addView(r, lp())
        }
    }, lp())
    if (footer != null) addView(c.text(footer, 12f, MT.gray).apply { setPadding(dp(16), dp(8), dp(16), 0) }, lp())
}

/**
 * A SETTINGS PAGE (iOS List on the page's ground, the inline title): the crest behind, the bar with its one mark — the back
 * chevron on a pushed page, the cross on the settings' root — and the list that scrolls.
 */
fun settingsPage(act: MainActivity, title: String, onLead: () -> Unit, cross: Boolean = false, trailing: View? = null,
                 build: LinearLayout.() -> Unit): View {
    val c: Context = act
    val bar = FrameLayout(c).apply {
        setPadding(dp(8), 0, dp(8), 0)
        // THE BAR'S MARKS ARE ROUNDS OF GLASS (iOS MontanaBarMark, MontanaShapes.swift:1115-1134 and 1225-1246: the toolbar's own glass
        // circle round the glyph in a 44 frame): the back chevron, or the cross on the settings' root, on the left
        addView(FrameLayout(c).apply {
            background = c.glassPlate(oval = true)
            contentDescription = c.getString(if (cross) R.string.coin_close else R.string.back)
            addView(c.icon(if (cross) R.drawable.ic_close else R.drawable.ic_arrow_back_ios_new, Color.WHITE), FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER))
            pressable(onLead)
        }, FrameLayout.LayoutParams(dp(44), dp(44), Gravity.CENTER_VERTICAL or Gravity.START))
        addView(c.text(title, 17f, Color.WHITE, bold = true, center = true), FrameLayout.LayoutParams(WRAP, WRAP, Gravity.CENTER))
        // the page's own act at the right of its bar (iOS the toolbar's trailing mark: «Done» as the platform's checkmark), on its round
        // of glass as well; a mark that brings its own round keeps it
        trailing?.let { t ->
            val round = if (t.background != null) t else FrameLayout(c).apply { background = c.glassPlate(oval = true); addView(t, FrameLayout.LayoutParams(MATCH, MATCH)) }
            addView(round, FrameLayout.LayoutParams(dp(44), dp(44), Gravity.CENTER_VERTICAL or Gravity.END))
        }
    }
    return FrameLayout(c).apply {
        setBackgroundColor(Color.BLACK)
        addView(c.chatGround(ChatWall.PAGE), FrameLayout.LayoutParams(MATCH, MATCH))   // my page's ground (iOS montanaPageGround)
        addView(c.vstack(Gravity.NO_GRAVITY) {
            addView(bar, lp(MATCH, dp(52)))
            addView(ScrollView(c).apply {
                addView(c.vstack(Gravity.NO_GRAVITY) { setPadding(dp(16), 0, dp(16), dp(32)); build() })
            }, lp(MATCH, 0, 1f))
        }, FrameLayout.LayoutParams(MATCH, MATCH))
    }
}

/** A page over the current one (iOS NavigationLink): back or its own mark takes it away. */
fun MainActivity.push(build: (close: () -> Unit) -> View) {
    lateinit var close: () -> Unit
    close = overlay(build { close() })
}

// ─────────────────────────── the settings' first page (iOS SettingsTabView) ───────────────────────────

/** THE SETTINGS ARE THE PLATFORM'S OWN LIST: two sections of rows, the cross top left. */
fun settingsRoot(act: MainActivity, onForget: () -> Unit, onClose: () -> Unit): View {
    val c: Context = act
    return settingsPage(act, c.getString(R.string.settings), onClose, cross = true) {
        // THE 24 WORDS AT THE HEAD (iOS MontanaSettings.swift:120-126, the author's word 08.10.2026): the one thing nobody can give back
        section(null, c.getString(R.string.set_save_words_footer),
            c.settingsRow(R.drawable.ic_key, SysColor.gray, c.getString(R.string.set_save_words)) { act.push { seedPage(act, it) } })
        section(null, null,
            c.settingsRow(R.drawable.ic_set_bell, SysColor.red, c.getString(R.string.notif_sounds)) { act.push { notificationsPage(act, it) } },
            // THE FOLDERS' TABS (iOS MontanaSettings.swift:130 at 2235, 17.10.2026): «Chat Folders», folder.fill on blue, after the notifications
            c.settingsRow(R.drawable.ic_folder_fill, SysColor.blue, c.getString(R.string.fl_title)) { act.push { folderSettingsPage(act, it) } },
            c.settingsRow(R.drawable.ic_arrow_circle_down, SysColor.indigo, c.getString(R.string.data_storage)) { act.push { dataStoragePage(act, it) } },
            c.settingsRow(R.drawable.ic_set_server, SysColor.gray, c.getString(R.string.your_node)) { act.push { NodePage(act, it).view } },
            c.settingsRow(R.drawable.ic_set_lock, SysColor.gray, c.getString(R.string.privacy)) { act.push { privacyPage(act, onForget, it) } },
            // ACCESS BY LEVEL (iOS MontanaSettings.swift:134, MTLevelAccessPage): stairs on orange, after Privacy
            c.settingsRow(R.drawable.ic_stairs, SysColor.orange, c.getString(R.string.la_title)) { act.push { levelAccessPage(act, it) } },
            c.settingsRow(R.drawable.ic_set_brush, SysColor.blue, c.getString(R.string.appearance)) { act.push { AppearancePage(act, it).view } },
            c.settingsRow(R.drawable.ic_language, SysColor.cyan, c.getString(R.string.language)) { act.push { languagePage(act, it) } })
        section(null, null,
            c.settingsRow(R.drawable.ic_set_help, SysColor.blue, c.getString(R.string.ask_question)) { act.push { supportPage(act, it) } },
            c.settingsRow(R.drawable.ic_set_doc, SysColor.gray, c.getString(R.string.terms_of_use)) { act.push { termsGate(act, onAgree = null, onClose = it) } },
            // THE POLICY STANDS WHERE THE TERMS STAND (iOS 141-143, App Review 5.1.1(i)): it opens on the site, in the languages the site speaks
            c.settingsRow(R.drawable.ic_hand, SysColor.blue, c.getString(R.string.set_privacy_policy), chevron = false) {
                runCatching { act.startActivity(android.content.Intent(android.content.Intent.ACTION_VIEW, android.net.Uri.parse(PRIVACY_URL))) }
            })
    }
}

/**
 * ACCESS BY LEVEL (iOS MTLevelAccessPage, MontanaSettings.swift:2682-2750, the author's words 16.10.2026 18:2x MSK): the Global Level and
 * what each level opens -- level 7 forbids deletion on this phone, level 8 joins the person's own node to the network through this app.
 * Below its level a switch stands off and shows what works; the person's own choice is kept for the day it opens. (iOS «Record calls»
 * of level 7 joins with the calls' recording stage.)
 */
fun levelAccessPage(act: MainActivity, onBack: () -> Unit): View {
    val c: Context = act
    val level = PersonChain.global(PersonChain.level, CoinBook.balance)
    val seven = LevelAccess.Feature.KEEP_DELETED.level
    val open = LevelAccess.opens(LevelAccess.Feature.KEEP_DELETED)
    val eight = LevelAccess.Feature.OWN_NODE.level
    val nodeOpen = LevelAccess.opens(LevelAccess.Feature.OWN_NODE)
    return settingsPage(act, c.getString(R.string.la_title), onBack) {
        section(null, c.getString(R.string.la_global_footer),
            c.text(c.getString(R.string.la_global, level), 17f).apply { setPadding(dp(16), dp(13), dp(16), dp(13)) })   // USER-DATA: the Global Level
        section(c.getString(R.string.la_level, seven), if (open) null else c.getString(R.string.la_opens, seven, level),
            c.switchLine(R.drawable.ic_shield, SysColor.green, c.getString(R.string.la_keep), open && Prefs.bool(LevelAccess.KEEP_KEY, true),
                caption = c.getString(R.string.la_keep_caption)) { on -> Prefs.setBool(LevelAccess.KEEP_KEY, on) }.apply { isEnabled = open; alpha = if (open) 1f else 0.5f; disableAll(this, open) })
        section(c.getString(R.string.la_level, eight), if (nodeOpen) null else c.getString(R.string.la_opens, eight, level),
            c.vstack(Gravity.NO_GRAVITY) {
                setPadding(dp(16), dp(10), dp(14), dp(10))
                addView(c.hstack {
                    gravity = Gravity.CENTER_VERTICAL
                    addView(c.settingsGlyph(R.drawable.ic_set_server, SysColor.gray), lp(dp(29), dp(29))); gap(12)
                    addView(c.text(c.getString(R.string.your_node), 16f), lp(0, WRAP, 1f))
                    addView(c.icon(R.drawable.ic_chevron_right, Color.rgb(89, 89, 89), 18), lp(dp(18), dp(18)))
                }, lp())
                addView(c.text(c.getString(R.string.la_node_caption), 12f, MT.gray).apply { setPadding(0, dp(4), 0, dp(2)) }, lp())
                alpha = if (nodeOpen) 1f else 0.5f
                if (nodeOpen) pressable { act.push { NodePage(act, it).view } }
            })
    }
}
/** A row and every control in it off together (iOS .disabled on a section). */
private fun disableAll(v: View, on: Boolean) {
    v.isEnabled = on
    if (v is android.view.ViewGroup) for (i in 0 until v.childCount) disableAll(v.getChildAt(i), on)
}

// ─────────────────────────── Notifications and Sounds (iOS NotificationsView) ───────────────────────────

/**
 * The permission is the system's: the row asks it when it was never asked and leads to where the system keeps it
 * otherwise; the word beside it is read again whenever the window comes back (the person may have changed it there).
 * The four switches are kept under the iOS keys; the notifications that read them come with the network.
 */
fun notificationsPage(act: MainActivity, onBack: () -> Unit): View {
    val c: Context = act
    val status = c.text("", 15f, MT.gray)
    fun asked() = Build.VERSION.SDK_INT < 33 || Prefs.notifyAsked
    fun refresh() {
        val on = c.getSystemService(NotificationManager::class.java).areNotificationsEnabled()
        status.text = c.getString(if (on) R.string.st_connected else if (!asked()) R.string.st_not_asked else R.string.st_disconnected)
    }
    fun sw(res: Int, color: Int, word: Int, key: String) =
        c.switchLine(res, color, c.getString(word), Prefs.bool(key, true)) { Prefs.setBool(key, it) }
    val page = settingsPage(act, c.getString(R.string.notifications), onBack) {
        section(null, null, c.settingsRow(R.drawable.ic_set_bell, SysColor.red, c.getString(R.string.allow_notifications), status) {
            if (!asked()) {
                Prefs.notifyAsked = true
                act.requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 2)
            } else act.startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, c.packageName))
        })
        section(null, null,
            sw(R.drawable.ic_set_speaker, SysColor.pink, R.string.sound, "notifSound"),
            sw(R.drawable.ic_set_textbubble, SysColor.green, R.string.show_text, "notifPreview"),
            sw(R.drawable.ic_person, SysColor.orange, R.string.show_sender, "notifSender"),
            sw(R.drawable.ic_set_lock, SysColor.blue, R.string.name_lock, "notifLockName"))
    }
    page.viewTreeObserver.addOnWindowFocusChangeListener { if (it) refresh() }
    refresh()
    return page
}

// ─────────────────────────── Language (iOS LanguagePickerView) ───────────────────────────

/**
 * THE APP'S OWN LANGUAGE, KEPT BY THE SYSTEM: from Android 13 the platform's per-app language (LocaleManager) — the
 * system itself redraws the app in it and lists it in its own settings; before, the choice is kept here and laid over
 * the app's context at every start. "" is the system's.
 */
object AppLanguage {
    const val KEY = "AppLanguage"
    private fun tag(id: String) = if (id == "zh-Hans") "zh-CN" else id
    val chosen: String get() = Prefs.str(KEY, "")
    fun set(act: MainActivity, id: String) {
        Prefs.setStr(KEY, id)
        act.getSharedPreferences("mt.lang", Context.MODE_PRIVATE).edit().putString(KEY, id).commit()
        if (Build.VERSION.SDK_INT >= 33) {
            act.getSystemService(LocaleManager::class.java).applicationLocales =
                if (id.isEmpty()) LocaleList.getEmptyLocaleList() else LocaleList.forLanguageTags(tag(id))
        } else act.recreate()
    }
    /** Before Android 13: the chosen language laid over the context the activity starts with. */
    fun wrap(base: Context): Context {
        if (Build.VERSION.SDK_INT >= 33) return base
        val id = base.getSharedPreferences("mt.lang", Context.MODE_PRIVATE).getString(KEY, "") ?: ""
        if (id.isEmpty()) return base
        val conf = android.content.res.Configuration(base.resources.configuration)
        conf.setLocales(LocaleList.forLanguageTags(tag(id)))
        return base.createConfigurationContext(conf)
    }
}

fun languagePage(act: MainActivity, onBack: () -> Unit): View {
    val c: Context = act
    class Option(val id: String, val native: String, val english: Int, val flag: String?)
    val options = listOf(
        Option("", c.getString(R.string.lang_system), R.string.lang_system_sub, null),
        Option("en", "English", R.string.lang_english, "🇬🇧"),          // USER-DATA: the language's own name
        Option("zh-Hans", "简体中文", R.string.lang_chinese, "🇨🇳"),     // USER-DATA: the language's own name
        Option("ru", "Русский", R.string.lang_russian, "🇷🇺"))          // USER-DATA: the language's own name CYRILLIC-DATA-OK
    val rows = options.map { o ->
        c.hstack {
            setPadding(dp(16), dp(10), dp(16), dp(10))
            addView(FrameLayout(c).apply {
                background = android.graphics.drawable.GradientDrawable().apply { shape = android.graphics.drawable.GradientDrawable.OVAL; setColor(Color.rgb(41, 41, 41)) }
                if (o.flag == null) addView(c.icon(R.drawable.ic_language, Color.WHITE), FrameLayout.LayoutParams(dp(22), dp(22), Gravity.CENTER))
                else addView(c.text(o.flag, 22f, center = true), FrameLayout.LayoutParams(WRAP, WRAP, Gravity.CENTER))
            }, lp(dp(44), dp(44)))
            gap(14)
            addView(c.vstack(Gravity.NO_GRAVITY) {
                addView(c.text(o.native, 16f))
                addView(c.text(c.getString(o.english), 12f, MT.gray))
            }, lp(0, WRAP, 1f))
            addView(c.icon(R.drawable.ic_check, MT.green).apply { alpha = if (AppLanguage.chosen == o.id) 1f else 0f }, lp(dp(20), dp(20)))
            pressable { if (AppLanguage.chosen != o.id) AppLanguage.set(act, o.id) }
        }
    }
    return settingsPage(act, c.getString(R.string.language), onBack) {
        section(null, c.getString(R.string.lang_footer), *rows.toTypedArray())
    }
}

// ─────────────────────────── Ask a question (iOS SupportView) ───────────────────────────

/** A REAL DOOR: the addresses shown as they are; a tap opens the mail, and with no mail on the phone the address is copied. */
fun supportPage(act: MainActivity, onBack: () -> Unit): View {
    val c: Context = act
    val mail = "contact@montana.quest"   // iOS MontanaSafety.contactMail
    val site = "https://montana.quest"   // iOS MontanaSafety.site
    fun write(subject: Int) {
        val i = Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:$mail")).putExtra(Intent.EXTRA_SUBJECT, c.getString(subject))
        try { act.startActivity(i) } catch (_: ActivityNotFoundException) {
            (c.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("Montana", mail))
            AlertDialog.Builder(act).setMessage(R.string.no_mail).setPositiveButton(R.string.ok, null).show()
        }
    }
    fun value(s: String) = c.text(s, 13f, MT.gray)   // USER-DATA: an address
    return settingsPage(act, c.getString(R.string.ask_question), onBack) {
        section(c.getString(R.string.write_to_us), null,
            c.settingsRow(null, 0, c.getString(R.string.ask_question), value(mail), chevron = false) { write(R.string.mail_question) },
            c.settingsRow(null, 0, c.getString(R.string.report_abuse), value(mail), chevron = false) { write(R.string.mail_report) },
            c.settingsRow(null, 0, c.getString(R.string.website), value(site), chevron = false) {
                act.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(site)))
            })
        section(null, null, c.text(c.getString(R.string.reports_24h), 13f, MT.gray).apply { setPadding(dp(16), dp(12), dp(16), dp(12)) })
    }
}

// ─────────────────────────── Privacy (iOS PrivacyView) ───────────────────────────

/**
 * PRIVACY (iOS PrivacyView, MontanaSettings.swift:1702-1946): the system's answers, the switches of what this person shares, the wall's
 * rules, the filter and the blocked, the seed phrase, and the one act that deletes the account. iOS's contacts row and «Sync contacts»
 * stand with the feature that writes a person's Montana name into the phone's book (iOS ContactsTabView.upsertSystemCard), which
 * Android has not yet: a row would claim what nothing does.
 */
fun privacyPage(act: MainActivity, onForget: () -> Unit, onBack: () -> Unit): View {
    val c: Context = act
    fun sw(res: Int, color: Int, word: Int, key: String, caption: Int? = null) =
        c.switchLine(res, color, c.getString(word), Prefs.bool(key, true), caption?.let { c.getString(it) }) { Prefs.setBool(key, it) }
    fun granted(p: String) = c.checkSelfPermission(p) == android.content.pm.PackageManager.PERMISSION_GRANTED
    // THE SYSTEM'S OWN ANSWERS (iOS PrivacyView, its first section): the local network — «Connected» while this phone is findable
    // on the mesh, the one switch owning the concept (iOS MontanaSettings 1731, 1765), and it leads to where the system keeps it; the
    // location — asked here when never asked, changed where the system keeps it, the same answer the place page reads; the photos —
    // the system's own word for this app's pictures (iOS MTSystemAccess.photosWord): all of them, the ones the person chose, none,
    // or never asked, and the same road
    val place = c.text("", 15f, MT.gray)
    val photos = c.text("", 15f, MT.gray)
    fun placeAllowed() = granted(android.Manifest.permission.ACCESS_FINE_LOCATION) || granted(android.Manifest.permission.ACCESS_COARSE_LOCATION)
    val photoAsks = if (34 <= android.os.Build.VERSION.SDK_INT) arrayOf(android.Manifest.permission.READ_MEDIA_IMAGES, android.Manifest.permission.READ_MEDIA_VIDEO,
            android.Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)
        else if (33 <= android.os.Build.VERSION.SDK_INT) arrayOf(android.Manifest.permission.READ_MEDIA_IMAGES, android.Manifest.permission.READ_MEDIA_VIDEO)
        else arrayOf(android.Manifest.permission.READ_EXTERNAL_STORAGE)
    fun photosWord(): Int = when {
        if (33 <= android.os.Build.VERSION.SDK_INT) granted(android.Manifest.permission.READ_MEDIA_IMAGES) else granted(android.Manifest.permission.READ_EXTERNAL_STORAGE) -> R.string.pr_full_access
        34 <= android.os.Build.VERSION.SDK_INT && granted(android.Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED) -> R.string.pr_limited_access
        Prefs.bool("photosAsked", false) -> R.string.pr_none
        else -> R.string.st_not_asked
    }
    fun drawPlace() {
        place.text = c.getString(if (placeAllowed()) R.string.st_allowed else if (Prefs.bool("locAsked", false)) R.string.st_denied else R.string.st_not_asked)
        photos.text = c.getString(photosWord())
    }
    fun systemSettings() = SystemSettings.open(act)   // the one door, warning while a call stands
    drawPlace()
    val page = settingsPage(act, c.getString(R.string.privacy), onBack) {
        section(null, null,
            c.settingsRow(R.drawable.ic_language, SysColor.blue, c.getString(R.string.local_network), c.text(c.getString(if (Mesh.discoverable) R.string.st_connected else R.string.st_disconnected), 15f, MT.gray)) { systemSettings() },
            c.settingsRow(R.drawable.ic_compose_location, SysColor.blue, c.getString(R.string.location), place) {
                if (!placeAllowed() && !Prefs.bool("locAsked", false)) {
                    Prefs.setBool("locAsked", true)
                    act.requestPermissions(arrayOf(android.Manifest.permission.ACCESS_FINE_LOCATION, android.Manifest.permission.ACCESS_COARSE_LOCATION), 7)
                } else systemSettings()
            },
            c.settingsRow(R.drawable.ic_photo, SysColor.blue, c.getString(R.string.pr_photos), photos) {
                if (photosWord() == R.string.st_not_asked) { Prefs.setBool("photosAsked", true); act.requestPermissions(photoAsks, 8) } else systemSettings()
            })
        section(null, null,
            // the switch speaks: hidden, one farewell word; shown, «here» at once (iOS MontanaPresencePrivacy.setSharing)
            c.switchLine(R.drawable.ic_set_eye, SysColor.teal, c.getString(R.string.online_status), Presence.sharing, c.getString(R.string.online_status_sub)) { Presence.setSharing(it) },
            // THE OWNER SHOWS OR HIDES THEIR COINS (iOS MTCoinShow, MontanaSettings.swift:1815-1825): the coins told to the correspondents
            // and the coins on one's own face; the pairs in the app hear it at once (iOS showChanged → MTCoinTell)
            c.switchLine(R.drawable.ic_trophy, SysColor.orange, c.getString(R.string.pr_show_coins), CoinShow.on, c.getString(R.string.pr_show_coins_sub)) { CoinShow.set(it) },
            sw(R.drawable.ic_set_check_circle, SysColor.green, R.string.read_receipts, "readReceiptsEnabled"),
            sw(R.drawable.ic_set_link, SysColor.blue, R.string.link_previews, "linkPreviewsEnabled", R.string.link_previews_sub),
            // THE DIARY LEAVES ONLY BY THE PERSON'S YES (iOS MontanaSettings 1852-1861, MontanaDiagConsent; App Review 5.1.1(ii), 08.10):
            // off, nothing of the diary leaves this phone; the doc glyph stands for the iPhone's stethoscope, which the set lacks
            c.switchLine(R.drawable.ic_set_doc, SysColor.gray, c.getString(R.string.diag_share), Diary.consented, c.getString(R.string.diag_share_sub)) { Diary.setConsent(it) })
        // THE WALL (iOS MontanaSettings 1858-1878, the author's word 24.09): who may write on my wall, and who may see it -- everyone,
        // until the person says otherwise
        section(null, c.getString(R.string.wall_rule_footer),
            c.settingsRow(R.drawable.ic_text_below_photo, SysColor.blue, c.getString(R.string.wall_who_write_mine)) { act.push { wallRulePage(act, WallRule.Act.WRITE, it) } },
            c.settingsRow(R.drawable.ic_set_eye, SysColor.blue, c.getString(R.string.wall_who_see_mine)) { act.push { wallRulePage(act, WallRule.Act.SEE, it) } })
        section(null, null, sw(R.drawable.ic_set_eye_slash, SysColor.purple, R.string.filter_objectionable, "objectionableFilterOn"),
            c.settingsRow(R.drawable.ic_hand, SysColor.red, c.getString(R.string.blocked_users)) { act.push { blockedPage(act, it) } })
        section(null, null, c.settingsRow(R.drawable.ic_key, SysColor.gray, c.getString(R.string.seed_phrase)) { act.push { seedPage(act, it) } })
        section(null, null, c.text(c.getString(R.string.pr_delete_account), 17f, MT.red, center = true).apply {
            setPadding(dp(16), dp(14), dp(16), dp(14))
            pressable {
                // The words come first: a person without the phrase leaves here toward it, not past the edge. An account that holds coins
                // says how many first, and that only its 24 words bring them back (iOS PrivacyView.alert, the author's word 12.10.2026)
                val coins = CoinBook.balance
                val words = c.getString(R.string.pr_delete_account_msg)
                AlertDialog.Builder(act).setTitle(R.string.pr_delete_account_q)
                    .setMessage(if (0L < coins) c.getString(R.string.pr_delete_account_coins, coins.toString()) + "\n\n" + words else words)
                    .setNeutralButton(R.string.show_seed) { _, _ -> act.push { seedPage(act, it) } }
                    .setPositiveButton(R.string.pr_delete_account) { _, _ -> onForget() }
                    .setNegativeButton(R.string.cancel, null).show()
                    .getButton(AlertDialog.BUTTON_POSITIVE)?.setTextColor(SysColor.red)
            }
        })
    }
    // the system's answer is read again while the page stands: a return from the system's settings, the question answered
    var live = false
    lateinit var beat: Runnable
    beat = Runnable { if (live) { drawPlace(); MainThread.later(1000, beat) } }
    page.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(v: View) { live = true; beat.run() }
        override fun onViewDetachedFromWindow(v: View) { live = false }
    })
    return page
}

/**
 * THE BLOCKED LIST (iOS MontanaBlockedView, Settings → Privacy, MontanaSafety 245-266): every blocked person, the name on one line,
 * and «Unblock» beside it — the word is the control, the name is not, so a tap on a name never lets a blocked person back.
 */
fun blockedPage(act: MainActivity, onBack: () -> Unit): View {
    val c: Context = act
    lateinit var list: LinearLayout
    fun draw() {
        list.removeAllViews()
        val people = Book.refs().filter { PeerSafety.isBlocked(it) }
            .map { ref -> ref to (Book.chat(ref)?.shown?.ifBlank { null } ?: c.getString(R.string.peer)) }
            .sortedBy { it.second.lowercase() }
        if (people.isEmpty()) {
            list.section(null, null, c.text(c.getString(R.string.nobody_blocked), 16f, MT.gray).apply { setPadding(dp(16), dp(14), dp(16), dp(14)) })
            return
        }
        list.section(null, null, *people.map { (ref, name) ->
            c.hstack {
                setPadding(dp(16), 0, dp(6), 0)
                minimumHeight = dp(48)
                addView(c.text(name, 16f, Color.WHITE).apply { singleLineEllipsis() }, lp(0, WRAP, 1f))   // USER-DATA: a person's name
                addView(c.text(c.getString(R.string.pi_unblock), 16f, Color.WHITE).apply {
                    gravity = Gravity.CENTER; setPadding(dp(10), 0, dp(10), 0)
                    pressable { PeerSafety.setBlocked(ref, false); draw() }
                }, lp(WRAP, dp(48)))
            }
        }.toTypedArray())
    }
    return settingsPage(act, c.getString(R.string.blocked_users), onBack) { list = this; draw() }
}

/**
 * THE SEED PHRASE (iOS SeedShowView), in three steps: the lock — the phone's owner confirms with a finger, a face or the
 * code, and a phone with no lock shows nothing; the two promises read and ticked — Montana has no access to this key, the
 * words go on paper; then the 24 words in two columns read top to bottom, and the copy that the system keeps sensitive.
 * The whole page keeps its secret: no screenshot, no recording, black in the recent apps.
 */
fun seedPage(act: MainActivity, onBack: () -> Unit): View {
    val c: Context = act
    lateinit var body: LinearLayout
    var ask: () -> Unit = {}
    fun words() { body.removeAllViews(); body.seedWords(c) }
    fun locked(word: OwnerWord?) {
        body.removeAllViews()
        body.gap(48)
        body.addView(c.icon(R.drawable.ic_set_lock, Color.WHITE, 44), lp(WRAP, WRAP).apply { gravity = Gravity.CENTER_HORIZONTAL })
        body.gap(16)
        val say = when (word) { OwnerWord.NO_LOCK -> R.string.sg_no_lock; OwnerWord.FAILED -> R.string.sg_failed; else -> R.string.sg_confirm }
        body.addView(c.text(c.getString(say), 13f, MT.gray, center = true), lp())
        body.gap(16)
        body.addView(AccentButton(c, c.getString(R.string.sg_unlock)) { ask() }, lp())
    }
    fun promises() {
        body.removeAllViews()
        body.gap(36)
        body.addView(c.icon(R.drawable.ic_shield, Color.WHITE, 72), lp(WRAP, WRAP).apply { gravity = Gravity.CENTER_HORIZONTAL })
        body.gap(12)
        body.addView(c.text("⚠ " + c.getString(R.string.sg_for_you), 17f, Color.WHITE, bold = true, center = true), lp())
        body.gap(6)
        body.addView(c.text(c.getString(R.string.sg_wallet), 22f, Color.WHITE, bold = true, center = true), lp())
        body.gap(16)
        lateinit var go: AccentButton
        val ticks = BooleanArray(2)
        fun promise(i: Int, res: Int) = c.hstack {
            background = c.rounded(MT.plate, 12)
            setPadding(dp(14), dp(14), dp(14), dp(14))
            val box = CheckBox(c).apply {
                buttonTintList = ColorStateList(arrayOf(intArrayOf(android.R.attr.state_checked), intArrayOf()), intArrayOf(MT.green, MT.gray))
                isClickable = false
            }
            addView(box)
            gap(8)
            addView(c.text(c.getString(res), 15f, Color.WHITE), lp(0, WRAP, 1f))
            pressable { box.toggle(); ticks[i] = box.isChecked; go.setOn(ticks.all { it }) }   // the whole row is the target
        }
        body.addView(promise(0, R.string.sg_no_access), lp())
        body.gap(8)
        body.addView(promise(1, R.string.sg_on_paper), lp())
        body.gap(16)
        go = AccentButton(c, c.getString(R.string.continue_word)) { words() }.apply { setOn(false) }
        body.addView(go, lp())
    }
    ask = { OwnerCheck.ask(act, c.getString(R.string.sg_reason)) { w -> act.onMain { if (w == OwnerWord.CONFIRMED) promises() else locked(w) } } }
    val page = settingsPage(act, c.getString(R.string.seed_phrase), onBack) {
        body = c.vstack(Gravity.NO_GRAVITY) {}
        addView(body, lp())
    }
    locked(null)
    ask()   // asked at once, as iOS asks on appear; «Unlock» asks again
    return page.keepsSecret()
}

/** The words themselves, shown only after the lock and the two promises (seedPage). */
private fun LinearLayout.seedWords(c: Context) {
    val words = (MontanaSeed.mnemonic ?: "").split(' ').filter { it.isNotEmpty() }
    gap(12)
    addView(c.text(c.getString(R.string.sg_write_down), 12f, MT.gray, center = true), lp())
    gap(12)
    if (words.isEmpty()) { gap(28); addView(c.text(c.getString(R.string.sg_no_seed), 15f, MT.gray, center = true), lp()); return }
    val half = (words.size + 1) / 2
    val order = (0 until half).flatMap { r -> if (r + half < words.size) listOf(r, r + half) else listOf(r) }
    addView(GridLayout(c).apply {
        columnCount = 2
        order.forEach { i ->
            addView(c.hstack {
                background = c.rounded(MT.plate, 8)
                setPadding(dp(7), dp(7), dp(7), dp(7))
                addView(c.text("${i + 1}.", 15f, MT.gray).apply { gravity = Gravity.END }, lp(dp(26), WRAP))
                gap(6)
                addView(c.text(words[i], 15f, Color.WHITE, bold = true))   // USER-DATA: the person's own words
            }, GridLayout.LayoutParams(GridLayout.spec(GridLayout.UNDEFINED), GridLayout.spec(GridLayout.UNDEFINED, 1f)).apply {
                width = 0; setMargins(dp(4), dp(4), dp(4), dp(4))
            })
        }
    }, lp())
    gap(14)
    lateinit var copy: TextView
    copy = c.text(c.getString(R.string.copy), 14f, Color.WHITE, center = true).apply {
        setPadding(dp(12), dp(10), dp(12), dp(10))
        pressable {
            val clip = ClipData.newPlainText("Montana", words.joinToString(" "))
            if (Build.VERSION.SDK_INT >= 33) clip.description.extras = android.os.PersistableBundle().apply { putBoolean("android.content.extra.IS_SENSITIVE", true) }
            (c.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(clip)
            copy.text = c.getString(R.string.copied); copy.setTextColor(MT.green)
        }
    }
    addView(copy, lp())
}

// ─────────────────────────── Data and Storage (iOS DataStorageView) ───────────────────────────

/**
 * DATA AND STORAGE: whether attachments come by themselves, and the backup by hand — made on this phone and handed to a
 * place the person picks through the system's own document picker, taken back from a file the same way. The iOS «Sync»
 * section is iCloud's: Android's daily copy goes to the person's own node («Your node»), not to a cloud of the platform.
 */
fun dataStoragePage(act: MainActivity, onBack: () -> Unit): View {
    val c: Context = act
    val progress = c.vstack(Gravity.NO_GRAVITY) { setPadding(dp(16), dp(10), dp(16), dp(12)); visibility = View.GONE }
    val progressWord = c.text("", 15f)
    val progressShare = c.text("", 13f, MT.gray)
    val bar = ProgressBar(c, null, android.R.attr.progressBarStyleHorizontal).apply { max = 100; progressTintList = ColorStateList.valueOf(Color.WHITE) }
    progress.addView(c.hstack { addView(progressWord, lp(0, WRAP, 1f)); addView(progressShare) }, lp())
    progress.addView(bar, lp())
    var working = false
    fun show(word: Int?, f: Double) = act.onMain {
        if (word == null) { progress.visibility = View.GONE; return@onMain }
        progress.visibility = View.VISIBLE
        progressWord.text = c.getString(word)
        progressShare.text = "${(f * 100).toInt()}%"   // USER-DATA: a share
        bar.progress = (f * 100).toInt()
    }
    fun say(s: String) = act.onMain { AlertDialog.Builder(act).setTitle(R.string.backup_header).setMessage(s).setPositiveButton(R.string.ok, null).show() }
    fun make() {
        if (working) return
        working = true
        act.background {
            val r = MontanaBackup.create(act) { show(R.string.sealing_copy, it) }
            show(null, 0.0); working = false
            when (r) {
                is CopyResult.Made -> act.onMain {
                    act.saveDocument(r.file.name) { uri ->
                        if (uri == null) { r.file.delete(); return@saveDocument }
                        act.background {
                            try {
                                act.contentResolver.openOutputStream(uri)?.use { out -> r.file.inputStream().use { it.copyTo(out, 1 shl 16) } }
                                say(act.getString(R.string.node_taken_by, r.tally.chats, r.tally.records, r.tally.media))
                            } catch (e: Exception) { say(Refusal.DiskRefused(e.javaClass.simpleName).spoken(act)) }
                            finally { r.file.delete() }
                        }
                    }
                }
                is CopyResult.Refused -> say(r.why.spoken(act))
                else -> {}
            }
        }
    }
    fun restore() {
        if (working) return
        AlertDialog.Builder(act).setTitle(R.string.restore_q).setMessage(R.string.restore_msg)
            .setPositiveButton(R.string.continue_word) { _, _ ->
                act.openDocument { uri ->
                    if (uri == null) return@openDocument
                    working = true
                    act.background {
                        val tmp = File(act.cacheDir, "restore.montana")
                        try {
                            act.contentResolver.openInputStream(uri)?.use { i -> tmp.outputStream().use { i.copyTo(it, 1 shl 16) } }
                            when (val r = MontanaBackup.restore(act, tmp) { show(R.string.restoring_backup, it) }) {
                                is CopyResult.Taken -> say(act.getString(R.string.node_taken_into, r.tally.chats, r.tally.records, r.tally.media))
                                is CopyResult.Refused -> say(r.why.spoken(act))
                                else -> {}
                            }
                        } catch (e: Exception) { say(Refusal.DiskRefused(e.javaClass.simpleName).spoken(act)) }
                        finally { tmp.delete(); show(null, 0.0); working = false }
                    }
                }
            }
            .setNegativeButton(R.string.cancel, null).show()
    }
    fun sw(res: Int, color: Int, word: Int, key: String) =
        c.switchLine(res, color, c.getString(word), Prefs.bool(key, true)) { Prefs.setBool(key, it) }
    return settingsPage(act, c.getString(R.string.data_storage), onBack) {
        section(c.getString(R.string.media_autodownload), c.getString(R.string.autodownload_footer),
            sw(R.drawable.ic_set_antenna, SysColor.green, R.string.over_mobile, "autoDownloadCellular"),
            sw(R.drawable.ic_set_wifi, SysColor.blue, R.string.over_wifi, "autoDownloadWiFi"))
        section(c.getString(R.string.backup_header), c.getString(R.string.backup_footer),
            c.settingsRow(R.drawable.ic_arrow_circle_up, SysColor.green, c.getString(R.string.create_backup), chevron = false) { make() },
            c.settingsRow(R.drawable.ic_arrow_circle_down, SysColor.orange, c.getString(R.string.restore_backup), chevron = false) { restore() },
            progress)
        keepingSection(act)   // the copy kept by the people one writes to (iOS MTKeepingSection, 08.10)
        // THE PICTURE CACHE (iOS MontanaSettings.swift:1225-1242 at 2155, MontanaCaches.dropAll; atom 542558a36f0e): the pictures kept
        // so chats and walls open without waiting are emptied here alone, by the person; the checkmark says it was done
        val cleared = c.icon(R.drawable.ic_check, MT.gray).apply { visibility = View.INVISIBLE }
        section(c.getString(R.string.picture_cache_header), c.getString(R.string.picture_cache_footer),
            c.settingsRow(R.drawable.ic_photo, SysColor.gray, c.getString(R.string.picture_cache_clear), value = cleared, chevron = false) {
                val n = Caches.dropAll()
                android.util.Log.d("Montana", "caches cleared=" + n + " by=person")
                cleared.visibility = View.VISIBLE
            })
    }
}
