package quest.montana.app

import android.app.AlertDialog
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Color
import android.os.Build
import android.os.PersistableBundle
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.GridLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/**
 * The first launch (iOS MontanaOnboardingView). Steps keep the iOS numbers:
 * 0 the doors, then the Montana road (intro) · 1 responsibility · 2 the words · 3 the name · 4 recovery ·
 * 5 the copy coming back from the person's own node.
 */
class Onboarding(private val act: MainActivity, private val onDone: () -> Unit) {
    val view = FrameLayout(act)
    private val content = FrameLayout(act)
    // In memory only: the words are never written anywhere but the device vault.
    private var bornWords: String? = null
    private var creating = false
    /** The doors screen chose Montana: the roads to a seed stand behind it (iOS montanaRoad, 29.09). */
    private var montanaRoad = false
    /** The person's own node, named beside the words (iOS nodeHost). */
    private var nodeHost = ""
    /** The person walked on without the copy: its late answer no longer speaks on this screen. */
    private var walkedOn = false
    /** The new person chose a ground: the pages of the making wear it from then on (iOS groundChosen, 30.09). */
    private var groundChosen = false
    private val ground = act.chatGround(ChatWall.PAGE).apply { visibility = View.GONE }

    init {
        view.addView(ground, FrameLayout.LayoutParams(MATCH, MATCH))
        view.addView(content, FrameLayout.LayoutParams(MATCH, MATCH))
        go(0)
    }

    private fun go(step: Int) {
        content.removeAllViews()
        // THE AUTHOR'S OWN GROUND (iOS 29.09): his picture under every step of the first screens, edge to edge;
        // the name's editor stands on its own black, as on iOS.
        // THE LOGIN PAGE IS BURGUNDY BY DEFAULT (iOS 2127-2133, the author's word 06.10.2026 15:1x MSK): his file as it came
        act.setBackdrop(if (step == 3 || groundChosen) null else R.drawable.montana_burgundy)
        ground.visibility = if (groundChosen && step != 3) View.VISIBLE else View.GONE   // the chosen ground, once chosen (iOS 2129-2130)
        val page: View = when (step) {
            0 -> if (montanaRoad) intro() else doors()
            1 -> responsibility()
            2 -> seedWords()
            3 -> Profile(act, onboarding = true, onFinish = onDone).view
            5 -> takingBack()
            else -> recover()
        }
        content.addView(page, FrameLayout.LayoutParams(MATCH, MATCH))
        act.back = when (step) {
            0 -> if (montanaRoad) ({ montanaRoad = false; go(0) }) else null
            1 -> { { go(0) } }
            2 -> { { go(1) } }
            4 -> { { go(0) } }
            else -> null
        }
        // THE ONE WAY BACK OF THE PATH (iOS 2188-2204, the author's word 29.09, 23:25): the back chevron on its glass circle,
        // top left where the system draws its own — one mark for every page of the path, never a grey word at the foot
        act.back?.let { b ->
            page.setPadding(page.paddingLeft, page.paddingTop + act.dp(28), page.paddingRight, page.paddingBottom)   // iOS .padding(.top, 28) under the mark
            content.addView(FrameLayout(act).apply {
                background = act.glassPlate(oval = true)
                contentDescription = act.getString(R.string.back)
                addView(act.icon(R.drawable.ic_arrow_back_ios_new, Color.rgb(204, 204, 204), 22), FrameLayout.LayoutParams(act.dp(22), act.dp(22), Gravity.CENTER))
                pressable { b() }
            }, FrameLayout.LayoutParams(act.dp(44), act.dp(44), Gravity.TOP or Gravity.START).apply { leftMargin = act.dp(12); topMargin = act.dp(4) })
        }
    }

    /** Page frame: black ground, 24dp padding, a column. */
    private fun page(build: LinearLayout.() -> Unit) = act.vstack {
        setPadding(dp(24), dp(24), dp(24), dp(24))
        clipChildren = false   // the logo's halo spreads past its own frame, as on iOS
        build()
    }

