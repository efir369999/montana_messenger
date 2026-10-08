package quest.montana.app

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.projection.MediaProjection
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Build
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import org.webrtc.AudioSource
import org.webrtc.AudioTrack
import org.webrtc.Camera2Enumerator
import org.webrtc.CameraVideoCapturer
import org.webrtc.DataChannel
import org.webrtc.IceCandidate
import org.webrtc.MediaConstraints
import org.webrtc.MediaStream
import org.webrtc.MediaStreamTrack
import org.webrtc.PeerConnection
import org.webrtc.RtpParameters
import org.webrtc.RtpReceiver
import org.webrtc.RtpTransceiver
import org.webrtc.ScreenCapturerAndroid
import org.webrtc.SdpObserver
import org.webrtc.SessionDescription
import org.webrtc.SurfaceTextureHelper
import org.webrtc.VideoFrame
import org.webrtc.VideoSink
import org.webrtc.VideoSource
import org.webrtc.VideoTrack
import java.util.concurrent.Executors

/**
 * THE CALL'S VOICE (iOS MontanaCall, the callee's half: rtcConfig 1028-1111, buildPC 1113-1140, proceedAccept 2653-2698,
 * produceAndSendAnswer 2700-2790, the candidates 4910-4962 and 2368-2379; the map is docs/calls.md). «Answer» builds one
 * connection with the relay pass the doors give, takes the caller's offer, says «call-answer» with its own description tuned
 * as iOS tunes it, and the candidates go both ways on the call's lane. The microphone is one track; the loudspeaker and the
 * mute are the person's. The line closes with its call (Calls.end) and gives back the seconds it spoke, for the call's row.
 * THE PICTURE rides the same line (iOS toggleVideo 3138-3262, the restart road 2391-2483 and 5138-5169): «Video» asks the far
 * side first, its «yes» brings my camera in and the new description is offered as «call-restart»; their offers in the middle of
 * the call are answered the same way, and their first frame drawn makes the call a video call.
 */
object CallLine {
    private const val CONNECT_MS = 60_000L   // iOS armHardTimeout: an answered call that never connects ends in a minute
    private const val PASS = "turnPass"   // iOS rememberTurnPass: {u, c, uris, stun}; the name is the pass's own moment
    // THE ONE OWNER'S OWN CLOCK (iOS restartSettleS/restartCalleeLeadS/restartMax/reconnectDeadlineS/disconnectGraceS, b23f80900c0f)
    private const val RESTART_SETTLE_MS = 9_000L     // a transport over a relay forms in seconds; asking sooner aborts it
    private const val RESTART_CALLEE_LEAD_MS = 1_500L
    private const val RESTART_MAX = 3                 // three fresh transports in a row failed — then the call is honestly lost
    private const val RECONNECT_DEADLINE_MS = 30_000L
    private const val DISCONNECT_GRACE_MS = 2_500L

    private class Line(val ref: String, val seed: String, val pc: PeerConnection, val source: AudioSource, val track: AudioTrack) {
        val out = ArrayList<IceCandidate>()
        var batching = false
        var flushes = 0
        var remoteSet = false
        var answerTaken = false
        var holding = false   // the caller's candidates wait for the far phone's first word (iOS iceHeldForPeerWord)
        var caller = false   // this side offered the call (iOS isInitiator): in a glare of two offers mid-call it keeps its own
        var seenOffer: String? = null   // iOS seenRestartOffer, seenRestartAnswer: the second road's copy is buried
        var seenAnswer: String? = null
        // the one owner of «ask for fresh checks» (iOS requestIceRestart, b23f80900c0f)
        var restartAskedAt = 0L   // iOS restartAskedAt (.distantPast here is 0): never asked until set
        var iceRestarts = 0   // iOS iceRestarts: fresh transports asked since the break was declared
        var routeKey = ""   // iOS routeKey: the wifi/cellular letters of the route in hand
        var routeRestartAt = 0L   // iOS routeRestartAt: one ask per route change, debounced two seconds
        var routeCallback: ConnectivityManager.NetworkCallback? = null   // iOS routeMonitor
        // my picture (iOS birthLocalVideo): the camera, its frames' helper, the source and the track «mt_video»
        var cam: CameraVideoCapturer? = null
        var helper: SurfaceTextureHelper? = null
        var vsource: VideoSource? = null
        var vtrack: VideoTrack? = null
        var remote: VideoTrack? = null   // theirs, as the connection handed it — never a copy read off its list of receivers
        var armedAt = 0L   // iOS videoArmedAt: my «yes» to their camera stands forty seconds
        var speakerDecided = false   // iOS videoSpeakerDecided: the video call's loudspeaker is decided once, the person's choice stands
        var grewByShare = false   // iOS peerShareGrewVideo: their screen made the voice call a video one
        // my screen (iOS MTScreenShare, startScreenShare 3282): its capturer and helper; what the call was before it
        var screen: ScreenCapturerAndroid? = null
        var shelper: SurfaceTextureHelper? = null
        var audioBefore = false   // iOS audioBeforeShare: the video line grew for the share alone
        var cameraWas = false   // iOS cameraWasLive: my camera comes back when the share ends
        @Volatile var connectedAt = 0L
    }

    // the connection's own queue (iOS: the call machine's serial queue) — the order of the words holds, no screen waits on it
    private val work = Executors.newSingleThreadExecutor()
    private val gate = Any()
    private var line: Line? = null
    private val waiting = ArrayList<Pair<String, IceCandidate>>()   // the caller's candidates that came before the line stood
    private var focus: AudioFocusRequest? = null
    @Volatile var muted = false
        private set
    @Volatile var speaker = false
        private set
    @Volatile var held = false   // this side put the call on hold (iOS softHeld)
        private set
    @Volatile var heldByPeer = false   // the far side did (iOS heldByPeer)
        private set
    @Volatile var lost = false   // the link broke and has not healed (iOS «reconnecting»): the call's light is red
        private set

    // ── THE PICTURE'S STATE, read by the call's screen (iOS isVideo; CallUIModel video, videoAskPending, videoAskIncoming,
    // videoAsk, remoteLive, peerSharing, pipSwapped; wantFrontCamera) ──
    @Volatile var video = false
        private set
    @Volatile var asking = false   // I asked for video and wait for the far side's word, thirty seconds at most
        private set
    @Volatile var asked = false   // the far side asks: «… is calling with video» — Accept or Decline
        private set
    @Volatile var offerMine = false   // their picture came while my camera sleeps: «Turn on your video?»
    @Volatile var remoteLive = false   // their frames are drawn: a track is not a picture
        private set
    @Volatile var peerSharing = false   // their screen rides the video line
        private set
    @Volatile var sharing = false   // my screen rides it (iOS screenSharing)
        private set
    @Volatile var swapped = false   // the corner picture was tapped: mine fills the screen, theirs rides the corner
    @Volatile var front = true   // the front camera, shown mirrored
        private set
    @Volatile var changed: (() -> Unit)? = null   // the call's screen, told on the main thread when the picture's state moves
    @Volatile private var askRound = 0
    @Volatile private var sniffed = false

    /** My camera stands in the call. */
    val camera: Boolean get() = synchronized(gate) { line?.vtrack != null }

