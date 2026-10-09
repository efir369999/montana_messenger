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
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
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
import org.webrtc.RTCStatsReport
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
    private const val SETUP_ASK_MAX = 2   // iOS setupAskMax (MontanaCall.swift, atom 319c1ca96b0a): fresh asks before a path failed before the connect ends the call

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
        var setupAsks = 0   // iOS setupAsks (atom 319c1ca96b0a): fresh asks on a path failed before the first connect
        var routeKey = ""   // iOS routeKey: the wifi/cellular letters of the route in hand
        var routeRestartAt = 0L   // iOS routeRestartAt: one ask per route change, debounced two seconds
        var routeCallback: ConnectivityManager.NetworkCallback? = null   // iOS routeMonitor
        // my picture (iOS birthLocalVideo): the camera, its frames' helper, the source and the track «mt_video»
        var cam: CameraVideoCapturer? = null
        var camGen = 0   // iOS resumeGen, 24.09, build 51552a7b8d64: voids a fault still arriving off the camera this line has already left
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
        // THE MEASURE'S OWN STATE (iOS 3862-3895, resetConnectionWitnesses 3528-3531): one connection's witnesses of a break,
        // the peer's picture stream by stream, the ladder's step and floor, and the summary's counters
        var measureGen = 0
        var measuring = false
        var pathSeen: Map<String, Long> = emptyMap()   // each pair's own count at its last sighting (iOS pathSeen, 24.09)
        var lastInBytes = 0L
        var stallSamples = 0
        var everFlowed = false
        val pictureSeen = HashMap<String, Long>()   // each incoming video stream's frames (iOS pictureSeen, 23.09)
        var pictureStall = 0
        var firstVideoIn = false
        var lastJournalAt = 0L
        var ladderStep = MODEST
        var pathFloor = MODEST   // iOS pathFloor 3850: the modest top until the pair is proven direct
        var ladderMovedAt = 0L
        var ladderGoodTicks = 0
        var lastVideoLost = 0L
        var powerTicks = 0
        var breakRound = 0   // a deadline armed by an earlier break never ends a later one
        var lastIce = "new"
        var sum = Summary()   // the call's story outlives a connection rebuilt in place: it is handed over
        // THE CALL OUTLIVES ITS CONNECTION (iOS rejoinHeldCall 3533-3587, rebuildInPlace 3612-3640, rebuildForRejoin 3656-3713):
        // a connection built in place of a dead one -- by the run that came back, or by the living side -- until it stands
        var rejoining = false
        var rebuiltInPlace = false
        var rejoinUntil = 0L   // the run that came back waits for its peer until the call's window closes
        var seenRejoin: String? = null   // the peer's rejoin offer, taken once
    }

    /** THE CALL TELLS ITS OWN STORY IN ONE LINE (iOS 3864-3884, the summary 3021-3064): gathered while it lives, spoken at its end. */
    private class Summary {
        var samples = 0; var relaySamples = 0; var tunnelSamples = 0
        val paths = sortedSetOf<String>()
        var breaks = 0; var restarts = 0; var ladderMin = 0; var powerFloorMax = 0
        var rttSum = 0L; var rttN = 0
        var lostVideo = 0L; var inBytes = 0L; var outBytes = 0L; var videoDarkS = 0
        var battStart = -1; var battLast = -1; var charging = false; var thermal = "-"
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
    /** THE PEER REBUILDS A CALL IN PLACE (iOS peerRebuilds, learnPeerCaps 922-932): its caps said «rejoin» once in this call. A break
     * then waits for it as long as a ring rings -- its run comes back within it. */
    @Volatile var peerRebuilds = false
        private set
    fun learnCaps(ref: String, epoch: String, caps: JSONObject?) {
        if (caps?.optBoolean("rejoin") != true || peerRebuilds) return
        if (mine(ref, epoch) == null && Calls.peer() != ref) return
        peerRebuilds = true
        log("call_caps the peer rebuilds in place")
        Calls.holdOnDisk(force = true)   // the record says it at once: a run that dies now goes back into the call
    }

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
    // THE PEER'S PICTURE HAS ONE WITNESS, ITS OWN FRAMES, STREAM BY STREAM (iOS notePeerPicture 3907, pictureSeen 3885-3889,
    // measureTick 4059-4079): two samples of the measure without a new frame on any incoming video stream after the picture
    // once arrived name it stood still, and the call's screen covers the stale frame with the peer's blurred face -- the same
    // cover that stands while either side holds the call (iOS applyCovers 5491-5495).
    @Volatile var peerPaused = false
        private set
    // MY OWN CAMERA WAS TAKEN BY THE SYSTEM (iOS CallUIModel.selfPaused 5482, noteSelfPicture 3900-3906): its own two words --
    // taken (disconnected, a fault) and given back (its first frame) -- never a guess from frames
    @Volatile var selfPaused = false
        private set
    // THE LIGHT BEFORE THE CALL'S NAME (iOS MTCallLight 5424-5435, CallUIModel.signal 5466): 2 green -- clean at the top
    // step, 1 yellow -- held below it, 0 red -- squeezed now; a break reddens it whatever the ladder says.
    @Volatile var signal = 2
        private set
    // THE POWER FLOOR (iOS MontanaPower.swift 12-29, MontanaCall.swift applyLadder 3730-3746, build 41d0cac99d59): the
    // battery, the charger, Low Power Mode and the thermal state, read every two seconds while a picture rides the
    // line; under pressure the call's light wears the battery instead of its dot (iOS MTCallLight, build bd83db719a66).
    @Volatile var powerSaving = false
        private set
    @Volatile private var powerFloorNow = 0
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
            val s = peerShape
            if (s == null || s.first != f.rotatedWidth || s.second != f.rotatedHeight) { peerShape = f.rotatedWidth to f.rotatedHeight; moved() }
            theirs.onFrame(f)
        }
    }

    private fun moved() = MainThread.post { updateProximity(); CallFloat.refresh(why = "model"); changed?.invoke() }

    /** The peer's picture's own shape (its frames, rotated as drawn): the window over other apps takes it (iOS MTFloatFeed.onSize). */
    @Volatile var peerShape: Pair<Int, Int>? = null
        private set

    /** THE CALL HOLDS THE SENSOR WHILE ITS SOUND STANDS AT THE EAR (iOS updateProximity 4398-4403): a call in any state, a
     * voice call, not on the loudspeaker, no headset or car holding the sound. Re-asked at every change of the call and of
     * the route -- a headset that comes or goes moves it too. */
    fun updateProximity() = Proximity.hold("call", Calls.busy() && !video && !Calls.ringVideo() && !speaker && !outsideNow())
    private fun outsideNow(): Boolean {
        val am = am() ?: return false
        return if (Build.VERSION.SDK_INT >= 31) am.communicationDevice?.let { it.type in OUTSIDE } == true
        else runCatching { am.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any { it.type in OUTSIDE } }.getOrDefault(false)
    }

    /** The moment the voice joined, for the call's clock; 0 — not yet. */
    val connectedAt: Long get() = synchronized(gate) { line?.connectedAt ?: 0L }
    /** The second of talk now (iOS MontanaCall.talkSecond, MontanaCall.swift:672-677; CallMint): the call's peer, a name of this call
     * alone — the first eight bytes of its seed in hex, or its connect's millisecond — and a name of this call's second. */
    class TalkSecond(val peer: String, val call: String, val ref: String)
    fun talkSecond(): TalkSecond? {
        val l = synchronized(gate) { line?.takeIf { it.connectedAt != 0L } } ?: return null
        val at = l.connectedAt
        val seed = runCatching { android.util.Base64.decode(l.seed, android.util.Base64.DEFAULT) }.getOrNull()
        val call = seed?.takeIf { it.isNotEmpty() }?.take(8)?.joinToString("") { "%02x".format(it) } ?: at.toString()
        return TalkSecond(l.ref, call, call + ":" + (System.currentTimeMillis() - at) / 1000)
    }

    /** «Answer» with the offer in hand (iOS proceedAccept): the line is built on its own queue, the answer leaves at once. */
    fun answer(ref: String, seed: String, offer: String) = work.execute {
        val l = build(ref, seed) ?: return@execute
        armConnect(l)
        l.pc.setRemoteDescription(sdp(onSet = {
            // A BIRTH HAS ONE LIFE (iOS callGen guards, atom 7492b6b28754): a call refused or ended while its offer was being
            // taken raises no camera and says nothing -- the line in hand is no longer this one
            if (synchronized(gate) { line !== l }) return@sdp
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

    /** One connection for one call (iOS rtcConfig + buildPC), on the line's queue; the phone's sound turns to the call. A connection
     * built in place of a dead one (`replacing`) takes its call's clock, its side and its story; the sound already stands. */
    private fun build(ref: String, seed: String, replacing: Line? = null): Line? {
        if (synchronized(gate) { line != null && line !== replacing }) return null
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
            // THE ENGINE'S OWN GATHER FAILURES (iOS didFailToGatherIceCandidate, atom 319c1ca96b0a): by scheme and code, never an address
            override fun onIceCandidateError(e: org.webrtc.IceCandidateErrorEvent) {
                log("ice_gather_fail scheme=" + e.url.substringBefore(':') + " code=" + e.errorCode)
            }
        }) ?: return null.also { log("no connection"); Calls.hangUp("connection-unbuilt") }
        // iOS buildPC: one voice track «mt_audio» in the stream «mt_stream», the person's mute applied to it at birth
        val source = f.createAudioSource(MediaConstraints())
        val track = f.createAudioTrack("mt_audio", source)
        track.setEnabled(!muted)
        pc.addTrack(track, listOf("mt_stream"))
        val l = Line(ref, seed, pc, source, track)
        made = l
        if (replacing != null) {
            l.connectedAt = replacing.connectedAt; l.caller = replacing.caller; l.speakerDecided = replacing.speakerDecided
            l.sum = replacing.sum; l.breakRound = replacing.breakRound; l.routeKey = replacing.routeKey
            synchronized(gate) { line = l }
            // the dead connection goes, its call does not: its camera and its picture are the new connection's to raise
            stopRouteWatch(replacing)
            replacing.measureGen++
            cameraOff(replacing)
            runCatching { replacing.remote?.dispose() }
            runCatching { replacing.pc.dispose() }
            runCatching { replacing.source.dispose() }
            remoteLive = false; peerSharing = false; sniffed = false
            moved()
            return l
        }
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
        .put("sframe", false).put("av", false).put("rejoin", true)   // this build rebuilds a call in place and goes back into it (iOS caps.rejoin)

    private fun word(l: Line, ctrl: String) =
        JSONObject().put("t", "cal").put("ctrl", ctrl).put("ts", NodeClock.now()).put("e", Calls.epochOf(l.seed))

    private fun say(l: Line, words: JSONArray) = Signal.postWord(l.ref, Calls.epochOf(l.seed), words.toString().toByteArray())

    /** The answer travels an unreliable road: said again every two seconds until the voice joins (iOS answerResendTimer). */
    private fun sendAnswer(l: Line, sdp: String, n: Int) {
        // a connection built in place keeps its call's clock: its answer is said until the new connection stands
        if (synchronized(gate) { line !== l } || (l.connectedAt != 0L && !l.rejoining)) return
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
        log("ice_tx " + kinds(l.out))
        l.out.clear()
        l.flushes++
        say(l, words)
    }

    /** The caller's candidates (iOS «call-ice» 2368): into the line once it holds the offer, kept until then. */
    fun remoteIce(ref: String, epoch: String, cs: List<IceCandidate>) = work.execute {
        val l = mine(ref, epoch)
        if (l != null) log("ice_rx " + kinds(cs))
        if (l != null && l.remoteSet) { cs.forEach { l.pc.addIceCandidate(it) }; return@execute }
        synchronized(gate) {
            cs.forEach { waiting.add(epoch to it) }
            while (waiting.size > 64) waiting.removeAt(0)
        }
    }

    /** THE CANDIDATES BY TYPE, TRANSPORT AND FAMILY (iOS ice_tx/ice_rx, atom 319c1ca96b0a): whether a relay ever existed is
     * said, never an address -- «relay/tcp/4=1 host/udp/6=2». */
    private fun kinds(cs: List<IceCandidate>): String {
        val n = java.util.TreeMap<String, Int>()
        for (c in cs) {
            val t = c.sdp.removePrefix("a=").split(' ')
            if (t.size < 8) continue
            val key = t[7] + "/" + t[2].lowercase() + "/" + (if (':' in t[4]) "6" else "4")
            n[key] = (n[key] ?: 0) + 1
        }
        return if (n.isEmpty()) "none" else n.entries.joinToString(" ") { it.key + "=" + it.value }
    }

    /** THE PAIR TABLE AT A FAILED VERDICT (iOS call_pairs, atom 319c1ca96b0a): each pair's local and remote type, its transport
     * and its state -- what the engine tried before it said «failed». */
    private fun notePairs(l: Line, why: String) = runCatching {
        l.pc.getStats { r ->
            val all = r.statsMap
            val rows = all.values.filter { it.type == "candidate-pair" }.take(12).map { p ->
                val lc = all[p.members["localCandidateId"] as? String]?.members
                val rc = all[p.members["remoteCandidateId"] as? String]?.members
                (lc?.get("candidateType") ?: "?").toString() + "/" + (lc?.get("protocol") ?: "?") + "-" + (rc?.get("candidateType") ?: "?") + ":" + (p.members["state"] ?: "?")
            }
            log("call_pairs " + why + " n=" + rows.size + " " + rows.joinToString(" "))
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
        l.lastIce = s.name.lowercase()
        when (s) {
            PeerConnection.IceConnectionState.CONNECTED, PeerConnection.IceConnectionState.COMPLETED -> {
                leaveBreak(l, "ice connected")
                l.iceRestarts = 0
                l.restartAskedAt = 0L
                startRouteWatch(l)
                if (l.connectedAt == 0L) {
                    l.connectedAt = System.currentTimeMillis()
                    MintBeat.run()   // both sides mint or burn the talk by the second (iOS MontanaCall.swift:4417-4419, CallMint)
                    l.sum.battStart = power().level   // iOS 4420: every call's battery at its connect, a voice call's too
                    CallService.sync()
                    autoSpeaker(l)
                }
                // THE MEASUREMENT STARTS HERE AND ONLY HERE (iOS 5048-5055): a reconnect never starts a second loop
                if (!l.measuring) { l.measuring = true; measure(l, ++l.measureGen) }
                if (l.rejoining) {
                    // A CONNECTION BUILT IN PLACE STANDS (iOS 5072-5080): the call goes on, a rejoin that stood counts no fall, and
                    // a video call speaks aloud again as at its first connect
                    l.rejoining = false
                    l.speakerDecided = false
                    autoSpeaker(l)
                    log("call_rejoin the new connection stands — the call goes on")
                    Calls.rejoinStood()
                }
                Calls.holdOnDisk(force = true)   // the record of the call that lives (iOS holdOnDisk 3505-3521)
                raiseVideoCeiling(l)   // the link is proven: in five seconds the pair is read and the ceiling set (iOS 5056)
            }
            // A FAILED PATH BEFORE THE FIRST CONNECT IS ANSWERED, NOT FINAL (iOS setupPathFailed, MontanaCall.swift, atom
            // 319c1ca96b0a, 29.09): the engine's «failed» here used to end the call at once while both phones still held
            // each other's candidates; asking again, once on every road with a fresh relay pass and once on the relay
            // alone, finds the path a flat end never tried. AFTER THE CONNECT «failed» IS A BREAK, NOT AN END (iOS 5084-5091):
            // the side that sees it asks for fresh checks, and the thirty-second deadline is the verdict.
            PeerConnection.IceConnectionState.FAILED -> if (l.connectedAt == 0L) setupPathFailed(l) else enterBreak(l, "ice failed")
            // THE SUSPICION GETS A GRACE (iOS peerConnection(_:didChange:) 5092-5102, b23f80900c0f): «disconnected» is a few
            // missed checks, not a verdict — measured 22:51:34, it healed in 1.4s and the person heard the break cue for a blip.
            PeerConnection.IceConnectionState.DISCONNECTED -> MainThread.later(DISCONNECT_GRACE_MS) {
                if (synchronized(gate) { line === l }) work.execute {
                    if (l.pc.iceConnectionState() != PeerConnection.IceConnectionState.DISCONNECTED) return@execute log("disconnected healed within the grace — no break declared")
                    enterBreak(l, "ice disconnected past the grace")
                }
            }
            else -> {}
        }
    }

    /**
     * THE BREAK HAS ONE DOOR IN (iOS enterReconnecting 3478-3488): the ICE machine past its grace, its «failed» after the
     * connect, or the path's own silence (the measure) — the light reddens, the break's quiet pips sound under the talk, fresh
     * checks are asked at once and every three seconds (iOS scheduleIceRestart 5147-5165), and the thirty-second deadline
     * is the verdict if none of them form.
     */
    private fun enterBreak(l: Line, why: String, fresh: Boolean = false) {
        if (synchronized(gate) { line !== l } || l.connectedAt == 0L) return
        if (lost) { if (fresh) armDeadline(l); return }   // a rebuild inside a break waits anew by its own window
        lost = true
        if (!fresh) l.sum.breaks++
        log("call_reconnect break by " + why)
        breakTone(true)
        moved()
        armDeadline(l)
        if (!fresh) scheduleIceRestart(l)   // a fresh connection is checked by its own offer, not asked again
    }

    /**
     * THE WAIT OF A BREAK (iOS armReconnectDeadline 3489-3501): the run that came back waits for its peer's answer until the
     * call's window closes (its peer may be in Settings too), at least twenty seconds; a peer that rebuilds in place is waited
     * for as long as a ring rings -- its run comes back within it; any other peer, the thirty seconds of checks.
     */
    private fun armDeadline(l: Line) {
        val round = ++l.breakRound
        val wait = if (l.rejoining) maxOf(REJOIN_ANSWER_MS, l.rejoinUntil - System.currentTimeMillis())
            else if (peerRebuilds) Calls.LIFE_MS else RECONNECT_DEADLINE_MS
        MainThread.later(wait) {
            if (synchronized(gate) { line === l } && lost && l.breakRound == round) work.execute {
                log("reconnecting past the deadline (" + wait / 1000 + "s) — " + l.iceRestarts + " fresh transports asked, none formed — ending")
                Calls.hangUp(if (l.rejoining) "rejoin-unanswered" else "lost")   // a rule ended it, not a hand (iOS endByRule)
            }
        }
    }
    private const val REJOIN_ANSWER_MS = 20_000L   // iOS rejoinAnswerS

    // ═══ THE CALL OUTLIVES ITS PROCESS AND ITS CONNECTION (iOS 3503-3713, atoms dc1b54275bf6, 85e52e1b67b9, c0e89e93b0f9) ═══

    /**
     * THE RUN GOES BACK INTO THE CALL ITS PROCESS HELD (iOS rejoinHeldCall 3533-3587): the same seed, a new connection, its offer
     * as «call» with the reason «rejoin» on the node's lane -- no ring on either side. The call keeps its clock; the screen says
     * the break until the new connection stands, and waits until the call's window closes.
     */
    fun rejoin(ref: String, seed: String, withVideo: Boolean, caller: Boolean, connectedAt: Long, until: Long) = work.execute {
        val l = build(ref, seed) ?: return@execute
        l.caller = caller
        l.connectedAt = connectedAt
        l.rejoining = true
        l.rejoinUntil = until
        peerRebuilds = true   // only a peer that rebuilds is gone back into (iOS h.rebuilds)
        log("call_rejoin tx video=" + (if (withVideo) 1 else 0) + " epoch=" + Calls.epochOf(seed).take(8))
        if (withVideo) {
            video = true
            if (camera(l)) place(l)
            else l.pc.addTransceiver(MediaStreamTrack.MediaType.MEDIA_TYPE_VIDEO, RtpTransceiver.RtpTransceiverInit(RtpTransceiver.RtpTransceiverDirection.RECV_ONLY))
        }
        enterBreak(l, "rejoin", fresh = true)
        offerRejoin(l)
    }

    /**
     * THE LIVING RUN REBUILDS ITS OWN TRANSPORT (iOS rebuildInPlace 3612-3640): the break's first ask did not form, and a dead
     * transport is not asked again -- the connection is closed and born anew, the peer answers the rejoin in place; the call
     * keeps its clock, its system call and its screen. What a hand did by hanging up and dialling again, without the hand.
     */
    private fun rebuildInPlace(old: Line, why: String) {
        if (!lost || old.rebuiltInPlace) return
        log("call_rejoin tx in place — " + why)
        val l = build(old.ref, old.seed, replacing = old) ?: return
        l.rebuiltInPlace = true
        l.rejoining = true
        l.rejoinUntil = System.currentTimeMillis() + Calls.LIFE_MS
        if (video) { if (camera(l)) place(l) else l.pc.addTransceiver(MediaStreamTrack.MediaType.MEDIA_TYPE_VIDEO, RtpTransceiver.RtpTransceiverInit(RtpTransceiver.RtpTransceiverDirection.RECV_ONLY)) }
        armDeadline(l)
        offerRejoin(l)
    }

    /** The rejoin's own offer (iOS offerRejoin 3588-3611): one road for the run that came back and for the living run's rebuild. */
    private fun offerRejoin(l: Line) {
        l.holding = true   // the candidates wait for the peer's answer, eight seconds at most (iOS iceHeldForPeerWord, releaseHeldIce)
        MainThread.later(8000) { if (synchronized(gate) { line === l }) work.execute { unhold(l, "time") } }
        l.pc.createOffer(sdp(onMade = { d ->
            val tuned = SessionDescription(d.type, tune(d.description, 64000))
            l.pc.setLocalDescription(sdp(onSet = { if (l.vtrack != null) bound(l); sendRejoinOffer(l, tuned.description, 0) },
                onFail = { e -> log("own rejoin offer refused: " + e); Calls.hangUp("rejoin-offer-refused-here") }), tuned)
        }, onFail = { e -> log("rejoin offer unbuilt: " + e); Calls.hangUp("rejoin-offer-unbuilt") }), MediaConstraints())
    }

    /** The rejoin's offer rides the node's lane every two seconds until the peer's answer stands, nine times at most (iOS
     * sendRejoinOffer 3641-3655): the peer is awake in the call, no ring is needed, and the lane names the call. */
    private fun sendRejoinOffer(l: Line, sdp: String, n: Int) {
        if (synchronized(gate) { line !== l } || !l.rejoining || l.remoteSet || 9 <= n) return
        val w = word(l, "call").put("sdp", JSONObject().put("type", "offer").put("sdp", sdp)).put("video", video).put("caps", caps())
            .put("s", l.seed).put("rsn", "rejoin").put("n", Prefs.userName.trim())
        say(l, JSONArray().put(w))
        log("call_rejoin offer n=" + (n + 1))
        MainThread.later(2000) { work.execute { sendRejoinOffer(l, sdp, n + 1) } }
    }

    /**
     * THE LIVING SIDE REBUILDS IN PLACE (iOS rebuildForRejoin 3656-3713): the peer's run came back with a new connection; the
     * dead one is closed, a new one answers the rejoin, and the call -- its clock, its system call, its screen -- goes on. A
     * rejoin carrying this connection's own certificate is a copy, not a rebirth; a copy of the offer already taken is buried.
     * BOTH RUNS CAME BACK (iOS 2118-2126): the caller's offer stands while nothing has answered it -- the callee's run answers it.
     */
    fun rebuildForRejoin(ref: String, epoch: String, offer: String, caps: JSONObject?) = work.execute {
        val old = mine(ref, epoch) ?: return@execute log("call_rejoin rx for no call held here — buried")
        if (old.connectedAt == 0L) return@execute log("call_rejoin rx for a call that never stood — buried")
        if (offer == old.seenRejoin) return@execute log("call_rejoin rx copy — buried")
        val theirs = fingerprint(offer)
        if (theirs != null && theirs == old.pc.remoteDescription?.description?.let { fingerprint(it) })
            return@execute log("call_rejoin rx with this connection's own certificate — no rebirth, buried")
        if (old.rejoining && old.caller && !old.remoteSet) {
            log("call_rejoin rx while this run is rejoining too — the caller's offer stands, theirs buried")
            return@execute
        }
        if (caps?.optBoolean("rejoin") == true) peerRebuilds = true
        log("call_rejoin rx — the peer's new connection replaces the dead one, no ring")
        val l = build(old.ref, old.seed, replacing = old) ?: return@execute
        l.seenRejoin = offer
        l.rejoining = true
        l.rejoinUntil = System.currentTimeMillis() + Calls.LIFE_MS
        enterBreak(l, "peer rejoin", fresh = true)
        l.pc.setRemoteDescription(sdp(onSet = {
            l.remoteSet = true
            drain(l)
            // the offer decides whether the call goes on with video (iOS adoptVideoFromOffer, 3685-3686)
            if (offer.contains("m=video")) { video = true; if (camera(l)) place(l) } else if (video) { video = false; remoteLive = false }
            moved()
            CallService.sync()
            l.pc.createAnswer(sdp(onMade = { d ->
                val tuned = SessionDescription(d.type, tune(d.description, 40000))
                l.pc.setLocalDescription(sdp(onSet = { sendAnswer(l, tuned.description, 0); if (l.vtrack != null) bound(l) },
                    onFail = { e -> log("own rejoin answer refused: " + e); Calls.hangUp("rejoin-answer-refused-here") }), tuned)
            }, onFail = { e -> log("rejoin answer unbuilt: " + e); Calls.hangUp("rejoin-answer-unbuilt") }), MediaConstraints())
        }, onFail = { e -> log("the peer's rejoin offer refused: " + e); Calls.hangUp("rejoin-offer-refused") }), SessionDescription(SessionDescription.Type.OFFER, offer))
    }

    /** The rejoining run: its own offer stands and waits for the peer's answer (Calls routes «call-answer» here). */
    fun rejoiningFor(ref: String, epoch: String): Boolean = mine(ref, epoch)?.rejoining == true

    /** ...AND ONE DOOR OUT (iOS leaveReconnecting 3715-3723): the ICE machine's «connected» or the path answering again. */
    private fun leaveBreak(l: Line, why: String) {
        if (!lost) return
        lost = false
        l.breakRound++
        l.iceRestarts = 0
        l.restartAskedAt = 0L
        log("call_reconnect back by " + why)
        breakTone(false)
        moved()
    }

    /**
     * THE BREAK'S OWN SOUND (iOS reconnectVoice 4647-4668, reconnectFile 4616-4645): the tone and the red light are one act —
     * two low pips every three seconds, the iPhone's own samples (Calls.searchPips), quietly under the talk (0.35): the line
     * may come back mid-word. Both are silenced by the same return.
     */
    private var breakPips: android.media.AudioTrack? = null
    private fun breakTone(on: Boolean) = MainThread.post {
        breakPips?.let { runCatching { it.stop(); it.release() } }
        breakPips = null
        if (!on || !lost) return@post
        val pcm = Calls.searchPips()
        breakPips = runCatching {
            android.media.AudioTrack.Builder()
                .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION_SIGNALLING)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
                .setAudioFormat(android.media.AudioFormat.Builder().setEncoding(android.media.AudioFormat.ENCODING_PCM_16BIT).setSampleRate(8000)
                    .setChannelMask(android.media.AudioFormat.CHANNEL_OUT_MONO).build())
                .setTransferMode(android.media.AudioTrack.MODE_STATIC).setBufferSizeInBytes(pcm.size * 2).build()
                .also { t -> t.write(pcm, 0, pcm.size); t.setLoopPoints(0, pcm.size, -1); t.setVolume(0.35f); t.play() }
        }.getOrNull()
        log("call_reconnect voice on played=" + (if (breakPips != null) 1 else 0))
    }

    /**
     * A FAILED PATH BEFORE THE CONNECT IS ANSWERED, NOT WATCHED (iOS setupPathFailed, MontanaCall.swift, atom
     * 319c1ca96b0a, 29.09): the first ask tries every road again with a fresh relay pass, the second the relay alone; a
     * third verdict ends the call by rule and tells the person in their language (CallScreen.tellNoRoad).
     */
    private fun setupPathFailed(l: Line) {
        if (synchronized(gate) { line !== l } || l.connectedAt != 0L) return
        notePairs(l, "failed ask=" + l.setupAsks)
        l.setupAsks++
        if (l.setupAsks > SETUP_ASK_MAX) {
            log("no path after " + (l.setupAsks - 1) + " fresh asks, the last on the relay alone — ending")
            CallScreen.tellNoRoad()
            Calls.hangUp("no-path")
            return
        }
        val relay = l.setupAsks == SETUP_ASK_MAX
        log("path failed before the connect — ask n=" + l.setupAsks + " " + (if (relay) "relay only" else "every road, fresh pass"))
        val cfg = PeerConnection.RTCConfiguration(servers(fresh = true)).apply {
            sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN
            continualGatheringPolicy = PeerConnection.ContinualGatheringPolicy.GATHER_CONTINUALLY
            bundlePolicy = PeerConnection.BundlePolicy.MAXBUNDLE
            iceTransportsType = if (relay) PeerConnection.IceTransportsType.RELAY else PeerConnection.IceTransportsType.ALL
        }
        if (!l.pc.setConfiguration(cfg)) log("the engine refused the new configuration — the ask rides the old one")
        l.restartAskedAt = 0L
        requestIceRestart(l, "setup ask n=" + l.setupAsks)
    }

    /** What a closed line tells its call: the seconds it spoke, the moment it connected, and its part of the call's story. */
    class Spoken(val dur: Int, val connectedAt: Long, val summary: String, val end: String, val video: Boolean = false)

    /** The call ended (Calls.end): the line closes, the phone's sound is given back, and what it spoke is returned. */
    fun stop(seed: String): Spoken {
        val l = synchronized(gate) {
            waiting.clear()
            line?.takeIf { it.seed == seed }?.also { line = null }
        } ?: return Spoken(0, 0L, "", "")
        val spoken = story(l)
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
        front = true; sniffed = false; askRound++; sharing = false; peerPaused = false; selfPaused = false; cameraTold = false; peerShape = null
        peerRebuilds = false
        powerFloorNow = 0; powerSaving = false; signal = 2   // the counters and the lights belong to one call (iOS 3066-3072)
        l.measureGen++   // no tick of the ended call survives into the next one (iOS K-9, 3081)
        breakTone(false)
        theirs.into = null; own.into = null
        AvatarMask.set(false, "call-end")   // the mask lives inside one call (iOS MontanaCall.swift 3110)
        moved()
        return spoken
    }

    /**
     * THE LINE'S PART OF THE CALL'S ONE LINE (iOS 3021-3053): how it was carried, how much rode a relay or a tunnel, the round
     * trip, the breaks and restarts it survived, how far the picture stepped down, the dark seconds, the bytes both ways, and
     * the battery's drain in percent an hour (a call of a minute or more, off the charger); and its part of the day-long
     * journal's end line (iOS 3061-3064): the paths, the round trip, the breaks, the ICE machine's last word, the setup's asks.
     */
    private fun story(l: Line): Spoken {
        val at = l.connectedAt
        val dur = if (at == 0L) 0 else ((System.currentTimeMillis() - at) / 1000).toInt()
        val sm = l.sum
        val relayPct = if (sm.samples > 0) sm.relaySamples * 100 / sm.samples else -1
        val tunPct = if (sm.samples > 0) sm.tunnelSamples * 100 / sm.samples else -1
        val rtt = if (sm.rttN > 0) (sm.rttSum / sm.rttN).toInt() else -1
        val paths = if (sm.paths.isEmpty()) "-" else sm.paths.joinToString("+")
        val b0 = sm.battStart; val b1 = sm.battLast
        val drain = if (b0 >= 0 && b1 >= 0 && dur >= 60 && !sm.charging) String.format(java.util.Locale.ROOT, "%.1f", (b0 - b1) * 3600.0 / dur) else "-"
        val summary = "talk_s=" + dur + " paths=" + paths + " relay_pct=" + relayPct + " tun_pct=" + tunPct + " rtt_avg=" + rtt +
            " breaks=" + sm.breaks + " restarts=" + sm.restarts + " ladder_min_step=" + sm.ladderMin + " video_lost_pkts=" + sm.lostVideo +
            " video_dark_s=" + sm.videoDarkS + " in_kb=" + sm.inBytes / 1024 + " out_kb=" + sm.outBytes / 1024 + " crypto=dtls-srtp" +
            " batt=" + b0 + "->" + b1 + " drain_pct_h=" + drain + " thermal=" + sm.thermal + " power_floor_max=" + sm.powerFloorMax
        val end = "paths=" + paths + " rtt_avg=" + rtt + " breaks=" + sm.breaks + " ice=" + l.lastIce + " asks=" + l.setupAsks +
            " relay_only=" + (if (l.setupAsks >= SETUP_ASK_MAX) 1 else 0)
        return Spoken(dur, at, summary, end, video)
    }

    // ── the relay pass (iOS rtcConfig 1045-1109, WakePush fetchTurnCred 1467) ──

    private fun servers(fresh: Boolean = false): List<PeerConnection.IceServer> {
        val p = pass(fresh) ?: return emptyList<PeerConnection.IceServer>().also { log("NO ICE SERVERS — host-only call") }
        val list = ArrayList<PeerConnection.IceServer>()
        // NOT ONE ADDRESS OF A FAMILY THIS PHONE DOES NOT HOLD (iOS reachableRelay, ContentView 3405, MontanaCall 1095-1110, atom
        // 82296a6b5364): a road of a family the phone does not hold is a wall, and every packet sent at it burns its whole
        // retransmission budget first (13.09: twenty of a call's twenty-four seconds went into two IPv6 addresses of our relay on a
        // cellular network with no IPv6). A relay named by name is left alone: the system resolves what it can reach.
        val allStun = strings(p.optJSONArray("stun"))
        val allUris = strings(p.optJSONArray("uris"))
        val stun = reachable(allStun)
        val reachableUris = reachable(allUris)
        if (stun.size != allStun.size || reachableUris.size != allUris.size) log("turn_cred dropped " + (allStun.size - stun.size + allUris.size - reachableUris.size) + " of a family this phone has not")
        if (stun.isNotEmpty()) list.add(PeerConnection.IceServer.builder(stun).createIceServer())
        // iOS turnRank: the TLS door on 443 first — it survives dead UDP and DPI — then the other TLS, tcp, udp
        val uris = reachableUris.sortedBy { u ->
            if (u.startsWith("turns:")) (if (u.contains(":443")) 0 else 1) else if (u.contains("transport=tcp")) 2 else 3
        }
        if (uris.isNotEmpty()) list.add(PeerConnection.IceServer.builder(uris).setUsername(p.optString("u")).setPassword(p.optString("c")).createIceServer())
        log("servers stun=" + stun.size + " relay=" + uris.size)
        return list
    }

    /** The families this phone holds now (iOS MontanaNet.hasV4/hasV6): a literal relay address of another family is dropped. */
    private fun reachable(urls: List<String>): List<String> {
        val lp = runCatching { Book.ctx.getSystemService(ConnectivityManager::class.java).let { it.getLinkProperties(it.activeNetwork) } }.getOrNull() ?: return urls
        val addrs = lp.linkAddresses.map { it.address }.filter { !it.isLoopbackAddress && !it.isLinkLocalAddress }
        val v4 = addrs.any { it is java.net.Inet4Address }
        val v6 = addrs.any { it is java.net.Inet6Address }
        return urls.filter { u ->
            val host = u.substringAfter(':').substringBefore('?')
            if (host.startsWith("[")) v6
            else host.substringBeforeLast(':').split('.').let { it.size == 4 && it.all { p -> p.toIntOrNull() != null } }.let { literal -> if (literal) v4 else true }
        }
    }

    private fun strings(a: JSONArray?) = (0 until (a?.length() ?: 0)).mapNotNull { a?.optString(it)?.ifEmpty { null } }

    /** iOS turnPassLive: a pass whose name is its moment lives while ten minutes of it remain. */
    private fun live(p: JSONObject) = p.optString("u").toDoubleOrNull()?.let { it - System.currentTimeMillis() / 1000.0 > 600 } ?: true

    /** The remembered pass, else a fresh one from every door at once — the first answer wins (iOS fetchTurnCred). */
    // A FRESH ASK AFTER A VERDICT SKIPS THE REMEMBERED PASS (iOS rtcConfig freshPass, atom 319c1ca96b0a): the remembered
    // one may be the very pass the relay just refused.
    private fun pass(fresh: Boolean = false): JSONObject? {
        if (!fresh) runCatching { JSONObject(Prefs.str(PASS, "")) }.getOrNull()?.takeIf { it.optJSONArray("uris") != null && live(it) }?.let { return it }
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
    private val routeWatch = AudioManager.OnCommunicationDeviceChangedListener { d -> log("audio_route_change now=" + way(d?.type)); MainThread.post { updateProximity() } }
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
    fun setSpeaker(on: Boolean) { speaker = on; synchronized(gate) { line }?.speakerDecided = true; route(on); MainThread.post { updateProximity() } }

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
        val icon = if (ext != null) glyphOf(ext.type) else if (onSpeaker) R.drawable.ic_speaker_wave3 else R.drawable.ic_route_phone
        return Face(R.string.call_audio, icon, ext != null || onSpeaker, true)
    }

    // WHERE THE SOUND IS, BY ITS DEVICE'S OWN GLYPH (iOS MontanaAudioRoute.glyph 7319-7331): headphones for a headset and any
    // Bluetooth (the iPhone tells AirPods by their name, which Android's devices do not carry), the loudspeaker box
    // (hifispeaker) for any other device outside the phone
    private fun glyphOf(t: Int) = when (t) {
        AudioDeviceInfo.TYPE_USB_DEVICE, AudioDeviceInfo.TYPE_BLE_SPEAKER -> R.drawable.ic_hifispeaker
        else -> R.drawable.ic_route_headphones
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
            return false.also { log("cam_denied — the call goes on with sound"); cameraGate() }
        val f = CallEngine.factory ?: return false
        val egl = CallEngine.egl ?: return false
        return runCatching {
            val en = Camera2Enumerator(Book.ctx)
            // THE BACK CAMERA IS NEVER THE MACHINE'S CHOICE (iOS MontanaCall 1340-1343, the author's word 22.09: an iPhone showed its
            // room to the caller): the side the person chose, or no picture at all — the other camera is the flip mark's tap alone
            val name = en.deviceNames.firstOrNull { en.isFrontFacing(it) == front } ?: return false.also { log("camera: none on the chosen side — the call goes on with sound") }
            val gen = ++l.camGen
            val cam = en.createCapturer(name, cameraEvents(l, gen)) ?: return false
            val src = f.createVideoSource(false)
            val helper = SurfaceTextureHelper.create("mt_camera", egl.eglBaseContext)
            // THE MASK'S DOOR STANDS BETWEEN THE CAMERA AND THE SOURCE (iOS FrameCountingCapturerDelegate, MontanaCall.swift
            // 7221-7224, atom c98a92d589e3): while the mask is on, the camera's frame is read on this phone and never reaches the source
            cam.initialize(helper, Book.ctx, AvatarMask.Door(src.capturerObserver))
            cam.startCapture(1280, 720, 30)
            val track = f.createVideoTrack("mt_video", src)
            track.addSink(own)
            l.cam = cam; l.helper = helper; l.vsource = src; l.vtrack = track
            log("cam_start auth=authorized front=" + front)   // the start names the system's answer (iOS cam_start auth=, atom 6ebef1dc1ca8)
            true
        }.getOrElse { log("camera: " + it.message); false }
    }

    /**
     * THE ACCESS GATE LIVES INSIDE THE ONE CAPTURE ROAD (iOS ensureCameraAccess 1581-1601, atom 6ebef1dc1ca8): every start --
     * the dial, the answer, a mid-call upgrade, an accepted ask, «Turn on» -- passes the system's answer. Undecided: the one
     * system question, and a «yes» brings the camera into the call at once; refused for good: the refusal is said to the face
     * once a call (iOS cameraDeniedTold), the call goes on with sound.
     */
    @Volatile private var cameraTold = false
    private fun cameraGate() = MainThread.post {
        val act = CallScreen.front ?: return@post
        // iOS's two answers: undecided (never asked) -- the system's question; decided -- the refusal said to the face
        if (!Prefs.bool(CAM_ASKED, false)) {
            Prefs.setBool(CAM_ASKED, true)
            log("cam_ask system prompt")
            act.askCamera { ok ->
                log("cam_ask answer=" + (if (ok) "granted" else "denied"))
                if (ok) work.execute { synchronized(gate) { line }?.let { if (video || asking || it.armedAt != 0L) enableMine(it) } }
                else if (!cameraTold) { cameraTold = true; CallScreen.tellCameraOff() }
            }
        } else if (!cameraTold) { cameraTold = true; CallScreen.tellCameraOff() }
    }
    const val CAM_ASKED = "camAskedCall"   // the system's camera question was put for a call once: «undecided» is over

    private fun cameraOff(l: Line) {
        l.camGen++   // voids a camera fault still arriving for the capturer cleared below (iOS resumeGen, 24.09)
        val cam = l.cam; val helper = l.helper; val src = l.vsource; val track = l.vtrack
        l.cam = null; l.helper = null; l.vsource = null; l.vtrack = null
        runCatching { cam?.stopCapture() }
        runCatching { cam?.dispose() }
        runCatching { helper?.dispose() }
        runCatching { track?.removeSink(own); track?.dispose() }
        runCatching { src?.dispose() }
    }

    /**
     * THE CAMERA'S OWN FAULT IS RAISED AT ONCE (iOS AVCaptureSessionRuntimeError, MontanaCall.swift 24.09, build 51552a7b8d64:
     * -11819 mediaServicesWereReset came with an interruption's end, and the picture returned only after a timed resume probe
     * had judged silence — two seconds of cover for the peer the fix removed by raising the session the instant the fault is
     * told, never waiting for a probe). Android's capturer carries no such probe to begin with: raising at once, here, is the
     * whole of the fix. A fault off a capturer this line has already left (switchCamera's own instance aside, cameraOff, the
     * share) is silent — the generation it was born under no longer matches (iOS resumeGen).
     */
    private fun cameraEvents(l: Line, gen: Int) = object : CameraVideoCapturer.CameraEventsHandler {
        override fun onCameraError(error: String) = cameraReset(l, gen, "error: " + error)
        override fun onCameraDisconnected() = cameraReset(l, gen, "disconnected")
        override fun onCameraFreezed(error: String) {}
        override fun onCameraOpening(name: String) {}
        override fun onFirstFrameAvailable() { if (selfPaused) { selfPaused = false; log("cam_ok first frame -- my picture is back"); moved() } }
        override fun onCameraClosed() {}
    }

    private fun cameraReset(l: Line, gen: Int, why: String) = work.execute {
        if (synchronized(gate) { line !== l } || l.camGen != gen || l.vtrack == null) return@execute
        log("cam_reset " + why + " — raising at once")
        if (!selfPaused) { selfPaused = true; moved() }   // until the raised camera's first frame (iOS noteSelfPicture 1468)
        val cam = l.cam
        l.cam = null
        runCatching { cam?.stopCapture() }
        runCatching { cam?.dispose() }
        startCam(l)
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

    // THE LADDER'S STEPS (iOS videoLadder 3458, modestStep 3849): six steps from 2 Mbit/s down to none; a call starts on the
    // modest one, 700 kbit/s, and the top opens only for a pair proven direct (raiseVideoCeiling)
    private val LADDER = intArrayOf(2_000_000, 1_200_000, 700_000, 400_000, 250_000, 0)
    private const val MODEST = 2

    /** iOS ladderFloor 3851: the step the picture may not rise above -- the power's floor and the path's, the higher of them. */
    private fun floorOf(l: Line) = maxOf(powerFloorNow, l.pathFloor)

    /** iOS boostVideo 3826-3839: every offer and answer writes the step the ladder stands on, never a top it has left. */
    private fun bound(l: Line) = ceiling(l, LADDER[maxOf(l.ladderStep, floorOf(l))])

    /**
     * THE ONE PLACE A VIDEO CEILING IS SET (iOS setVideoCeiling 3792-3824). Zero is the bottom step: the encoding goes quiet,
     * the track and its owners (the hold, the share) are untouched. At least half the ceiling, never more than 300 kbit/s.
     * UNDER THE POWER FLOOR the encoder's work falls fourfold (iOS 3816-3819): a camera at half its resolution and fifteen
     * frames a second; a shared screen keeps its pixels and slows to eight -- letters stay letters.
     */
    private fun ceiling(l: Line, bps: Int) {
        runCatching {
            val s = l.pc.transceivers.firstOrNull { it.mediaType == MediaStreamTrack.MediaType.MEDIA_TYPE_VIDEO }?.sender ?: return
            val p = s.parameters
            val floor = powerFloorNow
            p.encodings.firstOrNull()?.let {
                it.active = bps > 0
                if (bps > 0) {
                    it.maxBitrateBps = bps; it.minBitrateBps = minOf(300_000, bps / 2)
                    it.scaleResolutionDownBy = if (floor > 0 && !sharing) 2.0 else 1.0
                    it.maxFramerate = if (floor > 0) (if (sharing) 8 else 15) else null
                }
            }
            // a shared screen keeps its letters sharp and gives up motion; a camera the reverse (iOS 3804-3809, 3822)
            p.degradationPreference = if (sharing) RtpParameters.DegradationPreference.MAINTAIN_RESOLUTION else RtpParameters.DegradationPreference.MAINTAIN_FRAMERATE
            s.setParameters(p)
        }.onFailure { log("ceiling: " + it.message) }
    }

    /**
     * THE POWER FACTS (iOS MontanaPower.swift 12-29, atom 41d0cac99d59): the battery, the charger, Low Power Mode and the
     * thermal state, one reading. Its floor: 2 (700 kbit/s, half resolution, 15 fps) under Low Power Mode, a serious thermal
     * state, or a battery at 15 % or less off the charger; 4 (250 kbit/s) under a critical thermal state. Android's thermal
     * scale is finer than iOS's four words: LIGHT and MODERATE read «fair», SEVERE «serious», CRITICAL and above «critical».
     */
    private class Power(val level: Int, val charging: Boolean, val lowPower: Boolean, val thermal: String) {
        val floor = if (thermal == "critical") 4 else if (lowPower || thermal == "serious" || (!charging && level in 0..15)) 2 else 0
        val word = "batt=" + level + " chg=" + (if (charging) 1 else 0) + " lowpower=" + (if (lowPower) 1 else 0) + " thermal=" + thermal
    }
    private fun power(): Power {
        val bm = Book.ctx.getSystemService(BatteryManager::class.java)
        val pm = Book.ctx.getSystemService(PowerManager::class.java)
        val t = if (Build.VERSION.SDK_INT >= 29) (pm?.currentThermalStatus ?: PowerManager.THERMAL_STATUS_NONE) else PowerManager.THERMAL_STATUS_NONE
        val thermal = when {
            t >= PowerManager.THERMAL_STATUS_CRITICAL -> "critical"
            t == PowerManager.THERMAL_STATUS_SEVERE -> "serious"
            t >= PowerManager.THERMAL_STATUS_LIGHT -> "fair"
            else -> "nominal"
        }
        return Power(bm?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: -1, bm?.isCharging == true, pm?.isPowerSaveMode == true, thermal)
    }

    /**
     * THE LADDER (iOS applyLadder 3725-3790): one sample moves it. The power facts first -- a floor that moves re-applies the
     * ceiling the instant it moves and the call's light wears the battery (nothing about saving is written on the screen,
     * the author's word 11.09 at 3742). Then the network: a squeeze is a fact of two witnesses of three (the encoder held by
     * bandwidth, more than eight video packets lost, a round trip past 400 ms) and steps down after eight seconds; one
     * witness holds the step; a clean channel climbs back only after three good samples and twelve seconds, never above the floor.
     */
    private fun applyLadder(l: Line, limit: String, lostDelta: Long, rttMs: Int) {
        if (!video || l.connectedAt == 0L || lost) return   // iOS guard isVideo, state == "connected"
        val now = System.currentTimeMillis()
        val pw = power()
        l.sum.battLast = pw.level; l.sum.charging = pw.charging; l.sum.thermal = pw.thermal
        l.powerTicks++
        if (l.powerTicks % 12 == 1) log("call_power " + pw.word + " floor=" + pw.floor + " step=" + l.ladderStep)
        if (pw.floor != powerFloorNow) {
            powerFloorNow = pw.floor
            l.sum.powerFloorMax = maxOf(l.sum.powerFloorMax, pw.floor)
            log("call_power floor " + pw.floor + " — " + pw.word)
            if (l.ladderStep < floorOf(l)) {
                l.ladderStep = floorOf(l); l.ladderMovedAt = now; l.ladderGoodTicks = 0
                l.sum.ladderMin = maxOf(l.sum.ladderMin, l.ladderStep)
            }
            ceiling(l, LADDER[l.ladderStep])   // re-applied: the floor changes the encoder's shape too
            val saving = pw.floor > 0
            if (powerSaving != saving) { powerSaving = saving; moved() }
        }
        val witnesses = (if (limit == "bandwidth") 1 else 0) + (if (lostDelta > 8) 1 else 0) + (if (rttMs > 400) 1 else 0)
        val squeezed = witnesses >= 2
        // the traffic light: the top step is the floor's -- a pair not proven direct stands at its modest top and is green there
        val light = if (squeezed) 0 else if (l.ladderStep > floorOf(l)) 1 else 2
        if (signal != light) { signal = light; moved() }
        val since = now - l.ladderMovedAt
        if (squeezed) {
            l.ladderGoodTicks = 0
            if (since <= 8_000 || l.ladderStep >= LADDER.size - 1) return
            l.ladderStep++
            l.sum.ladderMin = maxOf(l.sum.ladderMin, l.ladderStep)
            l.ladderMovedAt = now
            ceiling(l, LADDER[l.ladderStep])
            log("call_ladder down step=" + l.ladderStep + " cap_kbps=" + LADDER[l.ladderStep] / 1000 + " limit=" + limit + " lost=" + lostDelta + " rtt=" + rttMs)
        } else if (lostDelta > 8 || rttMs > 400) {
            l.ladderGoodTicks = 0   // ONE NETWORK WITNESS HOLDS THE STEP (iOS 3768-3777): neither a squeeze nor a clean channel
        } else {
            l.ladderGoodTicks++
            if (l.ladderGoodTicks < 3 || since <= 12_000 || l.ladderStep <= floorOf(l)) return
            l.ladderStep--
            l.ladderMovedAt = now
            l.ladderGoodTicks = 0
            ceiling(l, LADDER[l.ladderStep])
            log("call_ladder up step=" + l.ladderStep + " cap_kbps=" + LADDER[l.ladderStep] / 1000 + " rtt=" + rttMs)
        }
    }

    /**
     * THE PATH'S PROOF (iOS raiseVideoCeiling 4097-4142): five seconds after the connect the nominated pair is read -- direct
     * over UDP on the phone's own radio or Wi-Fi opens the top step; a relay, TCP or a tunnel (the engine names the adapter a
     * VPN; iOS ridesTunnel 4144-4160) keeps the modest one. The proof moves the path's floor both ways: a pair re-formed after a
     * restart does not keep the top the old pair earned. The battery glyph is left to the power floor alone -- the iPhone
     * clears it here (4130) while the floor may still hold the picture down; a light must say what it names.
     */
    private fun raiseVideoCeiling(l: Line) {
        if (!video) return
        MainThread.later(5000) { work.execute {   // the line's own queue: the connection is never read while it is being closed
            if (synchronized(gate) { line !== l } || lost) return@execute
            runCatching { l.pc.getStats { r -> work.execute {
                if (synchronized(gate) { line !== l } || lost) return@execute
                val direct = HashSet<String>(); val tunnel = HashSet<String>()
                for (x in r.statsMap.values) if (x.type == "local-candidate") {
                    if (x.members["networkType"] == "vpn") { tunnel.add(x.id); continue }
                    if (x.members["candidateType"] != "relay" && (x.members["protocol"] as? String)?.lowercase() == "udp") direct.add(x.id)
                }
                val nominated = r.statsMap.values.filter { it.type == "candidate-pair" && it.members["state"] == "succeeded" && it.members["nominated"] == true }
                    .mapNotNull { it.members["localCandidateId"] as? String }
                val isDirect = nominated.any { it in direct }
                l.pathFloor = if (isDirect) 0 else MODEST
                if (isDirect) {
                    l.ladderStep = floorOf(l); l.ladderMovedAt = System.currentTimeMillis(); l.ladderGoodTicks = 0
                    ceiling(l, LADDER[l.ladderStep])
                    if (signal != 2) { signal = 2; moved() }
                    log("video: ceiling raised -- the pair is direct over UDP")
                } else {
                    if (l.ladderStep < floorOf(l)) { l.ladderStep = floorOf(l); l.ladderMovedAt = System.currentTimeMillis(); l.ladderGoodTicks = 0 }
                    ceiling(l, LADDER[l.ladderStep])
                    val why = if (nominated.any { it in tunnel }) "the pair rides a tunnel" else if (nominated.isEmpty()) "no pair nominated yet" else "the pair goes through a relay or over TCP"
                    log("video: ceiling held modest (" + LADDER[l.ladderStep] / 1000 + " kbps) -- " + why)
                }
            } } }
        } }
    }

    // ═══ THE MEASURE (iOS measureStreams 3915-3918, measureTick 3919-4095): one sample every two seconds while the call
    // stands connected or broken -- the path's witness of a break, the peer's picture, the summary, the journal, the ladder ═══

    private fun measure(l: Line, gen: Int) {
        if (synchronized(gate) { line !== l } || gen != l.measureGen) { l.measuring = false; return }
        // the next tick is armed BEFORE the request (iOS 3926-3929): one swallowed reply never kills the measurement
        MainThread.later(2000) { work.execute { measure(l, gen) } }
        runCatching { l.pc.getStats { r -> work.execute { sample(l, gen, r) } } }
    }

    private fun n(v: Any?): Long = (v as? Number)?.toLong() ?: 0L
    private fun ms(v: Any?): Int = ((v as? Number)?.toDouble()?.times(1000))?.toInt() ?: -1

    private fun sample(l: Line, gen: Int, r: RTCStatsReport) {
        if (synchronized(gate) { line !== l } || gen != l.measureGen) return
        var pair = "?"; var rttMs = -1; var kind = "?"; var net = "?"; var tun = 0
        var aBytes = 0L; var aLost = 0L; var aJit = -1
        var vBytes = 0L; var vLost = 0L; var vW = 0L; var vH = 0L; var vFps = 0L
        var outBytes = 0L; var outFrames = 0L; var outLimit = "-"; var outAudio = 0L
        val pictureNow = HashMap<String, Long>()
        // THE PATH IS THE NOMINATED PAIR'S, and its own word is the bytes that reached us on each pair -- the peer's media and
        // its reports on ours; connectivity checks are not in this count, so a relay's keepalive cannot pose as the peer
        val pathNow = HashMap<String, Long>()
        var nominatedLocal: String? = null
        val all = r.statsMap.values
        for (x in all) if (x.type == "candidate-pair") {
            if (x.members["nominated"] == true && x.members["state"] == "succeeded") nominatedLocal = x.members["localCandidateId"] as? String
            pathNow[x.id] = n(x.members["bytesReceived"])
        }
        for (x in all) {
            val m = x.members
            val media = (m["mediaType"] ?: m["kind"]) as? String ?: ""
            when (x.type) {
                "candidate-pair" -> if (m["nominated"] == true) { rttMs = ms(m["currentRoundTripTime"]); pair = m["state"] as? String ?: "?" }
                // after a renegotiation two streams of one media can coexist, one dead: the live one -- the larger counter -- speaks
                "outbound-rtp" -> if (media == "video") {
                    val b = n(m["bytesSent"])
                    if (b >= outBytes) { outBytes = b; outFrames = n(m["framesSent"]); outLimit = m["qualityLimitationReason"] as? String ?: "-" }
                } else if (media == "audio") outAudio = maxOf(outAudio, n(m["bytesSent"]))
                "local-candidate" -> if (x.id == nominatedLocal) {
                    kind = m["candidateType"] as? String ?: "?"
                    net = m["networkType"] as? String ?: "?"
                    tun = if (net == "vpn") 1 else 0
                }
                "inbound-rtp" -> {
                    val bytes = n(m["bytesReceived"]); val lostPk = n(m["packetsLost"])
                    if (media == "audio") {
                        if (bytes >= aBytes) { aBytes = bytes; aLost = lostPk; aJit = ms(m["jitter"]) }
                    } else if (media == "video") {
                        pictureNow[x.id] = (m["framesReceived"] ?: m["framesDecoded"])?.let { n(it) } ?: bytes
                        if (bytes >= vBytes) { vBytes = bytes; vLost = lostPk; vW = n(m["frameWidth"]); vH = n(m["frameHeight"]); vFps = n(m["framesPerSecond"]) }
                    }
                }
            }
        }
        // THE FIRST RECEIVED FRAME gets its own mark (iOS 4004-4011): the instant a person calls «video started»
        if (video && vBytes > 0 && !l.firstVideoIn) {
            l.firstVideoIn = true
            if (!remoteLive) { remoteLive = true; moved() }   // a belt for a missed first frame
            log("video_first_in ms=" + (System.currentTimeMillis() - l.connectedAt) + " size=" + vW + "x" + vH + " path=" + kind)
        }
        // THE BREAK IS WITNESSED BY THE PATH, NOT BY THE PICTURE (iOS 4012-4046, atom 66882a697917): a far phone gone to the
        // background stops its camera and its voice falls silent while its reports on our stream keep arriving -- a living call.
        // A pair answers only by its own growth past its last sighting (24.09: a fresh transport drops the dead pairs, and a
        // smaller sum must not read as «the path answers»). Two silent samples, four seconds, declare the break; the first
        // answering sample ends it -- and only after the media flowed once: the opening seconds are silent by nature.
        Calls.holdOnDisk()   // the last moment the call was known alive, every five seconds (iOS measureTick 3925)
        val pathAnswered = pathNow.any { (id, b) -> b > (l.pathSeen[id] ?: 0L) }
        l.pathSeen = pathNow
        val inNow = aBytes + vBytes
        if (inNow > 0) l.everFlowed = true
        if (l.everFlowed) {
            if (pathAnswered || inNow > l.lastInBytes) {
                l.lastInBytes = maxOf(l.lastInBytes, inNow)
                l.stallSamples = 0
                if (lost) leaveBreak(l, "path answers")
            } else {
                l.stallSamples++
                if (l.stallSamples == 2 && !lost) enterBreak(l, "path silent 4s")
            }
        }
        // the summary is fed by the same sample that feeds the journal and the ladder (iOS 4047-4056); its out bytes count
        // the voice too (25.09, atom d3fcc97a4974: out_kb=0 stood on a 455-second voice call)
        val sm = l.sum
        sm.samples++
        if (kind != "?") { sm.paths.add(kind); if (kind == "relay") sm.relaySamples++ }
        if (tun == 1) sm.tunnelSamples++
        if (rttMs >= 0) { sm.rttSum += rttMs; sm.rttN++ }
        sm.inBytes = maxOf(sm.inBytes, aBytes + vBytes)
        sm.outBytes = maxOf(sm.outBytes, outBytes + outAudio)
        sm.lostVideo = maxOf(sm.lostVideo, vLost)
        // THE PEER'S PICTURE MOVED when ANY incoming video stream received a frame since the last sample (iOS 4059-4079, atom
        // b1df5c186009): after a renegotiation a dead stream keeps its larger count while the live one starts from zero
        if (video && l.firstVideoIn) {
            val movedNow = pictureNow.any { (id, f) -> f > (l.pictureSeen[id] ?: 0L) }
            for ((id, f) in pictureNow) l.pictureSeen[id] = maxOf(l.pictureSeen[id] ?: 0L, f)
            if (movedNow) { l.pictureStall = 0; notePeerPicture(false) }
            else { sm.videoDarkS += 2; l.pictureStall++; if (l.pictureStall == 2) notePeerPicture(true) }
        } else if (!video) { l.pictureStall = 0; notePeerPicture(false) }
        val now = System.currentTimeMillis()
        if (now - l.lastJournalAt < 5000) return   // the journal keeps its five-second rhythm (iOS 4080-4087)
        l.lastJournalAt = now
        val via = if (tun == 1) "tunnel" else net
        log("call_audio path=" + kind + " pair=" + pair + " rtt_ms=" + rttMs + " bytes=" + aBytes + " lost=" + aLost + " jitter_ms=" + aJit +
            " via=" + via + " out_bytes=" + outAudio + " mic=" + (if (muted || held) 0 else 1))
        if (video) {
            log("call_video path=" + kind + " rtt_ms=" + rttMs + " in_bytes=" + vBytes + " lost=" + vLost + " size=" + vW + "x" + vH + " fps=" + vFps +
                " out_bytes=" + outBytes + " out_frames=" + outFrames + " limit=" + outLimit + " via=" + via)
            // one measurement, one owner (iOS 4088-4092): the sample that speaks in the journal also moves the ladder
            val lostDelta = maxOf(0L, vLost - l.lastVideoLost)
            l.lastVideoLost = vLost
            applyLadder(l, outLimit, lostDelta, rttMs)
        }
    }

    /** The one writer of the cover over the peer's stale frame (iOS notePeerPicture 3907-3914). */
    private fun notePeerPicture(paused: Boolean) {
        if (peerPaused == paused) return
        peerPaused = paused
        log("peer_picture " + (if (paused) "paused -- the cover stands" else "back -- the cover goes"))
        moved()
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
        AvatarMask.set(false, "video-end")   // no camera, no mask (iOS MontanaCall.swift 3201)
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
            val gen = ++l.camGen
            val cam = en.createCapturer(name, cameraEvents(l, gen)) ?: return
            runCatching { l.helper?.dispose() }
            val helper = SurfaceTextureHelper.create("mt_camera", egl.eglBaseContext)
            l.helper = helper
            cam.initialize(helper, Book.ctx, AvatarMask.Door(src.capturerObserver))   // the mask's door, as at the camera's birth
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
                // A FRESH TRANSPORT AFTER ONE ASK THAT DID NOT FORM (iOS scheduleIceRestart 5153-5162, 29.09): once the first ask
                // has had its settle, the caller of a peer that rebuilds builds a new connection in place by the rejoin road; the
                // callee keeps its asks and answers the rebuild as it answers a run that came back
                if (l.caller && peerRebuilds && 1 <= l.iceRestarts && !l.rebuiltInPlace && RESTART_SETTLE_MS <= System.currentTimeMillis() - l.restartAskedAt) {
                    rebuildInPlace(l, "ask n=" + l.iceRestarts + " did not form in " + RESTART_SETTLE_MS / 1000 + "s")
                    return@execute
                }
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
        l.sum.restarts++   // iOS sendIceRestartOffer 5183: the summary counts the fresh checks asked
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

/**
 * THE PROXIMITY SENSOR HAS ONE OWNER (iOS MTProximity, MontanaCall.swift 7430-7483, atom f0da6cb01947; the author's word 24.09:
 * «during a call I covered it with a finger and took the finger away, and the screen stayed off, black and dead»). The screen's
 * sensor switch is one for the whole phone, and every hand -- «call», «voice» -- holds and lets go of it here by its name; it
 * stands on while any hand holds it. NEVER OFF WHILE «NEAR» (the reference's rule): with no hand left and the sensor covered,
 * the switch goes off only at «far» (the platform's own RELEASE_FLAG_WAIT_FOR_NO_PROXIMITY). Every change of the sensor and of
 * the switch is a diary line (proximity): a dark screen says who held the sensor and what the sensor said last.
 */
object Proximity {
    private val holders = sortedSetOf<String>()
    private var lock: PowerManager.WakeLock? = null
    @Volatile private var near = false
    /** The sensor's word now, as iOS reads UIDevice.proximityState; meaningful while a hand holds the sensor. */
    val isNear: Boolean get() = near
    /** Who hears the sensor change (iOS UIDevice.proximityStateDidChangeNotification): the reply at the ear, on the main thread. */
    var onChange: ((Boolean) -> Unit)? = null
    private val ear = object : android.hardware.SensorEventListener {
        override fun onSensorChanged(e: android.hardware.SensorEvent) {
            val max = e.sensor?.maximumRange ?: 5f
            val now = e.values.isNotEmpty() && e.values[0] < minOf(max, 5f)
            if (now == near) return
            near = now
            note(if (now) "near" else "far", "sensor")
            onChange?.invoke(now)
            if (!now && holders.isEmpty()) stopListening()
        }
        override fun onAccuracyChanged(s: android.hardware.Sensor?, a: Int) {}
    }
    private var listening = false

    /** A hand holds the sensor (true) or lets it go (false); from any thread. */
    fun hold(who: String, on: Boolean) {
        if (android.os.Looper.myLooper() != android.os.Looper.getMainLooper()) { MainThread.post { hold(who, on) }; return }
        if (on == holders.contains(who)) return   // this hand already stands so
        if (on) holders.add(who) else holders.remove(who)
        val pm = Book.ctx.getSystemService(PowerManager::class.java)
        if (holders.isNotEmpty()) {
            if (lock?.isHeld == true) return note("hold", who)
            if (pm?.isWakeLockLevelSupported(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK) != true) return note("absent", who)   // the phone has no sensor
            lock = pm.newWakeLock(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK, "montana:ear").apply { setReferenceCounted(false); acquire() }
            listen()
            note("on", who)
        } else {
            val l = lock ?: return
            lock = null
            if (l.isHeld) runCatching { l.release(PowerManager.RELEASE_FLAG_WAIT_FOR_NO_PROXIMITY) }
            note(if (near) "off-at-far" else "off", who)   // covered: the switch goes off when the sensor says «far»
            if (!near) stopListening()
        }
    }
    private fun listen() {
        if (listening) return
        val sm = Book.ctx.getSystemService(android.hardware.SensorManager::class.java) ?: return
        val s = sm.getDefaultSensor(android.hardware.Sensor.TYPE_PROXIMITY) ?: return
        listening = sm.registerListener(ear, s, android.hardware.SensorManager.SENSOR_DELAY_UI)
    }
    private fun stopListening() {
        if (!listening) return
        listening = false
        Book.ctx.getSystemService(android.hardware.SensorManager::class.java)?.unregisterListener(ear)
    }
    private fun note(what: String, why: String) { Log.d("Montana", "proximity " + what + " by=" + why + " holders=" + holders.joinToString(",")) }
}