    // ── 0: intro ──
    private fun intro() = page {
        val c = context
        spacer()
        addView(c.glowingLogo(66, 300, 2300), lp(MATCH, dp(120)))
        gap(18)
        addView(c.text("Montana", 40f, Color.WHITE, bold = true, center = true))   // iOS Color.accentColor: white in the dark
        gap(18)
        addView(c.text(c.getString(R.string.intro_tagline), 15f, MT.gray, center = true).apply { setPadding(dp(20), 0, dp(20), 0) })
        gap(18)
        addView(c.vstack(Gravity.NO_GRAVITY) {
            privRow(R.drawable.ic_key, R.string.priv_words_title, R.string.priv_words_sub); gap(12)
            privRow(R.drawable.ic_shield, R.string.priv_e2e_title, R.string.priv_e2e_sub); gap(12)
            privRow(R.drawable.ic_credit_card, R.string.priv_wallet_title, R.string.priv_wallet_sub); gap(12)
            privRow(R.drawable.ic_hub, R.string.priv_servers_title, R.string.priv_servers_sub)
        })
        spacer()
        // EVERY ACT OF THE PATH IS A DOOR (iOS intro 2281-2291): the main act rimmed in the platform's blue, the second clear;
        // the account's door left this page for the page of opening (the author's word 29.09, 23:25)
        lateinit var create: PathDoor
        // THE GROUND COMES BEFORE THE PERSON (iOS 2167-2172, the author's word 30.09): the first «Create» opens my page's ground;
        // its checkmark makes the person
        create = PathDoor(c, c.getString(R.string.create), MT.blue) { if (bornWords == null && !groundChosen) chooseGround(create) else createSeed(create) }
        addView(create, lp())
        gap(18)
        addView(PathDoor(c, c.getString(R.string.open_identity)) { go(4) }, lp())
        gap(18)
        addView(c.text(versionFooter(c), 11f, MT.withAlpha(MT.gray, 0.7f), center = true))
    }

    private fun chooseCarried(all: List<MontanaBackupID.Carried>) {
        // USER-DATA: the moment a record was written, and how many devices wrote it
        val fmt = java.text.DateFormat.getDateTimeInstance(java.text.DateFormat.MEDIUM, java.text.DateFormat.SHORT)
        val lines = all.map { fmt.format(java.util.Date(it.at)) + if (it.devices > 1) " · ×${it.devices}" else "" }
        android.app.AlertDialog.Builder(act)
            .setTitle(R.string.which_identity)
            .setItems(lines.toTypedArray()) { _, i -> openCarried(all[i].words) }
            .show()
    }

    /** The seed the account carries opens this phone (iOS openCarried); the copy of the history comes with the network. */
    private fun openCarried(words: String) {
        if (creating) return
        creating = true
        act.background {
            val keys = SeedKeys.from(words)
            val stored = keys != null && MontanaSeed.enter(keys)
            act.onMain { creating = false; if (stored) onDone() else go(0) }
        }
    }

    // ── 0: the door (the author's design, iOS 29.09; iOS keeps the Montana door alone) ──
    private fun doors() = page {
        val c = context
        spacer()
        addView(ImageView(c).apply { setImageResource(R.drawable.icon_glass) }, lp(dp(120), dp(120)))
        gap(22)
        addView(c.text(c.getString(R.string.sign_in_title), 28f, Color.WHITE, bold = true, center = true))
        gap(6)
        addView(c.text(c.getString(R.string.sign_in_sub), 17f, MT.gray, center = true))
        spacer()
        addView(c.loginDoor(R.drawable.logo, c.getString(R.string.continue_montana)) {
            montanaRoad = true; go(0)
        }, lp())
        gap(14)
        addView(c.linkedText(c.getString(R.string.sign_in_footer), 11f, MT.gray, MT.withAlpha(Color.WHITE, 0.8f)) { url ->
            when (url) {
                "montana://terms" -> act.showTermsSheet()
                "montana://privacy" -> runCatching { act.startActivity(android.content.Intent(android.content.Intent.ACTION_VIEW, android.net.Uri.parse(PRIVACY_URL))) }
            }
        }.apply { setPadding(dp(12), 0, dp(12), 0) }, lp())
    }