    /** A picture's way to the screen (iOS VideoView's side): the track draws into it, the screen lends it a surface or none. */
    class Slot : VideoSink {
        @Volatile var into: VideoSink? = null
        override fun onFrame(f: VideoFrame) { into?.onFrame(f) }
    }
    val theirs = Slot()
    val own = Slot()

    // their frames pass here first: the first one drawn makes the call a video call (iOS MTFirstFrameSniffer, remoteVideoArrived)
    private val sniff = object : VideoSink {
        override fun onFrame(f: VideoFrame) {
            if (!remoteLive) { remoteLive = true; moved() }
            if (!sniffed) { sniffed = true; work.execute { arrived() } }
            theirs.onFrame(f)
        }
    }

    private fun moved() = MainThread.post { changed?.invoke() }

    /** The moment the voice joined, for the call's clock; 0 — not yet. */
    val connectedAt: Long get() = synchronized(gate) { line?.connectedAt ?: 0L }

    /** «Answer» with the offer in hand (iOS proceedAccept): the line is built on its own queue, the answer leaves at once. */
    fun answer(ref: String, seed: String, offer: String) = work.execute {
        val l = build(ref, seed) ?: return@execute
        armConnect(l)
        l.pc.setRemoteDescription(sdp(onSet = {
            l.remoteSet = true
            drain(l)
            // THE OFFER SAYS WHETHER IT IS A VIDEO CALL (iOS adoptVideoFromOffer 1147, produceAndSendAnswer 2706): its video line is
            // answered both ways at once and my camera's track goes into it — the answer never waits for the camera's first frame
            if (offer.contains("m=video")) { video = true; camera(l); place(l); moved(); CallService.sync() }
            l.pc.createAnswer(sdp(onMade = { d ->
                val tuned = SessionDescription(d.type, tune(d.description, 40000))
                // an answer without its own accepted description is not an answer (iOS 2729): the call ends, nothing is sent
                l.pc.setLocalDescription(sdp(onSet = { sendAnswer(l, tuned.description, 0); if (l.vtrack != null) bound(l) },
                    onFail = { e -> log("own description refused: " + e); Calls.hangUp("answer-refused-here") }), tuned)
            }, onFail = { e -> log("answer unbuilt: " + e); Calls.hangUp("answer-unbuilt") }), MediaConstraints())
        }, onFail = { e -> log("offer refused: " + e); Calls.hangUp("offer-refused") }), SessionDescription(SessionDescription.Type.OFFER, offer))
    }

    /**
     * THE CALLER'S HALF (iOS startCall 1857-1884): the line, and its offer tuned as iOS tunes its own (64 kbit/s), handed back to
     * be said; the candidates are held until the far phone's first word.
     */
    fun dial(ref: String, seed: String, withVideo: Boolean, offered: (String) -> Unit) = work.execute {
        val l = build(ref, seed) ?: return@execute
        l.holding = true
        l.caller = true
        // THE HOLD HAS A CEILING (iOS startCall 1771-1772, b23f80900c0f): «call-ringing» or «call-answer» usually release it,
        // but a ring word the network drops must not hold the candidates past the far phone's own life — eight seconds, then anyway.
        MainThread.later(8000) { if (synchronized(gate) { line === l }) work.execute { unhold(l, "time") } }
        // a video call carries my camera from the dial (iOS startCall, birthLocalVideo): its line in the offer, the camera in it —
        // and without the camera granted the line still stands, to receive
        if (withVideo) {
            video = true
            if (camera(l)) place(l)
            else l.pc.addTransceiver(MediaStreamTrack.MediaType.MEDIA_TYPE_VIDEO, RtpTransceiver.RtpTransceiverInit(RtpTransceiver.RtpTransceiverDirection.RECV_ONLY))
            moved()
            CallService.sync()
        }
        l.pc.createOffer(sdp(onMade = { d ->
            val tuned = SessionDescription(d.type, tune(d.description, 64000))
            l.pc.setLocalDescription(sdp(onSet = { offered(tuned.description); if (l.vtrack != null) bound(l) },
                onFail = { e -> log("own offer refused: " + e); Calls.hangUp("offer-refused-here") }), tuned)
        }, onFail = { e -> log("offer unbuilt: " + e); Calls.hangUp("offer-unbuilt") }), MediaConstraints())
    }

    /** The far phone's answer (iOS «call-answer» 2039, 2332): taken once; the minute to connect runs from here (armHardTimeout). */
    fun answered(ref: String, epoch: String, answer: String) = work.execute {
        val l = mine(ref, epoch) ?: return@execute
        if (l.answerTaken) return@execute
        l.answerTaken = true
        armConnect(l)
        log("answer in")
        l.pc.setRemoteDescription(sdp(onSet = { l.remoteSet = true; drain(l); unhold(l, "answer"); if (l.vtrack != null) bound(l) },
            onFail = { e -> log("answer refused: " + e); Calls.hangUp("answer-refused") }), SessionDescription(SessionDescription.Type.ANSWER, answer))
    }

    /** The far phone said its first word: the candidates held for it leave in one batch (iOS releaseHeldIce 1772, 2339, 2350). */
    fun release(ref: String, epoch: String) = work.execute { mine(ref, epoch)?.let { unhold(it, "ringing") } }

    private fun unhold(l: Line, why: String) {
        if (!l.holding) return
        l.holding = false
        log("ice hold released by " + why)
        flush(l)
    }

    private fun mine(ref: String, epoch: String) = synchronized(gate) { line?.takeIf { it.ref == ref && Calls.epochOf(it.seed) == epoch } }

    private fun armConnect(l: Line) = MainThread.later(CONNECT_MS) { if (synchronized(gate) { line === l } && l.connectedAt == 0L) Calls.hangUp("connect-timeout") }

    /** One connection for one call (iOS rtcConfig + buildPC), on the line's queue; the phone's sound turns to the call. */
    private fun build(ref: String, seed: String): Line? {
        if (synchronized(gate) { line != null }) return null
        val f = CallEngine.factory ?: return null.also { log("no engine"); Calls.hangUp("engine-missing") }
        val cfg = PeerConnection.RTCConfiguration(servers()).apply {
            sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN
            continualGatheringPolicy = PeerConnection.ContinualGatheringPolicy.GATHER_CONTINUALLY
            bundlePolicy = PeerConnection.BundlePolicy.MAXBUNDLE
            iceTransportsType = PeerConnection.IceTransportsType.ALL   // iOS 15.13: both roads at once, the relay offered first
        }
        var made: Line? = null
        val pc = f.createPeerConnection(cfg, object : PeerConnection.Observer {
            override fun onIceCandidate(c: IceCandidate) { made?.let { gathered(it, c) } }
            override fun onIceConnectionChange(s: PeerConnection.IceConnectionState) { made?.let { state(it, s) } }
            override fun onSignalingChange(s: PeerConnection.SignalingState) {}
            override fun onIceConnectionReceivingChange(b: Boolean) {}
            override fun onIceGatheringChange(s: PeerConnection.IceGatheringState) {}
            override fun onIceCandidatesRemoved(cs: Array<out IceCandidate>) {}
            override fun onAddStream(s: MediaStream) {}
            override fun onRemoveStream(s: MediaStream) {}
            override fun onAddTrack(r: RtpReceiver, s: Array<out MediaStream>) { made?.let { added(it, r) } }
            override fun onDataChannel(d: DataChannel) {}
            override fun onRenegotiationNeeded() {}
        }) ?: return null.also { log("no connection"); Calls.hangUp("connection-unbuilt") }
        // iOS buildPC: one voice track «mt_audio» in the stream «mt_stream», the person's mute applied to it at birth
        val source = f.createAudioSource(MediaConstraints())
        val track = f.createAudioTrack("mt_audio", source)
        track.setEnabled(!muted)
        pc.addTrack(track, listOf("mt_stream"))
        val l = Line(ref, seed, pc, source, track)
        made = l
        synchronized(gate) { line = l }
        audioOn()
        return l
    }

