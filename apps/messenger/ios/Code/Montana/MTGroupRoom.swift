//  MTGroupRoom.swift -- a group's live room: a voice or video chat of up to 13 people, and a stream.
//
//  THE AUTHOR'S WORDS 07.10.2026 MSK. 00:2x: "groups up to 130 people and audio and video calls in a group with up to 13 connected
//  at once ... and add streaming so one can connect to stream rooms". 00:3x: "a tap on the phone in a group chooses the kind of call,
//  then whom of the group to invite by a link to the group call, not by the call itself; the link opens the way into the room;
//  everyone has a picture of their own on the screen, even on audio; easy control of the groups and the calls, in our style, with
//  the screen shown, and the control with the call's owner, who created it".
//
//  No server holds a room and no phone carries another's picture: a room of N is N-1 calls of two that share one microphone and one
//  camera (the checklist, stage G.2). Every pair speaks its own lane -- the node's blind envelope sealed by a key only the two derive
//  from the room's key and their seats -- and the later of the two to come in offers, so two offers never cross. Each pair has its
//  own encoder, so each watcher gets the picture it asks for: a small one in the grid, the whole one when it shows that person large.
//  The room is told to the group by the group's own word (MTGroup "room"): opened, invited, came in, went out, closed; the room's
//  key rides inside those end-to-end words alone. An invitation is a word of the group to the seats chosen -- a way in, never a ring.
//
//  [I-16] A-4 -- admission, not security: the media transport is WebRTC (DTLS-SRTP), classical by its standard, as in MontanaCall.

import Foundation
import WebRTC
import CallKit
import AVFoundation
import SwiftUI
import CryptoKit
import UIKit
import MontanaBindings

/// What a room is: a chat where everyone speaks and shows, or a stream where its owner speaks and the rest watch.
enum MTRoomKind: String, Codable { case call, live }

/// A room's event on the group's road (MTGroupWord "room", its JSON in tx). Short keys; a key a reader does not know is skipped.
struct MTRoomEvent: Codable {
    /// The room's id: 32 lowercase hex.
    var r: String
    /// open, ask (an invitation to the seats in to), in, key (my room key, handed to the one who came in), here (the room is alive --
    /// its first one says so every ten minutes), out, end.
    var e: String
    /// The room's kind (MTRoomKind).
    var m: String
    /// The room's key, base64 of 32 bytes: rides open, ask and in.
    var k: String?
    /// 1: the speaker comes with a camera (open: a video chat).
    var v: Int?
    /// The node's clock, seconds.
    var at: Double
    /// The seat that holds the room's control -- its owner, who created it.
    var o: String?
    /// The seats an invitation is for.
    var to: [String]?
    /// The seat the event is about when it is not the speaker's own (an out said for a seat that vanished without a word).
    var w: String?
    /// The speaker's own room key (ML-KEM-768 public, base64): every pair word to the speaker is sealed to it. Rides open, ask, in --
    /// on the group's road, which proves whose word it is.
    var q: String?
    /// The seats in the room (here): a phone that came to the group late learns who is in.
    var p: [String]? = nil
}

/// A group's room as this phone knows it from the group's words. Kept sealed on this device (MTGroupRoom.bookKey) so a run that
/// comes back after the app was closed still shows the room and holds its people's keys.
struct MTRoomSeen: Equatable, Codable {
    var id: String
    var kind: MTRoomKind
    var key: Data
    var owner: String
    var video: Bool
    /// Every seat in the room and the moment it came in.
    var people: [String: Double]
    /// The room's first moment known here: of two rooms of one group the earlier stands.
    var since: Double
    var at: Double
    /// The seat that invited this phone, when one did.
    var askedBy: String?
    /// Every seat's room key, as its own word on the group's road named it.
    var keys: [String: Data] = [:]
}

/// One pair word on the pair's lane. Its content (the description, the candidates) is sealed to the receiver's room key: the room's
/// own key, which every person of the group may hold, opens the lane and nothing in it.
struct MTRoomSignal: Codable {
    var r: String
    var f: String
    var t: String
    /// offer, answer, ice, bye
    var c: String
    var g: Int
    /// The ML-KEM-768 ciphertext to the receiver's room key, base64.
    var ct: String? = nil
    /// The content under the key it carries (AES-256-GCM), base64.
    var x: String? = nil
    var at: Double
}
/// The content of a pair word.
struct MTRoomInner: Codable {
    var sdp: String? = nil
    var ice: [MTRoomICE]? = nil
}

/// A PAIR WORD IS SEALED TO ITS RECEIVER (07.10): each person in a room holds a room key of its own (ML-KEM-768, born when it comes
/// in, gone when it leaves), named to the group on the group's road; every word of a pair is sealed to the receiver's key alone. A
/// person of the group who holds the room's key but is not one of the two reads none of it -- not the description, not the
/// candidates, not the ICE password without which no third side can stand between the two. [I-1]: ML-KEM-768 and SHA-256; the
/// content key is AES-256-GCM, as the call's frames are.
enum MTRoomSeal {
    static let pubSize = Int(MT_MLKEM_PUBKEY_SIZE)
    static func keypair() -> (pub: Data, sec: Data)? {
        let seed = montanaRandom(Int(MT_MLKEM_SEED_LEN))
        var pk = [UInt8](repeating: 0, count: Int(MT_MLKEM_PUBKEY_SIZE))
        var sk = [UInt8](repeating: 0, count: Int(MT_MLKEM_SECKEY_SIZE))
        let rc = seed.withUnsafeBytes { sb in mt_mlkem_keypair_from_seed(sb.bindMemory(to: UInt8.self).baseAddress, &pk, &sk) }
        return rc == 0 ? (Data(pk), Data(sk)) : nil
    }
    static func seal(_ plain: Data, to pub: Data, bind: Data) -> (ct: Data, box: Data)? {
        guard pub.count == pubSize else { return nil }
        var ct = [UInt8](repeating: 0, count: Int(MT_MLKEM_CT_SIZE))
        var ss = [UInt8](repeating: 0, count: Int(MT_MLKEM_SS_SIZE))
        let rc = pub.withUnsafeBytes { pb in mt_mlkem_encaps(pb.bindMemory(to: UInt8.self).baseAddress, &ct, &ss) }
        guard rc == 0, let box = try? AES.GCM.seal(plain, using: key(Data(ss), bind)).combined else { return nil }
        return (Data(ct), box)
    }
    static func open(_ box: Data, ct: Data, sec: Data, bind: Data) -> Data? {
        guard ct.count == Int(MT_MLKEM_CT_SIZE), sec.count == Int(MT_MLKEM_SECKEY_SIZE) else { return nil }
        var ss = [UInt8](repeating: 0, count: Int(MT_MLKEM_SS_SIZE))
        let rc = sec.withUnsafeBytes { kb in ct.withUnsafeBytes { cb in
            mt_mlkem_decaps(kb.bindMemory(to: UInt8.self).baseAddress, cb.bindMemory(to: UInt8.self).baseAddress, &ss)
        } }
        guard rc == 0, let sealed = try? AES.GCM.SealedBox(combined: box) else { return nil }
        return try? AES.GCM.open(sealed, using: key(Data(ss), bind))
    }
    /// The content key: the shared secret bound to the room, the two seats, the word's kind and generation -- a word sealed for one
    /// pair, one direction, one moment of the pair opens nowhere else.
    private static func key(_ ss: Data, _ bind: Data) -> SymmetricKey {
        var d = Data("mt-room-word".utf8)
        d.append(ss); d.append(bind)
        return SymmetricKey(data: SHA256.hash(data: d))
    }
}
struct MTRoomICE: Codable { var s: String; var i: Int32; var m: String? }

/// One person of a group who may be invited into its room.
struct MTRoomPerson: Identifiable, Equatable {
    let seat: String
    let name: String
    var id: String { seat }
}

/// One face on the room's screen.
struct MTRoomTile: Identifiable, Equatable {
    var id: String { seat }
    let seat: String
    var name: String
    var me: Bool
    var camera: Bool
    var screen: Bool
    var muted: Bool
    var speaking: Bool
    var linked: Bool
    var owner: Bool
}

/// A group's live room as the bar over its chat shows it.
struct MTRoomBrief: Equatable {
    var kind: MTRoomKind
    var video: Bool
    var count: Int
    var asker: String?
    var mine: Bool
}

/// THE GROUPS' LIVING ROOMS, as the chats list, the chat's top and its bar show them: a book of its own that changes only when a
/// room does -- the list's rows never redraw at the room's every beat. Written by the room alone, on the main thread.
final class MTRoomBook: ObservableObject {
    static let shared = MTRoomBook()
    /// Every group's live room by the group's id.
    @Published var rooms: [String: MTRoomBrief] = [:]
}

/// What the room's screen shows: one model, written by the room alone, on the main thread.
final class MTRoomModel: ObservableObject {
    static let shared = MTRoomModel()
    @Published var inRoom = false
    @Published var shown = false
    /// The feed key of the group whose room this phone is in.
    @Published var chat = ""
    /// How many are in the room (a stream's watchers among them).
    @Published var count = 0
    @Published var title = ""
    @Published var kind: MTRoomKind = .call
    @Published var tiles: [MTRoomTile] = []
    @Published var muted = false
    @Published var camera = false
    @Published var screen = false
    @Published var speaker = true
    @Published var front = true
    @Published var focus: String?
    @Published var note: String?
    /// This phone speaks and shows in the room (a chat, or the owner of a stream).
    @Published var speaks = true
    @Published var amOwner = false
    /// The system holds the room (a phone call came in): nothing is said or heard until the person takes it back.
    @Published var held = false
    @Published var tick = 0
}

/// One call of two inside a room: this phone and one seat. WebRTC speaks to it on its own threads; every word goes to the main one.
final class MTRoomPair: NSObject, RTCPeerConnectionDelegate, RTCDataChannelDelegate {
    let seat: String
    let lane: String
    /// The later of the two to come into the room offers; the earlier answers -- two offers never cross.
    let offerer: Bool
    var gen = 0
    var pc: RTCPeerConnection?
    var channel: RTCDataChannel?
    var remoteVideo: RTCVideoTrack?
    var remoteAudio: RTCAudioTrack?
    var linked = false
    var everLinked = false
    var lostAt: Date?
    var bornAt = Date()
    var heldIce: [RTCIceCandidate] = []
    var outIce: [MTRoomICE] = []
    var flushArmed = false
    var camera = false
    var screen = false
    var muted = false
    /// The peer shows my picture large: my lane to them carries the whole picture.
    var wantsMe = false
    var answered = false
    /// The moment the seat came in, as this pair was born for: a seat that comes in again is another pair.
    var moment: Double = 0
    var offers = 0
    var offeredAt = Date.distantPast
    var restarts = 0
    var lastOffer: String?
    var lastAnswer: String?
    /// The transport fingerprint of the connection the offers came from: another one is a connection built anew.
    var remoteFP: String?
    var level: Double = 0
    weak var room: MTGroupRoom?

    init(seat: String, lane: String, offerer: Bool, room: MTGroupRoom) {
        self.seat = seat; self.lane = lane; self.offerer = offerer; self.room = room
        super.init()
    }

