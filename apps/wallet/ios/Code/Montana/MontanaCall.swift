//  MontanaCall.swift — native calls (WebRTC + CallKit) over the mesh.
//  Signaling travels E2E over the ratchet (PQ authentication of the DTLS fingerprint); media — DTLS-SRTP.
//  Post-quantum layer: SFrame (RTCFrameCryptor AES-GCM-256) with sframe_key from call_seed —
//  the key delivered over the ratchet, frames encrypted on top of SRTP. Premium iOS↔iOS: .voiceChat AEC.
//
//  [I-16] A-4 — admission, not security. The media transport of this file is WebRTC, and its
//  handshake is classical by the standard it implements: the key agreement of DTLS is not
//  post-quantum and is not ours to choose. What stands on it is bounded on purpose:
//    · identity, signalling and the call key are ML-DSA-65 / ML-KEM-768 over the ratchet;
//    · the fingerprint of the transport is authenticated by that post-quantum channel, so a
//      break of the classical layer yields interference — a dropped or refused call — and not
//      a readable one, once SFrame carries the media;
//    · SFrame is the layer that makes this true, and it is OFF at this line (see myCaps).
//  While it is off, the confidentiality of media rests on the classical layer alone. Turning
//  it on is verified on two phones, not reasoned about: one-sided enabling gave mutual
//  silence once already. That verification belongs to 0.9, and this comment is its debt note.

import Foundation
import UserNotifications
import Network
import WebRTC
import CallKit
import ReplayKit
import AVKit
import AVFoundation
import Intents
import UIKit
import SwiftUI
import UserNotifications
import Combine

// Signaling types CallSDP/CallICE/CallCaps — in E2ECore.swift (compiled into the NSE too).

struct CallSignalOut {
    var ctrl: String          // "call" | "call-answer" | "call-ice" | "call-end" | "call-ringing" | "call-key"
    var sdp: CallSDP?
    var candidate: CallICE?
    var candidates: [CallICE]?   // batch (no.5): a bunch of candidates in one message
    var video: Bool?
    var caps: CallCaps?
    var callSeed: String?
    var targetDevice: String?   // addressed delivery to a known peer device
    // The epoch of the call this signal belongs to. The sender used to stamp every signal
    // with the CURRENT call's epoch, so a decline of the second line and the farewell of a
    // parked call died as STALE at the receiver (critic K-2). Empty = the current call.
    var epoch: String?
    // call-restart only: "ice" — the network broke, "media" — video/screen renegotiation.
    // Consent must not fire on an ICE restart (critic K-6); absent = an old build, read as media.
    // «call» only: "rejoin" -- the run that came back into the call it held (24.09).
    var reason: String?
    // The node's lane only, never the pipe (24.09): the lane names the call by its epoch on every build, so a device
    // that does not hold the call buries the word; the pipe of an older build would take a «call» word as a birth.
    var nodeOnly = false
}

/// What the SYSTEM sees instead of the conversation link.
///
/// The iPhone Recents list keeps a handle outside our world: it lands in the system call
/// journal, enters the backup and, with journal sync on, leaves for the cloud.
/// The conversation link does not belong there at all: it is derived from the shared secret
/// of two people, is IDENTICAL on both their devices, and ties every call to one person into
/// a single trail of who-with-whom-when-how-often. Next to its derivation stands "never leaves
/// the device" -- through the handset it did leave.
///
/// What goes out is a one-time token: sixteen random bytes per call. It is derived from
/// nothing, means nothing anywhere but this device, and two calls to one person get different
/// tokens -- there is nothing left to link. The reverse mapping lives in the local encrypted
/// vault and is bounded, so that "call back" from Recents works and memory stays finite.
enum MontanaCallHandle {
    private static let key = "callHandleTokens"
    // BOUND-OK: as many entries as Recents itself keeps. A smaller bound would silently kill
    // the call-back button on an old entry; the value is local and encrypted, and holds nothing
    // new about the person -- the conversation already sits in the chat list.
    private static let cap = 256

    private static func rows() -> [[String]] {
        guard let d = MontanaLocalVault.getDecrypted(key),
              let m = try? JSONDecoder().decode([[String]].self, from: d) else { return [] }
        return m
    }

    /// The token for THIS call. Every call gets a new one: repetition is exactly what links.
    static func token(for conv: String) -> String {
        let tok = montanaRandom(16).map { String(format: "%02x", $0) }.joined()
        var m = rows()
        m.insert([tok, conv], at: 0)
        if m.count > cap { m.removeSubrange(cap..<m.count) }
        if let d = try? JSONEncoder().encode(m) { MontanaLocalVault.setEncrypted(key, d) }
        return tok
    }

    /// The way back for "call back". An unknown value returns as is: Recents entries written by
    /// earlier builds carry the link itself, and calling back from them keeps working -- we
    /// cannot erase somebody else's journal after the fact anyway.
    static func conv(for token: String) -> String {
        rows().first { $0.count == 2 && $0[0] == token }?[1] ?? token
    }
}

final class MontanaCall: NSObject {
    static let shared = MontanaCall()

    var sendSignal: ((_ peer: String, _ signal: CallSignalOut) -> Void)?
    var displayNameFor: ((String) -> String)?
    /// The name from the call ENVELOPE -- available before any store (cold voip start):
    /// the screen and CallKit take it first, the book catches up on the warm path.
    private var presetNames: [String: String] = [:]
    func presetPeerName(_ peer: String, _ name: String) {
        var t = name.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("@") { t.removeFirst() }
        t = MontanaAvatar.spokenName(t)
        guard !t.isEmpty else { return }
        let changed = presetNames[peer] != t
        presetNames[peer] = t
        // The name arrived AFTER the call began -- the native handset must learn exactly what
        // the person sees in the app. One stamp, both directions.
        if changed, peer == self.peer, let u = callUUID {
            stampNativeName(peer: peer, uuid: u, video: isVideo)
        }
    }

    /// The ONE place where the native handset learns the peer's name ([C-1]).
    ///
    /// An incoming call stamps the name in the same call that creates it, and so was correct.
    /// An outgoing call must NOT be stamped at the moment of the tap: the request goes to the
    /// system asynchronously, the call does not exist yet, and the update is lost silently --
    /// Recents kept digits. The stamp goes where the call exists, and repeats when a name arrives late.
    func stampNativeName(peer: String, uuid: UUID, video: Bool) {
        if nativeHandle.isEmpty { nativeHandle = MontanaCallHandle.token(for: peer) }
        let upd = CXCallUpdate()
        upd.remoteHandle = CXHandle(type: .generic, value: nativeHandle)   // the one-time token -- Recents call back by it
        upd.localizedCallerName = callerName(peer)
        upd.hasVideo = video
        provider.reportCall(with: uuid, updated: upd)
    }
    /// ONE answer to "what is the caller called" ([C-1]): book -> envelope -> neutral word.
    /// MY RECORD FIRST (the author's word 18.09): the book carries a rename, the contact card, then
    /// the name the peer declared; the envelope's own word names a stranger only. It stood first
    /// here and was never let go, so the call screen, Recents and the missed banner wore the
    /// caller's word over my record for the life of the process.
    func callerName(_ peer: String) -> String {
        if peer == "Montana" { return "Montana" }   // the mandatory report of a push whose envelope did not open: the app's own name
        // WHO NAMED THEM decides (the author's word 18.09): named by me — my word; named by
        // themselves — the envelope of THIS call is their freshest word, the book its echo.
        if let n = MTNameBook.mine(peer) { return MontanaAvatar.spokenName(n) }
        if let n = presetNames[peer], !n.isEmpty { return n }
        if let n = displayNameFor?(peer), !n.isEmpty, n != MontanaConv.short(peer) { return n }
        // Digits are never a person's name: the native call screen, Recents and banners show
        // the neutral word until the peer's name arrives over the channel.
        return String(localized: "Correspondent", bundle: MTLanguage.bundle)
    }
    var onStateChange: ((_ state: String, _ peer: String?) -> Void)?
    var ringReach: ((_ peer: String, _ video: Bool, _ offerSdp: String?, _ callSeed: String?) async -> (rung: Int, online: Bool, nobody: Bool))?
    /// 15.7 — every call word of the peer is proof of presence; the store stamps «seen» through it.
    var onPeerWord: ((_ peer: String) -> Void)?
    /// `rang` — the far phone said «ringing» during this call. It decides whether a miss of MINE
    /// needs a loud word on their screen: a phone that rang has already told its person and written
    /// its own row (13.09, the author's three notifications for one call).
    var onCallLog: ((_ peer: String, _ video: Bool, _ incoming: Bool, _ durationSec: Int, _ missed: Bool, _ declined: Bool, _ seed: String?, _ rang: Bool, _ refused: Bool) -> Void)?
    /// THE ONE DOOR FOR A CALLER'S NAME AND FACE (12.09, the author's word «by SSOT»): a call word
    /// — wake, ring letter or signal — carries the caller's name, and the book learns it HERE,
    /// in the branch that ACCEPTS the word as an incoming call, never at the doors. A word this
    /// machine refuses (its own echo, a dead seed, a duplicate, a stale offer, glare it holds
    /// course through) names nobody: build 1480's echo wrote the caller's own name onto the
    /// callee through three doors at once.
    var onCallerNamed: ((_ peer: String, _ name: String?, _ glyph: String?) -> Void)?
    private func adoptCallerName(_ peer: String, _ name: String?, _ glyph: String?) {
        if let n = name, !n.isEmpty, n.count <= 64 { presetPeerName(peer, n) }
        onCallerNamed?(peer, name, glyph)
    }

    /// One factory and one audio module for every call of this app: a group's room (MTGroupRoom) speaks through it too, so two
    /// audio modules never fight over the one microphone.
    let factory: RTCPeerConnectionFactory
    private var pc: RTCPeerConnection?
    private var localAudio: RTCAudioTrack?
    private var localVideo: RTCVideoTrack?
    // The capturer mirrors its birth into the model ([C-1], same construction as isVideo): every
    // birth or replacement bumps the tick, and the model decides the call's sides afresh
    // (CallUIModel.applySides) — hand-placed pushes covered only some of the five birth sites
    // (the author's fourth strike 29.08). No view pulls the capture session: the pictures are
    // WebRTC tracks, and the session has one owner, the camera's queue (23.09).
    private var capturer: MontanaCamera? {
        didSet { DispatchQueue.main.async { CallUIModel.shared.tick += 1 } }
    }
    private(set) var remoteVideoTrack: RTCVideoTrack?
    var localVideoTrack: RTCVideoTrack? { localVideo }

    private var peer: String?
    private var peerDevice: String?
    /// This call's token -- the only thing the system sees instead of the conversation link.
    private var nativeHandle = ""
    // THE one truth about being a video call mirrors itself into the UI model at birth
    // ([C-1]): isVideo and CallUIModel.video were two stores of one concept synced by hand
    // at nine sites, and the missed site — startCall — left the CALLER's dial screen on the
    // audio branch: no self-video while ringing, appearing only when a later path happened
    // to mirror the flag (the author's third strike 29.08). A didSet cannot be missed.
    private(set) var isVideo = false {
        didSet {
            let v = isVideo
            DispatchQueue.main.async { CallUIModel.shared.video = v }
        }
    }
    private var isInitiator = false
    private var callT0 = Date()
    private var iceGenCount = 0
    private var firstMediaLogged = false
    private var firstVideoIn = false
    private var callUUID: UUID?
    // K-1: the machine's owner is the MAIN thread. Two entrances stay off it by design —
    // the signal fast-path (answer/ICE must not wait for a busy screen) and the WebRTC
    // callbacks — and everything they touch lives under this one lock.
    private let signalLock = NSLock()
    private var pendingIce: [RTCIceCandidate] = []
    private var callSeed: Data? { didSet {
        refreshEpochSnapshot()
        // The living call stands on disk while it lives (HeldCall): the next run reads it.
        holdOnDisk(force: true)
        // The seed enters the shared notebook the moment this device knows the call: the
        // caller's «missed» letter about it is then redundant in BOTH processes ([C-1]).
        if let s = callSeed?.base64EncodedString() { MontanaMissedCall.note(s, "alive") }
    } }
    // Busy state is read WITHOUT giving birth to the call machine. Touching the machine itself
    // from a foreign thread creates it there, and birth touches the audio subsystem, the call
    // presentation and the badge -- on a foreign thread that is a crash (precedent: build 840
    // died two seconds after launch because busy state was asked of the machine from a peer-up
    // notification). The flag is set on every state change -- one source.
    static var isBusy: Bool {
        get { busyFlag || MTGroupRoom.isLive }   // a group's room holds the sound as a call does (07.10)
        set { busyFlag = newValue }
    }
    private static var busyFlag = false
    // K-1: snapshots for foreign threads (the signal poller) — the machine's fields belong
    // to the main thread; these mirrors live under their own lock.
    private static let snapLock = NSLock()
    private static var _stateSnap = "idle"
    static var stateSnapshot: String { snapLock.lock(); defer { snapLock.unlock() }; return _stateSnap }
    private static var _peerSnap: String?
    /// The correspondent of the standing call, for the presence line (15.7): a person on the line is present.
    static var peerSnapshot: String? { snapLock.lock(); defer { snapLock.unlock() }; return _peerSnap }
    /// A NATIVE RING RAISED BY THE PUSH ROAD, with no call machine behind it yet. The system
    /// screen is up and the person hears it, while `state` is still «idle» — and everything that
    /// judges «is a call happening» by the state alone goes blind exactly then (13.09: the signal
    /// lane retired nine seconds into such a ring, the caller's hang-up lay uncollected on the node
    /// and the phone rang on). The fact belongs beside the state, under the same lock.
    private static var _ringPosted = false
    static var ringPosted: Bool { snapLock.lock(); defer { snapLock.unlock() }; return _ringPosted }
    private static func noteRingPosted(_ on: Bool) { snapLock.lock(); _ringPosted = on; snapLock.unlock() }
    private static var _epochSnap: Set<String> = []
    static var epochSnapshot: Set<String> { snapLock.lock(); defer { snapLock.unlock() }; return _epochSnap }
    private func refreshEpochSnapshot() {
        let live = Set([callEpoch, secondCallEpoch, parkedCallEpoch].compactMap { $0 }.filter { !$0.isEmpty })
        Self.snapLock.lock(); Self._epochSnap = live; Self.snapLock.unlock()
    }
    private(set) var state: String = "idle" {
        didSet {
            MontanaCall.isBusy = (state != "idle")
            Self.snapLock.lock(); Self._stateSnap = state; Self._peerSnap = peer; Self.snapLock.unlock()
        }
    }
    private var connectHardTimer: Timer?
    private var reconnectTimer: Timer?
    private var restartTimer: Timer?
    // 12.7: the call machine owns its OWN route watcher (born with the call, dies in
    // cleanup — birth-point sovereignty). A system-named route change asks for fresh ICE
    // checks AT ONCE instead of waiting out the 3s disconnected diagnosis.
    private var frameSniffer: MTFirstFrameSniffer?
    private var routeMonitor: NWPathMonitor?
    private var routeKey = ""
    private var routeRestartAt = Date.distantPast
    // 12.7 dialing phase: the route changed while the call was still being set up — the ICE
    // candidates were gathered on a path that no longer exists (measured 08:11: dial on
    // Wi-Fi, flap to cellular at +18s, answer applied at +22s, checking till timeout).
    private var routeDirty = false
    private var iceRestarts = 0
    /// FRESH ASKS BEFORE THE FIRST CONNECT (29.09). The engine's «failed» is final for the pairs it holds, and a setup used
    /// to wait it out: T1 to a cellular phone, 12:38:37 MSK, «failed» at the fifteenth second with both phones holding the
    /// other's candidates, and the call stood «connecting» until the far hand ended it; the same at 17:03 the day before.
    /// One ask per verdict: the first on every road with a fresh relay pass, the second on the relay alone with the TLS
    /// door first -- the road that survives a carrier NAT, a dead UDP and a filter on the ordinary ports -- and a third
    /// verdict ends the call by rule, named, so the person hears «no path» and not silence.
    private var setupAsks = 0
    private var askedRelayOnly = false
    private static let setupAskMax = 2
    private var lastIce = "new"
    private var rebuiltInPlace = false
    /// RENEGOTIATION IS IDEMPOTENT (the author's word 10.09, measured in the day's diaries: the
    /// same restart offer arrived two and three times over the two signal roads, both sides
    /// answered each copy, and the answers landed on a closed door — «applied ok=0» in fives and
    /// eights, glare rollbacks, the first video frame after 101 s). An offer already seen is
    /// buried; an answer already seen is buried; an answer applies only while an offer is open.
    private var seenRestartOffer = ""
    private var seenRestartAnswer = ""
    /// The peer rebuilds this call in place when its run comes back (its caps said «rejoin»): it is waited for
    /// and its rejoin is answered. [P2P-COMPAT] a peer that never said it is never sent one and waits its own way.
    private var peerRebuilds = false
    /// This run went back into the call its previous process held: until the new connection stands, the call is
    /// the rejoin's -- its offer, its deadline, the system's call it reported.
    private var rejoining = false
    private var seenRejoinOffer = ""
    private var heldRejoins = 0
    /// The rejoin's own offers are on the way (its loop lives): two runs that came back meet on it -- the caller's stands.
    private var rejoinOffering = false
    /// The run that came back waits for its peer until the call's window closes -- the peer may be coming back too.
    private var rejoinUntil = Date.distantPast
    private var heldWrittenAt = Date.distantPast

    // ── THE SECOND LINE (12.2, the author's word 28.08): another person calling during a
    // live call rings as a REAL CallKit call until answered / declined / expired — never a
    // flash-dummy, never a silent busy. Answering ends the current call (swap, not hold);
    // holding with paused media is a separate later step. The live call stays sovereign:
    // none of these fields belong to it.
    private var secondUUID: UUID?
    private var secondFrom: String?
    private var secondDevice = ""
    private var secondVideo = false
    private var secondSeed: String? { didSet { refreshEpochSnapshot() } }     // base64, as it rides the signal
    private var secondOffer: CallSDP?
    private var secondTimer: Timer?
    var secondCallEpoch: String? { secondSeed.map { String($0.prefix(16)) } }

    // ── HOLD (12.3): the held call is PARKED — its connection stays alive with every
    // track muted; the singleton machine empties WITHOUT closing it and serves the other
    // call. Resume moves the context back. The peer is told honestly (call-hold /
    // call-resume — old builds bury unknown words silently).
    private struct ParkedCall {
        let pc: RTCPeerConnection?
        let peer: String
        let device: String?
        let uuid: UUID
        let seed: Data?
        let video: Bool
        let cryptors: [RTCFrameCryptor]
        let startedAt: Date?
        let connectedAt: Date?
    }
    private var parked: ParkedCall? {
        didSet {
            refreshEpochSnapshot()
            let v = parked != nil; DispatchQueue.main.async { CallUIModel.shared.hasParked = v }
        }
    }
    var parkedCallEpoch: String? { parked?.seed.map { String($0.base64EncodedString().prefix(16)) } }

    @discardableResult
    private func parkCurrent() -> Bool {
        guard parked == nil, let u = callUUID, let p = peer,
              state == "connected" || state == "active" || state == "reconnecting" else { return false }
        localAudio?.isEnabled = false
        localVideo?.isEnabled = false
        remoteVideoTrack?.isEnabled = false
        pc?.receivers.forEach { $0.track?.isEnabled = false }
        var hs = CallSignalOut(ctrl: "call-hold"); hs.targetDevice = peerDevice
        hs.epoch = callEpoch
        sendSignal?(p, hs)
        MontanaP2PTrace.mark("call_hold", "parked peer=\(String(p.prefix(10)))")
        reconnectTimer?.invalidate(); reconnectTimer = nil
        disconnectGrace?.invalidate(); disconnectGrace = nil; iceHeldForPeerWord = false; restartAskedAt = .distantPast; setupAsks = 0; askedRelayOnly = false; lastIce = "new"; rebuiltInPlace = false
        restartTimer?.invalidate(); restartTimer = nil; iceRestarts = 0
        measuring = false
        parked = ParkedCall(pc: pc, peer: p, device: peerDevice, uuid: u, seed: callSeed,
                            video: isVideo, cryptors: frameCryptors,
                            startedAt: startedAt, connectedAt: connectedAt)
        // The singleton empties WITHOUT closing the parked connection.
        pc = nil; frameCryptors = []
        localAudio = nil; localVideo = nil; remoteVideoTrack = nil
        peer = nil; peerDevice = nil; callUUID = nil; callSeed = nil
        pendingOffer = nil; pendingIce = []
        connectedAt = nil; startedAt = nil
        endSignalSent = true   // nothing may farewell the parked call through the empty fields
        softHeld = false
        measureGen += 1        // the parked call's measure loop dies at once (K-9)
        DispatchQueue.main.async { CallUIModel.shared.held = false }
        setState("idle")
        return true
    }
    private func unpark(_ pk: ParkedCall) {
        pc = pk.pc
        frameCryptors = pk.cryptors
        peer = pk.peer; peerDevice = pk.device
        callUUID = pk.uuid; callSeed = pk.seed; isVideo = pk.video
        startedAt = pk.startedAt; connectedAt = pk.connectedAt
        ended = false; endSignalSent = false; declinedByMe = false; endReason = "-"; endDoor = "-"
        softHeld = false
        pc?.receivers.forEach { $0.track?.isEnabled = true }
        for sn in pc?.senders ?? [] {
            if let a = sn.track as? RTCAudioTrack { a.isEnabled = true; localAudio = a }
            if let v = sn.track as? RTCVideoTrack { v.isEnabled = true; localVideo = v }
        }
        remoteVideoTrack = pc?.receivers.compactMap { $0.track as? RTCVideoTrack }.first
        var rs = CallSignalOut(ctrl: "call-resume"); rs.targetDevice = peerDevice
        rs.epoch = pk.seed.map { String($0.base64EncodedString().prefix(16)) }
        sendSignal?(pk.peer, rs)
        MontanaP2PTrace.mark("call_hold", "resumed peer=\(String(pk.peer.prefix(10)))")
        DispatchQueue.main.async { CallUIModel.shared.held = false }
        setState("connected")
        MontanaWakePush.startSignalPolling(pk.peer)
        DispatchQueue.main.async {
            guard !self.measuring else { return }
            self.measuring = true
            self.measureStreams()
        }
    }
    private func swapWithParked() {
        guard let other = parked else { return }
        parked = nil
        // The active call parks into the freed slot. A silent parking failure used to be
        // walked past, and unpark would overwrite a LIVE call's machine without a close or
        // a farewell (critic K-7). The guard is now symmetric: no park — no swap.
        guard parkCurrent() else {
            parked = other
            MontanaP2PTrace.mark("call_hold", "swap refused st=\(state)")
            return
        }
        unpark(other)          // the held one takes the machine
        MontanaP2PTrace.mark("call_hold", "swapped")
    }
    private func tearParked(reason: CXCallEndedReason) {
        guard let pk = parked else { return }
        parked = nil
        MontanaP2PTrace.mark("call_hold", "parked ended reason=\(reason == .remoteEnded ? "remote" : "other")")
        provider.reportCall(with: pk.uuid, endedAt: nil, reason: reason)
        pk.pc?.close()
        MontanaCall.burySeed(pk.seed?.base64EncodedString())
    }

    // A LONE hold (no second line): the call stays on the machine and on the screen —
    // only the tracks sleep. Parking a lone hold proved fatal (measured 17:03:22.401→.580:
    // the emptied machine read as "call ended" on the holder, the CallKit reconciliation
    // buried the parked context 179ms later, and the held peer hung forever). Park serves
    // the second line only.
    private var softHeld = false   // THE record the Hold button decides by (K-10): the
                                   // CallUIModel mirror lands async, and a fast double tap
                                   // used to read the stale value and hold twice.
    private func softHold(_ on: Bool) {
        guard let p = peer else { return }
        softHeld = on
        if on {
            localAudio?.isEnabled = false
            localVideo?.isEnabled = false
            remoteVideoTrack?.isEnabled = false
            pc?.receivers.forEach { $0.track?.isEnabled = false }
            var hs = CallSignalOut(ctrl: "call-hold"); hs.targetDevice = peerDevice
            sendSignal?(p, hs)
            MontanaP2PTrace.mark("call_hold", "soft-held peer=\(String(p.prefix(10)))")
        } else {
            localAudio?.isEnabled = !desiredMuted
            localVideo?.isEnabled = !CallUIModel.shared.cameraOff
            remoteVideoTrack?.isEnabled = true
            pc?.receivers.forEach { $0.track?.isEnabled = true }
            var rs = CallSignalOut(ctrl: "call-resume"); rs.targetDevice = peerDevice
            sendSignal?(p, rs)
            MontanaP2PTrace.mark("call_hold", "soft-resumed peer=\(String(p.prefix(10)))")
            DispatchQueue.main.async {
                guard !self.measuring else { return }
                self.measuring = true
                self.measureStreams()
            }
        }
        DispatchQueue.main.async { CallUIModel.shared.held = on }
    }

    func postSecondLine(from: String, video: Bool) {
        if secondFrom == from, secondUUID != nil { return }          // already ringing
        guard secondUUID == nil else { reportDummyAndEnd(from: from); return }   // a THIRD caller
        let u = UUID()
        secondUUID = u; secondFrom = from; secondVideo = video
        MontanaP2PTrace.mark("ring_posted", "second-line from=\(String(from.prefix(10))) video=\(video ? 1 : 0)")
        reportIncoming(uuid: u, from: from, video: video)
        startWaitingTone()   // the carrier's short pips: the busy ear HEARS the second line
        DispatchQueue.main.async {
            self.secondTimer?.invalidate()
            self.secondTimer = self.callTimer(45, repeats: false) { [weak self] _ in
                self?.expireSecond()
            }
        }
    }
    private func clearSecond(report reason: CXCallEndedReason?) {
        stopWaitingTone()
        secondTimer?.invalidate(); secondTimer = nil
        if let u = secondUUID, let r = reason { provider.reportCall(with: u, endedAt: nil, reason: r) }
        secondUUID = nil; secondFrom = nil; secondDevice = ""; secondVideo = false
        secondSeed = nil; secondOffer = nil
    }
    private func expireSecond() {
        guard secondUUID != nil else { return }
        MontanaP2PTrace.mark("ring_dead", "second-line expired")
        MontanaCall.burySeed(secondSeed)
        clearSecond(report: .unanswered)
    }
    private func declineSecond() {
        guard let sf = secondFrom else { return }
        var bs = CallSignalOut(ctrl: "call-end")
        bs.epoch = secondCallEpoch   // the SECOND call's epoch — the current call's would be STALE at the caller
        if !secondDevice.isEmpty { bs.targetDevice = secondDevice }
        sendSignal?(sf, bs)
        MontanaP2PTrace.mark("ring_dead", "second-line declined")
        MontanaCall.burySeed(secondSeed)
        clearSecond(report: nil)   // the CXEndCallAction removes the call itself
    }
    private func answerSecond() {
        guard let sf = secondFrom, let su = secondUUID else { return }
        let dev = secondDevice, vid = secondVideo, seed = secondSeed, offer = secondOffer
        stopWaitingTone()
        secondTimer?.invalidate(); secondTimer = nil
        secondUUID = nil; secondFrom = nil; secondDevice = ""; secondVideo = false
        secondSeed = nil; secondOffer = nil
        // Hold & Accept: the call was PARKED a breath ago — the teardown below must not
        // touch it (measured 17:03:22: cleanup honestly ended the parked call 170ms after
        // the hold word, and the held peer stormed restarts into a closed connection).
        // The parked context steps aside for the teardown and returns after it.
        let keepParked = parked
        parked = nil
        // End the live call honestly, then adopt the second as THE call (swap, not hold).
        if endReason == "-" { endReason = "swapped-to-second" }
        sendEndSignal()
        cleanup()
        parked = keepParked
        ended = false; endSignalSent = false; declinedByMe = false; answeredByMe = false; endReason = "-"; endDoor = "-"
        peer = sf; peerDevice = dev.isEmpty ? nil : dev
        isVideo = vid; isInitiator = false; pendingIce = []
        startedAt = Date(); connectedAt = nil; answeredAt = nil
        cameraDeniedTold = false
        pendingOffer = offer
        if let s = seed, let d = Data(base64Encoded: s) { callSeed = d }
        callUUID = su
        callT0 = Date(); iceGenCount = 0; firstMediaLogged = false; firstVideoIn = false
        beginBackgroundHold()
        setState("incoming")
        MontanaP2PTrace.mark("ring_posted", "second-line answered from=\(String(sf.prefix(10)))")
        MontanaWakePush.startSignalPolling(sf)
        acceptCall()
    }
    private var answerResendTimer: Timer?
    private var answerResends = 0
    private var offerResendTimer: Timer?
    private var offerResends = 0
    private var pendingOfferSdp: String?
    private var bgTask: UIBackgroundTaskIdentifier = .invalid
    private var pendingAnswerAction: CXAnswerCallAction?
    private var prewarming = false
    private var callGen = 0   // call generation: buildPC does not assign pc to a foreign generation
    private var iceOutBatch: [CallICE] = []
    /// THE CALLER'S CANDIDATES LEAVE ONLY AFTER THE PEER'S FIRST WORD (the critic 22.09). An idle
    /// receiver has no epoch: everything that reaches it before its call is born is buried as STALE
    /// by construction — and the offer is re-sent every two seconds, the candidates never. Measured
    /// 21.09 22:48:52 (iPhone 15 to T1, both on cellular, the voip wake not delivered): the offer and
    /// four batches of candidates left at +0.7…+1.5 s, the ring letter bore the call at +2.9 s, T1
    /// buried the candidates, answered for twenty seconds into the void, and the call never joined.
    /// The candidates now wait for «call-ringing» or «call-answer» — the first word that proves the
    /// call is born over there — and leave in one batch; a peer that never speaks gets them by time.
    private var iceHeldForPeerWord = false
    /// ONE OWNER OF «ASK FOR FRESH CHECKS» (the critic 22.09): the route monitor and the reconnect
    /// clock both used to send a restart offer on their own. Two phones leaving one Wi-Fi in the
    /// same second offered at once and refused each other (glare, 22:48:43); a reconnect clock
    /// asked every three seconds and aborted every transport it had just asked for (23:15:45–
    /// 23:16:00, six restarts, each answered, none given the seconds a relay needs to form, the
    /// call killed by its own deadline at 25 s). A fresh transport is asked for HERE alone: the
    /// caller at once, the callee after a lead so the caller's asks land first, and never while the
    /// previous ask is still forming — unless the machine says it failed.
    private var restartAskedAt: Date = .distantPast
    private static let restartSettleS: TimeInterval = 9      // a transport over a relay forms in seconds; asking sooner aborts it
    private static let restartCalleeLeadS: TimeInterval = 1.5
    private static let restartMax = 3                          // three fresh transports in a row failed — then the call is honestly lost
    private static let reconnectDeadlineS: TimeInterval = 30   // three asks, nine seconds each, and the verdict
    /// «disconnected» is the machine's suspicion, «failed» its verdict (the WebRTC state machine: disconnected
    /// is raised on a few missed checks and may heal by itself, failed is final). A break for the person
    /// is declared when the suspicion holds — measured 22:51:34: one and a half seconds of «reconnecting»
    /// with the voice cue over a link that healed by itself.
    private var disconnectGrace: Timer?
    private static let disconnectGraceS: TimeInterval = 2.5
    // Candidate sending does NOT hang on the main loop: under a call the main loop enters
    // tracking mode for touches and animations, while Timer.scheduledTimer lives only in the
    // default mode -- the measurement showed candidates lying idle for FOURTEEN seconds, and
    // the peer starting its path checks on the 17th second of the call.
    // ONE BIRTH OF A CALL TIMER (24.09). The class was «closed whole» by a second call after each
    // birth (keepAwake), and five births went without it -- the break's grace, the reconnect
    // deadline, the restart knocks, the second line's expiry and the video consent's: under a
    // finger on the screen the recovery of a broken call stood still until the finger lifted. A
    // call timer is born here and nowhere else, already in the common modes, whatever thread asks;
    // the layout guard refuses a Timer.scheduledTimer in this file.
    private func callTimer(_ interval: TimeInterval, repeats: Bool, _ block: @escaping (Timer) -> Void) -> Timer {
        let t = Timer(timeInterval: interval, repeats: repeats, block: block)
        RunLoop.main.add(t, forMode: .common)
        return t
    }

    private var iceBatchTimer: DispatchSourceTimer?
    private let iceQ = DispatchQueue(label: "montana.call.ice")
    private var iceFlushes = 0
    private var iceOutKinds: [String: Int] = [:]   // the batch's candidates by type, transport and family (29.09)
    private var answerFastApplied = false
    private var measuring = false
    fileprivate var audioUnitPending = false
    fileprivate var videoReady = false
    private var peerPremium = false
    /// The caller reads an ANSWER off the wake road (their `av`). Learned from the ring envelope —
    /// which arrives BEFORE any lane of ours is up — and from the caps of the lane copy.
    private(set) var peerReadsVoipAnswer = false
    private var declinedByMe = false   // user tapped Decline on the ringing call — no "missed" banner
    private var answeredByMe = false   // user tapped Accept: even if the offer never arrived, this is no «missed» (K-12)
    // One truth for "this ring went unanswered": any teardown path (call-end signal, cancel,
    // timeout, phantom-fix) reports the SAME CallKit reason — .unanswered = red missed in Phone Recents.
    private var unansweredIncoming: Bool { !isInitiator && connectedAt == nil && !declinedByMe }
    private var ended = false
    private var endSignalSent = false
    private var peerRinging = false
    // THE RING'S LEDGER (13.09, the author's word: our part is concrete, the rest is Apple's, and
    // the diary says whose): knocks made, knocks Apple accepted, the seconds of the first and
    // the last accepted one, whether every door said «nobody», whether the second bell rang.
    private var knockN = 0, knockOk = 0, knockFirstOkS = -1, knockLastOkS = -1, knockNobody = false, bellRung = false
    /// WHOSE SIDE THE MISS IS ON — one word for the diary, derived from facts only.
    private func faultSide() -> String {
        if connectedAt != nil { return "talk" }
        if !isInitiator { return answeredByMe ? "net" : "hand" }
        if answeredAt != nil { return "net" }              // the far hand answered, the road failed
        if peerRinging { return "callee" }                 // it rang there, nobody picked up
        if knockNobody { return "ours-registration" }      // every publisher: no token for them
        if knockOk > 0 { return "apple" }                  // Apple accepted a wake, no word «ringing» came
        if knockN > 0 { return "ours-road" }               // not one door took a single wake
        return "ours"
    }
    /// THE PERSON HEARS WHY (29.09): a call that found no road, or one this network's filter cannot pass, ends with a word
    /// in the person's language -- not with a screen that closes. The alert stands under the one owner of the modal stack.
    static func tellNoRoad(filtered: Bool) {
        DispatchQueue.main.async {
            let title = filtered ? String(localized: "Calls are filtered on this network", bundle: MTLanguage.bundle)
                                 : String(localized: "The call found no road", bundle: MTLanguage.bundle)
            let body = filtered
                ? String(localized: "This network passes only permitted destinations. A call cannot go through it until the filter is lifted.", bundle: MTLanguage.bundle)
                : String(localized: "The two phones could not open a path for the voice. Try again in a moment.", bundle: MTLanguage.bundle)
            let alert = UIAlertController(title: title, message: body, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: String(localized: "OK", bundle: MTLanguage.bundle), style: .default))
            MTTop.present(alert, kind: "alert")
        }
    }
    static func dropBell(_ seedB64: String) {
        let tag = MontanaMissedCall.tag(seedB64)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["bell-" + tag])
        sweepCallBanners(mids: ["bell-" + tag, "ring-" + tag])
    }
    /// A BANNER OF A CALL THIS PHONE HAS ALREADY SERVED IS TAKEN DOWN (13.09, the author's three
    /// notifications for one call). An extension cannot hide a loud push: where it means silence it
    /// hands the system an empty content, and the system shows the node's own «New message» — a
    /// banner promising a letter that does not exist. What it cannot hide, the app removes: every
    /// delivered notification whose letter name is one of this call's is swept the moment the call
    /// rings natively, connects or is written down. The name travels inside the push itself
    /// (userInfo «mid»), so a banner the extension never touched is found by it too.
    static func sweepCallBanners(mids: [String]) {
        guard !mids.isEmpty else { return }
        let want = Set(mids)
        UNUserNotificationCenter.current().getDeliveredNotifications { list in
            let ids = list.filter { n in
                if want.contains(n.request.identifier) { return true }
                if let m = n.request.content.userInfo["mid"] as? String { return want.contains(m) }
                return false
            }.map { $0.request.identifier }
            guard !ids.isEmpty else { return }
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
            MontanaP2PTrace.mark("banner_swept", "n=\(ids.count)")
        }
    }
    private(set) var unreachable = false
    private var reachTimer: Timer?
    private let speech = AVSpeechSynthesizer()

    // log/duration
    private var startedAt: Date?
    private var connectedAt: Date?
    /// A call stands connected, placed or answered: each of its seconds mints one coin on this side (MTCallMint, 07.10.2026).
    var mintsTalk: Bool { connectedAt != nil }
    /// The second of talk now (MTCallMint): the call's peer, a name of this call alone and a name of this call's second.
    var talkSecond: (peer: String, call: String, ref: String)? {
        guard let c = connectedAt, let p = peer else { return nil }
        let call = callSeed.map { MontanaHomeNode.hex($0.prefix(8)) } ?? String(Int(c.timeIntervalSince1970 * 1000))
        return (p, call, call + ":" + String(Int(Date().timeIntervalSince(c))))
    }

    // speakerphone
    private(set) var speakerOn = false
    private var desiredMuted = false

    // SFrame
    private var keyProvider: RTCFrameCryptorKeyProvider?
    private var frameCryptors: [RTCFrameCryptor] = []
    private let shareLock = NSLock()   // K-1: the frame thread reads the pair below at 30fps
    private var videoSource: RTCVideoSource?          // the live lane's source — camera or screen
    private var screenShareActive = false
    private func setVideoSource(_ v: RTCVideoSource?) { shareLock.lock(); videoSource = v; shareLock.unlock() }
    private func setShareActive(_ a: Bool) { shareLock.lock(); screenShareActive = a; shareLock.unlock(); if a { videoFramesSeen = true } }
    private var cameraWasLive = false                 // the camera returns when the share ends
    private var audioBeforeShare = false              // the video state grew FOR the share — falls with it
    private var peerShareGrewVideo = false            // same truth on the watching side
    private var videoAskTimer: Timer?                 // consent waits this long, then «no answer»
    private var videoAcceptArmed = false              // accepted: our camera joins when theirs lands
    private var videoArmedAt = Date.distantPast       // consent lives 40s — never until the call's end
    private var videoConsentFresh: Bool { videoAcceptArmed && Date().timeIntervalSince(videoArmedAt) < 40 }
    /// A picture actually flowed in this call — theirs rendered, or our camera or screen was born.
    /// The record in the chat reads THIS, not the video flag: the flag can stand on a frameless track.
    private var videoFramesSeen = false
    private lazy var screenPusher = RTCVideoCapturer()
    private var sframeWrapped: Set<ObjectIdentifier> = []


    // ringback
    private var ringback: AVAudioPlayer?
    private var tonePlayer: AVAudioPlayer?
    private var waitingTone: AVAudioPlayer?   // 12.2: carrier-style call-waiting pips over the live talk
    private var ringbackWanted = false
    private var dialTone: AVAudioPlayer?
    private var dialToneWanted = false
    private var audioActive = false
    private var captureRunning = false
    /// WHAT WE WANT. Every call starts with the front camera — outgoing and incoming alike:
    /// a person shows their face, not whatever the phone happens to point at. Only the person
    /// changes it, with the button. Intent and outcome used to live in ONE variable set from
    /// whichever device the fallback managed to open, so after a fallback to the back camera
    /// the next incoming call started with the back one — "what we got" read as "what we want".
    private var wantFrontCamera = true
    /// WHAT WE GOT. Display and telemetry only; never an input for the next start.
    private(set) var usingFrontCamera = true   // read by the self-view mirror transform
    private var cameraDeniedTold = false
    private var captureProbeUntil = Date.distantPast   // the resumed session is being probed until then — no raise meanwhile
    private var captureRetryTimer: Timer?
    private var frameCounter: FrameCountingCapturerDelegate?
    private var probeGen = 0
    private var sessionRefused = false
    /// The resume probe's generation: a raise that already answered the reset voids the probe still waiting (24.09).
    private var resumeGen = 0
    /// ONE END PER CALL (the critic 24.09): the call whose end the system already holds -- our own End action being
    /// performed, or an end already reported -- is not reported ended a second time by the teardown.
    private var endReportedUUID: UUID?
    /// The call that ended last: a system action that times out after the end says whether it was that call's.
    private var lastEndedUUID: UUID?
    private var captureObservers: [NSObjectProtocol] = []
    private var sframeAuthorized = false   // caller: on call-key-ok; callee: on receiving call-key
    private var remoteIceSeen = false

    private let provider: CXProvider
    private let callController = CXCallController()
    /// THE SYSTEM'S OWN LIST OF CALLS (23.09): what the system still holds after our machine says idle,
    /// read at the end of every call and on every change the system reports (sweepSystemCalls).
    private let callObserver = CXCallObserver()
    /// Every call this app put into the system's list, until the system itself reports it ended: the
    /// incoming births (reportIncoming, the one door) and the outgoing ones (CXStartCallAction). Owned by
    /// the main thread: the push registry, the provider and the observer all deliver there.
    private var reportedCalls = Set<UUID>()
    private var sweepPending = false

    /// THE CALL THIS DEVICE HELD WHEN ITS PROCESS DIED (the critic 24.09) -- AND THE CALL THAT OUTLIVES IT (the author's
    /// word 24.09: «not only the cause named: such breaks are not admitted by construction, in no scenario, under no system
    /// notice»). iOS ends an app whose person changes a privacy switch in Settings (iPhone 15 13:02:44 and 13:06:05), and
    /// memory and a fall end it too; the call died with the process, the far phone held a dead line, and the person came
    /// back to nothing. The living call stands on disk, sealed by the device key, from its birth to its end -- who, its
    /// seed, video or voice, which side, since when, whether the peer rebuilds a call in place, the last moment it was
    /// known alive -- and the next run finds it: the call goes on (rejoinHeldCall); a call that ended leaves nothing. Only
    /// for the lost call's epoch does this device say «call-gone» -- a second device of the same person (one seed, one twin
    /// pipe) never held it, and must not end the call its twin carries.
    struct HeldCall: Codable {
        var peer: String
        var device: String?
        var seed: String          // base64: the call's one name
        var video: Bool
        var initiator: Bool
        var startedAt: Double
        var connectedAt: Double   // 0: it never connected
        var rebuilds: Bool        // the peer rebuilds a call in place (its caps say «rejoin»)
        var alive: Double         // the last moment this process knew the call alive
        var rejoins: Int          // runs that went back into it and died before its new connection stood -- a fall inside
                                  // a rejoin cannot loop; a rejoin that stood counts nothing (24.09 23:20, T1: the third
                                  // return was refused because two rejoins that had stood were counted as falls)
    }
    static let heldKey = "mt.call.heldEpoch"   // the name the first record (the epoch alone, 1922) was kept under
    private(set) static var lostEpoch: String?
    private static var heldAtLaunch: HeldCall?
    /// A peer that rebuilds is waited for as long as a ring rings: its run comes back within it.
    static let rejoinWindowS: TimeInterval = callLifeS
    /// The run that came back waits at least this long for the peer's answer and the new connection -- and until the
    /// call's window closes, since its peer may be coming back from the same Settings too (rejoinUntil).
    static let rejoinAnswerS: TimeInterval = 20
    /// A REJOIN OF THIS EPOCH WAITS FOR ITS PERSON (24.09): the run came back while the person was still away from the
    /// screen, and «call-gone» said now would end the very call the person is about to go back into. Main thread.
    static func rejoinAwaits(_ epoch: String) -> Bool {
        guard let h = heldAtLaunch else { return false }
        return String(h.seed.prefix(16)) == epoch
    }
    private override init() {
        if let raw = MontanaLocalVault.getDecrypted(Self.heldKey), let h = try? JSONDecoder().decode(HeldCall.self, from: raw) {
            Self.lostEpoch = String(h.seed.prefix(16))
            Self.heldAtLaunch = h
            MontanaP2PTrace.mark("call_lost", "epoch=\(String(h.seed.prefix(8))) connected=\(h.connectedAt > 0 ? 1 : 0) rebuilds=\(h.rebuilds ? 1 : 0) tries=\(h.rejoins) age_s=\(Int(Date().timeIntervalSince1970 - h.alive)) — the previous run died holding it")
        } else if let e = UserDefaults.standard.string(forKey: Self.heldKey), !e.isEmpty {
            Self.lostEpoch = e   // the first record: the epoch alone
            MontanaP2PTrace.mark("call_lost", "epoch=\(String(e.prefix(8))) — the previous run died holding it")
        }
        // A held call stays on disk until this run judges it (rejoinHeldCall): a run that iOS ends again before its person
        // comes back -- a background wake while they are still in Settings -- leaves the call to the next run (24.09).
        if Self.heldAtLaunch == nil { UserDefaults.standard.removeObject(forKey: Self.heldKey) }
        RTCInitFieldTrialDictionary(["WebRTC-IceFieldTrials": "initial_select_dampening:0"])
        RTCInitializeSSL()
        let enc = RTCDefaultVideoEncoderFactory()
        let dec = RTCDefaultVideoDecoderFactory()
        factory = RTCPeerConnectionFactory(encoderFactory: enc, decoderFactory: dec)
        let cfg = CXProviderConfiguration()
        cfg.iconTemplateImageData = MontanaCall.appGlyphTemplate()   // app glyph next to the name in the native call UI
        cfg.supportsVideo = true
        cfg.maximumCallGroups = 2   // 12.2: the second line rings beside the live call
        cfg.maximumCallsPerCallGroup = 1
        cfg.supportedHandleTypes = [.generic]
        provider = CXProvider(configuration: cfg)
        super.init()
        provider.setDelegate(self, queue: nil)
        callObserver.setDelegate(self, queue: nil)
        // RTCAudioSession with CallKit — manual activation management via didActivate/didDeactivate.
        let s = RTCAudioSession.sharedInstance()
        s.useManualAudio = true
        s.isAudioEnabled = false
    }

    func cameraDeliveredFirstFrame() { bringUp(.camReady) }

    private func tlog(_ e: String) {
        let now = Date()
        let ms = Int(now.timeIntervalSince(callT0) * 1000)
        let ep = Int(now.timeIntervalSince1970 * 1000)
        let role = isInitiator ? "CER" : "CEE"
        E2E.shared.callDebug("\(role) +\(ms)ms abs=\(ep) \(e) st=\(state)")
        // THE CALL'S OWN WORDS REACH THE DIARY (the author's word 20.09). Every camera refusal —
        // input not created, format failed to start, session silent, access denied — was named
        // here and here only, and this line went to the system log nobody reads from Lauterbourg.
        // Measured on an iPad 6 (D210851C): eight camera starts over six days, zero frames, zero
        // reasons in the diary. One mirror at the one funnel ([C-1]): no branch can stay unheard.
        MontanaP2PTrace.mark("call_dbg", "\(role) +\(ms)ms \(e.replacingOccurrences(of: "|", with: "/"))")
    }
    private func iceName(_ s: RTCIceConnectionState) -> String {
        switch s {
        case .new: return "new"; case .checking: return "checking"
        case .connected: return "connected"; case .completed: return "completed"
        case .failed: return "failed"; case .disconnected: return "disconnected"
        case .closed: return "closed"; case .count: return "count"
        @unknown default: return "?"
        }
    }
    // Background assertion for the whole call: iOS puts the app to sleep during outgoing ringback
    // (CallKit activates the audio session only on answer) → main/timers/polling freeze →
    // signaling stalls for tens of seconds. The assertion keeps the app alive until cleanup.
    /// THE SCREEN DOES NOT DIM ON A VIDEO CALL -- neither for the caller nor for the callee. A
    /// dimming screen takes the app to the background, the system takes the camera, and the peer
    /// watches blackness. The system holds the screen itself; no counter of ours is needed. On a
    /// call without video the screen lives as usual: the phone is at an ear, nothing to hold.
    /// The value is re-evaluated on every change of the video flag -- an offer may declare a call
    /// a video call after it has already begun.
    private func applyScreenHold() {
        let want = isVideo && state != "idle"
        DispatchQueue.main.async {
            if UIApplication.shared.isIdleTimerDisabled != want {
                UIApplication.shared.isIdleTimerDisabled = want
                MontanaP2PTrace.mark("screen_hold", want ? "on" : "off")
            }
        }
    }

    private func beginBackgroundHold() {
        DispatchQueue.main.async {
            self.applyScreenHold()
            guard self.bgTask == .invalid else { return }
            self.bgTask = UIApplication.shared.beginBackgroundTask(withName: "mt-call") { [weak self] in
                MontanaP2PTrace.mark("bg_hold", "expired")
                self?.endBackgroundHold()
            }
            MontanaP2PTrace.mark("bg_hold", self.bgTask == .invalid ? "REFUSED" : "id=\(self.bgTask.rawValue)")
            self.tlog("bg-hold started id=\(self.bgTask.rawValue)")
        }
    }
    // HEARTBEAT FOR THE DURATION OF A BUILD. The measurement caught seven and a half seconds of
    // total silence across the whole app -- not one trace from any subsystem -- and by it a busy
    // main thread could not be told from an app put to sleep. One even beat per second answers
    // that at a glance: missed beats = the app slept.
    private var setupBeat: DispatchSourceTimer?
    private func startSetupHeartbeat() {
        setupBeat?.cancel()
        let tm = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        tm.schedule(deadline: .now() + 1, repeating: 1)
        tm.setEventHandler { [weak self] in
            guard let self, self.state != "idle" else { self?.setupBeat?.cancel(); self?.setupBeat = nil; return }
            // A call's heartbeat is a STATE, not a metronome: 112 lines for one call said «still
            // ringing» a hundred times. The line speaks when the call changes what it is doing, and
            // once every half-minute to prove the beat is still alive.
            // The age is written in half-minute steps, so the line changes when something changed —
            // the call's state, or another half-minute of it. A raw millisecond would «change» every
            // beat and defeat the gate by construction (112 lines for one call).
            let age = Int(Date().timeIntervalSince(self.startedAt ?? Date()))
            MontanaP2PTrace.markChanged("call_beat", "s=\(age / 30 * 30) state=\(self.state)")
            // The beat also measures MAIN-THREAD BUSYNESS: it posts a mark to it and watches how
            // long that takes to arrive. Silent while the thread is free, it names the number when
            // the thread is busy longer than a third of a second. That number shows what held the call.
            let sent = Date()
            DispatchQueue.main.async {
                let late = Int(Date().timeIntervalSince(sent) * 1000)
                if late > 300 { MontanaP2PTrace.mark("main_stall", "ms=\(late)") }
            }
        }
        setupBeat = tm; tm.resume()
    }
    private func endBackgroundHold() {
        setupBeat?.cancel(); setupBeat = nil
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = false   // the call ended -- the screen lives by its own timeout again
            if self.bgTask != .invalid {
                UIApplication.shared.endBackgroundTask(self.bgTask); self.bgTask = .invalid
            }
        }
    }
    private func myCaps() -> CallCaps {
        // SFrame is OFF, and while it is off media confidentiality rests on the classical layer of
        // DTLS-SRTP alone — see the [I-16] A-4 note at the head of this file. It was switched off
        // after mutual silence over a live connection: enabling was one-sided. The two-phase
        // enabling exists below (call-key / call-key-ok -> sframeAuthorized); flipping this flag
        // is a change of live call behaviour and is accepted on two phones, not blind.
        CallCaps(tier: "ios-native", ver: 1, opus_max: 64000, hw_aec: true, sframe: false, av: true, rejoin: true)
    }
    /// WHAT THE FAR BUILD CAN DO IS LEARNED FROM EVERY WORD OF THE CALL IN HAND (24.09 23:14, T3): a call born by the wake
    /// came without caps, its copies that carried them were buried as copies, and the callee never learned that its caller
    /// rebuilds -- its run, ended by iOS for a privacy switch, came back and said «call-gone» instead of going back in.
    /// A capability, once said, stands for the call; cleanup forgets it.
    private func learnPeerCaps(_ caps: CallCaps?) {
        if caps?.av == true { peerReadsVoipAnswer = true }
        if caps?.rejoin == true, !peerRebuilds {
            peerRebuilds = true
            holdOnDisk(force: true)   // the record says it at once: a run that dies now goes back into the call
        }
    }

    // ── Audio session for the call (category/mode; activation done by CallKit) ──
    private func configureAudioSession() {
        let s = RTCAudioSession.sharedInstance()
        s.lockForConfiguration()
        do {
            let cfg = RTCAudioSessionConfiguration.webRTC()
            cfg.category = AVAudioSession.Category.playAndRecord.rawValue
            // ONE MODE, THE EAR BY DEFAULT (the author's word 21.09: no loudspeaker while a video call
            // dials — only once the seconds run). The platform's videoChat mode routes to the
            // loudspeaker on its own, so the ringback of a video call blasted the room before anyone
            // answered, whatever setSpeaker intended; voiceChat routes to the receiver, and the one
            // ruler below (setSpeaker at connection) moves a video call to the loudspeaker then.
            cfg.mode = AVAudioSession.Mode.voiceChat.rawValue
            // ONE category for every call, and the speaker NEVER lives in it. Two rulers
            // used to hold the loudspeaker: the category declared it for video at dial time
            // (the ringback blasted the room, the button stayed dark), and the button only
            // steered the route on top — turning it "off" fell back into the category's
            // default, which was the speaker again. The route override in setSpeaker is the
            // ONLY ruler now; video turns it on at the moment of connection. A category that
            // never differs is also a category never rebuilt over a running camera.
            cfg.categoryOptions = [.allowBluetooth, .allowBluetoothA2DP]
            try s.setConfiguration(cfg)
        } catch { E2ELog.write("call: audio cfg err \(error)") }
        s.unlockForConfiguration()
    }

    // Video turns the loudspeaker on AT CONNECTION, not at dialing — and through the one
    // ruler, so the button lights up and can turn it off again in any scenario.
    /// THE VIDEO CALL'S LOUDSPEAKER IS DECIDED WHEN ITS SOUND IS BORN (24.09, T1 12:29:26: a repeated video call spoke
    /// into the ear). The rule read the route at the connect, and that call's sound was not active yet -- the system never
    /// activated it, the machine's own activation came 1.5 s later -- so the route was empty, «not built-in», and the rule
    /// let the call go; the sound was born at the receiver and stayed there until a hand moved it. The rule now waits for
    /// the sound: it is asked at the connect, when the audio node rises, and when the machine activates the sound itself,
    /// and it decides once per call -- a later activation never undoes a person's choice.
    private var videoSpeakerDecided = false
    private func autoSpeakerOnVideo() {
        // THE REFERENCE'S RULE: the loudspeaker is offered only when the sound stands at the ear;
        // a headset, a speaker or a car already holds it and is never taken over (measured 11:05).
        guard !videoSpeakerDecided, isVideo, state == "connected", audioActive else { return }
        videoSpeakerDecided = true
        guard !speakerOn, MontanaAudioRoute.isBuiltin else { return }
        setSpeaker(true)
    }

    /// The person's own switch of the loudspeaker (the audio button with the phone alone): it stands for the rest of the
    /// call, and the video call's rule never overrides it.
    func speakerFromUI(_ on: Bool) {
        MontanaP2PTrace.mark("touch", "speaker to=\(on ? "speaker" : "phone") state=\(state)")
        videoSpeakerDecided = true
        setSpeaker(on)
    }

    func setSpeaker(_ on: Bool) {
        speakerOn = on
        // OUTPUT SWITCH ONLY -- NEVER an audio category rebuild. Here lived the root of "video
        // turns on and goes dark every other time": at the moment a video call connected this was
        // called from the signaling thread and rebuilt the category over a RUNNING camera -- the
        // system took the camera from the caller (the callee was saved by starting its camera
        // after connect -- hence "every other time"). The rebuild also stalled the signaling
        // thread, and the call measurement died on the first tick: zero samples across six calls
        // on the caller side. The video call speaker category is declared IN ADVANCE, in
        // configureAudioSession; what remains here is turning the output.
        Self.audioQ.async {
            let s = RTCAudioSession.sharedInstance()
            s.lockForConfiguration()
            do {
                if on { MontanaAudioRoute.preferPhoneMicrophone() }   // the loudspeaker takes the phone's microphone (the reference)
                try s.overrideOutputAudioPort(on ? .speaker : .none)
            }
            catch { E2ELog.write("call: speaker route err \(error)") }
            s.unlockForConfiguration()
            // WHERE THE SOUND ACTUALLY GOES (15.28): the switch used to be logged as a wish;
            // the route the system holds after it is the fact (the author, 07.09: «I press the
            // speaker while it rings and the ringing stays in the earpiece»).
            let outs = AVAudioSession.sharedInstance().currentRoute.outputs.map { $0.portType.rawValue }.joined(separator: ",")
            MontanaP2PTrace.mark("speaker", (on ? "on" : "off") + " route=\(outs) active=\(self.audioActive ? 1 : 0) ringback=\(self.ringback?.isPlaying == true ? 1 : 0)")
        }
        DispatchQueue.main.async { CallUIModel.shared.speaker = on }
        updateProximity()
    }

    /// The relay pass lives between calls: it is temporary, but not single-use.
    private static let turnLock = NSLock()
    private static var _turnCache: (uris: [String], name: String, credential: String, stun: [String])?
    private static var _turnCachedAt = Date.distantPast
    private static var turnCache: (uris: [String], name: String, credential: String, stun: [String])? {
        get { turnLock.lock(); defer { turnLock.unlock() }; return _turnCache }
        set { turnLock.lock(); _turnCache = newValue; turnLock.unlock() }
    }
    private static var turnCachedAt: Date {
        get { turnLock.lock(); defer { turnLock.unlock() }; return _turnCachedAt }
        set { turnLock.lock(); _turnCachedAt = newValue; turnLock.unlock() }
    }

    /// The pass a wake carried (MontanaWakePush.adoptTurnPass): in hand before the ring is posted.
    static func adoptTurnPass(_ t: (uris: [String], name: String, credential: String, stun: [String])) {
        turnCache = t; turnCachedAt = Date()
    }

    private func turnRank(_ u: String) -> Int {
        // 443 first BY RANK: Swift's sort is not stable, and two equal "turns:" ranks let
        // 5349 land ahead of the DPI-proof 443 door by luck of the draw (critic K-12).
        if u.hasPrefix("turns:") { return u.contains(":443") ? 0 : 1 }
        return u.contains("transport=tcp") ? 2 : 3
    }

    func rtcConfig(relayOnly: Bool = false, freshPass: Bool = false) async -> RTCConfiguration {
        let c = RTCConfiguration()
        c.sdpSemantics = .unifiedPlan
        c.continualGatheringPolicy = .gatherContinually
        c.bundlePolicy = .maxBundle
        // Candidates come from the device itself: local interfaces and whatever the peer path
        // yields. Address discovery and traversal live in the mesh (MontanaNATTraversal), so the
        // media path is peer-to-peer end to end.
        c.iceTransportPolicy = relayOnly ? .relay : .all
        // An empty ICE list broke calls over cellular (CGNAT): host candidates do not meet
        // without STUN/TURN. STUN goes instantly, TURN credentials come from the node (we wait
        // 1.5s at most -- a call does not hang on an unreachable node, TURN catches up next call).
        // NOT ONE ADDRESS IS BAKED IN HERE. A name compiled into the client outlives the
        // machine behind it: when that machine was switched off, every call still asked it
        // for the one reflexive address it had, got nothing, and died in ICE checking. The
        // relay and its reflector are named by the NODE (and remembered from the last pass);
        // an empty list is honest and says so in the trace.
        var servers: [RTCIceServer] = []
        // THE RELAY PASS IS REMEMBERED. It is temporary by construction and good for many calls
        // in a row, yet it was requested anew for EVERY one -- a second and a half of waiting on
        // each side before building the connection, and behind that same request stood the camera,
        // which needs no pass at all. Now we take the remembered one; a fresh one is fetched in the background.
        let t0 = Date()
        // The remembered pass seeds the cache: a relaunched app is never born blind while a
        // fetch is still in flight (the pass is good for hours by construction).
        // A fresh ask after a verdict takes a fresh pass: the remembered one may be the very pass the relay refused.
        if freshPass { Self.turnCache = nil; MontanaP2PTrace.mark("turn_cred", "a fresh pass is asked for the new checks") }
        if !freshPass, Self.turnCache == nil, let kept = MontanaWakePush.rememberedTurnPass() {
            Self.turnCache = kept
            Self.turnCachedAt = .distantPast   // valid to use, stale enough to refresh behind the call
        }
        var turn = Self.turnCache
        if let t = turn, !MontanaWakePush.turnPassLive(t) {
            MontanaP2PTrace.mark("turn_cred", "expired — fetching before the call")
            Self.turnCache = nil; turn = nil
        }
        if turn == nil {
            turn = await withTaskGroup(of: (uris: [String], name: String, credential: String, stun: [String])?.self) { group -> (uris: [String], name: String, credential: String, stun: [String])? in
                group.addTask { await MontanaWakePush.fetchTurnCred() }
                group.addTask { try? await Task.sleep(nanoseconds: 4_000_000_000); return nil }   // the last resort on a cold start; the doors' probe normally fetched the pass already
                let first = await group.next() ?? nil
                group.cancelAll()
                return first
            }
            if let got = turn { Self.turnCache = got; Self.turnCachedAt = Date() }
        } else if Date().timeIntervalSince(Self.turnCachedAt) > 600 {
            Task.detached(priority: .utility) {   // refresh for the NEXT call, not this one
                if let fresh = await MontanaWakePush.fetchTurnCred() {
                    Self.turnCache = fresh; Self.turnCachedAt = Date()
                    MontanaP2PTrace.mark("turn_cred", "refreshed")
                }
            }
        }
        MontanaP2PTrace.mark("turn_cred", "ms=\(Int(Date().timeIntervalSince(t0) * 1000)) cached=\(Self.turnCache != nil ? 1 : 0) uris=\(turn?.uris.count ?? 0) stun=\(turn?.stun.count ?? 0)")
        if let t = turn {
            // NOT ONE ADDRESS OF A FAMILY THIS PHONE DOES NOT HOLD (13.09). The node now names its
            // relay by the family the phone reached it by; this is the second lock, on our side, so
            // that an answer from an older node — or a network that changed family since the pass
            // was taken — can never cost a call its twenty seconds again.
            let stun = MontanaNet.shared.reachableRelay(t.stun)
            let uris = MontanaNet.shared.reachableRelay(t.uris)
            if stun.count != t.stun.count || uris.count != t.uris.count {
                MontanaP2PTrace.mark("turn_cred", "dropped \(t.stun.count - stun.count + t.uris.count - uris.count) of a family this phone has not")
            }
            if !stun.isEmpty { servers = [RTCIceServer(urlStrings: stun)] }
            // 12.6: the TLS door first — it survives dead UDP and DPI; tcp, then udp.
            let ordered = uris.sorted { turnRank($0) < turnRank($1) }
            if !ordered.isEmpty {
                servers.append(RTCIceServer(urlStrings: ordered, username: t.name, credential: t.credential))
            }
            // 15.13 (the author's word 07.09): BOTH ROADS AT ONCE ON EVERY CONNECTION, on both
            // sides. The relay is offered first (the TLS door survives dead UDP and DPI) and the
            // direct candidates stand beside it; the checks race and the first pair that works
            // carries the call. A relay-only policy on cellular left the call with zero usable
            // candidates the minute the relay's server was out of the phone's reach (07.09 07:24).
            MontanaP2PTrace.mark("call_ice", "policy=\(relayOnly ? "relay" : "all") (\(MontanaP2PNode.shared.wifiOn ? "wifi" : "cellular"), relay first)")
        }
        // A call with no servers at all can only ever pair host endpoints — behind carrier
        // NAT that is no call. It is still attempted (a local network may carry it), but the
        // impossibility is NAMED rather than discovered a minute later by the person.
        if servers.isEmpty { MontanaP2PTrace.mark("call_ice", "NO ICE SERVERS — host-only call") }
        c.iceServers = servers
        return c
    }

    private func buildPC() async {
        let gen = callGen
        let cfg = await rtcConfig()
        // The call could be ended/changed while the connection is being built — don't revive a zombie pc
        // over cleanup and don't overwrite the pc of a new call. [critic-289: high]
        guard gen == callGen else { return }
        // THE TUNNEL IS A ROAD, NOT A NODE (the author's word 30.09: «a VPN is only a network tunnel, not a node of
        // communication; the calling nodes are ours, as before»). The call's word and its relay stay our nodes; the VPN is
        // only the pipe its packets travel. A call that left the tunnel out while the tunnel held every route of the phone
        // gathered on adapters the system let nothing out of: 30.09, T1, three calls of four stood in ICE checking until the
        // person gave up, and each connected at once after the tunnel was switched off by hand. So the call gathers on every
        // adapter, the tunnel's among them, and the checks race: the first pair that works carries it.
        // The loopback bit is set again by hand: these options are built from a blank set, and the engine's own
        // default (kDefaultNetworkIgnoreMask) leaves the loopback out.
        let opts = RTCPeerConnectionFactoryOptions()
        opts.ignoreLoopbackNetworkAdapter = true
        factory.setOptions(opts)
        MontanaP2PTrace.mark("call_ice", MontanaP2PNode.tunnelUp() ? "every adapter -- the tunnel among them" : "every adapter")
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        pc = factory.peerConnection(with: cfg, constraints: constraints, delegate: self)
        let audioConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let audioSource = factory.audioSource(with: audioConstraints)
        let track = factory.audioTrack(with: audioSource, trackId: "mt_audio")
        localAudio = track
        pc?.add(track, streamIds: ["mt_stream"])
        track.isEnabled = !desiredMuted   // apply the desired microphone state to the new track
        if isVideo { addVideoTrack() }
    }

    /// The video track must exist by the time of the answer. The connection may have been
    /// built for a call nobody knew was video — then the track is added here and the answer
    /// leaves carrying video. The OFFER is the single source of truth about being a video
    /// call: a push may arrive without the flag, or earlier than the caller turned the
    /// camera on; the m=video line in the offer either exists or it does not.
    private func adoptVideoFromOffer(_ off: CallSDP) {
        guard off.sdp.contains("m=video"), !isVideo else { return }
        isVideo = true
        applyScreenHold()   // the offer declared video -- the screen must hold
        tlog("the offer carries video — accepting as a video call")
        DispatchQueue.main.async { CallUIModel.shared.video = true }
    }

    /// The picture's BIRTH needs no peer connection: source, camera and track live on the
    /// factory alone. Wiring into the connection is a separate step (ensureLocalVideoTrack) —
    /// splitting the two is what lets the caller see themselves the instant they dial.
    private func birthLocalVideo() {
        guard isVideo, localVideo == nil else { return }
        MontanaP2PTrace.mark("cam_start", "want_front=\(wantFrontCamera ? 1 : 0) auth=\(AVCaptureDevice.authorizationStatus(for: .video).rawValue)")
        videoFramesSeen = true
        let source = factory.videoSource()
        setVideoSource(source)
        let counter = FrameCountingCapturerDelegate(sink: source)
        frameCounter = counter
        let cap = MontanaCamera(delegate: counter)
        capturer = cap
        observeCaptureSession(cap)
        let track = factory.videoTrack(with: source, trackId: "mt_video")
        localVideo = track
        DispatchQueue.main.async { CallUIModel.shared.tick += 1 }   // the screen learns about its own track
        wantFrontCamera = true
        startCapture(front: wantFrontCamera)
    }

    private func ensureLocalVideoTrack() {
        // SILENT-OK: a call without video -- nothing to raise.
        guard isVideo else { return }
        birthLocalVideo()   // no-op when the track already lives (born at dial)
        guard let pc, let track = localVideo else { pushCaptureUntilRunning(); return }
        // If the video line already exists (the offer created it), the track goes INTO
        // it and the direction opens for sending. A new line here would be stillborn:
        // absent from the offer, it cannot appear in the answer either.
        if let tr = pc.transceivers.first(where: { $0.mediaType == .video }) {
            if tr.sender.track !== track {
                tr.sender.track = track
                tr.setDirection(.sendRecv, error: nil)
                tlog("video track placed into the existing line")
            }
        } else if !pc.senders.contains(where: { $0.track === track }) {
            pc.add(track, streamIds: ["mt_stream"])
        }
        maybeEnableSframe()   // a new track must fall under frame encryption
        pushCaptureUntilRunning()
    }

    private func addVideoTrack() {
        birthLocalVideo()
        guard let pc, let track = localVideo,
              !pc.senders.contains(where: { $0.track === track }) else { return }
        pc.add(track, streamIds: ["mt_stream"])
    }

    /// The camera, closed by construction. The single place it starts from, and not one
    /// silent exit: every impossibility is named and logged. There used to be four silent
    /// returns — no capturer, no camera on the wanted side, unreadable format, fps out of
    /// range — and all four made the defect read as "video does not work on this device".
    private func startCapture(front: Bool) {
        // THE ONE GATE ON THE ONE CAPTURE ROAD (the author's word 20.09). The access check stood
        // BESIDE the camera — at dial only — while the capture was reached from buildPC and from
        // every callee road unguarded: with the camera switched off in Settings it walked eight
        // formats on two cameras into «not authorized», the retry loop named the denial to the
        // system log, and the person saw nothing (an iPad 6, six days, eight starts, zero frames).
        // Now every start passes the system's own answer: authorized — the camera; not decided —
        // the system prompt, the only time iOS shows it; denied — the alert with the road to
        // Settings, and the call goes on with sound. The track and the offer's video line do not
        // depend on it: a person without a camera still sees the peer.
        ensureCameraAccess { [weak self] ok in
            guard let self, ok else { return }
            self.startCapture(front: front, attempt: 0)
        }
    }

    /// Pixel formats the library can turn into a frame. Ten-bit (`x420`) is absent on
    /// purpose: such a format starts cleanly, frames flow, and the picture stays black —
    /// nobody converts it. This lists ability, not prohibition: it grows with what the
    /// library actually reads.
    private static let renderableSubtypes: Set<FourCharCode> = [
        kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
    ]

    /// Format candidates in order of fitness. The order is NOT "closest to some width":
    /// small formats on modern front cameras turn out to be cropped modes living next to
    /// Center Stage and produce no picture. The order is the one proven in production:
    /// 720p with a wide angle and 30 fps, then large, then medium, then whatever is left.
    /// A list, not a single format: a clean start proves nothing about the picture, and
    /// the next candidate must exist.
    private func formatCandidates(for device: AVCaptureDevice) -> [AVCaptureDevice.Format] {
        // Filtering happens BEFORE choosing. There is deliberately no "take the whole list"
        // fallback: a format the library cannot read starts cleanly and yields black — that
        // is the very defect being closed. An empty pool is reported in words, not papered
        // over with a dead format.
        var pool = MontanaCamera.formats(for: device).filter {
            Self.renderableSubtypes.contains(CMFormatDescriptionGetMediaSubType($0.formatDescription))
        }
        // Center Stage is the SYSTEM's switch, not ours. While it is on, a format without
        // its support cannot be set: the system answers with an exception, the library
        // swallows it, and the camera stays on a foreign format. So the pool narrows by
        // support, and the person keeps their toggle.
        if AVCaptureDevice.isCenterStageEnabled {
            let staged = pool.filter(\.isCenterStageSupported)
            if !staged.isEmpty { pool = staged }
        }
        func rank(_ f: AVCaptureDevice.Format) -> Int {
            let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
            let maxFps = f.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
            if d.width == 1280, d.height == 720, f.videoFieldOfView > 60, maxFps >= 30 { return 0 }
            if d.width >= 720, d.height >= 720 { return 1 }
            if d.width >= 640, d.height >= 640 { return 2 }
            return 3
        }
        return pool.sorted { a, b in
            let ra = rank(a), rb = rank(b)
            if ra != rb { return ra < rb }
            return CMVideoFormatDescriptionGetDimensions(a.formatDescription).width
                 < CMVideoFormatDescriptionGetDimensions(b.formatDescription).width
        }
    }

    /// The frame rate must lie INSIDE ONE of the format's ranges: asking 24 of a format whose range
    /// starts at 30 means not starting the camera at all — the system answers with a refusal. A format
    /// may carry several ranges, and a number between their common least and most can fall into the gap
    /// between two of them (23.09, the critic): the same uncatchable exception. So each range offers its
    /// own whole number nearest to 24 and the nearest offer wins. 0 when no range holds a whole number
    /// (a range like 29.97...29.97): the camera then keeps the format's own rate and nothing is asked.
    private func fpsFor(_ fmt: AVCaptureDevice.Format) -> Int {
        let want = 24
        var best = 0, gap = Int.max
        for r in fmt.videoSupportedFrameRateRanges {
            let lo = Int(r.minFrameRate.rounded(.up)), hi = Int(r.maxFrameRate.rounded(.down))
            guard lo <= hi else { continue }   // a range too narrow to hold a whole number of frames
            let pick = min(max(want, lo), hi)
            if abs(pick - want) < gap { gap = abs(pick - want); best = pick }
        }
        return best
    }

    private func fourCC(_ c: FourCharCode) -> String {
        let b = [UInt8((c >> 24) & 255), UInt8((c >> 16) & 255), UInt8((c >> 8) & 255), UInt8(c & 255)]
        return String(bytes: b, encoding: .ascii) ?? "????"
    }

    private func startCapture(front: Bool, attempt: Int) {
        // THE CAMERA DOES NOT RUN IN THE BACKGROUND -- that is a system rule, not our choice of
        // format. Before, we asked it to start anyway, got a yes and a silent interruption right
        // after, then walked eight settings into the wall for nothing (six seconds) and wrote
        // ourselves "the camera started". The refusal is now named aloud, the attempt is not
        // spent, and what brings us back here is the end of the interruption and the return to
        // the foreground.
        // THE CAMERA WAITS FOR THE END OF BACKGROUND -- and only for that. The flicker gave not
        // an "inactive" state but background proper: the system takes the camera in the
        // background (interruption reason 1), we raised capture again, it fell again. Waiting for
        // the ACTIVE state proved costlier than the illness: under the native call screen the app
        // stands "inactive" long, and the first frame left on the 11th second -- the peer saw blackness until then.
        if UIApplication.shared.applicationState == .background {
            MontanaP2PTrace.mark("cam_deferred", "state=\(UIApplication.shared.applicationState.rawValue)")
            tlog("capture deferred: the app is not active, the system will not give the camera")
            captureRunning = false
            return
        }
        guard let cap = capturer else { cameraFailed("no capturer"); return }
        let devices = MontanaCamera.devices()
        // The camera side is a wish, not a requirement: a device without a front camera
        // must call with the one it has, not stay without a picture.
        guard let device = devices.first(where: { $0.position == (front ? .front : .back) })
                        ?? devices.first(where: { $0.position == (front ? .back : .front) })
                        ?? devices.first else { cameraFailed("no camera at all"); return }
        usingFrontCamera = (device.position == .front)
        frameCounter?.newSegment()   // the next delivered frame speaks for THIS camera

        let cands = formatCandidates(for: device)
        guard !cands.isEmpty else { cameraFailed("the device returned no readable format"); return }
        guard attempt < min(cands.count, 4) else {
            // This camera ran out of candidates. The other camera is the next constructive
            // step, and after it — not a refusal but the best format without proof: an empty
            // screen is worse than a doubtful picture, and that choice belongs to the person.
            // THE BACK CAMERA IS NEVER THE MACHINE'S CHOICE (the author's word 22.09; the iPhone 17 Pro Max at
            // 19:48:37 showed its room to the caller): a camera out of candidates settles on its best format
            // without proof — the front one first (settleWithoutProof). The other camera is the person's
            // own tap on the flip mark, and nothing else, on any device and any system.
            settleWithoutProof()
            return
        }
        let fmt = cands[attempt]
        let fps = fpsFor(fmt)
        let dim = CMVideoFormatDescriptionGetDimensions(fmt.formatDescription)
        let sub = fourCC(CMFormatDescriptionGetMediaSubType(fmt.formatDescription))
        frameCounter?.beginProbe()
        let beforeLit = frameCounter?.litFrames ?? 0
        let beforeAll = frameCounter?.frames ?? 0
        cap.start(device: device, format: fmt, fps: fps) { [weak self] err in
            guard let self else { return }
            if let err {
                self.tlog("format \(attempt) \(dim.width)x\(dim.height)@\(fps) \(sub) failed to start: \(err.localizedDescription)")
                self.startCapture(front: front, attempt: attempt + 1)
                return
            }
            self.captureRunning = true
            self.noteSelfPicture(paused: false)   // a camera raised again is a camera given back
            self.probeGen += 1
            let gen = self.probeGen
            self.sessionRefused = false
            self.tlog("camera started \(self.usingFrontCamera ? "front" : "back") \(dim.width)x\(dim.height)@\(fps) \(sub) fov \(Int(fmt.videoFieldOfView))°")
            self.tlog(self.sessionState(cap, device: device))
            let next: () -> Void = { [weak self] in
                guard let self else { return }
                self.captureRunning = false
                self.startCapture(front: front, attempt: attempt + 1)
            }
            // Camera SILENCE and camera DARKNESS are different failures and deserve
            // different waits. Warm-up takes time: black frames flow for a second while
            // exposure and white balance converge. Total absence of frames takes none:
            // the session either delivers or it does not, and 0.75 s is enough to know.
            // A person must not sit in front of blackness for extra seconds per candidate.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
                guard let self, gen == self.probeGen else { return }
                guard self.state != "idle", self.isVideo else { self.frameCounter?.endProbe(); return }
                guard (self.frameCounter?.frames ?? 0) - beforeAll == 0 else { return }
                // THE SYSTEM'S SILENCE IS NOT THE FORMAT'S (23.09, the iPhone 13 Pro Max at 18:55:00): a video call rang
                // while the app went to the background, the session stood interrupted, and the format was judged silent
                // and the next one raised into the same wall. An interrupted session waits for the interruption's end --
                // the one raise road after the background (observeCaptureSession); this attempt's verdicts are void.
                if cap.session.isInterrupted {
                    self.captureRunning = false
                    self.frameCounter?.endProbe()
                    self.probeGen += 1
                    MontanaP2PTrace.markFolded("cam_wait", "interrupted — the end of the interruption raises", window: 5)
                    return
                }
                self.tlog("format \(attempt) \(dim.width)x\(dim.height) \(sub): camera SILENT — zero frames in 0.75s; \(self.sessionState(cap, device: device))")
                // A SESSION refusal and a FORMAT refusal are different things. While the
                // session is not running, iterating candidates is pointless: every one hits
                // the same wall. The loop used to spin for tens of seconds hiding the one
                // line that mattered.
                if self.sessionRefused {
                    self.captureRunning = false
                    self.cameraFailed("the capture session refused to run — no format will help")
                    return
                }
                next()
            }
            // PROOF of work is a frame WITH LIGHT, not a frame at all. Any arriving frame
            // used to count, and the guard was disarmed by the very black warm-up frames
            // it was written against.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self, gen == self.probeGen else { return }
                guard self.state != "idle", self.isVideo else { self.frameCounter?.endProbe(); return }
                let lit = (self.frameCounter?.litFrames ?? 0) - beforeLit
                let got = (self.frameCounter?.frames ?? 0) - beforeAll
                // FRAMES ARRIVE -- THE FORMAT IS GOOD. Before, only a LIT frame counted as good,
                // and a dark room (or a phone face down) read as a broken format: capture
                // restarted in a circle, up to four candidates at two seconds each. Eight seconds
                // without a picture at the peer -- exactly what was measured (15 s of silence on a
                // live connection). Darkness is not a camera refusal, and it is cured by light,
                // not by changing format. The walk remains for exactly one case: NO frames at all.
                self.frameCounter?.endProbe()
                if got > 0 {
                    MontanaP2PTrace.mark("cam_ok", "format=\(attempt) \(dim.width)x\(dim.height) frames=\(got) lit=\(lit)")
                    self.tlog("format accepted: frames \(got), of them lit \(lit)")
                    DispatchQueue.main.async { CallUIModel.shared.tick += 1 }
                } else if cap.session.isInterrupted {
                    self.captureRunning = false   // the system holds the camera: its end raises, not the next format
                    MontanaP2PTrace.markFolded("cam_wait", "interrupted — the end of the interruption raises", window: 5)
                } else {
                    MontanaP2PTrace.mark("cam_silent", "format=\(attempt) \(dim.width)x\(dim.height)")
                    self.tlog("format \(attempt) \(dim.width)x\(dim.height) \(sub): no frames -- next")
                    next()
                }
            }
        }
    }

    /// The session state in words. The capturer reports a clean start and does not lie: it
    /// really did ask the system to begin. Whether frames flow is another question, and the
    /// answer lives here: is the session running, is it interrupted, did the input attach at
    /// all. The stock capturer, failing to add the input, logged it privately and went on —
    /// a session without a camera, a successful start, no frames and no reason.
    private func sessionState(_ cap: MontanaCamera, device: AVCaptureDevice) -> String {
        let s = cap.session
        let inputs = s.inputs.compactMap { ($0 as? AVCaptureDeviceInput)?.device }
        let side = inputs.first.map { $0.position == .front ? "front" : ($0.position == .back ? "back" : "?") } ?? "NO INPUT"
        return "session: running=\(s.isRunning) interrupted=\(s.isInterrupted) input=\(side) inputs=\(s.inputs.count) outputs=\(s.outputs.count) device connected=\(device.isConnected) center stage=\(AVCaptureDevice.isCenterStageEnabled)"
    }

    /// The system knows why the camera is silent and says so in notifications. Nobody used
    /// to listen: the capturer reported a clean start, the session stood silently
    /// interrupted, and telemetry said "0 frames" with no cause. The cause belongs in the log.
    private func observeCaptureSession(_ cap: MontanaCamera) {
        let c = NotificationCenter.default
        // THE ONE RAISE ROAD AFTER THE BACKGROUND IS THE INTERRUPTION'S END (13.09): the system takes
        // the camera in the background with an interruption and gives it back with «interruption
        // ended» — that road probes and raises below; the birth of a call is covered by the retry
        // loop (pushCaptureUntilRunning). An «app became active» raise stood here as well, registered
        // and removed in the same breath (it never fired) — and had it fired, it would have torn down
        // the very session the system was resuming.
        captureObservers.forEach { c.removeObserver($0) }
        captureObservers.removeAll()
        let s = cap.session
        captureObservers.append(c.addObserver(forName: .AVCaptureSessionWasInterrupted, object: s, queue: .main) { [weak self] n in
            let raw = (n.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int) ?? -1
            // INTERRUPTED MEANS NOT RUNNING. Before, this was a line in the journal while the
            // running flag stayed up: four pickup mechanisms saw "capture is running" and walked
            // past, while the peer watched emptiness (measured: 15 seconds of zero on a live link).
            self?.captureRunning = false
            self?.noteSelfPicture(paused: true)
            MontanaP2PTrace.mark("cam_interrupted", "reason=\(raw)")
            self?.tlog("capture interrupted by the system: \(Self.interruptionReason(raw))")
        })
        captureObservers.append(c.addObserver(forName: .AVCaptureSessionInterruptionEnded, object: s, queue: .main) { [weak self] _ in
            guard let self else { return }
            // THE INTERRUPTION ENDED — THE SESSION RESUMES BY ITSELF, AND IS PROBED FIRST (13.09 15:21,
            // the callee answered on the lock screen): the raise that stood here tore the resuming
            // session down and rebuilt it — 3.4 s of black, the first format judged silent for the
            // seconds it never had, the second one raised. Frames within 0.75 s = the camera is back
            // and nothing is raised; silence = the raise, as before.
            MontanaP2PTrace.mark("cam_resume", "after-interruption")
            self.captureRunning = false
            let before = self.frameCounter?.frames ?? 0
            self.captureProbeUntil = Date().addingTimeInterval(0.75)
            let gen = self.resumeGen
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
                guard let self, gen == self.resumeGen, self.isVideo, self.state != "idle" else { return }
                self.captureProbeUntil = .distantPast
                let got = (self.frameCounter?.frames ?? 0) - before
                if got > 0, self.capturer?.session.isInterrupted == false {
                    self.captureRunning = true
                    self.noteSelfPicture(paused: false)
                    MontanaP2PTrace.mark("cam_ok", "after-interruption frames=\(got)")
                    self.tlog("capture interruption ended -- the session resumed by itself, \(got) frames")
                    DispatchQueue.main.async { CallUIModel.shared.tick += 1 }
                } else {
                    MontanaP2PTrace.mark("cam_silent", "after-interruption frames=\(got) — raising")
                    self.tlog("capture interruption ended -- no frames in 0.75 s, raising again")
                    self.ensureCaptureRunning()
                }
            }
        })
        captureObservers.append(c.addObserver(forName: .AVCaptureSessionRuntimeError, object: s, queue: .main) { [weak self] n in
            guard let self else { return }
            let e = n.userInfo?[AVCaptureSessionErrorKey] as? NSError
            self.sessionRefused = true
            self.tlog("capture session ERROR: \(e?.localizedDescription ?? "unknown") code=\(e?.code ?? 0)")
            // THE PLATFORM'S MEDIA SERVICES WERE RESET (-11819; the iPhone 15, 24.09 21:21:06: an interruption's end and this
            // error in the same millisecond, the session dead, and the picture came back only after the resume probe had
            // waited 0.75 s for frames that could not come and raised -- two seconds of cover for the peer). The platform's
            // own answer to this error is to raise the session again (the AVCam sample): a session whose services were reset
            // does not resume by itself. It is raised at once and the waiting probe stands down, so nothing is raised twice.
            if e?.code == AVError.Code.mediaServicesWereReset.rawValue, self.isVideo, self.state != "idle" {
                MontanaP2PTrace.mark("cam_reset", "media services were reset — raising at once")
                self.resumeGen += 1
                self.captureProbeUntil = .distantPast
                self.captureRunning = false
                self.ensureCaptureRunning()
            }
        })
    }

    private static func interruptionReason(_ raw: Int) -> String {
        switch AVCaptureSession.InterruptionReason(rawValue: raw) {
        case .videoDeviceNotAvailableInBackground: return "camera unavailable in background"
        case .audioDeviceInUseByAnotherClient: return "microphone in use by another client"
        case .videoDeviceInUseByAnotherClient: return "camera is held by another client"
        case .videoDeviceNotAvailableWithMultipleForegroundApps: return "camera unavailable with multiple foreground apps"
        case .videoDeviceNotAvailableDueToSystemPressure: return "camera shut down by system pressure"
        default: return "reason \(raw)"
        }
    }

    /// The last resort. No format on any camera proved a picture — but an empty screen is
    /// the worst outcome of all, and the "lit frame" measure may err on hardware unknown to
    /// us. So the best candidate starts and stays without proof, probing stops, and the
    /// person is told the video may not make it.
    private func settleWithoutProof() {
        let devices = MontanaCamera.devices()
        guard let cap = capturer,
              let device = devices.first(where: { $0.position == .front }) ?? devices.first,
              let fmt = formatCandidates(for: device).first else {
            cameraFailed("no format produced a picture")
            return
        }
        usingFrontCamera = (device.position == .front)
        frameCounter?.endProbe()
        cap.stop { [weak self] in
            guard let self else { return }
            cap.start(device: device, format: fmt, fps: self.fpsFor(fmt)) { [weak self] err in
                guard let self else { return }
                if let err { self.cameraFailed("no format produced a picture: \(err.localizedDescription)"); return }
                self.captureRunning = true
                self.noteSelfPicture(paused: false)
                self.tlog("settled on the best format without picture proof")
                DispatchQueue.main.async { CallUIModel.shared.tick += 1 }
            }
        }
    }

    /// The inability to start the camera is named in the diary, not swallowed. The call itself
    /// goes on: voice flows. NO LINE UNDER THE NAME (the author's word 13.09): the screen keeps
    /// its one status line; every cause lives in the diary.
    private func cameraFailed(_ why: String) {
        tlog("camera did not start: \(why)")
        MontanaP2PTrace.mark("cam_fail", "why=\(why.replacingOccurrences(of: "|", with: "/")) auth=\(AVCaptureDevice.authorizationStatus(for: .video).rawValue)")
    }

    /// A camera denial does not cancel the conversation: voice flows; the diary names the cause
    /// once. The screen carries no line for it (the author's word 13.09).
    private func cameraDenied() {
        guard !cameraDeniedTold else { return }
        cameraDeniedTold = true
        let st = AVCaptureDevice.authorizationStatus(for: .video).rawValue
        tlog("camera denied (status=\(st)) — video not sent, the call continues with sound")
        MontanaP2PTrace.mark("cam_denied", "status=\(st) side=\(isInitiator ? "caller" : "callee")")
        // SAID TO THE FACE, EVERY CALL (the author's word 20.09): the system prompt shows once in an
        // app's life, so a camera switched off in Settings can only be named by us — the system
        // alert on the call screen with the system road to Settings. The flag is reset per call.
        DispatchQueue.main.async { CallUIModel.shared.cameraDenied = true }
    }

    /// Camera access has ONE place for the whole call. The permission used to be merely
    /// requested with the answer thrown away: on refusal the camera silently did not start,
    /// the peer saw emptiness and never knew why. Three outcomes, all named: ask, start,
    /// tell the truth.
    func ensureCameraAccess(_ done: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            done(true)
        case .notDetermined:
            MontanaP2PTrace.mark("cam_ask", "system prompt")
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    MontanaP2PTrace.mark("cam_ask", "answer=\(granted ? "granted" : "denied")")
                    if !granted { self.cameraDenied() }
                    done(granted)
                }
            }
        default:
            DispatchQueue.main.async { self.cameraDenied(); done(false) }
        }
    }

    // Answering a video call from the background: the camera doesn't start in the background — kick it off when entering the app.
    func ensureCaptureRunning() {
        // The "capture is running" flag is derived from DELIVERED FRAMES, not from the fact that
        // we called start: a live session without frames is not work, and the pickup must happen.
        // SILENT-OK: capture already runs with live frames, or there is no call -- nothing to raise.
        let alive = captureRunning && (capturer?.session.isRunning ?? false)
            && !(capturer?.session.isInterrupted ?? false) && (frameCounter?.frames ?? 0) > 0
        guard isVideo, state != "idle", capturer != nil, !alive else { return }
        // AN INTERRUPTED SESSION IS NOT RAISED (13.09 15:21): the system took the camera and gives it
        // back with «interruption ended» — a raise in between tears the session down and rebuilds it
        // against the system's own resume (measured on the callee after a lock-screen answer: 3.4 s of
        // black, then the first format judged silent, the second raised). The end of the interruption
        // probes the resumed session first and raises only on silence.
        if capturer?.session.isInterrupted == true {
            MontanaP2PTrace.markFolded("cam_wait", "interrupted — the end of the interruption raises", window: 5)
            return
        }
        if Date() < captureProbeUntil { return }   // the resumed session is being probed — its verdict raises or not
        startCapture(front: wantFrontCamera)   // the access gate lives inside the one capture road
    }

    /// The camera does not start in the background: the connection is built FOR the call,
    /// and the first attempt fails silently. One "app became active" event is not enough —
    /// it arrives whenever it arrives. So attempts repeat until success, in a short window
    /// with a limit.
    private func pushCaptureUntilRunning() {
        guard isVideo else { return }
        captureRetryTimer?.invalidate()
        var left = 20   // NATIVE-CHECKED: an attempt bound, not a clock reading -- retries are counted (20 x 0.5s), no time is shown to the person
        captureRetryTimer = callTimer(0.5, repeats: true) { [weak self] tm in
            guard let self, self.isVideo, self.state != "idle" else { tm.invalidate(); return }
            if self.captureRunning || left <= 0 {
                tm.invalidate()
                if self.captureRunning { self.tlog("camera came up") }
                return
            }
            left -= 1
            self.ensureCaptureRunning()
        }
    }

    private func tuneSDP(_ sdp: String, premium: Bool) -> String {
        let bitrate = premium ? 64000 : 40000
        return sdp.replacingOccurrences(
            of: "useinbandfec=1",
            with: "useinbandfec=1;stereo=0;maxaveragebitrate=\(bitrate);maxplaybackrate=48000;cbr=0")
    }

    // ── Post-quantum SFrame on top of SRTP: enable when both sides are ios-native + there is a call_seed ──
    private func maybeEnableSframe() {
        // K-1: the cryptor array belongs to the owner thread — this used to be mutated from
        // three threads at once (main, didAdd, setRemote callbacks).
        guard Thread.isMainThread else { DispatchQueue.main.async { self.maybeEnableSframe() }; return }
        // Enable ONLY when both sides have the key: callee — on receiving call-key (sends call-key-ok),
        // caller — on receiving call-key-ok. Key didn't arrive → SFrame is enabled nowhere → media lives
        // on DTLS-SRTP (doesn't go silent from one-sided decryption).
        guard sframeAuthorized, peerPremium, let seed = callSeed,
              let sk = MontanaPQ.sframeKey(callSeed: seed), let pc = pc else { return }
        let kp: RTCFrameCryptorKeyProvider
        if let existing = keyProvider { kp = existing }
        else {
            let salt = Data("mt-call-sframe".utf8)   // LOCAL-HASH-OK: the frame-layer salt, it leaves together with the layer in 4b
            kp = RTCFrameCryptorKeyProvider(ratchetSalt: salt, ratchetWindowSize: 0,
                                            sharedKeyMode: true, uncryptedMagicBytes: nil)
            kp.setSharedKey(sk, with: 0)
            keyProvider = kp
        }
        // Idempotent per sender/receiver — late (video) receivers are wrapped too.
        for s in pc.senders where s.track != nil && !sframeWrapped.contains(ObjectIdentifier(s)) {
            guard let fc = RTCFrameCryptor(factory: factory, rtpSender: s, participantId: "mt",
                                           algorithm: .aesGcm, keyProvider: kp) else { continue }
            fc.keyIndex = 0; fc.enabled = true; frameCryptors.append(fc)
            sframeWrapped.insert(ObjectIdentifier(s))
        }
        for r in pc.receivers where r.track != nil && !sframeWrapped.contains(ObjectIdentifier(r)) {
            guard let fc = RTCFrameCryptor(factory: factory, rtpReceiver: r, participantId: "mt",
                                           algorithm: .aesGcm, keyProvider: kp) else { continue }
            fc.keyIndex = 0; fc.enabled = true; frameCryptors.append(fc)
            sframeWrapped.insert(ObjectIdentifier(r))
        }
        if !frameCryptors.isEmpty { E2ELog.write("call: SFrame-PQ active (AES-GCM, sframe_key, wrapped \(frameCryptors.count))") }
    }

    // Callback from the native iPhone «Recents» (INStartCall/Audio/VideoCallIntent).
    // personHandle.value holds the call's ONE-TIME TOKEN -- the conversation is found by it in the
    // local vault. The conversation link itself is never given to the system: no foreign journal keeps it.
    /// ONE TAP IN «RECENTS», ONE CALL (23.09): the tap reaches the app by two doors — the scene's continue and the
    /// delegate's — and each started the call on its own. The idle guard refused the second only while the first
    /// still stood: a first call that ended inside the second door's ten-second wait for the identity was dialled
    /// again. The same person with the same kind within five seconds is the same tap; the door is named either way.
    private var lastIntent: (peer: String, video: Bool, at: Date)?

    @discardableResult
    func handleCallIntent(_ ua: NSUserActivity, door: String = "scene") -> Bool {
        var ref: String? = nil
        var video = false
        if let i = ua.interaction?.intent as? INStartCallIntent {
            ref = i.contacts?.first?.personHandle?.value
            video = (i.callCapability == .videoCall)
        } else if let i = ua.interaction?.intent as? INStartVideoCallIntent {
            ref = i.contacts?.first?.personHandle?.value; video = true
        } else if let i = ua.interaction?.intent as? INStartAudioCallIntent {
            ref = i.contacts?.first?.personHandle?.value; video = false
        }
        guard let token = ref, !token.isEmpty else { return false }
        let peer = MontanaCallHandle.conv(for: token)
        guard MontanaConv.holds(peer) else { return false }
        if let l = lastIntent, l.peer == peer, l.video == video, Date().timeIntervalSince(l.at) < 5 {
            MontanaP2PTrace.mark("call_intent", "door=\(door) dup=1 video=\(video ? 1 : 0) peer=\(String(peer.prefix(10)))")
            return true
        }
        lastIntent = (peer, video, Date())
        MontanaP2PTrace.mark("call_intent", "door=\(door) video=\(video ? 1 : 0) peer=\(String(peer.prefix(10)))")
        startCallWhenReady(peer: peer, video: video)
        return true
    }

    // Wait for the session to be ready (cold start from «Recents») and call immediately.
    func startCallWhenReady(peer: String, video: Bool, attempt: Int = 0) {
        if MontanaP2PNode.stageGate {
            startCall(peer: peer, device: "", video: video)
            return
        }
        guard attempt < 40 else { return }   // up to ~10 s of waiting for the identity/unlock
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            self.startCallWhenReady(peer: peer, video: video, attempt: attempt + 1)
        }
    }

    /// The system is told NOTHING about a call beyond the necessary.
    ///
    /// Here the "call intent" was sacrificed: the person's name, their face and the conversation
    /// link went into the suggestions store -- out from under our encryption, into the backup and
    /// onto other devices of the account. For a round face in Recents that is far too expensive:
    /// the native handset gets the name directly (stampNativeName), and the face is seen where the
    /// conversation itself lives -- in the app.

    /// A step of a birth that no longer holds the machine writes why and does nothing else; a connection it
    /// built for a call already rested is closed.
    private func birthAborted(_ gen: Int, _ at: String) {
        MontanaP2PTrace.mark("call_birth", "aborted at=\(at) gen=\(gen) state=\(state)")
        if state == "idle", let p = pc { p.close(); pc = nil }
    }

    // ═══ Outgoing ═══
    func startCall(peer: String, device: String, video: Bool, displayName: String? = nil) {
        guard state == "idle" else { return }
        // ONE CALL OF OURS AT A TIME (07.10): a group's room in hand is left first by its own hand, never put on hold by ours.
        if MTGroupRoom.isLive { MTGroupRoom.shared.say("Leave the group call first"); return }
        // A blocked person is called by nobody (the reference's rule): their answer would be refused
        // at the door anyway (measured 15.09 13:35 — the call rang them and died on the answer).
        if ChatStore.refusesNow(peer) { MontanaP2PTrace.mark("call_refused", "blocked peer=\(String(peer.prefix(10)))"); return }
        // UNDER THE PERMITTED-LIST FILTER A CALL HAS NO ROAD (29.09): the doors may stand on a permitted cascade, the media
        // cannot -- the relay and the reflector are ours and stand on no list. The line's one verdict (MontanaNetProbe, with no
        // tunnel carrying the app past the filter) is the call's before a far phone is rung for nothing, and the person's, in words.
        if MontanaNetProbe.filtersCalls {
            MontanaP2PTrace.mark("call_refused", "filtered — this network passes permitted destinations only")
            MontanaLog.event("E2E-CALL refused why=whitelist dir=out")
            Self.tellNoRoad(filtered: true)
            return
        }
        // The OUTGOING call learns the name from the place it was started (the chat row, the
        // profile) — the same resolver the person just saw; the incoming one learns it from
        // the envelope. Recents then shows a person, never digits.
        if let dn = displayName { presetPeerName(peer, dn) }
        nativeHandle = MontanaCallHandle.token(for: peer)   // the token is born BEFORE the first showing to the system
        self.peer = peer; self.peerDevice = device; self.isVideo = video
        self.isInitiator = true; self.pendingIce = []; self.sframeWrapped = []; self.frameCryptors = []
        self.iceHeldForPeerWord = true; self.restartAskedAt = .distantPast; self.setupAsks = 0; self.askedRelayOnly = false; self.lastIce = "new"; self.rebuiltInPlace = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.releaseHeldIce("time") }
        iceBatchTimer?.cancel(); iceBatchTimer = nil; iceOutBatch = []; iceFlushes = 0; resetSignalFlags(); audioUnitPending = false; videoReady = false; measuring = false
        self.sframeAuthorized = false; self.captureRunning = false
        // THE END'S REASON BELONGS TO ONE CALL (23.09): it was written «only if unnamed» and never unnamed again, so
        // every call after the first in a process wore the first one's reason -- T1's own hang-ups of 18:36:13 and
        // 19:20:30 were summed as «peer-ended». Every birth of a call names it anew.
        self.ended = false; self.endSignalSent = false; self.declinedByMe = false; self.answeredByMe = false; self.endReason = "-"; self.endDoor = "-"
        self.cameraDeniedTold = false
        self.callSeed = montanaRandom(32)
        callGen += 1
        // ONE BIRTH, ONE LIFE (25.09, the phantom call on a tester's phone): the system reset the provider two
        // milliseconds after the start was asked, the machine wrote the call ended -- and the birth went on: the
        // audio session, the connection, the offer and the wake to the far phone, which rang and answered a call
        // nobody held. Every step of this birth from here on checks that it still holds the machine (callGen).
        let gen = callGen
        self.startedAt = Date(); self.connectedAt = nil; self.answeredAt = nil
        let uuid = UUID(); self.callUUID = uuid
        setState("outgoing")
        callT0 = Date(); iceGenCount = 0; firstMediaLogged = false; firstVideoIn = false
        beginBackgroundHold()
        startSetupHeartbeat()
        // Bare ring first: reach the peer over the mesh INSTANTLY, WITHOUT an offer — no waiting for
        // buildPC/createOffer. The offer catches up over the warm channel (ctrl=call below).
        // THE KNOCK GOES ON FOR THE WHOLE RING (13.09, the author's word): four knocks in ten seconds
        // left fifty silent seconds — a phone whose link to Apple came back on the fifteenth second
        // never rang (a tester's phone, 08:41 and 09:07: one push in the queue, the voip wake dead
        // after 25 s). Every five seconds a fresh wake, each with its own life, until the far phone
        // says «ringing» or the call ends. Repeats are folded on the callee (ring_copy).
        Task { [weak self] in
            guard let self else { return }
            var everRung = false
            var attempt = 0
            while true {
                if self.state != "outgoing" || self.callGen != gen || self.peerRinging { break }
                let r = await self.ringReach?(peer, video, nil, self.callSeed?.base64EncodedString()) ?? (rung: 0, online: false, nobody: false)   // seed in the bare ring: the callee knows the call epoch from the FIRST wake
                await MainActor.run {
                    guard self.state == "outgoing" else { return }
                    self.tlog("② bare-ring rung=\(r.rung) online=\(r.online) attempt=\(attempt + 1)")
                    // 15.12: «No recipients» means the other phone has never registered for calls;
                    // the knock stops and the diary says so (ring_nobody, side=ours-registration).
                    // The screen carries no line for it (the author's word 13.09).
                    if r.nobody { MontanaP2PTrace.mark("ring_nobody", "peer=\(String(peer.prefix(10)))") }
                }
                if r.nobody { self.knockNobody = true; break }
                self.knockN += 1
                if r.rung > 0 {
                    everRung = true; self.knockOk += 1
                    let s = Int(Date().timeIntervalSince(self.startedAt ?? Date()))
                    if self.knockFirstOkS < 0 { self.knockFirstOkS = s }
                    self.knockLastOkS = s
                }
                if self.peerRinging { break }
                attempt += 1
                // THE SECOND BELL: Apple took a wake, TEN seconds passed, no «ringing» — the ring
                // letter goes out loud by the message road (E2E.ringBell), once per call. Ten, not
                // five (13.09): the knock walks every five seconds, and at the second knock the far
                // phone's «ringing» word is usually still on the road — a bell rung then lands on a
                // phone already ringing, and the extension cannot take that banner back.
                if attempt >= 3, everRung, !self.bellRung, !self.peerRinging, self.state == "outgoing" {
                    self.bellRung = true
                    E2E.shared.ringBell(to: peer, video: video, callSeed: self.callSeed?.base64EncodedString())
                }
                // Four knocks, nobody rung, nobody ringing: the phone is asleep or out of reach — the
                // diary says so (ring_unreached); the screen keeps its one status line and the knock
                // goes on (the author's word 13.09: no line under the name).
                if attempt == 4, !everRung, !self.peerRinging, self.state == "outgoing" {
                    MontanaP2PTrace.mark("ring_unreached", "peer=\(String(peer.prefix(10)))")
                }
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
            MontanaP2PTrace.mark("ring_knock", "stop n=\(attempt) rung=\(everRung ? 1 : 0) ringing=\(self.peerRinging ? 1 : 0) state=\(self.state)")
        }
        tlog("① startCall pressed video=\(video) peer=\(MontanaConv.short(peer))")
        // A call is the sharpest case for the direct path: the address is named the same instant as
        // the invitation, so path checks start at once instead of after an exchange through the node.
        MontanaNATService.shared.announce(to: peer)
        if video {
            // The caller's picture is born HERE, not inside buildPC: the track and the
            // camera need no peer connection, and waiting for one chained the picture
            // behind the audio session and the TURN fetch — seconds of black at dial.
            birthLocalVideo()   // the access gate lives inside the capture road; the track is born regardless
            pushCaptureUntilRunning()
        }
        startDialTone()   // the searching pips until the peer's own word «ringing»; the ringback waits for that word
        armReachTimeout(seconds: 20)   // safety net: the offer chain may break before ringing [critic-289]
        let handle = CXHandle(type: .generic, value: nativeHandle)
        let action = CXStartCallAction(call: uuid, handle: handle)
        action.isVideo = video
        callController.request(CXTransaction(action: action)) { [weak self] err in
            // THE SYSTEM'S REFUSAL ENDS THE BIRTH (25.09): a start the system did not take was ignored here, and the
            // machine dialled on without a call the system knew.
            guard let err, let self else { return }
            DispatchQueue.main.async {
                guard self.callGen == gen, self.state == "outgoing" else { return }
                MontanaP2PTrace.mark("call_refused", "callkit err=\(err.localizedDescription.prefix(60))")
                self.endByRule("callkit-refused")
            }
        }
        // The name is set in perform(CXStartCallAction) -- there the call already exists for the system.
        Task { @MainActor in   // K-1: the machine's fields are the owner thread's
            guard callGen == gen, state == "outgoing" else { birthAborted(gen, "before the audio session"); return }
            configureAudioSession()
            tlog("③ configureAudioSession done, building pc")
            await buildPC()
            guard callGen == gen, state == "outgoing" else { birthAborted(gen, "after buildPC"); return }
            tlog("④ buildPC done, creating offer")
            let mc = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
            pc?.offer(for: mc) { [weak self] desc, _ in
                guard let self, self.callGen == gen, self.state == "outgoing" else { return }
                guard let desc else { self.tlog("createOffer FAILED"); self.armReachTimeout(seconds: 4); return }
                let tuned = RTCSessionDescription(type: desc.type, sdp: self.tuneSDP(desc.sdp, premium: true))
                self.pc?.setLocalDescription(tuned) { err in
                    guard self.callGen == gen, self.state == "outgoing" else { return }
                    // An offer whose own description was refused is not an offer. The peer
                    // would accept it as remote, build an answer, raise the ICE checks — and
                    // they could never converge, while the call looked established and stayed
                    // silent until the hard timeout.
                    if let err {
                        self.tlog("own description refused: \(err.localizedDescription) — the offer is not sent")
                        self.endByRule("offer-refused-here")
                        return
                    }
                    self.boostVideo()
                    self.sendSignal?(peer, CallSignalOut(
                        ctrl: "call", sdp: CallSDP(type: "offer", sdp: tuned.sdp), video: video,
                        caps: self.myCaps(), callSeed: self.callSeed?.base64EncodedString()))
                    self.tlog("⑤ offer setLocal done → sent over channel (\(tuned.sdp.count)b)")
                    // The bare ring already went out at the start (without an offer) — the peer is up.
                    // The offer is resent over the warm channel every 2s UNTIL an answer arrives (meaning the peer
                    // received the offer). A single channel blink doesn't lose the offer = stability. [author: instantly always]
                    self.pendingOfferSdp = tuned.sdp
                    // the offer is ready -- we send it by a voip wake (on cellular without mesh the
                    // callee gets the offer ONLY this way; the early bare ring already lit their screen).
                    Task { [weak self] in
                        guard let self else { return }
                        _ = await self.ringReach?(peer, video, tuned.sdp, self.callSeed?.base64EncodedString())
                    }
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        self.offerResends = 0
                        self.offerResendTimer?.invalidate()
                        self.offerResendTimer = self.callTimer(2, repeats: true) { [weak self] t in
                            guard let self else { t.invalidate(); return }
                            self.offerResends += 1
                            // REPEATING STOPS ON RING CONFIRMATION, not on a counter.
                            // The peer has already confirmed that it rings for them -- the offer
                            // arrived, and six repeats of four kilobytes each only clogged the
                            // signal queue on the node (it is short) and PUSHED THE ANSWER OUT of it:
                            // measured -- the answer reached the caller ten seconds after it was
                            // sent, while offer repeats flowed in an even stream.
                            if self.state != "outgoing" || self.peerRinging
                                || self.pc?.remoteDescription != nil || self.offerResends > 6 {
                                t.invalidate(); self.offerResendTimer = nil
                                MontanaP2PTrace.mark("offer_resend", "stop n=\(self.offerResends) ringing=\(self.peerRinging ? 1 : 0)")
                                return
                            }
                            if let sdp = self.pendingOfferSdp {
                                self.sendSignal?(peer, CallSignalOut(ctrl: "call", sdp: CallSDP(type: "offer", sdp: sdp),
                                                                     video: video, caps: self.myCaps(), callSeed: self.callSeed?.base64EncodedString()))
                            }
                        }
                    }
                }
            }
            armHardTimeout()
        }
    }

    /// The mandatory CallKit report for a voip wake that could not be opened or accepted:
    /// the system demands a report for EVERY voip push (iOS 13+), or it takes the app away.
    /// Carried over from the proven client.
    func reportDummyAndEnd(from: String, blocked: Bool = false, reason: CXCallEndedReason = .unanswered) {
        let u = UUID()
        // A blocked caller's wake (the second wall, 15.09): the report the system demands, ended as
        // a FAILED call — «unanswered» is the system's word for a missed call and wrote the blocked
        // person into the phone's call list. A wake that carried no call (an answer, an echo, a word of a
        // buried call) ends failed too (25.09): «unanswered» wrote a missed call from the far person into a
        // tester's list for a push that had answered his own dial.
        let why: CXCallEndedReason = blocked ? .failed : reason
        MontanaP2PTrace.mark("ring_posted", "busy-dummy from=\(String(from.prefix(10)))\(blocked ? " blocked" : "") end=\(why == .failed ? "failed" : "unanswered")")
        // THE DUMMY ENDS AFTER THE SYSTEM HAS IT (25.09): the end used to follow the report at once, and an end for a
        // call the system had not registered yet ended nothing -- the dummy stood as a full ringing call from the far
        // person and was answered 1.6 s later. The end is asked inside the report's own completion.
        reportIncoming(uuid: u, from: from, video: false) { [weak self] in
            self?.provider.reportCall(with: u, endedAt: nil, reason: why)
        }
    }

    // PushKit execution law (stage 12.1): a VoIP push must post to CallKit BEFORE the push
    // completion returns, on EVERY branch — otherwise the system kills the whole process
    // («Killing app because it never posted an incoming call…», measured 20.08), taking
    // sends, receives and live typing with it. This is the ONE door of the push road:
    // it posts synchronously and idempotently; the signal machine ADOPTS the posted call,
    // and every rejecting branch ends it on top — never a silent return.
    private var pushPostedUUID: UUID?
    func postForPush(from: String, video: Bool) {
        if state != "idle", callUUID != nil {
            // Busy with another peer: the push posts the SECOND LINE (12.2) — a real ringing
            // call, not a flash-dummy. Same peer: the live posted call stands for this push.
            // THE STANDING RING IS THIS WAKE'S RING (21.09, the critic): the call had already been
            // born by the signal lane half a second before the voip push, and the verdict read the
            // silence of this branch as «no-ring» — eight false alarms on T1 in one afternoon while
            // the native ring stood on the screen. A measure names what it measures.
            if peer != from { postSecondLine(from: from, video: video) }
            // PUSHKIT'S LAW IS PER PUSH (25.09): a standing call answered nothing -- T1 got two wakes at 10:40:15Z for a
            // call the signal lane had already born and reported, posted neither, and the system killed the process
            // (MetricKit: signal 9, RBS 0xBAADCA11). The standing call is reported again under its own uuid: the system
            // answers «already exists», and the push is answered.
            if peer == from, let u = callUUID { reportIncoming(uuid: u, from: from, video: video) }
            MontanaWakeDoor.note("ring")
            MontanaP2PTrace.mark("ring_posted", "standing from=\(String(from.prefix(10))) state=\(state) reported=\(peer == from ? 1 : 0)")
            return
        }
        let u = callUUID ?? UUID()
        callUUID = u
        pushPostedUUID = u
        Self.noteRingPosted(true)
        MontanaP2PTrace.mark("ring_posted", "push-first from=\(String(from.prefix(10))) video=\(video ? 1 : 0)")
        MontanaWakeDoor.note("ring")
        reportIncoming(uuid: u, from: from, video: video)
        // A RING CANNOT OUTLIVE THE CALL THAT RAISED IT (13.09, the author: he called, hung up, and
        // the far phone rang on). This ring is the push road's, and until the machine adopts it nothing
        // of ours can end it: the caller's hang-up rides the signal lane, and a lane can be deaf. So
        // the ring carries its own end — the call's one life, the same ninety seconds the caller
        // knocks for. A ring the machine adopted is the machine's from that moment and this hand
        // never touches it.
        DispatchQueue.main.asyncAfter(deadline: .now() + MontanaCall.callLifeS) { [weak self] in
            guard let self, self.pushPostedUUID == u, self.state == "idle" else { return }
            MontanaP2PTrace.mark("ring_posted", "life spent — the unadopted ring ends itself")
            self.endPushPosted()
        }
    }
    private func endPushPosted() {
        guard let u = pushPostedUUID else { return }
        pushPostedUUID = nil
        Self.noteRingPosted(false)
        MontanaP2PTrace.mark("ring_posted", "ended-on-top")
        provider.reportCall(with: u, endedAt: nil, reason: .unanswered)
        if callUUID == u { callUUID = nil }
    }

    func handleSignalGate(_ ctrl: String, _ seed: String?) -> Bool {
        if ctrl == "call", MontanaCall.isDeadSeed(seed) {
            MontanaP2PTrace.mark("ring_dead", "seed=\(String((seed ?? "").prefix(8)))")
            return false
        }
        return true
    }
    func handleSignal(from: String, device: String, ctrl: String, sdp: CallSDP?, candidate: CallICE?,
                      video: Bool?, caps: CallCaps?, callSeed: String?, ts: Int? = nil,
                      candidates: [CallICE]? = nil, reason: String? = nil,
                      name: String? = nil, glyph: String? = nil) {
        // The one entrance for all three call roads (voip push, call letter, signal queue):
        // the seed of a finished call is dead -- a late invitation does not light the screen.
        if ctrl == "call", MontanaCall.isDeadSeed(callSeed) {
            MontanaP2PTrace.mark("ring_dead", "seed=\(String((callSeed ?? "").prefix(8)))")
            // A REJOIN OF A CALL THAT ENDED HERE is told so at once (24.09): the run that came back would otherwise
            // wait out its answer window over «Reconnecting…» for a call nobody holds any more.
            if reason == "rejoin", !from.isEmpty, let s = callSeed {
                var es = CallSignalOut(ctrl: "call-end"); es.epoch = String(s.prefix(16)); es.nodeOnly = true
                DispatchQueue.main.async { self.sendSignal?(from, es) }
            }
            return
        }
        if !from.isEmpty { onPeerWord?(from) }   // 15.7: a signal of theirs is presence, whatever it says
        // A CALL SIGNAL DOES NOT QUEUE BEHIND THE SCREEN. Here was the reason voice connected
        // instantly while video took ten seconds: the offer, the answer and the candidates were
        // applied on the main queue, and under a video call that queue is busy showing self,
        // laying out the view and sending name and face to neighbours. Measured: the answer
        // arrived at 26.8 s, and path checks began at 30.5 -- three and seven tenths of a second
        // the answer lay in the queue behind somebody else's work. Voice has an empty queue, and
        // that is the whole of its "instant". Our own queue is serial, so signal order holds; only
        // view updates go to the main queue, and they are already wrapped at the place of use.
        // THE ANSWER AND THE CANDIDATES GO INTO THE CALL MACHINE IMMEDIATELY, on the arriving thread.
        // The measurement caught exactly this place: the answer came at 3.45 s of the call and was
        // handed to the machine at 12.3 -- eight and nine tenths of a second it waited for the main
        // thread while that one parsed an arrived letter. The app was awake meanwhile: heartbeats
        // came every second evenly. Applying a description and adding a candidate are themselves
        // thread-safe on the call machine and touch neither the screen nor app state -- so they go
        // at once, while the paperwork (whom to answer, drop the deadlines, refresh the view)
        // stays on the main thread and arrives after.
        if ctrl == "call-answer", let s = sdp, let pcx = pc, pcx.remoteDescription == nil, claimAnswerFast() {
            MontanaP2PTrace.mark("sdp_in", "answer ms=\(Int(Date().timeIntervalSince(startedAt ?? Date())*1000)) bytes=\(s.sdp.count)")
            pcx.setRemoteDescription(RTCSessionDescription(type: .answer, sdp: s.sdp)) { [weak self] err in
                // SILENT-OK: the call machine is gone -- the call has ended, there is no one to report to.
                guard let self else { return }
                if let err {
                    self.tlog("peer answer refused: \(err.localizedDescription) — the call cannot proceed")
                    MontanaP2PTrace.mark("sdp_in", "REFUSED \(err.localizedDescription)")
                    self.endByRule("answer-refused"); return
                }
                self.armHardTimeout(); self.flushIce(); self.maybeEnableSframe()
                DispatchQueue.main.async {
                    self.startRouteWatch()
                    guard self.routeDirty else { return }
                    self.routeDirty = false
                    // The answer landed on candidates born on the dead path: give the first
                    // checks two seconds, then ask for fresh ones — do not wait out a minute
                    // of checking into the void (precedent 08:11, call never connected).
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                        guard let self, self.state != "connected", self.state != "active",
                              !self.ended, self.pc != nil else { return }
                        MontanaP2PTrace.mark("call_route", "dirty route at answer — ice restart")
                        self.requestIceRestart(reason: "dirty route at answer")
                    }
                }
            }
        }
        if ctrl == "call-ice", let pcx = pc, pcx.remoteDescription != nil {
            for c in (candidates ?? []) + (candidate.map { [$0] } ?? []) {
                pcx.add(RTCIceCandidate(sdp: c.candidate, sdpMLineIndex: c.sdpMLineIndex ?? 0, sdpMid: c.sdpMid)) { _ in }
            }
            markRemoteIceSeen()
            return   // candidates have no paperwork -- they are already in the machine
        }
        // Parsing runs on the MAIN thread -- inside it touches app state (is the window available,
        // may capture start), and that from a foreign thread crashes the app. Speed comes not from
        // moving the call to a foreign thread but from taking foreign work off the main one:
        // the introduction volley yields to the call, and one extra hop through the queue is gone.
        if Thread.isMainThread {
            handleSignalBody(from: from, device: device, ctrl: ctrl, sdp: sdp, candidate: candidate,
                             video: video, caps: caps, callSeed: callSeed, ts: ts, candidates: candidates,
                             reason: reason, name: name, glyph: glyph)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.handleSignalBody(from: from, device: device, ctrl: ctrl, sdp: sdp, candidate: candidate,
                                       video: video, caps: caps, callSeed: callSeed, ts: ts, candidates: candidates,
                                       reason: reason, name: name, glyph: glyph)
            }
        }
    }
    private func handleSignalBody(from: String, device: String, ctrl: String, sdp: CallSDP?, candidate: CallICE?,
                      video: Bool?, caps: CallCaps?, callSeed: String?, ts: Int? = nil,
                      candidates: [CallICE]? = nil, reason: String? = nil,
                      name: String? = nil, glyph: String? = nil) {
        switch ctrl {
        case "call":
            // THE PEER CAME BACK INTO THIS CALL (24.09). iOS ended the far app (a privacy switch changed in Settings,
            // memory, a fall), and its next run went back into the call it held: the same seed, a new connection, the
            // word «rejoin». The dead connection is replaced in place -- nothing rings, nothing is accepted twice, the
            // screen says «reconnecting» until the media flows. A rejoin is never a birth and never a copy: a machine
            // that does not hold this very call buries it. Stands before the echo and the copy rules -- a rejoin carries
            // this call's own seed by construction.
            if reason == "rejoin" {
                if from == peer, let s = sdp, let theirs = callSeed, !theirs.isEmpty,
                   theirs == self.callSeed?.base64EncodedString(), state == "connected" || state == "reconnecting" {
                    // BOTH RUNS CAME BACK (24.09): iOS ended both apps, and each run's rejoin offer reaches the other;
                    // two answers to two offers whose connections were just closed build nothing. One offer stands, by
                    // no clock: the caller's, while nothing has answered it -- the callee's run answers it. A caller
                    // whose offers had stopped sends its own again: the callee back later still meets it.
                    if rejoining, isInitiator, pc?.remoteDescription == nil {
                        MontanaP2PTrace.mark("call_rejoin", "rx while this run is rejoining too -- the caller's offer stands, theirs buried")
                        if !rejoinOffering, let mine = pc?.localDescription?.sdp { sendRejoinOffer(mine, gen: callGen) }
                        return
                    }
                    rebuildForRejoin(offer: s, device: device, caps: caps)
                } else {
                    MontanaP2PTrace.mark("call_rejoin", "rx for no call held here state=\(state) — buried")
                }
                return
            }
            // MY OWN WORD, RETURNED (the author's word 12.09: «the system sent call-end itself —
            // inadmissible»; measured 07:34:56 and 07:48:31): the ring letter of this very call came
            // back through the node on a stale subscription row, and the busy branch answered it
            // with call-end — to the peer, who hung up mid-talk. A call word carrying the seed THIS
            // phone generated is this phone's echo, in every state: it names nobody, moves nothing,
            // and is answered with nothing. Stands before every other rule of the word.
            if isInitiator, from == peer, let theirs = callSeed, !theirs.isEmpty,
               theirs == self.callSeed?.base64EncodedString() {
                MontanaP2PTrace.mark("ring_echo", "own seed state=\(state) — buried")
                endPushPosted(); return
            }
            // A COPY OF THE CALL IN HAND (13.09): the same seed from the same peer is the same call —
            // the queue copy, the ring letter, a late fan-out — never a second call and never a
            // stranger, in every state. Carrying an offer while none is in hand it IS the offer and
            // goes on to be taken; anything else of it is nothing. The former rule keyed on «an
            // offer already in hand», and a copy that reached a connected call after the offer had
            // been consumed fell through to the busy branch — and the busy branch answers with
            // call-end to the peer. That is the K-18 road once more, by a copy instead of an echo.
            if from == peer, state != "idle", let theirs = callSeed, !theirs.isEmpty,
               theirs == self.callSeed?.base64EncodedString(), sdp == nil || pendingOffer != nil || state == "connected" {
                learnPeerCaps(caps)   // a copy moves nothing, but what the far build can do it still says (24.09 23:14)
                MontanaP2PTrace.mark("ring_copy", "same seed state=\(state) sdp=\(sdp == nil ? 0 : 1) — nothing")
                endPushPosted(); return
            }
            // A NEW CALL OF THE PEER OF AN ESTABLISHED CALL SUPERSEDES IT (24.09, the author: «after the broadcast error
            // iPhone 15 still could not get through to me on T1»). iOS ends an app whose person changes a privacy switch
            // in Settings; the far phone came back without our call and called anew. This machine held its call
            // «reconnecting», buried the new seed's offers under the duplicate rule below (it keys on the peer, not on
            // the seed), posted its pushes as «standing», and the caller knocked into a call nobody had (T1 10:03:16-33
            // and 10:06:43-10:07:12Z, until the caller gave up). A person does not run two calls with us: a new seed from
            // them means their side of ours is gone. Ours ends here without a farewell — a call-end keyed by the peer
            // on the mesh road would end their NEW call — and theirs is born as an ordinary incoming call. A dead seed
            // never reaches this line (ring_dead above); an expired offer is not a call.
            // YOUNGER THAN OURS (the critic 24.09): a delayed invitation of a call the peer placed BEFORE ours — never born
            // here, so not in the graveyard — must not end a living call. A word with a moment (the pipe, the ring letter)
            // is younger than our call's birth on the node's clock; a push carries no moment, and only a call whose media is
            // already dead yields to it.
            let youngerThanOurs: Bool = {
                guard let ts else { return self.state == "reconnecting" }
                let skew = MontanaWakePush.nodeNow() - Date().timeIntervalSince1970
                let ours = ((self.startedAt ?? Date.distantPast).timeIntervalSince1970 + skew) * 1000
                return Double(ts) > ours
            }()
            if from == peer, let theirs = callSeed, !theirs.isEmpty, theirs != self.callSeed?.base64EncodedString(),
               state == "connected" || state == "reconnecting" || (state == "active" && !wantAccept), youngerThanOurs,
               !(ts.map { Double($0) < (MontanaWakePush.nodeNow() - MontanaCall.callLifeS) * 1000 } ?? false) {
                MontanaP2PTrace.mark("call_superseded", "state=\(state) mine=\(String((self.callSeed?.base64EncodedString() ?? "-").prefix(8))) theirs=\(String(theirs.prefix(8)))")
                endSignalSent = true    // no farewell: it would end the call that supersedes this one
                endReason = "superseded"
                cleanup()
                handleSignalBody(from: from, device: device, ctrl: "call", sdp: sdp, candidate: nil,
                                 video: video, caps: caps, callSeed: callSeed, ts: ts, candidates: nil,
                                 name: name, glyph: glyph)
                return
            }
            // Duplicate offer of the CURRENT call (the offer travels by both the ring and the queue — the queue copy
            // may arrive after acceptance): silently ignore, otherwise the busy/stale branch sends
            // call-end and drops a live call. [critic-289: blocker]
            if from == peer, state != "idle", pendingOffer != nil { endPushPosted(); return }   // duplicate ONLY if the offer is already in hand; an empty pendingOffer = this is the real offer from the queue, accept it
            // Expired offer (sat in the queue while the phone had no network) — don't ring.
            // The age is judged by the NODE's clock on both ends (K-11): judging a peer's
            // stamp by our own clock made a phone with a skewed clock unable to call anyone.
            if let ts, Double(ts) < (MontanaWakePush.nodeNow() - MontanaCall.callLifeS) * 1000 {
                // EVERY RULE THAT ENDS OR REFUSES A CALL SAYS SO IN THE DIARY (13.09: a tester's phone
                // ended two incoming calls half a second after the offer, and no line named the rule).
                MontanaP2PTrace.mark("call_refused", "expired age_s=\(Int(MontanaWakePush.nodeNow() - Double(ts) / 1000)) state=\(state)")
                var es = CallSignalOut(ctrl: "call-end"); es.targetDevice = device
                es.epoch = callSeed.map { String($0.prefix(16)) }   // the refused call's name -- ours would be STALE at the caller (K-2)
                sendSignal?(from, es); endPushPosted(); return
            }
            // THE LIVE CALL IS SOVEREIGN: a stranger's invitation must not touch its state.
            // These writes stood BEFORE the busy guard, so a third phone calling in poisoned
            // peerDevice and callSeed of the call IN PROGRESS — the farewell then left under
            // the stranger's epoch to the stranger's device, and the peer buried it as STALE
            // and hung 25s in reconnecting (measured 15:44:35.758: STALE epoch=DUMAEqPf
            // my=qEP43fE1). The writes now live ONLY in the branches that accept the call.
            if (state == "incoming" || (state == "active" && wantAccept)) && peer == from {
                adoptCallerName(from, name, glyph)   // the word is accepted as the call in hand — now it names its caller
                self.peerDevice = device
                self.peerPremium = (caps?.tier == "ios-native" && caps?.sframe == true)
                self.learnPeerCaps(caps)
                if let cs = callSeed, let d = Data(base64Encoded: cs) { self.callSeed = d }
                if let s = sdp { self.pendingOffer = s; MontanaWakeDoor.note("offer") }
                // A late video offer upgrades the already-ringing call to video: the bare
                // wake may have raised it as audio, and the screen must catch up with the
                // truth. The offer's m=video is the primary sign; the flag is the fallback.
                let sdpVideo = (sdp?.sdp.contains("m=video") == true)
                if (sdpVideo || video == true), !self.isVideo {
                    self.isVideo = true
                    self.applyScreenHold()
                    DispatchQueue.main.async { CallUIModel.shared.video = true }
                    self.ensureLocalVideoTrack()
                    if let u = self.callUUID {
                        let upd = CXCallUpdate(); upd.hasVideo = true
                        self.provider.reportCall(with: u, updated: upd)
                    }
                }
                tlog("② offer received from queue (hasOffer now true)")
                if !wantAccept { prewarmIncoming() }   // no.4; on wantAccept it builds acceptCall — don't compete
                var rs = CallSignalOut(ctrl: "call-ringing"); rs.targetDevice = device
                sendSignal?(from, rs)   // confirm to the caller: the phone is ringing
                if wantAccept { acceptCall() }   // accepted BEFORE the offer — the offer arrived, build (acceptCall will reset wantAccept itself)
                return
            }
            // MUTUAL DIAL (glare): both pressed «call» at once. Each side used to answer the
            // counter-call with call-end, and each call-end killed the OTHER side's outgoing —
            // both calls died within a second, neither person understood why. The tie-break is
            // deterministic and computed identically on both phones from the two seeds both
            // know: the call whose seed string is smaller SURVIVES; the other caller yields —
            // silently folds its own dial (no farewell: the surviving call must live) and
            // adopts the counter-call as an ordinary incoming. An old build on the far side
            // keeps its old call-end road — no worse than before for mixed pairs.
            if from == peer, state == "outgoing" {
                let mine = self.callSeed?.base64EncodedString() ?? ""
                let theirs = callSeed ?? ""
                if !theirs.isEmpty, !mine.isEmpty, theirs < mine {
                    MontanaP2PTrace.mark("call_glare", "yield mine=\(String(mine.prefix(8))) theirs=\(String(theirs.prefix(8)))")
                    endSignalSent = true    // fold silently — a call-end would kill the surviving call
                    startedAt = nil         // no «missed outgoing» letter: the talk continues as their call
                    endReason = "glare-yield"
                    cleanup()
                    handleSignalBody(from: from, device: device, ctrl: "call", sdp: sdp, candidate: nil,
                                     video: video, caps: caps, callSeed: callSeed, ts: ts, candidates: nil,
                                     name: name, glyph: glyph)
                } else {
                    MontanaP2PTrace.mark("call_glare", "hold-course mine=\(String(mine.prefix(8))) theirs=\(String(theirs.prefix(8)))")
                    // our dial survives; their side yields by the same rule — nothing is sent
                }
                return
            }
            guard state == "idle" else {
                if from != peer {
                    // 12.2: the stranger's invitation becomes the ringing second line; its
                    // details live in second* fields ONLY — the live call is sovereign.
                    adoptCallerName(from, name, glyph)   // a stranger's accepted invitation names the stranger
                    postSecondLine(from: from, video: (sdp?.sdp.contains("m=video") == true) || video == true)
                    secondDevice = device
                    if let cs = callSeed { secondSeed = cs }
                    if let s = sdp { secondOffer = s }
                    var rs = CallSignalOut(ctrl: "call-ringing"); rs.targetDevice = device
                    rs.epoch = secondCallEpoch   // the second call's name, not the call in hand's (K-2)
                    sendSignal?(from, rs)   // the caller hears ringing; their offer resends stop
                    return
                }
                MontanaP2PTrace.mark("call_refused", "busy state=\(state) same_peer=1")
                var bs = CallSignalOut(ctrl: "call-end"); bs.targetDevice = device
                bs.epoch = callSeed.map { String($0.prefix(16)) }   // the refused call's name (K-2)
                sendSignal?(from, bs); endPushPosted(); return
            }
            // A CALL IS BORN OF A SEED ONLY (13.09): the seed is the call's one name across the
            // three roads — the graveyard, the copies, the epoch all stand on it. A word without
            // one is an offer for a call already in hand: kept aside, adopted by the seeded birth.
            guard let bornSeed = callSeed, !bornSeed.isEmpty else {
                if let s = sdp { seedlessOffer = (from, s, video ?? false, caps, Date()) }
                MontanaP2PTrace.mark("call_refused", "seedless from=\(String(from.prefix(10))) parked=\(sdp == nil ? 0 : 1)")
                endPushPosted(); return
            }
            adoptCallerName(from, name, glyph)   // the incoming call is born — its caller is named here, before the screen
            self.peerDevice = device
            self.peerPremium = (caps?.tier == "ios-native" && caps?.sframe == true)
            if caps?.av == true { self.peerReadsVoipAnswer = true }
            self.peerRebuilds = caps?.rejoin == true
            if let cs = callSeed, let d = Data(base64Encoded: cs) { self.callSeed = d }
            self.peer = from; self.isVideo = video ?? false
            self.isInitiator = false; self.pendingIce = []; self.iceHeldForPeerWord = false; self.restartAskedAt = .distantPast; self.setupAsks = 0; self.askedRelayOnly = false; self.lastIce = "new"; self.rebuiltInPlace = false
            self.startedAt = Date(); self.connectedAt = nil; self.answeredAt = nil
            self.ended = false; self.endSignalSent = false; self.declinedByMe = false; self.answeredByMe = false; self.endReason = "-"; self.endDoor = "-"
            self.cameraDeniedTold = false
            if let s = sdp { self.pendingOffer = s }
            if self.pendingOffer == nil, let so = seedlessOffer, so.from == from,
               Date().timeIntervalSince(so.at) < MontanaCall.callLifeS {
                self.pendingOffer = so.sdp
                if so.video { self.isVideo = true }
                self.peerPremium = (so.caps?.tier == "ios-native" && so.caps?.sframe == true)
                self.learnPeerCaps(so.caps)
                MontanaP2PTrace.mark("call_adopt", "parked seedless offer age_s=\(Int(Date().timeIntervalSince(so.at)))")
            }
            seedlessOffer = nil
            MontanaCall.dropBell(bornSeed)   // the native ring is the one face now — the bell banner leaves
            let uuid = self.pushPostedUUID ?? UUID(); self.callUUID = uuid
            callT0 = Date(); iceGenCount = 0; firstMediaLogged = false; firstVideoIn = false
            beginBackgroundHold()
            setState("incoming")
            if self.pushPostedUUID == nil {
                reportIncoming(uuid: uuid, from: from, video: self.isVideo)
            } else if self.isVideo, let u = self.callUUID {
                // Adopted: posted before the envelope told video — the screen catches up.
                self.pushPostedUUID = nil
                let upd = CXCallUpdate(); upd.hasVideo = true
                self.provider.reportCall(with: u, updated: upd)
            } else {
                self.pushPostedUUID = nil
            }
            Self.noteRingPosted(false)   // adopted: the ring is the machine's now, and the machine has a state
            var rs2 = CallSignalOut(ctrl: "call-ringing"); rs2.targetDevice = device
            sendSignal?(from, rs2)   // confirm to the caller: the phone is ringing
            // THE WARM-UP IS CALLED RIGHT HERE. The branch that GIVES BIRTH to an incoming call did
            // not call it: when the offer arrived as the first envelope, the connection was built
            // only after the person touched accept, and everything -- the node request, gathering
            // candidates, path checks -- happened under their wait (measured: 9.6 s to path checks).
            if let s = sdp { adoptVideoFromOffer(s) }   // video is decided by the OFFER, not by an envelope flag
            prewarmIncoming()
        case "call-ringing":
            guard !unreachable, from == peer else { break }
            tlog("received call-ringing (peer's phone is ringing)")
            peerRinging = true; reachTimer?.invalidate(); reachTimer = nil
            releaseHeldIce("ringing")   // the call is born over there: the candidates may leave now
            // The peer rings: the ring letter has done its work. Left in the queue it was re-sent
            // thirty seconds later for want of a receipt — and came back as an echo (12.09).
            if let p = peer { MontanaDeliveryEngine.shared.cancelRing(to: p) }
            MontanaP2PTrace.mark("call_tone", "ringback ms=\(Int(Date().timeIntervalSince(startedAt ?? Date())*1000))")
            stopDialTone(); startRingback()   // the ear switches with the fact: searching pips -> the peer's phone rings
            DispatchQueue.main.async { CallUIModel.shared.peerRinging = true }
        case "call-answer":
            E2E.shared.callDebug("cer call-answer: from=\(MontanaConv.short(from)) state=\(state) hasPC=\(pc != nil) hasRemote=\(pc?.remoteDescription != nil) sdp=\(sdp?.sdp.count ?? -1)b")
            if answeredAt == nil { answeredAt = Date() }   // the far hand answered: from here the road alone is on the clock
            guard let s = sdp else { return }
            releaseHeldIce("answer")   // a peer that never said «ringing» is surely born by its answer
            // The description is already handed to the machine by the fast path above; here -- paperwork only.
            if !answerFastAppliedNow {
                guard pc?.remoteDescription == nil else { return }
            }
            self.peerDevice = device   // from now on we signal addressed to this device
            reachTimer?.invalidate(); reachTimer = nil
            self.peerPremium = (caps?.tier == "ios-native" && caps?.sframe == true)
            self.learnPeerCaps(caps)
            // Ringback keeps playing through the connecting phase (until ICE connected) — the caller
            // hears the tone the whole attempt, so a silent "Connecting…" never reads as a freeze.
            DispatchQueue.main.async { CallUIModel.shared.connecting = true }
            if answerFastAppliedNow { return }   // the description is applied, the paperwork is done above
            let rd = RTCSessionDescription(type: .answer, sdp: s.sdp)
            MontanaP2PTrace.mark("sdp_in", "answer-slow ms=\(Int(Date().timeIntervalSince(startedAt ?? Date())*1000)) bytes=\(s.sdp.count)")
            pc?.setRemoteDescription(rd) { [weak self] err in
                guard let self else { return }
                if let err {
                    // The peer's answer was refused — the connection can no longer happen by
                    // any path. The refusal used to go unrecorded and the call hung silently
                    // until the hard timeout: a person watched "Connecting…" for a quarter of
                    // a minute and never learned the cause.
                    self.tlog("peer answer refused: \(err.localizedDescription) — the call cannot proceed")
                    self.endByRule("answer-refused")
                    return
                }
                // The answer is applied (possibly late — the network revived after an LTE stall):
                // give ICE a full 60s from THIS moment, rather than finishing on the old timer.
                self.armHardTimeout()
                self.tlog("answer applied → hard-timeout restarted (60s)")
                self.flushIce(); self.maybeEnableSframe()
            }
        case "call-ice":
            let batch = (candidates ?? []) + (candidate.map { [$0] } ?? [])
            guard !batch.isEmpty else { return }
            if !remoteIceSeenNow { tlog("first remote ICE candidates received (\(batch.count))") }
            var kinds: [String: Int] = [:]
            for c in batch { kinds[Self.candidateKind(c.candidate), default: 0] += 1 }
            MontanaP2PTrace.mark("ice_rx", "n=\(batch.count) types=\(Self.foldKinds(kinds)) applied=\(pc?.remoteDescription != nil ? 1 : 0)")
            markRemoteIceSeen()
            for c in batch {
                let ice = RTCIceCandidate(sdp: c.candidate, sdpMLineIndex: c.sdpMLineIndex ?? 0, sdpMid: c.sdpMid)
                if pc?.remoteDescription != nil { pc?.add(ice) { _ in } } else { stashIce(ice) }
            }
        case "call-key":
            // the SFrame media key arrived over the E2E ratchet (signalling travels the mesh queue in the clear)
            if from == peer, let cs = callSeed, let d = Data(base64Encoded: cs) {
                self.callSeed = d
                sframeAuthorized = true
                maybeEnableSframe()
                var ok = CallSignalOut(ctrl: "call-key-ok"); ok.targetDevice = device
                sendSignal?(from, ok)   // confirm to the caller: we have the key, enable frame encryption
            }
        case "call-key-ok":
            if from == peer { sframeAuthorized = true; maybeEnableSframe() }
        case "call-restart":
            // A mid-call re-offer: fresh ICE ("ice") or a video/screen renegotiation ("media").
            guard from == peer, let s = sdp, let pcx = pc else { return }
            // A RESTART WORD OF ANOTHER CONNECTION IS BURIED (24.09, iPhone 15 10:03:24Z): the peer's dead connection kept
            // asking for fresh checks, and its asks were read as a glare against a younger call. A connection's name is its
            // certificate: an offer whose fingerprint is not the one this connection holds for the peer -- or one that comes
            // before this connection holds the peer's description at all -- belongs to another connection.
            guard let held = pcx.remoteDescription?.sdp, Self.fingerprint(held) == Self.fingerprint(s.sdp) else {
                MontanaP2PTrace.mark("call_ice", "restart offer of another connection — buried")
                return
            }
            if s.sdp == seenRestartOffer {
                MontanaP2PTrace.mark("call_ice", "restart offer dup — buried")   // the second road's copy
                return
            }
            seenRestartOffer = s.sdp
            MontanaP2PTrace.mark("call_ice", "restart offer rx rsn=\(reason ?? "-")")
            let answerTheirOffer: () -> Void = { [weak self] in
                guard let self else { return }
                let mc = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
                self.pc?.answer(for: mc) { desc, _ in
                    guard let desc else { return }
                    let tuned = RTCSessionDescription(type: desc.type, sdp: self.tuneSDP(desc.sdp, premium: self.peerPremium))
                    self.pc?.setLocalDescription(tuned) { lerr in
                        guard lerr == nil else { return }
                        var ans = CallSignalOut(ctrl: "call-restart-answer",
                                                sdp: CallSDP(type: "answer", sdp: tuned.sdp))
                        ans.targetDevice = device.isEmpty ? self.peerDevice : device
                        // The accepted consent joins HERE: the asker's offer arrives every round,
                        // unlike didAdd which rings once per call. Only while FRESH and only on a
                        // MEDIA offer — an ICE restart minutes later must not raise the camera (K-6).
                        if self.videoConsentFresh, reason != "ice" {
                            self.videoAcceptArmed = false
                            DispatchQueue.main.async { self.enableMyVideo() }
                        }
                        self.sendSignal?(from, ans)
                        MontanaP2PTrace.mark("call_ice", "restart answer sent")
                    }
                }
            }
            pcx.setRemoteDescription(RTCSessionDescription(type: .offer, sdp: s.sdp)) { [weak self] err in
                guard let self else { return }
                guard let err else { answerTheirOffer(); return }
                // GLARE: both sides offered at once (mutual video consent — both pressed Accept).
                // The refusal used to be final: no retry road exists for a media offer, and the
                // call froze with both consents granted and no video (critic K-5). The callee
                // yields by construction: rolls its own offer back and answers the caller's —
                // the track it already added rides that very answer, one round, both cameras.
                // The ICE restart glared the same way (22:48:43, both phones off one Wi-Fi in one second,
                // both offered, both refused, the pictures froze and the hand hung up): the callee
                // yields on EVERY restart offer; the camera consent below still fires on media only.
                if !self.isInitiator, pcx.signalingState == .haveLocalOffer {
                    MontanaP2PTrace.mark("call_ice", "\(reason == "ice" ? "ice" : "media") glare — callee rolls back and answers")
                    pcx.setLocalDescription(RTCSessionDescription(type: .rollback, sdp: "")) { rerr in
                        guard rerr == nil else {
                            MontanaP2PTrace.mark("call_ice", "rollback refused err=\(rerr?.localizedDescription ?? "?")")
                            return
                        }
                        pcx.setRemoteDescription(RTCSessionDescription(type: .offer, sdp: s.sdp)) { e2 in
                            guard e2 == nil else {
                                MontanaP2PTrace.mark("call_ice", "restart offer refused after rollback err=\(e2?.localizedDescription ?? "?")")
                                return
                            }
                            answerTheirOffer()
                        }
                    }
                    return
                }
                if self.isInitiator, pcx.signalingState == .haveLocalOffer {
                    // The caller keeps its own offer in a glare: the callee rolls back and answers it.
                    MontanaP2PTrace.mark("call_ice", "\(reason == "ice" ? "ice" : "media") glare — the caller keeps its own, the callee yields")
                    return
                }
                MontanaP2PTrace.mark("call_ice", "restart offer refused err=\(err.localizedDescription)")
            }
        case "call-restart-answer":
            guard from == peer, let s = sdp, let pcx = pc else { return }
            guard let held = pcx.remoteDescription?.sdp, Self.fingerprint(held) == Self.fingerprint(s.sdp) else {
                MontanaP2PTrace.mark("call_ice", "restart answer of another connection — buried")
                return
            }
            if s.sdp == seenRestartAnswer {
                MontanaP2PTrace.mark("call_ice", "restart answer dup — buried")
                return
            }
            seenRestartAnswer = s.sdp
            guard pcx.signalingState == .haveLocalOffer else {
                MontanaP2PTrace.mark("call_ice", "restart answer with no offer open — buried")
                return
            }
            pcx.setRemoteDescription(RTCSessionDescription(type: .answer, sdp: s.sdp)) { err in
                MontanaP2PTrace.mark("call_ice", "restart answer applied ok=\(err == nil ? 1 : 0)")
            }
        case "call-video-end":
            guard from == peer else { return }
            MontanaP2PTrace.mark("call_video", "peer ended video mode")
            DispatchQueue.main.async { self.dropVideoMode(tellPeer: false) }
        case "call-video-ask":
            guard from == peer else { return }
            MontanaP2PTrace.mark("call_video", "consent asked by peer")
            DispatchQueue.main.async { CallUIModel.shared.videoAskIncoming = true }
        case "call-video-ok":
            guard from == peer else { return }
            MontanaP2PTrace.mark("call_video", "consent granted")
            videoAskTimer?.invalidate(); videoAskTimer = nil
            DispatchQueue.main.async {
                if CallUIModel.shared.videoAskPending {
                    CallUIModel.shared.videoAskPending = false
                    self.upgradeToVideo()
                }
            }
        case "call-video-no":
            guard from == peer else { return }
            MontanaP2PTrace.mark("call_video", "consent declined")
            videoAskTimer?.invalidate(); videoAskTimer = nil
            DispatchQueue.main.async {
                CallUIModel.shared.videoAskPending = false
            }
        case "call-screen-on":
            guard from == peer else { return }
            peerShareGrewVideo = !isVideo
            // a repeated share in the same call: didAdd will not fire again —
            // the standing receiver hands the track back
            if remoteVideoTrack == nil {
                remoteVideoTrack = pc?.receivers.compactMap { $0.track as? RTCVideoTrack }.first
            }
            if remoteVideoTrack != nil, !isVideo {
                isVideo = true
                applyScreenHold()
                DispatchQueue.main.async { CallUIModel.shared.video = true; CallUIModel.shared.tick += 1 }
            }
            MontanaP2PTrace.mark("call_screen", "peer sharing on grew=\(peerShareGrewVideo ? 1 : 0)")
            DispatchQueue.main.async { CallUIModel.shared.peerSharing = true }
        case "call-screen-off":
            guard from == peer else { return }
            let backToAudio = video == false || (video == nil && peerShareGrewVideo)
            MontanaP2PTrace.mark("call_screen", "peer sharing off audio=\(backToAudio ? 1 : 0) word=\(video == nil ? "nil" : String(video == false))")
            if backToAudio {
                peerShareGrewVideo = false
                isVideo = false
                updateProximity()
                remoteVideoTrack = nil   // recovered from the standing receiver on the next share
                if let u = callUUID {
                    let upd = CXCallUpdate(); upd.hasVideo = false
                    provider.reportCall(with: u, updated: upd)
                }
                DispatchQueue.main.async {
                    CallUIModel.shared.video = false
                    CallUIModel.shared.videoAsk = false
                    CallUIModel.shared.tick += 1
                }
            }
            DispatchQueue.main.async { CallUIModel.shared.peerSharing = false }
        case "call-hold":
            guard from == peer else { return }
            MontanaP2PTrace.mark("call_hold", "held by peer")
            DispatchQueue.main.async { CallUIModel.shared.heldByPeer = true }
        case "call-resume":
            guard from == peer else { return }
            MontanaP2PTrace.mark("call_hold", "peer resumed")
            DispatchQueue.main.async { CallUIModel.shared.heldByPeer = false }
        case "call-gone":
            // THE PEER HOLDS NO SUCH CALL (24.09): their phone came back without it — iOS ends an app whose person
            // changes a privacy switch in Settings — and answered our ask for fresh checks with the truth. This side
            // used to stay «reconnecting» until its own deadline, revived meanwhile by any byte on the path. The word
            // names the call's epoch on every road: a word about another call ends nothing.
            guard from == peer, state != "idle", let ep = callSeed, !ep.isEmpty, ep == callEpoch else { return }
            MontanaP2PTrace.mark("call_gone", "rx state=\(state) epoch=\(String(ep.prefix(8)))")
            if endReason == "-" { endReason = "peer-gone" }
            endCall(silent: true)
        case "call-end":
            if let pk = parked, from == pk.peer {
                tlog("the parked call's peer hung up")
                tearParked(reason: .remoteEnded)
                return
            }
            if let sf = secondFrom, from == sf {
                tlog("second line: the caller hung up")
                MontanaCall.burySeed(secondSeed)
                clearSecond(report: .remoteEnded)
                return
            }
            guard peer == nil || from == peer else { return }   // a stranger cannot end the live call
            // AN END WORD AFTER THE END ENDS NOTHING (23.09): the peer's call-end rides every road, and the copies that
            // landed after our machine rested wrote «⑧ endCall -- teardown initiated» three times over an idle machine
            // (T1 18:34:52, 18:49:58, 18:55:02) and named the reason of the NEXT call. Only a ring a push raised still
            // stands for such a word; with nothing standing it is one line and nothing more.
            if state == "idle", pushPostedUUID == nil, callUUID == nil {
                MontanaP2PTrace.markFolded("call_end_rx", "after the end -- nothing stands", window: 10)
                return
            }
            tlog("received call-end from \(MontanaConv.short(from)) (peer ended)")
            MontanaP2PTrace.mark("call_end_rx", "state=\(state) connected=\(connectedAt == nil ? 0 : 1)")
            if endReason == "-" { endReason = "peer-ended" }   // the far hand or the far rule, not ours
            endCall(silent: true)
        default: break
        }
    }

    private var pendingOffer: CallSDP?
    /// A «call» word that came without a seed (the pipe copy of an old build's offer, ahead of
    /// the wake): it births nothing, it waits here for the seeded birth of the same call.
    private var seedlessOffer: (from: String, sdp: CallSDP, video: Bool, caps: CallCaps?, at: Date)?
    private var wantAccept = false

    // Accept from OUR in-app incoming screen: route through CallKit so the system state,
    // audio session and the receiver stopwatch stay in sync (same as tapping the native UI).
    func muteFromUI(_ muted: Bool) {
        guard let u = callUUID else { toggleMute(muted); return }
        callController.request(CXTransaction(action: CXSetMutedCallAction(call: u, muted: muted))) { [weak self] err in
            guard err != nil else { return }   // ok-path: provider(perform: CXSetMutedCallAction) mutes
            DispatchQueue.main.async { self?.toggleMute(muted) }   // CallKit refused — mute directly
        }
    }

    func holdFromUI() {
        if parked != nil { swapWithParked(); return }   // one button: hold — or swap the two lines
        guard let u = callUUID else { return }
        let on = !softHeld   // the machine's record, not the async UI mirror (K-10)
        callController.request(CXTransaction(action: CXSetHeldCallAction(call: u, onHold: on))) { [weak self] err in
            guard err != nil else { return }
            DispatchQueue.main.async { self?.softHold(on) }   // CallKit refused — hold directly
        }
    }

    func answerFromUI() {
        guard state == "incoming", let uuid = callUUID else { return }
        callController.request(CXTransaction(action: CXAnswerCallAction(call: uuid))) { [weak self] err in
            guard err != nil else { return }
            DispatchQueue.main.async { self?.acceptCall() }   // CallKit refused — accept directly (audio self-activates)
        }
    }

    func acceptCall() {
        answeredByMe = true
        if answeredAt == nil {
            answeredAt = Date()
            MontanaP2PTrace.mark("call_accept", "ms=\(Int(Date().timeIntervalSince(startedAt ?? Date()) * 1000))")
        }
        tlog("③ acceptCall pressed hasOffer=\(pendingOffer != nil) st=\(state)")
        // Accepted on a dropped call (state=idle, but the CallKit oval still hangs) — don't stay silent:
        // dismiss the orphaned CallKit, otherwise the green oval hangs, the screen is empty. [bug: empty screen]
        guard state == "incoming" || (state == "active" && wantAccept) else {
            if state == "idle" { endCall(silent: true) }
            return
        }
        guard let peer = peer else { return }
        if state == "incoming" { setState("active") }   // call screen visible IMMEDIATELY ("Connecting…"), not empty incoming
        guard let off = pendingOffer else {
            wantAccept = true
            // The offer is still traveling (bare ring without SDP / queue). 15 s and we honestly end.
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
                guard let self, self.wantAccept, self.pc == nil else { return }
                E2ELog.write("call: offer didn't arrive within 15s after Accept — ending")
                self.endByRule("offer-missing")
            }
            return
        }
        wantAccept = false
        proceedAccept(peer: peer, offer: off)
    }

    private func proceedAccept(peer: String, offer off: CallSDP) {
        adoptVideoFromOffer(off)   // before any building: the offer decides whether this is video
        if isVideo { ensureCameraAccess { [weak self] ok in if ok { self?.pushCaptureUntilRunning() } } }
        Task { @MainActor in   // K-1: the machine's fields are the owner thread's
            configureAudioSession()
            if prewarming {   // prewarm in flight — wait for it, do NOT build a second pc (double-buildPC race)
                for _ in 0..<30 where prewarming { try? await Task.sleep(nanoseconds: 100_000_000) }
                tlog("④ waited for in-flight prewarm pc=\(pc != nil)")
            }
            if pc == nil {   // prewarm didn't happen/failed — build now
                await buildPC()
                tlog("④ buildPC on accept (no prewarm)")
            }
            // Two different outcomes used to share one silent exit. The call was cancelled
            // while the connection was being built — leaving quietly is right. The connection
            // FAILED TO BUILD is another thing entirely: the screen stays "active", there is
            // no sound and no exit, and the person stares at a call that does not exist.
            guard state == "active" else { return }
            guard pc != nil else {
                tlog("the connection did not build — nothing to accept the call with")
                endByRule("connection-unbuilt")
                return
            }
            if pc?.remoteDescription == nil {
                let rd = RTCSessionDescription(type: .offer, sdp: off.sdp)
                pc?.setRemoteDescription(rd) { [weak self] rderr in
                    guard let self else { return }
                    E2E.shared.callDebug("cee accept: setRemote err=\(rderr?.localizedDescription ?? "nil")")
                    // The peer's offer was refused — there is nothing to answer. The answer
                    // used to be built and sent anyway: the peer raised ICE checks that could
                    // never converge and listened to silence for a minute.
                    if let rderr {
                        self.tlog("peer offer refused: \(rderr.localizedDescription)")
                        self.endByRule("offer-refused")
                        return
                    }
                    self.flushIce()
                    self.produceAndSendAnswer(peer: peer)
                }
            } else {
                tlog("④ pc prewarmed under ringtone — answer immediately")   // buildPC+setRemote already done
                produceAndSendAnswer(peer: peer)
            }
            armHardTimeout()
        }
    }

    private func produceAndSendAnswer(peer: String) {
        // THE ANSWER DOES NOT WAIT FOR THE CAMERA. Measured at three points: the offer arrived in
        // 0.7 s, and the caller began path checks only ten seconds later -- all that time the callee
        // held the answer while raising capture. The video line already exists in the offer, so the
        // answer is built at once and the track enters a ready line when the camera arrives: the peer
        // sees a black frame for the same seconds as before, but the connection stands up immediately.
        if isVideo, let tr = pc?.transceivers.first(where: { $0.mediaType == .video }) {
            tr.setDirection(.sendRecv, error: nil)   // the place for our picture is taken in advance
        }
        MontanaP2PTrace.mark("call_answer", "build ms=\(Int(Date().timeIntervalSince(startedAt ?? Date())*1000))")
        let mc = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        pc?.answer(for: mc) { [weak self] desc, aerr in
            guard let self else { return }
            E2E.shared.callDebug("cee accept: answer desc=\(desc != nil) err=\(aerr?.localizedDescription ?? "nil")")
            guard let desc else {
                // The answer did not build — the critical path is severed. This used to be a
                // silent exit, and the call hung "active" until the minute-long hard timeout.
                self.tlog("the answer did not build — the call cannot proceed")
                self.endByRule("answer-unbuilt")
                return
            }
            let tuned = RTCSessionDescription(type: desc.type, sdp: self.tuneSDP(desc.sdp, premium: self.peerPremium))
            self.pc?.setLocalDescription(tuned) { lerr in
                E2E.shared.callDebug("cee accept: setLocal err=\(lerr?.localizedDescription ?? "nil") → send call-answer dev=\(self.peerDevice ?? "nil")")
                // A refusal to accept one's OWN description used to be merely logged while
                // the answer went out regardless: the peer received a full answer, raised ICE
                // checks that could not converge, and listened to a minute of silence. An
                // answer without an accepted description is not an answer; the truth is told
                // now, not after a minute of dead air.
                if let lerr {
                    self.tlog("own description refused: \(lerr.localizedDescription) — the answer is not sent")
                    self.endByRule("answer-refused-here")
                    return
                }
                self.boostVideo()
                self.maybeEnableSframe()
                var ans = CallSignalOut(ctrl: "call-answer",
                                        sdp: CallSDP(type: "answer", sdp: tuned.sdp), caps: self.myCaps())
                ans.targetDevice = self.peerDevice   // addressed delivery to the known peer device
                // THE ANSWER TAKES THE ROAD THE INVITATION CAME BY (13.09, measured on a call to a
                // phone on cellular under a tunnel): the invitation rides inside the wake and is in
                // hand the instant the phone stirs, while the answer waited for a lane this phone
                // still had to build from nothing — dead sockets after sleep, TCP and the cipher
                // handshake to two doors, a second of the person's life on every such call. The wake
                // road needs none of that. The lane copy goes out all the same: two roads, whichever
                // arrives first wins, and the caller buries the second by the call's own name.
                if self.peerReadsVoipAnswer, let seed = self.callSeed?.base64EncodedString() {
                    MontanaWakePush.wakeVoip(peer, callSeed: seed, answer: tuned.sdp)
                }
                self.sendSignal?(peer, ans)
                MontanaP2PTrace.mark("call_answer", "sent")
        // THE ANSWER RINGS THE DOORBELL. The caller waits for the answer with a dark screen, and the
        // system may put them to sleep: a wake holder is not always granted, and the call system wakes
        // the app only when sound arrives, and there is none before the answer. Measured: the answer
        // reached the node in one hundred and eighty milliseconds and LAY there eight seconds until an
        // unrelated letter woke the sleeper. Now the answer wakes them itself -- by the same doorbell
        // with which the invitation woke the callee.
        if let bellPeer = self.peer, !bellPeer.isEmpty {
            let tag = String((self.callSeed?.base64EncodedString() ?? "x").prefix(12))
            MontanaWakePush.wake(bellPeer, mid: "ans-" + tag, sealedEnvelopeB64: nil, silent: true) { code in
                MontanaP2PTrace.mark("answer_bell", "code=\(code)")
                // A refused bell is rung once more two seconds later: the node's minute window
                // and a dead lane both clear in that time, and the caller is still waiting.
                if code != 200 {
                    DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                        MontanaWakePush.wake(bellPeer, mid: "ans-" + tag + "r", sealedEnvelopeB64: nil, silent: true, recall: true) { c2 in
                            MontanaP2PTrace.mark("answer_bell", "retry code=\(c2)")
                        }
                    }
                }
            }
        }
                // The camera comes AFTER the answer: setting up capture takes seconds, and it was
                // exactly what held the answer. The track enters an already-built line.
                DispatchQueue.main.async { [weak self] in self?.ensureLocalVideoTrack() }
                // The answer travels over an unreliable transport — idempotent fan-out resend
                // every 2s until a real connection (criterion — connected, not remoteIceSeen).
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.answerResends = 0
                    self.answerResendTimer?.invalidate()
                    self.answerResendTimer = self.callTimer(2, repeats: true) { [weak self] t in
                        guard let self else { t.invalidate(); return }
                        self.answerResends += 1
                        // The same order for the answer: an oncoming candidate means the answer is
                        // applied, and there is nothing left to repeat.
                        if self.state == "connected" || self.state == "idle"
                            || self.remoteIceSeenNow || self.answerResends > 8 {
                            t.invalidate(); self.answerResendTimer = nil; return
                        }
                        var again = ans; again.targetDevice = nil   // fan-out: any device/transport of the caller
                        self.sendSignal?(peer, again)
                    }
                }
            }
        }
    }

    // Prewarm under the ringtone — buildPC + setRemote(offer) + early
    // caller candidates, WHILE the melody plays. Answer is NOT created (otherwise gathering/sending our
    // candidates and ICE checks would complete before picking up — the call would «connect» by itself).
    // On accept only createAnswer + setLocal remains (~100-300ms).
    private func prewarmIncoming() {
        guard state == "incoming", pc == nil, !prewarming, let off = pendingOffer else { return }
        // The video sign is read BEFORE the connection is built: otherwise it comes out
        // audio-only, and video cannot be added later — the answer carries only the offer's lines.
        adoptVideoFromOffer(off)
        prewarming = true
        Task { @MainActor [weak self] in   // K-1: the machine's fields are the owner thread's
            guard let self else { return }
            await self.buildPC()
            guard self.state == "incoming", self.pc != nil else { self.prewarming = false; return }
            let rd = RTCSessionDescription(type: .offer, sdp: off.sdp)
            self.pc?.setRemoteDescription(rd) { [weak self] err in
                guard let self else { return }
                self.prewarming = false
                self.tlog("prewarm: pc+setRemote ready under ringtone err=\(err?.localizedDescription ?? "nil")")
                self.flushIce()
            }
        }
    }

    private func sendEndSignal() {
        guard !endSignalSent, let p = peer else { return }
        endSignalSent = true
        var es = CallSignalOut(ctrl: "call-end"); es.targetDevice = peerDevice
        sendSignal?(p, es)
        if peerDevice == nil || peerDevice?.isEmpty == true {
            let fan = CallSignalOut(ctrl: "call-end")   // the peer device is unknown — fan-out
            sendSignal?(p, fan)
        }
    }

    /// ONE DOOR FOR A HAND'S END (23.09, the critic). The grid's End, the incoming Decline, the pill's
    /// red handset and the red handsets at a name and in a list row each called the teardown on their
    /// own, and the diary could not tell which of them a finger touched: the 13:21 end on the iPhone 15
    /// stood in the day as «hung-up» with no place. Every hand passes here and names its place; the
    /// word for the reason is one function (handReason) for this door and for the system's.
    func endByHand(_ origin: String) {
        guard Thread.isMainThread else { DispatchQueue.main.async { self.endByHand(origin) }; return }
        guard state != "idle" else { return }
        MontanaP2PTrace.mark("call_end_hand", "origin=\(origin) state=\(state) connected=\(connectedAt == nil ? 0 : 1) minimized=\(CallUIModel.shared.minimized ? 1 : 0)")
        // A Decline on our own ring is a decline even when the system's End transaction fails and the
        // teardown runs directly — it used to be set only inside the system's handler, and the direct
        // road logged the declined call as missed and raised the missed-call banner.
        if state == "incoming" { declinedByMe = true }
        if endReason == "-" { endReason = handReason(); endDoor = origin }
        endCall(silent: false)
    }

    /// A RULE'S END NAMES THE RULE (23.09). A refused description, an offer that never came, a
    /// connection that did not build went through the hand's road and the summary said «cancelled»
    /// or «hung-up» -- a person's hand where there was none.
    private func endByRule(_ why: String) {
        guard Thread.isMainThread else { DispatchQueue.main.async { self.endByRule(why) }; return }
        MontanaP2PTrace.mark("call_end_rule", "why=\(why) state=\(state) connected=\(connectedAt == nil ? 0 : 1)")
        if endReason == "-" { endReason = why; endDoor = "rule:" + why }
        if why == "no-path" { Self.tellNoRoad(filtered: MontanaNetProbe.filtersCalls) }
        endCall(silent: false)
    }

    /// Who closed the call, in one word, when a hand closed it: our End and the system's End read here.
    private func handReason() -> String {
        state == "incoming" ? "declined"
            : (connectedAt == nil ? (isInitiator && !peerRinging ? "cancelled-unrung" : "cancelled") : "hung-up")
    }

    private func endCall(silent: Bool) {
        // K-1: teardown belongs to the owner thread — refusal callbacks used to run it
        // straight on the WebRTC/signaling threads.
        guard Thread.isMainThread else { DispatchQueue.main.async { self.endCall(silent: silent) }; return }
        if endReason == "-" {
            // 12.11: who closed the call, in one word. «silent» is the peer's word; every other end
            // arrives named — by endByHand or endByRule — and this is only the belt.
            endReason = silent ? (state == "reconnecting" ? "lost" : "peer-or-rule") : handReason()
        }
        tlog("⑧ endCall(silent=\(silent)) — teardown initiated")
        if silent {
            // The remote side ended: dismiss directly (CXEndCallAction on an unanswered
            // incoming may not go through — CallKit kept ringing, bug «ringing on the second one»).
            endSignalSent = true
            if let uuid = callUUID {
                provider.reportCall(with: uuid, endedAt: nil, reason: unansweredIncoming ? .unanswered : .remoteEnded)
                endReportedUUID = uuid   // the teardown does not report it a second time
            }
            cleanup()
            return
        }
        sendEndSignal()
        if let uuid = callUUID {
            callController.request(CXTransaction(action: CXEndCallAction(call: uuid))) { [weak self] err in
                guard err != nil else { return }   // ok-path: provider(perform: CXEndCallAction) tears down
                // CallKit refused (stale/unregistered call object) — the End button must STILL end
                // the call: tear down directly, never leave the screen hanging.
                DispatchQueue.main.async {
                    guard let self, !self.ended else { return }
                    E2ELog.write("call: CXEndCallAction failed (\(err!.localizedDescription)) — direct teardown")
                    self.provider.reportCall(with: uuid, endedAt: Date(), reason: .remoteEnded)
                    self.endReportedUUID = uuid
                    self.cleanup()
                }
            }
            // Failsafe: if the transaction goes silent, the call may not outlive the button.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, !self.ended, self.state != "idle" else { return }
                E2ELog.write("call: end transaction silent for 2s — forcing teardown")
                if let u = self.callUUID { self.provider.reportCall(with: u, endedAt: Date(), reason: .remoteEnded); self.endReportedUUID = u }
                self.cleanup()
            }
        } else {
            cleanup()
        }
    }

    // -- the call graveyard: the seed of a finished call stays dead for 10 minutes ----------
    // A call invitation also travels by push: APNs may hand it over AFTER the hang-up (precedent
    // 19:09:13 -- the envelope arrived 9 s after the end, and CallKit rang anew). A real-time signal
    // whose time has passed has no right to light the screen.
    private static let deadSeedLock = NSLock()
    private static var deadSeeds: [String: Double] = [:]
    private static var deadSeedsLoaded = false
    // The graveyard is DURABLE: the missed-call letter lives in the sender queue for up to 7 days,
    // while a 10-minute memory forgot the buried on the very first restart -- every relaunch gave
    // birth to a duplicate call row (precedent 22.08). The term equals the queue term.
    private static func deadLoadLocked() {
        guard !deadSeedsLoaded else { return }
        deadSeedsLoaded = true
        if let d = MontanaLocalVault.getDecrypted("callDeadSeeds"),
           let m = try? JSONDecoder().decode([String: Double].self, from: d) {
            deadSeeds.merge(m) { a, _ in a }
        }
    }
    static func burySeed(_ s: String?) {
        guard let s, !s.isEmpty else { return }
        let now = Date().timeIntervalSince1970
        deadSeedLock.lock()   // LOCK-OK: the dead-seed set and its vault record change as one step
        deadLoadLocked()
        deadSeeds[s] = now
        deadSeeds = deadSeeds.filter { now - $0.value < 7 * 86400 }
        if let d = try? JSONEncoder().encode(deadSeeds) { _ = MontanaLocalVault.setEncrypted("callDeadSeeds", d) }
        deadSeedLock.unlock()
    }
    static func isDeadSeed(_ s: String?) -> Bool {
        guard let s, !s.isEmpty else { return false }
        deadSeedLock.lock(); defer { deadSeedLock.unlock() }
        deadLoadLocked()
        return deadSeeds[s] != nil
    }

    private func cleanup() {
        if ended { return }
        ended = true
        // No door may leave the summary without a reason. A door that did not name itself is
        // named by the state it came through — a fact, not a guess.
        if endReason == "-" { endReason = "unnamed-\(state)" }
        if Thread.isMainThread, powerStart != nil { powerLast = MontanaPower.snapshot() }   // the last reading at the end, for a voice call too
        stopRouteWatch(); routeDirty = false
        // The parked call SURVIVES the machine's teardown (critic K-8): ending the active
        // call — by hand, by timeout, by a failed second-line adoption — returns the held
        // call to the machine, still held, exactly as a phone does. It used to be buried
        // here with the active one: hold first, accept second, second fails — lose BOTH.
        let orphanParked = parked
        parked = nil
        // CONSENT LIVES FOR EXACTLY ONE CALL. The flag "the person pressed Accept before the offer
        // arrived" was cleared only on the happy branch: if the call did not come together, it
        // outlived the end and the NEXT incoming answered itself -- microphone and camera, no touch.
        wantAccept = false
        Self.noteRingPosted(false)   // no call, no standing ring — whatever raised it
        pushPostedUUID = nil         // the push's ring lives and ends with the call that took it (sweepSystemCalls reads it)
        MontanaCall.burySeed(callSeed?.base64EncodedString())
        // The end of a call also buries its invitation letter in the delivery queue: an unsent RG,
        // arriving later, would ring the person in the back.
        if let p = peer { MontanaDeliveryEngine.shared.cancelRing(to: p) }
        // PHANTOM FIX: guaranteed dismissal of the CallKit call, HOWEVER cleanup was invoked. Without this
        // CallKit hangs forever (a phantom call) if the path reached cleanup bypassing endCall
        // (ICE→failed/closed, timeout, late-ring race). Idempotent — a repeated end is harmless.
        // ONE END PER CALL (the critic 24.09): every end was reported twice -- the peer's end reported the call ended and
        // this line reported it again; our own End was reported here while the End action itself was still being performed,
        // and fulfilled after. The call whose end the system already holds is not reported again; every other road keeps
        // the guaranteed dismissal.
        if let uuid = callUUID, uuid != endReportedUUID {
            provider.reportCall(with: uuid, endedAt: Date(), reason: unansweredIncoming ? .unanswered : .remoteEnded)
        }
        lastEndedUUID = callUUID ?? lastEndedUUID
        endReportedUUID = nil
        let teardownStart = Date()
        let talkDur = connectedAt != nil ? Date().timeIntervalSince(connectedAt!) : 0
        tlog("⑨ cleanup start — talk \(String(format: "%.1f", talkDur))s")
        // call log before reset
        if let p = peer, let started = startedAt {
            let incoming = !isInitiator
            // «Missed» means the person never reacted. Answering a call whose offer then
            // failed to arrive is not a miss — the red banner over an answered call lied.
            let missed = connectedAt == nil && !(incoming && answeredByMe)
            let dur = connectedAt != nil ? Int(Date().timeIntervalSince(connectedAt!)) : 0
            _ = started
            let v = videoFramesSeen   // 15.7: the record names a picture that flowed, not a flag
            let declined = declinedByMe
            let seed = callSeed?.base64EncodedString()
            MontanaP2PTrace.mark("call_log", "fire peer=\(String(p.prefix(10))) dur=\(dur) missed=\(missed) wired=\(onCallLog != nil ? 1 : 0)")
            let rang = peerRinging || connectedAt != nil
            // A BIRTH THE SYSTEM REFUSED IS NO CALL OF THEIRS TO MISS (25.09): the far phone gets the row, quietly.
            let refused = endReason.hasPrefix("callkit-")
            DispatchQueue.main.async { self.onCallLog?(p, v, incoming, dur, missed, declined, seed, rang, refused) }
        } else {
            MontanaP2PTrace.mark("call_log", "SKIP peer-nil=\(peer == nil ? 1 : 0) started-nil=\(startedAt == nil ? 1 : 0)")
        }
        // 12.11 — ONE LINE PER CALL. Duration, how it was carried, how much of it rode a relay,
        // how many breaks and restarts it survived, how far the picture had to step down, and
        // why it ended. Encryption is named too: the transport pair is admission ([I-16] A-3/A-4,
        // a DoS class and never a breach), the content is held by the post-quantum frame layer
        // ([I-1]) — so a reader of the journal can tell «encrypted» from «encrypted by what».
        // A CALL THIS PROCESS NEVER HAD LEAVES NO SUMMARY (20.09): a relaunched app receiving the
        // peer's end word wrote «dir=in video=0 end=peer-ended» for a call it never ran — a second
        // incoming call in the day's journal that did not exist.
        if startedAt != nil {
            let dur = connectedAt != nil ? Int(Date().timeIntervalSince(connectedAt!)) : 0
            let setup = connectedAt != nil && startedAt != nil
                ? Int(connectedAt!.timeIntervalSince(startedAt!) * 1000) : -1
            let relayShare = sumSamples > 0 ? sumRelaySamples * 100 / sumSamples : -1
            let tunnelShare = sumSamples > 0 ? sumTunnelSamples * 100 / sumSamples : -1
            let rtt = sumRttN > 0 ? sumRttSum / sumRttN : -1
            let paths = sumPaths.isEmpty ? "-" : sumPaths.sorted().joined(separator: "+")
            let crypto = frameCryptors.isEmpty ? "dtls-srtp" : "dtls-srtp+sframe-pq"
            // The drain in the summary: the battery at the first tick and at the last, and from
            // them the percent an hour of this call — the number the author asked to see.
            let b0 = powerStart?.level ?? -1, b1 = powerLast?.level ?? -1
            // SETUP is the whole wait from the first touch to the media, ringing included; CONNECT is
            // the road alone — from the answering hand to the first path. Read apart, they tell a slow
            // road from a slow person (12.09: the week's «ICE tail» was people taking their time).
            let connect = (answeredAt != nil && connectedAt != nil) ? Int(connectedAt!.timeIntervalSince(answeredAt!) * 1000) : -1
            let ring = (answeredAt != nil && startedAt != nil) ? Int(answeredAt!.timeIntervalSince(startedAt!)) : -1
            let drain = (b0 >= 0 && b1 >= 0 && dur >= 60 && !(powerLast?.charging ?? false)) ? String(format: "%.1f", Double(b0 - b1) * 3600.0 / Double(dur)) : "-"
            MontanaP2PTrace.mark("call_summary",
                "dir=\(isInitiator ? "out" : "in") video=\(isVideo ? 1 : 0) setup_ms=\(setup) connect_ms=\(connect) ring_s=\(ring) rang=\(peerRinging ? 1 : 0) talk_s=\(dur) "
                + "paths=\(paths) relay_pct=\(relayShare) tun_pct=\(tunnelShare) rtt_avg=\(rtt) breaks=\(sumBreaks) "
                + "restarts=\(sumRestarts) ladder_min_step=\(sumLadderMin) video_lost_pkts=\(sumLostVideo) video_dark_s=\(sumVideoDarkS) "
                + "in_kb=\(sumInBytes / 1024) out_kb=\(sumOutBytes / 1024) crypto=\(crypto) end=\(endReason) "
                + "batt=\(b0)->\(b1) drain_pct_h=\(drain) thermal=\(powerLast.map { MontanaPower.thermalWord($0.thermal) } ?? "-") power_floor_max=\(sumPowerFloorMax) "
                + "knocks=\(knockN)/\(knockOk) first_ok_s=\(knockFirstOkS) last_ok_s=\(knockLastOkS) bell=\(bellRung ? 1 : 0) side=\(faultSide())")
            // THE END OF A CALL IS IN THE TELEMETRY TOO (25.09): the trace alone knew it, and the trace of T1's 19:07 call
            // from the car rotated away before it shipped -- the diary could not say whether the call had ended on the
            // phone while the car kept counting.
            // THE RING'S LEDGER RIDES THE DAY-LONG JOURNAL TOO (28.09, the 17:41 call the far phone never rang): the
            // trace held the knocks, the bell and the door, and the trace on a phone holds an hour and a half -- nine
            // hours later only this line was left, and it could say «side=apple» but not how many wakes Apple took,
            // whether our loud bell went out, or who closed a call that had not rung.
            MontanaLog.event("E2E-CALL end dir=\(isInitiator ? "out" : "in") video=\(isVideo ? 1 : 0) talk_s=\(dur) end=\(endReason) door=\(endDoor) "
                + "rang=\(peerRinging ? 1 : 0) knocks=\(knockN)/\(knockOk) first_ok_s=\(knockFirstOkS) bell=\(bellRung ? 1 : 0) "
                + "paths=\(paths) rtt_avg=\(rtt) breaks=\(sumBreaks) ice=\(lastIce) asks=\(setupAsks) relay_only=\(askedRelayOnly ? 1 : 0) "
                + "probe=\(MontanaNetProbe.verdictWord) side=\(faultSide())")
        }
        // THE COUNTERS BELONG TO ONE CALL. Measured 10.09 (62CC699C): two summaries in a row
        // carried the same rtt, lost and bytes — nothing reset them between calls.
        sumSamples = 0; sumRelaySamples = 0; sumPaths = []; sumBreaks = 0; sumRestarts = 0
        sumLadderMin = 0; sumRttSum = 0; sumRttN = 0; sumLostVideo = 0; sumInBytes = 0; sumOutBytes = 0
        sumVideoDarkS = 0; pictureSeen = [:]; answeredAt = nil
        powerFloor = 0; powerStart = nil; powerLast = nil; powerTicks = 0; sumPowerFloorMax = 0
        pathFloor = Self.modestStep; ladderStep = Self.modestStep; sumTunnelSamples = 0   // the next call proves its own pair
        stopRingback(); stopDialTone(); stopWaitingTone(); tonePlayer?.stop(); tonePlayer = nil; speech.stopSpeaking(at: .immediate)
        connectHardTimer?.invalidate(); connectHardTimer = nil
        reconnectTimer?.invalidate(); reconnectTimer = nil
        disconnectGrace?.invalidate(); disconnectGrace = nil; iceHeldForPeerWord = false; restartAskedAt = .distantPast; setupAsks = 0; askedRelayOnly = false; lastIce = "new"; rebuiltInPlace = false
        answerResendTimer?.invalidate(); answerResendTimer = nil; answerResends = 0
        offerResendTimer?.invalidate(); offerResendTimer = nil; offerResends = 0; pendingOfferSdp = nil
        prewarming = false; callGen += 1
        iceBatchTimer?.cancel(); iceBatchTimer = nil; iceOutBatch = []; iceFlushes = 0; resetSignalFlags(); audioUnitPending = false; videoReady = false; measuring = false
        measureGen += 1   // K-9: no tick of the ended call survives into the next one
        softHeld = false
        endBackgroundHold()
        if let a = pendingAnswerAction { pendingAnswerAction = nil; a.fulfill() }
        reachTimer?.invalidate(); reachTimer = nil
        videoAskTimer?.invalidate(); videoAskTimer = nil; videoAcceptArmed = false
        captureRetryTimer?.invalidate(); captureRetryTimer = nil
        captureObservers.forEach { NotificationCenter.default.removeObserver($0) }
        captureObservers.removeAll()
        peerRinging = false; unreachable = false
        for fc in frameCryptors { fc.enabled = false }; frameCryptors = []; keyProvider = nil; sframeWrapped = []
        sframeAuthorized = false; captureRunning = false
        wantFrontCamera = true; usingFrontCamera = true
        let cap = capturer; capturer = nil
        cap?.stop { }   // asynchronous stop of AVCaptureSession with completion
        pc?.close(); pc = nil
        videoFramesSeen = false; localAudio = nil; localVideo = nil; remoteVideoTrack = nil
        if let s = callSeed { MontanaCall.dropBell(s.base64EncodedString()) }
        peer = nil; peerDevice = nil; pendingOffer = nil; pendingIce = []; callUUID = nil
        callSeed = nil; peerPremium = false; peerReadsVoipAnswer = false; startedAt = nil; connectedAt = nil
        peerRebuilds = false; rejoining = false; freshConnection = false; seenRejoinOffer = ""; heldRejoins = 0
        rejoinOffering = false; rejoinUntil = .distantPast
        seedlessOffer = nil; knockN = 0; knockOk = 0; knockFirstOkS = -1; knockLastOkS = -1; knockNobody = false; bellRung = false
        let s = RTCAudioSession.sharedInstance()
        s.isAudioEnabled = false
        speakerOn = false; desiredMuted = false; videoSpeakerDecided = false
        setShareActive(false); cameraWasLive = false; setVideoSource(nil)
        audioBeforeShare = false; peerShareGrewVideo = false
        MTScreenShare.shared.disarm()
        MTAvatarMask.shared.set(false, why: "call-end")   // the mask lives inside one call (checklist 36)
        DispatchQueue.main.async {
            let m = CallUIModel.shared
            m.held = false; m.heldByPeer = false; m.screenSharing = false; m.peerSharing = false
            m.videoAsk = false; m.videoAskIncoming = false; m.videoAskPending = false
        }
        tlog("⑩ cleanup done teardown=\(Int(Date().timeIntervalSince(teardownStart)*1000))ms → idle, all call info cleared")
        setState("idle")
        if let pk = orphanParked { adoptParkedHeld(pk) }
        scheduleSweep("after-end")   // the system's own list is read once the end has settled
    }

    /// K-8: the held call takes the emptied machine back — WITHOUT waking its tracks and
    /// without a call-resume word: it stays exactly as the person left it, on hold. The
    /// Hold button resumes it; its CallKit oval never died.
    private func adoptParkedHeld(_ pk: ParkedCall) {
        pc = pk.pc
        frameCryptors = pk.cryptors
        peer = pk.peer; peerDevice = pk.device
        callUUID = pk.uuid; callSeed = pk.seed; isVideo = pk.video
        startedAt = pk.startedAt; connectedAt = pk.connectedAt
        ended = false; endSignalSent = false; declinedByMe = false; endReason = "-"; endDoor = "-"
        softHeld = true
        remoteVideoTrack = pc?.receivers.compactMap { $0.track as? RTCVideoTrack }.first
        for sn in pc?.senders ?? [] {
            if let a = sn.track as? RTCAudioTrack { localAudio = a }
            if let v = sn.track as? RTCVideoTrack { localVideo = v }
        }
        beginBackgroundHold()
        DispatchQueue.main.async { CallUIModel.shared.held = true }
        setState("connected")
        MontanaWakePush.startSignalPolling(pk.peer)
        MontanaP2PTrace.mark("call_hold", "parked adopted held after the machine emptied")
    }

    func toggleMute(_ muted: Bool) { desiredMuted = muted; localAudio?.isEnabled = !muted }

    // The native Video button (12.3 screen parity): an audio call grows a camera mid-talk —
    // the track is added and a plain renegotiation offer rides the standing restart road
    // (call-restart, no ICE restart); the peer answers like any re-offer and the video
    // arrives through didAdd. Turning it off mutes OUR camera honestly; the call stays a
    // video call while the peer still sends.
    func toggleVideo() {
        if screenShareActive { MTScreenShare.shared.dropPeer(); return }   // Video ends the share; the camera returns by cameraWasLive
        if !isVideo {
            // Consent first (the author's word): the camera does not start until the peer
            // says yes. Old builds bury the unknown word — silence becomes «no answer».
            guard let p = peer else { return }
            guard !CallUIModel.shared.videoAskPending else { return }   // SILENT-OK: already asked
            var va = CallSignalOut(ctrl: "call-video-ask"); va.targetDevice = peerDevice
            sendSignal?(p, va)
            MontanaP2PTrace.mark("call_video", "consent asked")
            DispatchQueue.main.async {
                CallUIModel.shared.videoAskPending = true
                self.videoAskTimer?.invalidate()
                self.videoAskTimer = self.callTimer(30, repeats: false) { _ in
                    guard CallUIModel.shared.videoAskPending else { return }
                    CallUIModel.shared.videoAskPending = false
                    MontanaP2PTrace.mark("call_video", "consent timeout")
                }
            }
        } else {
            dropVideoMode(tellPeer: true)   // the second press leaves video — both sides return to audio
        }
    }

    private func dropVideoMode(tellPeer: Bool) {
        guard isVideo, !screenShareActive else { return }   // SILENT-OK: nothing to leave
        if tellPeer, let p = peer {
            var ve = CallSignalOut(ctrl: "call-video-end"); ve.targetDevice = peerDevice
            sendSignal?(p, ve)   // old builds bury the word — their side keeps video, ours returns honestly
        }
        captureRunning = false
        let cap = capturer; capturer = nil
        cap?.stop { }
        if let tr = pc?.transceivers.first(where: { $0.mediaType == .video }) { tr.sender.track = nil }
        localVideo = nil
        setVideoSource(nil)
        remoteVideoTrack = nil   // recovered from the standing receiver if video rises again
        isVideo = false
        updateProximity()
        if let u = callUUID {
            let upd = CXCallUpdate(); upd.hasVideo = false
            provider.reportCall(with: u, updated: upd)
        }
        DispatchQueue.main.async {
            CallUIModel.shared.video = false
            CallUIModel.shared.cameraOff = false
            CallUIModel.shared.videoAsk = false
            CallUIModel.shared.tick += 1
        }
        MTAvatarMask.shared.set(false, why: "video-end")   // no camera, no mask (checklist 36)
        MontanaP2PTrace.mark("call_video", "video mode ended tell=\(tellPeer ? 1 : 0)")
    }
    private func upgradeToVideo() {
        guard !isVideo else { return }   // SILENT-OK: already a video call
        isVideo = true
        applyScreenHold()
        if remoteVideoTrack == nil {
            remoteVideoTrack = pc?.receivers.compactMap { $0.track as? RTCVideoTrack }.first
        }
        DispatchQueue.main.async { CallUIModel.shared.video = true }
        ensureLocalVideoTrack()
        if let u = callUUID {
            let upd = CXCallUpdate(); upd.hasVideo = true
            provider.reportCall(with: u, updated: upd)
        }
        pushCaptureUntilRunning()
        sendRenegotiationOffer(iceRestart: false)
        autoSpeakerOnVideo()
        MontanaP2PTrace.mark("call_video", "upgrade offered")
    }

    func acceptVideoAsk() {
        DispatchQueue.main.async { CallUIModel.shared.videoAskIncoming = false }
        guard let p = peer else { return }
        videoAcceptArmed = true   // our camera joins the moment theirs lands — offers stay sequential
        videoArmedAt = Date()     // consent is fresh for 40s, not for the call's lifetime (K-6)
        var ok = CallSignalOut(ctrl: "call-video-ok"); ok.targetDevice = peerDevice
        sendSignal?(p, ok)
        MontanaP2PTrace.mark("call_video", "consent accepted")
    }
    func declineVideoAsk() {
        DispatchQueue.main.async { CallUIModel.shared.videoAskIncoming = false }
        guard let p = peer else { return }
        var no = CallSignalOut(ctrl: "call-video-no"); no.targetDevice = peerDevice
        sendSignal?(p, no)
        MontanaP2PTrace.mark("call_video", "consent refused")
    }

    // The answer to the peer's video invitation: the camera joins the standing call.
    func enableMyVideo() {
        DispatchQueue.main.async { CallUIModel.shared.videoAsk = false }
        guard state == "connected" || state == "active" || state == "reconnecting" else { return }
        if localVideo == nil {
            isVideo = true
            applyScreenHold()
            if remoteVideoTrack == nil {
                remoteVideoTrack = pc?.receivers.compactMap { $0.track as? RTCVideoTrack }.first
            }
            DispatchQueue.main.async { CallUIModel.shared.video = true; CallUIModel.shared.tick += 1 }
            if let u = callUUID {
                let upd = CXCallUpdate(); upd.hasVideo = true
                provider.reportCall(with: u, updated: upd)
            }
            ensureLocalVideoTrack()
            pushCaptureUntilRunning()
            sendRenegotiationOffer(iceRestart: false)
            MontanaP2PTrace.mark("call_video", "joined by invitation")
        } else if let lv = localVideo {
            lv.isEnabled = true
            DispatchQueue.main.async { CallUIModel.shared.cameraOff = false }
        }
    }

    func switchCamera() {
        guard let cap = capturer else { return }
        // The button changes INTENT. The count starts from what the person chose last time,
        // not from whichever device the system managed to open. THE ONE ROAD TO THE OTHER CAMERA,
        // and it speaks in the diary (measured 22.09: a back camera came up on the iPhone 17 with no
        // line between «camera came up» and «camera started back» — the silent road was this one).
        let next = !wantFrontCamera
        MontanaP2PTrace.mark("cam_switch", "to=\(next ? "front" : "back") why=tap")
        wantFrontCamera = next
        captureRunning = false
        cap.stop { self.startCapture(front: next) }
    }

    // ── SCREEN SHARE: the system broadcast feeds the STANDING video lane — same sender,
    // same SFrame cryptor, same renegotiation road; the screen is just another source.
    private func ensureScreenVideoTrack() {
        guard localVideo == nil, let pc else { return }
        let source = factory.videoSource(forScreenCast: true)
        setVideoSource(source)
        let track = factory.videoTrack(with: source, trackId: "mt_video")
        localVideo = track
        if let tr = pc.transceivers.first(where: { $0.mediaType == .video }) {
            tr.sender.track = track
            tr.setDirection(.sendRecv, error: nil)
        } else {
            pc.add(track, streamIds: ["mt_stream"])
        }
        maybeEnableSframe()
        DispatchQueue.main.async { CallUIModel.shared.tick += 1 }
    }

    func startScreenShare() {
        guard state == "connected" || state == "active" || state == "reconnecting" else {
            MontanaP2PTrace.mark("call_screen", "share refused st=\(state)")
            MTScreenShare.shared.dropPeer()
            return
        }
        audioBeforeShare = !isVideo
        cameraWasLive = capturer != nil && (localVideo?.isEnabled ?? false)
        if let cap = capturer { captureRunning = false; capturer = nil; cap.stop { } }   // the camera rests; the lane stays
        // ACCEPTED LIMITATION: when the lane was born for the camera, its source carries no
        // screencast hints — swapping the track mid-call risks the proven return road for a
        // rare quality gain (sharper text). Named here so the trade is a choice, not a hole.
        setShareActive(true)
        if localVideo == nil {
            // an audio call grows the video lane — the Video-button road, without a camera
            isVideo = true
            applyScreenHold()
            DispatchQueue.main.async { CallUIModel.shared.video = true }
            ensureScreenVideoTrack()
            if let u = callUUID {
                let upd = CXCallUpdate(); upd.hasVideo = true
                provider.reportCall(with: u, updated: upd)
            }
            sendRenegotiationOffer(iceRestart: false)
        }
        localVideo?.isEnabled = true
        boostVideo()   // the ceiling written anew for the screen's own shape (the ladder is its one writer)
        // THE SHAPE OF THE SHARE IS THE SHAPE OF THE SCREEN SHARED (the author's word 21.09): the
        // lane used to be adapted to a fixed phone portrait, 720x1560, and the adapter cuts a frame
        // to the shape it is given — a wider screen (the tablet's 1918x1260) lost its sides at the
        // sender before the peer could fit anything. The shape is now taken from the first frame
        // (pushScreenFrame: shareShape) — scaled down to the same pixel budget, never cut.
        shareShape = (0, 0)
        if let p = peer {
            var so = CallSignalOut(ctrl: "call-screen-on"); so.targetDevice = peerDevice
            sendSignal?(p, so)   // old builds bury the unknown word silently
        }
        DispatchQueue.main.async {
            CallUIModel.shared.cameraOff = true          // the camera IS off while the screen rides
            CallUIModel.shared.screenSharing = true
            CallUIModel.shared.fold(true, why: "own-share")   // the sharer lands on the very screen he shares
        }
        screenFrames = 0
        MontanaP2PTrace.mark("call_screen", "share started camera_was=\(cameraWasLive ? 1 : 0)")
    }

    func stopScreenShare() {
        guard screenShareActive else { return }   // SILENT-OK: a late socket EOF after cleanup already reset everything
        setShareActive(false)
        boostVideo()   // the camera's shape again, on whatever step the ladder stands
        if let p = peer {
            var so = CallSignalOut(ctrl: "call-screen-off"); so.targetDevice = peerDevice
            // The sharer is the ONLY one who knows what the call was before the share —
            // the viewer's guess lost a 60ms race to the media lane once (grew=0 at
            // 20:48:13.027 while the first frame landed at 12.963). The truth rides
            // the word: video=false — the call returns to audio.
            so.video = !audioBeforeShare
            sendSignal?(p, so)
        }
        DispatchQueue.main.async {
            CallUIModel.shared.screenSharing = false
            CallUIModel.shared.fold(false, why: "own-share-end")   // the standard call screen returns
        }
        if cameraWasLive, let src = videoSource {
            // the camera returns into the SAME track through a fresh capturer
            let counter = FrameCountingCapturerDelegate(sink: src)
            frameCounter = counter
            let cap = MontanaCamera(delegate: counter)
            capturer = cap
            observeCaptureSession(cap)
            startCapture(front: wantFrontCamera)
            DispatchQueue.main.async { CallUIModel.shared.cameraOff = false }
        } else if let lv = localVideo {
            lv.isEnabled = false
            if audioBeforeShare {
                // the video state grew only for the share — it falls with it WHOLE:
                // the track leaves the sender, the model returns to the audio face
                // identical to the receiving side's
                isVideo = false
                updateProximity()
                if let tr = pc?.transceivers.first(where: { $0.mediaType == .video }) {
                    tr.sender.track = nil
                }
                localVideo = nil
                setVideoSource(nil)
                if let u = callUUID {
                    let upd = CXCallUpdate(); upd.hasVideo = false
                    provider.reportCall(with: u, updated: upd)
                }
                DispatchQueue.main.async {
                    CallUIModel.shared.video = false
                    CallUIModel.shared.cameraOff = false
                    CallUIModel.shared.tick += 1
                }
            } else {
                DispatchQueue.main.async { CallUIModel.shared.cameraOff = true }
            }
        }
        MontanaP2PTrace.mark("call_screen", "share stopped camera_back=\(cameraWasLive ? 1 : 0) audio_back=\(audioBeforeShare ? 1 : 0)")
        cameraWasLive = false; audioBeforeShare = false
    }

    private var screenFrames = 0   // frames pushed this share — the first one is a diary line
    /// The pixel shape the lane is adapted to for this share — the frame's own, scaled to the budget.
    private var shareShape: (w: Int, h: Int) = (0, 0)
    private static let sharePixelBudget = 720 * 1560   // the same area the phone portrait had
    func pushScreenFrame(_ pb: CVPixelBuffer, orientation: UInt32, ptsNs: Int64) {
        shareLock.lock()
        let active = screenShareActive
        let src0 = videoSource
        shareLock.unlock()
        guard active, let src = src0 else { return }   // SILENT-OK: frames racing the stop are expected
        let ts = ptsNs > 0 ? ptsNs : Int64(Date().timeIntervalSince1970 * 1_000_000_000)
        let bw = CVPixelBufferGetWidth(pb), bh = CVPixelBufferGetHeight(pb)
        if (bw != shareShape.w || bh != shareShape.h), bw != 0, bh != 0 {
            // Every screen keeps its own proportions on the wire: the adapter only scales.
            let scale = min(1.0, (Double(Self.sharePixelBudget) / Double(bw * bh)).squareRoot())
            let tw = max(2, Int(Double(bw) * scale) / 2 * 2), th = max(2, Int(Double(bh) * scale) / 2 * 2)
            src.adaptOutputFormat(toWidth: Int32(tw), height: Int32(th), fps: 30)
            shareShape = (bw, bh)
            MontanaP2PTrace.mark("call_screen", "share shape \(bw)x\(bh) lane=\(tw)x\(th)")
        }
        // THE KEY IS HOW THE DEVICE IS HELD, NOT AN EXIF TAG (measured 21.09 on the tablet, three
        // builds): ReplayKit hands a buffer in the device's native shape — landscape on a tablet
        // (1918x1260), portrait on a phone (886x1918) — and RPVideoSampleOrientationKey says how the
        // device stood. The tablet held upright gave orient=8: turned 270 the peer saw it upside
        // down (1830), turned 0 he saw it on its side (1831) — so 8 is a quarter turn CLOCKWISE
        // and 6 the other way, the reverse of the EXIF reading the code was born with.
        let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb)
        let rot: RTCVideoRotation
        switch orientation {
        case 3: rot = ._180    // .down
        case 6: rot = ._270    // .right
        case 8: rot = ._90     // .left
        default: rot = ._0     // .up
        }
        if screenFrames == 0 { MontanaP2PTrace.mark("call_screen", "share frame \(w)x\(h) orient=\(orientation) rot=\(rot.rawValue)") }
        screenFrames &+= 1
        let frame = RTCVideoFrame(buffer: RTCCVPixelBuffer(pixelBuffer: pb), rotation: rot, timeStampNs: ts)
        src.capturer(screenPusher, didCapture: frame)
    }

    /// 12.9 — THE VOICE IS NOT A VICTIM. When a channel narrows, something must give way, and
    /// the choice is made HERE rather than by chance: the voice lane is marked high priority so
    /// the system's own bandwidth split starves the picture first, and its rate is never touched
    /// by the ladder below. A conversation survives a bad channel; a picture may wait.
    private func protectVoice() {
        guard let sender = pc?.senders.first(where: { $0.track?.kind == "audio" }) else { return }
        let p = sender.parameters
        if !p.encodings.isEmpty {
            p.encodings[0].networkPriority = .high
            p.encodings[0].bitratePriority = 4.0   // four parts of the split to the voice
        }
        sender.parameters = p
    }

    /// 12.9 — THE LADDER. The bandwidth estimator already lowers sharpness on its own, but it
    /// answers to the channel, not to the CONVERSATION: under a real squeeze it keeps spending
    /// the whole channel on the picture while the voice tears. The ladder is a ceiling the call
    /// itself lowers step by step while the squeeze holds, and raises back when it lets go —
    /// the voice keeps its share at every step, and the bottom step is «no picture, but the
    /// person is heard», never «both broken».
    private static let videoLadder = [2_000_000, 1_200_000, 700_000, 400_000, 250_000, 0]
    private var ladderStep = 0
    private var ladderMovedAt = Date.distantPast
    private var ladderGoodTicks = 0
    /// THE POWER FLOOR (the author's word 10.09): the battery, the charger, Low Power Mode and the
    /// thermal state are read with every ladder tick (MontanaPower, the one source); while the
    /// phone is under power pressure the ladder may not rise above the floor, and the encoder
    /// works at half resolution and 15 fps — the picture stays, the heat and the drain fall.
    private var powerFloor = 0
    private var powerStart: MontanaPower.Snapshot?
    private var powerLast: MontanaPower.Snapshot?
    private var powerTicks = 0

    /// The break has ONE door in and ONE door out. The ICE machine is only one of the witnesses:
    /// measured 29.08, a picture froze while ICE went on calling itself connected — the relay's
    /// keepalives kept flowing while the media did not, so nothing was said to the person at all.
    /// The other witness is the media itself, and it is the one the person actually hears.
    /// A REBUILD ENTERS BY THE SAME DOOR (24.09): the run that came back into its call is born straight into the break
    /// (it holds no connection yet), and the living side enters it from a connected call when the peer's rejoin comes.
    /// Neither asks a dead connection for fresh checks -- a new one is being built (`fresh`).
    private func enterReconnecting(_ why: String, fresh: Bool = false) {
        guard state == "connected" || (fresh && state == "idle") else { return }
        if state == "connected" { sumBreaks += 1 }
        setState("reconnecting")
        MontanaP2PTrace.mark("call_reconnect", "break by \(why)")
        reconnectVoice(true)
        DispatchQueue.main.async {
            self.armReconnectDeadline()
            if !fresh { self.scheduleIceRestart() }
        }
    }
    /// THE WAIT OF A BREAK (24.09): the run that came back waits for its peer's answer until the call's window closes (its
    /// peer may be in Settings too -- both phones ended by iOS, the second person back later); a peer that rebuilds in place
    /// is waited for as long as a ring rings -- its run comes back within it; any other peer, the thirty seconds of checks.
    private func armReconnectDeadline() {
        let wait = rejoining ? max(Self.rejoinAnswerS, rejoinUntil.timeIntervalSinceNow)
                             : (peerRebuilds ? Self.rejoinWindowS : Self.reconnectDeadlineS)
        reconnectTimer?.invalidate()
        reconnectTimer = callTimer(wait, repeats: false) { [weak self] _ in
            guard let self, self.state == "reconnecting" else { return }
            E2ELog.write("call: reconnecting past the deadline (\(Int(wait))s) — \(self.iceRestarts) fresh transports asked, none formed — ending")
            self.endByRule(self.rejoining ? "rejoin-unanswered" : "lost")   // a rule ended it, not a hand: the summary says so
        }
    }

    // ── THE CALL OUTLIVES ITS PROCESS (24.09) ──

    /// The call on disk (HeldCall), sealed by the device key: written at its birth, at its connection and every few
    /// seconds while it lives (the last moment it was known alive), wiped with its seed.
    private func holdOnDisk(force: Bool = false) {
        guard let seed = callSeed?.base64EncodedString() else {
            // A held call waiting for its person is not wiped by an end elsewhere: only its judgement removes it.
            if Self.heldAtLaunch == nil { UserDefaults.standard.removeObject(forKey: Self.heldKey) }
            heldWrittenAt = .distantPast
            return
        }
        guard let p = peer, force || Date().timeIntervalSince(heldWrittenAt) >= 5 else { return }
        heldWrittenAt = Date()
        let h = HeldCall(peer: p, device: peerDevice, seed: seed, video: isVideo, initiator: isInitiator,
                         startedAt: (startedAt ?? Date()).timeIntervalSince1970,
                         connectedAt: connectedAt?.timeIntervalSince1970 ?? 0, rebuilds: peerRebuilds,
                         alive: Date().timeIntervalSince1970, rejoins: heldRejoins)
        if let d = try? JSONEncoder().encode(h) { MontanaLocalVault.setEncrypted(Self.heldKey, d) }
    }
    /// Whether this call would go on if iOS ended the app now: a peer that rebuilds, a call that stands.
    var outlivesItsProcess: Bool { peerRebuilds && (state == "connected" || state == "reconnecting") }
    /// A connection built in place of a dead one (a rejoin on either side): its first «connected» protects the voice
    /// and names itself, as a first connection's does.
    private var freshConnection = false
    /// The witnesses of a break and the ladder belong to one connection: a rebuilt one starts them anew.
    private func resetConnectionWitnesses() {
        lastInBytes = 0; stallSamples = 0; everFlowed = false; pathSeen = [:]; pictureStallSamples = 0; pictureSeen = [:]
        ladderStep = ladderFloor; ladderMovedAt = Date(); ladderGoodTicks = 0; lastVideoLost = 0
    }

    /// THE RUN GOES BACK INTO THE CALL ITS PROCESS HELD (24.09). Called at launch; waits until the app faces the person
    /// and the peer's pipe is open, then rejoins: the same seed, a new connection, the word «rejoin» on the node's lane
    /// -- no ring on either side. Only a call that stood connected, with a peer that rebuilds in place, whose last known
    /// moment lies inside the peer's wait, and that no run went back into twice.
    func rejoinHeldCall(attempt: Int = 0) {
        guard Thread.isMainThread else { DispatchQueue.main.async { self.rejoinHeldCall(attempt: attempt) }; return }
        guard let h = Self.heldAtLaunch else { return }
        let age = Date().timeIntervalSince1970 - h.alive
        guard h.connectedAt > 0, h.rebuilds, h.rejoins < 2, age < Self.rejoinWindowS, state == "idle" else {
            Self.heldAtLaunch = nil
            if callSeed == nil { UserDefaults.standard.removeObject(forKey: Self.heldKey) }   // judged: a living call keeps its own
            MontanaP2PTrace.mark("call_rejoin", "not tried connected=\(h.connectedAt > 0 ? 1 : 0) rebuilds=\(h.rebuilds ? 1 : 0) tries=\(h.rejoins) age_s=\(Int(age)) state=\(state)")
            return
        }
        // Not yet: the person has not come back to the screen, or the store has not opened the peer's pipe.
        guard UIApplication.shared.applicationState == .active, MTPipeBook.secret(for: h.peer) != nil else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.rejoinHeldCall(attempt: attempt + 1) }
            return
        }
        Self.heldAtLaunch = nil
        MontanaP2PTrace.mark("call_rejoin", "tx age_s=\(Int(age)) video=\(h.video ? 1 : 0) waited_ms=\(attempt * 250) epoch=\(String(h.seed.prefix(8)))")
        nativeHandle = MontanaCallHandle.token(for: h.peer)
        peer = h.peer; peerDevice = h.device; isVideo = h.video; isInitiator = h.initiator
        signalLock.lock(); pendingIce = []; signalLock.unlock()
        sframeWrapped = []; frameCryptors = []
        iceHeldForPeerWord = true; restartAskedAt = .distantPast; setupAsks = 0; askedRelayOnly = false; lastIce = "new"; rebuiltInPlace = false
        iceBatchTimer?.cancel(); iceBatchTimer = nil; iceOutBatch = []; iceFlushes = 0; resetSignalFlags(); audioUnitPending = false; videoReady = false; measuring = false
        sframeAuthorized = false; captureRunning = false
        ended = false; endSignalSent = false; declinedByMe = false; answeredByMe = true; endReason = "-"; endDoor = "-"
        cameraDeniedTold = false
        peerRebuilds = true; rejoining = true; freshConnection = true; heldRejoins = h.rejoins + 1
        rejoinUntil = Date(timeIntervalSince1970: h.alive + Self.rejoinWindowS)
        startedAt = Date(timeIntervalSince1970: h.startedAt)
        connectedAt = Date(timeIntervalSince1970: h.connectedAt); answeredAt = connectedAt
        callSeed = Data(base64Encoded: h.seed)   // the epoch lives again: the peer's words for this call are taken
        callGen += 1
        let uuid = UUID(); callUUID = uuid
        callT0 = Date(); iceGenCount = 0; firstMediaLogged = false; firstVideoIn = false
        enterReconnecting("rejoin", fresh: true)
        beginBackgroundHold(); startSetupHeartbeat()
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.releaseHeldIce("time") }
        if isVideo { birthLocalVideo(); pushCaptureUntilRunning() }
        let action = CXStartCallAction(call: uuid, handle: CXHandle(type: .generic, value: nativeHandle))
        action.isVideo = isVideo
        let gen = callGen
        callController.request(CXTransaction(action: action)) { [weak self] err in
            guard let err, let self else { return }
            DispatchQueue.main.async {
                guard self.callGen == gen, self.rejoining else { return }
                MontanaP2PTrace.mark("call_refused", "callkit err=\(err.localizedDescription.prefix(60)) rejoin=1")
                self.endByRule("callkit-refused")
            }
        }
        offerRejoin(gen: gen, configureAudio: true)
    }
    /// THE REJOIN'S OWN OFFER -- one road for the run that came back and for the living run whose asks did not form
    /// (rebuildInPlace): a new connection, the same seed, the word «rejoin» on the node's lane.
    private func offerRejoin(gen: Int, configureAudio: Bool) {
        Task { @MainActor in   // K-1: the machine's fields are the owner thread's
            if configureAudio { configureAudioSession() }
            await buildPC()
            guard gen == callGen, rejoining else { return }
            guard let pcx = pc else { endByRule("rejoin-unbuilt"); return }
            pcx.offer(for: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)) { [weak self] desc, _ in
                guard let self else { return }
                guard let desc else { self.endByRule("rejoin-offer-unbuilt"); return }
                let tuned = RTCSessionDescription(type: desc.type, sdp: self.tuneSDP(desc.sdp, premium: true))
                self.pc?.setLocalDescription(tuned) { err in
                    if let err {
                        self.tlog("own rejoin offer refused: \(err.localizedDescription)")
                        self.endByRule("rejoin-offer-refused-here")
                        return
                    }
                    self.boostVideo()
                    DispatchQueue.main.async { self.sendRejoinOffer(tuned.sdp, gen: gen) }
                }
            }
        }
    }
    /// THE LIVING RUN REBUILDS ITS OWN TRANSPORT (29.09): the break's first ask did not form, and a dead transport is not
    /// asked again -- the connection is closed and born anew, the peer answers the rejoin in place (rebuildForRejoin), the
    /// call keeps its clock, its system call and its screen. What a hand did by hanging up and dialling again, without the hand.
    private func rebuildInPlace(_ why: String) {
        guard state == "reconnecting", !rebuiltInPlace, peer != nil, let dead = pc else { return }
        rebuiltInPlace = true
        MontanaP2PTrace.mark("call_rejoin", "tx in place — \(why)")
        MontanaLog.event("E2E-CALL rebuild in-place why=\(why)")
        restartTimer?.invalidate(); restartTimer = nil; iceRestarts = 0; restartAskedAt = .distantPast
        disconnectGrace?.invalidate(); disconnectGrace = nil
        answerResendTimer?.invalidate(); answerResendTimer = nil; answerResends = 0
        iceBatchTimer?.cancel(); iceBatchTimer = nil; iceOutBatch = []; iceFlushes = 0; iceOutKinds = [:]
        signalLock.lock(); pendingIce = []; signalLock.unlock()
        seenRestartOffer = ""; seenRestartAnswer = ""
        resetSignalFlags()
        measureGen += 1; measuring = false
        for fc in frameCryptors { fc.enabled = false }; frameCryptors = []; keyProvider = nil; sframeWrapped = []; sframeAuthorized = false
        remoteVideoTrack = nil
        peerShareGrewVideo = false
        DispatchQueue.main.async { CallUIModel.shared.peerSharing = false; CallUIModel.shared.remoteLive = false; CallUIModel.shared.tick += 1 }
        rejoining = true; freshConnection = true
        iceHeldForPeerWord = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.releaseHeldIce("time") }
        callGen += 1
        pc = nil; dead.close()
        resetConnectionWitnesses()
        armReconnectDeadline()
        offerRejoin(gen: callGen, configureAudio: false)
    }
    /// The rejoin's offer rides the node's lane alone (nodeOnly) every two seconds until the peer's answer stands: the
    /// peer is awake in the call, no ring is needed, and the lane names the call -- a device that never held it buries it.
    private func sendRejoinOffer(_ sdp: String, gen: Int, n: Int = 0) {
        guard gen == callGen, rejoining, let p = peer, pc?.remoteDescription == nil, n < 9 else {
            if gen == callGen { rejoinOffering = false }
            return
        }
        rejoinOffering = true
        var o = CallSignalOut(ctrl: "call", sdp: CallSDP(type: "offer", sdp: sdp), video: isVideo, caps: myCaps(),
                              callSeed: callSeed?.base64EncodedString())
        o.reason = "rejoin"; o.nodeOnly = true
        sendSignal?(p, o)
        MontanaP2PTrace.mark("call_rejoin", "offer n=\(n + 1)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.sendRejoinOffer(sdp, gen: gen, n: n + 1) }
    }
    /// THE LIVING SIDE REBUILDS IN PLACE (24.09): the peer's run came back with a new connection; the dead one is closed,
    /// a new one answers the rejoin, and the call -- its clock, its system call, its screen -- goes on. A rejoin carrying
    /// this connection's own certificate is a copy, not a rebirth.
    private func rebuildForRejoin(offer s: CallSDP, device: String, caps: CallCaps?) {
        guard s.sdp != seenRejoinOffer else { MontanaP2PTrace.mark("call_rejoin", "rx copy — buried"); return }
        // A copy carries the certificate this connection already holds -- judged only when both are read: a reading
        // that failed is no proof of a copy, and a rejoin is never buried on the parser's word.
        if let fresh = Self.fingerprint(s.sdp), fresh == pc?.remoteDescription.flatMap({ Self.fingerprint($0.sdp) }) {
            MontanaP2PTrace.mark("call_rejoin", "rx with this connection's own certificate — no rebirth, buried")
            return
        }
        guard let p = peer else { return }
        seenRejoinOffer = s.sdp
        rejoinOffering = false   // our own offer, if this run was rejoining too, is let go: theirs is answered
        MontanaP2PTrace.mark("call_rejoin", "rx state=\(state) — the peer's new connection replaces the dead one, no ring")
        restartTimer?.invalidate(); restartTimer = nil; iceRestarts = 0; restartAskedAt = .distantPast
        disconnectGrace?.invalidate(); disconnectGrace = nil
        answerResendTimer?.invalidate(); answerResendTimer = nil; answerResends = 0
        iceBatchTimer?.cancel(); iceBatchTimer = nil; iceOutBatch = []; iceFlushes = 0
        signalLock.lock(); pendingIce = []; signalLock.unlock()
        seenRestartOffer = ""; seenRestartAnswer = ""
        resetSignalFlags()
        measureGen += 1; measuring = false
        for fc in frameCryptors { fc.enabled = false }; frameCryptors = []; keyProvider = nil; sframeWrapped = []; sframeAuthorized = false
        remoteVideoTrack = nil
        // The dead run's share died with it, and its picture is the new connection's to show: the screen lets both go
        // and waits for the first new frame; the offer decides whether the call goes on with video.
        peerShareGrewVideo = false
        DispatchQueue.main.async { CallUIModel.shared.peerSharing = false; CallUIModel.shared.remoteLive = false; CallUIModel.shared.tick += 1 }
        adoptVideoFromOffer(s)
        if !s.sdp.contains("m=video"), isVideo { isVideo = false; applyScreenHold(); updateProximity() }
        callGen += 1   // a build of the dead connection still in flight must not land on the new one
        let dead = pc; pc = nil; dead?.close()
        if !device.isEmpty { peerDevice = device }
        peerPremium = (caps?.tier == "ios-native" && caps?.sframe == true)
        if caps?.av == true { peerReadsVoipAnswer = true }
        peerRebuilds = caps?.rejoin == true
        pendingOffer = s
        freshConnection = true
        resetConnectionWitnesses()
        if state == "connected" { enterReconnecting("peer rejoin", fresh: true) } else { armReconnectDeadline() }
        let gen = callGen
        Task { @MainActor in   // K-1: the machine's fields are the owner thread's
            await self.buildPC()
            guard gen == self.callGen, self.state == "reconnecting" else { return }
            guard let pcx = self.pc else { self.endByRule("rejoin-unbuilt"); return }
            pcx.setRemoteDescription(RTCSessionDescription(type: .offer, sdp: s.sdp)) { [weak self] err in
                guard let self else { return }
                if let err {
                    self.tlog("the peer's rejoin offer refused: \(err.localizedDescription)")
                    self.endByRule("rejoin-offer-refused")
                    return
                }
                self.flushIce()
                self.produceAndSendAnswer(peer: p)
            }
        }
    }

    private func leaveReconnecting(_ why: String) {
        guard state == "reconnecting" else { return }
        MontanaP2PTrace.mark("call_reconnect", "back by \(why)")
        reconnectTimer?.invalidate(); reconnectTimer = nil
        restartTimer?.invalidate(); restartTimer = nil; iceRestarts = 0
        restartAskedAt = .distantPast
        reconnectVoice(false)
        setState("connected")
    }

    private func applyLadder(limit: String, lostDelta: Int, rttMs: Int) {
        guard isVideo, state == "connected" else { return }
        // The power facts ride the same tick as the network facts: one measurement, one owner.
        let power = MontanaPower.snapshot()
        if powerStart == nil { powerStart = power }
        powerLast = power
        powerTicks += 1
        if powerTicks % 12 == 1 { MontanaP2PTrace.mark("call_power", power.word + " floor=\(power.ladderFloor) step=\(ladderStep)") }
        if power.ladderFloor != powerFloor {
            powerFloor = power.ladderFloor
            sumPowerFloorMax = max(sumPowerFloorMax, powerFloor)
            MontanaP2PTrace.mark("call_power", "floor \(powerFloor) — \(power.word)")
            if ladderStep < ladderFloor {
                ladderStep = ladderFloor; ladderMovedAt = Date(); ladderGoodTicks = 0
                sumLadderMin = max(sumLadderMin, ladderStep)
            }
            setVideoCeiling(Self.videoLadder[ladderStep])   // re-applied: the floor changes the encoder's shape too
            // Nothing about saving is written on the screen (the author's word 11.09): the light
            // before the call's name wears the battery instead of the dot, and that is all.
            let saving = powerFloor > 0
            DispatchQueue.main.async { CallUIModel.shared.powerSaving = saving }
        }
        // A squeeze is a FACT of three witnesses, not one bad tick: the encoder says it is held
        // by bandwidth, packets are actually being lost, or the round trip has doubled past what
        // a conversation tolerates. One witness is noise; two are a squeeze.
        let witnesses = (limit == "bandwidth" ? 1 : 0) + (lostDelta > 8 ? 1 : 0) + (rttMs > 400 ? 1 : 0)
        let squeezed = witnesses >= 2
        // The traffic light: green — the channel is clean at the top step; yellow — the picture
        // is held below the top step; red — squeezed right now. The top step is the floor's: a pair not
        // proven direct stands at its modest top and is green there.
        let light = squeezed ? 0 : (ladderStep > ladderFloor ? 1 : 2)
        DispatchQueue.main.async { if CallUIModel.shared.signal != light { CallUIModel.shared.signal = light } }
        let since = Date().timeIntervalSince(ladderMovedAt)
        if squeezed {
            ladderGoodTicks = 0
            guard since > 8, ladderStep < Self.videoLadder.count - 1 else { return }
            ladderStep += 1
            sumLadderMin = max(sumLadderMin, ladderStep)
            ladderMovedAt = Date()
            let cap = Self.videoLadder[ladderStep]
            setVideoCeiling(cap)
            MontanaP2PTrace.mark("call_ladder",
                "down step=\(ladderStep) cap_kbps=\(cap / 1000) limit=\(limit) lost=\(lostDelta) rtt=\(rttMs)")
        } else if lostDelta > 8 || rttMs > 400 {
            // ONE NETWORK WITNESS HOLDS THE STEP (24.09). It is not a squeeze, so the ladder does not step
            // down, and it is not a clean channel, so it does not step up either. It used to count as a good
            // tick: on T1 (23.09 20:30Z, LTE through the tunnel) the ladder climbed with the round trip at
            // 2.6 s (up step=2 rtt=2594) and at 604 ms (up step=0 cap_kbps=2000) -- over a stream-carried
            // pipe a loss never shows, the round trip is the witness left, and alone it stood outvoted. The
            // encoder's own «bandwidth» does not hold the step: under a low step it names our ceiling as
            // often as the channel (T1 at 400 kbps said «bandwidth» at a round trip of 160 ms), and holding
            // on it would pin a clean pair below its top.
            ladderGoodTicks = 0
        } else {
            ladderGoodTicks += 1
            // Coming back is slower than going down — a channel that just recovered is not yet
            // proven, and a picture that leaps back up drags the voice with it a second time.
            guard ladderGoodTicks >= 3, since > 12, ladderStep > ladderFloor else { return }   // never above the floor: power or path
            ladderStep -= 1
            ladderMovedAt = Date()
            ladderGoodTicks = 0
            let cap = Self.videoLadder[ladderStep]
            setVideoCeiling(cap)
            MontanaP2PTrace.mark("call_ladder", "up step=\(ladderStep) cap_kbps=\(cap / 1000) rtt=\(rttMs)")
        }
    }

    /// The one place a video ceiling is set. Zero means the bottom step: the picture stops being
    /// sent and the voice takes the whole channel — the track stays in place, so returning costs
    /// nothing and needs no renegotiation.
    ///
    /// THE BOTTOM STEP STOPS THE ENCODING, NOT THE TRACK (24.09). The track's enabled flag has owners of its
    /// own -- the hold (softHold, parkCurrent) and the screen's share -- and this function used to switch it
    /// back on under every ceiling above zero: during a soft hold the call stays «connected», the measure
    /// loop runs on, and the next step up, a change of the power floor or the pair's proof after a restart
    /// re-enabled the camera of a call on hold by construction. isActive is the platform's own switch for
    /// exactly this (RTCRtpEncodingParameters): the encoding goes quiet, the track and its owners are untouched.
    private func setVideoCeiling(_ bps: Int) {
        guard let sender = pc?.senders.first(where: { $0.track?.kind == "video" }) else { return }
        // THE SHARED SCREEN IS WRITING (25.09; the iPhone 15's page reached T1 at 330x716 and 15 fps: the power floor
        // halved a 720x1558 lane of text, and the encoder, told to keep the frame rate, shrank it further). A camera's
        // picture bears a softer frame better than a slower one; a screen's is the reverse -- letters must stay
        // letters, and a page that turns at eight frames a second is still a page. So the share keeps its pixels under
        // every ceiling: the encoder gives up motion, not resolution, and the power floor slows it instead of shrinking it.
        shareLock.lock(); let sharing = screenShareActive; shareLock.unlock()
        let p = sender.parameters
        if !p.encodings.isEmpty {
            p.encodings[0].isActive = bps > 0
            if bps > 0 {
                p.encodings[0].maxBitrateBps = NSNumber(value: bps)
                p.encodings[0].minBitrateBps = NSNumber(value: min(300_000, bps / 2))
                // Under the power floor the encoder's work falls fourfold: half the resolution,
                // fifteen frames a second. Above it — the camera's own shape, as before.
                p.encodings[0].scaleResolutionDownBy = NSNumber(value: (powerFloor > 0 && !sharing) ? 2.0 : 1.0)
                p.encodings[0].maxFramerate = powerFloor > 0 ? NSNumber(value: sharing ? 8 : 15) : nil
            }
        }
        p.degradationPreference = NSNumber(value: (sharing ? RTCDegradationPreference.maintainResolution : .maintainFramerate).rawValue)
        sender.parameters = p
    }

    private func boostVideo() {
        // An audio call has no video sender -- setVideoCeiling's exit is normal then, not a failure.
        // The starting ceiling is modest: on cellular the uplink does not carry megabits, and our own
        // video stream drowns the ICE checks -- the pair does not form and the call "does not connect".
        // Full sharpness turns on later, once the link is proven (raiseVideoCeiling).
        // AND A LOWER BOUND: the bandwidth estimator starts near zero and crawls up over minutes --
        // the measurement showed "limitation: bandwidth" and the peer's first frames only at the
        // twenty-first second. A lower bound gives a picture at once while staying modest.
        // When bandwidth is short we sacrifice sharpness, not smoothness: torn motion reads as a
        // broken link, a soft picture does not. The default left that choice to chance.
        // All of it is written by the ladder's one writer (24.09): an offer or an answer in the middle
        // of a call (an ICE restart) writes the step the ladder stands on, never a top it has left.
        setVideoCeiling(Self.videoLadder[max(ladderStep, ladderFloor)])
    }

    /// THE PATH'S FLOOR (24.09) -- the ladder's second floor beside the power floor. A call starts on the
    /// modest step (700 kbps) and the top step opens only when the nominated pair is proven direct over
    /// UDP on the phone's own radio or Wi-Fi (raiseVideoCeiling); a relay, TCP and our own tunnel keep the
    /// modest top for as long as they carry the call. The ladder is the ONE owner of the video ceiling
    /// ([C-1]): the start (boostVideo), the proof and every squeeze write it through its steps. It had three
    /// writers: a raised value outlived its call (T3 23.09 20:31 wrote «ceiling left modest» over an encoder
    /// still held at the 2 Mbps its previous call had earned), and the ladder's steps did not know the
    /// modest top (the same pair, called not direct, climbed to up step=0 cap_kbps=2000 at 20:32:41).
    private static let modestStep = 2   // videoLadder[2] = 700 kbps
    private var pathFloor = MontanaCall.modestStep
    private var ladderFloor: Int { max(powerFloor, pathFloor) }

    /// Full sharpness only over a direct pair. A relay and TCP carry video badly by construction:
    /// megabits through a relay over TCP build a queue, the picture tears, and the queue drops the
    /// pair itself. Carried over from the proven precedent: the ceiling rises only for a direct pair.
    /// CALL STREAM MEASUREMENT -- voice apart, video apart.
    ///
    /// "Video works badly" is a feeling; the numbers say what exactly is bad: does the stream take
    /// a direct path or a relay, what is the round-trip delay, how many bytes arrive, how many
    /// packets are lost, and at what resolution and frame rate the picture goes. Taken every five
    /// seconds while the conversation lasts, one line per stream.
    private var measureGen = 0   // K-9: every (re)start bumps it; a stale tick dies silently
    private var lastVideoLost = 0   // 12.9: losses are counted as a DELTA per sample, not as a running total
    // 12.11 — A CALL TELLS ITS OWN STORY IN ONE LINE. Scattered marks answer «what happened at
    // 17:33:12»; nobody can answer «how was that call» without reading a hundred of them. The
    // facts are gathered while the call lives and spoken once, at its end.
    private var sumSamples = 0            // measurement samples taken
    private var sumRelaySamples = 0       // of those, ones that rode a relay
    private var sumTunnelSamples = 0      // of those, ones whose pair rode our VPN tunnel
    private var sumPaths: Set<String> = []
    private var sumBreaks = 0             // times the media or the machine declared a break
    private var sumRestarts = 0           // ICE restarts asked for
    private var sumLadderMin = 0          // the lowest ladder step the call fell to
    private var sumPowerFloorMax = 0      // the highest power floor the call stood on
    private var sumRttSum = 0, sumRttN = 0
    private var sumLostVideo = 0
    private var sumInBytes = 0, sumOutBytes = 0
    private var endReason = "-"
    /// THE DOOR THE END CAME THROUGH (28.09, the 17:41 call that never rang on the far phone): the reason alone
    /// says «cancelled-unrung», not who cancelled it -- a finger on End, a rule of ours, or the system's own End.
    /// The word is written where the reason is written and travels with it into the day-long journal.
    private var endDoor = "-"
    private var answeredAt: Date?         // the answering hand: the callee's tap, the caller's received answer
    private var sumVideoDarkS = 0         // seconds a connected video call brought no picture in after it once had
    /// THE PICTURE'S PROGRESS PER STREAM (23.09): the frames received on each incoming video stream, by
    /// its report id (its bytes where the frame count is absent). The largest counter spoke for the call
    /// before, and after a renegotiation a dead stream's larger count hid the live one: the cover would
    /// have stood over a moving picture, and dark seconds were counted in the light.
    private var pictureSeen: [String: Int] = [:]
    private var lastJournalAt = Date.distantPast   // the journal keeps its five-second rhythm
    private var lastInBytes = 0                    // 12.10: the media flow -- now the belt beside the path
    private var pathSeen: [String: Int] = [:]      // 24.09: each pair's own count at its last sighting -- the witness of a break
    private var stallSamples = 0
    private var everFlowed = false
    private var pictureStallSamples = 0            // 23.09: samples the peer's picture stood still
    /// The one writer of CallUIModel.peerPaused (the author's word 23.09): the cover over the peer's
    /// stale frame stands only when the picture really stopped, and goes with its first new frame.
    /// The one writer of CallUIModel.selfPaused (23.09): the system took my camera (another app, the
    /// background) and gave it back -- the camera's own two words, not a guess from frames.
    private func noteSelfPicture(paused: Bool) {
        DispatchQueue.main.async {
            let m = CallUIModel.shared
            guard m.selfPaused != paused else { return }
            m.selfPaused = paused
        }
    }
    private func notePeerPicture(paused: Bool) {
        DispatchQueue.main.async {
            let m = CallUIModel.shared
            guard m.peerPaused != paused else { return }
            m.peerPaused = paused
            MontanaP2PTrace.mark("peer_picture", paused ? "paused -- the cover stands" : "back -- the cover goes")
        }
    }
    private func measureStreams() {
        measureGen += 1
        measureTick(measureGen)
    }
    private func measureTick(_ gen: Int) {
        // SILENT-OK: the conversation ended or the loop was recreated -- nothing to measure.
        // THE LOOP LIVES THROUGH A RECONNECT (23.09): the path's own word is the way back, and a loop
        // that stopped at the break left the machine only the ICE event -- which a path that never
        // broke never sends (three calls T1-T3 15:20-15:28 died waiting for it).
        guard gen == measureGen, state == "connected" || state == "reconnecting" else { measuring = false; return }
        holdOnDisk()   // the last moment the call was known alive (every five seconds)
        // The next tick is armed BEFORE the request, not inside the reply: the reply arrives on the
        // signaling thread, and one swallowed reply (the thread was busy) killed the measurement
        // until the end of the call -- six calls in a row without a single statistics line.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.measureTick(gen) }
        pc?.statistics { [weak self] report in
            guard let self else { return }
            var pair = "?", rttMs = -1, kind = "?"
            var aBytes = 0, aLost = 0, aJitMs = -1
            var vBytes = 0, vLost = 0, vW = 0, vH = 0, vFps = 0
            var pictureNow: [String: Int] = [:]   // each incoming video stream's frames (its bytes without a frame count)
            var outBytes = 0, outFrames = 0, outLimit = "-"
            var outAudio = 0, tun = 0, net = "?"   // 24.09: what the voice sends, and whether the pair rides our tunnel
            // THE PATH IS TAKEN FROM THE NOMINATED PAIR, not from a random candidate. Before, the
            // type was read off the last local candidate that turned up -- and there are always
            // several in the set -- so the "path" jumped from sample to sample on its own. From
            // exactly this came the false conclusion that "the link hops between direct and relay".
            var nominatedLocalId: String?
            // THE PATH'S OWN WORD (23.09): the bytes that reached us on each candidate pair -- the peer's
            // media AND its reports on ours. Connectivity checks are not in this count (the stat excludes
            // them), so a relay's keepalive cannot pose as the peer (the 29.08 frozen picture).
            var pathNow: [String: Int] = [:]
            for s in report.statistics.values where s.type == "candidate-pair" {
                if (s.values["nominated"] as? Bool) == true, (s.values["state"] as? String) == "succeeded" {
                    nominatedLocalId = s.values["localCandidateId"] as? String
                }
                pathNow[s.id] = Int((s.values["bytesReceived"] as? NSNumber)?.intValue ?? 0)
            }
            for s in report.statistics.values {
                switch s.type {
                case "candidate-pair" where (s.values["nominated"] as? Bool) == true:
                    rttMs = Int(((s.values["currentRoundTripTime"] as? Double) ?? -0.001) * 1000)
                    pair = (s.values["state"] as? String) ?? "?"
                case "outbound-rtp":
                    let media = (s.values["mediaType"] as? String) ?? (s.values["kind"] as? String) ?? ""
                    if media == "video" {
                        // After a renegotiation two streams of one media can coexist — one dead,
                        // one live. The LIVE one (the larger counter) speaks for the call: the
                        // dict order once froze the journal on the dead stream — the same bytes
                        // every tick of a 65s call, both phones (measured 28.08).
                        let b = Int((s.values["bytesSent"] as? NSNumber)?.intValue ?? 0)
                        if b >= outBytes {
                            outBytes = b
                            outFrames = Int((s.values["framesSent"] as? NSNumber)?.intValue ?? 0)
                            outLimit = (s.values["qualityLimitationReason"] as? String) ?? "-"
                        }
                    } else if media == "audio" {
                        // «We do not hear them» split from «they do not send»: 23.09 T1 heard 49259 bytes
                        // in five minutes and the diary could not say which side was silent.
                        outAudio = max(outAudio, Int((s.values["bytesSent"] as? NSNumber)?.intValue ?? 0))
                    }
                case "local-candidate":
                    if let want = nominatedLocalId, s.id == want {
                        kind = (s.values["candidateType"] as? String) ?? "?"
                        tun = MontanaCall.ridesTunnel(s) ? 1 : 0
                        net = (s.values["networkType"] as? String) ?? "?"
                    }
                case "inbound-rtp":
                    let media = (s.values["mediaType"] as? String) ?? (s.values["kind"] as? String) ?? ""
                    let bytes = Int((s.values["bytesReceived"] as? NSNumber)?.intValue ?? 0)
                    let lost = Int((s.values["packetsLost"] as? NSNumber)?.intValue ?? 0)
                    if media == "audio" {
                        if bytes >= aBytes {
                            aBytes = bytes; aLost = lost
                            aJitMs = Int(((s.values["jitter"] as? Double) ?? -0.001) * 1000)
                        }
                    } else if media == "video" {
                        let frames = (s.values["framesReceived"] as? NSNumber)?.intValue ?? (s.values["framesDecoded"] as? NSNumber)?.intValue
                        pictureNow[s.id] = frames ?? bytes
                        if bytes >= vBytes {
                            vBytes = bytes; vLost = lost
                            vW = Int((s.values["frameWidth"] as? NSNumber)?.intValue ?? 0)
                            vH = Int((s.values["frameHeight"] as? NSNumber)?.intValue ?? 0)
                            vFps = Int((s.values["framesPerSecond"] as? NSNumber)?.intValue ?? 0)
                        }
                    }
                default: break
                }
            }
            // THE FIRST RECEIVED FRAME gets its own mark: this is the instant a person calls
            // "video started", and until now it was absent from the journal entirely.
            if self.isVideo, vBytes > 0, !self.firstVideoIn {
                self.firstVideoIn = true
                DispatchQueue.main.async { CallUIModel.shared.remoteLive = true }   // belt for a missed sniffer
                let ms = Int(Date().timeIntervalSince(self.startedAt ?? Date()) * 1000)
                MontanaP2PTrace.mark("video_first_in", "ms=\(ms) size=\(vW)x\(vH) path=\(kind)")
            }
            // 12.10 — THE WATCHDOG OF FLOW, 23.09 — WITNESSED BY THE PATH. A call is broken for the
            // person when nothing of the peer reaches us any more. The media alone was the witness and
            // it lied three times in eight minutes (T1-T3, 15:20-15:28): the far phone went to the
            // background, the system stopped its camera, its voice was silent -- the media sum stood
            // still while the peer's reports on OUR stream kept arriving, and «connection lost» was
            // written over a living path. The path's bytes (media and reports, checks excluded) are
            // the verdict now; a picture that stops on a living path is the peer's picture pausing
            // (notePeerPicture below), never a break. Two silent samples (four seconds) declare the
            // break; the first answering sample ends it. It only judges after the media has flowed
            // at least once — the opening seconds are silent by nature and are not a break.
            // A PAIR ANSWERS BY ITS OWN GROWTH (24.09, T1 10:03:18 and 10:06:39Z). The sum over the pairs was the
            // witness, and a sum moves whenever the SET of pairs moves: a fresh transport after a restart drops the dead
            // pairs, the smaller sum read as «the path answers», and «back by path answers» was written over a line
            // nobody was on -- iOS had ended the far app for a privacy switch. Each false return spent the restart budget
            // and the deadline anew, and the dead call stood for a minute more, swallowing the peer's new call. A pair
            // answers only when its own count grows past its last sighting; a pair seen for the first time answers by any
            // byte (checks are not counted); a pair that left says nothing.
            let pathAnswered = pathNow.contains { id, bytes in bytes > (self.pathSeen[id] ?? 0) }
            self.pathSeen = pathNow
            let inNow = aBytes + vBytes
            if inNow > 0 { self.everFlowed = true }
            if self.everFlowed {
                if pathAnswered || inNow > self.lastInBytes {
                    self.lastInBytes = max(self.lastInBytes, inNow)
                    self.stallSamples = 0
                    if self.state == "reconnecting" {
                        DispatchQueue.main.async { self.leaveReconnecting("path answers") }
                    }
                } else {
                    self.stallSamples += 1
                    if self.stallSamples == 2, self.state == "connected" {
                        DispatchQueue.main.async { self.enterReconnecting("path silent 4s") }
                    }
                }
            }
            // 12.11: the summary is fed by the same sample that feeds the journal and the ladder.
            self.sumSamples += 1
            if kind != "?" { self.sumPaths.insert(kind); if kind == "relay" { self.sumRelaySamples += 1 } }
            if tun == 1 { self.sumTunnelSamples += 1 }
            if rttMs >= 0 { self.sumRttSum += rttMs; self.sumRttN += 1 }
            self.sumInBytes = max(self.sumInBytes, aBytes + vBytes)
            // THE SUMMARY'S OUT BYTES COUNT THE VOICE (25.09): out_kb=0 stood on T1's 455-second voice call whose own
            // samples wrote 1.6 MB sent -- the summary read the video counter alone while in_kb counted both.
            self.sumOutBytes = max(self.sumOutBytes, outBytes + outAudio)
            self.sumLostVideo = max(self.sumLostVideo, vLost)
            // DARK SECONDS, not lost packets: a picture that once arrived and then stopped, counted
            // by the sample clock. «lost_video» named packets and was read as pictures lost.
            // THE PEER'S PICTURE HAS ONE WITNESS (the author's word 23.09): its own frames. Two samples
            // without a new frame after it once flowed -- the peer's camera stopped (the far app went to
            // the background, another app took the screen, the camera was turned off) -- and the screen
            // covers the stale frame with the peer's blurred face, as a voice call shows it. The first
            // new frame takes the cover away.
            if self.isVideo, self.firstVideoIn {
                // A picture moved when ANY incoming video stream received a frame since the last sample.
                let moved = pictureNow.contains { $0.value > (self.pictureSeen[$0.key] ?? 0) }
                for (id, n) in pictureNow { self.pictureSeen[id] = max(self.pictureSeen[id] ?? 0, n) }
                if moved {
                    self.pictureStallSamples = 0
                    self.notePeerPicture(paused: false)
                } else {
                    self.sumVideoDarkS += 2
                    self.pictureStallSamples += 1
                    if self.pictureStallSamples == 2 { self.notePeerPicture(paused: true) }
                }
            } else if !self.isVideo {
                self.pictureStallSamples = 0
                self.notePeerPicture(paused: false)
            }
            guard Date().timeIntervalSince(self.lastJournalAt) >= 5 else { return }
            self.lastJournalAt = Date()
            let via = tun == 1 ? "tunnel" : net
            MontanaP2PTrace.mark("call_audio", "path=\(kind) pair=\(pair) rtt_ms=\(rttMs) bytes=\(aBytes) lost=\(aLost) jitter_ms=\(aJitMs) via=\(via) out_bytes=\(outAudio) mic=\(self.localAudio?.isEnabled == true ? 1 : 0)")
            if self.isVideo {
                // OUTGOING VIDEO IS MEASURED TOO: without it "zero bytes" cannot be split into "we
                // do not send" and "it does not reach us" -- both sides spoke of the same zero.
                MontanaP2PTrace.mark("call_video", "path=\(kind) rtt_ms=\(rttMs) in_bytes=\(vBytes) lost=\(vLost) size=\(vW)x\(vH) fps=\(vFps) out_bytes=\(outBytes) out_frames=\(outFrames) limit=\(outLimit) cam_frames=\(self.frameCounter?.frames ?? 0) via=\(via)")
                // 12.9: the same sample that speaks in the journal also moves the ladder — one
                // measurement, one owner, no second loop to drift ([C-1]).
                let lostDelta = max(0, vLost - self.lastVideoLost)
                self.lastVideoLost = vLost
                DispatchQueue.main.async { self.applyLadder(limit: outLimit, lostDelta: lostDelta, rttMs: rttMs) }
            }
        }
    }

    /// over UDP on the phone's own radio or Wi-Fi; on a relay, TCP or our tunnel it stays modest.
    private func raiseVideoCeiling() {
        guard isVideo else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.state == "connected" else { return }
            self.pc?.statistics { [weak self] report in
                guard let self else { return }
                var localIds = Set<String>()
                var tunnelIds = Set<String>()
                for s in report.statistics.values where s.type == "local-candidate" {
                    if MontanaCall.ridesTunnel(s) { tunnelIds.insert(s.id); continue }
                    if (s.values["candidateType"] as? String) != "relay",
                       (s.values["protocol"] as? String)?.lowercased() == "udp" {
                        localIds.insert(s.id)
                    }
                }
                let nominatedLocal = report.statistics.values.compactMap { s -> String? in
                    guard s.type == "candidate-pair",
                          (s.values["state"] as? String) == "succeeded",
                          (s.values["nominated"] as? Bool) == true else { return nil }
                    return s.values["localCandidateId"] as? String
                }
                let direct = nominatedLocal.contains { localIds.contains($0) }
                let why = nominatedLocal.contains { tunnelIds.contains($0) } ? "the pair rides a tunnel"
                    : (nominatedLocal.isEmpty ? "no pair nominated yet" : "the pair goes through a relay or over TCP")
                DispatchQueue.main.async {
                    guard self.state == "connected" else { return }
                    // The proof moves the path floor BOTH ways: a pair re-formed after a restart (Wi-Fi to the
                    // tunnel, direct to a relay) does not keep the top step the old pair earned.
                    self.pathFloor = direct ? 0 : MontanaCall.modestStep
                    if direct {
                        self.ladderStep = self.ladderFloor; self.ladderMovedAt = Date(); self.ladderGoodTicks = 0   // 12.9: a proven direct pair starts at the top step
                        self.setVideoCeiling(MontanaCall.videoLadder[self.ladderStep])
                DispatchQueue.main.async { CallUIModel.shared.signal = 2; CallUIModel.shared.powerSaving = false }
                        self.tlog("video: ceiling raised -- the pair is direct over UDP")
                    } else {
                        if self.ladderStep < self.ladderFloor {
                            self.ladderStep = self.ladderFloor; self.ladderMovedAt = Date(); self.ladderGoodTicks = 0
                        }
                        self.setVideoCeiling(MontanaCall.videoLadder[self.ladderStep])
                        self.tlog("video: ceiling held modest (\(MontanaCall.videoLadder[self.ladderStep] / 1000) kbps) -- \(why)")
                    }
                }
            }
        }
    }

    /// THE PAIR RIDES OUR TUNNEL (24.09): the candidate's own address (a host candidate) or its base (a
    /// reflexive one) is an address our packet tunnel holds (MontanaP2PNode.isTunnelHost), or the engine
    /// itself names the adapter a VPN. Through the tunnel a datagram is not a datagram: VLESS, VMess and
    /// Trojan carry UDP inside their one TCP stream -- the engine turns every UDP request into XUDP frames on
    /// the connection (xray-core v1.260327.0, proxy/vless/outbound/outbound.go 315-332) -- so one loss on the
    /// radio becomes seconds of delay for every packet behind it, and no loss is ever seen. Measured 23.09
    /// 20:30Z, T1 on LTE through a VLESS tcp reality subscription: round trip 371 ms at the median, 2.8 s at
    /// the ninetieth sample, 7.5 s at worst, eleven video packets lost in five minutes -- and the proof
    /// above called that pair «direct over UDP» and opened 2 Mbps into it. Shadowsocks carries UDP as
    /// datagrams (proxy/shadowsocks/client.go 57-65) and would earn the top step; the call does not know
    /// the tunnel's protocol yet, so every tunnel pair stays modest until that is published to the call.
    private static func ridesTunnel(_ s: RTCStatistics) -> Bool {
        if (s.values["networkType"] as? String) == "vpn" { return true }
        if (s.values["vpn"] as? NSNumber)?.boolValue == true { return true }
        for key in ["address", "ip", "relatedAddress"] {
            if let a = s.values[key] as? String, MontanaP2PNode.isTunnelHost(a) { return true }
        }
        return false
    }

    /// A connection's name: the DTLS certificate's fingerprint its description carries. It holds through every
    /// fresh-checks ask and every media renegotiation of one connection, and a new connection has a new one.
    /// A description's lines end in CR LF, and Swift reads CR LF as ONE character: a split on "\n" or "\r" never split
    /// a real description, no fingerprint was ever found, and a run that came back was buried as its own copy (T3 and T1,
    /// 24.09 20:17). The platform's own newline test splits every kind (proved on a CR LF description and a LF one).
    static func fingerprint(_ sdp: String) -> String? {
        for line in sdp.split(whereSeparator: \.isNewline) where line.hasPrefix("a=fingerprint:") {
            return String(line.dropFirst("a=fingerprint:".count)).trimmingCharacters(in: .whitespaces).lowercased()
        }
        return nil
    }

    private func resetSignalFlags() {
        signalLock.lock(); answerFastApplied = false; remoteIceSeen = false; signalLock.unlock()
    }
    private var answerFastAppliedNow: Bool { signalLock.lock(); defer { signalLock.unlock() }; return answerFastApplied }
    private func markRemoteIceSeen() { signalLock.lock(); remoteIceSeen = true; signalLock.unlock() }
    private var remoteIceSeenNow: Bool { signalLock.lock(); defer { signalLock.unlock() }; return remoteIceSeen }
    /// K-1: one winner applies the answer, whichever thread saw it first.
    private func claimAnswerFast() -> Bool {
        signalLock.lock(); defer { signalLock.unlock() }
        if answerFastApplied { return false }
        answerFastApplied = true
        return true
    }
    private func stashIce(_ c: RTCIceCandidate) { signalLock.lock(); pendingIce.append(c); signalLock.unlock() }
    private func flushIce() {
        signalLock.lock()
        let batch = pendingIce
        pendingIce = []
        signalLock.unlock()
        for c in batch { pc?.add(c) { _ in } }
    }

    // Reachability like cellular: if within 8 s there's no «phone is ringing» confirmation and no answer —
    // the subscriber is offline (turned off/offline). We display and announce it.
    private func armReachTimeout(seconds: Double) {
        DispatchQueue.main.async {
            self.reachTimer?.invalidate()
            self.reachTimer = self.callTimer(seconds, repeats: false) { [weak self] _ in
                guard let self else { return }
                // We don't announce «Unavailable»: the ring often lands late while the peer is present. We just
                // keep ringing until the 60s hard timeout (then «missed»). [author: remove «unavailable»]
                if !self.peerRinging && self.state != "connected" {
                    self.tlog("reach-timeout \(Int(seconds))s — peer hasn't confirmed the ring yet, keep calling (no false «unreachable»)")
                    // THE CALLER HEARS THE TRUTH IT CAN KNOW (13.09 08:41: the node accepted the
                    // wake, APNs accepted the push, the far phone was out of reach for eight
                    // minutes — and the caller watched «Calling…» for thirty-seven seconds). No word
                    // «ringing» in twenty seconds is the fact; the diary says it (ring_silent) and the
                    // ringing goes on until the minute runs out or the hand ends it. The screen keeps
                    // its one status line (the author's word 13.09: no line under the name).
                    if self.state == "outgoing" {
                        MontanaP2PTrace.mark("ring_silent", "s=\(Int(seconds))")
                    }
                }
            }
        }
    }


    /// The epoch of the current call -- the first 16 characters of the random call seed. Every
    /// signal is stamped with it; a foreign or old epoch is dropped on receipt, so a new call is not
    /// poisoned by the corpse of the previous one from the node queue (a class the server model did
    var callEpoch: String? { callSeed.map { String($0.base64EncodedString().prefix(16)) } }

    /// THE LIFE OF A CALL IS ONE NUMBER (13.09, the author's word): the caller rings this long,
    /// the node keeps the voip wake alive this long, the callee refuses an offer older than this,
    /// a delivered push older than this is dead. Four gates, one value — they cannot drift apart.
    static let callLifeS: TimeInterval = 90

    private func armHardTimeout() {
        DispatchQueue.main.async { self.startRouteWatch() }
        DispatchQueue.main.async {
            self.connectHardTimer?.invalidate()
            self.connectHardTimer = self.callTimer(MontanaCall.callLifeS, repeats: false) { [weak self] _ in
                // A SETUP RULE JUDGES SETUP ONLY (23.09, 15:21:46): «checking» and «connected» came in one
                // millisecond, the connect cleared a timer this async hop had not created yet, and ninety
                // seconds later it found the call reconnecting and ended a call that had talked for a
                // minute and a half. A call that ever connected belongs to the reconnect deadline.
                guard let self, self.connectedAt == nil, self.state != "idle" else { return }
                MontanaP2PTrace.mark("call_timeout", "hard \(Int(MontanaCall.callLifeS))s state=\(self.state)")
                self.endByRule("timeout")
            }
        }
    }

    /// THE PAIRS ARE NAMED WHEN THEY FAIL (29.09). The diary held «ice=failed» and nothing else, and the relay hop keeps
    /// no journal of its own by construction: whether a relay candidate ever existed, and which pairs died, was nobody's
    /// word. One line per verdict: the candidates by type, transport and family, the pairs by state -- addresses never.
    private func dumpCandidatePairs(tag: String) {
        guard let pc = pc else { return }
        pc.statistics { report in
            var cand: [String: String] = [:]
            var local: [String: Int] = [:], remote: [String: Int] = [:]
            for (_, st) in report.statistics where st.type == "local-candidate" || st.type == "remote-candidate" {
                let t = (st.values["candidateType"] as? String) ?? "?"
                let p = (st.values["protocol"] as? String) ?? "?"
                let rp = (st.values["relayProtocol"] as? String) ?? ""
                let fam = ((st.values["address"] as? String) ?? "").contains(":") ? "6" : "4"
                let word = t + (rp.isEmpty ? "" : "(" + rp + ")") + "/" + p + "/v" + fam
                cand[st.id] = word
                if st.type == "local-candidate" { local[word, default: 0] += 1 } else { remote[word, default: 0] += 1 }
            }
            var pairs: [String: Int] = [:]
            for (_, st) in report.statistics where st.type == "candidate-pair" {
                let l = cand[(st.values["localCandidateId"] as? String) ?? ""] ?? "?"
                let r = cand[(st.values["remoteCandidateId"] as? String) ?? ""] ?? "?"
                let s = (st.values["state"] as? String) ?? "?"
                pairs[l + "-" + r + ":" + s, default: 0] += 1
            }
            let body = "tag=\(tag) local=\(Self.foldKinds(local)) remote=\(Self.foldKinds(remote)) pairs=\(Self.foldKinds(pairs))"
            MontanaP2PTrace.mark("call_pairs", body)
            MontanaLog.event("E2E-CALL pairs " + body)
        }
    }

    /// The type, transport and family of one candidate line («typ host», «typ srflx», «typ relay») -- never its address.
    static func candidateKind(_ sdp: String) -> String {
        let f = sdp.split(separator: " ").map(String.init)
        var typ = "?"
        if let i = f.firstIndex(of: "typ"), i + 1 < f.count { typ = f[i + 1] }
        let proto = f.count > 2 ? f[2].lowercased() : "?"
        let fam = f.count > 4 && f[4].contains(":") ? "6" : "4"
        return typ + "/" + proto + "/v" + fam
    }
    static func foldKinds(_ d: [String: Int]) -> String {
        d.isEmpty ? "-" : d.sorted { $0.key < $1.key }.map { "\($0.key)x\($0.value)" }.joined(separator: ",")
    }

    /// A FAILED PATH BEFORE THE CONNECT IS ANSWERED, NOT WATCHED (29.09): see setupAsks. The engine judges, the machine
    /// asks; the ask goes out by the one owner of «fresh checks» (requestIceRestart), whose settle gate stands aside for a
    /// verdict already in. The callee asks after its lead, as always; the glare rule answers a double ask.
    private func setupPathFailed() {
        guard state != "idle", !ended, pc != nil else { return }
        dumpCandidatePairs(tag: "failed")
        setupAsks += 1
        guard setupAsks <= Self.setupAskMax else {
            MontanaP2PTrace.mark("call_setup", "no path after \(setupAsks - 1) fresh asks, the last on the relay alone — ending")
            MontanaLog.event("E2E-CALL setup verdict=no-path asks=\(setupAsks - 1)")
            endByRule("no-path")
            return
        }
        let relay = setupAsks == Self.setupAskMax
        MontanaP2PTrace.mark("call_setup", "path failed before the connect — ask n=\(setupAsks) \(relay ? "relay only, TLS door first" : "every road, fresh pass")")
        MontanaLog.event("E2E-CALL setup ask=\(setupAsks) relay_only=\(relay ? 1 : 0)")
        let gen = callGen
        Task { @MainActor in
            let cfg = await self.rtcConfig(relayOnly: relay, freshPass: true)
            guard gen == self.callGen, let pcx = self.pc, self.state != "idle", !self.ended else { return }
            self.askedRelayOnly = relay
            if !pcx.setConfiguration(cfg) { MontanaP2PTrace.mark("call_setup", "the engine refused the new configuration — the ask rides the old one") }
            self.restartAskedAt = .distantPast
            self.requestIceRestart(reason: "setup ask n=\(self.setupAsks)")
        }
    }

    // Diagnostics: which ICE pair is actually selected (type/protocol) + bytes — into the local trace.
    func reportSelectedPair(tag: String) {
        guard let pc = pc else { return }
        pc.statistics { report in
            var pairInfo = "none"; var bytesTx = "0"; var bytesRx = "0"
            var candById: [String: (type: String, proto: String)] = [:]
            for (_, st) in report.statistics {
                if st.type == "local-candidate" || st.type == "remote-candidate" {
                    let t = (st.values["candidateType"] as? String) ?? "?"
                    let p = (st.values["protocol"] as? String) ?? "?"
                    let rp = (st.values["relayProtocol"] as? String) ?? ""
                    candById[st.id] = (t + (rp.isEmpty ? "" : "(\(rp))"), p)
                }
            }
            for (_, st) in report.statistics where st.type == "candidate-pair" {
                let nominated = (st.values["nominated"] as? Bool) ?? false
                let state = (st.values["state"] as? String) ?? ""
                guard nominated, state == "succeeded" else { continue }
                let l = candById[(st.values["localCandidateId"] as? String) ?? ""]
                let r = candById[(st.values["remoteCandidateId"] as? String) ?? ""]
                bytesTx = String((st.values["bytesSent"] as? UInt64) ?? 0)
                bytesRx = String((st.values["bytesReceived"] as? UInt64) ?? 0)
                pairInfo = "L=\(l?.type ?? "?")/\(l?.proto ?? "?") R=\(r?.type ?? "?")/\(r?.proto ?? "?")"
            }
            let au = "act:\(self.audioActive ? 1 : 0)/en:\(RTCAudioSession.sharedInstance().isAudioEnabled ? 1 : 0)"
            let epx = Int(Date().timeIntervalSince1970 * 1000)
            let msx = Int(Date().timeIntervalSince(self.callT0) * 1000)
            if !self.firstMediaLogged, (Int(bytesTx) ?? 0) > 0 || (Int(bytesRx) ?? 0) > 0 {
                self.firstMediaLogged = true
                E2E.shared.callDebug("\(self.isInitiator ? "CER" : "CEE") +\(msx)ms abs=\(epx) ⑥ FIRST MEDIA tx:\(bytesTx) rx:\(bytesRx)")
            }
            E2E.shared.callDebug("\(tag) +\(msx)ms abs=\(epx) pair:\(pairInfo) tx:\(bytesTx) rx:\(bytesRx) \(au) state:\(self.state)")
        }
    }

    private var pairTimer: Timer?

    // Proximity sensor: an audio call without speakerphone = phone at the ear → the screen turns off,
    // accidental touches are prevented (behavior of a normal cellular call). Video/speaker — off.
    /// EVERY CHANGE OF THE AUDIO ROUTE DURING A CALL, with the system's own reason (15.28): a
    /// category set anew, a device plugged in, an override withdrawn — each names itself, and the
    /// diary shows who moved the sound after the person chose the speaker.
    private static var routeObserver: NSObjectProtocol?
    static func watchRoute() {
        guard routeObserver == nil else { return }
        MontanaAudioRoute.read("watch")
        routeObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { n in
            let reason = (n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap { AVAudioSession.RouteChangeReason(rawValue: $0) }
            let out = MontanaAudioRoute.read(reason.map { String(describing: $0) } ?? "-")
            guard MontanaCall.stateSnapshot != "idle" else { return }
            let cat = AVAudioSession.sharedInstance().category.rawValue.replacingOccurrences(of: "AVAudioSessionCategory", with: "")
            MontanaP2PTrace.mark("audio_route", "reason=\(reason.map { String(describing: $0) } ?? "-") outputs=\(out.ports) category=\(cat) speaker=\(MontanaCall.shared.speakerOn ? 1 : 0)")
            // THE ROUTE IS THE SYSTEM'S (the critic's word 15.09, measured 11:05: the app ordered
            // the loudspeaker over a connected headset, the headset took the sound back two seconds
            // later, and the button stayed lit). An external output ends the app's wish for the
            // loudspeaker, so no re-activation replays it; the button shows where the sound IS.
            if out.isExternal { MontanaCall.shared.speakerOn = false }
            // THE PERSON'S CHOICE IN THE SYSTEM MENU IS THE MACHINE'S CHOICE (the author's word 20.09:
            // «I put it on the loudspeaker while it rings and it lands there only after the connect»).
            // The route sheet sets the override itself and the machine never learned it: speakerOn
            // stayed false, and every replay of the session — the fallback activation, CallKit's
            // didActivate, the connect — re-asserted the machine's own wish, the receiver. Now the
            // override is read back into the machine, and every replay keeps the loudspeaker.
            if reason == .override, !out.isExternal {
                MontanaCall.shared.speakerOn = (out.current == .speaker)
                MontanaP2PTrace.mark("speaker", "\(out.current == .speaker ? "on" : "off") by=system route=\(out.ports) state=\(MontanaCall.stateSnapshot) tone=\(MontanaCall.shared.tonePlaying ? 1 : 0)")
            }
            // THE PHONE'S OUTPUT TAKES THE PHONE'S MICROPHONE (the reference's rule; measured 15:43:
            // the system menu put the sound on the loudspeaker, the headset's voice link kept the
            // microphone, and a second later «new device available» pulled the sound back to the
            // headset — twice). A choice of the phone or its loudspeaker is completed with the
            // built-in microphone; the headset's link then closes and nothing pulls the sound back.
            if reason == .override || reason == .categoryChange { MontanaAudioRoute.completePhoneChoice(out) }
            DispatchQueue.main.async { CallUIModel.shared.speaker = (out.current == .speaker) }
            MontanaCall.shared.updateProximity()   // a headset in or out: the sensor is the call's only while the sound stands at the ear
        }
    }

    private func updateProximity() {
        DispatchQueue.main.async {
            // The call holds the sensor while its sound stands at the ear (MTProximity, the sensor's one owner, 24.09).
            MTProximity.hold("call", self.state != "idle" && !self.isVideo && !self.speakerOn && !MontanaAudioRoute.isExternal)
        }
    }

    private func setState(_ s: String) {
        let born = state == "idle" && s != "idle"
        state = s
        updateProximity()
        // A CALL IS BORN — THE STANDING QUESTION IS CUT (13.09 15:20): the long question of an idle
        // phone stood on until its own deadline while the call needed the short one. The machine's
        // state is the call's from the line above, so the fresh question is the call's (wait 3).
        if born { MontanaWakePush.cutStandingQuestion("call born") }
        if born { DispatchQueue.main.async { VoicePlayer.shared.yieldToCall() } }   // the call holds the sound from its birth (24.09)
        if born || s == "idle" { MontanaAudioRoute.read(born ? "call born" : "call idle") }
        DispatchQueue.main.async {
            self.onStateChange?(s, self.peer)
            if s == "connected", self.connectedAt == nil {
                self.connectedAt = Date()
                Task { @MainActor in MTMintBeat.run() }   // both sides mint the talk (MTCallMint, 07.10.2026)
                self.powerStart = MontanaPower.snapshot()   // every call, a voice call too: the ladder's tick ran only for video
                self.pictureSeen = [:]
                self.autoSpeakerOnVideo()
                self.protectVoice()   // 12.9: the voice takes its share before anything competes for the channel
                self.ladderStep = self.ladderFloor; self.ladderMovedAt = Date(); self.ladderGoodTicks = 0; self.lastVideoLost = 0
        DispatchQueue.main.async { CallUIModel.shared.signal = 2; CallUIModel.shared.powerSaving = false }
                self.lastInBytes = 0; self.stallSamples = 0; self.everFlowed = false; self.lastJournalAt = .distantPast
                self.pathSeen = [:]; self.pictureStallSamples = 0
                self.holdOnDisk(force: true)   // the call stood connected: a run that comes back goes into it
            }
            if s == "connected" {
                MTScreenShare.shared.onStart = { [weak self] in self?.startScreenShare() }
                MTScreenShare.shared.onFrame = { [weak self] pb, orient, pts in self?.pushScreenFrame(pb, orientation: orient, ptsNs: pts) }
                MTScreenShare.shared.onStop = { [weak self] in DispatchQueue.main.async { self?.stopScreenShare() } }
                MTScreenShare.shared.arm()
            }
            // Signalling arrives over the peer channel; the timer only reaps state when the call ends.
            if s == "idle" {
                CallUIModel.shared.pipSwapped = false
                CallUIModel.shared.remoteLive = false; CallUIModel.shared.mirrorLocal = true
                CallUIModel.shared.peerPaused = false
                CallUIModel.shared.selfPaused = false
                self.reconnectTone?.stop(); self.reconnectTone = nil   // 12.10: a tone never outlives its call
                self.frameSniffer = nil
                self.pairTimer?.invalidate(); self.pairTimer = nil
            } else if self.pairTimer == nil {
                self.pairTimer = self.callTimer(5, repeats: true) { [weak self] _ in
                    self?.reportSelectedPair(tag: "tick")
                }
            }
        }
    }

    // 40pt template glyph (alpha mask) for the native call UI — the Montana Ɉ.
    static func appGlyphTemplate() -> Data? {
        let size = CGSize(width: 40, height: 40)
        let img = UIGraphicsImageRenderer(size: size).image { _ in
            let para = NSMutableParagraphStyle(); para.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 34, weight: .bold),
                .foregroundColor: UIColor.white, .paragraphStyle: para]
            ("Ɉ" as NSString).draw(in: CGRect(x: 0, y: 1, width: 40, height: 38), withAttributes: attrs)
        }
        return img.pngData()
    }


    func reportIncoming(uuid: UUID, from: String, video: Bool, done: (() -> Void)? = nil) {
        nativeHandle = MontanaCallHandle.token(for: from)   // the token is born BEFORE the first showing to the system
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: nativeHandle)   // a one-time token, not the conversation link
        update.localizedCallerName = callerName(from)
        update.hasVideo = video
        update.supportsHolding = true   // 12.3: Hold & Accept lives beside End & Accept
        reportedCalls.insert(uuid)   // the system's list now holds a call of ours (sweepSystemCalls)
        provider.reportNewIncomingCall(with: uuid, update: update) { err in
            if let err = err { E2ELog.write("call: reportIncoming err \(err)"); E2E.shared.callDebug("‼️ reportIncoming ERR \(err.localizedDescription)") }
            if let done { DispatchQueue.main.async(execute: done) }   // what must follow the report waits for it (25.09)
        }
    }

    // ── Ringback at the caller: 425 Hz, 1 s tone / 4 s pause (European) ──
    private func ensureAudioActive() {
        guard !audioActive else { return }
        let s = RTCAudioSession.sharedInstance()
        s.lockForConfiguration()
        let cfg = RTCAudioSessionConfiguration.webRTC()
        cfg.category = AVAudioSession.Category.playAndRecord.rawValue
        cfg.mode = AVAudioSession.Mode.voiceChat.rawValue
        cfg.categoryOptions = [.allowBluetooth, .allowBluetoothA2DP]
        try? s.setConfiguration(cfg, active: true)
        if speakerOn, !MontanaAudioRoute.isExternal { try? s.overrideOutputAudioPort(.speaker) }   // the chosen route survives re-activation — never over an external output
        s.isAudioEnabled = true
        s.unlockForConfiguration()
        audioActive = true
        autoSpeakerOnVideo()   // the sound is born here: a video call that connected before it goes aloud now
    }

    private func startRingback() {
        ringbackWanted = true
        if audioActive { playRingbackNow(); return }
        // The session is activated by CallKit (didActivate finishes playback). Safety net: if activation didn't arrive
        // within 1.2 s (CallKit failure) — activate ourselves. Immediate self-activation is FORBIDDEN:
        // CallKit grabs the session right after and mutes the player (bug «ringback disappeared»).
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, self.ringbackWanted, self.ringback == nil, self.state == "outgoing" else { return }
            self.ensureAudioActive()
            self.playRingbackNow()
        }
    }

    private func playRingbackNow() {
        guard ringbackWanted, state == "outgoing", !unreachable else { return }
        if ringback == nil, let url = MontanaCall.ringbackFile() {
            ringback = try? AVAudioPlayer(contentsOf: url)
            ringback?.numberOfLoops = -1
            ringback?.volume = 1.0
        }
        ringback?.play()   // a repeated call after CallKit grabs the session resumes the sound
    }

    private func stopRingback() { ringbackWanted = false; ringback?.stop(); ringback = nil }
    /// A tone of the dial (the search pips or the ringback) is sounding right now — the diary's
    /// proof that a loudspeaker choice while ringing had something to carry.
    var tonePlaying: Bool { ringback?.isPlaying == true || dialTone?.isPlaying == true }

    /// THE LOUDSPEAKER CHOSEN WHILE RINGING SURVIVES THE CONNECT (the author's word 20.09). The
    /// machine's fact is re-asserted on the session from the moments that touch it; idempotent —
    /// nothing is switched when the sound already stands there.
    private func reassertSpeaker(_ why: String) {
        guard speakerOn, !MontanaAudioRoute.isExternal else { return }
        Self.audioQ.async {
            let outs = AVAudioSession.sharedInstance().currentRoute.outputs
            if outs.contains(where: { $0.portType == .builtInSpeaker }) { return }
            let s = RTCAudioSession.sharedInstance()
            s.lockForConfiguration()
            do { try s.overrideOutputAudioPort(.speaker) } catch { E2ELog.write("call: speaker reassert err \(error)") }
            s.unlockForConfiguration()
            MontanaP2PTrace.mark("speaker", "reassert why=\(why) was=\(outs.map { $0.portType.rawValue }.joined(separator: ","))")
        }
    }

    // ── The searching tone at the caller: two low pips every three seconds, from the dial until
    // the peer's own word «ringing». The ringback used to start the instant the call was dialed,
    // before anything had reached the other phone: a person heard «their phone is ringing» while
    // the offer was still looking for a door, or the phone was off. The carrier's order: no ringback
    // before the far phone confirms ringing. The caption changes with the tone (statusText), from the
    // same fact, so the ear and the eye cannot disagree.
    private func startDialTone() {
        dialToneWanted = true
        if audioActive { playDialToneNow(); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, self.dialToneWanted, self.dialTone == nil, self.state == "outgoing" else { return }
            self.ensureAudioActive()
            self.playDialToneNow()
        }
    }

    private func playDialToneNow() {
        guard dialToneWanted, state == "outgoing", !peerRinging else { return }
        if dialTone == nil, let url = MontanaCall.reconnectFile() {
            dialTone = try? AVAudioPlayer(contentsOf: url)
            dialTone?.numberOfLoops = -1
            dialTone?.volume = 0.6
            MontanaP2PTrace.mark("call_tone", "search ms=\(Int(Date().timeIntervalSince(startedAt ?? Date())*1000))")
        }
        dialTone?.play()
    }

    private func stopDialTone() { dialToneWanted = false; dialTone?.stop(); dialTone = nil }

    private func playDialSoundNow() { if peerRinging { playRingbackNow() } else { playDialToneNow() } }

    private static var _ringbackURL: URL?
    private static func ringbackFile() -> URL? {
        if let u = _ringbackURL { return u }
        let sr = 8000, total = 5 * sr, on = 1 * sr
        var samples = [Int16](repeating: 0, count: total)
        for i in 0..<on {
            let v = sin(2.0 * Double.pi * 425.0 * Double(i) / Double(sr))
            samples[i] = Int16(v * 9000)
        }
        var data = Data()
        let byteRate = sr * 2
        func le32(_ v: Int) -> [UInt8] { [UInt8(v & 0xff), UInt8((v>>8) & 0xff), UInt8((v>>16) & 0xff), UInt8((v>>24) & 0xff)] }
        func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xff), UInt8((v>>8) & 0xff)] }
        let dataBytes = total * 2
        data.append(contentsOf: Array("RIFF".utf8)); data.append(contentsOf: le32(36 + dataBytes))
        data.append(contentsOf: Array("WAVE".utf8)); data.append(contentsOf: Array("fmt ".utf8))
        data.append(contentsOf: le32(16)); data.append(contentsOf: le16(1)); data.append(contentsOf: le16(1))
        data.append(contentsOf: le32(sr)); data.append(contentsOf: le32(byteRate)); data.append(contentsOf: le16(2)); data.append(contentsOf: le16(16))
        data.append(contentsOf: Array("data".utf8)); data.append(contentsOf: le32(dataBytes))
        for s in samples { data.append(contentsOf: le16(Int(s) & 0xffff)) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mt_ringback.wav")
        try? data.write(to: url)
        _ringbackURL = url
        return url
    }

    private func startWaitingTone() {
        guard state == "connected" || state == "active" || state == "reconnecting" else { return }
        if waitingTone == nil, let url = MontanaCall.waitingFile() {
            waitingTone = try? AVAudioPlayer(contentsOf: url)
            waitingTone?.numberOfLoops = -1
            waitingTone?.volume = 0.5   // the pips ride OVER the talk, they must not drown it
        }
        waitingTone?.play()
    }
    private func stopWaitingTone() { waitingTone?.stop(); waitingTone = nil }

    /// 12.10 — THE VOICE OF A BREAK. A silent «Connecting…» reads as a frozen phone: the person
    /// keeps talking into a dead line and learns of the break only when the call ends. A tone
    /// says it in the ear, where the conversation is. Deliberately quiet and slow — this is the
    /// sound of waiting, not of an alarm: two low pips every three seconds, the carrier's manner.
    private var reconnectTone: AVAudioPlayer?
    private static var _reconnectURL: URL?
    private static func reconnectFile() -> URL? {
        if let u = _reconnectURL { return u }
        let sr = 8000, total = 3 * sr
        var samples = [Int16](repeating: 0, count: total)
        // Two pips of 120 ms at 380 Hz with 100 ms between them, then two and a half seconds of
        // silence — the ear reads it as «waiting», not as «error».
        for pip in 0..<2 {
            let start = pip * (sr * 220 / 1000)
            for i in 0..<(sr * 120 / 1000) {
                let v = sin(2.0 * Double.pi * 380.0 * Double(i) / Double(sr))
                // A soft edge: a square start clicks, and a click reads as a fault.
                let edge = min(1.0, min(Double(i), Double(sr * 120 / 1000 - i)) / Double(sr / 100))
                samples[start + i] = Int16(v * edge * 6000)
            }
        }
        var data = Data()
        func le32(_ v: Int) -> [UInt8] { [UInt8(v & 0xff), UInt8((v>>8) & 0xff), UInt8((v>>16) & 0xff), UInt8((v>>24) & 0xff)] }
        func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xff), UInt8((v>>8) & 0xff)] }
        let dataBytes = total * 2
        data.append(contentsOf: Array("RIFF".utf8)); data.append(contentsOf: le32(36 + dataBytes))
        data.append(contentsOf: Array("WAVE".utf8)); data.append(contentsOf: Array("fmt ".utf8))
        data.append(contentsOf: le32(16)); data.append(contentsOf: le16(1)); data.append(contentsOf: le16(1))
        data.append(contentsOf: le32(sr)); data.append(contentsOf: le32(sr * 2)); data.append(contentsOf: le16(2)); data.append(contentsOf: le16(16))
        data.append(contentsOf: Array("data".utf8)); data.append(contentsOf: le32(dataBytes))
        for x in samples { data.append(contentsOf: le16(Int(x) & 0xffff)) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mt_reconnect.wav")
        try? data.write(to: url)
        _reconnectURL = url
        return url
    }

    /// The tone and the caption are ONE act, so they can never disagree: the state says «the link
    /// broke» and both the ear and the eye learn it at the same instant, and both are silenced by
    /// the same return. Split across two places they drift — the caption once stayed on a
    /// reconnected call while the tone had already stopped.
    private func reconnectVoice(_ on: Bool) {
        DispatchQueue.main.async {
            if on {
                guard self.state == "reconnecting" else { return }
                if self.reconnectTone == nil, let url = MontanaCall.reconnectFile() {
                    self.reconnectTone = try? AVAudioPlayer(contentsOf: url)
                    self.reconnectTone?.numberOfLoops = -1
                    self.reconnectTone?.volume = 0.35   // under the talk: the line may come back mid-word
                }
                let played = self.reconnectTone?.play() ?? false
                MontanaP2PTrace.mark("call_reconnect", "voice on played=\(played ? 1 : 0)")
            } else {
                guard self.reconnectTone != nil else { return }
                self.reconnectTone?.stop(); self.reconnectTone = nil
                MontanaP2PTrace.mark("call_reconnect", "voice off")
            }
        }
    }

    private static var _waitingURL: URL?
    private static func waitingFile() -> URL? {
        if let u = _waitingURL { return u }
        // The carrier's call-waiting: two short 440 Hz pips, then silence — a 5 s loop.
        let sr = 8000, total = 5 * sr
        let pip = sr / 5, gap = sr / 5
        var samples = [Int16](repeating: 0, count: total)
        for p in 0..<2 {
            let start = p * (pip + gap)
            for i in 0..<pip {
                let v = sin(2.0 * Double.pi * 440.0 * Double(i) / Double(sr))
                samples[start + i] = Int16(v * 7000)
            }
        }
        var data = Data()
        let byteRate = sr * 2
        func le32(_ v: Int) -> [UInt8] { [UInt8(v & 0xff), UInt8((v>>8) & 0xff), UInt8((v>>16) & 0xff), UInt8((v>>24) & 0xff)] }
        func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xff), UInt8((v>>8) & 0xff)] }
        let dataBytes = total * 2
        data.append(contentsOf: Array("RIFF".utf8)); data.append(contentsOf: le32(36 + dataBytes))
        data.append(contentsOf: Array("WAVE".utf8)); data.append(contentsOf: Array("fmt ".utf8))
        data.append(contentsOf: le32(16)); data.append(contentsOf: le16(1)); data.append(contentsOf: le16(1))
        data.append(contentsOf: le32(sr)); data.append(contentsOf: le32(byteRate)); data.append(contentsOf: le16(2)); data.append(contentsOf: le16(16))
        data.append(contentsOf: Array("data".utf8)); data.append(contentsOf: le32(dataBytes))
        for s in samples { data.append(contentsOf: le16(Int(s) & 0xffff)) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mt_waiting.wav")
        try? data.write(to: url)
        _waitingURL = url
        return url
    }

    // Operator unavailability signal (SIT): three ascending tones 950/1400/1800 Hz of ~0.33 s each.
    private static var _sitURL: URL?
}

// ── CXProviderDelegate ──
extension MontanaCall: CXProviderDelegate {
    func providerDidReset(_ provider: CXProvider) {
        E2E.shared.callDebug("‼️ providerDidReset — CallKit reset the provider")
        tearParked(reason: .failed)   // CallKit forgot the held uuid — adoption would be a phantom
        // THE RESET IS A RULE'S END, NAMED AND TOLD TO THE FAR PHONE (25.09): the first knock had already left when
        // the system reset the provider, and the far phone rang for a call this machine had written off.
        MontanaP2PTrace.mark("call_end_rule", "why=callkit-reset state=\(state) connected=\(connectedAt == nil ? 0 : 1)")
        if endReason == "-" { endReason = "callkit-reset" }
        sendEndSignal()
        cleanup()
    }
    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        // THE ACKNOWLEDGEMENT IS IMMEDIATE. Before, the action was held until the paths connected,
        // for the sake of synchronous stopwatches -- but when the paths did not meet, the system did
        // not activate audio for TWENTY SECONDS (measured: didActivate at 41 s with path checks from
        // 19 s). The system stopwatch starts a couple of seconds early -- an honest price.
        action.fulfill()
        if let su = secondUUID, action.callUUID == su { answerSecond(); return }
        acceptCall()
    }
    /// THE SYSTEM'S TIMEOUT REACHES US (23.09, the critic): the method was named «timeoutPerformAction», a
    /// name the protocol does not have (the compiler: «nearly matches timedOutPerforming»), so the system
    /// never called it and a timed-out action went unwitnessed. The action already timed out: it is named
    /// in the diary, not reported as done.
    func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
        if let a = pendingAnswerAction, a === action { pendingAnswerAction = nil }
        let u = (action as? CXCallAction)?.callUUID
        // WHAT TIMED OUT, AND WHOSE (the critic 24.09): after every end on T1 and T3 the system's «set muted» waited five
        // seconds and timed out, never delivered here. Whether it belonged to the call that had just ended, and whether it
        // muted or unmuted, is written, so the next end says who asked for it.
        let muted = (action as? CXSetMutedCallAction).map { $0.isMuted ? "1" : "0" } ?? "-"
        MontanaP2PTrace.mark("callkit_timeout", "action=\(type(of: action)) uuid=\(u.map { String($0.uuidString.prefix(8)) } ?? "-") ours=\(u.map { reportedCalls.contains($0) ? 1 : 0 } ?? 0) last=\(u != nil && u == lastEndedUUID ? 1 : 0) muted=\(muted) state=\(state) connected=\(connectedAt == nil ? 0 : 1)")
        // 23.09 15:17:35, both phones five seconds after an ended call: the system still had an action
        // pending for a call -- its own list is read now, not left to guesswork.
        if state == "idle" { scheduleSweep("timeout") }
    }
    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        if let su = secondUUID, action.callUUID == su {
            E2E.shared.callDebug("‼️ CXEndCallAction second line — declined")
            declineSecond(); action.fulfill(); return
        }
        E2E.shared.callDebug("‼️ CXEndCallAction st=\(state) — CallKit/user ended")
        // THE SYSTEM'S END IS A DIARY LINE (21.09, the critic): seven incoming calls on a tester's
        // phone were torn down two seconds after the ring by this door, and the diary held no word
        // of it -- only the E2E log, which no verdict reads. The state at the moment names the hand:
        // «incoming» is a decline on the screen, «connected» a hang-up, anything else the system.
        // «ours=1»: the transaction is our own end (a hand or a rule of ours already named itself);
        // «ours=0»: the system's own End -- the lock screen, the green oval, a headset button.
        MontanaP2PTrace.mark("call_end_sys", "state=\(state) connected=\(connectedAt == nil ? 0 : 1) ours=\(endSignalSent ? 1 : 0) peer=\(String((peer ?? "").prefix(10)))")
        if state == "incoming" { declinedByMe = true }   // user saw the ringing call and declined — not "missed"
        // The system's own End reaches the teardown past our End button; it names the hand all the
        // same (measured 12.09: ten talks of the week ended with «end=-», every one of them by this door).
        if endReason == "-" { endReason = handReason(); endDoor = "system-end" }
        sendEndSignal()   // no-op if already sent (programmatic end) or a remote end
        endReportedUUID = action.callUUID   // the End action itself ends the call for the system -- the teardown reports nothing more
        cleanup(); action.fulfill()
    }
    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        reportedCalls.insert(action.callUUID)   // the system's list now holds a call of ours (sweepSystemCalls)
        action.fulfill()
        // The call exists for the system only from this minute -- here is where the name is set.
        if let p = peer { stampNativeName(peer: p, uuid: action.callUUID, video: isVideo) }
        provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: nil)   // → didActivate → ringback
    }
    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        MontanaP2PTrace.mark("callkit_mute", "muted=\(action.isMuted ? 1 : 0) live=\(action.callUUID == callUUID ? 1 : 0) last=\(action.callUUID == lastEndedUUID ? 1 : 0) state=\(state)")
        toggleMute(action.isMuted)
        DispatchQueue.main.async { CallUIModel.shared.muted = action.isMuted }   // one truth for both screens
        action.fulfill()
    }
    func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        if action.isOnHold {
            if action.callUUID == callUUID {
                // Hold & Accept (second line ringing) keeps the park lane;
                // a lone hold keeps the machine and only mutes the tracks.
                if parked != nil { swapWithParked() }
                else if secondUUID != nil { parkCurrent() }
                else { softHold(true) }
            }
        } else {
            if action.callUUID == callUUID { softHold(false) }
            else if let pk = parked, action.callUUID == pk.uuid {
                if callUUID == nil { parked = nil; unpark(pk) } else { swapWithParked() }
            }
        }
        action.fulfill()
    }
    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        // HERE LIVED THE DEATH OF THE CALL. Picking up on the other side turns audio on for us, and
        // the whole turning-on ran on the main thread: raising the audio node and REBUILDING THE
        // CATEGORY for the speaker. Measured: the main thread stalled for eight and nine tenths of a
        // second from exactly this instant, the call paths had no time to refresh, and the link broke
        // on the eleventh second. And the category rebuild over a running camera took the camera away
        // -- the caller's own video went dark at the very instant the second phone picked up.
        // Now: the light work here, the heavy work in its own queue, and instead of a category
        // rebuild only an output switch, which does not touch the camera.
        RTCAudioSession.sharedInstance().audioSessionDidActivate(audioSession)
        audioActive = true
        MontanaP2PTrace.mark("call_audio_session", "on")
        // NOTHING HEAVY ON THE MAIN THREAD AT THE SESSION'S RISE (the author's word 25.09: «remove them altogether»): the
        // diary of T1 measured the main thread held 391 and 317 ms right here at the start of two video calls — the
        // allowance of haptics during recording (an audio-server call, 24.09) and the dial tone restarted over the session
        // just risen stood between this line and the audio node. Both are gone: the audio node rises at once on its own
        // queue, and the owed tone returns with the peer's next «ringing».
        bringUp(.audioWanted)
        // A fuse: the camera may give no frame at all (access denied) -- audio does not wait for it
        // longer than two seconds.
        Self.audioQ.asyncAfter(deadline: .now() + 2) { [weak self] in self?.bringUp(.timeout) }
        ensureCaptureRunning()   // a video call accepted from the background: the camera starts only in an active app
    }
    static let audioQ = DispatchQueue(label: "montana.call.audio")

    // -- a group's room (MTGroupRoom, 07.10): its sound is touched here, in the call's file -- the phone's sound keeps its two
    // owners, the call and MontanaAudioSession (the layout ring, rule 18); a room is a call of the system like this one.
    static func roomSoundConfigure() {
        let s = RTCAudioSession.sharedInstance()
        s.lockForConfiguration()
        let cfg = RTCAudioSessionConfiguration.webRTC()
        cfg.category = AVAudioSession.Category.playAndRecord.rawValue
        cfg.mode = AVAudioSession.Mode.voiceChat.rawValue
        cfg.categoryOptions = [.allowBluetooth, .allowBluetoothA2DP]
        do { try s.setConfiguration(cfg) } catch { MontanaP2PTrace.mark("room_sound", "config \(error)") }
        s.unlockForConfiguration()
    }
    /// The room's loudspeaker: a headset, a car or a speaker that holds the sound is never taken over.
    static func roomSpeaker(_ on: Bool) {
        audioQ.async {
            guard !(on && MontanaAudioRoute.isExternal) else { return }
            let s = RTCAudioSession.sharedInstance()
            s.lockForConfiguration()
            do { try s.overrideOutputAudioPort(on ? .speaker : .none) } catch { MontanaP2PTrace.mark("room_sound", "route \(error)") }
            s.unlockForConfiguration()
        }
    }
    /// The system refused the room its call: the sound is raised by hand so the room still speaks.
    static func roomSoundByHand() {
        roomSoundConfigure()
        let s = RTCAudioSession.sharedInstance()
        s.lockForConfiguration()
        do { try s.setActive(true) } catch { MontanaP2PTrace.mark("room_sound", "active \(error)") }
        s.unlockForConfiguration()
        s.isAudioEnabled = true
    }

    // -- THE ONE CALL BRING-UP ORDER (SSOT) --
    // The order is single and lives in one place: (1) screen and view; (2) THE CAMERA first: it is
    // the only one the system knows how to take away, and it takes longest to rise;
    // (3) signaling and paths in parallel, they touch neither camera nor audio;
    // (4) AUDIO last, AFTER the camera's first frame: audio rises in milliseconds and has nothing
    // to wait for, while its early touches to the audio subsystem twice turned out to be the
    // camera's killers; (5) measurement -- from the writing of the "connected" state.
    // Every entrance meets one queue -- no races by construction.
    private enum BringUp: String { case audioWanted, camReady, timeout }
    private func bringUp(_ ev: BringUp) {
        Self.audioQ.async { [weak self] in
            guard let self else { return }
            switch ev {
            case .audioWanted: self.audioUnitPending = true
            case .camReady, .timeout: self.videoReady = true
            }
            guard self.audioUnitPending, (!self.isVideo || self.videoReady) else { return }
            self.audioUnitPending = false
            let t0 = Date()
            RTCAudioSession.sharedInstance().isAudioEnabled = true
            if self.speakerOn, !MontanaAudioRoute.isExternal {
                let s = RTCAudioSession.sharedInstance()
                s.lockForConfiguration()
                do { try s.overrideOutputAudioPort(.speaker) }
                catch { E2ELog.write("call: speaker route err \(error)") }
                s.unlockForConfiguration()
            }
            MontanaP2PTrace.mark("audio_on", "ms=\(Int(Date().timeIntervalSince(t0)*1000)) after=\(ev.rawValue)")
            DispatchQueue.main.async { self.autoSpeakerOnVideo() }   // the audio node rose: the video call's loudspeaker is decided now
        }
    }
    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        RTCAudioSession.sharedInstance().audioSessionDidDeactivate(audioSession)
        RTCAudioSession.sharedInstance().isAudioEnabled = false
        audioActive = false
        MontanaP2PTrace.mark("call_audio_session", "off")
        // THE MICROPHONE ROAD CLOSES WITH THE CALL (28.09, the author: «after a call the minutes keep running in the
        // car»). The system takes its session back and the CATEGORY stays as the call left it -- playAndRecord in the
        // voice-chat mode, the hands-free road open: a car goes on showing a call, and the next voice plays into the
        // earpiece of a conversation gone by. The ledger of holders closes the road and lowers the session with the
        // word that lets every other app resume (MontanaAudioSession, the one door).
        MontanaAudioSession.callEnded()
    }
}

// -- THE SYSTEM'S LIST IS THE TRUTH ABOUT ITS CALLS (the author's word 23.09) --
// After a call the car kept counting the talk's seconds until the app was killed (16:21, T1). The diary
// said the call had ended and the machine rested -- and it could not see what the system still held: a
// call of ours or the call's audio, alive for as long as the process lived (the hands-free link shows a
// call while the voice session stands). The keeper of the system's calls is read, not trusted to follow:
// at the end of every call and on every change it reports, every call of ours that lives without a right
// (not the live call, not the second line, not the parked one, not a push ring still waiting) is named
// and ended; the call's audio the system did not take back is let go when nothing of ours needs it.
extension MontanaCall: CXCallObserverDelegate {
    func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        if call.hasEnded { reportedCalls.remove(call.uuid); return }
        if state == "idle", reportedCalls.contains(call.uuid), !aliveByRight(call.uuid) { scheduleSweep("changed") }
    }
    private func aliveByRight(_ u: UUID) -> Bool {
        u == callUUID || u == secondUUID || u == pushPostedUUID || u == parked?.uuid
    }
    /// One read at a time, two seconds after the reason: the system's list settles after our own end report.
    fileprivate func scheduleSweep(_ why: String) {
        guard !sweepPending else { return }
        sweepPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            self.sweepPending = false
            self.sweepSystemCalls(why)
        }
    }
    private func sweepSystemCalls(_ why: String) {
        guard state == "idle" else { return }   // a living call owns the system's list
        var live = 0, ours = 0, orphans = 0
        for c in callObserver.calls {
            if c.hasEnded { reportedCalls.remove(c.uuid); continue }
            live += 1
            guard reportedCalls.contains(c.uuid) else { continue }   // not ours: a phone call, another app's
            ours += 1
            if aliveByRight(c.uuid) { continue }
            orphans += 1
            MontanaP2PTrace.mark("callkit_orphan", "uuid=\(c.uuid.uuidString.prefix(8)) connected=\(c.hasConnected ? 1 : 0) held=\(c.isOnHold ? 1 : 0) out=\(c.isOutgoing ? 1 : 0) why=\(why)")
            provider.reportCall(with: c.uuid, endedAt: Date(), reason: .remoteEnded)
        }
        // The call's audio the system did not take back (its didDeactivate never came -- the session was
        // raised by our own hand when didActivate was late, or the system kept it): nothing of ours has a
        // right to it any more, so it is let go here.
        var released = false
        if audioActive, ours == orphans {
            let s = RTCAudioSession.sharedInstance()
            s.lockForConfiguration()
            do { try s.setActive(false) } catch { E2ELog.write("call: releasing the call's audio: \(error)") }
            s.unlockForConfiguration()
            s.isAudioEnabled = false
            audioActive = false
            released = true
        }
        if released { MontanaP2PTrace.mark("audio_left_active", "released why=\(why)") }
        MontanaAudioSession.callEnded()   // whatever the system did or did not take back, the road closes here (28.09)
        MontanaP2PTrace.mark("call_system", "after=\(why) live=\(live) ours=\(ours) orphans=\(orphans) audio_released=\(released ? 1 : 0)")
        MontanaLog.event("E2E-CALL system after=\(why) live=\(live) ours=\(ours) orphans=\(orphans) audio_released=\(released ? 1 : 0)")   // the system's list, in the file that survives a storm
    }
}

// ── RTCPeerConnectionDelegate ──
extension MontanaCall: RTCPeerConnectionDelegate {
    func peerConnection(_ pc: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        guard peer != nil else { return }
        iceGenCount += 1
        if iceGenCount == 1 { tlog("first local ICE candidate") }
        let c = CallICE(candidate: candidate.sdp, sdpMid: candidate.sdpMid, sdpMLineIndex: candidate.sdpMLineIndex)
        let kind = Self.candidateKind(candidate.sdp)
        // no.5 (analysis): candidates in a batch once per 200ms in one POST — instead of N sequential
        // requests (each a target for an LTE stall and a queue jump of 0.3-1.5s).
        DispatchQueue.main.async { [weak self] in
            guard let self, pc === self.pc else { return }   // a candidate of a connection no longer in hand is nobody's
            self.iceOutBatch.append(c)
            self.iceOutKinds[kind, default: 0] += 1
            guard self.iceBatchTimer == nil else { return }
            // The first bundle leaves immediately: it is the one carrying the reflected address on
            // which the direct path is built. The rest go in batches of 200 ms.
            let wait: Int = self.iceFlushes == 0 ? 0 : 200
            let tm = DispatchSource.makeTimerSource(queue: self.iceQ)
            tm.schedule(deadline: .now() + .milliseconds(wait))
            tm.setEventHandler { [weak self] in
                DispatchQueue.main.async { [weak self] in
                    self?.iceBatchTimer = nil
                    self?.flushIceBatch()
                }
            }
            self.iceBatchTimer = tm
            tm.resume()
        }
    }
    private func flushIceBatch() {
        guard let peer = peer, !iceOutBatch.isEmpty else { iceOutBatch = []; iceOutKinds = [:]; return }   // dead call — dump the tail
        if iceHeldForPeerWord {
            MontanaP2PTrace.markFolded("ice_hold", "held n=\(iceOutBatch.count) — until the peer's first word", window: 30, key: "ice_hold")
            return   // the batch stays; releaseHeldIce sends it whole
        }
        let n = iceOutBatch.count
        let kinds = Self.foldKinds(iceOutKinds); iceOutKinds = [:]
        var ice = CallSignalOut(ctrl: "call-ice", candidates: iceOutBatch)
        iceOutBatch = []
        ice.targetDevice = peerDevice   // nil until the answer (fan-out), addressed after
        iceFlushes += 1
        MontanaP2PTrace.mark("ice_tx", "n=\(n) batch=\(iceFlushes) ms=\(Int(Date().timeIntervalSince(startedAt ?? Date())*1000)) types=\(kinds)")
        sendSignal?(peer, ice)
    }
    /// The held candidates leave in one batch — by the peer's first word, or by time for a peer that never speaks.
    private func releaseHeldIce(_ why: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.iceHeldForPeerWord else { return }
            self.iceHeldForPeerWord = false
            MontanaP2PTrace.mark("ice_hold", "released by \(why) n=\(self.iceOutBatch.count)")
            self.iceBatchTimer?.cancel(); self.iceBatchTimer = nil
            self.flushIceBatch()
        }
    }
    func peerConnection(_ pc: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        // K-1: the machine's owner is the main thread — the whole reaction hops there.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.peerConnection(pc, didChange: newState) }
            return
        }
        // A CONNECTION NO LONGER IN HAND SAYS NOTHING TO THE LIVING CALL (24.09): a connection a rejoin replaced, or one
        // the second line parked, keeps this delegate; its late «failed» or «disconnected» would break the call that
        // stands on the new one.
        guard pc === self.pc else {
            MontanaP2PTrace.markFolded("call_ice", "\(iceName(newState)) of a connection no longer in hand — nothing", window: 10, key: "ice_foreign")
            return
        }
        tlog("ICE→\(iceName(newState))")
        lastIce = iceName(newState)
        // Call measurement, told without naming anyone: the state and the milliseconds from the start
        MontanaLog.event("E2E-CALL ice=\(iceName(newState)) ms=\(Int(Date().timeIntervalSince(startedAt ?? Date())*1000))")
        MontanaP2PTrace.mark("call_ice", "\(iceName(newState)) ms=\(Int(Date().timeIntervalSince(startedAt ?? Date())*1000)) video=\(isVideo ? 1 : 0)")

        switch newState {
        case .checking:
            MontanaWakeDoor.note("ice")
            armHardTimeout()   // checks started — a full 60s to connect from this moment
        case .connected, .completed:
            // A PATH THAT MEETS AFTER THE END BELONGS TO NOBODY (25.09): the zombie birth's connection met while the
            // machine had already rested, «connected» was written over an ended call, and the end button ended nothing.
            if ended {
                MontanaP2PTrace.mark("call_ice", "connected after the end -- closed")
                DispatchQueue.main.async { [weak self] in self?.pc?.close(); self?.pc = nil }
                return
            }
            connectHardTimer?.invalidate(); reconnectTimer?.invalidate(); reconnectTimer = nil
            restartTimer?.invalidate(); restartTimer = nil; iceRestarts = 0
            restartAskedAt = .distantPast
            disconnectGrace?.invalidate(); disconnectGrace = nil
            startRouteWatch()
            stopRingback()
            leaveReconnecting("ice connected")
            setState("connected")
            // The measurement starts AFTER the state is written, and only here: the former start went
            // to the main thread before "connected" was written, the measurement saw the old state,
            // exited -- and the loop was dead until the end of the call. A coin toss: in time, it
            DispatchQueue.main.async {
                guard !self.measuring else { return }   // a reconnect does not start a second loop
                self.measuring = true
                self.measureStreams()
            }
            raiseVideoCeiling()   // link proven — in 5s check the pair and raise sharpness
            pushCaptureUntilRunning()   // the camera may not have started in background — catch it up here

            tlog("⑦ CONNECTED (ICE) — media path open, ringback stops")
            reportSelectedPair(tag: "connected")
            // CallKit sometimes does NOT send didActivate to the receiver → the audio unit is dead: packets flow,
            // the microphone doesn't record, the speaker doesn't play (telemetry: tx≈RTCP-only). Safety net after 1.5s.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, self.state == "connected", !self.audioActive else { return }
                E2ELog.write("call: didActivate didn't arrive — self-activating audio")
                self.ensureAudioActive()
            }
            if let uuid = callUUID, isInitiator || rejoining {
                // A rejoined call's clock is the call's own: the system resumes it from its first connected moment.
                provider.reportOutgoingCall(with: uuid, connectedAt: rejoining ? connectedAt : nil)   // system call timer
            }
            if freshConnection {
                // The run that came back has a new audio route: a video call speaks aloud again, as at its first connect.
                autoSpeakerOnVideo()
                freshConnection = false; rejoining = false
                heldRejoins = 0; rejoinOffering = false   // a rejoin that stood is no fall: the next run goes back in
                holdOnDisk(force: true)
                protectVoice()   // a rebuilt connection's voice takes its share, as a first connection's does
                MontanaP2PTrace.mark("call_rejoin", "the new connection stands — the call goes on")
            }
            reassertSpeaker("connected")   // the loudspeaker chosen while ringing stays after the connect
            // The video call speaker belongs to the one bring-up order (bringUp): there are no
            // touches to audio here -- early touches killed the camera twice.
        case .failed:
            // The cellular NAT rebinds mid-call and the selected pair dies on ONE side (measured
            // 28.08: 22s of reconnecting, the peer kept sending into the void, nobody asked for
            // fresh checks). The side that SEES the break asks; the callee starts later — the
            // usual glare tie-break. Everything else lives behind the one door.
            disconnectGrace?.invalidate(); disconnectGrace = nil
            if connectedAt == nil { setupPathFailed(); break }
            enterReconnecting("ice failed")
        case .disconnected:
            // A suspicion, not a verdict (disconnectGraceS): the break is declared only if it holds.
            guard disconnectGrace == nil else { break }
            disconnectGrace = callTimer(Self.disconnectGraceS, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.disconnectGrace = nil
                guard self.pc?.iceConnectionState == .disconnected else {
                    MontanaP2PTrace.mark("call_ice", "disconnected healed within the grace — no break declared")
                    return
                }
                self.enterReconnecting("ice disconnected past the grace")
            }
        default: break
        }
    }
    // 12.7: route change without the timeout. The system names the interface-set change
    // (Wi-Fi<->cellular); the side whose route changed asks for fresh checks immediately —
    // one shot, 2s debounce against flaps; if the network does not reconverge, the ordinary
    // disconnected road (scheduleIceRestart) takes over. Glare with the peer's own restart
    // resolves by the existing deterministic tie-break on the signal road.
    private func startRouteWatch() {
        guard routeMonitor == nil else { return }
        let m = NWPathMonitor()
        m.pathUpdateHandler = { [weak self] path in
            // Only a SATISFIED path names a route. A transient "unsatisfied" blip (VPN
            // tunnel re-establishing at call start, audio-session churn) used to rewrite
            // the key, and the return of the SAME route then read as a change — marking
            // the dial dirty and firing a needless ICE restart right after the answer.
            guard path.status == .satisfied else { return }
            let key = (path.usesInterfaceType(.wifi) ? "w" : "")
                + (path.usesInterfaceType(.cellular) ? "c" : "")
            DispatchQueue.main.async {
                guard let self else { return }
                let old = self.routeKey
                self.routeKey = key
                guard !old.isEmpty, old != key else { return }
                if self.state == "connected" || self.state == "active" || self.state == "reconnecting" {
                    guard Date().timeIntervalSince(self.routeRestartAt) > 2 else { return }
                    self.routeRestartAt = Date()
                    MontanaP2PTrace.mark("call_route", "changed \(old)->\(key) — ice restart asked")
                    self.requestIceRestart(reason: "route \(old)->\(key)")
                } else if self.pc != nil {
                    // Still dialing/ringing: the gathered candidates just died with the old
                    // path. Remember it; the applied answer checks this flag and restarts.
                    self.routeDirty = true
                    MontanaP2PTrace.mark("call_route", "changed \(old)->\(key) during setup — marked dirty")
                }
            }
        }
        m.start(queue: .global(qos: .utility))
        routeMonitor = m
    }
    private func stopRouteWatch() {
        routeMonitor?.cancel(); routeMonitor = nil; routeKey = ""
    }
    private func scheduleIceRestart() {
        restartTimer?.invalidate()
        requestIceRestart(reason: "reconnecting")
        // The clock only KNOCKS; whether a fresh ask leaves is the one owner's decision below.
        restartTimer = callTimer(3, repeats: true) { [weak self] t in
            guard let self, self.state == "reconnecting", self.iceRestarts < Self.restartMax else { t.invalidate(); return }
            // A FRESH TRANSPORT AFTER ONE ASK THAT DID NOT FORM (29.09, T1 12:54 MSK): the person hung up on the ninth
            // second of a break and dialled again, and the new connection stood in five seconds -- what two more asks over
            // the dead transport would not do in twenty. Once the first ask has had its settle, the caller rebuilds in place
            // by the rejoin road; the callee keeps its asks and answers the rebuild as it answers a run that came back.
            if self.isInitiator, self.peerRebuilds, self.iceRestarts >= 1, !self.rebuiltInPlace,
               Date().timeIntervalSince(self.restartAskedAt) >= Self.restartSettleS {
                t.invalidate()
                self.rebuildInPlace("ask n=\(self.iceRestarts) did not form in \(Int(Self.restartSettleS))s")
                return
            }
            self.requestIceRestart(reason: "reconnecting")
        }
    }
    /// The one owner of «ask for fresh checks» (see restartAskedAt): the caller at once, the callee after
    /// the lead, never over an ask still forming unless the machine says it failed.
    private func requestIceRestart(reason: String) {
        let forming = Date().timeIntervalSince(restartAskedAt)
        if forming < Self.restartSettleS, pc?.iceConnectionState != .failed {
            MontanaP2PTrace.markFolded("call_ice", "restart held — one forming \(Int(forming))s (\(reason))", window: 3, key: "restart_held")
            return
        }
        restartAskedAt = Date()
        let lead = isInitiator ? 0.0 : Self.restartCalleeLeadS
        DispatchQueue.main.asyncAfter(deadline: .now() + lead) { [weak self] in
            guard let self, self.pc != nil, self.state != "idle" else { return }
            if self.state == "reconnecting" { self.iceRestarts += 1 }
            MontanaP2PTrace.mark("call_ice", "restart asked (\(reason))\(lead > 0 ? " after the caller's lead" : "")")
            self.sendIceRestartOffer()
        }
    }
    private func sendIceRestartOffer() { sumRestarts += 1; sendRenegotiationOffer(iceRestart: true) }
    private func sendRenegotiationOffer(iceRestart: Bool) {
        guard let peer, let pcx = pc else { return }
        // A media offer waits for a stable machine: offered into an open negotiation it is
        // refused and the camera stays dark; it tries again in a moment. An ICE restart goes
        // regardless — the reconnect road owns its own timing.
        if !iceRestart, pcx.signalingState != .stable {
            MontanaP2PTrace.mark("call_ice", "media offer deferred — signaling busy")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, self.pc != nil, self.state != "idle" else { return }
                self.sendRenegotiationOffer(iceRestart: false)
            }
            return
        }
        MontanaP2PTrace.mark("call_ice", iceRestart ? "restart offer n=\(iceRestarts)" : "renegotiation offer (video)")
        let mc = RTCMediaConstraints(mandatoryConstraints: iceRestart ? ["IceRestart": "true"] : nil,
                                     optionalConstraints: nil)
        pc?.offer(for: mc) { [weak self] desc, _ in
            guard let self, let desc else { return }
            let tuned = RTCSessionDescription(type: desc.type, sdp: self.tuneSDP(desc.sdp, premium: self.peerPremium))
            self.pc?.setLocalDescription(tuned) { err in
                guard err == nil else {
                    MontanaP2PTrace.mark("call_ice", "restart offer setLocal refused")
                    return
                }
                var o = CallSignalOut(ctrl: "call-restart",
                                      sdp: CallSDP(type: "offer", sdp: tuned.sdp), caps: self.myCaps())
                o.targetDevice = self.peerDevice
                o.reason = iceRestart ? "ice" : "media"   // consent fires on media only (K-6)
                self.sendSignal?(peer, o)
            }
        }
    }
    func peerConnection(_ pc: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams: [RTCMediaStream]) {
        // K-1: the machine's owner is the main thread — the whole reaction hops there.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.peerConnection(pc, didAdd: rtpReceiver, streams: streams) }
            return
        }
        guard pc === self.pc else { return }   // a track of a connection no longer in hand is nobody's
        if let v = rtpReceiver.track as? RTCVideoTrack {
            remoteVideoTrack = v
            // A TRACK IS NOT A PICTURE (15.7). A receiver is born by any offer that carries a video
            // line — an ICE restart of an old build, a return from background — and no frame ever
            // rides it (measured 05.09 16:21: a nine-minute audio call went dark on a frameless
            // track and was logged as video). The call grows video on the FIRST RENDERED FRAME
            // (remoteVideoArrived) or on the peer's own word — never on the birth of a receiver.
            if !CallUIModel.shared.remoteLive { frameSniffer = MTFirstFrameSniffer(track: v) }
            DispatchQueue.main.async { self.onStateChange?(self.state, self.peer); CallUIModel.shared.tick += 1 }
        }
        maybeEnableSframe()   // attach SFrame to the arrived receiver
    }
    /// The first remote frame rendered: now, and only now, the call grew video from the peer's
    /// side. Main thread — the sniffer hops there before calling.
    func remoteVideoArrived() {
        videoFramesSeen = true
        guard !isVideo else { return }
        isVideo = true
        applyScreenHold()
        let mineSleeps = localVideo == nil
        let armed = videoConsentFresh   // stale consent must not raise the camera (K-6)
        videoAcceptArmed = false
        autoSpeakerOnVideo()
        CallUIModel.shared.video = true
        if armed {
            enableMyVideo()   // the accepted consent: both cameras, sequential offers
        } else if mineSleeps, !CallUIModel.shared.peerSharing {
            CallUIModel.shared.videoAsk = true   // an old build upgraded without asking — the picture is the invitation
        }
        if let u = callUUID {
            let upd = CXCallUpdate(); upd.hasVideo = true
            provider.reportCall(with: u, updated: upd)
        }
        onStateChange?(state, peer); CallUIModel.shared.tick += 1
    }
    func peerConnectionShouldNegotiate(_ pc: RTCPeerConnection) {}
    func peerConnection(_ pc: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ pc: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnection(_ pc: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ pc: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    func peerConnection(_ pc: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    /// A RELAY THAT REFUSED, A REFLECTOR THAT NEVER ANSWERED (29.09): the engine's own word on a candidate it could not
    /// gather -- the scheme, the transport and the code, never the server's address. Without it a dead pass and a dead road
    /// wrote the same silence.
    func peerConnection(_ peerConnection: RTCPeerConnection, didFailToGatherIceCandidate event: RTCIceCandidateErrorEvent) {
        let url = event.url
        let scheme = String(url.prefix { $0 != ":" })
        let transport = url.contains("transport=tcp") ? "tcp" : (url.contains("transport=udp") ? "udp" : "-")
        let key = scheme + "/" + transport
        MontanaP2PTrace.markFolded("ice_gather_fail", "\(key) code=\(event.errorCode) text=\(String(event.errorText.prefix(60)))", window: 5, key: key)
        MontanaLog.event("E2E-CALL gather_fail \(key) code=\(event.errorCode)")
    }
    func peerConnection(_ pc: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}

// ── UI ──
// The first RENDERED remote frame flips the layout to pip — a track object alone is born at
// answer-apply while the peer may still be ringing, and keying the layout on it collapsed the
// caller's fullscreen preview into the corner under a black frameless screen (precedent 08:31:
// the 1192 fast answer made the black dial the rule, not the race).
final class MTFirstFrameSniffer: NSObject, RTCVideoRenderer {
    private weak var track: RTCVideoTrack?
    private var fired = false
    init(track: RTCVideoTrack) { self.track = track; super.init(); track.add(self) }
    func setSize(_ size: CGSize) {}
    func renderFrame(_ frame: RTCVideoFrame?) {
        guard frame != nil, !fired else { return }
        fired = true
        let t = track
        DispatchQueue.main.async {
            CallUIModel.shared.remoteLive = true
            MontanaP2PTrace.mark("video_live", "first remote frame rendered")
            MontanaCall.shared.remoteVideoArrived()
            t?.remove(self)
        }
    }
}

/// THE NAME OF A VIDEO CALL, IN THE CENTRE OF THE TOP ROW (the author's word 23.09, said three times: «the name's
/// font to the buttons' size»; «a longer name runs several times»; «the name in the centre and the timer under it,
/// a little apart, centred too»). The name is as large as the marks beside it allow — the largest system size whose
/// line fits their 44 points, read from the platform's own font metrics, not guessed — and stands in the centre
/// between the fold-away arrow and the camera flip; a name wider than its room runs (MTCallMarquee). The time
/// stands under the panel's row (MTCallTimeLine), the events under the time (MTCallStateLine). No words about the
/// kind of call: the picture says it.
private struct MTCallTopTitle: View {
    @ObservedObject var model: CallUIModel
    @State private var nameWidth: CGFloat = 0
    static let nameSize: CGFloat = {
        var s: CGFloat = 40
        while s > 12, UIFont.systemFont(ofSize: s, weight: .semibold).lineHeight > montanaTouchTarget { s -= 1 }
        return s
    }()
    var body: some View {
        let name = MontanaCall.shared.callerName(model.peer ?? "")
        let font = Font.system(size: Self.nameSize, weight: .semibold)
        GeometryReader { g in
            MTCallMarquee(text: name, font: font, textWidth: nameWidth)
                .frame(width: min(nameWidth, g.size.width), height: montanaTouchTarget)
                .frame(width: g.size.width, height: g.size.height)
        }
        .frame(height: montanaTouchTarget)
        // The name's own width at its own size, measured off the screen: the room decides whether it runs.
        .background(Text(verbatim: name).font(font).lineLimit(1).fixedSize().hidden()   // USER-DATA: the peer's name, measured
            .modifier(MTCallEdge { f in if abs(nameWidth - f.width) > 0.5 { nameWidth = f.width } }))
        .shadow(color: .black.opacity(0.5), radius: 3)   // legible over whatever the picture shows
    }
}

/// THE CALL'S TIME UNDER THE NAME (the author's word 23.09): the light and the time — or the stage before the call
/// connects — a little apart from the name and centred like it. Its line is always one 17-point line tall, with or
/// without words, so the panel under which the corner picture stands never changes height when the call connects.
private struct MTCallTimeLine: View {
    @ObservedObject var model: CallUIModel
    let statusText: String
    static let height: CGFloat = ceil(UIFont.systemFont(ofSize: 17, weight: .medium).lineHeight)
    var body: some View {
        HStack(spacing: 5) {
            MTCallLight()
            if model.state == "connected", let since = model.startedAt {
                Text(timerInterval: since...Date.distantFuture, countsDown: false)
            } else if !statusText.isEmpty {
                Text(LocalizedStringKey(statusText))
            }
        }
        .font(.system(size: 17, weight: .medium)).monospacedDigit().foregroundColor(.white.opacity(0.85))
        .lineLimit(1).fixedSize()
        .shadow(color: .black.opacity(0.5), radius: 3)
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
    }
}

/// A RUNNING LINE, AND ONLY WHEN IT MUST (the author's word 23.09: «if the name is longer — a running line, several
/// times»). The platform has none — UILabel and Text truncate or shrink — so the smallest one is built here: the
/// text at its own width, clipped to its room; wider than the room it runs three times with a second copy
/// following it, and comes to rest with the name's beginning in place. Narrower, it simply stands still.
private struct MTCallMarquee: View {
    let text: String
    let font: Font
    let textWidth: CGFloat
    var runs: Int = 3
    @State private var offset: CGFloat = 0
    @State private var ran: String = ""
    private static let gap: CGFloat = 36
    private static let speed: CGFloat = 36   // points a second: read at a glance, never a blur
    var body: some View {
        GeometryReader { g in
            let overflow = textWidth > g.size.width + 0.5
            HStack(spacing: Self.gap) {
                line
                if overflow { line }
            }
            .offset(x: overflow ? offset : 0)
            .frame(width: g.size.width, height: g.size.height, alignment: overflow ? .leading : .center)
            .clipped()
            .onAppear { run(overflow) }
            .onChange(of: overflow) { _, o in run(o) }
            .onChange(of: text) { _, _ in ran = ""; run(overflow) }
        }
    }
    private var line: some View {
        Text(verbatim: text).font(font).foregroundColor(.white).lineLimit(1).fixedSize()   // USER-DATA: the peer's name
    }
    private func run(_ overflow: Bool) {
        guard overflow, ran != text else { return }
        ran = text
        var still = Transaction(); still.disablesAnimations = true
        withTransaction(still) { offset = 0 }
        let distance = textWidth + Self.gap
        withAnimation(.linear(duration: Double(distance / Self.speed)).delay(1).repeatCount(runs, autoreverses: false)) {
            offset = -distance
        }
    }
}

/// THE CALL'S EVENTS STAND UNDER THE PANEL (the author's word 23.09): «On hold» or «Connection lost — reconnecting»,
/// one line at most (a break outranks a hold), drawn from the call's own state, at the 17 points bold the author set
/// for the hold line. The strip is ALWAYS there on a video call, empty when nothing is so: the corner picture is
/// measured from its bottom, so an event that comes or goes moves nothing on the screen.
private struct MTCallStateLine: View {
    @ObservedObject var model: CallUIModel
    static let height: CGFloat = ceil(UIFont.systemFont(ofSize: 17, weight: .bold).lineHeight)
    var body: some View {
        Group {
            if model.state == "reconnecting" {
                Text(LocalizedStringKey("Connection lost — reconnecting"))
            } else if model.heldByPeer || model.held {
                Text(LocalizedStringKey("On hold"))
            } else {
                Color.clear
            }
        }
        .font(.system(size: 17, weight: .bold)).foregroundColor(.white)
        .lineLimit(1).minimumScaleFactor(0.7)
        .shadow(color: .black.opacity(0.5), radius: 3)
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
    }
}

/// THE LIGHT BEFORE THE CALL'S NAME (the author's word 11.09): a traffic light of the channel —
/// green clean, yellow held down, red squeezed or reconnecting — and while the battery holds the
/// picture down the same light wears the battery instead of the dot. No words about it anywhere.
struct MTCallLight: View {
    @ObservedObject var model = CallUIModel.shared
    var body: some View {
        let level = model.state == "reconnecting" ? 0 : model.signal
        let tint: Color = level >= 2 ? .green : (level == 1 ? .orange : .red)
        Image(systemName: model.powerSaving ? "battery.25percent" : "circle.fill")
            .font(.footnote).foregroundColor(tint)
    }
}

final class CallUIModel: ObservableObject {
    static let shared = CallUIModel()
    /// A call holds the screen awake for its whole life (the author's word 18.09) — one door, MontanaScreenAwake.
    @Published var state: String = "idle" {
        didSet {
            if state == "idle" { MontanaScreenAwake.release("call"); cameraDenied = false } else { MontanaScreenAwake.hold("call") }
            armChromeFold("state")
        }
    }
    @Published var peer: String? = nil
    @Published var muted: Bool = false
    @Published var video: Bool = false { didSet { armChromeFold("video") } }
    @Published var speaker: Bool = false
    @Published var audioExternal: Bool = false   // the sound stands in a headset, a speaker or a car (the route observer)
    @Published var route = MontanaAudioRoute.Face(caption: "Speaker", icon: "speaker.wave.3.fill", lit: false, menu: false)   // the audio button's face
    /// THE CALL SCREEN IS FOLDED AND UNFOLDED THROUGH ONE DOOR THAT NAMES ITSELF (23.09: the diary saw the call screen
    /// born anew at 18:48:15 and 18:48:34 and could not say why). Every change is one line with the door that made it.
    @Published private(set) var minimized: Bool = false
    func fold(_ v: Bool, why: String) {
        if minimized != v { MontanaP2PTrace.mark("call_fold", "\(v ? "folded" : "unfolded") by=\(why)") }
        minimized = v
        armChromeFold("fold")
    }
    /// A LIVE CALL FOLDED INTO THE APP (the critic 24.09: the same answer stood in three places -- the handsets, the bubble
    /// on the clock and the way back through it -- and two of them read it differently). One answer for every place that
    /// shows a folded call or takes the person back to it.
    var foldedLive: Bool { minimized && state != "idle" && state != "incoming" }
    @Published var peerRinging: Bool = false
    @Published var connecting: Bool = false   // outgoing: answer received, ICE in progress -> "Connecting…"
    @Published var signal: Int = 2            // the light before the call's name: 2 green, 1 yellow, 0 red
    @Published var powerSaving = false        // the light wears the battery: the power floor holds the picture down
    @Published var cameraOff = false { didSet { applyCovers("camera") } }   // my camera muted inside a video call (the Video button face)
    @Published var masked = false             // the avatar mask stands in for my camera (one writer: MTAvatarMask.set)
    @Published var cameraDenied = false       // the camera is switched off for Montana — the alert with the road to Settings
    @Published var held = false { didSet { applyCovers("hold") } }             // I put the call on hold (the Hold button face)
    @Published var heldByPeer = false { didSet { applyCovers("peer-hold") } }  // the peer put me on hold (the bold banner)
    @Published var hasParked = false          // a second call waits parked — Hold becomes Swap
    @Published var screenSharing = false { didSet { armChromeFold("share") } }   // the broadcast rides the video lane
    @Published var peerSharing = false { didSet { applySides("share"); applyCovers("share"); armChromeFold("peer-share") } }   // the peer's screen arrives — our UI steps aside
    @Published var videoAsk = false { didSet { armChromeFold("ask") } }              // the peer's camera arrived while ours sleeps — offer to join
    @Published var videoAskIncoming = false { didSet { armChromeFold("ask-in") } }   // the peer asks to go video — accept or decline
    @Published var videoAskPending = false    // we asked and wait for the word back
    @Published var peerImage: UIImage? = nil  // full-size peer photo for the call screens
    /// The peer's picture stood still after it once flowed (23.09): one writer, MontanaCall.notePeerPicture.
    @Published var peerPaused = false { didSet { applyCovers("frames") } }
    /// My own camera was taken by the system (another app, the background): one writer, MontanaCall.noteSelfPicture.
    @Published var selfPaused = false { didSet { applyCovers("own-camera") } }
    /// THE COVERS HAVE ONE OWNER (the author's word 23.09: «on hold the same cover, and wherever else the
    /// picture pauses»). The peer's picture is covered with the peer's blurred face while either side holds
    /// the call -- a held track sends black frames, so the frame witness alone would show black -- or when
    /// its frames stood still; my own picture is covered with my own face while I hold, my camera is off or
    /// the system took it. Decided here, written in the diary, read by the slots themselves.
    @Published private(set) var remoteCovered = false
    @Published private(set) var selfCovered = false
    private func applyCovers(_ why: String) {
        let remote = held || heldByPeer || (peerPaused && !peerSharing)
        let own = held || cameraOff || selfPaused
        guard remote != remoteCovered || own != selfCovered else { return }
        remoteCovered = remote; selfCovered = own
        MontanaP2PTrace.mark("call_cover", "remote=\(remote ? 1 : 0) self=\(own ? 1 : 0) why=\(why)")
    }
    @Published var remoteLive = false { didSet { applySides("remote") } }   // the peer's video has RENDERED a frame — only then the layout goes pip
    @Published var mirrorLocal = true         // the self-view mirror follows the CAMERA'S FIRST FRAME, not the switch intent
    @Published var pipSwapped = false { didSet { applySides("tap") } }   // the miniature was tapped: my picture fullscreen, the peer in the corner
    /// THE BUTTON GRID'S OWN RECT in window coordinates, written by the grid as it is laid out (.zero
    /// while the buttons are folded away). It decides who gets a TOUCH where the corner picture and the
    /// buttons overlap — never where the picture STANDS (the author's word 22.09, said twice: the
    /// picture's bottom corners go down to the safe bottom and stand behind the buttons).
    @Published var bottomRowRect: CGRect = .zero
    /// WHERE THE BUTTONS STAND, REMEMBERED (the author's word 23.09: «the buttons must never cover the corner
    /// picture — it is unstable: now they cover it, now not, now it stands above them»). The top of the grid
    /// as last measured, and never forgotten while the grid is folded away: the corner picture's bottom
    /// edge stands on it, so the picture neither slides under the buttons nor jumps when they come and go.
    @Published var buttonsTop: CGFloat = 0
    /// THE TOP ROW'S EDGE, MEASURED (the author's word 22.09: the corner picture lies ten points under the top
    /// marks, touching neither, on any device and any system): the row's bottom in window coordinates,
    /// written by the row itself as it is laid out.
    @Published var topRowBottom: CGFloat = 0
    /// THE BUTTONS STEP ASIDE BY TAP OR BY TIME, ONE OWNER (the author's word 21.09 and 29.09): on a video call the
    /// picture is the switch -- a tap hides the buttons, the next tap brings them back -- and while the pictures
    /// flow (the call connected, no screen riding, no question standing) the buttons fold by themselves six
    /// seconds after they were last shown. The clock lives HERE, not in a view: a view's own state dies with every
    /// new showing of the call screen (the corner picture's lesson, 23.09), and a folded or re-shown screen counts
    /// its six seconds from the moment the person sees the buttons again. One work item on the main queue -- no
    /// run-loop timer (the layout guard, section 17), nothing the system's version or the device could vary.
    @Published var chromeHidden = false { didSet { armChromeFold("chrome") } }
    static let chromeFoldS: TimeInterval = 6
    private var chromeFold: DispatchWorkItem?
    /// Every model beat that can change whether the buttons stand on the screen asks here: a clock already running
    /// is kept (a camera beat must not stretch the six seconds), a clock that lost its ground is dropped and named.
    private func armChromeFold(_ why: String) {
        let stream = (video || MontanaCall.shared.isVideo) && state == "connected" && !screenSharing && !peerSharing
        let want = chromeVisible && stream && !minimized && !videoAsk && !videoAskIncoming
        guard want else {
            if let w = chromeFold { w.cancel(); chromeFold = nil; MontanaP2PTrace.mark("call_chrome", "fold dropped why=\(why)") }
            return
        }
        guard chromeFold == nil else { return }
        let w = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.chromeFold = nil
            // The screen is not looked at while the app is away: the clock is dropped, and the app's return (the
            // scene's phase unfolds the call, ContentView) starts a new one -- no clock turns in the background.
            guard UIApplication.shared.applicationState == .active else { MontanaP2PTrace.mark("call_chrome", "fold waits for the app"); return }
            guard self.chromeVisible else { return }
            self.chromeHidden = true
            MontanaP2PTrace.mark("call_chrome", "hidden by time after=\(Int(Self.chromeFoldS))s")
        }
        chromeFold = w
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.chromeFoldS, execute: w)
        MontanaP2PTrace.mark("call_chrome", "fold armed in=\(Int(Self.chromeFoldS))s why=\(why)")
    }
    @Published var tick: Int = 0 { didSet { applySides("track") } }
    /// THE SIDES OF THE CALL SCREEN HAVE ONE OWNER (23.09): which picture fills the screen and which rides
    /// the corner is decided here -- from the peer's picture, the tap and the peer's share -- and written in
    /// the diary with its reason. The slots read it themselves (MTCallSurface, MTCallMini). A parent's
    /// snapshot used to carry it, and a parent that stopped redrawing kept the old answer: taps on the corner
    /// without a swap (T1 13:28:59-13:29:12, twenty taps, no surface moved; the iPhone 15 13:25:14-28,
    /// nineteen), a tap on a corner picture that should not have existed (13:38:23, the peer sharing).
    @Published private(set) var bigIsLocal = true
    @Published private(set) var miniShown = false
    private func applySides(_ why: String) {
        let pip = MontanaCall.shared.remoteVideoTrack != nil && remoteLive
        let shown = pip && !peerSharing
        let bigLocal = !pip || (pipSwapped && shown)
        if shown != miniShown { miniShown = shown }
        if bigLocal != bigIsLocal {
            bigIsLocal = bigLocal
            MontanaP2PTrace.mark("call_sides", "big=\(bigLocal ? "local" : "remote") mini=\(shown ? (bigLocal ? "remote" : "local") : "none") why=\(why)")
        }
    }
    /// THE CORNER PICTURE'S PLACE LIVES AS LONG AS THE CALL (23.09): it was the view's own state and died
    /// with every new showing of the call screen -- «born corner=1» dozens of times a day on both phones.
    @Published var miniCorner: Int = 1        // 0 TL, 1 TR, 2 BL, 3 BR
    /// The buttons are up: a voice call always, a video call until the picture is tapped (21.09). One owner
    /// for the full screen and the corner picture.
    var chromeVisible: Bool { !((video || MontanaCall.shared.isVideo) && chromeHidden) }
    /// When the call connected. The duration is derived from it rather than accumulated: a timer that
    /// adds one every second counts its own ticks, not time — it falls behind whenever the run loop is
    /// busy and stops entirely while the app is away, so a call shown as four minutes could have run
    /// six. The label is driven by the system from this instant instead.
    @Published var startedAt: Date?
    func startTimer() { startedAt = Date() }
    func stopTimer() { startedAt = nil }
}

// The call screen lives in its OWN window above EVERYTHING (sheets, navigation, chat keyboard) —
// one presentation path from any app state (SSOT). The in-app overlay renders only the minimized
// pill; fullscreen is always this window. Showing the window also drops the chat keyboard.
// ONE WINDOW FOR THE WHOLE CALL (23.09): born once when the call first shows, hidden while it is
// minimized, shown when it comes back, taken down when the call ends. It used to be rebuilt on every
// return -- a new root for the call screen mid-call, a share's end included -- and the returns were
// exactly where the corner picture stopped answering and the back camera stayed mirrored.
final class CallWindowPresenter {
    static let shared = CallWindowPresenter()
    private var window: UIWindow?
    func update() {
        DispatchQueue.main.async {
            let m = CallUIModel.shared
            let alive = m.state != "idle"
            var show = alive && !m.minimized
            if m.state == "incoming", UIApplication.shared.applicationState != .active {
                show = false   // locked/background ring: the native CallKit screen rules
            }
            // AN AUDIO CALL ON A PHONE STANDS UPRIGHT while its screen is shown (MTCallUpright, the author's word 24.09).
            MTCallUpright.apply(show && !m.video && UIDevice.current.userInterfaceIdiom == .phone)
            if show, self.window == nil {
                let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else { return }
                let w = UIWindow(windowScene: scene)
                w.windowLevel = .alert + 1
                w.backgroundColor = .black
                let host = MontanaHost.make(CallOverlayView(model: CallUIModel.shared))
                host.view.backgroundColor = .black
                // THE CALL TAKES NO KEYBOARD'S ROOM (the author's word 23.09: «after the demo the buttons stood up to the
                // middle of the screen»). The call has no field of its own, yet its host took the platform's whole safe
                // area, the keyboard's region included, so a keyboard of ANOTHER window placed its buttons: T1 18:48:34,
                // the chat's keys up, the grid stood on their edge; 18:14:46 and 18:47:58, a region handed over while the
                // app went to the background and kept after the return until the phone was turned (60 and 207 points up).
                // The platform's own switch gives the tree the device's safe area and nothing else -- the same switch the
                // page and the drawer wear (ContentView). The incoming ring stands in this window and is closed with it.
                host.safeAreaRegions = [.container]
                w.rootViewController = host
                self.window = w
                MTCallFloat.shared.stand(on: host.view)   // the floating window rises from this screen when the person leaves the app
            }
            guard let w = self.window else { return }
            if show {
                w.isHidden = false
                w.makeKeyAndVisible()
                w.windowScene?.windows.forEach { $0.endEditing(true) }   // keyboard must not float over the call
            } else if !w.isHidden || !alive {
                w.isHidden = true
                if !alive { self.window = nil }
                w.windowScene?.windows.first(where: { !$0.isHidden && $0 !== w })?.makeKeyAndVisible()
            }
            MTCallFloat.shared.windowMoved()   // the floating window is born on the view that stands now
        }
    }
}

/// 15.8 — THE TWO HANDSETS BESIDE A NAME. A minimized call used to float as a pill over the top
/// of every screen — exactly over the chat header and the list's names (the author's word 05.09).
/// The system's green status indicator returns to the app from outside, but inside the app its
/// tap reaches nobody, so the return must stand where the person looks: green (return) to the
/// LEFT of the name, red (end) to the RIGHT. One model, one view, placed by the header and the row.
struct CallInlineHandset: View {
    enum Side { case green, red }
    let side: Side
    /// nil — any minimized call (the chat header); a peer — only the call with that person (the list row).
    let peer: String?
    @ObservedObject private var model = CallUIModel.shared
    @State private var asking = false
    private var shown: Bool {
        guard model.foldedLive else { return false }
        if let peer { return model.peer == peer }
        return true
    }
    var body: some View {
        if shown {
            // 44 POINTS, AND THE RED ASKS FIRST (the author's word 23.09): the red handset stood on its
            // own 26-point face beside a name and a list row, and at 13:21 a call ended under a finger
            // that reached for the name. The face keeps its size; the target around it is the
            // platform's 44 points; ending asks in the platform's own sheet.
            Button {
                if side == .green { model.fold(false, why: "handset") } else { asking = true }
            } label: {
                Image(systemName: side == .green ? "phone.fill" : "phone.down.fill")
                    .font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                    .frame(width: 26, height: 26)
                    .background(side == .green ? Color.green : Color.red).clipShape(Circle())
                    .frame(width: montanaTouchTarget, height: montanaTouchTarget).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .confirmationDialog("End the call?", isPresented: $asking, titleVisibility: .visible) {
                Button("End", role: .destructive) { MontanaCall.shared.endByHand(peer == nil ? "handset-chat" : "handset-row") }
            }
        }
    }
}

/// THE WAY BACK THROUGH THE CLOCK -- AND NOTHING DRAWN ON IT (the author's word 24.09 evening: «you drew a crooked thing
/// by hand on the clock -- do it as it should be»). A call is the platform's to show outside the app: the island while the
/// app is not in use, a notch phone's green bubble. Inside the app a folded call is shown by its own floating window. The
/// green capsule this file drew behind the clock on island phones is gone. What stays is the tap: with a call folded, a
/// tap on the status bar unfolds it -- the platform's scroll-to-top gesture reaches the page's own scroller, and every
/// place that hears it passes this one door, named in the diary.
enum MTCallClockBubble {
    @discardableResult
    static func returnToCall(by door: String) -> Bool {
        let m = CallUIModel.shared
        guard m.foldedLive else { return false }
        MontanaP2PTrace.mark("call_clock", "tap by=\(door)")
        m.fold(false, why: "clock")
        return true
    }
}

enum MontanaCallWiring {
    static var done = false
    static var bag = Set<AnyCancellable>()
    static func setup() {
        guard !done else { return }; done = true
        let c = MontanaCall.shared
        c.sendSignal = { peer, sig in E2E.shared.sendCallSignal(to: peer, sig) }
        c.ringReach = { peer, video, offer, seed in await E2E.shared.ringCall(to: peer, video: video, offerSdp: offer, callSeed: seed) }
        c.displayNameFor = { ref in MontanaAvatar.spokenName(E2E.shared.displayName(for: ref)) }   // the SSOT of display; the callsign emoji lives in the face, not in the name
        c.onPeerWord = { peer in E2E.shared.notePeerSeen(peer) }
        c.onCallerNamed = { peer, n, _ in   // the glyph is derived from the name ([C-1], 20.09)
            if let n, !n.isEmpty, n.count <= 64 { MontanaDeliveryEngine.shared.store?.setPeerName(ref: peer, name: n, at: 0, source: "call") }
        }
        MontanaCall.watchRoute()   // 15.28: the audio route is measured for the whole call
        MontanaLog.holdRotation = { ch in ch == .trace && MontanaCall.stateSnapshot != "idle" }   // 29.09: the call's trace outlives the call
        c.rejoinHeldCall()   // 24.09: the call its previous process held goes on
        c.onCallLog = { peer, video, incoming, dur, missed, declined, seed, rang, refused in
            E2E.shared.logCall(peer: peer, video: video, incoming: incoming, durationSec: dur, missed: missed)
            if !missed { E2E.shared.notePeerSeen(peer) }   // 15.7: a call that connected is the freshest proof
            // Banner is OURS (iOS posts none for third-party CallKit misses);
            // the system Phone app gets the red Recents entry via the CallKit .unanswered report.
            if incoming && missed && !declined { postMissedCallBanner(peer: peer, video: video, seed: seed) }
            // A missed call of MINE, outgoing: the peer may not have learned of it at all (the voip
            // push expired at Apple, the signals died by timeout). The mark travels as an ORDINARY
            // guaranteed letter -- a call row in their chat and a plain banner, NOT a call: a call is
            // a value of the present moment (the author's word 22.08). Row dedup comes from the seed
            // graveyard: whoever saw the call alive gets no duplicate row from the letter.
            // LOUD ONLY FOR A PHONE THAT NEVER RANG (13.09, the author's three notifications for one
            // call): a phone that said «ringing» has already shown its person the call and written its
            // own missed row — a second loud push for the same fact is one notification too many, and
            // the far extension cannot take it back (its silence shows the node's «New message»
            // instead). The letter still rides, guaranteed and silent: the row and the sender's queue
            // are unchanged, only the second banner is gone.
            if !incoming && missed {
                let json = "{\"v\":\(video),\"s\":\"\(seed ?? "")\"}"
                // A BIRTH THE SYSTEM REFUSED (callkit-reset, callkit-refused) rides silent too (25.09): the far phone
                // was knocked once, if at all, for a call this machine never held -- a loud «missed call» for it is
                // one notification too many; the row still lands.
                MontanaP2PTrace.mark("missed_tx", "rang=\(rang ? 1 : 0) refused=\(refused ? 1 : 0) loud=\((rang || refused) ? 0 : 1)")
                MontanaDeliveryEngine.shared.enqueue(to: peer, chat: peer,
                                                     mid: ChatStore.mintMid().mid,
                                                     text: missedCallMark + json, silent: rang || refused)
            }
        }
        c.onStateChange = { state, peer in
            DispatchQueue.main.async {
                let m = CallUIModel.shared
                let was = m.state
                m.state = state; m.peer = peer; m.video = MontanaCall.shared.isVideo; m.tick += 1
                if state == "connected" && was != "connected" { m.startTimer() }
                if state == "idle" { m.stopTimer(); m.fold(false, why: "idle"); m.muted = false; m.speaker = false; m.miniCorner = 1
                    m.peerRinging = false; m.connecting = false; m.peerImage = nil }
                else if let p = peer { loadPeerImage(p) }
                if state == "connected" { m.connecting = false }
                CallWindowPresenter.shared.update()
            }
        }
        CallUIModel.shared.$minimized
            .receive(on: DispatchQueue.main)
            .sink { _ in CallWindowPresenter.shared.update() }
            .store(in: &bag)
        // A call turning to video frees the turn; back to sound on a phone it stands upright again (MTCallUpright, 24.09).
        CallUIModel.shared.$video
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { _ in CallWindowPresenter.shared.update() }
            .store(in: &bag)
    }

    // Full-size peer photo for the call screens: prefer the avatar file (the 128px keychain
    // copy is a thumbnail), decode off-main, prepared for display.
    static func loadPeerImage(_ peer: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            var ui: UIImage? = nil
            if let url = E2E.shared.peerAvatarFileURL(peer) { ui = UIImage(contentsOfFile: url.path) }
            // The same face as in chats and in the banner: on a file miss -- the bundle mirrors
            // (av_ by key, then the thumbnail from shareChats) -- a conversation may be keyed by ref.
            if ui == nil {
                let key = "av_" + MontanaQueueKeys.sha256(Data(peer.utf8)).map { String(format: "%02x", $0) }.joined()
                if let d = MontanaKeychain.get(key), let img = UIImage(data: d) { ui = img }
            }
            if ui == nil, let e = MontanaFace.mirrorEntry(peer) {
                if let td = e.thumb, let img = UIImage(data: td) { ui = img }
                else if let g = MTNameBook.faceGlyph(peer) ?? e.initial, !g.isEmpty {
                    ui = MontanaFace.circleImage(glyph: g, colorHex: e.colorHex, side: 240)
                }
            }
            // No mirror yet (the first call on a sleeping node) -- the face comes from the envelope glyph.
            if ui == nil, let g = MTNameBook.faceGlyph(peer) {
                ui = MontanaFace.circleImage(glyph: g, colorHex: MontanaAvatar.colorHex(peer), side: 240)
            }
            if ui == nil {
                let key = "av_" + MontanaQueueKeys.sha256(Data(peer.utf8)).map { String(format: "%02x", $0) }.joined()
                if let d = MontanaKeychain.get(key), !d.isEmpty { ui = UIImage(data: d) }
            }
            let prepared = ui?.preparingForDisplay() ?? ui
            DispatchQueue.main.async { CallUIModel.shared.peerImage = prepared }
        }
    }

    // Missed-call banner: ONE birth per call ([C-1], the author's word 09.09). The look is
    // MontanaNotify's — the same content the extension serves; the seed notebook says whether a
    // banner for this call already stands (the extension or the letter road may have rung first).
    static func postMissedCallBanner(peer: String, video: Bool, seed: String?) {
        // Whatever a push left on the screen for THIS call goes now: the ring letter's banner, the
        // bell's, and the node's bare «New message» behind either of them. One call — one face.
        if let seed { MontanaCall.dropBell(seed) }
        if let seed, MontanaMissedCall.state(seed) == "rang" {
            MontanaLog.event("MISSED banner skipped \(peer.prefix(10)) seed=\(seed.prefix(8)) — already rang")
            return
        }
        if let seed { MontanaMissedCall.note(seed, "rang") }
        let name = MontanaCall.shared.callerName(peer)
        let final = MontanaMissedCall.content(peer: peer, name: name, video: video)
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "missed-\(peer)-\(Int(Date().timeIntervalSince1970))", content: final, trigger: nil))
        MontanaLog.event("MISSED banner posted \(peer.prefix(10)) seed=\(String((seed ?? "").prefix(8)))")
    }
}

/// One view for both sides of a call: which track it shows is the only difference, so there is
/// one implementation and not two that drift apart the first time either is fixed.
struct VideoView: UIViewRepresentable {
    enum Side { case local, remote }
    let side: Side
    // The surface observes the model ITSELF (birth-point sovereignty, the transfer-board
    // construction): every model beat re-runs updateUIView and the track re-check — the
    // attach no longer depends on the parent chain delivering a re-render (measured 09:35:
    // branch=video, camera lit, and not one attach for 36s of dialing).
    @ObservedObject private var model = CallUIModel.shared

    private var track: RTCVideoTrack? {
        side == .local ? MontanaCall.shared.localVideoTrack : MontanaCall.shared.remoteVideoTrack
    }

    final class Coordinator { weak var track: RTCVideoTrack? }
    func makeCoordinator() -> Coordinator { Coordinator() }

    /// A FACE FILLS, A SCREEN FITS (the author's word 21.09: the tablet's share came in cut): a
    /// camera picture fills the surface and loses its edges, as the system's own call does; a shared
    /// screen — any size, any shape, a tablet's landscape on a phone's portrait — is shown WHOLE,
    /// fitted inside the surface with bars, never cropped. The mode follows the track's meaning,
    /// re-read on every model beat.
    private var contentMode: UIView.ContentMode { side == .remote && model.peerSharing ? .scaleAspectFit : .scaleAspectFill }
    func makeUIView(context: Context) -> RTCMTLVideoView {
        let v = RTCMTLVideoView(); v.videoContentMode = contentMode
        // A PICTURE IS NOT A CONTROL (29.09): the platform hands a touch to the deepest view that takes it, and
        // this view took every finger laid on the call's picture. The switch over it is drawn (the tap layer in
        // CallOverlayView), and the drawn tree alone answers for the finger on every system when no platform
        // view under it claims the touch (the gif's lesson, P-131).
        v.isUserInteractionEnabled = false
        if let t = track { t.add(v); context.coordinator.track = t }
        MontanaP2PTrace.mark("call_surface", "born side=\(side == .local ? "local" : "remote") track=\(track == nil ? 0 : 1)")
        return v
    }
    func updateUIView(_ v: RTCMTLVideoView, context: Context) {
        if v.videoContentMode != contentMode {
            v.videoContentMode = contentMode
            MontanaP2PTrace.mark("call_surface", "mode=\(contentMode == .scaleAspectFit ? "fit" : "fill") side=\(side == .local ? "local" : "remote")")
        }
        let t = track
        if context.coordinator.track !== t {          // the track changed — reattach exactly once
            context.coordinator.track?.remove(v)
            t?.add(v); context.coordinator.track = t
            MontanaP2PTrace.mark("call_surface", "side=\(side == .local ? "local" : "remote") track=\(t == nil ? 0 : 1)")
        }
    }
    static func dismantleUIView(_ v: RTCMTLVideoView, coordinator: Coordinator) {
        coordinator.track?.remove(v); coordinator.track = nil   // detach the renderer — otherwise the Metal layer hangs
    }
}

// ═══ THE CALL ABOVE OTHER APPS ═══════════════════════════════════════════════════════════════════
// The author's word 23.09: «when the video call is folded away, picture in picture works if it is on; otherwise only
// the cover» and «show the peer's picture when I fold Montana away, so I see him and know he sees me». The platform's
// own window for a video call (AVPictureInPictureVideoCallViewController) rises by itself when the person leaves the
// app with a video call on — the system asks the person's own switch (Settings › General › Picture in Picture › Start
// Automatically). With the switch off nothing rises: the camera stops in the background and the peer sees my face over
// my stopped picture (their cover, one owner: CallUIModel.applyCovers). With the window standing the camera goes on
// where the platform allows it (a voip app linked on iOS 18 or later: isMultitaskingCameraAccessSupported), so the
// peer keeps seeing me while I see them.
//
// The window is drawn by the system from sample buffers: an app in the background may not draw with the GPU, so the
// Metal surface of the call screen cannot feed it. Frames go to it only while it may be asked for — from the moment
// the app leaves the screen until it is back — and it shows the person I talk to, as the system's own call does.
//
// THE FOLD BUTTON AND THE VOICE CALL (the author's word 29.09): the fold-away mark of the call screen asks the same window
// to rise (MTCallFloat.foldAway) -- the fold counts as the app's leaving -- and a voice call has the window as well, showing
// the peer's cover (MTCallGround) where a video call shows their picture.

/// The peer's picture as sample buffers, turned by the frame's own rotation.
final class MTFloatVideoView: UIView {
    let display = AVSampleBufferDisplayLayer()
    private var rotation: RTCVideoRotation = ._0
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        display.videoGravity = .resizeAspectFill
        layer.addSublayer(display)
    }
    required init?(coder: NSCoder) { nil }
    func turn(_ r: RTCVideoRotation) { if r != rotation { rotation = r; setNeedsLayout() } }
    override func layoutSubviews() {
        super.layoutSubviews()
        let quarter = rotation == ._90 || rotation == ._270
        let angle: CGFloat = rotation == ._90 ? .pi / 2 : rotation == ._180 ? .pi : rotation == ._270 ? -.pi / 2 : 0
        CATransaction.begin(); CATransaction.setDisableActions(true)
        display.bounds = CGRect(x: 0, y: 0, width: quarter ? bounds.height : bounds.width, height: quarter ? bounds.width : bounds.height)
        display.position = CGPoint(x: bounds.midX, y: bounds.midY)
        display.setAffineTransform(CGAffineTransform(rotationAngle: angle))
        CATransaction.commit()
    }
}

/// The peer's frames for the floating window. `feeding` is written by the main thread and read by the decoder's, under
/// one small lock; a frame the decoder handed as planes is copied into a bi-planar buffer of its own size (a hardware
/// frame is handed over as it is).
final class MTFloatFeed: NSObject, RTCVideoRenderer {
    weak var view: MTFloatVideoView?
    var onSize: ((CGSize) -> Void)?
    private let lock = NSLock()
    private var on = false
    private var pool: CVPixelBufferPool?
    private var poolW = 0, poolH = 0
    var feeding: Bool {
        get { lock.withLock { on } }
        set { lock.withLock { on = newValue } }
    }
    func setSize(_ size: CGSize) {}
    /// The peer's picture as it stands — upright or lying — told whenever it turns, fed or not: the window takes the
    /// shape of the way the peer holds the camera (the author's word 23.09).
    private var lastSize = CGSize.zero
    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame else { return }
        let r = frame.rotation
        let quarter = r == ._90 || r == ._270
        let size = CGSize(width: CGFloat(quarter ? frame.height : frame.width), height: CGFloat(quarter ? frame.width : frame.height))
        if size != lastSize {
            lastSize = size
            DispatchQueue.main.async { [weak self] in self?.onSize?(size) }
        }
        guard feeding, let pb = buffer(frame), let sb = Self.sample(pb) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let v = self.view else { return }
            let l = v.display
            if l.status == .failed || l.requiresFlushToResumeDecoding { l.flush() }
            l.enqueue(sb)
            v.turn(r)
        }
    }
    private func buffer(_ frame: RTCVideoFrame) -> CVPixelBuffer? {
        if let cv = frame.buffer as? RTCCVPixelBuffer { return cv.pixelBuffer }
        let p = frame.buffer.toI420()
        let w = Int(p.width), h = Int(p.height)
        guard w != 0, h != 0 else { return nil }
        if pool == nil || poolW != w || poolH != h {
            let attrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: h,
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()]
            var made: CVPixelBufferPool?
            CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attrs as CFDictionary, &made)
            pool = made; poolW = w; poolH = h
        }
        guard let pool else { return nil }
        var out: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &out) == kCVReturnSuccess, let pb = out else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        guard let y = CVPixelBufferGetBaseAddressOfPlane(pb, 0), let uv = CVPixelBufferGetBaseAddressOfPlane(pb, 1) else { return nil }
        let yRow = CVPixelBufferGetBytesPerRowOfPlane(pb, 0), uvRow = CVPixelBufferGetBytesPerRowOfPlane(pb, 1)
        let sy = Int(p.strideY), su = Int(p.strideU), sv = Int(p.strideV)
        for row in 0..<h { memcpy(y + row * yRow, p.dataY + row * sy, w) }
        let cw = Int(p.chromaWidth), ch = Int(p.chromaHeight)
        for row in 0..<ch {
            let dst = (uv + row * uvRow).assumingMemoryBound(to: UInt8.self)
            let u = p.dataU + row * su, v = p.dataV + row * sv
            for c in 0..<cw { dst[2 * c] = u[c]; dst[2 * c + 1] = v[c] }
        }
        return pb
    }
    static func sample(_ pb: CVPixelBuffer) -> CMSampleBuffer? {
        var fmt: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pb, formatDescriptionOut: &fmt) == noErr,
              let fmt else { return nil }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()), decodeTimeStamp: .invalid)
        var sb: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pb, formatDescription: fmt,
                                                       sampleTiming: &timing, sampleBufferOut: &sb) == noErr, let sb else { return nil }
        if let atts = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: true), CFArrayGetCount(atts) != 0 {
            let d = unsafeBitCast(CFArrayGetValueAtIndex(atts, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(d, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sb
    }
}

/// The one owner of the floating window of a video call: armed while a video call lives, it rises from the call screen
/// (or from the app's own window while the call is folded into the chats), shows the peer — their picture, or their
/// cover when it does not flow — and brings the call screen back when the person taps it.
final class MTCallFloat: NSObject, AVPictureInPictureControllerDelegate {
    static let shared = MTCallFloat()
    private var controller: AVPictureInPictureController?
    private let content = AVPictureInPictureVideoCallViewController()
    private let video = MTFloatVideoView()
    private let cover = UIImageView()
    private let feed = MTFloatFeed()
    private weak var callRoot: UIView?
    private weak var track: RTCVideoTrack?
    private var bag = Set<AnyCancellable>()
    private var wired = false
    /// THE WINDOW STANDS ON THE CONTROLLER THAT SAID SO, AND DIES WITH IT (30.09). A flag of ours outlived the controller
    /// it described: a call that ended with its window up dropped the controller before the system could say «gone», the
    /// flag stayed true, and every later call refused the fold as «standing» -- T1 22:07:54, the call after the one whose
    /// window stood at its end, whatever the phone at the other end. A weak hold on the very controller that started is
    /// no window once that controller is dropped or replaced -- by construction, whatever the system's order of words.
    private weak var standingOn: AVPictureInPictureController?
    private var standing: Bool { standingOn != nil && standingOn === controller }
    /// A start asked or begun and not yet standing (the fold button's road, 29.09): the controller is not disturbed by
    /// the call screen going away under it -- the view it rose from stays its source until the window stands or refuses.
    private var rising = false
    /// The fold button's ask, held until the system answers (stands or refuses), so the answer knows whose ask it is:
    /// the system's own automatic start on the app's leaving folds nothing.
    private var foldAsked: String?
    /// When the app itself last asked the window to go (appReturned): the platform may answer our own ending with a
    /// restore, and that restore must not unfold what the app's return decided.
    private var goneWithAppAt: CFTimeInterval = 0
    private var painted = false
    private var paintedFor: ObjectIdentifier?
    /// Whether the system holds the window possible — said in the diary whenever it changes (23.09: the window never
    /// rose on T1 and nothing said why).
    private var possibleWatch: NSKeyValueObservation?

    /// The call's own window was born: its root is what the floating window rises from while the call screen stands.
    /// Asked on the next turn of the loop — the window is shown in the same pass that births it.
    func stand(on root: UIView) {
        callRoot = root
        wire()
        DispatchQueue.main.async { self.refresh("window") }
    }
    /// The call's window was shown or hidden (CallWindowPresenter): the view that stands may have changed.
    func windowMoved() { if wired { refresh("window") } }

    private func wire() {
        guard !wired else { return }
        wired = true
        feed.view = video
        // A WINDOW HAS A SHAPE FROM ITS BIRTH (23.09, T1 20:09: armed, on the call screen, and nothing rose when the
        // person went home): its size stood at zero until the first fed frame, and frames were fed only after the app
        // had left. Upright until the peer's picture says otherwise, then the picture's own shape.
        content.preferredContentSize = CGSize(width: 1080, height: 1920)
        feed.onSize = { [weak self] size in
            guard let self, size.width != 0, size.height != 0, self.content.preferredContentSize != size else { return }
            self.content.preferredContentSize = size
            MontanaP2PTrace.mark("call_float", "shape \(Int(size.width))x\(Int(size.height))")
        }
        content.view.backgroundColor = .black
        for v in [video, cover] as [UIView] {
            v.frame = content.view.bounds
            v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            content.view.addSubview(v)
        }
        cover.contentMode = .scaleAspectFill
        cover.clipsToBounds = true
        let m = CallUIModel.shared
        Publishers.CombineLatest4(m.$state, m.$video, m.$minimized, m.$tick)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh("model") }
            .store(in: &bag)
        m.$remoteLive.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.refresh("picture") }.store(in: &bag)
        Publishers.CombineLatest3(m.$remoteCovered, m.$remoteLive, m.$peerImage)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.drawCover() }
            .store(in: &bag)
        NotificationCenter.default.addObserver(self, selector: #selector(leaving), name: UIApplication.willResignActiveNotification, object: nil)
    }

    /// Where the window rises from: the call screen while it stands, the app's own window while the call is folded into
    /// the chats — the person leaves the app from there as well.
    private func sourceView() -> UIView? {
        if !CallUIModel.shared.minimized {
            guard let r = callRoot, let w = r.window, !w.isHidden else { return nil }
            return r
        }
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }
        return windows.first { !$0.isHidden && $0.windowLevel == .normal && $0.rootViewController != nil }?.rootViewController?.view
    }

    /// ONE CONTROLLER PER VIEW THAT STANDS (23.09, T1 20:27 on 1914: possible=1, the shape set, and the system never
    /// tried to raise the window when the person went home, twice). It was born on the app's own window — covered by
    /// the call's — and its source was swapped onto the call screen afterwards. The reference implementation births its
    /// controller once, on the call screen that stands, only when a picture flows, and never swaps it; so does this: a
    /// controller is born on the view that stands while a picture flows (mine or the peer's), and a change of that view
    /// births a new one. A standing window is never disturbed by a change behind it.
    private func refresh(_ why: String) {
        let m = CallUIModel.shared
        let call = MontanaCall.shared
        // A CALL OF ANY KIND HAS THE WINDOW (the author's word 29.09: «the fold of an audio call too -- the same system
        // miniature hangs»): a video call shows the peer's picture in it, a voice call the peer's cover (the face and the
        // wash, MTCallGround, drawCover) -- the window is the call's, not the picture's. An incoming ring has none: the
        // system's own screen rules it (CallWindowPresenter).
        let want = m.state != "idle" && m.state != "incoming"
        let src = want && AVPictureInPictureController.isPictureInPictureSupported() ? sourceView() : nil
        if let c = controller, !want || (!standing && !rising && c.contentSource?.activeVideoCallSourceView !== src) {
            if c.isPictureInPictureActive { c.stopPictureInPicture() }
            possibleWatch = nil
            controller = nil
            rising = false; foldAsked = nil
            if !want { feed.feeding = false; video.display.flushAndRemoveImage() }
            MontanaP2PTrace.mark("call_float", "disarmed why=\(why)")
        }
        if controller == nil, let src {
            let c = AVPictureInPictureController(contentSource: .init(activeVideoCallSourceView: src, contentViewController: content))
            c.canStartPictureInPictureAutomaticallyFromInline = true
            c.delegate = self
            controller = c
            possibleWatch = c.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { c, _ in
                MontanaP2PTrace.mark("call_float", "possible=\(c.isPictureInPicturePossible ? 1 : 0)")
            }
            drawCover()
            MontanaP2PTrace.mark("call_float", "armed from=\(src === callRoot ? "call" : "app") kind=\(m.video || call.isVideo ? "video" : "voice") why=\(why)")
        }
        let t = want ? call.remoteVideoTrack : nil
        if t !== track {
            track?.remove(feed)
            t?.add(feed)
            track = t
        }
    }

    /// The cover is the call's own (MTCallGround, one owner of its drawing), painted while the app is on the screen —
    /// an app in the background may not draw it — and shown while the peer's picture does not flow.
    private func drawCover() {
        let m = CallUIModel.shared
        let key = m.peerImage.map { ObjectIdentifier($0) }
        if UIApplication.shared.applicationState != .background, !painted || key != paintedFor {
            cover.image = MainActor.assumeIsolated { () -> UIImage? in
                let r = ImageRenderer(content: MTCallGround().frame(width: 270, height: 480))
                r.scale = 2
                return r.uiImage
            }
            painted = true; paintedFor = key
        }
        cover.isHidden = m.remoteLive && !m.remoteCovered
    }

    /// THE FOLD BUTTON IS THE APP'S LEAVING (the author's word 29.09: «even our own fold button of a video call must
    /// count as the app folded away and raise the platform's own picture in picture»). The window is asked to rise from
    /// the call screen that stands; when the system takes the ask (willStart) the call screen folds away under it, as
    /// the platform's own call does. A voice call folds the same way, its window showing the peer's cover (the author's
    /// word 29.09). False when there is no window to ask -- an incoming ring, a system that holds the window impossible,
    /// a window already standing or rising -- and the fold takes its old road (the pill in the app).
    func foldAway(why: String) -> Bool {
        guard let c = controller, !standing, !rising else {
            MontanaP2PTrace.mark("call_float", "fold by=\(why) refused: \(controller == nil ? "no window" : standing ? "standing" : "rising")")
            return false
        }
        guard c.isPictureInPicturePossible else {
            MontanaP2PTrace.mark("call_float", "fold by=\(why) refused: possible=0")
            return false
        }
        rising = true
        foldAsked = why
        feed.feeding = true
        MontanaP2PTrace.mark("call_float", "fold by=\(why): asked to rise size=\(Int(content.preferredContentSize.width))x\(Int(content.preferredContentSize.height))")
        c.startPictureInPicture()
        return true
    }

    /// The frames go ahead of the window: it rises on the picture of this moment, not on black. A window that did not
    /// rise in three seconds (the person's switch is off, or the app only glanced away) ends the feed by its own term —
    /// the call's file listens to no activation of the app (P-118.10).
    @objc private func leaving() {
        guard let c = controller else { return }
        MontanaP2PTrace.mark("call_float", "leaving possible=\(c.isPictureInPicturePossible ? 1 : 0) size=\(Int(content.preferredContentSize.width))x\(Int(content.preferredContentSize.height))")
        feed.feeding = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, !self.standing else { return }
            self.feed.feeding = false
            self.video.display.flushAndRemoveImage()
        }
    }

    /// THE WINDOW GOES WHEN THE APP COMES BACK (the author's word 24.09: «I came back to the full screen and the small
    /// window still stood as with the app folded -- I saw her on two screens»). T1 22:58:32-23:00:28: the window rose
    /// when the app left, the app came back at 22:59:15 and again at 22:59:47, and the window stood over it until the
    /// person tapped it (23:00:40-23:01:24 the same, 19 s over the app). The platform does not end a call's window
    /// when its app returns; the app ends it, as the reference implementation does -- half a second after the return,
    /// asked twice more while it still stands. Told by the app's one road of activation (the scene's phase), so the
    /// call's own file still listens to no activation (P-118.10). Our own ending unfolds nothing: the fold stays as the
    /// return set it (a screen share keeps its fold).
    func appReturned() {
        guard standing else { return }
        for (n, after) in [0.5, 0.7, 1.0].enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + after) { [weak self] in
                guard let self, let c = self.controller, c.isPictureInPictureActive else { return }
                self.goneWithAppAt = CACurrentMediaTime()
                MontanaP2PTrace.mark("call_float", "the app is back: asked to go try=\(n + 1)")
                c.stopPictureInPicture()
            }
        }
    }

    // A controller already dropped may still speak; its words are not about the window that stands now.
    func pictureInPictureControllerWillStartPictureInPicture(_ c: AVPictureInPictureController) {
        guard c === controller else { return }
        feed.feeding = true
        rising = true
        MontanaP2PTrace.mark("call_float", foldAsked == nil ? "rising" : "rising by=\(foldAsked ?? "")")
        // The fold button's ask, taken by the system: the window is on its way from the call screen, and the call
        // screen folds away under it now -- as the app's own leaving folds it (the pill and the way back unchanged).
        if let why = foldAsked { CallUIModel.shared.fold(true, why: "float-" + why) }
    }
    func pictureInPictureControllerDidStartPictureInPicture(_ c: AVPictureInPictureController) {
        guard c === controller else { return }
        standingOn = c
        rising = false; foldAsked = nil
        MontanaP2PTrace.mark("call_float", "stands peer_live=\(CallUIModel.shared.remoteLive ? 1 : 0) covered=\(CallUIModel.shared.remoteCovered ? 1 : 0)")
    }
    func pictureInPictureController(_ c: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        guard c === controller else { return }
        let e = error as NSError
        rising = false
        MontanaP2PTrace.mark("call_float", "refused domain=\(e.domain) code=\(e.code)" + (foldAsked == nil ? "" : " fold by=" + (foldAsked ?? "")))
        // The fold button's ask the system refused: the fold takes its old road -- the call folded into the app.
        if let why = foldAsked { foldAsked = nil; CallUIModel.shared.fold(true, why: why) }
    }
    func pictureInPictureControllerDidStopPictureInPicture(_ c: AVPictureInPictureController) {
        guard c === controller else { return }
        standingOn = nil
        rising = false; foldAsked = nil
        feed.feeding = false
        video.display.flushAndRemoveImage()
        MontanaP2PTrace.mark("call_float", "gone")
    }
    func pictureInPictureController(_ c: AVPictureInPictureController,
                                    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler done: @escaping (Bool) -> Void) {
        if CACurrentMediaTime() - goneWithAppAt < 2 {
            MontanaP2PTrace.mark("call_float", "gone with the app -- the fold stays as the return set it")
        } else {
            CallUIModel.shared.fold(false, why: "float")
            MontanaP2PTrace.mark("call_float", "back to the call")
        }
        done(true)
    }
}

/// ONE SLOT OF THE VIDEO CALL (23.09): the full screen or the corner. The side it shows, the self-view
/// mirror, the black under a peer's fitted screen and the cover over a peer's picture that stood still are
/// read from the model HERE -- the slot watches the model itself. They rode a parent's snapshot, and a
/// parent that stopped redrawing kept them: the back camera stayed mirrored (the iPhone 15, 13:25:41 and
/// 13:26:07) because the flip's new flag never reached the snapshot.
struct MTCallSurface: View {
    enum Slot { case big, mini }
    let slot: Slot
    @ObservedObject private var model = CallUIModel.shared
    private var side: VideoView.Side {
        switch slot {
        case .big: return model.bigIsLocal ? .local : .remote
        case .mini: return model.bigIsLocal ? .remote : .local
        }
    }
    var body: some View {
        let s = side
        VideoView(side: s)
            .scaleEffect(x: s == .local && model.mirrorLocal ? -1 : 1, y: 1)
            .background(s == .remote && model.peerSharing ? Color.black : Color.clear)   // a fitted screen stands on black bars, not on the face
            .overlay {
                // THE COVER (the author's word 23.09): the peer's picture stood still -- the far app went to the
                // background, another app took the screen, the camera was turned off -- and the stale frame gives
                // way to the peer's blurred face, as a voice call shows it. Only a picture that really stopped,
                // or a held call (a held track sends black frames): CallUIModel.applyCovers decides. My own
                // picture wears my own face the same way while I hold, my camera is off or the system took it.
                if s == .remote, model.remoteCovered { MTCallGround() }
                else if s == .local, model.selfCovered { MTCallGround(own: true) }
            }
    }
}

/// The dial's shade over one's own picture while no peer picture rides the corner -- read from the model.
private struct MTCallShade: View {
    @ObservedObject private var model = CallUIModel.shared
    var body: some View {
        if !model.miniShown, !model.peerSharing {
            LinearGradient(colors: [.black.opacity(0.35), .clear, .black.opacity(0.45)],
                           startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
        }
    }
}

// The ONE miniature (no fallbacks — the author's word 29.08): drag lives INSIDE this small
// view, so a finger move re-renders only this subtree — the big surface and the chrome never
// recompute per drag tick (the drag jerk class). Free drag, clamped inside the safe frame,
// a spring to the nearest corner on release.
/// A row of the call's chrome tells its edge in window coordinates as it is laid out (the author's word
/// 22.09: the corner picture measures from the rows themselves, not from a number about them).
private struct MTCallEdge: ViewModifier {
    let write: (CGRect) -> Void
    func body(content: Content) -> some View {
        content.background(GeometryReader { g -> Color in
            let f = g.frame(in: .global)
            DispatchQueue.main.async { write(f) }
            return Color.clear
        })
    }
}

private struct MTCallMini: View {
    let screen: CGSize
    let safeTop: CGFloat                       // the screen's safe inset (the fallback until the row is measured)
    let safeBottom: CGFloat                    // the screen's safe inset at the bottom: the picture goes down to it
    // THE CORNER PICTURE WATCHES THE MODEL ITSELF (23.09): whether it stands, its corner, the rows' edges and
    // whether the buttons are up are read here, not handed down -- a parent that stopped redrawing held the
    // picture between buttons that were already gone (the author: «limited to the area between the buttons»).
    @ObservedObject private var model = CallUIModel.shared
    @State private var drag: CGSize = .zero
    private static let w: CGFloat = 110, h: CGFloat = 156
    static let gap: CGFloat = 10               // the author's word 22.09: ten points off the marks and the buttons
    private var corner: Int { model.miniCorner }
    private var topRowBottom: CGFloat { model.topRowBottom }
    private var buttonsTop: CGFloat { model.buttonsTop }
    private var buttonsUp: Bool { model.chromeVisible && !model.screenSharing && !model.peerSharing }
    private var topUp: Bool { model.chromeVisible || model.screenSharing }
    private var blockRect: CGRect { (model.chromeVisible && !model.screenSharing) ? model.bottomRowRect : .zero }
    private func center(_ d: CGSize) -> CGPoint {
        let xs = [14 + Self.w / 2, screen.width - 14 - Self.w / 2]
        // TWO FACTS DECIDE THE PLACE, ONE FOR EACH EDGE, AND THE EDGES ARE MIRRORS (the author's word 23.09: «in the
        // bottom corner when there are no buttons, rising over them when they appear»; then «the same at the top: the
        // very corner with the same margin as at the bottom, and shifting when the buttons appear»). The place used
        // to follow NUMBERS — a rect measured a frame late, zeroed when its row left and read stale when it came
        // back — so what the person saw changed from one moment to the next. Now: the top panel up — ten points under
        // its remembered bottom, down — fourteen points under the safe top; the buttons up — ten points over the
        // grid's remembered top, down — fourteen points over the safe bottom. The moves are the springs below.
        // Until a row has been measured once, its place keeps a row's height of room.
        let lowered = (topRowBottom > 0 ? topRowBottom : safeTop + MontanaCallMark.topPad + montanaTouchTarget) + Self.gap
        let top = topUp ? lowered : safeTop + 14
        let raised = buttonsTop > 0 ? buttonsTop - Self.gap : screen.height - safeBottom - 220
        let bottom = buttonsUp ? raised : screen.height - safeBottom - 14
        let ys = [top + Self.h / 2, max(top + Self.h / 2, bottom - Self.h / 2)]
        var p = CGPoint(x: corner % 2 == 0 ? xs[0] : xs[1], y: corner < 2 ? ys[0] : ys[1])
        p.x = min(max(p.x + d.width, xs[0]), xs[1])
        p.y = min(max(p.y + d.height, ys[0]), ys[1])
        return p
    }
    var body: some View {
        if model.miniShown {
            MTCallSurface(slot: .mini)
                .frame(width: Self.w, height: Self.h)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.25), lineWidth: 1))
                // THE TOUCH IS THE PLATFORM'S OWN (the author's word 18.09: native by UIKit, from the first
                // touch): a tap and a pan recognizer on one view, arbitrated by UIKit — a tap that does not
                // move is a tap, a finger that moves is a drag. The translation is read in the WINDOW's
                // space: the local space moves with the picture it drags, the translation feeds back on
                // itself and the picture jitters under the finger. The tap writes its word in the diary;
                // the swap it causes is written by its owner (CallUIModel.applySides, «call_sides»).
                .overlay(
                    MTCallMiniTouch(
                        blockRect: blockRect,
                        onTap: { MontanaP2PTrace.mark("call_pip", "tapped — swap"); model.pipSwapped.toggle() },
                        onDrag: { drag = $0 },
                        onEnd: { v in
                            let p = center(v)
                            let c = (p.x > screen.width / 2 ? 1 : 0) + (p.y > screen.height / 2 ? 2 : 0)
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                model.miniCorner = c; drag = .zero
                            }
                        })
                )
                .position(center(drag))
                .animation(.spring(response: 0.35, dampingFraction: 0.86), value: buttonsUp)
                .animation(.spring(response: 0.35, dampingFraction: 0.86), value: topUp)
                .animation(.spring(response: 0.35, dampingFraction: 0.86), value: topRowBottom)
                .animation(.spring(response: 0.35, dampingFraction: 0.86), value: buttonsTop)
                // WHERE IT STANDS IS WRITTEN, NOT GUESSED (23.09: the author saw the corner picture wrong again,
                // and the diary could not say where it had stood). Its corner, its bottom edge against the
                // screen's safe bottom, and whether the buttons were up — at birth, at every settle, and when
                // the buttons come or go.
                .onAppear { note("born") }
                .onChange(of: model.miniCorner) { _, _ in note("moved") }
                .onChange(of: buttonsUp) { _, _ in note("buttons") }
                .onChange(of: topUp) { _, _ in note("panel") }
                .onChange(of: screen) { _, _ in note("screen") }
                .onChange(of: buttonsTop) { _, _ in note("grid") }
                // The top row's edge is witnessed too (23.09): a birth reads the remembered edges, and the line that
                // follows it says when the row was measured again (18:46:23 born with the share's 99, the panel's 165 unsaid).
                .onChange(of: topRowBottom) { _, _ in note("row") }
        }
    }
    private func note(_ why: String) {
        let c = center(.zero)
        MontanaP2PTrace.mark("call_pip", "\(why) corner=\(corner) bottom=\(Int(c.y + Self.h / 2)) safe_bottom=\(Int(screen.height - safeBottom)) top=\(Int(c.y - Self.h / 2)) screen=\(Int(screen.width))x\(Int(screen.height)) buttons=\(buttonsUp ? 1 : 0) panel=\(topUp ? 1 : 0) panel_bottom=\(Int(topRowBottom)) grid_top=\(Int(buttonsTop))")
    }
}

/// The miniature's touch: UIKit's own tap and pan on one clear view (see MTCallMini).
///
/// WHERE THE BUTTONS STAND, THE TOUCH IS THEIRS (the author's word 22.09). This is a real view of the
/// platform's inside a drawn tree, and the platform hands a touch to the deepest view that holds it —
/// so a picture standing BEHIND the buttons would still have taken the finger meant for the end of the
/// call, and the button drawn over it would never have felt it. The picture therefore refuses, by
/// itself, every touch that lands inside the grid's measured rect while the buttons are up: the buttons
/// keep their own ground, the picture keeps all the rest, and nothing has to move for it.
private struct MTCallMiniTouch: UIViewRepresentable {
    let blockRect: CGRect
    let onTap: () -> Void
    let onDrag: (CGSize) -> Void
    let onEnd: (CGSize) -> Void
    func makeUIView(context: Context) -> UIView {
        let v = MTHorizontalOwner()   // its drag is its own: the tabs' pan gives way over it (24.09)
        v.backgroundColor = .clear
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap))
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        tap.delegate = context.coordinator
        pan.delegate = context.coordinator
        v.addGestureRecognizer(tap)
        v.addGestureRecognizer(pan)
        return v
    }
    func updateUIView(_ v: UIView, context: Context) { context.coordinator.parent = self }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: MTCallMiniTouch
        init(_ p: MTCallMiniTouch) { parent = p }
        /// The one question this view asks of every touch: does it land where the buttons stand?
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            let r = parent.blockRect
            guard !r.isEmpty else { return true }
            return !r.contains(touch.location(in: nil))   // window coordinates: the rect is measured there
        }
        @objc func tap() { parent.onTap() }
        @objc func pan(_ g: UIPanGestureRecognizer) {
            let t = g.translation(in: g.view?.window)
            let d = CGSize(width: t.x, height: t.y)
            switch g.state {
            case .changed: parent.onDrag(d)
            case .ended, .cancelled, .failed: parent.onEnd(d)
            default: break
            }
        }
    }
}

/// THE PEER'S FACE IS THE GROUND OF THE CALL (the author's word 21.09) -- and its cover (23.09): drawn
/// the way the crest stands behind the chats tab — one haze edge to edge and the picture itself at the
/// centre, the same softness numbers (MontanaCrestGround, one owner) — under the name, the words and the
/// buttons; the video, when it renders, covers it. Without a photo: the system wash and the initial,
/// dimmed. ONE VIEW, ONE OWNER OF THE DRAWING: under a voice call, under the sharer's own screen, and over
/// a peer's picture that stood still (the author's word 23.09: «the blurred face, as in a voice call»).
/// It watches the model itself, so it never waits for a parent to redraw it.
struct MTCallGround: View {
    /// My own face instead of the peer's -- the cover over my own picture (23.09).
    var own = false
    @ObservedObject private var model = CallUIModel.shared
    var body: some View {
        let face = own ? MontanaSelfFace.image : model.peerImage
        GeometryReader { g in
            ZStack {
                LinearGradient(colors: [Color(red: 0.13, green: 0.15, blue: 0.19),
                                        Color(red: 0.16, green: 0.20, blue: 0.28),
                                        Color(red: 0.10, green: 0.11, blue: 0.13)],
                               startPoint: .topTrailing, endPoint: .bottomLeading)
                if let ui = face {
                    Image(uiImage: ui).resizable().scaledToFill()
                        .frame(width: g.size.width, height: g.size.height)
                        .blur(radius: MontanaCrestGround.hazeBlur)
                        .opacity(MontanaCrestGround.hazeOpacity)
                    Image(uiImage: ui).resizable().scaledToFit()
                        .frame(width: min(g.size.width, g.size.height) * MontanaCrestGround.scale)
                        .blur(radius: MontanaCrestGround.blur)
                        .opacity(MontanaCrestGround.opacity)
                } else {
                    Text(own ? E2E.myFaceGlyph() : String(MontanaCall.shared.callerName(model.peer ?? "").prefix(1)).uppercased())
                        .font(.system(size: min(160, min(g.size.width, g.size.height) * 0.6), weight: .bold))
                        .foregroundColor(Color.accentColor.opacity(0.22))
                }
            }
            .frame(width: g.size.width, height: g.size.height)
            .clipped()
            .drawingGroup()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct CallOverlayView: View {
    @ObservedObject var model: CallUIModel
    // THE BUTTONS ARE ALWAYS THERE, AND A TAP ON THE PICTURE HIDES THEM (the author's word 21.09):
    // on a video call the panel stands from the first frame and steps aside on a tap of the
    // picture, and the next tap brings it back — the picture is the switch, nothing else folds it
    // (the link, the state and the peer's picture never do: the 20.09 rule holds for those). On a
    // voice call there is no picture to tap, the panel stands. A riding screen (mine or the
    // peer's) keeps its own face, and there the pill carries End.
    private var videoBranch: Bool { model.video || MontanaCall.shared.isVideo }
    private var chromeVisible: Bool { model.chromeVisible }
    @Environment(\.verticalSizeClass) private var vClass
    private var landscape: Bool { vClass == .compact }
    /// The ground is one view (MTCallGround): the voice call, the sharer's own screen and the cover over
    /// a peer's picture that stood still all draw it through the one owner.
    var callGround: some View { MTCallGround() }
    /// The buttons are cut from the screen's width, never from a number: three columns in portrait
    /// (the system grid), one row of six in landscape (the system's own landscape face). A column
    /// is the circle plus its caption; on the narrowest phone the circle keeps 44 points and more.
    private func grid(_ w: CGFloat) -> (side: CGFloat, col: CGFloat, gap: CGFloat) {
        if landscape {
            let gap: CGFloat = 12
            let col = min(84, floor((w - 32 - 5 * gap) / 6))
            return (max(44, min(64, col - 4)), col, gap)
        }
        let gap: CGFloat = 24
        let col = min(100, floor((w - 32 - 2 * gap) / 3))
        return (max(44, min(76, col - 4)), col, gap)
    }
    var statusText: String {
        switch model.state {
        case "connected": return ""   // the duration is a live label, not a string — see callDuration
        case "active", "reconnecting": return "Connecting…"
        case "outgoing": return model.connecting ? "Connecting…" : (model.peerRinging ? "Ringing…" : "Calling…")
        default: return ""
        }
    }
    var body: some View {
        Group {
            if model.state == "idle" { EmptyView() }
            else if model.state == "incoming" { incomingScreen }   // in-app ring (window shows it only when the app is active)
            else if model.minimized { minimizedPill }
            else { fullScreen }
        }
        // THE CAMERA REFUSAL IS SAID TO THE FACE (the author's word 20.09): the system alert with
        // the system road to Settings (UIApplication.openSettingsURLString). iOS restarts the app
        // when the switch is flipped, so the call is placed again after it.
        .alert("Camera is off for Montana", isPresented: $model.cameraDenied) {
            Button("Open Settings") { MontanaSystemSettings.open(callWarned: true) }
            Button("Continue with voice", role: .cancel) {}
        } message: {
            // A call whose peer rebuilds in place goes on after the restart (24.09): the words say what will happen.
            if MontanaCall.shared.outlivesItsProcess {
                Text("Your video is not sent. Allow the camera in Settings › Montana › Camera — iOS restarts Montana when the switch changes. Come back within a minute, and the call goes on.")
            } else {
                Text("Your video is not sent. Allow the camera in Settings › Montana › Camera, then call again — iOS restarts Montana when the switch changes.")
            }
        }
    }

    // In-app incoming ring: half-screen photo + native-style Accept/Decline (our colors).
    // Incoming wears the SAME native face as the outgoing screen: the wash, the
    // glyph line, the 40pt name — only the bottom row differs (Decline / Accept).
    var incomingScreen: some View {
        GeometryReader { geo in
        let m = grid(geo.size.width)
        ZStack {
            callGround
            VStack(spacing: 10) {
                Spacer().frame(height: landscape ? 6 : 22)   // the notch is the safe area's (safeAreaPadding below), this is the gap under it
                HStack(spacing: 6) {
                    MTCallLight()
                    Text(LocalizedStringKey(model.video ? "Montana Video Call" : "Montana Audio Call"))
                }
                .font(.title3).foregroundColor(.white.opacity(0.6))
                Text(MontanaCall.shared.callerName(model.peer ?? ""))
                    .font(.system(size: landscape ? 28 : 40, weight: .bold)).foregroundColor(.white)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 0)   // the face is the ground now; the column's flexible piece is empty room
                HStack(alignment: .top, spacing: 72) {
                    gridBtn("Decline", "phone.down.fill", active: false, tint: .red, side: m.side, col: m.col) {
                        MontanaCall.shared.endByHand("decline")
                    }
                    gridBtn("Accept", "phone.fill", active: false, tint: .green, side: m.side, col: m.col) {
                        MontanaCall.shared.answerFromUI()
                    }
                }.padding(.bottom, landscape ? 12 : 46)
            }
            .safeAreaPadding(.top)
            .mtOnScreen("call-incoming")
        }
        }
    }

    var minimizedPill: some View { CallOverlayView.pillBody(model: model) }
    static func pillBody(model: CallUIModel) -> some View {
        HStack(spacing: 8) {
            Spacer()
            Button { model.fold(false, why: "pill") } label: {
                HStack(spacing: 8) {
                    Image(systemName: MontanaCall.shared.isVideo ? "video.fill" : "phone.fill")
                    if model.state == "connected", let since = model.startedAt {
                        Text(timerInterval: since...Date.distantFuture, countsDown: false)
                    } else { Text("Call") }
                }.font(.footnote.bold()).foregroundColor(.white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color.green).clipShape(Capsule()).shadow(radius: 4)
            }
            Button { MontanaCall.shared.endByHand("pill") } label: {
                Image(systemName: "phone.down.fill").font(.footnote.bold()).foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.red).clipShape(Circle()).shadow(radius: 4)
                    .frame(width: montanaTouchTarget, height: montanaTouchTarget).contentShape(Rectangle())   // the finger's 44 points around the 32-point face
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.bottom, 64).frame(maxHeight: .infinity, alignment: .bottom)   // 15.8: above the tab bar, never over a name
    }

    var fullScreen: some View {
        GeometryReader { screen in
        let m = grid(screen.size.width)
        ZStack {
            callGround   // the peer's face under everything; a rendered video covers it
            if model.screenSharing {
                // THE SHARER SEES THE PEER'S GROUND (23.09): the camera rests while the screen rides. The
                // preview layer that stood here bound the call's capture session from the main thread while
                // the camera's queue raised a new session at the share's end -- «startRunning may not be
                // called between calls to beginConfiguration and commitConfiguration», 13:30:22 on the
                // iPhone 15, and the same pair met without a crash three times on T1 (cam_preview rebind
                // 4 ms after share stopped). The session has one owner now, its queue; this branch shows
                // the ground laid under everything above.
                EmptyView()
            } else if model.video || MontanaCall.shared.isVideo {
                // The machine's own truth rides as the belt: two measured calls dialed on the
                // AUDIO branch while the camera ran — the mirrored flag failed to arrive. The
                // voice below names the traitor on the next run.
                // LIVE SURFACES ARE NOT RECREATED. The former .id(model.tick) on every camera event
                // tore down and rebuilt both pictures, and recreation is synchronous surgery on a
                // RUNNING camera from the main thread: detach the display layer from a live session,
                // attach a new one, re-read the connection. The measurement caught it as a nine-second
                // main-thread freeze 40-180 ms after cam_ok in EVERY call -- hence both "connecting
                // takes ~12 s" (cam_ok at 3 s plus 9 of freeze), and the own picture going dark, and
                // nine deaf seconds on the hang-up tap. Voice has no surfaces -- that is why it was
                // always instant.
                // The own picture is ONE node for the whole call: when the peer's appears, it changes
                // only its frame (full screen -> inset), without being recreated. The peer's is born
                // once, when the track arrives; a change of track itself both catch inside updateUIView.
                // FIXED SLOTS, root closure of three strikes at once (freeze on mini tap,
                // blank dial preview, corner overlap): two slots with FIXED frames — the big
                // one is born fullscreen and stays fullscreen, the mini is born 110x156 and
                // stays so; only the TRACKS change hands inside the slots (the proven
                // one-reattach road in updateUIView). No live surface is ever resized (the
                // 9s-freeze law), and no AVCapture session is bound at all — the local WebRTC
                // track lights the dial screen from the camera's first frame by itself.
                // WHICH PICTURE FILLS WHICH SLOT is the model's decision (CallUIModel.applySides), read by
                // the slots themselves with the mirror, the black of a shared screen and the cover (23.09).
                GeometryReader { geo in
                    ZStack {
                        MTCallSurface(slot: .big)
                        // THE PICTURE IS THE SWITCH (the author's word 21.09): a tap hides the buttons, the next
                        // tap brings them back; the surface itself never moves. THE SWITCH IS A LAYER OF ITS OWN,
                        // NOT A MODIFIER ON THE PICTURE (29.09): a tap hung as an overlay on the picture's platform
                        // view never fired on iOS 17 (the iPad on 17.7.11: nine video calls 22-29.09, not one
                        // call_chrome line, while the back mark standing in the same stack folded the call at
                        // 14:35:32 on 27.09), and fired on every 18 and later. A sibling in the stack is hit-tested
                        // by the drawn tree alone, the way the marks and the buttons are, on every system.
                        Color.clear.contentShape(Rectangle())
                            .onTapGesture { model.chromeHidden.toggle(); MontanaP2PTrace.mark("call_chrome", model.chromeHidden ? "hidden by tap" : "shown by tap") }
                        MTCallShade()
                        MTCallMini(screen: geo.size,
                                   safeTop: MTScene.safeInsets().top,
                                   safeBottom: MTScene.safeInsets().bottom)
                    }
                }
                .ignoresSafeArea()
                .onAppear { MontanaP2PTrace.mark("call_screen", "branch=video model=\(model.video ? 1 : 0) machine=\(MontanaCall.shared.isVideo ? 1 : 0)") }
            } else {
                // The voice call stands on the same ground (callGround above): the face and the wash.
                Color.clear
                    .onAppear { MontanaP2PTrace.mark("call_screen", "branch=audio model=\(model.video ? 1 : 0) machine=\(MontanaCall.shared.isVideo ? 1 : 0)") }
            }
            if model.screenSharing || model.peerSharing {
                // The author's word: while a screen rides — mine or the peer's — none of our
                // words or buttons over it: one arrow in a circle, top left, folds the demo
                // away; the green pill brings it back.
                VStack {
                    HStack {
                        MontanaCallMark(glyph: "chevron.down", label: "Back") { model.fold(true, why: "back-share") }   // the chat's mark, one to one (22.09)
                        Spacer()
                    }.padding(.horizontal, MontanaCallMark.sidePad).padding(.top, MontanaCallMark.topPad)
                    // The share's row speaks for the corner picture only while I share (the picture stands under it then).
                    // Under the peer's share no picture stands, and this row's edge overwrote the panel's remembered one:
                    // when the share ended the picture was born 66 points high and slid down (T1 18:46:23, 99 for 165).
                    .modifier(MTCallEdge { f in if model.screenSharing, abs(model.topRowBottom - f.maxY) > 0.5 { model.topRowBottom = f.maxY } })
                    Spacer()
                    if model.screenSharing {
                        // the sharer can stop the demo right here; ending the call lives on the pill
                        Button { MTScreenShare.shared.dropPeer() } label: {
                            Image(systemName: "rectangle.inset.filled.and.person.filled")
                                .font(.system(size: 22)).foregroundColor(.black)
                                .frame(width: 56, height: 56)
                                .background(Color.white).clipShape(Circle())
                        }.padding(.bottom, 40)
                    }
                }
            } else if chromeVisible {
            VStack(spacing: 10) {
                VStack(spacing: 2) {
                HStack {
                    // THE CHAT'S MARKS, ONE TO ONE (the author's word 22.09): the fold-away and the camera
                    // flip are the same marks as the chat's back arrow and handset — the platform's glass
                    // circle, the same glyph size, a 44-point target, a Button (a bare tap gesture over a
                    // 36-point plate flipped the iPhone 17's camera to its room on 21.09 with no line to say so).
                    // THE FOLD IS THE APP'S LEAVING (the author's word 29.09): on a video call the mark asks the platform's
                    // own window to rise (MTCallFloat.foldAway) and the screen folds under it -- a voice call the same, its
                    // window showing the peer's cover; with no window to ask (a system that holds it impossible) the mark
                    // folds the call into the app as before.
                    MontanaCallMark(glyph: "chevron.down", label: "Back") {
                        if !MTCallFloat.shared.foldAway(why: "back") { model.fold(true, why: "back") }
                    }
                    // THE MASK'S TWIN ROOM (checklist 36): the mask stands beside the camera flip on the right, and an
                    // empty room of the same size here keeps the name in the centre of the row.
                    if videoBranch {
                        Color.clear.frame(width: montanaTouchTarget, height: montanaTouchTarget)
                    }
                    // THE NAME STANDS IN THE CENTRE OF THE TOP ROW ON A VIDEO CALL (the author's word 23.09: no words
                    // about the kind of call; the name as large as the marks, between the arrow and the camera flip).
                    // The block is the row's own height (MTCallTopTitle); the time stands under the row.
                    if videoBranch {
                        MTCallTopTitle(model: model).frame(maxWidth: .infinity)
                    } else {
                        Spacer()
                    }
                    if model.video {
                        // THE MASK (the author's word 30.09, checklist 36): a glyph mark with no word on the platform's 44 points,
                        // a sibling over the picture in the stack -- never a gesture on its platform view. Filled masks: it is on.
                        MontanaCallMark(glyph: model.masked ? "theatermasks.fill" : "theatermasks", label: "Mask") {
                            MTAvatarMask.shared.toggle(why: "tap")
                        }
                        MontanaCallMark(glyph: "camera.rotate", label: "Camera") { MontanaCall.shared.switchCamera() }
                    } else if videoBranch {
                        // No flip mark and no mask (my camera is off): their places are held, so the block stays in the centre.
                        Color.clear.frame(width: montanaTouchTarget, height: montanaTouchTarget)
                        Color.clear.frame(width: montanaTouchTarget, height: montanaTouchTarget)
                    }
                }
                // THE TIME UNDER THE NAME, THEN THE EVENTS (the author's word 23.09): the light and the time a little
                // apart from the name, centred; under them a strip for the events that is always there on a video
                // call. All of it is measured WITH the row — the corner picture stands under the whole panel, so
                // neither the call connecting nor an event coming moves anything.
                if videoBranch {
                    MTCallTimeLine(model: model, statusText: statusText).padding(.top, 4)
                    MTCallStateLine(model: model)
                }
                }.padding(.horizontal, MontanaCallMark.sidePad).padding(.top, MontanaCallMark.topPad)
                .modifier(MTCallEdge { f in if abs(model.topRowBottom - f.maxY) > 0.5 { model.topRowBottom = f.maxY } })
                // A video call leaves the room between the panel and the buttons empty (its events stand under
                // the panel, MTCallStateLine). A voice call keeps the system's own place under the marks.
                if videoBranch { Spacer(minLength: 0) } else { Spacer().frame(height: landscape ? 0 : 20) }
                if !videoBranch {
                    // The system line, 1:1: the app glyph, «Montana Audio Call — 00:03», then the name.
                    HStack(spacing: 6) {
                        MTCallLight()
                        Text(LocalizedStringKey("Montana Audio Call"))
                        if model.state == "connected", let since = model.startedAt {
                            Text(verbatim: "—")   // USER-DATA: a dash glyph
                            Text(timerInterval: since...Date.distantFuture, countsDown: false)
                        } else if !statusText.isEmpty {
                            Text(verbatim: "—")   // USER-DATA: a dash glyph
                            Text(LocalizedStringKey(statusText))
                        }
                    }
                    .font(.title3).monospacedDigit().foregroundColor(.white.opacity(0.6))
                    Text(MontanaCall.shared.callerName(model.peer ?? ""))
                        .font(.system(size: landscape ? 28 : 40, weight: .bold)).foregroundColor(.white)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
                // NO LINE UNDER THE NAME (the author's word 13.09): the status line above says what
                // the call is doing — the light, the kind, the time or the stage — and nothing else
                // stands between the name and the picture, nor holds the chrome up. Every cause a
                // line used to carry (camera, doors, a refused description) lives in the diary.
                // On a video call these two lines stand under the call's time in the top row (MTCallTopTitle).
                if !videoBranch, model.heldByPeer || model.held {
                    // the hold line — 30% larger than the footnote and bold (the author's word)
                    Text(LocalizedStringKey("On hold"))
                        .font(.system(size: 17, weight: .bold)).foregroundColor(.white)
                        .padding(.top, 2)
                }
                if !videoBranch, model.state == "reconnecting" {
                    // A BREAK IS A STATE OF THE CALL, not a passing notice: it wears the same
                    // face as «On hold» (the author's word 29.08) and is drawn from the state
                    // itself, so it can never linger after the link is back.
                    Text(LocalizedStringKey("Connection lost — reconnecting"))
                        .font(.system(size: 17, weight: .bold)).foregroundColor(.white)
                        .padding(.top, 2)
                }
                if model.screenSharing {
                    Text(LocalizedStringKey("You are sharing your screen"))
                        .font(.system(size: 17, weight: .bold)).foregroundColor(Color.accentColor)
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)   // the face is the ground (callGround); the room between the name and the buttons is empty
                if model.videoAskIncoming {
                    HStack(spacing: 12) {
                        (Text(verbatim: MontanaCall.shared.callerName(model.peer ?? "")).bold()   // USER-DATA: the peer's name
                         + Text(verbatim: " ")   // USER-DATA: a space glyph
                         + Text("is calling with video"))
                            .font(.subheadline).foregroundColor(.white)
                        Button { MontanaCall.shared.acceptVideoAsk() } label: {
                            Text(LocalizedStringKey("Accept")).font(.subheadline.bold())
                                .foregroundColor(.black)
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(Color.green).clipShape(Capsule())
                        }
                        Button { MontanaCall.shared.declineVideoAsk() } label: {
                            Text(LocalizedStringKey("Decline")).font(.subheadline.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(Color.red).clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Color.black.opacity(0.45)).clipShape(Capsule())
                    .padding(.bottom, 12)
                }
                if model.videoAsk, !model.peerSharing, model.video {
                    HStack(spacing: 12) {
                        Text(LocalizedStringKey("Turn on your video?"))
                            .font(.subheadline).foregroundColor(.white)
                        Button { MontanaCall.shared.enableMyVideo() } label: {
                            Text(LocalizedStringKey("Turn On")).font(.subheadline.bold())
                                .foregroundColor(.black)
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(Color.accentColor).clipShape(Capsule())
                        }
                        Button { model.videoAsk = false } label: {
                            Image(systemName: "xmark").font(.footnote.bold()).foregroundColor(.white)
                                .frame(width: 28, height: 28)
                                .background(Color.white.opacity(0.18)).clipShape(Circle())
                                .montanaFingerRoom(layout: 28)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Color.black.opacity(0.45)).clipShape(Capsule())
                    .padding(.bottom, 12)
                }
                // The system grid, 1:1 — two rows of three. Every button carries a real
                // function: «more» opens hold and camera flip; the keypad types locally.
                // The system grid, cut from the screen's width (grid(_:)): two rows of three in
                // portrait, one row of six in landscape — the system's own two faces. Every button
                // carries a real function: «more» opens hold and camera flip; the keypad types locally.
                let rowGap: CGFloat = m.gap
                // THE AUDIO BUTTON WEARS THE SYSTEM CALL'S OWN WORDS (MontanaAudioRoute.Face, the author's word 24.09): with
                // the phone alone it is «Speaker» and one press moves the sound between the ear and the loudspeaker; with a
                // headset, a car or any other source it is «Audio» and the platform's own route menu opens (15.09).
                let audioBtn = routeBtn(model.route, side: m.side, col: m.col)
                let videoBtn = gridBtn("Video", "video.fill",
                                       active: (model.video && !model.cameraOff) || model.videoAskPending, side: m.side, col: m.col) { MontanaCall.shared.toggleVideo() }
                // THE MICROPHONE OFF IS SHOWN AS THE SYSTEM'S OWN CALL SHOWS IT (the author's word 24.09 with the reference):
                // the lit plate with the crossed microphone in red; the press answers under the finger with a light tap.
                let muteBtn = gridBtn("Mute", "mic.slash.fill",
                                      active: model.muted, activeGlyph: .red, side: m.side, col: m.col) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    MontanaCall.shared.muteFromUI(!model.muted)
                }
                let holdBtn = gridBtn(model.hasParked ? "Swap" : "Hold",
                                      model.hasParked ? "arrow.triangle.2.circlepath" : "pause.fill",
                                      active: model.held, side: m.side, col: m.col) { MontanaCall.shared.holdFromUI() }
                let endBtn = gridBtn("End", "phone.down.fill", active: false, tint: .red, side: m.side, col: m.col) {
                    MontanaCall.shared.endByHand("grid")
                }
                // «Broadcast» (the author's word 21.09): the system's broadcast picker IS the button, on the
                // chat's glass face like the rest; the picker's own view rides invisibly over the plate.
                let screenBtn = VStack(spacing: 8) {
                    Image(systemName: "rectangle.inset.filled.and.person.filled")
                        .font(.system(size: m.side * 0.34, weight: .semibold))
                        .foregroundColor(model.screenSharing ? .black : MontanaOctagon.barGlyph)
                        .montanaOctagonFace(square: true, bar: true, height: m.side, tint: model.screenSharing ? .white : nil)
                        .overlay(MTBroadcastPickerButton().frame(width: m.side, height: m.side))
                    Text(LocalizedStringKey("Broadcast")).font(.subheadline).foregroundColor(.white)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(width: m.col)
                // The grid tells its top edge as it is laid out (MTCallEdge, the same way the top row does):
                // the corner picture measures from the buttons themselves, not from a number about them.
                if landscape {
                    HStack(alignment: .top, spacing: rowGap) {
                        audioBtn; videoBtn; muteBtn; holdBtn; endBtn; screenBtn
                    }
                    .modifier(MTCallEdge { f in
                        if model.bottomRowRect != f { model.bottomRowRect = f }
                        if f.height > 0, model.buttonsTop != f.minY { model.buttonsTop = f.minY }
                    })
                    // AND IT TELLS WHEN IT IS GONE (the author 22.09: "it worked after a screen share, it was
                    // not stable"). A rect written by a view that is not always in the tree goes stale the
                    // moment the view leaves — the grid is not built at all while a screen rides, nor while
                    // the chrome is folded away, and whoever read that number went on believing the buttons
                    // were still standing there. The grid says .zero as it leaves; nobody has to guess.
                    .onDisappear { if model.bottomRowRect != .zero { model.bottomRowRect = .zero } }
                    .padding(.bottom, 12)
                } else {
                    VStack(spacing: 30) {
                        HStack(alignment: .top, spacing: rowGap) { audioBtn; videoBtn; muteBtn }
                        HStack(alignment: .top, spacing: rowGap) { holdBtn; endBtn; screenBtn }
                    }
                    .modifier(MTCallEdge { f in
                        if model.bottomRowRect != f { model.bottomRowRect = f }
                        if f.height > 0, model.buttonsTop != f.minY { model.buttonsTop = f.minY }
                    })
                    // AND IT TELLS WHEN IT IS GONE (the author 22.09: "it worked after a screen share, it was
                    // not stable"). A rect written by a view that is not always in the tree goes stale the
                    // moment the view leaves — the grid is not built at all while a screen rides, nor while
                    // the chrome is folded away, and whoever read that number went on believing the buttons
                    // were still standing there. The grid says .zero as it leaves; nobody has to guess.
                    .onDisappear { if model.bottomRowRect != .zero { model.bottomRowRect = .zero } }
                    .padding(.bottom, 46)
                }
            }
            // INSIDE THE SAFE AREA BY CONSTRUCTION (the author's word 20.09: on T3 the top of the call
            // screen stood under the notch): the platform's own safeAreaPadding adds exactly the part
            // of the notch this container did not already respect — zero where it did — and the
            // frame is measured (offscreen) so the diary says if any edge is ever crossed again.
            .safeAreaPadding(.top)
            .mtOnScreen("call-chrome")
            }
        }
        .onAppear { model.chromeHidden = false }   // every call starts with its buttons in the hand
        // THE ROOM THE CALL IS GIVEN IS WRITTEN (23.09): the buttons stand on the bottom of this room, and the diary
        // could not say who had moved it (T1 18:47:58, 207 points while the app went to the background). Every change
        // of its bottom is one line beside the window's own inset and the app's phase; with the keyboard's region
        // taken away (CallWindowPresenter), a line here names any other source.
        .onChange(of: screen.safeAreaInsets.bottom) { was, now in
            let s = UIApplication.shared.applicationState
            let phase = s == .active ? "active" : (s == .background ? "background" : "inactive")
            MontanaP2PTrace.mark("call_safe", "bottom=\(Int(now)) was=\(Int(was)) window_bottom=\(Int(MTScene.safeInsets().bottom)) size=\(Int(screen.size.width))x\(Int(screen.size.height)) phase=\(phase)")
        }
        }
    }
    // The system broadcast picker IS the button: the permission sheet, the countdown and
    // the red status pill are all the system's own. Only the tint is ours.
    struct MTBroadcastPickerButton: UIViewRepresentable {
        func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
            let v = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 76, height: 76))
            v.preferredExtension = MontanaContour.appId + ".MontanaBroadcast"
            v.showsMicrophoneButton = false
            Self.hideOwnFace(v)
            return v
        }
        func updateUIView(_ v: RPSystemBroadcastPickerView, context: Context) {
            Self.hideOwnFace(v)
        }
        // The picker paints its own broadcast circle over our glyph; tint does not touch
        // it. Its button keeps the tap, loses the face — configured on create and on each
        // SwiftUI render (our own lifecycle, not a patrol).
        static func hideOwnFace(_ v: RPSystemBroadcastPickerView) {
            v.tintColor = .clear
            for case let b as UIButton in v.subviews {
                b.setImage(nil, for: .normal)
                b.setImage(nil, for: .highlighted)
                b.imageView?.alpha = 0
                b.frame = v.bounds
            }
        }
    }

    struct MTRoutePicker: UIViewRepresentable {
        func makeUIView(context: Context) -> AVRoutePickerView {
            let v = AVRoutePickerView()
            v.activeTintColor = UIColor.white
            v.tintColor = .white
            return v
        }
        func updateUIView(_ v: AVRoutePickerView, context: Context) {}
    }
    // THE CHAT'S OWN GLASS (the author's word 21.09): every call button stands on the face the chat's
    // buttons stand on — montanaOctagonFace, liquid glass where the system has it, the thin material
    // with a rim before — tinted for End / Accept / Decline and lit white when active. One face for
    // every button of the tree, no circles of our own.
    /// The audio button (MontanaAudioRoute.Face): «Speaker», the loudspeaker's switch, with the phone alone; «Audio», the
    /// system's route menu, with a device outside the phone.
    func routeBtn(_ f: MontanaAudioRoute.Face, side: CGFloat, col: CGFloat) -> some View {
        VStack(spacing: 8) {
            Button {
                // THE PRESS ANSWERS UNDER THE FINGER (the author's word 24.09): a light tap, as the system's own call
                // buttons answer; the route menu is the platform's own and answers by itself.
                if !f.menu {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    MontanaCall.shared.speakerFromUI(!model.speaker)
                }
            } label: {
                Image(systemName: f.icon).font(.system(size: side * 0.34, weight: .semibold))
                    .foregroundColor(f.lit ? .black : MontanaOctagon.barGlyph)
            }
            .buttonStyle(.montanaOctagon(square: true, bar: true, height: side, tint: f.lit ? .white : nil))
            .overlay(alignment: .top) { if f.menu { MontanaRoutePicker().frame(width: side, height: side) } }
            Text(LocalizedStringKey(f.caption))
                .font(.subheadline).foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(width: col)
    }
    func gridBtn(_ caption: String, _ icon: String, active: Bool, tint: Color? = nil, activeGlyph: Color = .black,
                 side: CGFloat = 76, col: CGFloat = 100,
                 _ action: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            Button(action: action) {
                Image(systemName: icon).font(.system(size: side * 0.34, weight: .semibold))
                    .foregroundColor(tint != nil ? .white : (active ? activeGlyph : MontanaOctagon.barGlyph))
            }
            .buttonStyle(.montanaOctagon(square: true, bar: true, height: side, tint: active ? .white : tint))
            // Every column the same width and a one-line caption — the grid stays straight
            // whatever the words weigh.
            Text(LocalizedStringKey(caption)).font(.subheadline).foregroundColor(.white)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(width: col)
    }
}



/// The capture device, built after the proven reference implementation and owned by us.
/// The stock library capturer swallows the refusal to add the camera input, keeps a session
/// without a camera and reports a clean start; it also lets the capture session reconfigure
/// the application audio session, which a CallKit call already owns — the receiver side
/// then gets "Cannot Record" and no frames. This one refuses loudly and touches no audio.
final class MontanaCamera: RTCVideoCapturer {

    enum Failure: LocalizedError {
        case inputRefused
        case inputUnavailable(String)
        case outputRefused
        case lockRefused(String)
        var errorDescription: String? {
            switch self {
            case .inputRefused:            return "the session refused the camera input"
            case .inputUnavailable(let e): return "the camera input could not be created: \(e)"
            case .outputRefused:           return "the session refused the video output"
            case .lockRefused(let e):      return "the device would not lock for configuration: \(e)"
            }
        }
    }

    /// The camera roster: wide-angle only, both sides.
    static func devices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera],
                                         mediaType: .video,
                                         position: .unspecified).devices
    }

    /// Every format of the device. Picking the fit ones is the caller's job: the capturer
    /// does not decide which format is good, it honestly hands over the list.
    static func formats(for device: AVCaptureDevice) -> [AVCaptureDevice.Format] { device.formats }

    let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "montana.camera.capture", qos: .userInitiated)
    private var device: AVCaptureDevice?
    private var isFront = true
    private var rotation: RTCVideoRotation = ._90

    override init(delegate: RTCVideoCapturerDelegate) {
        super.init(delegate: delegate)
        session.sessionPreset = .inputPriority
        // The audio session belongs to the call: capture neither creates nor reconfigures it.
        session.usesApplicationAudioSession = true
        session.automaticallyConfiguresApplicationAudioSession = false
        #if !targetEnvironment(macCatalyst)
        if session.isMultitaskingCameraAccessSupported { session.isMultitaskingCameraAccessEnabled = true }
        // Whether the camera may go on while the call floats over other apps: the platform's own answer, named once a call.
        MontanaP2PTrace.mark("cam_multitask", "supported=\(session.isMultitaskingCameraAccessSupported ? 1 : 0) enabled=\(session.isMultitaskingCameraAccessEnabled ? 1 : 0)")
        #endif
        output.alwaysDiscardsLateVideoFrames = false
        output.setSampleBufferDelegate(self, queue: queue)
        session.beginConfiguration()
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        updateRotation()
        NotificationCenter.default.addObserver(self, selector: #selector(orientationChanged),
                                              name: UIDevice.orientationDidChangeNotification, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    /// The capture start order, fixed: device lock → input rebuild →
    /// active format and rate → output pixel format → run → unlock. One deliberate
    /// difference: every step that can fail returns an error.
    func start(device d: AVCaptureDevice, format f: AVCaptureDevice.Format, fps: Int,
               done: @escaping (Error?) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            let input: AVCaptureDeviceInput
            do { input = try AVCaptureDeviceInput(device: d) }
            catch { self.finish(done, Failure.inputUnavailable(error.localizedDescription)); return }
            do { try d.lockForConfiguration() }
            catch { self.finish(done, Failure.lockRefused(error.localizedDescription)); return }
            defer { d.unlockForConfiguration() }

            self.session.beginConfiguration()
            for old in self.session.inputs { self.session.removeInput(old) }
            guard self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                self.finish(done, Failure.inputRefused)
                return
            }
            self.session.addInput(input)
            self.session.commitConfiguration()

            // The format is set ONLY from the device's own list — otherwise the system
            // answers with an exception there is no catching here. For the same reason,
            // with Center Stage on, the caller must supply a format that supports it.
            d.activeFormat = f
            if fps != 0 { d.activeVideoMinFrameDuration = CMTime(value: 1, timescale: Int32(fps)) }   // 0: the format's own rate (fpsFor)

            // The pixel format — and ONLY it. Width and height are absent on purpose:
            // they add a scaler nobody asked for.
            self.output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: self.outputFormat(for: f)
            ]

            self.device = d
            self.isFront = (d.position == .front)
            self.updateRotation()
            if !self.session.isRunning { self.session.startRunning() }
            self.finish(done, nil)
        }
    }

    func stop(done: @escaping () -> Void) {
        queue.async { [weak self] in
            guard let self else { DispatchQueue.main.async { done() }; return }
            self.session.beginConfiguration()
            for old in self.session.inputs { self.session.removeInput(old) }
            self.session.commitConfiguration()
            self.session.stopRunning()
            self.device = nil
            DispatchQueue.main.async { done() }
        }
    }

    private func finish(_ done: @escaping (Error?) -> Void, _ e: Error?) {
        DispatchQueue.main.async { done(e) }
    }

    /// The output frame kind: the format's own kind if the library reads it, otherwise the
    /// first readable one available. No iteration over output kinds — one conscious choice.
    private func outputFormat(for f: AVCaptureDevice.Format) -> OSType {
        let readable: [OSType] = [kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                                  kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        let available = output.availableVideoPixelFormatTypes
        let own = CMFormatDescriptionGetMediaSubType(f.formatDescription)
        if readable.contains(own), available.contains(own) { return own }
        return readable.first(where: available.contains) ?? available.first ?? readable[0]
    }

    @objc private func orientationChanged() { queue.async { [weak self] in self?.updateRotation() } }

    /// Frame rotation by metadata, not by pixel shuffling. The angle table is the
    /// reference's, including the separate front-camera branch in landscape.
    private func updateRotation() {
        let o = UIDevice.current.orientation
        switch o {
        case .portrait:           rotation = ._90
        case .portraitUpsideDown: rotation = ._270
        case .landscapeLeft:      rotation = isFront ? ._180 : ._0
        case .landscapeRight:     rotation = isFront ? ._0 : ._180
        default: break
        }
    }
}

extension MontanaCamera: AVCaptureVideoDataOutputSampleBufferDelegate {
    /// Every valid frame is delivered, warm-up included. The reference drops twelve while
    /// exposure converges — half a second of black at 24 fps, and the person read it as
    /// "the camera is not on". A darkening-to-bright frame IS the camera turning on (the
    /// system Camera shows exactly that), the lit-frame probe stays honest by variance,
    /// and the silence probe stops needing thirteen frames inside its 0.75 s window.
    func captureOutput(_ o: AVCaptureOutput, didOutput sb: CMSampleBuffer, from c: AVCaptureConnection) {
        guard CMSampleBufferIsValid(sb), CMSampleBufferDataIsReady(sb),
              let px = CMSampleBufferGetImageBuffer(sb) else { return }
        let ns = Int64(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb)) * 1_000_000_000)
        let frame = RTCVideoFrame(buffer: RTCCVPixelBuffer(pixelBuffer: px), rotation: rotation, timeStampNs: ns)
        delegate?.capturer(self, didCapture: frame)
    }

    func captureOutput(_ o: AVCaptureOutput, didDrop sb: CMSampleBuffer, from c: AVCaptureConnection) {
        // The reason for a dropped frame speaks of load, not of failure; no need to make
        // noise with it in the call telemetry.
    }
}

/// The go-between of the capturer and the source that decides whether the picture is ALIVE.
/// A successful camera start proves nothing: a format starts cleanly and delivers not a
/// single frame — that is how the front camera behaved while the back one worked. A frame
/// arriving is not enough either: the first front-camera frames are always black while
/// exposure and white balance converge, and on a format the library cannot read ALL of them
/// stay black. The one proof is a frame whose brightness varies across a sparse sample: a
/// dead buffer has no variance at all.
final class FrameCountingCapturerDelegate: NSObject, RTCVideoCapturerDelegate {
    private let sink: RTCVideoCapturerDelegate
    private(set) var frames = 0
    private(set) var litFrames = 0
    private var probing = false
    private var segmentFirst = true   // re-armed at every camera (re)start — see newSegment

    init(sink: RTCVideoCapturerDelegate) { self.sink = sink }

    func beginProbe() { probing = true }
    func endProbe() { probing = false }
    func newSegment() { segmentFirst = true }

    func capturer(_ capturer: RTCVideoCapturer, didCapture frame: RTCVideoFrame) {
        // THE FIRST FRAME FROM THE CAMERA -- the mark that was missing: without it "video is slow"
        // cannot be told from "the camera was slow to rise".
        if segmentFirst {
            segmentFirst = false
            MontanaP2PTrace.mark("cam_first_frame", "size=\(frame.width)x\(frame.height) n=\(frames)")
            // The mirror flips WITH the new camera's frames — and with EVERY camera, not
            // only the call's first: the once-per-call latch (frames == 0) left the
            // self-view mirrored after a flip to the back camera.
            let front = MontanaCall.shared.usingFrontCamera
            DispatchQueue.main.async {
                CallUIModel.shared.mirrorLocal = front
                CallUIModel.shared.tick += 1
            }
            if frames == 0 { MontanaCall.shared.cameraDeliveredFirstFrame() }
        }
        frames += 1
        // Measuring happens ONLY inside the probe window: in steady flow there is no reason
        // to touch every frame, and locking the buffer on the hot path is cost without gain.
        if probing, let px = (frame.buffer as? RTCCVPixelBuffer)?.pixelBuffer, Self.hasPicture(px) {
            litFrames += 1
        }
        // THE MASK TAKES THE CAMERA'S FRAME HERE, AT THE BIRTH OF WHAT GOES OUT (checklist 36): while it is on, the frame is
        // read on this phone by the face tracking and never reaches the source -- the lane and the self-view carry only the
        // avatar's frames. The count above stands all the same: the camera's life is judged by the camera's own frames.
        if MTAvatarMask.shared.take(frame, from: capturer, into: sink) { return }
        sink.capturer(capturer, didCapture: frame)
    }

    /// Brightness spread over a sparse sample. The measure is deliberately independent of
    /// illumination: a dark room yields noise and therefore spread; a dead buffer yields the
    /// same value everywhere. A mean-brightness threshold would reject honestly filmed
    /// darkness — this one does not.
    private static func hasPicture(_ px: CVPixelBuffer) -> Bool {
        let fmt = CVPixelBufferGetPixelFormatType(px)
        guard fmt == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
           || fmt == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange else { return false }
        guard CVPixelBufferLockBaseAddress(px, .readOnly) == kCVReturnSuccess else { return false }
        defer { CVPixelBufferUnlockBaseAddress(px, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(px, 0) else { return false }
        let stride = CVPixelBufferGetBytesPerRowOfPlane(px, 0)
        let w = CVPixelBufferGetWidthOfPlane(px, 0)
        let h = CVPixelBufferGetHeightOfPlane(px, 0)
        guard w > 16, h > 16, stride >= w else { return false }
        let p = base.assumingMemoryBound(to: UInt8.self)
        var lo = Int(UInt8.max), hi = 0
        for gy in 0..<8 {
            let y = h * (gy * 2 + 1) / 16
            for gx in 0..<8 {
                let v = Int(p[y * stride + w * (gx * 2 + 1) / 16])
                if v < lo { lo = v }
                if v > hi { hi = v }
            }
        }
        return hi - lo > 3
    }
}


/// THE AUDIO ROUTE, READ FROM THE SYSTEM — the one owner of «where the sound is» (the critic's
/// word 15.09). Every wish of the app for the loudspeaker asks this first; every button shows this.
enum MontanaAudioRoute {
    enum Output: Equatable { case builtin, speaker, external }
    struct Reading { let current: Output; let ports: String; var isExternal: Bool { current == .external } }
    private static let lock = NSLock()
    private static var last: Output = .builtin
    static var current: Output { lock.lock(); defer { lock.unlock() }; return last }
    static var isExternal: Bool { current == .external }
    static var isBuiltin: Bool { current == .builtin }
    /// Headphones, any Bluetooth, a car, AirPlay, a dock: the sound is not in the phone.
    private static let externalPorts: Set<AVAudioSession.Port> = [.headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .carAudio, .airPlay, .lineOut, .usbAudio]
    @discardableResult
    static func read(_ why: String) -> Reading {
        let outs = AVAudioSession.sharedInstance().currentRoute.outputs
        let out: Output = outs.contains { externalPorts.contains($0.portType) } ? .external
            : (outs.contains { $0.portType == .builtInSpeaker } ? .speaker : .builtin)
        lock.lock(); last = out; lock.unlock()
        let device = outs.first(where: { externalPorts.contains($0.portType) })
        // THE SOURCE'S OWN GLYPH (the author's word 01.10 ~00:50: «the sound's source on the unfolded player determined natively,
        // in the system's blue, with the source's icon»): the device the sound goes to, else the phone itself, as the system's
        // own output menu names it.
        let wayGlyph = device.map { glyph($0) } ?? "iphone"
        DispatchQueue.main.async {   // the detector and the screen's model are the main thread's; a route change is told on any thread
            CallUIModel.shared.audioExternal = (out == .external)
            let f = face()
            if CallUIModel.shared.route != f { CallUIModel.shared.route = f }
            let w = Way.shared
            if w.glyph != wayGlyph { w.glyph = wayGlyph }
            if w.outside != (device != nil) { w.outside = device != nil }
        }
        return Reading(current: out, ports: outs.map { $0.portType.rawValue }.joined(separator: ","))
    }

    /// THE AUDIO BUTTON WEARS THE SYSTEM CALL'S OWN WORDS (the author's word 24.09, the later one, with the reference
    /// screenshot: «everything native and exactly as on a cellular call; the speaker button, not active -- the voice at
    /// the ear, pressed -- on the loudspeaker, with no sticky menus; headphones on -- the button is renamed natively and a
    /// press shows the native menu with the right source checked»). The phone alone: «Speaker», dark at the ear and lit
    /// on the loudspeaker, and one press moves the sound. A device outside the phone: «Audio» with the glyph of where
    /// the sound is, lit unless the sound stands at the ear, and a press opens the system's route menu. A choice exists
    /// only when such a device is there: the input a headset, a car or Bluetooth brings, or the sound already standing
    /// outside the phone. The route detector's «multiple routes» is not asked: it counts AirPlay devices on the network
    /// that never carry a call, and the phone alone turned into a menu that held only the phone and the loudspeaker.
    struct Face: Equatable {
        let caption: String   // a catalogue word: «Speaker» with the phone alone, «Audio» with a device
        let icon: String      // an SF Symbol: the loudspeaker with the phone alone, where the sound is with a device
        let lit: Bool
        let menu: Bool
    }
    static func face() -> Face {
        let s = AVAudioSession.sharedInstance()
        let outs = s.currentRoute.outputs
        let ext = outs.first(where: { externalPorts.contains($0.portType) })
        let onSpeaker = outs.contains(where: { $0.portType == .builtInSpeaker })
        let choice = ext != nil || (s.availableInputs ?? []).contains { $0.portType != .builtInMic }
        if choice {
            let icon = ext.map { glyph($0) } ?? (onSpeaker ? "speaker.wave.3.fill" : "iphone")
            return Face(caption: "Audio", icon: icon, lit: ext != nil || onSpeaker, menu: true)
        }
        return Face(caption: "Speaker", icon: "speaker.wave.3.fill", lit: onSpeaker, menu: false)
    }
    private static func glyph(_ p: AVAudioSessionPortDescription) -> String {
        switch p.portType {
        case .carAudio: return "car.fill"
        case .airPlay: return "airplayaudio"
        case .headphones: return "headphones"
        case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
            let name = p.portName
            if name.localizedCaseInsensitiveContains("airpods pro") { return "airpodspro" }
            if name.localizedCaseInsensitiveContains("airpods max") { return "airpodsmax" }
            return name.localizedCaseInsensitiveContains("airpods") ? "airpods" : "headphones"
        default: return "hifispeaker.fill"
        }
    }
    /// Where the music goes, as the system's output menu names it: the external device's glyph, else the phone. Written only by read().
    final class Way: ObservableObject {
        static let shared = Way()
        @Published fileprivate(set) var glyph = "iphone"
        @Published fileprivate(set) var outside = false
    }
    /// The phone's own microphone becomes the preferred input — used whenever the sound was put
    /// on the phone (earpiece or loudspeaker) while a headset still held the voice link.
    static func preferPhoneMicrophone() {
        let session = AVAudioSession.sharedInstance()
        guard let mic = session.availableInputs?.first(where: { $0.portType == .builtInMic }) else { return }
        if session.currentRoute.inputs.contains(where: { $0.portType == .builtInMic }) { return }   // already the phone's
        do { try session.setPreferredInput(mic); MontanaP2PTrace.mark("audio_route", "input=builtInMic (the phone's output takes the phone's microphone)") }
        catch { MontanaP2PTrace.mark("audio_route", "input=builtInMic FAILED \(error.localizedDescription)") }
    }
    /// After a route change: the phone's output with a headset's input is an unfinished choice.
    static func completePhoneChoice(_ r: Reading) {
        guard r.current != .external else { return }
        let ins = AVAudioSession.sharedInstance().currentRoute.inputs
        let headsetIn = ins.contains { externalPorts.contains($0.portType) || $0.portType == .headsetMic }
        if headsetIn { preferPhoneMicrophone() }
    }
}

/// The system's own output picker (AirPods, a car, a speaker, the phone) — the platform's element.
struct MontanaRoutePicker: UIViewRepresentable {
    /// THE MENU TAP IS A MARK (20.09): the Audio button had no touch line, so «I pressed the
    /// loudspeaker while it rang» could not be placed against the route the system then took.
    /// The picker's own delegate names the opening and the closing of the sheet.
    final class Coordinator: NSObject, AVRoutePickerViewDelegate {
        func routePickerViewWillBeginPresentingRoutes(_ v: AVRoutePickerView) {
            MontanaP2PTrace.mark("touch", "audio-menu open state=\(MontanaCall.stateSnapshot)")
            UIImpactFeedbackGenerator(style: .light).impactOccurred()   // the press answers under the finger here too (24.09)
        }
        func routePickerViewDidEndPresentingRoutes(_ v: AVRoutePickerView) {
            let outs = AVAudioSession.sharedInstance().currentRoute.outputs.map { $0.portType.rawValue }.joined(separator: ",")
            MontanaP2PTrace.mark("touch", "audio-menu closed route=\(outs)")
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.delegate = context.coordinator
        // The picker draws nothing of its own: it lies over our button as the touch target, and a
        // tap opens the system's route list; the face beneath shows where the sound is.
        v.tintColor = .clear
        v.activeTintColor = .clear
        v.backgroundColor = .clear
        v.prioritizesVideoDevices = false
        return v
    }
    func updateUIView(_ v: AVRoutePickerView, context: Context) {}
}


/// THE AUDIO CALL STANDS UPRIGHT ON A PHONE (the author's word 24.09: «during an audio call from the phone the screen
/// does not turn and stays vertical»). The system's own call screen stands upright on a phone, and so does ours while it
/// is shown: an audio call on a phone holds the whole scene upright through the app's one answer to «which
/// orientations» (AppDelegate), and the scene is asked to turn upright at once when the call rises in a landscape hand.
/// A video call, a folded call and a tablet keep the orientations the app declares. Every change is a diary line
/// (call_upright).
enum MTCallUpright {
    private(set) static var held = false
    /// The orientations the app declares for this kind of device (its Info.plist lists), read once: the answer
    /// whenever no audio call holds the phone upright.
    private static let declared: UIInterfaceOrientationMask = {
        let pad = UIDevice.current.userInterfaceIdiom == .pad
        let info = Bundle.main.infoDictionary ?? [:]
        let listed = info[pad ? "UISupportedInterfaceOrientations~ipad" : "UISupportedInterfaceOrientations~iphone"]
            ?? info["UISupportedInterfaceOrientations"]
        var mask: UIInterfaceOrientationMask = []
        for name in (listed as? [String]) ?? [] {
            switch name {
            case "UIInterfaceOrientationPortrait": mask.insert(.portrait)
            case "UIInterfaceOrientationPortraitUpsideDown": mask.insert(.portraitUpsideDown)
            case "UIInterfaceOrientationLandscapeLeft": mask.insert(.landscapeLeft)
            case "UIInterfaceOrientationLandscapeRight": mask.insert(.landscapeRight)
            default: break
            }
        }
        if mask.isEmpty { return pad ? .all : .allButUpsideDown }
        return mask
    }()
    /// The app's answer now; AppDelegate asks it for every window.
    static var mask: UIInterfaceOrientationMask { held ? .portrait : declared }
    /// Holds the phone upright or frees it; the scene learns at once and turns upright if it stood in landscape.
    static func apply(_ upright: Bool) {
        guard upright != held else { return }   // SILENT-OK: nothing changed
        held = upright
        MontanaP2PTrace.mark("call_upright", upright ? "held" : "free")
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for w in scene.windows { w.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations() }
            if upright {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { error in
                    MontanaP2PTrace.mark("call_upright", "turn refused: \(error.localizedDescription)")
                }
            }
        }
    }
}


/// THE PROXIMITY SENSOR HAS ONE OWNER (the author's word 24.09: «check the proximity sensor so it works constantly and
/// stably -- during a call I covered it with a finger and took the finger away, and the screen stayed off, black and
/// dead, on T1»). The sensor's switch is one flag for the whole device, and three hands wrote it by themselves: the
/// call, the voice player and the chat's reply at the ear. One turned it off under another: the player, yielding to a
/// newborn call, turned the sensor off one turn after the call had turned it on. Every hand now holds and lets go of
/// the sensor here by its name, and the sensor is on while any hand holds it.
/// NEVER OFF WHILE «NEAR» (the reference's rule): a switch turned off while the sensor is covered leaves the screen dark,
/// and the platform no longer hears the sensor that would light it again. With no hand left and the sensor covered, the
/// switch waits for «far» and goes off then. Every change of the sensor and of the switch is a diary line (proximity):
/// a dark screen now says who held the sensor and what the sensor said last.
enum MTProximity {
    private static var holders = Set([String]())
    private static var listening: NSObjectProtocol?
    /// A hand holds the sensor (true) or lets it go (false); from any thread.
    static func hold(_ who: String, _ on: Bool) {
        guard Thread.isMainThread else { DispatchQueue.main.async { MTProximity.hold(who, on) }; return }
        if on == holders.contains(who) { return }   // SILENT-OK: this hand already stands so
        if on { holders.insert(who) } else { holders.remove(who) }
        listen()
        let dev = UIDevice.current
        if !holders.isEmpty {
            if !dev.isProximityMonitoringEnabled {
                dev.isProximityMonitoringEnabled = true
                note(dev.isProximityMonitoringEnabled ? "on" : "absent", who)   // «absent»: the device has no sensor
            }
        } else if dev.isProximityMonitoringEnabled {
            if dev.proximityState {
                note("off-at-far", who)   // covered: the switch goes off when the sensor says «far»
            } else {
                dev.isProximityMonitoringEnabled = false
                note("off", who)
            }
        }
    }
    private static func listen() {
        guard listening == nil else { return }   // SILENT-OK: one listener for the process
        listening = NotificationCenter.default.addObserver(forName: UIDevice.proximityStateDidChangeNotification,
                                                           object: nil, queue: .main) { _ in
            let dev = UIDevice.current
            MTProximity.note(dev.proximityState ? "near" : "far", "sensor")
            if !dev.proximityState, MTProximity.holders.isEmpty, dev.isProximityMonitoringEnabled {
                dev.isProximityMonitoringEnabled = false
                MTProximity.note("off", "far")
            }
        }
    }
    private static func note(_ what: String, _ why: String) {
        MontanaP2PTrace.mark("proximity", "\(what) by=\(why) holders=\(holders.sorted().joined(separator: ","))")
    }
}