    /** The observer of one step of the descriptions; every callback goes back onto the line's queue. */
    private fun sdp(onSet: () -> Unit = {}, onMade: (SessionDescription) -> Unit = {}, onFail: (String) -> Unit) = object : SdpObserver {
        override fun onCreateSuccess(d: SessionDescription) { work.execute { onMade(d) } }
        override fun onSetSuccess() { work.execute { onSet() } }
        override fun onCreateFailure(e: String?) { work.execute { onFail(e ?: "") } }
        override fun onSetFailure(e: String?) { work.execute { onFail(e ?: "") } }
    }

    // iOS tuneSDP: the voice's settings ride its FEC line — 64 kbit/s on the caller's offer, 40 on an answer to a far side that
    // is not «premium» (SFrame off)
    private fun tune(sdp: String, rate: Int) = sdp.replace("useinbandfec=1", "useinbandfec=1;stereo=0;maxaveragebitrate=" + rate + ";maxplaybackrate=48000;cbr=0")

    // iOS myCaps, as this build is: SFrame off, no answer read off the wake road, no rejoin
    fun caps(): JSONObject = JSONObject().put("tier", "android-native").put("ver", 1).put("opus_max", 40000).put("hw_aec", true)
        .put("sframe", false).put("av", false).put("rejoin", false)

    private fun word(l: Line, ctrl: String) =
        JSONObject().put("t", "cal").put("ctrl", ctrl).put("ts", System.currentTimeMillis()).put("e", Calls.epochOf(l.seed))

    private fun say(l: Line, words: JSONArray) = Signal.postWord(l.ref, Calls.epochOf(l.seed), words.toString().toByteArray())

    /** The answer travels an unreliable road: said again every two seconds until the voice joins (iOS answerResendTimer). */
    private fun sendAnswer(l: Line, sdp: String, n: Int) {
        if (synchronized(gate) { line !== l } || l.connectedAt != 0L) return
        say(l, JSONArray().put(word(l, "call-answer").put("sdp", JSONObject().put("type", "answer").put("sdp", sdp)).put("caps", caps())))
        if (n == 0) log("answer sent")
        if (n < 15) MainThread.later(2000) { work.execute { sendAnswer(l, sdp, n + 1) } }
    }

    // ── the candidates ──

    /** Our candidates: the first bundle leaves at once, the rest in batches of 200 ms (iOS 4916-4936), one word each (E2E 1090). */
    private fun gathered(l: Line, c: IceCandidate) = work.execute {
        if (synchronized(gate) { line !== l }) return@execute
        l.out.add(c)
        if (l.batching || l.holding) return@execute
        l.batching = true
        MainThread.later(if (l.flushes == 0) 0L else 200L) { work.execute { flush(l) } }
    }

    private fun flush(l: Line) {
        l.batching = false
        if (l.out.isEmpty() || synchronized(gate) { line !== l }) { l.out.clear(); return }
        val words = JSONArray()
        for (c in l.out) words.put(word(l, "call-ice").put("candidate",
            JSONObject().put("candidate", c.sdp).put("sdpMid", c.sdpMid).put("sdpMLineIndex", c.sdpMLineIndex)))
        l.out.clear()
        l.flushes++
        say(l, words)
    }

    /** The caller's candidates (iOS «call-ice» 2368): into the line once it holds the offer, kept until then. */
    fun remoteIce(ref: String, epoch: String, cs: List<IceCandidate>) = work.execute {
        val l = mine(ref, epoch)
        if (l != null && l.remoteSet) { cs.forEach { l.pc.addIceCandidate(it) }; return@execute }
        synchronized(gate) {
            cs.forEach { waiting.add(epoch to it) }
            while (waiting.size > 64) waiting.removeAt(0)
        }
    }

    private fun drain(l: Line) {
        val e = Calls.epochOf(l.seed)
        val kept = synchronized(gate) { waiting.filter { it.first == e }.also { waiting.clear() } }
        kept.forEach { l.pc.addIceCandidate(it.second) }
        if (kept.isNotEmpty()) log("candidates kept: " + kept.size)
    }

    private fun state(l: Line, s: PeerConnection.IceConnectionState) = work.execute {
        if (synchronized(gate) { line !== l }) return@execute
        log("ice " + s)
        when (s) {
            PeerConnection.IceConnectionState.CONNECTED, PeerConnection.IceConnectionState.COMPLETED -> {
                lost = false
                l.iceRestarts = 0
                l.restartAskedAt = 0L
                startRouteWatch(l)
                if (l.connectedAt == 0L) {
                    l.connectedAt = System.currentTimeMillis()
                    CallService.sync()
                    autoSpeaker(l)
                }
            }
            PeerConnection.IceConnectionState.FAILED -> { lost = true; Calls.hangUp("ice-failed") }
            // THE SUSPICION GETS A GRACE (iOS peerConnection(_:didChange:) 5092-5102, b23f80900c0f): «disconnected» is a few
            // missed checks, not a verdict — measured 22:51:34, it healed in 1.4s and the person heard the break cue for a blip.
            // The red light waits for it to still stand 2.5s later; a quick heal shows nothing. Past the grace the one
            // owner is asked for fresh checks at once, then every three seconds while the break holds (iOS
            // scheduleIceRestart 5147-5165): the thirty-second deadline is the verdict if none of them form.
            PeerConnection.IceConnectionState.DISCONNECTED -> MainThread.later(DISCONNECT_GRACE_MS) {
                if (synchronized(gate) { line === l }) work.execute {
                    if (l.pc.iceConnectionState() != PeerConnection.IceConnectionState.DISCONNECTED) return@execute log("disconnected healed within the grace — no break declared")
                    lost = true
                    scheduleIceRestart(l)
                    MainThread.later(RECONNECT_DEADLINE_MS) {
                        if (synchronized(gate) { line === l } && lost) work.execute {
                            log("reconnecting past the deadline — " + l.iceRestarts + " fresh transports asked, none formed — ending")
                            Calls.hangUp("ice-lost")
                        }
                    }
                }
            }
            else -> {}
        }
    }

    /** The call ended (Calls.end): the line closes, the phone's sound is given back, and the seconds it spoke are returned. */
    fun stop(seed: String): Int {
        val l = synchronized(gate) {
            waiting.clear()
            line?.takeIf { it.seed == seed }?.also { line = null }
        } ?: return 0
        work.execute {
            stopRouteWatch(l)
            runCatching { l.pc.dispose() }
            runCatching { l.screen?.stopCapture() }
            runCatching { l.screen?.dispose() }
            runCatching { l.shelper?.dispose() }
            cameraOff(l)
            runCatching { l.remote?.dispose() }
            runCatching { l.source.dispose() }
        }
        audioOff()
        lost = false
        held = false
        heldByPeer = false
        video = false; asking = false; asked = false; offerMine = false; remoteLive = false; peerSharing = false; swapped = false
        front = true; sniffed = false; askRound++; sharing = false
        theirs.into = null; own.into = null
        moved()
        val at = l.connectedAt
        return if (at == 0L) 0 else ((System.currentTimeMillis() - at) / 1000).toInt()
    }