    private func main(_ f: @escaping (MTGroupRoom, MTRoomPair) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let r = self.room else { return }
            f(r, self)
        }
    }
    func peerConnection(_ pc: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        let c = MTRoomICE(s: candidate.sdp, i: candidate.sdpMLineIndex, m: candidate.sdpMid)
        main { r, p in r.pairCandidate(p, pc: pc, c) }
    }
    func peerConnection(_ pc: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        main { r, p in r.pairState(p, pc: pc, newState) }
    }
    func peerConnection(_ pc: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams: [RTCMediaStream]) {
        let track = rtpReceiver.track
        main { r, p in r.pairTrack(p, pc: pc, track) }
    }
    func peerConnection(_ pc: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        main { r, p in
            guard pc === p.pc else { return }
            p.channel = dataChannel
            dataChannel.delegate = p
        }
    }
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        let open = dataChannel.readyState == .open
        main { r, p in if open, dataChannel === p.channel { r.tellState(to: p) } }
    }
    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        let d = buffer.data
        main { r, p in if dataChannel === p.channel { r.pairWord(p, d) } }
    }
    func peerConnectionShouldNegotiate(_ pc: RTCPeerConnection) {}
    func peerConnection(_ pc: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ pc: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ pc: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnection(_ pc: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    func peerConnection(_ pc: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
}

/// The room this phone is in.
final class MTRoomLive {
    let group: String
    let chat: String
    let id: String
    let kind: MTRoomKind
    let key: Data
    let me: String
    let since: Double
    var owner: String
    var people: [String: Double]
    var pairs: [String: MTRoomPair] = [:]
    let uuid = UUID()
    var audio: RTCAudioTrack?
    var source: RTCVideoSource?
    var video: RTCVideoTrack?
    var camera: MontanaCamera?
    var cameraOn = false
    var front = true
    var muted = false
    var held = false
    /// The app is in the background: the camera rests and the pairs hear it.
    var away = false
    var screen = false
    var screenSource: RTCVideoSource?
    var screenTrack: RTCVideoTrack?
    var cameraBeforeScreen = false
    var myLevel: Double = 0
    var saidHere = Date()
    /// The generation each seat's next pair starts at: a pair built anew says a higher one than the pair that fell.
    var genFloor: [String: Int] = [:]
    /// Since when each seat has had no standing pair of ours.
    var unlinked: [String: Date] = [:]
    /// Everyone else fell silent and this phone said once more that it is here.
    var wasAlone = false
    /// The comings in already handed my key (seat and moment): each is handed once.
    var keyed = Set<String>()
    /// This phone's room key (MTRoomSeal), born with the room in hand and gone with it.
    var kemPub = Data()
    var kemSec = Data()
    /// Every other seat's room key, from its own word on the group's road.
    var keys: [String: Data] = [:]
    var reannounced: Set<String> = []

    init(group: String, chat: String, id: String, kind: MTRoomKind, key: Data, me: String, since: Double, owner: String,
         people: [String: Double]) {
        self.group = group; self.chat = chat; self.id = id; self.kind = kind; self.key = key; self.me = me; self.since = since
        self.owner = owner; self.people = people
    }
    /// Who speaks and shows: everyone in a chat; in a stream its owner alone.
    func stage(_ seat: String) -> Bool { kind == .call || seat == owner }
}

/// THE ONE OWNER OF ROOMS ON THIS PHONE: what each group's room is, the room this phone is in, its pairs, its sound and picture.
/// Read and written on the main thread; WebRTC and the node hand their words over to it there.
final class MTGroupRoom: NSObject, CXProviderDelegate {
    static let shared = MTGroupRoom()
    /// [I-14] The most people in one room at once (the author's word 07.10.2026 00:2x MSK: "up to 13 connected at once").
    static let capacity = 13
    /// A room no word renewed for this long is gone from the bars: its people may have left without a word. A living room says so
    /// every ten minutes (here), so half an hour of silence is a room that died with nobody left to close it.
    static let staleAfter: Double = 30 * 60
    /// How often a living room's first one says it lives.
    static let hereEvery: TimeInterval = 600
    /// A pair word older than this is a corpse (the node keeps a lane's word sixty seconds).
    static let signalLife: Double = 60
    /// A pair that stood and fell is waited for this long before its seat leaves the room.
    static let lostAfter: TimeInterval = 30
    /// A pair that never stood is given this long.
    static let birthAfter: TimeInterval = 60
    /// A seat no pair of ours has stood with for this long has left the room: a pair that falls is built anew until then (rebirth).
    static let goneAfter: TimeInterval = 180
    /// The level a voice is heard as speaking at.
    static let speakingLevel = 0.04

    private static let liveLock = NSLock()
    private static var _live = false
    /// A room this phone is in holds the sound as a call does: MontanaCall.isBusy reads it from any thread.
    static var isLive: Bool { liveLock.lock(); defer { liveLock.unlock() }; return _live }
    private static func setLive(_ on: Bool) { liveLock.lock(); _live = on; liveLock.unlock() }

    private var seen: [String: MTRoomSeen] = [:]
    /// The invitations already shown (room and asker): a repeat rings nothing.
    private var asked = Set<String>()
    /// [I-15] When each asker last rang this phone: one person's invitations ring once in two minutes, however many rooms they open.
    private var rangBy: [String: Double] = [:]
    static let askerPause: Double = 120
    private(set) var live: MTRoomLive?
    private let provider: CXProvider
    private let controller = CXCallController()
    private var observers: [NSObjectProtocol] = []
    private let shareLock = NSLock()
    private var shareSource: RTCVideoSource?
    private var shareShape = (w: 0, h: 0)
    private let sharePusher = RTCVideoCapturer()

    private override init() {
        let cfg = CXProviderConfiguration()
        cfg.supportsVideo = true
        cfg.maximumCallGroups = 1
        cfg.maximumCallsPerCallGroup = 1
        cfg.supportedHandleTypes = [.generic]
        // A group's room never enters the system's Recents: the journal outlives the room and would link who met whom.
        cfg.includesCallsInRecents = false
        cfg.iconTemplateImageData = MontanaCall.appGlyphTemplate()
        provider = CXProvider(configuration: cfg)
        super.init()
        provider.setDelegate(self, queue: nil)
        lift()
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: .montanaSeedForgotten, object: nil, queue: .main) { [weak self] _ in
            self?.seen = [:]   // another person's rooms are not this one's
            self?.publish()
        })
        observers.append(nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.away(true)
        })
        observers.append(nc.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.away(false)
        })
    }

    // -- names and keys -------------------------------------------------------------------------

    static func isRoomId(_ s: String) -> Bool { s.count == 32 && s.allSatisfy { $0.isHexDigit && !$0.isUppercase } }
    static func isSeat(_ s: String) -> Bool { !s.isEmpty && s.count <= 128 && s.allSatisfy { $0.isLetter || $0.isNumber } }
    /// The pair's lane: named by the room and the two seats, the lower first -- both phones name it alike.
    static func laneName(_ id: String, _ a: String, _ b: String) -> String {
        "room:" + id + ":" + min(a, b) + ":" + max(a, b)
    }
    /// The pair's key: the room's key and the two seats -- only the two, and the room's people, can open their lane.
    static func laneKey(_ key: Data, _ a: String, _ b: String) -> Data {
        var d = Data("mt-room-pair".utf8)
        d.append(key); d.append(Data(min(a, b).utf8)); d.append(0); d.append(Data(max(a, b).utf8))
        return Data(SHA256.hash(data: d))
    }
    /// The later of two to come in: the moment first, the seat for a tie -- the one order every phone computes alike.
    static func later(_ a: (Double, String), than b: (Double, String)) -> Bool { a.0 != b.0 ? a.0 > b.0 : a.1 > b.1 }
    /// The first in the room: it says what a seat that vanished cannot say, and holds the control when the owner goes.
    static func firstIn(_ people: [String: Double]) -> String {
        people.min { a, b in later((b.value, b.key), than: (a.value, a.key)) }?.key ?? ""
    }
    private static func hex(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }
    private func fresh(_ s: MTRoomSeen) -> Bool { MontanaWakePush.nodeNow() - s.at < Self.staleAfter }

    /// The name a seat is shown by in its group's room.
    func name(_ seat: String, in group: String) -> String {
        if let r = live, r.group == group, seat == r.me { return String(localized: "You", bundle: MTLanguage.bundle) }
        return MTGroup.shared.speakerName(MTGroup.speaker(group, seat))
    }

    // -- what a chat offers ---------------------------------------------------------------------

    /// The rooms a phone may open in a chat: a group -- a chat and a stream; a channel -- a stream, by its voices alone.
    func kinds(for chat: String) -> [MTRoomKind] {
        guard let g = MTGroup.shared.state(chat), g.left != true else { return [] }
        if g.kind == .group { return [.call, .live] }
        return MTGroup.shared.canWrite(chat) ? [.live] : []
    }
    /// The people of the chat this phone may invite: every seat it knows by name, but its own and those already in the room.
    func invitable(_ chat: String) -> [MTRoomPerson] {
        guard let g = MTGroup.shared.state(chat) else { return [] }
        let inside = live.map { Set($0.people.keys) } ?? []
        var out = MTGroup.shared.shownSeats(chat)
        // a member of a group carried by its owner knows the others by the names their own letters gave
        if !g.mine {
            for (seat, n) in g.names where seat != MTGroup.ownerSeat && !out.contains(where: { $0.seat == seat }) { out.append((seat, n)) }
        }
        return out.filter { $0.seat != g.me && !inside.contains($0.seat) }
            .map { MTRoomPerson(seat: $0.seat, name: $0.name) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // -- the room's road through the group -----------------------------------------------------

    private func tell(_ e: MTRoomEvent, in chat: String) {
        guard let d = try? JSONEncoder().encode(e), let text = String(data: d, encoding: .utf8) else { return }
        // an invitation goes to the seats it names alone and rings there; a key handed to one who came in goes to them alone, silent
        let targeted = e.e == "ask" || e.e == "key"
        let ask = targeted ? e.to : nil
        let ring = e.e == "ask"
        MainActor.assumeIsolated { MTGroup.shared.room(text, in: chat, ask: ask, ring: ring) }
    }

    /// A ROOM'S WORD FROM THE GROUP (MTGroup "room"): its seat is already proven by the group's road.
    func heard(_ text: String, group gid: String, chat: String, seat: String, name: String?, copy: String = "") {
        guard let d = text.data(using: .utf8), let e = try? JSONDecoder().decode(MTRoomEvent.self, from: d),
              Self.isRoomId(e.r), let kind = MTRoomKind(rawValue: e.m), let g = MTGroup.shared.state(chat) else {
            MontanaTrace.mark("room_refused", "unreadable seat=\(String(seat.prefix(8)))")
            return
        }
        let now = MontanaWakePush.nodeNow()
        guard now - e.at < Self.staleAfter else { return }
        let key = e.k.flatMap { Data(base64Encoded: $0) }.flatMap { $0.count == 32 ? $0 : nil }
        var s: MTRoomSeen
        var move = false
        var known = false
        var firstSight = false   // the room was not known here: its row, «X started a voice chat», is laid once
        var closed = false
        if let cur = seen[gid], cur.id == e.r {
            s = cur
            known = true
        } else {
            guard e.e != "out", e.e != "end", let key else { return }   // nothing is known of the room and the word does not bring it
            let born = MTRoomSeen(id: e.r, kind: kind, key: key, owner: e.o ?? seat, video: e.v == 1, people: [:], since: e.at,
                                  at: e.at, askedBy: nil)
            if let cur = seen[gid], !cur.people.isEmpty, fresh(cur) {
                // TWO ROOMS OF ONE GROUP (opened at once): the earlier stands -- by its moment, by its id for a tie -- on every phone.
                let curFirst = cur.since != born.since ? cur.since < born.since : cur.id < born.id
                if curFirst {
                    if let r = live, r.id == cur.id, !r.reannounced.contains(e.r) {
                        r.reannounced.insert(e.r)
                        tell(MTRoomEvent(r: r.id, e: "in", m: r.kind.rawValue, k: r.key.base64EncodedString(), at: r.since, o: r.owner,
                                         q: r.kemPub.base64EncodedString()), in: r.chat)
                    }
                    return
                }
                move = live?.id == cur.id
            }
            s = born
            firstSight = true
        }
        let who = e.w ?? seat
        // the speaker's room key, from its own word on the group's road: every pair word to it is sealed to this key
        if e.e != "out", e.e != "end", let q = e.q.flatMap({ Data(base64Encoded: $0) }), q.count == MTRoomSeal.pubSize { s.keys[seat] = q }
        switch e.e {
        case "open":
            // a room is opened once, by its owner: an open for a room known here from another seat takes nothing over
            guard !known || seat == s.owner else { MontanaTrace.mark("room_refused", "a second open from another seat"); return }
            s.people[seat] = e.at
            s.owner = e.o ?? seat
            s.video = e.v == 1
        case "ask":
            if s.people[seat] == nil { s.people[seat] = e.at }
            // an invitation is a word of its moment: a late one, or the same asker's repeat, rings nothing
            let once = e.r + "/" + seat
            let quiet = now - (rangBy[gid + "/" + seat] ?? 0) < Self.askerPause
            if e.to?.contains(g.me) == true, live?.id != s.id, now - e.at < 120, !asked.contains(once), !quiet {
                asked.insert(once)
                rangBy[gid + "/" + seat] = now
                s.askedBy = seat
                let asker = name.flatMap { $0.isEmpty ? nil : $0 } ?? self.name(seat, in: gid)
                let body: String
                switch (s.kind, e.v == 1) {
                case (.live, _): body = String(localized: "\(asker) invites you to a live stream", bundle: MTLanguage.bundle)
                case (.call, true): body = String(localized: "\(asker) invites you to a video chat", bundle: MTLanguage.bundle)
                case (.call, false): body = String(localized: "\(asker) invites you to a voice chat", bundle: MTLanguage.bundle)
                }
                // the copy's own name: a banner the notification extension already showed for it is not shown again
                let shown = copy.isEmpty ? "room-" + e.r : copy
                MainActor.assumeIsolated { MontanaNotify.presentGroup(title: g.title, body: body, chat: chat, copy: shown) }
            }
        case "in":
            s.people[who] = e.at
        case "key":
            if s.people[seat] == nil { s.people[seat] = e.at }
        case "here":
            if s.people[seat] == nil { s.people[seat] = e.at }
            for x in (e.p ?? []).prefix(Self.capacity) where Self.isSeat(x) && s.people[x] == nil { s.people[x] = e.at }
        case "out":
            s.people.removeValue(forKey: who)
        case "end":
            guard seat == s.owner || s.people.keys.allSatisfy({ $0 == seat }) else { return }
            s.people.removeAll()
            closed = true
        default:
            return
        }
        if s.people[s.owner] == nil, !s.people.isEmpty { s.owner = Self.firstIn(s.people) }
        s.at = max(s.at, e.at)
        if s.people.isEmpty { seen.removeValue(forKey: gid) } else { seen[gid] = s }
        MontanaTrace.mark("room_rx", "e=\(e.e) people=\(s.people.count) in=\(live?.id == s.id ? 1 : 0)")
        // THE ROOM IN THE GROUP'S FEED (stage R, the reference folder's rows): begun, once; ended, with how long it lived
        let begun = s
        if firstSight, !begun.people.isEmpty {
            MainActor.assumeIsolated { MTGroup.shared.lay(MTGroupEvent(e: "call", g: gid, a: begun.owner, k: begun.kind.rawValue, v: begun.video ? 1 : 0, r: begun.id)) }
        }
        if closed, known {
            MainActor.assumeIsolated { MTGroup.shared.lay(MTGroupEvent(e: "ended", g: gid, a: seat, k: begun.kind.rawValue, v: begun.video ? 1 : 0, d: Int(now - begun.since))) }
        }
        if move {
            leave(why: "the earlier room stands")
            join(chat, video: s.video)
        } else if let r = live, r.id == s.id {
            follow(s, event: e.e, seat: who, by: seat)
        }
        publish()
        // the banner tapped before the room's word landed: the way in opens now
        if let pj = pendingJoin, pj.room == e.r, live == nil, seen[gid] != nil {
            pendingJoin = nil
            if Date().timeIntervalSince(pj.at) < 60 { join(pj.chat, video: false) }
        }
    }

    /// The room this phone is in learns what the group said of it.
    private func follow(_ s: MTRoomSeen, event: String, seat: String, by speaker: String) {
        guard let r = live else { return }
        r.people = s.people
        // a seat with a standing pair of ours is in the room whatever another view says: the living line is the witness
        for (seat, p) in r.pairs where p.linked && r.people[seat] == nil { r.people[seat] = p.moment }
        for (k, v) in s.keys where k != r.me { r.keys[k] = v }
        if r.people[r.me] == nil { r.people[r.me] = r.since }   // a view that lost me does not take me out
        if r.people[r.owner] == nil { r.owner = Self.firstIn(r.people) }
        switch event {
        case "in", "open", "ask", "here", "key":
            guard seat != r.me else { break }
            // a seat that came in again is another pair: the old one goes, the new one is born
            if let p = r.pairs[seat], let m = r.people[seat], p.moment != m {
                drop(seat, why: "came in again")
                r.genFloor.removeValue(forKey: seat)   // its new run counts its connections from the start
            }
            let fresh = r.pairs[seat] == nil
            pairUp(seat)
            // ONE WHO CAME IN GETS MY KEY FROM ME (07.10): a person added to the group while the room lived never heard the words
            // that named the keys of those already in, and could seal an offer to nobody -- each of us hands ours, to them alone;
            // and one who says it is here again after our pair fell hears from us too, so the pair it owes is built
            if event == "in", let m = r.people[seat], fresh || !r.keyed.contains(seat + "/" + String(m)) {
                r.keyed.insert(seat + "/" + String(m))
                tell(MTRoomEvent(r: r.id, e: "key", m: r.kind.rawValue, k: r.key.base64EncodedString(), at: r.since, o: r.owner,
                                 to: [seat], q: r.kemPub.base64EncodedString()), in: r.chat)
            }
        case "out":
            // a seat takes itself out; another's word about it is believed only while no pair of ours stands with it
            guard seat != r.me else { break }
            if speaker != seat, let p = r.pairs[seat], p.linked { r.people[seat] = p.moment; break }
            drop(seat, why: "out")
        case "end":
            leave(why: "ended", tellGroup: false)
            say("The call has ended")
            return
        default:
            break
        }
        // THE ROOM GREW PAST ITS MEASURE (two came in at once): the latest by the one order leave, every phone alike.
        let order = r.people.sorted { a, b in Self.later((b.value, b.key), than: (a.value, a.key)) }.map(\.key)
        if let i = order.firstIndex(of: r.me), i >= Self.capacity {
            leave(why: "full")
            say("This call is full")
            return
        }
        refresh()
    }

    /// THE BOOK OF ROOMS IS KEPT, SEALED, ON THIS DEVICE (MontanaLocalVault, the device's key): the rooms this phone knows and their
    /// people's room keys -- this device's own, never a copy's (SeedScope.deviceKeys). A room older than its measure is not lifted.
    static let bookKey = "mt.rooms.seen"
    private func lift() {
        guard let d = MontanaLocalVault.getDecrypted(Self.bookKey),
              let book = try? JSONDecoder().decode([String: MTRoomSeen].self, from: d) else { return }
        seen = book.filter { fresh($0.value) && !$0.value.people.isEmpty }
        publish()
    }
    private func keep() {
        guard let d = try? JSONEncoder().encode(seen) else { return }
        MontanaLocalVault.setEncrypted(Self.bookKey, d)
    }

    /// Every group's room as the bars over the chats show it.
    private func publish() {
        var out: [String: MTRoomBrief] = [:]
        for (gid, s) in seen where !s.people.isEmpty && fresh(s) {
            out[gid] = MTRoomBrief(kind: s.kind, video: s.video, count: s.people.count, asker: s.askedBy.map { name($0, in: gid) },
                                   mine: live?.id == s.id)
        }
        let b = MTRoomBook.shared
        if b.rooms != out { b.rooms = out }
        keep()
    }

    // -- coming in and going out ----------------------------------------------------------------

    /// A ROOM IS OPENED (the chat's phone mark: the kind, then the people chosen). This phone is in it at once; the group hears it
    /// opened and the chosen hear they are invited -- a way in, never a ring. A room living in the group is joined instead: one
    /// room per group.
    func open(_ kind: MTRoomKind, video: Bool, in chat: String, invite seats: [String]) {
        guard let g = MTGroup.shared.state(chat), kinds(for: chat).contains(kind) else { return }
        if let s = seen[g.id], !s.people.isEmpty, fresh(s) {
            join(chat, video: video)
            invite(seats)
            return
        }
        guard admit() else { return }
        guard let kp = MTRoomSeal.keypair() else { say("The call could not start"); return }
        let id = Self.hex(Data(montanaRandom(16))), key = Data(montanaRandom(32))
        let now = MontanaWakePush.nodeNow()
        let s = MTRoomSeen(id: id, kind: kind, key: key, owner: g.me, video: video, people: [g.me: now], since: now, at: now, askedBy: nil,
                           keys: [g.me: kp.pub])
        seen[g.id] = s
        enter(s, group: g, chat: chat, video: video, kp: kp)
        tell(MTRoomEvent(r: id, e: "open", m: kind.rawValue, k: key.base64EncodedString(), v: video ? 1 : 0, at: now, o: g.me,
                         q: kp.pub.base64EncodedString()), in: chat)
        MainActor.assumeIsolated { MTGroup.shared.lay(MTGroupEvent(e: "call", g: g.id, a: g.me, k: kind.rawValue, v: video ? 1 : 0, r: id)) }
        invite(seats)
    }

    /// THIS PHONE COMES INTO THE GROUP'S ROOM (the bar over the chat, an invitation): it calls everyone already in, being later.
    func join(_ chat: String, video: Bool) {
        guard let g = MTGroup.shared.state(chat), g.left != true, let s = seen[g.id], fresh(s) else {
            say("The call has ended")
            return
        }
        if let r = live, r.id == s.id { show(true); return }
        guard s.people.count < Self.capacity else { say("This call is full"); return }
        guard admit() else { return }
        guard let kp = MTRoomSeal.keypair() else { say("The call could not start"); return }
        let now = MontanaWakePush.nodeNow()
        var s2 = s
        s2.people[g.me] = now; s2.at = now; s2.askedBy = nil; s2.keys[g.me] = kp.pub
        seen[g.id] = s2
        enter(s2, group: g, chat: chat, video: video && s.kind == .call, kp: kp)
        tell(MTRoomEvent(r: s.id, e: "in", m: s.kind.rawValue, k: s.key.base64EncodedString(), v: video ? 1 : 0, at: now, o: s.owner,
                         q: kp.pub.base64EncodedString()), in: chat)
        for seat in s.people.keys where seat != g.me { pairUp(seat) }
    }

    /// Who may come in now: no call of two in hand (the system holds one call of ours at a time); another room is left first.
    private func admit() -> Bool {
        if MontanaCall.stateSnapshot != "idle" { say("Finish the current call first"); return false }
        if live != nil { leave(why: "another room") }
        return true
    }

    private func enter(_ s: MTRoomSeen, group g: MTGroupState, chat: String, video: Bool, kp: (pub: Data, sec: Data)) {
        let r = MTRoomLive(group: g.id, chat: chat, id: s.id, kind: s.kind, key: s.key, me: g.me,
                           since: s.people[g.me] ?? MontanaWakePush.nodeNow(), owner: s.owner, people: s.people)
        r.kemPub = kp.pub
        r.kemSec = kp.sec
        r.keys = s.keys.filter { $0.key != g.me }
        live = r
        Self.setLive(true)
        let f = MontanaCall.shared.factory
        if r.stage(r.me) {
            r.audio = f.audioTrack(with: f.audioSource(with: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)),
                                   trackId: "room_a")
            askMicrophone()
        }
        let m = MTRoomModel.shared
        m.inRoom = true; m.shown = true; m.chat = chat; m.title = g.title; m.kind = r.kind; m.focus = nil; m.note = nil
        m.muted = false; m.camera = false; m.screen = false; m.speaker = true; m.front = true; m.held = false
        m.speaks = r.stage(r.me); m.amOwner = r.owner == r.me
        startSystemCall(r, video: video)
        if video, r.stage(r.me) { cameraOn(true) }
        armScreen()
        beatLater(r)
        publish()
        refresh()
        MTRoomWindow.shared.update()
        MontanaTrace.mark("room", "enter kind=\(r.kind.rawValue) people=\(r.people.count) owner=\(r.owner == r.me ? 1 : 0)")
    }

    private func askMicrophone() {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return
        case .denied:
            setMuted(true, tellSystem: false)
            say("Microphone access is off")
        default:
            AVAudioApplication.requestRecordPermission { ok in
                DispatchQueue.main.async {
                    guard !ok, self.live != nil else { return }
                    self.setMuted(true, tellSystem: false)
                    self.say("Microphone access is off")
                }
            }
        }
    }

    /// THIS PHONE LEAVES THE ROOM: every pair hears its bye, the group hears it went out -- the last one out closes the room.
    func leave(why: String, tellGroup: Bool = true, systemEnded: Bool = false) {
        guard let r = live else { return }
        live = nil
        Self.setLive(false)
        let streamEnds = r.kind == .live && r.owner == r.me
        for p in r.pairs.values { command(p, streamEnds ? "end" : "bye"); send(p, r, "bye"); close(p) }   // the channel's word is the proven one
        r.pairs.removeAll()
        stopCamera(r)
        if r.screen { MTScreenShare.shared.dropPeer() }
        shareLock.lock(); shareSource = nil; shareLock.unlock()
        if MontanaCall.stateSnapshot == "idle" { MTScreenShare.shared.disarm() }
        let now = MontanaWakePush.nodeNow()
        let others = r.people.keys.filter { $0 != r.me }
        // A STREAM ENDS WITH ITS OWNER: the watchers hold no voice and no line to each other, so a stream whose owner goes is over
        // for everyone -- said, not left to die in silence under a bar that still shows it.
        let ends = others.isEmpty || (r.kind == .live && r.owner == r.me)
        if tellGroup, ends { ended(r) }   // the last one out, or a stream's owner: the room's end stands in the feed
        if tellGroup {
            tell(MTRoomEvent(r: r.id, e: ends ? "end" : "out", m: r.kind.rawValue, at: now, o: r.owner), in: r.chat)
        }
        if var s = seen[r.group], s.id == r.id {
            s.people.removeValue(forKey: r.me)
            if ends { seen.removeValue(forKey: r.group) } else { s.at = now; seen[r.group] = s }
        }
        if !systemEnded { controller.request(CXTransaction(action: CXEndCallAction(call: r.uuid))) { _ in } }
        let m = MTRoomModel.shared
        m.inRoom = false; m.shown = false; m.tiles = []; m.focus = nil; m.screen = false; m.camera = false; m.muted = false
        publish()
        MTRoomWindow.shared.update()
        MontanaTrace.mark("room", "left why=\(why) others=\(others.count)")
    }

    /// A TAP ON A ROOM'S INVITATION (its banner): the way in -- at once when the room is known here, else the moment a word of it
    /// lands (a cold start from the banner reads the group's words after the tap); a minute later the tap is forgotten.
    private var pendingJoin: (chat: String, room: String, at: Date)?
    func joinFromBanner(_ chat: String, room: String) {
        if let gid = MTGroup.id(of: chat), seen[gid]?.id == room, live?.id != room { join(chat, video: false); return }
        if live?.id == room { show(true); return }
        pendingJoin = (chat, room, Date())
    }

    /// THE ONE ANSWER TO A TAP ON A GROUP'S CALL (the chat's top, the group's page): a living room is the way in, or back when this
    /// phone is in it; with none living, the person chooses whom to invite (ask) -- the kind and the camera as the tap named them.
    func tapped(_ chat: String, kind: MTRoomKind, video: Bool, ask: (MTRoomKind, Bool) -> Void) {
        if let gid = MTGroup.id(of: chat), let b = MTRoomBook.shared.rooms[gid] {
            if b.mine { show(true) } else { join(chat, video: video && b.kind == .call) }
            return
        }
        ask(kind, video)
    }

    /// THE GROUP WENT FROM THIS PHONE (left by its hand, taken out by its owner, no longer named by the organisation): the room goes
    /// with it -- a person outside a group is in none of its rooms.
    func groupGone(_ gid: String) {
        if let r = live, r.group == gid { leave(why: "the group went") }
        seen.removeValue(forKey: gid)
        publish()
    }

    /// The room's end in its group's feed: how long it lived, from its first moment known here.
    private func ended(_ r: MTRoomLive) {
        let began = seen[r.group].flatMap { $0.id == r.id ? $0.since : nil } ?? r.since
        let video = seen[r.group]?.video == true
        MainActor.assumeIsolated {
            MTGroup.shared.lay(MTGroupEvent(e: "ended", g: r.group, a: r.me, k: r.kind.rawValue, v: video ? 1 : 0,
                                            d: Int(MontanaWakePush.nodeNow() - began)))
        }
    }

    /// The owner closes the room for everyone in it.
    func endForEveryone() {
        guard let r = live, r.owner == r.me else { return }
        for p in r.pairs.values { command(p, "end") }
        tell(MTRoomEvent(r: r.id, e: "end", m: r.kind.rawValue, at: MontanaWakePush.nodeNow(), o: r.owner), in: r.chat)
        ended(r)
        let gid = r.group
        leave(why: "ended for everyone", tellGroup: false)
        seen.removeValue(forKey: gid)
        publish()
    }

    /// AN INVITATION: the seats chosen hear the room's way in -- a banner and the bar over their chat, never a ring.
    func invite(_ seats: [String]) {
        guard let r = live, !seats.isEmpty else { return }
        // a word of the group holds 4096 bytes (MTGroup.room): the seats ride in portions of sixteen -- an organisation's seat is
        // 64 letters, and two hundred of them in one word would be dropped whole
        let all = Array(Set(seats).filter(Self.isSeat).prefix(200))
        for start in stride(from: 0, to: all.count, by: 16) {
            let part = Array(all[start..<min(start + 16, all.count)])
            tell(MTRoomEvent(r: r.id, e: "ask", m: r.kind.rawValue, k: r.key.base64EncodedString(), v: r.cameraOn ? 1 : 0,
                             at: MontanaWakePush.nodeNow(), o: r.owner, to: part, q: r.kemPub.base64EncodedString()), in: r.chat)
        }
        say("Invitation sent")
    }

    /// The owner asks one seat to fall silent.
    func ownerMute(_ seat: String) {
        guard let r = live, r.owner == r.me, let p = r.pairs[seat] else { return }
        command(p, "mute")
    }
    /// The owner takes one seat out of the room.
    func ownerDrop(_ seat: String) {
        guard let r = live, r.owner == r.me, let p = r.pairs[seat] else { return }
        command(p, "drop")
        tell(MTRoomEvent(r: r.id, e: "out", m: r.kind.rawValue, at: MontanaWakePush.nodeNow(), o: r.owner, w: seat), in: r.chat)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.vanish(seat, tellGroup: false) }
    }

    // -- the pairs ------------------------------------------------------------------------------

    /// A pair with one seat: born once, its lane opened; the later of the two offers. In a stream the watchers do not call each
    /// other -- everyone calls its owner.
    private func pairUp(_ seat: String) {
        guard let r = live, seat != r.me, r.pairs[seat] == nil, Self.isSeat(seat), r.stage(seat) || r.stage(r.me) else { return }
        let mine = (r.people[r.me] ?? r.since, r.me), theirs = (r.people[seat] ?? 0, seat)
        let p = MTRoomPair(seat: seat, lane: Self.laneName(r.id, r.me, seat), offerer: Self.later(mine, than: theirs), room: self)
        p.moment = r.people[seat] ?? 0
        p.gen = r.genFloor[seat] ?? 0
        if r.unlinked[seat] == nil { r.unlinked[seat] = Date() }
        r.pairs[seat] = p
        MontanaWakePush.openRoomLane(p.lane, secret: Self.laneKey(r.key, r.me, seat))
        if p.offerer { offer(p) }
        refresh()
    }

    /// The pair's connection, built once on the call's own relay pass (MontanaCall.rtcConfig) and the one factory.
    private func build(_ p: MTRoomPair, then go: @escaping () -> Void) {
        if p.pc != nil { go(); return }
        Task {
            let cfg = await MontanaCall.shared.rtcConfig()
            DispatchQueue.main.async {
                guard let r = self.live, r.pairs[p.seat] === p else { return }
                if p.pc == nil {
                    let c = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
                    guard let pc = MontanaCall.shared.factory.peerConnection(with: cfg, constraints: c, delegate: p) else {
                        MontanaTrace.mark("room_pair", "connection refused by the factory")
                        return
                    }
                    p.pc = pc
                }
                go()
            }
        }
    }

    private func offer(_ p: MTRoomPair, restart: Bool = false) {
        build(p) { [weak self] in
            guard let self, let r = self.live, let pc = p.pc else { return }
            if pc.transceivers.isEmpty {
                let ai = RTCRtpTransceiverInit(); ai.direction = .sendRecv; ai.streamIds = ["mt_room"]
                _ = pc.addTransceiver(of: .audio, init: ai)
                let vi = RTCRtpTransceiverInit(); vi.direction = .sendRecv; vi.streamIds = ["mt_room"]
                _ = pc.addTransceiver(of: .video, init: vi)
                let dc = RTCDataChannelConfiguration(); dc.isOrdered = true
                p.channel = pc.dataChannel(forLabel: "room", configuration: dc)
                p.channel?.delegate = p
            }
            self.dress(p, r)
            if restart { p.gen += 1; p.answered = false; p.restarts += 1; p.offers = 0 }
            let c = RTCMediaConstraints(mandatoryConstraints: restart ? ["IceRestart": "true"] : nil, optionalConstraints: nil)
            pc.offer(for: c) { desc, err in
                guard let desc else { MontanaTrace.mark("room_pair", "offer FAIL \(err?.localizedDescription ?? "-")"); return }
                pc.setLocalDescription(desc) { lerr in
                    DispatchQueue.main.async {
                        guard lerr == nil, let r2 = self.live, r2.pairs[p.seat] === p else { return }
                        p.lastOffer = desc.sdp; p.offeredAt = Date(); p.offers += 1
                        self.send(p, r2, "offer", sdp: desc.sdp)
                    }
                }
            }
        }
    }

    private func answer(_ p: MTRoomPair, sdp: String, gen: Int) {
        // A CONNECTION BUILT ANEW BY THE LATER ONE (its pair fell and was born again): another transport fingerprint is another
        // connection -- the old one here is let go before the new one is answered.
        let fp = MontanaCall.fingerprint(sdp)
        if let fp, let old = p.remoteFP, old != fp, p.pc != nil {
            p.channel?.close(); p.channel = nil
            p.pc?.close(); p.pc = nil
            p.remoteVideo = nil; p.remoteAudio = nil
            p.lastAnswer = nil; p.linked = false   // candidates held for the new connection stay held
            MontanaTrace.mark("room_pair", "answered anew: the later one built its connection again")
        }
        // a repeat of an offer already answered: the same answer again -- the first may have died on the way
        if gen == p.gen, let a = p.lastAnswer, let r = live { send(p, r, "answer", sdp: a); return }
        build(p) { [weak self] in
            guard let self, let pc = p.pc else { return }
            pc.setRemoteDescription(RTCSessionDescription(type: .offer, sdp: sdp)) { err in
                DispatchQueue.main.async {
                    guard err == nil, let r = self.live, r.pairs[p.seat] === p else {
                        MontanaTrace.mark("room_pair", "offer not taken \(err?.localizedDescription ?? "-")")
                        return
                    }
                    p.gen = gen
                    p.remoteFP = fp
                    self.flushHeld(p)
                    self.dress(p, r)
                    pc.answer(for: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)) { desc, _ in
                        guard let desc else { return }
                        pc.setLocalDescription(desc) { lerr in
                            DispatchQueue.main.async {
                                guard lerr == nil, let r2 = self.live, r2.pairs[p.seat] === p else { return }
                                p.lastAnswer = desc.sdp
                                self.send(p, r2, "answer", sdp: desc.sdp)
                            }
                        }
                    }
                }
            }
        }
    }

    /// The pair's lines carry what this phone gives: its voice where it speaks, its picture (the camera or the screen) where it shows.
    private func dress(_ p: MTRoomPair, _ r: MTRoomLive) {
        guard let pc = p.pc else { return }
        let speaks = r.stage(r.me)
        let pic = speaks ? picture(r) : nil
        for tr in pc.transceivers {
            if tr.mediaType == .audio {
                let a: RTCMediaStreamTrack? = speaks ? r.audio : nil
                if tr.sender.track !== a { tr.sender.track = a }
                tr.setDirection(speaks ? .sendRecv : .recvOnly, error: nil)
            } else if tr.mediaType == .video {
                if tr.sender.track !== pic { tr.sender.track = pic }
                tr.setDirection(speaks ? .sendRecv : .recvOnly, error: nil)
                preferVP8(tr)
            }
        }
        tune(p, r)
    }
    private func picture(_ r: MTRoomLive) -> RTCVideoTrack? {
        if r.screen { return r.screenTrack }
        return r.cameraOn && !r.away ? r.video : nil
    }
    /// Twelve encoders at once on one phone: the software VP8 first, so the hardware's few sessions are never the limit.
    private func preferVP8(_ tr: RTCRtpTransceiver) {
        let all = MontanaCall.shared.factory.rtpSenderCapabilities(forKind: kRTCMediaStreamTrackKindVideo).codecs
        let vp8 = all.filter { $0.name.uppercased() == "VP8" }
        guard !vp8.isEmpty, tr.codecPreferences.first?.name.uppercased() != "VP8" else { return }
        do { try tr.setCodecPreferences(vp8 + all.filter { $0.name.uppercased() != "VP8" }, error: ()) }   // the import's own shape
        catch { MontanaTrace.mark("room_pair", "codec order refused \(error.localizedDescription)") }
    }
    /// The picture each watcher gets: small in the grid; whole when it shows me large, when we are two, on a stream, or a screen.
    private func tune(_ p: MTRoomPair, _ r: MTRoomLive) {
        guard let pc = p.pc else { return }
        if let v = pc.transceivers.first(where: { $0.mediaType == .video })?.sender {
            let params = v.parameters
            if let enc = params.encodings.first {
                let whole = r.screen || r.kind == .live || p.wantsMe || r.pairs.count <= 1
                enc.maxBitrateBps = NSNumber(value: r.screen ? 1_200_000 : (whole ? 700_000 : 160_000))
                enc.scaleResolutionDownBy = NSNumber(value: whole ? 1.0 : 2.0)
                enc.maxFramerate = NSNumber(value: r.screen ? 15 : (whole ? 24 : 15))
                v.parameters = params
            }
        }
        // the voice is never the victim: the picture gives way first when the channel narrows
        if let a = pc.transceivers.first(where: { $0.mediaType == .audio })?.sender {
            let params = a.parameters
            if let enc = params.encodings.first, enc.networkPriority != .high {
                enc.networkPriority = .high
                enc.bitratePriority = 4
                a.parameters = params
            }
        }
    }

    private func send(_ p: MTRoomPair, _ r: MTRoomLive, _ c: String, sdp: String? = nil, ice: [MTRoomICE]? = nil) {
        var s = MTRoomSignal(r: r.id, f: r.me, t: p.seat, c: c, g: p.gen, at: MontanaWakePush.nodeNow())
        if sdp != nil || ice != nil {
            guard let pub = r.keys[p.seat], let inner = try? JSONEncoder().encode(MTRoomInner(sdp: sdp, ice: ice)),
                  let sealed = MTRoomSeal.seal(inner, to: pub, bind: Self.bind(r.id, r.me, p.seat, c, p.gen)) else {
                MontanaTrace.mark("room_pair", "c=\(c) waits: the seat's room key has not come yet")
                if c == "ice", let ice { p.outIce.insert(contentsOf: ice, at: 0) }   // the candidates wait for the key (beat)
                return
            }
            s.ct = sealed.ct.base64EncodedString()
            s.x = sealed.box.base64EncodedString()
        }
        guard let d = try? JSONEncoder().encode(s) else { return }
        MontanaWakePush.postSignal(p.lane, epoch: "room", payloadB64: d.base64EncodedString())
    }

    /// What a pair word's content is bound to: the room, from whom, to whom, its kind and the pair's generation.
    static func bind(_ id: String, _ from: String, _ to: String, _ c: String, _ g: Int) -> Data {
        Data((id + "/" + from + "/" + to + "/" + c + "/" + String(g)).utf8)
    }

    /// A PAIR WORD FROM THE NODE (MontanaWakePush, epoch room): the lane is the room's, the content is mine alone (MTRoomSeal).
    func laneWord(conv: String, payload: Data) {
        guard let s = try? JSONDecoder().decode(MTRoomSignal.self, from: payload), let r = live, s.r == r.id, s.t == r.me,
              conv == Self.laneName(r.id, r.me, s.f), MontanaWakePush.nodeNow() - s.at < Self.signalLife,
              let p = r.pairs[s.f] else { return }
        var inner = MTRoomInner()
        if let ct = s.ct.flatMap({ Data(base64Encoded: $0) }), let x = s.x.flatMap({ Data(base64Encoded: $0) }) {
            guard let plain = MTRoomSeal.open(x, ct: ct, sec: r.kemSec, bind: Self.bind(r.id, s.f, r.me, s.c, s.g)),
                  let i = try? JSONDecoder().decode(MTRoomInner.self, from: plain) else {
                MontanaTrace.mark("room_refused", "a pair word not sealed to this phone c=\(s.c)")
                return
            }
            inner = i
        }
        switch s.c {
        case "offer":
            guard !p.offerer, let sdp = inner.sdp, s.g >= p.gen else { return }
            answer(p, sdp: MontanaCall.withoutLocalCandidates(sdp), gen: s.g)   // no local network (MontanaCall.onLocalNetwork)
        case "answer":
            guard p.offerer, let sdp = inner.sdp, s.g == p.gen, !p.answered, let pc = p.pc else { return }
            p.answered = true
            pc.setRemoteDescription(RTCSessionDescription(type: .answer, sdp: MontanaCall.withoutLocalCandidates(sdp))) { err in
                DispatchQueue.main.async {
                    if err != nil { p.answered = false; return }
                    self.flushHeld(p)
                }
            }
        case "ice":
            // a candidate of a connection older than the pair's is a corpse; one of a newer connection waits for its offer
            guard s.g >= p.gen else { return }
            for c in inner.ice ?? [] where !MontanaCall.onLocalNetwork(candidate: c.s) {
                let cand = RTCIceCandidate(sdp: c.s, sdpMLineIndex: c.i, sdpMid: c.m)
                if let pc = p.pc, pc.remoteDescription != nil, s.g == p.gen { pc.add(cand) { _ in } } else { p.heldIce.append(cand) }
            }
        case "bye":
            guard !p.linked else { return }   // a standing pair hears its bye on its own channel, never from the lane
            vanish(p.seat, tellGroup: false)
        default:
            break
        }
    }
    private func flushHeld(_ p: MTRoomPair) {
        guard let pc = p.pc, pc.remoteDescription != nil, !p.heldIce.isEmpty else { return }
        for c in p.heldIce { pc.add(c) { _ in } }
        p.heldIce.removeAll()
    }

    func pairCandidate(_ p: MTRoomPair, pc: RTCPeerConnection, _ c: MTRoomICE) {
        guard pc === p.pc, live?.pairs[p.seat] === p else { return }
        p.outIce.append(c)
        guard !p.flushArmed else { return }
        p.flushArmed = true
        // the candidates leave in small bundles: one post for many, the first bundle at once
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            p.flushArmed = false
            guard let self, let r = self.live, r.pairs[p.seat] === p, !p.outIce.isEmpty else { return }
            let batch = p.outIce
            p.outIce = []
            self.send(p, r, "ice", ice: batch)
        }
    }

    func pairState(_ p: MTRoomPair, pc: RTCPeerConnection, _ st: RTCIceConnectionState) {
        guard pc === p.pc, let r = live, r.pairs[p.seat] === p else { return }
        switch st {
        case .connected, .completed:
            p.linked = true; p.everLinked = true; p.lostAt = nil; p.restarts = 0
            r.unlinked.removeValue(forKey: p.seat)
            r.wasAlone = false
            tune(p, r)
            tellState(to: p)
        case .disconnected:
            p.linked = false
            if p.lostAt == nil { p.lostAt = Date() }
        case .failed:
            p.linked = false
            if p.lostAt == nil { p.lostAt = Date() }
            if p.offerer, p.restarts < 3 { offer(p, restart: true) }   // the later of the two asks for fresh paths
        default:
            break
        }
        MontanaTrace.mark("room_pair", "ice=\(st.rawValue) offerer=\(p.offerer ? 1 : 0) pairs=\(r.pairs.count)")
        refresh()
    }

    func pairTrack(_ p: MTRoomPair, pc: RTCPeerConnection, _ track: RTCMediaStreamTrack?) {
        guard pc === p.pc else { return }
        if let v = track as? RTCVideoTrack { p.remoteVideo = v }
        if let a = track as? RTCAudioTrack { p.remoteAudio = a; a.isEnabled = live?.held != true }
        MTRoomModel.shared.tick &+= 1
        refresh()
    }

    /// The pair's own words on its data channel: what each shows, and the owner's control.
    private struct Word: Codable { var c: String; var mu: Int? = nil; var cam: Int? = nil; var scr: Int? = nil; var big: Int? = nil }
    func tellState(to p: MTRoomPair) {
        guard let r = live, let ch = p.channel, ch.readyState == .open else { return }
        let w = Word(c: "st", mu: (r.muted || !r.stage(r.me)) ? 1 : 0, cam: (r.cameraOn && !r.away && !r.screen) ? 1 : 0,
                     scr: r.screen ? 1 : 0, big: MTRoomModel.shared.focus == p.seat ? 1 : 0)
        if let d = try? JSONEncoder().encode(w) { ch.sendData(RTCDataBuffer(data: d, isBinary: false)) }
    }
    private func tellAll() { live?.pairs.values.forEach { tellState(to: $0) } }
    private func command(_ p: MTRoomPair, _ x: String) {
        guard let ch = p.channel, ch.readyState == .open, let d = try? JSONEncoder().encode(Word(c: x)) else { return }
        ch.sendData(RTCDataBuffer(data: d, isBinary: false))
    }
    func pairWord(_ p: MTRoomPair, _ d: Data) {
        guard let r = live, let w = try? JSONDecoder().decode(Word.self, from: d) else { return }
        switch w.c {
        case "st":
            p.muted = w.mu == 1; p.camera = w.cam == 1; p.screen = w.scr == 1
            if (w.big == 1) != p.wantsMe { p.wantsMe = w.big == 1; tune(p, r) }
            MTRoomModel.shared.tick &+= 1
            refresh()
        case "mute" where p.seat == r.owner:
            setMuted(true, tellSystem: true)
            say("The owner muted you")
        case "drop" where p.seat == r.owner:
            leave(why: "taken out by the owner", tellGroup: false)
            say("The owner removed you from the call")
        case "end" where p.seat == r.owner:
            leave(why: "ended by the owner", tellGroup: false)
            say("The call has ended")
        case "bye":
            vanish(p.seat, tellGroup: false)
        default:
            break
        }
    }

    private func close(_ p: MTRoomPair) {
        MontanaWakePush.closeRoomLane(p.lane)
        p.channel?.close(); p.channel = nil
        p.pc?.close(); p.pc = nil
        p.remoteVideo = nil; p.remoteAudio = nil
    }
    private func drop(_ seat: String, why: String) {
        guard let r = live, let p = r.pairs.removeValue(forKey: seat) else { return }
        close(p)
        MontanaTrace.mark("room_pair", "drop why=\(why) pairs=\(r.pairs.count)")
        if MTRoomModel.shared.focus == seat { MTRoomModel.shared.focus = nil }
        refresh()
    }
    /// A PAIR BUILT ANEW BY THE LATER OF THE TWO: a higher generation, another connection; the earlier one answers it anew.
    private func rebirth(_ seat: String) {
        guard let r = live, let p = r.pairs[seat], p.offerer else { return }
        r.genFloor[seat] = p.gen + 1
        if r.unlinked[seat] == nil { r.unlinked[seat] = p.lostAt ?? p.bornAt }
        r.pairs.removeValue(forKey: seat)
        close(p)
        MontanaTrace.mark("room_pair", "rebirth gen=\(p.gen + 1)")
        pairUp(seat)
    }

    /// A SEAT THAT LEFT OR FELL SILENT WITHOUT A WORD: its pair goes, and the first in the room says it went out -- for the bars.
    private func vanish(_ seat: String, tellGroup: Bool = true) {
        guard let r = live else { return }
        drop(seat, why: "vanished")
        guard r.people.removeValue(forKey: seat) != nil else { return }
        if tellGroup, Self.firstIn(r.people) == r.me {
            tell(MTRoomEvent(r: r.id, e: "out", m: r.kind.rawValue, at: MontanaWakePush.nodeNow(), o: r.owner, w: seat), in: r.chat)
        }
        if r.owner == seat { r.owner = Self.firstIn(r.people) }
        r.unlinked.removeValue(forKey: seat)
        r.genFloor.removeValue(forKey: seat)
        if var s = seen[r.group], s.id == r.id { s.people.removeValue(forKey: seat); s.owner = r.owner; seen[r.group] = s }
        // ALONE AFTER EVERYONE FELL SILENT: the silence may be mine (this phone's network went) -- it says once more that it is here,
        // and whoever is still in hands it their key and builds the pairs again
        if tellGroup, r.people.count == 1, !r.wasAlone {
            r.wasAlone = true
            tell(MTRoomEvent(r: r.id, e: "in", m: r.kind.rawValue, k: r.key.base64EncodedString(), at: r.since, o: r.owner,
                             q: r.kemPub.base64EncodedString()), in: r.chat)
        }
        publish()
        refresh()
    }

    /// THE BEAT IS THE ROOM'S OWN (the call's construction, MontanaCall.measureTick): armed again by each beat while this room is
    /// the one in hand, gone with it -- no repeating timer outlives its room, and the main queue beats in every mode of the loop.
    private func beatLater(_ r: MTRoomLive) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self, weak r] in
            guard let self, let r, self.live === r else { return }
            self.beat()
            self.beatLater(r)
        }
    }

    /// The room's beat, once a second: an unanswered offer goes again, a pair that fell long ago goes, the voices are measured.
    private func beat() {
        guard let r = live else { return }
        let now = Date()
        for p in Array(r.pairs.values) {
            if p.offerer, !p.answered, let o = p.lastOffer, now.timeIntervalSince(p.offeredAt) > 5, p.offers < 12 {
                p.offeredAt = now; p.offers += 1
                send(p, r, "offer", sdp: o)
            }
            if !p.outIce.isEmpty, !p.flushArmed, r.keys[p.seat] != nil {   // candidates that waited for the seat's room key
                let batch = p.outIce
                p.outIce = []
                send(p, r, "ice", ice: batch)
            }
            // A PAIR THAT FELL (a network changed, a path died) is built anew by the later one; the seat leaves the room only when no
            // pair of ours has stood with it for three minutes -- a phone in a tunnel is not taken out on its first silence.
            let fell = p.lostAt.map { now.timeIntervalSince($0) > Self.lostAfter } ?? (!p.everLinked && now.timeIntervalSince(p.bornAt) > Self.birthAfter)
            if fell {
                if now.timeIntervalSince(r.unlinked[p.seat] ?? p.bornAt) > Self.goneAfter { vanish(p.seat) }
                else if p.offerer { rebirth(p.seat) }
            }
        }
        measure(r)
        // THE ROOM SAYS IT LIVES (every ten minutes, by its first one): the bars of the group stay, and a phone that came late learns
        // who is in; a room nobody speaks for leaves the bars by itself (staleAfter).
        if now.timeIntervalSince(r.saidHere) > Self.hereEvery, Self.firstIn(r.people) == r.me {
            r.saidHere = now
            tell(MTRoomEvent(r: r.id, e: "here", m: r.kind.rawValue, k: r.key.base64EncodedString(), at: MontanaWakePush.nodeNow(), o: r.owner,
                             q: r.kemPub.base64EncodedString(), p: Array(r.people.keys)), in: r.chat)
        }
    }
    private func measure(_ r: MTRoomLive) {
        for p in r.pairs.values {
            p.pc?.statistics { report in
                var lv = 0.0
                for s in report.statistics.values where s.type == "inbound-rtp" && (s.values["kind"] as? String) == "audio" {
                    lv = max(lv, (s.values["audioLevel"] as? NSNumber)?.doubleValue ?? 0)
                }
                DispatchQueue.main.async { p.level = lv }
            }
        }
        if let pc = r.pairs.values.first(where: { $0.linked })?.pc {
            pc.statistics { report in
                var lv = 0.0
                for s in report.statistics.values where s.type == "media-source" && (s.values["kind"] as? String) == "audio" {
                    lv = max(lv, (s.values["audioLevel"] as? NSNumber)?.doubleValue ?? 0)
                }
                DispatchQueue.main.async { r.myLevel = lv }
            }
        }
        refresh()
    }

    /// The screen's faces, in the order the people came in: mine among them, each with its own picture or its face.
    private func refresh() {
        guard let r = live else { return }
        let m = MTRoomModel.shared
        let order = r.people.keys.sorted { a, b in Self.later((r.people[b] ?? 0, b), than: (r.people[a] ?? 0, a)) }
        var tiles: [MTRoomTile] = []
        for seat in order {
            if seat == r.me {
                tiles.append(MTRoomTile(seat: seat, name: name(seat, in: r.group), me: true,
                                        camera: r.cameraOn && !r.away && !r.screen && r.video != nil, screen: r.screen,
                                        muted: r.muted || !r.stage(r.me),
                                        speaking: !r.muted && r.stage(r.me) && r.myLevel > Self.speakingLevel,
                                        linked: true, owner: r.owner == seat))
            } else if r.kind == .call || r.stage(seat) || r.stage(r.me) {
                let p = r.pairs[seat]
                tiles.append(MTRoomTile(seat: seat, name: name(seat, in: r.group), me: false,
                                        camera: p?.camera == true && p?.remoteVideo != nil, screen: p?.screen == true,
                                        muted: p?.muted ?? !r.stage(seat), speaking: (p?.level ?? 0) > Self.speakingLevel,
                                        linked: p?.linked == true, owner: r.owner == seat))
            }
        }
        if m.tiles != tiles { m.tiles = tiles }
        if m.count != r.people.count { m.count = r.people.count }
        if m.amOwner != (r.owner == r.me) { m.amOwner = r.owner == r.me }
        if m.muted != r.muted { m.muted = r.muted }
        if m.camera != r.cameraOn { m.camera = r.cameraOn }
        if m.screen != r.screen { m.screen = r.screen }
    }

    // -- the picture and the voice -------------------------------------------------------------

    /// The camera on or off: the picture goes into every pair's line, or leaves it; every pair hears the state.
    func cameraOn(_ on: Bool) {
        guard let r = live, r.stage(r.me) else { return }
        if on {
            if r.source == nil {
                let f = MontanaCall.shared.factory
                let src = f.videoSource()
                // one picture of 640 by 480 for every pair: each pair's encoder scales it for its own watcher (tune)
                src.adaptOutputFormat(toWidth: 640, height: 480, fps: 24)
                r.source = src
                r.video = f.videoTrack(with: src, trackId: "room_v")
            }
            r.cameraOn = true
            if !r.screen { startCamera(r) }
        } else {
            r.cameraOn = false
            stopCamera(r)
        }
        for p in r.pairs.values { dress(p, r) }
        tellAll()
        let m = MTRoomModel.shared
        m.camera = on
        m.tick &+= 1
        let upd = CXCallUpdate()
        upd.hasVideo = on
        provider.reportCall(with: r.uuid, updated: upd)
        refresh()
    }

    private func startCamera(_ r: MTRoomLive) {
        guard let src = r.source else { return }
        MontanaCall.shared.ensureCameraAccess { [weak self] ok in
            guard let self, let now = self.live, now === r, r.cameraOn, !r.away, !r.screen else { return }
            guard ok else { self.cameraOn(false); return }
            let pos: AVCaptureDevice.Position = r.front ? .front : .back
            let all = MontanaCamera.devices()
            guard let dev = all.first(where: { $0.position == pos }) ?? all.first else { self.say("The camera is unavailable"); return }
            // the smallest format that still gives 640 wide at 24 frames, in a pixel kind the library reads
            let fit = MontanaCamera.formats(for: dev).filter { f in
                let sub = CMFormatDescriptionGetMediaSubType(f.formatDescription)
                let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
                return (sub == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange || sub == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
                    && d.width >= 640 && f.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 24 }
            }
            let pick = fit.min { a, b in
                let da = CMVideoFormatDescriptionGetDimensions(a.formatDescription)
                let db = CMVideoFormatDescriptionGetDimensions(b.formatDescription)
                return Int(da.width) * Int(da.height) < Int(db.width) * Int(db.height)
            }
            guard let fmt = pick else { self.say("The camera is unavailable"); return }
            let cam = r.camera ?? MontanaCamera(delegate: src)
            r.camera = cam
            cam.start(device: dev, format: fmt, fps: 24) { err in
                if let err { MontanaTrace.mark("room_camera", "FAIL \(err.localizedDescription)") }
            }
        }
    }
    private func stopCamera(_ r: MTRoomLive) {
        guard let cam = r.camera else { return }
        r.camera = nil
        cam.stop { }
    }
    func flipCamera() {
        guard let r = live, r.cameraOn, !r.screen else { return }
        r.front.toggle()
        MTRoomModel.shared.front = r.front
        startCamera(r)
    }

    /// This phone's microphone, with the system's own switch kept in step (the lock screen shows it).
    func setMuted(_ on: Bool, tellSystem: Bool = true) {
        guard let r = live else { return }
        r.muted = on
        r.audio?.isEnabled = !on && !r.held
        MTRoomModel.shared.muted = on
        tellAll()
        refresh()
        if tellSystem { controller.request(CXTransaction(action: CXSetMutedCallAction(call: r.uuid, muted: on))) { _ in } }
    }

    /// The system put the room on hold (a phone call came in): nothing is said and nothing is heard until it lets go.
    private func hold(_ on: Bool) {
        guard let r = live else { return }
        r.held = on
        MTRoomModel.shared.held = on
        r.audio?.isEnabled = !on && !r.muted
        for p in r.pairs.values { p.remoteAudio?.isEnabled = !on }
        MontanaTrace.mark("room", "held=\(on ? 1 : 0)")
    }

    /// The app left the screen: the camera rests (the platform gives a background app no camera) and the pairs show my face.
    private func away(_ on: Bool) {
        guard let r = live, r.away != on else { return }
        r.away = on
        guard r.cameraOn, !r.screen else { return }
        if on { stopCamera(r) } else { startCamera(r) }
        for p in r.pairs.values { dress(p, r) }
        tellAll()
        refresh()
    }

    /// The person takes the held room back (its line on the room's screen): the system lets go of the hold, and the voices return.
    func resume() {
        guard let r = live, r.held else { return }
        controller.request(CXTransaction(action: CXSetHeldCallAction(call: r.uuid, onHold: false))) { [weak self] err in
            DispatchQueue.main.async {
                if err != nil { self?.hold(false) }   // the system holds nothing of it any more: the room takes its voices back itself
            }
        }
    }

    func setSpeaker(_ on: Bool) {
        MTRoomModel.shared.speaker = on
        applySpeaker()
    }
    /// The loudspeaker by default in a room (many voices); a headset, a car or a speaker that holds the sound is never taken over.
    private func applySpeaker() { MontanaCall.roomSpeaker(MTRoomModel.shared.speaker) }   // the call's file owns the sound
    private func configureSound() { MontanaCall.roomSoundConfigure() }
    /// The system refused the room its call: the sound is raised by hand (in the call's file) so the room still speaks.
    private func soundByHand() {
        MontanaCall.roomSoundByHand()
        applySpeaker()
    }

    // -- the screen shown -----------------------------------------------------------------------

    /// The system broadcast's frames come to the room while it lives (the same proven socket as a call of two).
    private func armScreen() {
        guard MontanaCall.stateSnapshot == "idle" else { return }
        let ss = MTScreenShare.shared
        ss.onStart = { [weak self] in DispatchQueue.main.async { self?.screenOn(true) } }
        ss.onFrame = { [weak self] pb, orient, pts in self?.screenFrame(pb, orient, pts) }
        ss.onStop = { [weak self] in DispatchQueue.main.async { self?.screenOn(false) } }
        ss.arm()
    }
    private func screenOn(_ on: Bool) {
        guard let r = live, r.stage(r.me) else {
            if on { MTScreenShare.shared.dropPeer() }
            return
        }
        if on {
            guard !r.screen else { return }
            let f = MontanaCall.shared.factory
            let src = f.videoSource(forScreenCast: true)
            r.screenSource = src
            r.screenTrack = f.videoTrack(with: src, trackId: "room_s")
            shareLock.lock(); shareSource = src; shareShape = (0, 0); shareLock.unlock()
            r.cameraBeforeScreen = r.cameraOn
            stopCamera(r)
            r.screen = true
        } else {
            guard r.screen else { return }
            r.screen = false
            shareLock.lock(); shareSource = nil; shareLock.unlock()
            r.screenTrack = nil; r.screenSource = nil
            if r.cameraOn { startCamera(r) }
        }
        for p in r.pairs.values { dress(p, r) }
        tellAll()
        MTRoomModel.shared.screen = on
        MTRoomModel.shared.tick &+= 1
        refresh()
        MontanaTrace.mark("room_screen", on ? "on" : "off")
    }
    func stopScreen() { MTScreenShare.shared.dropPeer() }
    /// One frame of the shown screen: its own proportions on the wire, scaled to the same pixel budget a call of two keeps, never cut.
    private func screenFrame(_ pb: CVPixelBuffer, _ orientation: UInt32, _ ptsNs: Int64) {
        shareLock.lock(); let src0 = shareSource; let shape = shareShape; shareLock.unlock()
        guard let src = src0 else { return }
        let bw = CVPixelBufferGetWidth(pb), bh = CVPixelBufferGetHeight(pb)
        if bw != shape.w || bh != shape.h, bw > 0, bh > 0 {
            let scale = min(1.0, (Double(720 * 1560) / Double(bw * bh)).squareRoot())
            let tw = max(2, Int(Double(bw) * scale) / 2 * 2), th = max(2, Int(Double(bh) * scale) / 2 * 2)
            src.adaptOutputFormat(toWidth: Int32(tw), height: Int32(th), fps: 15)
            shareLock.lock(); shareShape = (bw, bh); shareLock.unlock()
        }
        let rot: RTCVideoRotation
        switch orientation {
        case 3: rot = ._180
        case 6: rot = ._270
        case 8: rot = ._90
        default: rot = ._0
        }
        let ts = ptsNs > 0 ? ptsNs : Int64(Date().timeIntervalSince1970 * 1_000_000_000)
        src.capturer(sharePusher, didCapture: RTCVideoFrame(buffer: RTCCVPixelBuffer(pixelBuffer: pb), rotation: rot, timeStampNs: ts))
    }

    // -- the system's call ------------------------------------------------------------------------

    /// The room is one call of the system (CallKit): the sound is the system's to give, the lock screen shows it, a phone call
    /// holds it. The handle is the room's id -- it means nothing outside this phone and links nobody.
    private func startSystemCall(_ r: MTRoomLive, video: Bool) {
        configureSound()
        let start = CXStartCallAction(call: r.uuid, handle: CXHandle(type: .generic, value: r.id))
        start.isVideo = video
        controller.request(CXTransaction(action: start)) { [weak self] err in
            DispatchQueue.main.async {
                guard let self, let now = self.live, now === r, let err else { return }
                MontanaTrace.mark("room_system", "start refused \(err.localizedDescription)")
                self.soundByHand()
            }
        }
    }
    func providerDidReset(_ provider: CXProvider) { leave(why: "the system reset", systemEnded: true) }
    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        guard let r = live, r.uuid == action.callUUID else { action.fail(); return }
        action.fulfill()
        provider.reportOutgoingCall(with: r.uuid, startedConnectingAt: nil)
        provider.reportOutgoingCall(with: r.uuid, connectedAt: nil)
        let u = CXCallUpdate()
        u.localizedCallerName = MTRoomModel.shared.title
        u.hasVideo = action.isVideo
        u.supportsHolding = true; u.supportsGrouping = false; u.supportsUngrouping = false; u.supportsDTMF = false
        provider.reportCall(with: r.uuid, updated: u)
    }
    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        action.fulfill()
        if let r = live, r.uuid == action.callUUID { leave(why: "the system's end", systemEnded: true) }
    }
    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        action.fulfill()
        if let r = live, r.uuid == action.callUUID, r.muted != action.isMuted { setMuted(action.isMuted, tellSystem: false) }
    }
    func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        action.fulfill()
        if let r = live, r.uuid == action.callUUID { hold(action.isOnHold) }
    }
    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        RTCAudioSession.sharedInstance().audioSessionDidActivate(audioSession)
        RTCAudioSession.sharedInstance().isAudioEnabled = true
        applySpeaker()
        MontanaTrace.mark("room_system", "sound on")
    }
    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        RTCAudioSession.sharedInstance().audioSessionDidDeactivate(audioSession)
        if MontanaCall.stateSnapshot == "idle" { RTCAudioSession.sharedInstance().isAudioEnabled = false }
        MontanaAudioSession.callEnded()
        MontanaTrace.mark("room_system", "sound off")
    }

    // -- the screen's hands ---------------------------------------------------------------------

    func show(_ on: Bool) {
        MTRoomModel.shared.shown = on && live != nil
        MTRoomWindow.shared.update()
    }
    /// One face large, or the grid again; the person shown large gets my wish for the whole picture.
    func focus(_ seat: String?) {
        let m = MTRoomModel.shared
        m.focus = (seat == nil || m.focus == seat) ? nil : seat
        tellAll()
    }
    func track(for seat: String) -> RTCVideoTrack? {
        guard let r = live else { return nil }
        if seat == r.me { return r.screen ? r.screenTrack : r.video }
        return r.pairs[seat]?.remoteVideo
    }
    /// A short line over the room or the chat, gone by itself.
    func say(_ key: String.LocalizationValue) {
        let text = String(localized: key, bundle: MTLanguage.bundle)
        let m = MTRoomModel.shared
        m.note = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { if m.note == text { m.note = nil } }
    }
}

