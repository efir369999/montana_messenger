package quest.montana.app

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.view.View
import android.view.WindowInsets
import android.widget.FrameLayout
import java.util.concurrent.Executors

class MainActivity : Activity() {
    /** The window's whole surface: the backdrop runs under the system bars (iOS .ignoresSafeArea()). */
    private lateinit var surface: FrameLayout
    private lateinit var backdrop: android.widget.ImageView
    /** The pages: inside the system bars and above the keyboard. */
    private lateinit var root: FrameLayout
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()

    /** What the system back gesture does on the current page; null — the app's root, which the back never leaves. */
    var back: (() -> Unit)? = null
    /** The home's drawer: at the app's root the system's back from the screen's left edge opens it (Home.kt's DrawerShell). */
    var drawer: DrawerShell? = null
    private var edgeOpens = false
    /** The pushed page the platform's own predictive back drags one to one with the finger (iOS MontanaSlideHost's
     *  screen-edge pan, ContentView.swift:817-910); null when the current back target has no page to slide — the
     *  drawer's own close, a search field closing (Home.kt:320, Screens.kt:215). */
    private var slidingPage: View? = null

    // The screen's state (iOS RootView @State)
    private var hasSeed = false
    private var termsAccepted = false
    private var showWelcome = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        DeviceVault.init(this)
        Prefs.init(this)
        Book.ctx = applicationContext
        window.setDecorFitsSystemWindows(false)
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT
        surface = FrameLayout(this).apply { setBackgroundColor(Color.BLACK) }
        backdrop = android.widget.ImageView(this).apply { scaleType = android.widget.ImageView.ScaleType.CENTER_CROP }
        root = FrameLayout(this)
        surface.addView(backdrop, FrameLayout.LayoutParams(MATCH, MATCH))
        surface.addView(root, FrameLayout.LayoutParams(MATCH, MATCH))
        // The page stands inside the system bars and above the keyboard.
        root.setOnApplyWindowInsetsListener { v, insets ->
            val b = insets.getInsets(WindowInsets.Type.systemBars() or WindowInsets.Type.ime())
            v.setPadding(b.left, b.top, b.right, b.bottom)
            WindowInsets.CONSUMED
        }
        // THE KEYBOARD'S RISE AND FALL ARE MEASURED (iOS MTKeyboard will-show/will-hide to did-show/did-hide, atom b19d306a9d08): the
        // platform's own animation of the keys begins and ends the one frame meter; nothing of the insets' own handling changes
        if (30 <= Build.VERSION.SDK_INT) root.setWindowInsetsAnimationCallback(object : android.view.WindowInsetsAnimation.Callback(android.view.WindowInsetsAnimation.Callback.DISPATCH_MODE_CONTINUE_ON_SUBTREE) {
            private fun keys(a: android.view.WindowInsetsAnimation) = (a.typeMask and WindowInsets.Type.ime()) != 0
            override fun onStart(a: android.view.WindowInsetsAnimation, bounds: android.view.WindowInsetsAnimation.Bounds): android.view.WindowInsetsAnimation.Bounds {
                if (keys(a)) Motion.moveBegan(root)
                return bounds
            }
            override fun onProgress(insets: WindowInsets, running: MutableList<android.view.WindowInsetsAnimation>): WindowInsets = insets
            override fun onEnd(a: android.view.WindowInsetsAnimation) {
                if (keys(a)) Motion.moveEnded("keyboard:" + (if (root.rootWindowInsets?.isVisible(WindowInsets.Type.ime()) == true) "rise" else "fall"))
            }
        })
        setContentView(surface)
        registerBack()
        hasSeed = MontanaSeed.hasSeed
        termsAccepted = Prefs.termsAccepted
        render()
        Scheduled.run()   // the app's clock for letters sent later (Schedule.kt)
        Diary.start(this)   // the diary on disk and its shipper (iOS MontanaLog, MontanaDiagShip; 1340)
        Thread { Names.agreesWithCanon }.start()   // the core's name derivations against the Canon's own values, said once in the diary (names_canon)
        Exits.witness(this)   // how the last run ended, said once (iOS run sentinel, 1336)
        CallEngine.warm(this)   // the call engine stands from launch, as iOS MontanaCall.shared
        // «Share → Montana» from another app, else an invitation's link
        if (takeUpdate(intent)) return
        if (takeCall(intent)) return
        // A LINK OR A SHARE IS TAKEN ONCE (iOS handleLink: one link, one handling): a page the system rebuilt, or a task brought
        // back from the recent apps, carries the intent that once made it — the invitation opened anew and an expired card was
        // said expired every time the app came back.
        val handed = savedInstanceState == null && (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) == 0
        if (handed && !takeShared(intent, hasSeed && termsAccepted)) intent?.data?.let { openLink(it.toString()) }
    }

    /**
     * THE RING'S OWN PAGE (Calls): its conversation opens, and over it the call's screen while the call is in hand; «Answer»
     * takes the call first, the microphone asked once.
     */
    private fun takeCall(i: Intent?): Boolean {
        val ref = i?.getStringExtra(Calls.EXTRA_REF) ?: return false
        val answer = i.getBooleanExtra(Calls.EXTRA_ANSWER, false)
        i.removeExtra(Calls.EXTRA_REF)
        if (hasSeed && termsAccepted && Book.chat(ref) != null) push { close -> conversationPage(this, ref, close) }
        val asks = callAsks(Calls.ringVideo())
        if (answer && asks.isNotEmpty()) requestPermissions(asks, ASK_CALL_MIC) else takeTheCall(answer)
        return true
    }

    /** «Call» and «Video Call» (iOS startCall from the person's page and the calls' row): what the call needs asked once, then the call and its screen. */
    fun callOut(ref: String, video: Boolean = false) {
        val asks = callAsks(video)
        if (asks.isNotEmpty()) { pendingCall = ref; pendingVideo = video; requestPermissions(asks, ASK_CALL_OUT); return }
        if (Calls.dial(ref, video)) CallScreen.show(this, ref)
    }
    private var pendingCall: String? = null
    private var pendingVideo = false

    /** What a call still needs asked (iOS: the microphone, and the camera for a video call): asked together, once. */
    private fun callAsks(video: Boolean): Array<String> = listOfNotNull(
        android.Manifest.permission.RECORD_AUDIO.takeIf { !VoiceTape.granted(this) },
        android.Manifest.permission.CAMERA.takeIf { video && checkSelfPermission(it) != android.content.pm.PackageManager.PERMISSION_GRANTED }
            ?.also { Prefs.setBool(CallLine.CAM_ASKED, true) }   // asked here, the capture road's gate tells a refusal, never asks twice
    ).toTypedArray()

    /** The new version's notice tapped (Update): the app brings it and hands it to the system's installer. */
    private fun takeUpdate(i: Intent?): Boolean {
        if (i?.action != Update.ACTION) return false
        i.action = null
        Update.take(this)
        return true
    }

    /** iOS acceptCall: the call's screen stands at once («Connecting…»), not after the voice joins. */
    private fun takeTheCall(answer: Boolean) {
        if (answer) Calls.answer()
        Calls.held()?.let { CallScreen.show(this, it) }
    }

    /** AN INVITATION HANDED IN BY THE SYSTEM (iOS handleLink): opened now, or kept until the identity exists. */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (takeUpdate(intent)) return
        if (takeCall(intent)) return
        if (!takeShared(intent, hasSeed && termsAccepted)) intent.data?.let { openLink(it.toString()) }
    }
    fun openLink(link: String) {
        // A WALL'S LINK OPENS THE POST HELD HERE, CHECKED FIRST (iOS MontanaFirstContact.handleLink:1855, MontanaBoardViews.swift
        // MTBoardComments.open/target:2414-2433): a long link to a post or comment this phone holds opens its comments page,
        // scrolled to a comment's own link; a wall link to a post not held here is said so, never read as a spent invitation.
        if (Board.isWallLink(link)) {
            if (hasSeed && termsAccepted) {
                val t = Board.linkTarget(link)
                if (t != null) push { close -> wallCommentsPage(this, t.wall, t.post, close, t.comment) }
                else sayVerdict(this, R.string.wall_link_not_held)
            }
            return
        }
        // A COIN'S LINK OPENS THE WALLET (iOS handleLink 1871-1877, the author's word 03.10): the coin letter's machine line is no
        // invitation, and the invitation road answered it «could not be opened».
        if (Meeting.normalize(link).startsWith(CoinLetter.LINK.substringBefore("/1/"))) {
            if (hasSeed && termsAccepted) push { close -> walletPage(this, close) }
            return
        }
        if (!hasSeed || !termsAccepted) {
            Prefs.setStr("pendingInvite", link)
            sayVerdict(this, R.string.invite_wait)
            return
        }
        openInvitation(this, link)
    }

    /**
     * The one question the first screen asks (iOS RootView): does this device hold a person.
     * The answer is the seed itself — no second marker that could disagree with it.
     *   no seed → the first launch · seed, no terms → the terms · just born → the sign · else → main
     */
    private fun render() {
        back = null
        setBackdrop(null)
        val page: View = when {
            !hasSeed -> Onboarding(this) {
                hasSeed = MontanaSeed.hasSeed
                showWelcome = hasSeed
                render()
            }.view
            !termsAccepted -> termsGate(this, onAgree = { Prefs.termsAccepted = true; termsAccepted = true; render() })
            showWelcome -> welcome(this) { showWelcome = false; render() }
            else -> mainScreen(this) {
                // «Forget this device» (iOS: Privacy): first the archive seals what the words can reopen — every head, name and face
                // (iOS sealForForget) — then the seed and everything of the person leave; the sealed history stays for the 24 words.
                Archive.sealForForget {
                    MontanaSeed.clear(); Archive.forgetKeys(); Prefs.forgetPerson(); SelfFace.clear(this); SavedMessages.forget(this)
                    MontanaHomeNode.forget(this); MontanaBackup.forget(this); MontanaCard.forget(); Book.wipe()
                    MontanaBackupID.withdrawOwn(this)   // this installation's record leaves the account; a twin's stands
                    hasSeed = false; termsAccepted = false
                    render()
                }
            }
        }
        show(page)
        if (hasSeed) MontanaBackupID.publish(this)   // the account carries this device's words (iOS publish)
        if (hasSeed && termsAccepted && !showWelcome) askWhatIsUnasked()
        // THE DAILY ROAD to the person's own node, a little after the first screen stands (iOS tickSoon).
        if (hasSeed && termsAccepted) HomeNodeWatch.tickSoon(this)
        if (hasSeed && termsAccepted) Archive.atLaunch()   // the archive read into the feed's empty conversations (iOS cold start 15.10)
        // The identity is born: the invitation that waited for it opens by itself (iOS replayPendingInvite).
        if (hasSeed && termsAccepted && !showWelcome) Prefs.str("pendingInvite", "").takeIf { it.isNotEmpty() }?.let { Prefs.remove("pendingInvite"); openInvitation(this, it) }
    }

    /**
     * iOS askWhatIsUnasked: nobody is asked anything before they hold an identity; then exactly ONE
     * question, and it is the system's own — notifications. Asked once; the answer is the system's.
     */
    private fun askWhatIsUnasked() {
        if (Prefs.notifyAsked) return askDoze()
        Prefs.notifyAsked = true
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), ASK_NOTIFY)
        }
    }

    /**
     * THE EAR'S ONE QUESTION (EarService), the next time after the notifications' one: the system's own question whether the app
     * may keep its line while the phone dozes — without it a call to a sleeping phone waits for the doze's next window. Asked once.
     */
    private fun askDoze() {
        if (Prefs.str("dozeAsked", "").isNotEmpty()) return
        val pm = getSystemService(android.os.PowerManager::class.java) ?: return
        if (pm.isIgnoringBatteryOptimizations(packageName)) return
        Prefs.setStr("dozeAsked", "1")
        runCatching { startActivity(Intent(android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:" + packageName))) }
    }

    /** A picture under the whole window, system bars included; null — the plain black. */
    fun setBackdrop(res: Int?) {
        if (res == null) backdrop.setImageDrawable(null) else backdrop.setImageResource(res)
        ground?.let { surface.removeView(it) }; ground = null
    }

    /** A drawn ground under the whole window, system bars included (iOS MontanaCrestGround's .ignoresSafeArea()). */
    private var ground: View? = null
    fun setGround(v: View) {
        ground?.let { surface.removeView(it) }
        ground = v
        surface.addView(v, 1, FrameLayout.LayoutParams(MATCH, MATCH))   // over the backdrop, under the pages
    }

    /** Replaces the page with a short cross-fade. */
    private fun show(page: View) {
        page.alpha = 0f
        root.removeAllViews()
        root.addView(page, FrameLayout.LayoutParams(MATCH, MATCH))
        page.animate().alpha(1f).setDuration(220).start()
    }

    /**
     * A page over the current one, full screen: rides in from the trailing edge and leaves the same way — the
     * platform's own predictive back drags it one to one with the finger on API 34 (registerBack below), a plain
     * press settles it on older systems; the returned close does the same slide (iOS MontanaSlideHost's screen-edge
     * pan, ContentView.swift:687-910). The screen's left edge stays the system gesture's, not a view's own pan — the
     * drawer already made that choice (Home.kt's DrawerShell, line 266).
     */
    fun overlay(page: View): () -> Unit {
        val keepBack = back
        val keepSliding = slidingPage
        var open = true
        // the page's marks stand inside the system bars, as every page's do
        page.setPadding(root.paddingLeft, root.paddingTop, root.paddingRight, root.paddingBottom)
        surface.addView(page, FrameLayout.LayoutParams(MATCH, MATCH))
        val width = surface.width.takeIf { it > 0 }?.toFloat() ?: resources.displayMetrics.widthPixels.toFloat()
        page.translationX = width
        val close = {
            if (open) {
                open = false
                back = keepBack; slidingPage = keepSliding
                settle(page, width, out = true) { surface.removeView(page) }
            }
        }
        settle(page, width, out = false)
        back = close
        slidingPage = page
        return close
    }

    /**
     * A CLOUD OVER THE SCREEN (iOS MTPersonMenu and MessageContextOverlay: the platform's ultra-thin material over everything, then
     * the menu's own spring): the page stands at once, no slide, and all that lies under it is blurred while it stands. `onBack` is
     * the cloud's own leave; the returned function takes the page away at once.
     */
    fun cloud(page: View, onBack: () -> Unit): () -> Unit {
        val keepBack = back
        val keepSliding = slidingPage
        page.setPadding(root.paddingLeft, root.paddingTop, root.paddingRight, root.paddingBottom)
        val under = (0 until surface.childCount).map { surface.getChildAt(it) }
        if (31 <= Build.VERSION.SDK_INT) for (v in under) v.setRenderEffect(android.graphics.RenderEffect.createBlurEffect(dp(14).toFloat(), dp(14).toFloat(), android.graphics.Shader.TileMode.CLAMP))
        surface.addView(page, FrameLayout.LayoutParams(MATCH, MATCH))
        var open = true
        back = onBack
        slidingPage = null
        return {
            if (open) {
                open = false
                back = keepBack; slidingPage = keepSliding
                if (31 <= Build.VERSION.SDK_INT) for (v in under) v.setRenderEffect(null)
                surface.removeView(page)
            }
        }
    }

    /** The slide itself, scaled by how far the page already stands (the drawer's same spring, Home.kt's
     *  DrawerShell.settle): a page the predictive back already dragged near its edge does not visibly restart. */
    private fun settle(page: View, width: Float, out: Boolean, onDone: (() -> Unit)? = null) {
        val to = if (out) width else 0f
        val ms = (220 * kotlin.math.abs(to - page.translationX) / width.coerceAtLeast(1f)).toLong().coerceIn(90, 220)
        // THE PAGE'S TRANSITION, MEASURED (iOS MTPageMeter, MontanaPeerHeader.swift:507-528; moveBegan/moveEnded named
        // «motion», MontanaMessageFeed.swift:349-355): one diary line per push and back, to the slide's own end.
        Motion.moveBegan(page)
        page.animate().translationX(to).setDuration(ms).setInterpolator(android.view.animation.DecelerateInterpolator(1.6f))
            .withEndAction { Motion.moveEnded("page:" + (if (out) "back" else "push")); onDone?.invoke() }.start()
    }

    /**
     * THE PLATFORM'S OWN BACK (iOS MontanaSlideHost's screen-edge pan, ContentView.swift:817-910): the screen's left
     * edge is the system gesture's, not a view's own pan (the drawer's same choice, Home.kt's DrawerShell, line 266)
     * — a pushed page rides the predictive back the system already tracks one to one with the finger (BackEvent.touchX)
     * on API 34; older systems and the three-button bar have no such preview, and still leave by the same slide, never
     * a fade.
     */
    private fun registerBack() {
        if (Build.VERSION.SDK_INT < 33) return   // no OnBackInvokedDispatcher below 33: the deprecated onBackPressed is the only road
        val callback = if (Build.VERSION.SDK_INT >= 34) object : android.window.OnBackAnimationCallback {
            override fun onBackStarted(e: android.window.BackEvent) {
                keysDown()
                slidingPage?.animate()?.cancel()
                edgeOpens = back == null && slidingPage == null && e.swipeEdge == android.window.BackEvent.EDGE_LEFT && drawer != null
                if (edgeOpens) drawer?.edgeBegin()
            }
            override fun onBackProgressed(e: android.window.BackEvent) {
                if (edgeOpens) { drawer?.edgeMove(e.touchX); return }
                // the left edge drags the page one to one with the finger; the right edge has no such finger on the page — its progress
                slidingPage?.let { it.translationX = if (e.swipeEdge == android.window.BackEvent.EDGE_RIGHT) e.progress * surface.width else e.touchX.coerceAtLeast(0f) }
            }
            override fun onBackInvoked() = commitBack()
            override fun onBackCancelled() {
                if (edgeOpens) { edgeOpens = false; drawer?.edgeEnd(false); return }
                slidingPage?.let { settle(it, surface.width.toFloat(), out = false) }
            }
        } else android.window.OnBackInvokedCallback { commitBack() }
        onBackInvokedDispatcher.registerOnBackInvokedCallback(android.window.OnBackInvokedDispatcher.PRIORITY_DEFAULT, callback)
    }
    /**
     * THE BACK NEVER LEAVES THE APP (the author's word 09.10.2026 11:5x MSK: «take away the side swipe that leaves the app -- our swipe from
     * the left opens the side panel»): a page goes back as before; at the root the left edge's stroke opens the drawer it was dragging
     * (iOS MontanaDrawerHost: the drawer opens by a drag from the screen's left edge), and any other back there does nothing.
     */
    private fun commitBack() {
        val b = back
        when {
            b != null -> b()
            edgeOpens -> { edgeOpens = false; drawer?.edgeEnd(true) }
            Build.VERSION.SDK_INT < 34 -> drawer?.open()   // no edge is told below 34: the root's back is the drawer's
        }
    }
    /**
     * THE KEYBOARD LEAVES WITH THE SCREEN (iOS MontanaSlideHost.pan .began, ContentView.swift:880-884, the author's word 18.09: it hung
     * over the chats after the back swipe): the field that holds it lets go at the first movement of the back.
     */
    private fun keysDown() {
        val f = window.decorView.findFocus() ?: return
        getSystemService(android.view.inputmethod.InputMethodManager::class.java).hideSoftInputFromWindow(f.windowToken, 0)
        f.clearFocus()
    }

    /** The terms over the current page (iOS: a sheet from the doors' footer); back or its mark closes it. */
    fun showTermsSheet() {
        val keepBack = back
        lateinit var sheet: View
        val close = { root.removeView(sheet); back = keepBack }
        sheet = termsGate(this, onAgree = null, onClose = close)
        sheet.translationY = root.height.toFloat()
        root.addView(sheet, FrameLayout.LayoutParams(MATCH, MATCH))
        Motion.moveBegan(sheet)   // a sheet risen, measured to its end (iOS montanaMotionMeter on the sheets, atom 2f90be6bfda9)
        sheet.animate().translationY(0f).setDuration(280).setInterpolator(android.view.animation.DecelerateInterpolator())
            .withEndAction { Motion.moveEnded("sheet:rise") }.start()
        back = close
    }

    // ── THE BOX IS READ WHILE THE APP STANDS (iOS fetchBox on activation and by its kick): at once, then every eight seconds ──
    private val boxRound = object : Runnable {
        override fun run() {
            if (hasSeed && termsAccepted) { Signal.ear(true); Thread { Post.fetch() }.start() }   // a conversation born since is heard too
            main.postDelayed(this, 8000)
        }
    }
    override fun onResume() {
        super.onResume(); CallScreen.front = this; main.removeCallbacks(boxRound); main.post(boxRound); EarService.start(this)
        if (hasSeed && termsAccepted) Calls.rejoinHeldCall(this)   // the run goes back into the call its process held, once the app faces the person
        Thread { Update.look(applicationContext) }.start()   // a newer build on the site rings its notice (Update)
        if (hasSeed && termsAccepted) Thread { Signal.sweep() }.start()   // every peer's last word, one question (iOS ContentView 471)
        if (hasSeed && termsAccepted) Thread { LiveDraft.sayLinkToAll() }.start()   // the daily link, preloaded to every correspondent (iOS ContentView.swift:472)
        if (hasSeed && termsAccepted) Thread { Book.healFacesFromCards() }.start()   // a faceless correspondent is read from their card at once (iOS MontanaChatStore.swift:1916, atom 796a76a34ae0)
        if (hasSeed && termsAccepted) Thread { MontanaCard.keepLiveCardsUp(applicationContext) }.start()   // the live cards turn and top up on every return (iOS MontanaApp.swift:297)
        if (hasSeed && termsAccepted) Thread { NamePlane.keepInStep() }.start()   // the name renewed when due, its point listened at (iOS keepInStep)
        Thread { CoinBook.warm(); CoinSend.settle(); ChessSend.settleAll() }.start()
        // THE WALLS AT A RETURN (iOS ContentView.swift:474-477 at 2155): every wall never seen is asked (Board.sweep), and the owner carries
        // my wall to whoever speaks it -- at a return only while the presence is shown (the critic's N6)
        if (hasSeed && termsAccepted) Thread { Board.sweep(); if (Presence.sharing) MyWall.schedulePush() }.start()
        if (hasSeed && termsAccepted) Thread { MyWall.roadBack("active") }.start()   // a post on its way goes on by itself (iOS roadBack 1922)   // every coin letter the chats hold stands in the book (iOS MTCoinSend.settle)
    }
    // the ear stays when the app leaves the screen: EarService holds it (the app closed is heard as the app open)
    override fun onPause() { super.onPause(); CoinBook.closeWindows(); if (CallScreen.front === this) CallScreen.front = null; main.removeCallbacks(boxRound) }

    // THE CALL'S WINDOW OVER OTHER APPS (CallFloat): the person leaving on a system before the platform's auto-enter, and the
    // platform's own word that the window stands or is gone
    override fun onUserLeaveHint() { super.onUserLeaveHint(); CallFloat.leaving(this) }
    override fun onPictureInPictureModeChanged(inPip: Boolean, cfg: android.content.res.Configuration) {
        super.onPictureInPictureModeChanged(inPip, cfg)
        CallFloat.changed(this, inPip)
    }

    /** A small view over every page and every overlay (the call's pill), at the foot above the system bar; the close takes it away. */
    fun floating(v: View, bottomDp: Int): () -> Unit {
        val deck = window.decorView as FrameLayout
        deck.addView(v, FrameLayout.LayoutParams(WRAP, WRAP, android.view.Gravity.BOTTOM or android.view.Gravity.CENTER_HORIZONTAL)
            .apply { bottomMargin = root.paddingBottom + dp(bottomDp) })
        return { deck.removeView(v) }
    }

    /** «Accept» on the in-app ring (CallScreen): the microphone asked once, then the call and its screen. */
    fun answerCall() {
        val asks = callAsks(Calls.ringVideo())
        if (asks.isEmpty()) takeTheCall(true) else requestPermissions(asks, ASK_CALL_MIC)
    }

    @Deprecated("registerBack's OnBackInvokedCallback takes every system back from API 33; this is the road below it")
    override fun onBackPressed() {
        val b = back
        if (b != null) b() else drawer?.open()   // the root never leaves the app (commitBack)
    }

    // ── work off the main thread (the core's key derivation takes a moment) ──
    fun background(work: () -> Unit) { worker.execute(work) }
    fun onMain(work: () -> Unit) { main.post(work) }
    fun onMainAfter(ms: Long, work: () -> Unit) { main.postDelayed(work, ms) }

    // ── the system photo picker ──
    private var photoDone: ((Uri?) -> Unit)? = null
    fun pickPhoto(done: (Uri?) -> Unit) {
        photoDone = done
        val intent = if (Build.VERSION.SDK_INT >= 33) Intent(MediaStore.ACTION_PICK_IMAGES)
                     else Intent(Intent.ACTION_GET_CONTENT).setType("image/*")
        @Suppress("DEPRECATION") startActivityForResult(intent, PICK_PHOTO)
    }

    /** A picture OR a film from the system's own picker (iOS PhotosPicker .any(of: [.images, .videos])). */
    fun pickVisual(done: (Uri?) -> Unit) {
        photoDone = done
        val intent = if (Build.VERSION.SDK_INT >= 33) Intent(MediaStore.ACTION_PICK_IMAGES)
                     else Intent(Intent.ACTION_GET_CONTENT).setType("*/*").putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("image/*", "video/*"))
        @Suppress("DEPRECATION") startActivityForResult(intent, PICK_PHOTO)
    }

    /**
     * THE SYSTEM'S OWN WHOLE LIBRARY (iOS MTSystemPhotos: PHPicker, any of images and videos, its own ten): what was picked, in the
     * order the finger chose it; nothing — an empty list.
     */
    private var manyDone: ((List<Uri>) -> Unit)? = null
    fun pickVisualMany(max: Int, done: (List<Uri>) -> Unit) {
        manyDone = done
        val intent = if (33 <= Build.VERSION.SDK_INT) Intent(MediaStore.ACTION_PICK_IMAGES).putExtra(MediaStore.EXTRA_PICK_IMAGES_MAX, max)
                     else Intent(Intent.ACTION_GET_CONTENT).setType("*/*").putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("image/*", "video/*"))
                         .putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        runCatching { @Suppress("DEPRECATION") startActivityForResult(intent, PICK_MANY) }.onFailure { manyDone = null; done(emptyList()) }
    }

    /** Tracks and files, any number, from the system's document picker (iOS fileImporter [.audio, .item], allowsMultipleSelection). */
    fun openDocuments(done: (List<Uri>) -> Unit) {
        manyDone = done
        runCatching {
            @Suppress("DEPRECATION") startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE)
                .setType("*/*").putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true), PICK_MANY)
        }.onFailure { manyDone = null; done(emptyList()) }
    }

    /** The library's question (iOS PHPhotoLibrary.requestAuthorization): whole, a part the person chose, or no; answered once. */
    private var mediaDone: ((Boolean) -> Unit)? = null
    fun askMedia(done: (Boolean) -> Unit) {
        mediaDone = done
        requestPermissions(Library.perms(), ASK_MEDIA)
    }

    /** The microphone's question for a film of the camera (iOS AVCaptureDevice.requestAccess .audio); answered once. */
    private var micDone: ((Boolean) -> Unit)? = null
    fun askMic(done: (Boolean) -> Unit) {
        micDone = done
        requestPermissions(arrayOf(android.Manifest.permission.RECORD_AUDIO), ASK_MIC)
    }

    /** The camera's question, asked by the system; the answer comes back once (iOS AVCaptureDevice.requestAccess). */
    private var cameraDone: ((Boolean) -> Unit)? = null
    fun askCamera(done: (Boolean) -> Unit) {
        cameraDone = done
        requestPermissions(arrayOf(android.Manifest.permission.CAMERA), ASK_CAMERA)
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == ASK_MIC) { micDone?.invoke(grantResults.firstOrNull() == android.content.pm.PackageManager.PERMISSION_GRANTED); micDone = null }
        if (requestCode == ASK_MEDIA) { mediaDone?.invoke(grantResults.any { it == android.content.pm.PackageManager.PERMISSION_GRANTED }); mediaDone = null }
        if (requestCode == ASK_CAMERA) { cameraDone?.invoke(grantResults.firstOrNull() == android.content.pm.PackageManager.PERMISSION_GRANTED); cameraDone = null }
        if (requestCode == ASK_CALL_OUT) pendingCall?.let { pendingCall = null; if (Calls.dial(it, pendingVideo)) CallScreen.show(this, it) }
        if (requestCode == ASK_CALL_MIC) takeTheCall(true)   // refused, the call is still taken: the person hears, the other side does not
    }

    // ── the system's document picker: a backup handed to a place the person picks, and taken back from a file ──
    private var docDone: ((Uri?) -> Unit)? = null
    fun saveDocument(name: String, done: (Uri?) -> Unit) {
        docDone = done
        @Suppress("DEPRECATION") startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE)
            .setType("application/octet-stream").putExtra(Intent.EXTRA_TITLE, name), DOCUMENT)
    }
    /** A folder lent to the music (iOS fileImporter .folder): the system's tree picker; the grant is taken by MusicFolders. */
    fun pickFolder(done: (Uri?) -> Unit) {
        docDone = done
        @Suppress("DEPRECATION") startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION), DOCUMENT)
    }
    fun openDocument(done: (Uri?) -> Unit) {
        docDone = done
        @Suppress("DEPRECATION") startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE)
            .setType("*/*"), DOCUMENT)
    }

    /** The system camera (Capture.shoot): the shot is in the door's file; the answer is whether it was taken. */
    private var captureDone: ((Boolean) -> Unit)? = null
    fun captureWith(intent: Intent, done: (Boolean) -> Unit) {
        captureDone = done
        runCatching { @Suppress("DEPRECATION") startActivityForResult(intent, CAPTURE) }.onFailure { captureDone = null; done(false) }
    }
    /** The phone's own contacts picker (iOS CNContactPickerViewController): one phone row, read through its granted address. */
    private var contactDone: ((Uri?) -> Unit)? = null
    fun pickContact(done: (Uri?) -> Unit) {
        contactDone = done
        runCatching {
            @Suppress("DEPRECATION") startActivityForResult(Intent(Intent.ACTION_PICK, android.provider.ContactsContract.CommonDataKinds.Phone.CONTENT_URI), PICK_CONTACT)
        }.onFailure { contactDone = null; done(null) }
    }

    /** The phone's own new-contact screen (iOS upsertSystemCard): it closes once the card is saved, and says whether it was. */
    private var cardDone: ((Boolean) -> Unit)? = null
    fun addContact(card: Intent, done: (Boolean) -> Unit) {
        cardDone = done
        runCatching { @Suppress("DEPRECATION") startActivityForResult(card.putExtra("finishActivityOnSaveCompleted", true), ADD_CONTACT) }
            .onFailure { cardDone = null; done(false) }
    }

    /** The system's own question before a screen is shared (iOS: the broadcast picker, «Broadcast»): its answer comes back once. */
    private var screenDone: ((Intent?) -> Unit)? = null
    fun askScreen(done: (Intent?) -> Unit) {
        val mpm = getSystemService(android.media.projection.MediaProjectionManager::class.java) ?: return done(null)
        screenDone = done
        runCatching { @Suppress("DEPRECATION") startActivityForResult(mpm.createScreenCaptureIntent(), ASK_SCREEN) }.onFailure { screenDone = null; done(null) }
    }

    /** The system's code screen on Android 8–9 (OwnerCheck): its answer comes back through onActivityResult. */
    fun confirmOwner(intent: Intent) {
        @Suppress("DEPRECATION") startActivityForResult(intent, CONFIRM_OWNER)
    }

    @Deprecated("the platform's own result road")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION") super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == CAPTURE) {
            captureDone?.invoke(resultCode == RESULT_OK); captureDone = null
        } else if (requestCode == PICK_CONTACT) {
            contactDone?.invoke(if (resultCode == RESULT_OK) data?.data else null); contactDone = null
        } else if (requestCode == ADD_CONTACT) {
            cardDone?.invoke(resultCode == RESULT_OK); cardDone = null
        } else if (requestCode == CONFIRM_OWNER) {
            OwnerCheck.pending?.invoke(if (resultCode == RESULT_OK) OwnerWord.CONFIRMED else OwnerWord.FAILED)
            OwnerCheck.pending = null
        } else if (requestCode == PICK_MANY) {
            val got = ArrayList<Uri>()
            if (resultCode == RESULT_OK) {
                val clip = data?.clipData
                if (clip != null) for (i in 0 until clip.itemCount) got.add(clip.getItemAt(i).uri) else data?.data?.let { got.add(it) }
            }
            manyDone?.invoke(got); manyDone = null
        } else if (requestCode == PICK_PHOTO) {
            photoDone?.invoke(if (resultCode == RESULT_OK) data?.data else null)
            photoDone = null
        } else if (requestCode == DOCUMENT) {
            docDone?.invoke(if (resultCode == RESULT_OK) data?.data else null)
            docDone = null
        } else if (requestCode == ASK_SCREEN) {
            screenDone?.invoke(if (resultCode == RESULT_OK) data else null)
            screenDone = null
        }
    }

    /** The app's own language before Android 13 (from 13 the system keeps it: AppLanguage). */
    override fun attachBaseContext(base: android.content.Context) = super.attachBaseContext(pinnedText(AppLanguage.wrap(base)))

    private companion object { const val PICK_PHOTO = 1; const val ASK_NOTIFY = 2; const val DOCUMENT = 3; const val ASK_CAMERA = 4; const val CONFIRM_OWNER = 5; const val CAPTURE = 6; const val PICK_CONTACT = 7; const val ASK_CALL_MIC = 9; const val ASK_CALL_OUT = 10; const val ASK_SCREEN = 11; const val PICK_MANY = 12; const val ASK_MEDIA = 13; const val ASK_MIC = 14; const val ADD_CONTACT = 15 }
}