    // ── the relay pass (iOS rtcConfig 1045-1109, WakePush fetchTurnCred 1467) ──

    private fun servers(): List<PeerConnection.IceServer> {
        val p = pass() ?: return emptyList<PeerConnection.IceServer>().also { log("NO ICE SERVERS — host-only call") }
        val list = ArrayList<PeerConnection.IceServer>()
        val stun = strings(p.optJSONArray("stun"))
        if (stun.isNotEmpty()) list.add(PeerConnection.IceServer.builder(stun).createIceServer())
        // iOS turnRank: the TLS door on 443 first — it survives dead UDP and DPI — then the other TLS, tcp, udp
        val uris = strings(p.optJSONArray("uris")).sortedBy { u ->
            if (u.startsWith("turns:")) (if (u.contains(":443")) 0 else 1) else if (u.contains("transport=tcp")) 2 else 3
        }
        if (uris.isNotEmpty()) list.add(PeerConnection.IceServer.builder(uris).setUsername(p.optString("u")).setPassword(p.optString("c")).createIceServer())
        log("servers stun=" + stun.size + " relay=" + uris.size)
        return list
    }

    private fun strings(a: JSONArray?) = (0 until (a?.length() ?: 0)).mapNotNull { a?.optString(it)?.ifEmpty { null } }

    /** iOS turnPassLive: a pass whose name is its moment lives while ten minutes of it remain. */
    private fun live(p: JSONObject) = p.optString("u").toDoubleOrNull()?.let { it - System.currentTimeMillis() / 1000.0 > 600 } ?: true

    /** The remembered pass, else a fresh one from every door at once — the first answer wins (iOS fetchTurnCred). */
    private fun pass(): JSONObject? {
        runCatching { JSONObject(Prefs.str(PASS, "")) }.getOrNull()?.takeIf { it.optJSONArray("uris") != null && live(it) }?.let { return it }
        val got = java.util.concurrent.LinkedBlockingQueue<JSONObject>()
        for (door in MontanaCard.doors) Thread {
            val (code, text) = Wire.post(door, "/turn-cred", JSONObject(), 6000)
            val o = if (code == 200 && text != null) runCatching { JSONObject(text) }.getOrNull() else null
            val uris = o?.optJSONArray("uris")
            if (o != null && uris != null && uris.length() > 0 && o.optString("username").isNotEmpty())
                got.offer(JSONObject().put("u", o.optString("username")).put("c", o.optString("credential")).put("uris", uris)
                    .put("stun", o.optJSONArray("stun") ?: JSONArray()))
        }.start()
        val p = got.poll(4, java.util.concurrent.TimeUnit.SECONDS) ?: return null   // iOS: four seconds at most on a cold start
        Prefs.setStr(PASS, p.toString())
        return p
    }

    // ── the phone's sound (iOS configureAudioSession, setSpeaker 974, toggleMute 3131) ──

    private fun am() = Book.ctx.getSystemService(AudioManager::class.java)