// ════════════════════════════════════════════════════════════
// THE ROOM'S SCREEN
// ════════════════════════════════════════════════════════════

extension MTRoomKind: Identifiable { var id: String { rawValue } }

/// The room's own window over the app, as a call's: shown while the room is in hand and not folded; folded, a pill stays on top.
final class MTRoomWindow {
    static let shared = MTRoomWindow()
    private var window: UIWindow?
    private var pill: UIWindow?

    func update() {
        DispatchQueue.main.async {
            let m = MTRoomModel.shared
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else { return }
            if m.inRoom, m.shown {
                if self.window == nil {
                    let w = UIWindow(windowScene: scene)
                    w.windowLevel = .alert + 1
                    w.backgroundColor = .black
                    let host = MontanaHost.make(MTRoomScreen())
                    host.view.backgroundColor = .black
                    host.safeAreaRegions = [.container]   // the room has no field: no keyboard of another window moves it
                    w.rootViewController = host
                    self.window = w
                }
                self.window?.isHidden = false
                self.window?.makeKeyAndVisible()
                scene.windows.forEach { $0.endEditing(true) }
            } else if let w = self.window {
                w.isHidden = true
                if !m.inRoom { self.window = nil }
                scene.windows.first(where: { !$0.isHidden && $0 !== w && $0 !== self.pill })?.makeKeyAndVisible()
            }
            if m.inRoom, !m.shown {
                if self.pill == nil {
                    // the pill's window is the pill's size: the finger anywhere else reaches the app under it
                    let top = scene.windows.first(where: { $0.isKeyWindow })?.safeAreaInsets.top ?? 47
                    let width: CGFloat = 220
                    let w = UIWindow(windowScene: scene)
                    w.frame = CGRect(x: (scene.screen.bounds.width - width) / 2, y: top + 2, width: width, height: 44)
                    w.windowLevel = .alert
                    w.backgroundColor = .clear
                    let host = MontanaHost.make(MTRoomPill())
                    host.view.backgroundColor = .clear
                    w.rootViewController = host
                    self.pill = w
                }
                self.pill?.isHidden = false
            } else if let p = self.pill {
                p.isHidden = true
                self.pill = nil
            }
        }
    }
}