    private fun LinearLayout.privRow(iconRes: Int, title: Int, sub: Int) {
        val c = context
        addView(c.hstack {
            addView(c.icon(iconRes, Color.WHITE), LinearLayout.LayoutParams(dp(24), dp(24)).apply { marginEnd = dp(16) })
            addView(c.vstack(Gravity.NO_GRAVITY) {
                addView(c.text(c.getString(title), 15f, Color.WHITE, bold = true))
                addView(c.text(c.getString(sub), 12f, MT.gray))
            }, lp(0, WRAP, 1f))
        }, lp())
    }

    private fun chooseGround(button: PathDoor) {
        act.push { close ->
            wallpaperPicker(act, ChatWall.PAGE) {   // iOS shows no cross here; Android's bar cross closes as its checkmark does
                close()
                groundChosen = true
                act.setBackdrop(null); ground.visibility = View.VISIBLE   // the page under the door wears the chosen ground at once
                createSeed(button)
            }
        }
    }

    /** A person is born as an identity by their own act — the tap on «Create» — and by no other event. */
    private fun createSeed(button: PathDoor) {
        if (bornWords != null) { go(1); return }
        if (creating) return
        creating = true
        button.setBusy(true); button.setTitle(act.getString(R.string.creating))
        act.background {
            val keys = SeedKeys.generate()
            val stored = keys != null && MontanaSeed.enter(keys)
            act.onMain {
                creating = false
                button.setBusy(false); button.setTitle(act.getString(R.string.create))
                if (!stored) {
                    AlertDialog.Builder(act)
                        .setTitle(R.string.store_failed_title).setMessage(R.string.store_failed_msg)
                        .setPositiveButton(R.string.got_it, null).show()
                } else {
                    bornWords = keys!!.mnemonic
                    go(1)
                }
            }
        }
    }

    // ── 1: full control — full responsibility ──
    private fun responsibility() = page {
        val c = context
        lateinit var next: PathDoor
        spacer()
        addView(c.icon(R.drawable.ic_gpp_maybe, MT.orange, 52))
        gap(18)
        addView(c.text(c.getString(R.string.resp_title), 20f, Color.WHITE, bold = true, center = true))
        gap(18)
        addView(c.text(c.getString(R.string.resp_body), 15f, MT.gray))
        gap(18)
        addView(c.toggleRow(c.getString(R.string.resp_toggle)) { next.setOn(it) }, lp())
        spacer()
        next = PathDoor(c, c.getString(R.string.show_words), MT.blue) { go(2) }.apply { setOn(false) }
        addView(next, lp())
    }

    // ── 2: the 24 words ──
    private fun seedWords() = page {
        val c = context
        val words = (bornWords ?: MontanaSeed.mnemonic ?: "").split(' ')
        addView(c.text(c.getString(R.string.seed_title), 20f, Color.WHITE, bold = true, center = true))
        gap(14)
        addView(c.text(c.getString(R.string.seed_hint), 12f, MT.gray, center = true))
        gap(14)
        // Two columns read top to bottom, as on iOS: 1 | 13, 2 | 14, …
        val half = (words.size + 1) / 2
        val order = (0 until half).flatMap { r -> if (r + half < words.size) listOf(r, r + half) else listOf(r) }
        val grid = GridLayout(c).apply { columnCount = 2 }
        order.forEach { i ->
            val cell = c.hstack {
                background = c.rounded(MT.plate, 8)
                setPadding(dp(7), dp(7), dp(7), dp(7))
                addView(c.text("${i + 1}.", 15f, MT.gray).apply { gravity = Gravity.END }, lp(dp(26), WRAP))
                gap(6)
                addView(c.text(words[i], 15f, Color.WHITE, bold = true))
            }
            grid.addView(cell, GridLayout.LayoutParams(GridLayout.spec(GridLayout.UNDEFINED), GridLayout.spec(GridLayout.UNDEFINED, 1f)).apply {
                width = 0; setMargins(dp(4), dp(4), dp(4), dp(4))
            })
        }
        addView(ScrollView(c).apply { addView(grid) }, lp(MATCH, 0, 1f))
        gap(14)
        // copying the words is an act of the path too: a clear door (iOS 2653-2655)
        lateinit var copy: PathDoor
        copy = PathDoor(c, c.getString(R.string.copy)) { copySecret(c, words.joinToString(" ")); copy.setTitle(c.getString(R.string.copied)) }
        addView(copy, lp())
        gap(10)
        lateinit var done: PathDoor
        addView(c.toggleRow(c.getString(R.string.seed_saved)) { done.setOn(it) }, lp())
        gap(14)
        done = PathDoor(c, c.getString(R.string.seed_done), MT.blue) { go(3) }.apply { setOn(false) }
        addView(done, lp())
    }.keepsSecret()   // no screenshot, no recording, black in the recent apps while the words stand here