    private fun audioOn() {
        val am = am() ?: return
        val attrs = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build()
        focus = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT).setAudioAttributes(attrs).build().also { am.requestAudioFocus(it) }
        am.mode = AudioManager.MODE_IN_COMMUNICATION
        // EVERY ROUTE CHANGE DURING A CALL IS NAMED (iOS 15.28, 1369): where the sound went; the platform tells no reason
        if (Build.VERSION.SDK_INT >= 31) runCatching { am.addOnCommunicationDeviceChangedListener(java.util.concurrent.Executor { it.run() }, routeWatch) }
        route(speaker)
    }
    private val routeWatch = AudioManager.OnCommunicationDeviceChangedListener { d -> log("audio_route_change now=" + way(d?.type)) }
    private fun way(t: Int?): String = when (t) {
        null -> "none"
        android.media.AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "earpiece"
        android.media.AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "speaker"
        android.media.AudioDeviceInfo.TYPE_WIRED_HEADSET, android.media.AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "wired"
        android.media.AudioDeviceInfo.TYPE_BLUETOOTH_SCO, android.media.AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "bluetooth"
        android.media.AudioDeviceInfo.TYPE_BLE_HEADSET, android.media.AudioDeviceInfo.TYPE_BLE_SPEAKER -> "ble"
        android.media.AudioDeviceInfo.TYPE_USB_HEADSET, android.media.AudioDeviceInfo.TYPE_USB_DEVICE -> "usb"
        android.media.AudioDeviceInfo.TYPE_HEARING_AID -> "hearing-aid"
        else -> "type-" + t
    }

    private fun audioOff() {
        val am = am() ?: return
        if (Build.VERSION.SDK_INT >= 31) runCatching { am.removeOnCommunicationDeviceChangedListener(routeWatch) }
        route(false)
        am.mode = AudioManager.MODE_NORMAL
        focus?.let { am.abandonAudioFocusRequest(it) }
        focus = null
        speaker = false
        muted = false
    }

    /** The loudspeaker, or whatever the system holds for a call (the earpiece, the headset): its own communication device. */
    fun setSpeaker(on: Boolean) { speaker = on; synchronized(gate) { line }?.speakerDecided = true; route(on) }

    @Suppress("DEPRECATION")
    private fun route(on: Boolean) {
        val am = am() ?: return
        if (Build.VERSION.SDK_INT >= 31) {
            val loud = am.availableCommunicationDevices.firstOrNull { it.type == android.media.AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
            if (on && loud != null) am.setCommunicationDevice(loud) else am.clearCommunicationDevice()
            log("audio_route speaker=" + (if (on) 1 else 0) + " landed=" + way(am.communicationDevice?.type))   // the switch names where it landed (1369)
        } else am.isSpeakerphoneOn = on
    }

    // ── where the sound goes (iOS MontanaAudioRoute 7214-7285) ──

    data class Face(val caption: Int, val icon: Int, val lit: Boolean, val menu: Boolean)
    class Way(val name: String, val chosen: Boolean, val take: () -> Unit)

    // the devices outside the phone that carry a call (iOS externalPorts: headphones, Bluetooth, a car, USB)
    private val OUTSIDE = setOf(AudioDeviceInfo.TYPE_WIRED_HEADSET, AudioDeviceInfo.TYPE_WIRED_HEADPHONES, AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP, AudioDeviceInfo.TYPE_USB_HEADSET, AudioDeviceInfo.TYPE_USB_DEVICE, AudioDeviceInfo.TYPE_HEARING_AID,
        AudioDeviceInfo.TYPE_BLE_HEADSET, AudioDeviceInfo.TYPE_BLE_SPEAKER)

    /**
     * THE AUDIO BUTTON'S FACE (iOS MontanaAudioRoute.face 7261): the phone alone — «Speaker», lit on the loudspeaker; a device
     * outside the phone in reach — «Audio» with the glyph of where the sound is, lit unless it stands at the ear, and a menu.
     */
    fun face(): Face {
        val am = am()
        if (am == null || Build.VERSION.SDK_INT < 31) return Face(R.string.call_speaker, R.drawable.ic_speaker_wave3, speaker, false)
        val now = am.communicationDevice
        val onSpeaker = now?.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER
        if (am.availableCommunicationDevices.none { it.type in OUTSIDE }) return Face(R.string.call_speaker, R.drawable.ic_speaker_wave3, onSpeaker, false)
        val ext = now?.takeIf { it.type in OUTSIDE }
        val icon = if (ext != null) R.drawable.ic_route_headphones else if (onSpeaker) R.drawable.ic_speaker_wave3 else R.drawable.ic_route_phone
        return Face(R.string.call_audio, icon, ext != null || onSpeaker, true)
    }

    /** The menu's ways, as the system's own output menu names them: the phone, the loudspeaker, each device by its name. */
    fun ways(c: Context): List<Way> {
        val am = am() ?: return emptyList()
        if (Build.VERSION.SDK_INT < 31) return emptyList()
        val now = am.communicationDevice
        val out = ArrayList<Way>()
        for (d in am.availableCommunicationDevices) {
            val name = when (d.type) {
                AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> c.getString(R.string.call_route_phone)
                AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> c.getString(R.string.call_speaker)
                in OUTSIDE -> d.productName?.toString()?.ifBlank { null } ?: c.getString(R.string.call_audio)
                else -> continue
            }
            out.add(Way(name, now?.id == d.id) {
                speaker = d.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER
                synchronized(gate) { line }?.speakerDecided = true
                am.setCommunicationDevice(d)
            })
        }
        return out
    }

    /** The microphone goes quiet on its one track; the connection stays. */
    fun setMuted(on: Boolean) {
        muted = on
        val l = synchronized(gate) { line } ?: return
        work.execute { runCatching { l.track.setEnabled(!on && !held) } }
    }

    /**
     * HOLD (iOS softHold 429-455): my microphone and the far voice go quiet, the connection stays, the far side is told
     * «call-hold»; the resume gives both back — the microphone as the mute leaves it — and says «call-resume».
     */
    fun setHeld(on: Boolean) {
        val l = synchronized(gate) { line } ?: return
        held = on
        work.execute {
            runCatching { l.track.setEnabled(!on && !muted) }
            runCatching { l.pc.receivers.forEach { it.track()?.setEnabled(!on) } }
            say(l, JSONArray().put(word(l, if (on) "call-hold" else "call-resume")))
        }
    }

    /** The far side's hold and resume (iOS 2544-2551): the screen says «On hold». */
    fun peerHeld(ref: String, epoch: String, on: Boolean) { if (mine(ref, epoch) != null) heldByPeer = on }

    // ── THE PICTURE (iOS MontanaCall: toggleVideo 3138, dropVideoMode 3162, upgradeToVideo 3190, acceptVideoAsk 3209,
    // enableMyVideo 3227, switchCamera 3251, birthLocalVideo 1158, ensureLocalVideoTrack 1176, remoteVideoArrived 5191) ──

    /**
     * «VIDEO» (iOS toggleVideo 3138): a voice call asks the far side first — the camera waits for its «yes», thirty seconds at
     * most; a video call leaves the video, and both sides go back to the voice.
     */
    fun toggleVideo() {
        val l = synchronized(gate) { line } ?: return
        if (sharing) return stopShare()   // «Video» ends the share; the camera comes back as it was (iOS 3139)
        if (video) { work.execute { drop(l, aloud = true) }; return }
        if (asking) return
        asking = true
        val round = ++askRound
        moved()
        work.execute { say(l, JSONArray().put(word(l, "call-video-ask"))) }
        log("video: consent asked")
        MainThread.later(30_000) { if (askRound == round && asking) { asking = false; moved(); log("video: consent timeout") } }
    }

    /** «Accept» on their ask (iOS acceptVideoAsk 3209): «call-video-ok»; my camera joins when their picture's offer comes, forty seconds. */
    fun acceptAsk() {
        val l = synchronized(gate) { line } ?: return
        asked = false
        l.armedAt = System.currentTimeMillis()
        moved()
        work.execute { say(l, JSONArray().put(word(l, "call-video-ok"))) }
        log("video: consent accepted")
    }

    /** «Decline» on their ask (iOS declineVideoAsk 3218). */
    fun declineAsk() {
        val l = synchronized(gate) { line } ?: return
        asked = false
        moved()
        work.execute { say(l, JSONArray().put(word(l, "call-video-no"))) }
        log("video: consent refused")
    }

    /** «Turn On» (iOS enableMyVideo 3227): my camera joins the call that already shows their picture. */
    fun turnOn() = work.execute { synchronized(gate) { line }?.let { enableMine(it) } }

    /** The camera flip (iOS switchCamera 3251): the person's choice is the other camera, found by its name; the front one is mirrored. */
    fun switchCamera() {
        val l = synchronized(gate) { line } ?: return
        val cam = l.cam ?: return
        val next = !front
        val en = Camera2Enumerator(Book.ctx)
        val name = en.deviceNames.firstOrNull { en.isFrontFacing(it) == next } ?: return
        front = next
        cam.switchCamera(null, name)
        moved()
        log("camera: to " + (if (next) "front" else "back"))
    }

    /** The far side's words about the picture and the descriptions (iOS handleSignalBody 2391-2543). */
    fun heard(ref: String, epoch: String, ctrl: String, w: JSONObject) = work.execute {
        val l = mine(ref, epoch) ?: run {
            // THE FAR PHONE'S FRESH CHECKS FOR A CALL WE LOST ARE ANSWERED, NOT LEFT SILENT (iOS answerGone, MontanaWakePush.swift,
            // 24.09, build 4543d66a9265): without this word the far phone stood «reconnecting» to its own thirty-second deadline
            // over a call nobody here held any more. Only a restart ask is answered — a candidate may precede a birth and must
            // stay buried; Calls.answerGone itself answers only an epoch this phone's own graveyard says it once held and lost.
            if (ctrl == "call-restart" || ctrl == "call-restart-answer") Calls.answerGone(ref, epoch)
            return@execute
        }
        when (ctrl) {
            "call-video-ask" -> { asked = true; log("video: consent asked by peer") }
            "call-video-ok" -> { askRound++; log("video: consent granted"); if (asking) { asking = false; upgrade(l) } }
            "call-video-no" -> { askRound++; asking = false; log("video: consent declined") }
            "call-video-end" -> drop(l, aloud = false)
            "call-restart" -> restart(l, w)
            "call-restart-answer" -> restartAnswer(l, w)
            // their screen (iOS 2509-2543): it grows a voice call into a video one while it rides; its end says what the call was.
            // Each word comes by every door and both roads — the first copy is the word, the rest are buried: a second «on»
            // would read the call it grew as a video call already and lose the way back to the voice
            "call-screen-on" -> if (!peerSharing) {
                l.grewByShare = !video
                if (l.remote != null) video = true
                peerSharing = true
                log("screen: peer sharing on grew=" + l.grewByShare)
            }
            "call-screen-off" -> if (peerSharing) {
                val back = if (w.has("video")) !w.optBoolean("video") else l.grewByShare
                if (back) { l.grewByShare = false; video = false; remoteLive = false; offerMine = false }
                peerSharing = false
                log("screen: peer sharing off audio=" + back)
            }
        }
        moved()
    }

    /** My camera's birth (iOS birthLocalVideo 1158): the source, the camera and the track on the factory alone, 720p at thirty frames. */
    private fun camera(l: Line): Boolean {
        if (l.vtrack != null) return true
        if (Book.ctx.checkSelfPermission(android.Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED)
            return false.also { log("camera: not granted — the call goes on with sound") }
        val f = CallEngine.factory ?: return false
        val egl = CallEngine.egl ?: return false
        return runCatching {
            val en = Camera2Enumerator(Book.ctx)
            // THE BACK CAMERA IS NEVER THE MACHINE'S CHOICE (iOS MontanaCall 1340-1343, the author's word 22.09: an iPhone showed its
            // room to the caller): the side the person chose, or no picture at all — the other camera is the flip mark's tap alone
            val name = en.deviceNames.firstOrNull { en.isFrontFacing(it) == front } ?: return false.also { log("camera: none on the chosen side — the call goes on with sound") }
            val cam = en.createCapturer(name, null) ?: return false
            val src = f.createVideoSource(false)
            val helper = SurfaceTextureHelper.create("mt_camera", egl.eglBaseContext)
            cam.initialize(helper, Book.ctx, src.capturerObserver)
            cam.startCapture(1280, 720, 30)
            val track = f.createVideoTrack("mt_video", src)
            track.addSink(own)
            l.cam = cam; l.helper = helper; l.vsource = src; l.vtrack = track
            log("camera up front=" + front)
            true
        }.getOrElse { log("camera: " + it.message); false }
    }

    private fun cameraOff(l: Line) {
        val cam = l.cam; val helper = l.helper; val src = l.vsource; val track = l.vtrack
        l.cam = null; l.helper = null; l.vsource = null; l.vtrack = null
        runCatching { cam?.stopCapture() }
        runCatching { cam?.dispose() }
        runCatching { helper?.dispose() }
        runCatching { track?.removeSink(own); track?.dispose() }
        runCatching { src?.dispose() }
    }

    /** My picture into the connection (iOS ensureLocalVideoTrack 1176): into the video line that stands, opened both ways, else a line of its own. */
    private fun place(l: Line) {
        val track = l.vtrack
        val tr = l.pc.transceivers.firstOrNull { it.mediaType == MediaStreamTrack.MediaType.MEDIA_TYPE_VIDEO }
        if (tr != null) {
            if (track != null && tr.sender.track()?.id() != track.id()) tr.sender.setTrack(track, false)
            tr.setDirection(RtpTransceiver.RtpTransceiverDirection.SEND_RECV)
        } else if (track != null) l.pc.addTrack(track, listOf("mt_stream"))
    }

    /** The ceiling of my picture (iOS setVideoCeiling 3788 on the ladder's modest step): 700 kbit/s and no less than 300, motion kept before sharpness. */
    private fun bound(l: Line) {
        runCatching {
            val s = l.pc.transceivers.firstOrNull { it.mediaType == MediaStreamTrack.MediaType.MEDIA_TYPE_VIDEO }?.sender ?: return
            val p = s.parameters
            p.encodings.firstOrNull()?.let { it.maxBitrateBps = 700_000; it.minBitrateBps = 300_000 }
            // a shared screen keeps its letters sharp and gives up motion; a camera the reverse (iOS 3790-3808)
            p.degradationPreference = if (sharing) RtpParameters.DegradationPreference.MAINTAIN_RESOLUTION else RtpParameters.DegradationPreference.MAINTAIN_FRAMERATE
            s.setParameters(p)
        }.onFailure { log("ceiling: " + it.message) }
    }

    /** Their «yes» (iOS upgradeToVideo 3190): my camera into the connection, the new picture offered, the loudspeaker taken. */
    private fun upgrade(l: Line) {
        if (video) return
        video = true
        camera(l)
        place(l)
        reoffer(l)
        autoSpeaker(l)
        moved()
        CallService.sync()
        log("video: upgrade offered")
    }

    /** My camera joins their picture (iOS enableMyVideo 3227): only in a call that stands; a camera already there is lit again. */
    private fun enableMine(l: Line) {
        offerMine = false
        if (synchronized(gate) { line !== l } || l.connectedAt == 0L) return moved()
        val track = l.vtrack
        if (track != null) { track.setEnabled(true); return moved() }
        video = true
        if (camera(l)) { place(l); reoffer(l) }
        moved()
        CallService.sync()
        log("video: joined by invitation")
    }

    /** Back to the voice (iOS dropVideoMode 3162): my camera stops, its line stays and carries nothing; by my press or their word. */
    private fun drop(l: Line, aloud: Boolean) {
        if (!video || sharing) return
        if (aloud) say(l, JSONArray().put(word(l, "call-video-end")))
        runCatching { l.pc.transceivers.firstOrNull { it.mediaType == MediaStreamTrack.MediaType.MEDIA_TYPE_VIDEO }?.sender?.setTrack(null, false) }
        cameraOff(l)
        video = false; remoteLive = false; offerMine = false; swapped = false
        moved()
        CallService.sync()
        log("video: ended aloud=" + aloud)
    }

    /** Their first frame drawn (iOS remoteVideoArrived 5191): the call grows video; my fresh «yes» brings my camera, else it is offered. */
    private fun arrived() {
        val l = synchronized(gate) { line } ?: return
        if (video) return moved()
        video = true
        val armed = fresh(l)
        l.armedAt = 0L
        autoSpeaker(l)
        if (armed) enableMine(l) else if (l.vtrack == null && !peerSharing) offerMine = true
        moved()
        CallService.sync()
        log("video: their picture arrived armed=" + armed)
    }

    /** Their track, as the connection hands it (iOS didAdd 5170): its frames pass the first-frame watch on the way to the screen. */
    private fun added(l: Line, r: RtpReceiver) = work.execute {
        val v = r.track() as? VideoTrack ?: return@execute
        if (synchronized(gate) { line !== l } || l.remote?.id() == v.id()) return@execute
        l.remote?.let { old -> runCatching { old.dispose() } }
        l.remote = v
        sniffed = false
        v.addSink(sniff)
        log("video: their track came")
    }

    // ── MY SCREEN (iOS startScreenShare 3282-3326, stopScreenShare 3328-3382, sharePixelBudget 3387) ──

    /**
     * «BROADCAST», AFTER THE SYSTEM'S OWN YES: the screen rides the call's video line. The platform asks the projection's
     * foreground before the projection itself, so the call's service stands in it first; the capture follows on the line's queue.
     */
    fun startShare(data: Intent) {
        val l = synchronized(gate) { line } ?: return
        if (l.connectedAt == 0L || sharing) return log("screen: share refused")
        sharing = true
        moved()
        CallService.publishNow()
        work.execute { share(l, data) }
    }

    /** The share's end — by the stop on the call's screen, by «Video», or by the system's own stop of the projection. */
    fun stopShare() = work.execute { synchronized(gate) { line }?.let { unshare(it, "stop") } }

    /**
     * The screen into the line (iOS startScreenShare 3282): the camera rests and its line stays — the screen feeds its track; a
     * voice call grows the line as «Video» does, without a camera, and offers it. «call-screen-on» tells the far side.
     */
    private fun share(l: Line, data: Intent) {
        if (synchronized(gate) { line !== l }) return
        val f = CallEngine.factory ?: return failShare(l, "no engine")
        val egl = CallEngine.egl ?: return failShare(l, "no engine")
        l.audioBefore = !video
        l.cameraWas = l.cam != null
        l.cam?.let { cam -> runCatching { cam.stopCapture() }; runCatching { cam.dispose() } }
        l.cam = null
        val grew = l.vtrack == null
        if (grew) {
            val src = f.createVideoSource(true)
            l.vsource = src
            l.vtrack = f.createVideoTrack("mt_video", src)
            video = true
        }
        l.vtrack?.setEnabled(true)
        val src = l.vsource ?: return failShare(l, "no source")
        val (w, h) = shape()
        val helper = SurfaceTextureHelper.create("mt_screen", egl.eglBaseContext) ?: return failShare(l, "no helper")
        val cap = ScreenCapturerAndroid(data, object : MediaProjection.Callback() { override fun onStop() { stopShare() } })
        val up = runCatching { cap.initialize(helper, Book.ctx, src.capturerObserver); cap.startCapture(w, h, 15) }
        if (up.isFailure) {
            runCatching { cap.dispose() }; runCatching { helper.dispose() }
            return failShare(l, "capture: " + up.exceptionOrNull()?.message)
        }
        l.screen = cap; l.shelper = helper
        if (grew) { place(l); reoffer(l) }
        bound(l)
        say(l, JSONArray().put(word(l, "call-screen-on")))
        moved()
        CallService.sync()
        log("screen: share started " + w + "x" + h + " camera_was=" + l.cameraWas + " grew=" + grew)
    }

    private fun failShare(l: Line, why: String) {
        sharing = false
        if (l.cameraWas) startCam(l)
        moved()
        CallService.sync()
        log("screen: share failed " + why)
    }

    /**
     * The share ends (iOS stopScreenShare 3328): the far side is told what the call was before it; my camera comes back into the
     * same track through a fresh capturer, or a call that grew for the share falls back to the voice whole.
     */
    private fun unshare(l: Line, why: String) {
        if (!sharing) return
        sharing = false
        val cap = l.screen; val helper = l.shelper
        l.screen = null; l.shelper = null
        runCatching { cap?.stopCapture() }
        runCatching { cap?.dispose() }
        runCatching { helper?.dispose() }
        say(l, JSONArray().put(word(l, "call-screen-off").put("video", !l.audioBefore)))
        when {
            l.cameraWas -> startCam(l)
            l.audioBefore -> {
                runCatching { l.pc.transceivers.firstOrNull { it.mediaType == MediaStreamTrack.MediaType.MEDIA_TYPE_VIDEO }?.sender?.setTrack(null, false) }
                cameraOff(l)
                video = false
            }
            else -> l.vtrack?.setEnabled(false)   // a video call whose camera slept before the share: my picture stays dark
        }
        bound(l)
        l.cameraWas = false; l.audioBefore = false
        moved()
        CallService.sync()
        log("screen: share stopped why=" + why)
    }

    /** My camera into the track that stands (iOS stopScreenShare 3345): a fresh capturer feeds the same source. */
    private fun startCam(l: Line) {
        val src = l.vsource ?: return
        val egl = CallEngine.egl ?: return
        runCatching {
            val en = Camera2Enumerator(Book.ctx)
            val name = en.deviceNames.firstOrNull { en.isFrontFacing(it) == front } ?: return   // the chosen side or none (iOS 1340)
            val cam = en.createCapturer(name, null) ?: return
            runCatching { l.helper?.dispose() }
            val helper = SurfaceTextureHelper.create("mt_camera", egl.eglBaseContext)
            l.helper = helper
            cam.initialize(helper, Book.ctx, src.capturerObserver)
            cam.startCapture(1280, 720, 30)
            l.cam = cam
            log("camera back front=" + front)
        }.onFailure { log("camera back: " + it.message) }
    }

    /** The share's shape (iOS sharePixelBudget 3387): the screen's own, scaled down to the phone portrait's area, 720 by 1560, never cut. */
    private fun shape(): Pair<Int, Int> {
        val m = android.util.DisplayMetrics()
        @Suppress("DEPRECATION") Book.ctx.getSystemService(android.view.WindowManager::class.java).defaultDisplay.getRealMetrics(m)
        val w = m.widthPixels.toDouble()
        val h = m.heightPixels.toDouble()
        val s = minOf(1.0, Math.sqrt(720.0 * 1560.0 / (w * h)))
        return ((w * s).toInt() / 2 * 2) to ((h * s).toInt() / 2 * 2)
    }

    /**
     * MY OFFER IN THE MIDDLE OF THE CALL (iOS sendRenegotiationOffer 5138): the new picture rides «call-restart», «rsn» media; it
     * waits for a quiet connection — offered into an open negotiation it is refused — and tries again in six tenths of a second.
     */
    private fun reoffer(l: Line) {
        if (synchronized(gate) { line !== l }) return
        if (l.pc.signalingState() != PeerConnection.SignalingState.STABLE) {
            log("media offer deferred — signaling busy")
            MainThread.later(600) { work.execute { reoffer(l) } }
            return
        }
        log("renegotiation offer (video)")
        l.pc.createOffer(sdp(onMade = { d ->
            val tuned = SessionDescription(d.type, tune(d.description, 40000))
            l.pc.setLocalDescription(sdp(onSet = {
                say(l, JSONArray().put(word(l, "call-restart").put("sdp", JSONObject().put("type", "offer").put("sdp", tuned.description))
                    .put("caps", caps()).put("rsn", "media")))
                if (l.vtrack != null) bound(l)
            }, onFail = { e -> log("restart offer refused here: " + e) }), tuned)
        }, onFail = { e -> log("restart offer unbuilt: " + e) }), MediaConstraints())
    }

    // ── FRESH CHECKS, ONE OWNER (iOS requestIceRestart 5166-5182, startRouteWatch 5112-5143, scheduleIceRestart
    // 5147-5165, b23f80900c0f) ──

    /** The system names a route change (Wi-Fi<->cellular, after the connect): the side whose route changed asks for
     * fresh checks at once, debounced two seconds against flaps; the dial's own dirty-route road is the setup half,
     * untouched here. */
    private fun startRouteWatch(l: Line) {
        if (l.routeCallback != null) return
        val cm = Book.ctx.getSystemService(ConnectivityManager::class.java) ?: return
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onCapabilitiesChanged(n: Network, caps: NetworkCapabilities) {
                if (!caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) return
                val key = (if (caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) "w" else "") +
                    (if (caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) "c" else "")
                work.execute { routeChanged(l, key) }
            }
        }
        runCatching { cm.registerDefaultNetworkCallback(cb) }.onFailure { return }
        l.routeCallback = cb
    }

    private fun stopRouteWatch(l: Line) {
        val cb = l.routeCallback ?: return
        l.routeCallback = null
        runCatching { Book.ctx.getSystemService(ConnectivityManager::class.java)?.unregisterNetworkCallback(cb) }
    }

    private fun routeChanged(l: Line, key: String) {
        if (synchronized(gate) { line !== l } || l.connectedAt == 0L) return
        val old = l.routeKey
        l.routeKey = key
        if (old.isEmpty() || old == key) return
        val now = System.currentTimeMillis()
        if (now - l.routeRestartAt <= 2_000) return
        l.routeRestartAt = now
        log("route changed " + old + "->" + key + " — ice restart asked")
        requestIceRestart(l, "route " + old + "->" + key)
    }

    /** THE ONE OWNER OF «ASK FOR FRESH CHECKS» (iOS requestIceRestart 5168-5182): the route watch above and the
     * reconnect clock below only knock here — never over an ask still forming (nine seconds), unless the machine
     * already says failed; the caller asks at once, the callee after a lead so the caller's own ask lands first. */
    private fun requestIceRestart(l: Line, reason: String) {
        val forming = System.currentTimeMillis() - l.restartAskedAt
        if (forming < RESTART_SETTLE_MS && l.pc.iceConnectionState() != PeerConnection.IceConnectionState.FAILED)
            return log("restart held — one forming " + (forming / 1000) + "s (" + reason + ")")
        l.restartAskedAt = System.currentTimeMillis()
        val lead = if (l.caller) 0L else RESTART_CALLEE_LEAD_MS
        MainThread.later(lead) {
            work.execute {
                if (synchronized(gate) { line !== l }) return@execute
                if (lost) l.iceRestarts++
                log("restart asked (" + reason + ")" + (if (lead > 0) " after the caller's lead" else ""))
                sendIceRestartOffer(l)
            }
        }
    }

    /** THE RECONNECT CLOCK ONLY KNOCKS (iOS scheduleIceRestart 5147-5165): it asks once at once, then every three
     * seconds while the break holds, up to three fresh transports — requestIceRestart above decides which knock
     * actually leaves. */
    private fun scheduleIceRestart(l: Line) {
        requestIceRestart(l, "reconnecting")
        knock(l)
    }

    private fun knock(l: Line) {
        MainThread.later(3_000) {
            work.execute {
                if (synchronized(gate) { line !== l } || !lost || l.iceRestarts >= RESTART_MAX) return@execute
                requestIceRestart(l, "reconnecting")
                knock(l)
            }
        }
    }

    /** The restart offer itself (iOS sendIceRestartOffer 5183, sendRenegotiationOffer 5184-5215): fresh checks ride
     * «call-restart», «rsn» ice, the connection's own IceRestart constraint — it goes regardless of a busy signaling
     * state, unlike a media offer (reoffer): the reconnect road owns its own timing. */
    private fun sendIceRestartOffer(l: Line) {
        if (synchronized(gate) { line !== l }) return
        log("restart offer n=" + l.iceRestarts)
        val mc = MediaConstraints().apply { mandatory.add(MediaConstraints.KeyValuePair("IceRestart", "true")) }
        l.pc.createOffer(sdp(onMade = { d ->
            val tuned = SessionDescription(d.type, tune(d.description, 40000))
            l.pc.setLocalDescription(sdp(onSet = {
                say(l, JSONArray().put(word(l, "call-restart").put("sdp", JSONObject().put("type", "offer").put("sdp", tuned.description))
                    .put("caps", caps()).put("rsn", "ice")))
                if (l.vtrack != null) bound(l)
            }, onFail = { e -> log("restart offer refused here: " + e) }), tuned)
        }, onFail = { e -> log("restart offer unbuilt: " + e) }), mc)
    }

    /**
     * THEIR OFFER IN THE MIDDLE OF THE CALL (iOS «call-restart» 2391-2465): their new picture, their screen or fresh checks. An
     * offer of another connection — its certificate not the one this connection holds — and the second road's copy are buried.
     * In a glare of two offers the side that was called yields: it takes its own back and answers; the caller keeps its own.
     */
    private fun restart(l: Line, w: JSONObject) {
        val s = w.optJSONObject("sdp")?.optString("sdp")?.ifEmpty { null } ?: return
        val held = l.pc.remoteDescription?.description
        if (held == null || fingerprint(held) != fingerprint(s)) return log("restart offer of another connection — buried")
        if (s == l.seenOffer) return log("restart offer dup — buried")
        l.seenOffer = s
        val rsn = w.optString("rsn")
        log("restart offer rx rsn=" + rsn)
        val offer = SessionDescription(SessionDescription.Type.OFFER, s)
        fun answerIt() = l.pc.createAnswer(sdp(onMade = { d ->
            val tuned = SessionDescription(d.type, tune(d.description, 40000))
            l.pc.setLocalDescription(sdp(onSet = {
                say(l, JSONArray().put(word(l, "call-restart-answer").put("sdp", JSONObject().put("type", "answer").put("sdp", tuned.description))))
                log("restart answer sent")
                if (l.vtrack != null) bound(l)
                // my «yes» joins here, on their picture's offer, while it is fresh — never on fresh checks (iOS K-6)
                if (fresh(l) && rsn != "ice") { l.armedAt = 0L; enableMine(l) }
            }, onFail = { e -> log("restart answer refused here: " + e) }), tuned)
        }, onFail = { e -> log("restart answer unbuilt: " + e) }), MediaConstraints())
        l.pc.setRemoteDescription(sdp(onSet = { answerIt() }, onFail = { e ->
            val open = l.pc.signalingState() == PeerConnection.SignalingState.HAVE_LOCAL_OFFER
            when {
                open && !l.caller -> {
                    log("glare — the called side takes its own back and answers")
                    l.pc.setLocalDescription(sdp(onSet = {
                        l.pc.setRemoteDescription(sdp(onSet = { answerIt() }, onFail = { e2 -> log("restart offer refused after rollback: " + e2) }), offer)
                    }, onFail = { e3 -> log("rollback refused: " + e3) }), SessionDescription(SessionDescription.Type.ROLLBACK, ""))
                }
                open -> log("glare — the caller keeps its own")
                else -> log("restart offer refused: " + e)
            }
        }), offer)
    }

    /** Their answer to my offer in the middle of the call (iOS «call-restart-answer» 2466-2483): the same certificate, once, while my offer is open. */
    private fun restartAnswer(l: Line, w: JSONObject) {
        val s = w.optJSONObject("sdp")?.optString("sdp")?.ifEmpty { null } ?: return
        val held = l.pc.remoteDescription?.description
        if (held == null || fingerprint(held) != fingerprint(s)) return log("restart answer of another connection — buried")
        if (s == l.seenAnswer) return log("restart answer dup — buried")
        l.seenAnswer = s
        if (l.pc.signalingState() != PeerConnection.SignalingState.HAVE_LOCAL_OFFER) return log("restart answer with no offer open — buried")
        l.pc.setRemoteDescription(sdp(onSet = { log("restart answer applied"); if (l.vtrack != null) bound(l) },
            onFail = { e -> log("restart answer refused: " + e) }), SessionDescription(SessionDescription.Type.ANSWER, s))
    }

    /** A connection's name (iOS fingerprint 4155): the certificate's fingerprint its description carries, on any kind of line end. */
    private fun fingerprint(sdp: String) =
        sdp.lineSequence().firstOrNull { it.startsWith("a=fingerprint:") }?.removePrefix("a=fingerprint:")?.trim()?.lowercase()

    private fun fresh(l: Line) = l.armedAt != 0L && System.currentTimeMillis() - l.armedAt < 40_000

    /** iOS autoSpeakerOnVideo 957: a video call takes the loudspeaker once, and only from the ear — a headset or a car keep the sound. */
    private fun autoSpeaker(l: Line) {
        if (l.speakerDecided || !video || l.connectedAt == 0L) return
        l.speakerDecided = true
        if (speaker) return
        val am = am() ?: return
        if (Build.VERSION.SDK_INT >= 31 && am.communicationDevice?.let { it.type in OUTSIDE } == true) return
        setSpeaker(true)
        log("video: loudspeaker taken")
    }

    private fun log(s: String) { Log.d("Montana", "call line: " + s) }
}