/// The folded room: one green capsule over every screen -- a tap is the way back.
struct MTRoomPill: View {
    @ObservedObject private var m = MTRoomModel.shared
    var body: some View {
        Button { MTGroupRoom.shared.show(true) } label: {
            HStack(spacing: 8) {
                Image(systemName: m.kind == .live ? "dot.radiowaves.left.and.right" : (m.camera ? "video.fill" : "phone.fill"))
                    .font(.system(size: 14, weight: .semibold))
                Text(verbatim: m.title).font(.subheadline.weight(.semibold)).lineLimit(1)   // USER-DATA: the group's name
                Text(m.count, format: .number).font(.subheadline.monospacedDigit())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Capsule().fill(Color.green))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Return to the call"))
    }
}

/// THE ROOM: the faces in a grid -- everyone has a picture of their own, a face with a letter when on voice -- one face large at a
/// tap, the controls at the bottom; the owner's hand over each face (a long press) and over the room (the top menu).
struct MTRoomScreen: View {
    @ObservedObject private var m = MTRoomModel.shared
    @State private var inviting = false
    @State private var confirmEnd = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 12) {
                top
                if m.held {
                    // THE HELD ROOM SAYS SO (a phone call took the sound): the whole line is the way back
                    Button { MTGroupRoom.shared.resume() } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "pause.circle.fill").font(.system(size: 20))
                            Text("On hold").font(.subheadline.weight(.semibold))
                            Spacer(minLength: 0)
                            Image(systemName: "play.fill").font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 48)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.orange.opacity(0.85)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Resume the call"))
                }
                stage.frame(maxHeight: .infinity)
                controls
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            if let n = m.note {
                VStack {
                    Text(n)   // a line the room said, from the catalogue (say)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Capsule().fill(Color.white.opacity(0.18)))
                    Spacer()
                }
                .padding(.top, 64)
                .allowsHitTesting(false)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $inviting) {
            MTRoomInviteSheet(chat: m.chat, kind: m.kind, video: m.camera, opening: false)
        }
        .confirmationDialog("End the call for everyone?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End for Everyone", role: .destructive) { MTGroupRoom.shared.endForEveryone() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var subtitle: String {
        m.kind == .live ? String(localized: "\(m.count) watching", bundle: MTLanguage.bundle)
                        : String(localized: "\(m.count) of \(MTGroupRoom.capacity)", bundle: MTLanguage.bundle)
    }

    private var top: some View {
        HStack(spacing: 8) {
            Button { MTGroupRoom.shared.show(false) } label: { round("chevron.down") }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Minimize"))
            VStack(spacing: 2) {
                Text(verbatim: m.title).font(.headline).foregroundStyle(.white).lineLimit(1)   // USER-DATA: the group's name
                Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            if m.kind == .call || m.amOwner {
                Button { inviting = true } label: { round("person.badge.plus") }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Invite"))
            }
            if m.amOwner {
                Menu {
                    Button(role: .destructive) { confirmEnd = true } label: { Label("End for Everyone", systemImage: "phone.down.fill") }
                } label: { round("ellipsis") }
                .accessibilityLabel(Text("Call Settings"))
            }
        }
    }
    private func round(_ glyph: String) -> some View {
        Image(systemName: glyph)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(Circle().fill(Color.white.opacity(0.14)))
            .contentShape(Circle())
    }

    @ViewBuilder private var stage: some View {
        if let f = m.focus, let big = m.tiles.first(where: { $0.seat == f }) {
            VStack(spacing: 8) {
                MTRoomTileView(tile: big, big: true)
                if m.tiles.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(m.tiles.filter { $0.seat != f }) { t in MTRoomTileView(tile: t).frame(width: 96, height: 128) }
                        }
                    }
                    .frame(height: 128)
                }
            }
        } else {
            GeometryReader { geo in
                let n = m.tiles.count
                let wide = geo.size.width > 700
                let cols = n <= 2 ? 1 : (n <= 4 ? 2 : (wide && n > 9 ? 4 : 3))
                let shape: CGFloat = n == 1 ? 0.72 : (n == 2 ? 1.25 : 0.78)
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: cols), spacing: 8) {
                        ForEach(m.tiles) { t in MTRoomTileView(tile: t).aspectRatio(shape, contentMode: .fit) }
                    }
                }
            }
        }
    }

    private var controls: some View {
        HStack(alignment: .top, spacing: 6) {
            if m.speaks {
                control(m.muted ? "mic.slash.fill" : "mic.fill", "Microphone", on: !m.muted) { MTGroupRoom.shared.setMuted(!m.muted) }
                control(m.camera ? "video.fill" : "video.slash.fill", "Camera", on: m.camera) { MTGroupRoom.shared.cameraOn(!m.camera) }
                if m.camera, !m.screen {
                    control("arrow.triangle.2.circlepath.camera", "Flip", on: false) { MTGroupRoom.shared.flipCamera() }
                }
                screenControl
            }
            if MontanaAudioRoute.isExternal {
                // a headset, a car or a speaker holds the sound: the system's own choice of the road, as in a call of two
                VStack(spacing: 4) {
                    ZStack {
                        face("airplayaudio", on: false, red: false)
                        CallOverlayView.MTRoutePicker().frame(width: 56, height: 56)
                    }
                    Text("Audio").font(.caption2).foregroundStyle(.white.opacity(0.85)).lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
            } else {
                control(m.speaker ? "speaker.wave.2.fill" : "speaker.fill", "Speaker", on: m.speaker) { MTGroupRoom.shared.setSpeaker(!m.speaker) }
            }
            control("phone.down.fill", "Leave", on: false, red: true) { MTGroupRoom.shared.leave(why: "by hand") }
        }
    }
    private func face(_ glyph: String, on: Bool, red: Bool) -> some View {
        Image(systemName: glyph)
            .font(.system(size: 21, weight: .semibold))
            .foregroundStyle(red ? Color.white : (on ? Color.black : Color.white))
            .frame(width: 56, height: 56)
            .background(Circle().fill(red ? Color.red : (on ? Color.white : Color.white.opacity(0.18))))
    }
    private func control(_ glyph: String, _ caption: LocalizedStringKey, on: Bool, red: Bool = false,
                         _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            VStack(spacing: 4) {
                face(glyph, on: on, red: red)
                Text(caption).font(.caption2).foregroundStyle(.white.opacity(0.85)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    /// The screen shown: the system's own broadcast sheet is the way in (its countdown, its red pill); a tap while showing stops it.
    @ViewBuilder private var screenControl: some View {
        if m.screen {
            control("rectangle.on.rectangle.slash", "Screen", on: true) { MTGroupRoom.shared.stopScreen() }
        } else {
            VStack(spacing: 4) {
                ZStack {
                    face("rectangle.on.rectangle", on: false, red: false)
                    CallOverlayView.MTBroadcastPickerButton().frame(width: 56, height: 56)
                }
                Text("Screen").font(.caption2).foregroundStyle(.white.opacity(0.85)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .accessibilityLabel(Text("Share Screen"))
        }
    }
}

/// One face of the room: its picture (the camera or the screen), or the face with a letter on voice; the name, the muted mark,
/// the owner's crown, the green ring while it speaks.
struct MTRoomTileView: View {
    let tile: MTRoomTile
    var big = false
    @ObservedObject private var m = MTRoomModel.shared

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(white: 0.13))
            if tile.camera || tile.screen, let track = MTGroupRoom.shared.track(for: tile.seat) {
                MTRoomVideo(track: track, fit: tile.screen, mirror: tile.me && !tile.screen && m.front)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                Text(verbatim: initial)   // USER-DATA: the first letter of a person's name
                    .font(.system(size: big ? 54 : 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: big ? 120 : 64, height: big ? 120 : 64)
                    .background(Circle().fill(color))
            }
            VStack {
                Spacer()
                HStack(spacing: 4) {
                    if tile.muted { Image(systemName: "mic.slash.fill").font(.caption2) }
                    if tile.owner { Image(systemName: "crown.fill").font(.caption2) }
                    Text(verbatim: tile.name).font(.caption).lineLimit(1)   // USER-DATA: a person's name
                    if !tile.linked { ProgressView().controlSize(.mini).tint(.white) }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(Color.black.opacity(0.45)))
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // THE FINGER'S LAYER IS A SIBLING OVER THE PICTURE, never a gesture on the platform view (the law of 29.09).
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { MTGroupRoom.shared.focus(tile.seat) }
                .contextMenu { ownerMenu }
        }
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(tile.speaking ? Color.green : Color.clear, lineWidth: 3))
        .accessibilityElement(children: .combine)
    }
    @ViewBuilder private var ownerMenu: some View {
        if m.amOwner, !tile.me {
            Button { MTGroupRoom.shared.ownerMute(tile.seat) } label: { Label("Mute", systemImage: "mic.slash") }
            Button(role: .destructive) { MTGroupRoom.shared.ownerDrop(tile.seat) } label: {
                Label("Remove from Call", systemImage: "person.fill.xmark")
            }
        }
    }
    private var initial: String { tile.name.first.map { String($0).uppercased() } ?? "?" }
    /// One colour per seat, the same on every phone: the seat's own letters, summed.
    private var color: Color {
        let sum = tile.seat.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Color(hue: Double(sum % 360) / 360, saturation: 0.45, brightness: 0.55)
    }
}

/// A picture of the room: the platform's Metal view, which never takes the finger (a picture is not a control).
struct MTRoomVideo: UIViewRepresentable {
    let track: RTCVideoTrack
    let fit: Bool
    let mirror: Bool
    final class Coordinator { weak var track: RTCVideoTrack? }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> RTCMTLVideoView {
        let v = RTCMTLVideoView()
        v.isUserInteractionEnabled = false
        v.videoContentMode = fit ? .scaleAspectFit : .scaleAspectFill
        v.transform = mirror ? CGAffineTransform(scaleX: -1, y: 1) : .identity
        track.add(v)
        context.coordinator.track = track
        return v
    }
    func updateUIView(_ v: RTCMTLVideoView, context: Context) {
        let mode: UIView.ContentMode = fit ? .scaleAspectFit : .scaleAspectFill
        if v.videoContentMode != mode { v.videoContentMode = mode }
        v.transform = mirror ? CGAffineTransform(scaleX: -1, y: 1) : .identity
        if context.coordinator.track !== track {
            context.coordinator.track?.remove(v)
            track.add(v)
            context.coordinator.track = track
        }
    }
    static func dismantleUIView(_ v: RTCMTLVideoView, coordinator: Coordinator) {
        coordinator.track?.remove(v)
        coordinator.track = nil
    }
}

/// WHOM TO INVITE (the author's word 07.10.2026 00:3x MSK): the people of the group, everyone at one tap; the chosen get the room's
/// way in -- a banner and the bar over their chat -- and no phone rings.
struct MTRoomInviteSheet: View {
    let chat: String
    let kind: MTRoomKind
    let video: Bool
    /// True: the room is opened by this sheet; false: more people are invited into the room in hand.
    let opening: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: Set<String> = []

    var body: some View {
        let people = MTGroupRoom.shared.invitable(chat)
        NavigationStack {
            List {
                if !people.isEmpty {
                    Section {
                        Button {
                            chosen = chosen.count == people.count ? [] : Set(people.map(\.seat))
                        } label: {
                            row(glyph: "person.3.fill", name: String(localized: "Everyone", bundle: MTLanguage.bundle),
                                on: chosen.count == people.count)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Section {
                    ForEach(people) { p in
                        Button {
                            if chosen.contains(p.seat) { chosen.remove(p.seat) } else { chosen.insert(p.seat) }
                        } label: {
                            row(glyph: nil, name: p.name, on: chosen.contains(p.seat))
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text("The people chosen get a way into the call. Nobody's phone rings.")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(Text("Cancel"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { go() } label: { Image(systemName: "checkmark") }
                        .accessibilityLabel(Text("Invite"))
                }
            }
        }
    }
    private var title: LocalizedStringKey {
        kind == .live ? "Live Stream" : (video ? "Video Chat" : "Voice Chat")
    }
    private func row(glyph: String?, name: String, on: Bool) -> some View {
        HStack(spacing: 12) {
            if let glyph {
                Image(systemName: glyph).font(.system(size: 17)).foregroundStyle(.primary).frame(width: 36, height: 36)
            } else {
                Text(verbatim: name.first.map { String($0).uppercased() } ?? "?")   // USER-DATA: the first letter of a person's name
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 36, height: 36).background(Circle().fill(Color.gray))
            }
            Text(verbatim: name).foregroundStyle(.primary).lineLimit(1)   // USER-DATA: a person's name
            Spacer(minLength: 0)
            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22))
                .foregroundStyle(on ? Color(uiColor: .systemBlue) : Color.secondary)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
    private func go() {
        let seats = Array(chosen)
        dismiss()
        if opening { MTGroupRoom.shared.open(kind, video: video, in: chat, invite: seats) } else { MTGroupRoom.shared.invite(seats) }
    }
}

/// THE ROOM OVER ITS CHAT: a group whose room lives shows it here -- its kind, how many are in, who invited me. The whole row is the
/// way in, or back when this phone is in it; a line about the room (full, ended) stands here when no room screen is up.
struct MTRoomBar: View {
    let chat: String
    @ObservedObject private var book = MTRoomBook.shared
    @ObservedObject private var m = MTRoomModel.shared
    var body: some View {
        if let gid = MTGroup.id(of: chat), let b = book.rooms[gid] {
            Button {
                if b.mine { MTGroupRoom.shared.show(true) } else { MTGroupRoom.shared.join(chat, video: false) }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: b.kind == .live ? "dot.radiowaves.left.and.right" : (b.video ? "video.fill" : "phone.fill"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.green))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(headline(b)).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                        Text(detail(b)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: b.mine ? "arrow.up.left.and.arrow.down.right" : "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 52)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.top, 4)
        } else if !m.inRoom, let n = m.note {
            Text(n)   // a line the room said, from the catalogue (say)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .padding(.top, 4)
        }
    }
    private func headline(_ b: MTRoomBrief) -> String {
        switch (b.kind, b.video) {
        case (.live, _): return String(localized: "Live stream", bundle: MTLanguage.bundle)
        case (.call, true): return String(localized: "Video chat", bundle: MTLanguage.bundle)
        case (.call, false): return String(localized: "Voice chat", bundle: MTLanguage.bundle)
        }
    }
    private func detail(_ b: MTRoomBrief) -> String {
        if b.mine { return String(localized: "Tap to return", bundle: MTLanguage.bundle) }
        if let a = b.asker { return String(localized: "\(a) invites you", bundle: MTLanguage.bundle) }
        return b.kind == .live ? String(localized: "\(b.count) watching", bundle: MTLanguage.bundle)
                               : String(localized: "\(b.count) of \(MTGroupRoom.capacity)", bundle: MTLanguage.bundle)
    }
}

/// THE PHONE MARK OF A GROUP (the author's word 07.10.2026 00:3x MSK): a tap chooses the kind of call, then whom to invite; a room
/// already living in the group is joined at once, its mark ringed.
struct MTRoomMark: View {
    let chat: String
    let side: CGFloat
    /// The kind chosen: the chat shows whom to invite (its own sheet -- a sheet hung inside a bar's item is not always shown).
    var onAsk: (MTRoomKind, Bool) -> Void
    @ObservedObject private var book = MTRoomBook.shared

    var body: some View {
        let kinds = MTGroupRoom.shared.kinds(for: chat)
        let living = MTGroup.id(of: chat).flatMap { book.rooms[$0] }
        Group {
            if let b = living {
                Button {
                    MTGroupRoom.shared.tapped(chat, kind: b.kind, video: false, ask: onAsk)
                } label: {
                    MTBarRoundMark(ringed: true, side: side) { MontanaBarGlyph(glyph: "phone") }
                }
                .accessibilityLabel(Text("Join the Call"))
            } else if !kinds.isEmpty {
                Menu {
                    if kinds.contains(.call) {
                        Button { onAsk(.call, false) } label: { Label("Voice Chat", systemImage: "phone.fill") }
                        Button { onAsk(.call, true) } label: { Label("Video Chat", systemImage: "video.fill") }
                    }
                    if kinds.contains(.live) {
                        Button { onAsk(.live, true) } label: { Label("Live Stream", systemImage: "dot.radiowaves.left.and.right") }
                    }
                } label: {
                    MTBarRoundMark(ringed: false, side: side) { MontanaBarGlyph(glyph: "phone") }
                }
                .accessibilityLabel(Text("Call"))
            }
        }
    }
}

/// A GROUP'S LIVING ROOM IN THE CHATS LIST: a small green mark beside the group's name -- the row stays the one button (it opens the
/// chat, where the bar is the way in).
struct MTRoomRowMark: View {
    let chat: String
    @ObservedObject private var book = MTRoomBook.shared
    var body: some View {
        if let gid = MTGroup.id(of: chat), let b = book.rooms[gid] {
            Image(systemName: b.kind == .live ? "dot.radiowaves.left.and.right" : (b.video ? "video.fill" : "phone.fill"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.green)
                .accessibilityLabel(Text(b.kind == .live ? "Live stream" : (b.video ? "Video chat" : "Voice chat")))
        }
    }
}