    /** The words go to the clipboard marked sensitive, so the system does not show them in its preview. */
    private fun copySecret(ctx: Context, text: String) {
        val clip = ClipData.newPlainText("Montana", text)
        if (Build.VERSION.SDK_INT >= 33) {
            clip.description.extras = PersistableBundle().apply { putBoolean("android.content.extra.IS_SENSITIVE", true) }
        }
        (ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(clip)
    }

    // ── 4: recovery from the phrase ──
    private fun recover() = page {
        val c = context
        fun field(hint: String?, lines: Int) = EditText(c).apply {
            background = c.rounded(MT.plate, 10)
            setTextColor(Color.WHITE); setHintTextColor(MT.gray)
            setPadding(dp(12), dp(10), dp(12), dp(10))
            if (hint != null) this.hint = hint
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS or
                (if (lines > 1) InputType.TYPE_TEXT_FLAG_MULTI_LINE else InputType.TYPE_TEXT_VARIATION_URI)
            // The phrase is a secret: the keyboard neither learns it nor suggests it.
            imeOptions = imeOptions or 0x1000000 /* IME_FLAG_NO_PERSONALIZED_LEARNING */
            gravity = Gravity.TOP or Gravity.START
            if (lines > 1) { minLines = lines; maxLines = lines } else isSingleLine = true
        }
        gap(6)
        addView(c.icon(R.drawable.ic_restore, Color.WHITE, 46))
        gap(16)
        addView(c.text(c.getString(R.string.recover_title), 20f, Color.WHITE, bold = true, center = true))
        gap(16)
        addView(c.text(c.getString(R.string.recover_hint), 12f, MT.gray, center = true))
        gap(16)
        val input = field(null, 5)
        addView(input, lp(MATCH, dp(130)))
        gap(16)
        // THE PERSON'S OWN NODE, named beside the words (iOS 28.09): the copy it holds comes back before the first screen.
        val node = field(c.getString(R.string.recover_node), 1).apply { setText(nodeHost) }
        addView(node, lp())
        val error = c.text("", 12f, MT.red, center = true).apply { visibility = View.GONE }
        gap(16)
        addView(error, lp())
        gap(16)
        lateinit var restore: PathDoor
        restore = PathDoor(c, c.getString(R.string.restore), MT.blue) {
            val words = input.text.toString().lowercase().split(' ', '\n', ',').filter { it.isNotEmpty() }
            fun say(s: String) { error.text = s; error.visibility = View.VISIBLE }
            if (words.size != 24) { say(c.getString(R.string.words_count, words.size)); return@PathDoor }
            error.visibility = View.GONE
            restore.setBusy(true); restore.setTitle(c.getString(R.string.restoring))
            act.background {
                val keys = SeedKeys.from(words.joinToString(" "))
                val stored = keys != null && MontanaSeed.enter(keys)
                act.onMain {
                    restore.setBusy(false); restore.setTitle(c.getString(R.string.restore))
                    when {
                        keys == null -> say(c.getString(R.string.recover_invalid))
                        !stored -> say(c.getString(R.string.store_failed_title))
                        else -> { nodeHost = node.text.toString(); takeFromNode() }
                    }
                }
            }
        }
        addView(restore, lp())
        // THE ACCOUNT ALREADY HOLDS A SEED (iOS recover 2357-2387): beside the words, a clear door; more than one — the person
        // chooses. The account is asked while the page stands, every three seconds: its record comes after the sign-in.
        val carried = PathDoor(c, c.getString(R.string.continue_backup)) {
            val all = MontanaBackupID.held()
            if (all.size == 1) openCarried(all[0].words) else if (all.isNotEmpty()) chooseCarried(all)
        }.apply { visibility = View.GONE }
        addView(carried, lp().apply { topMargin = dp(16) })
        val ask = object : Runnable {
            override fun run() {
                if (!carried.isAttachedToWindow) return
                carried.visibility = if (MontanaBackupID.held().isEmpty()) View.GONE else View.VISIBLE
                carried.postDelayed(this, 3000)
            }
        }
        carried.post(ask)
        spacer()
    }

    // ── 5: the copy coming back ──

    /** THE WORDS OPENED; THE PERSON'S OWN NODE, IF NAMED, HANDS THE COPY BACK (iOS takeFromNode) — otherwise the first screen. */
    private fun takeFromNode() {
        val h = nodeHost.trim()
        if (h.isEmpty()) return onDone()
        MontanaHomeNode.setHost(h)
        MontanaHomeNode.setOn(act, true)
        walkedOn = false
        go(5)
        act.background {
            HomeNodeWatch.takeBack(act) { r ->
                act.onMain {
                    HomeNodeWatch.onChange = null
                    if (!walkedOn) when (r) {
                        is CopyResult.Taken -> onDone()
                        // EVERY REFUSAL ON THE WAY BACK IS SPOKEN (iOS 28.09), with «Try again» and the way on without the copy.
                        is CopyResult.Refused -> refuse(r.why.spoken(act)) { takeFromNode() }
                        is CopyResult.Made -> onDone()   // a copy made here never answers a taking back
                    }
                }
            }
        }
    }

    private fun refuse(word: String, again: () -> Unit) {
        AlertDialog.Builder(act)
            .setTitle(R.string.your_history).setMessage(word)
            .setPositiveButton(R.string.try_again) { _, _ -> again() }
            .setNegativeButton(R.string.go_on_without_copy) { _, _ -> onDone() }
            .setCancelable(false).show()
    }

    private fun takingBack() = page {
        val c = context
        spacer()
        addView(c.icon(R.drawable.ic_arrow_circle_down, Color.WHITE, 46))
        gap(16)
        addView(c.text(c.getString(R.string.taking_back), 20f, Color.WHITE, bold = true, center = true))
        gap(16)
        val bar = android.widget.ProgressBar(c, null, android.R.attr.progressBarStyleHorizontal).apply {
            max = 100
            progressTintList = android.content.res.ColorStateList.valueOf(Color.WHITE)
            indeterminateTintList = progressTintList
        }
        addView(bar, lp().apply { marginStart = dp(24); marginEnd = dp(24) })
        gap(8)
        val pct = c.text("", 12f, MT.gray, center = true)
        addView(pct, lp())
        spacer()
        // The person may walk on without the copy while nothing is being laid into this device: a copy half laid is
        // not a state to leave in (iOS canGoOn).
        val without = PathDoor(c, c.getString(R.string.go_on_without_copy)) { walkedOn = true; HomeNodeWatch.onChange = null; onDone() }
        addView(without, lp())
        fun show() {
            val f = HomeNodeWatch.fetching ?: HomeNodeWatch.restoring
            bar.isIndeterminate = f == null
            if (f != null) bar.progress = (f * 100).toInt()
            pct.text = if (f == null) "" else "${(f * 100).toInt()}%"   // USER-DATA: a share
            without.visibility = if (HomeNodeWatch.restoring == null) View.VISIBLE else View.GONE
        }
        show()
        HomeNodeWatch.onChange = { act.onMain { if (isAttachedToWindow) show() } }
    }
}

/** The version as scripts/version makes it: "1.0 (31 → 1277)" while catching up with iOS, "1.0 (1277)" once level. */
private fun versionName(c: Context): String =
    c.packageManager.getPackageInfo(c.packageName, 0).versionName ?: "—"

/** iOS AppVersion.full: "v<version> (<build>)". */
fun appVersionFull(c: Context): String = "v${versionName(c)}"

/** iOS MontanaVersion.footer: "<platform> <version> (<build>) · SSOT <core ABI>". */
fun versionFooter(c: Context): String =
    "Android ${versionName(c)} · SSOT ${MtBindings.nativeAbiVersion()}"

/** The privacy policy on the site (iOS MontanaSafety.privacy). */
const val PRIVACY_URL = "https://montana.quest/privacy/"
