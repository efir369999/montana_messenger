import Foundation
import SwiftUI
import MontanaBindings
import CryptoKit

// SSOT UI standards ([I-10]/[C-1]): every tappable control uses at least this hit area, and every
// long-press-to-menu uses this duration. Never hardcode 44 or 0.22 at a call site — use these.
let montanaTouchTarget: CGFloat = 44
let montanaLongPress: Double = 0.22

extension View {
    /// THE FINGER'S 44 AROUND A SMALLER FACE (23.09): the platform's least target is laid out, taken by
    /// the touch shape and given back to the layout -- the button keeps `layout` points of the row it
    /// stands in, and the finger gets its 44. The compose bar keeps its tier the same way.
    func montanaFingerRoom(layout: CGFloat) -> some View {
        frame(width: montanaTouchTarget, height: montanaTouchTarget)
            .contentShape(Rectangle())
            .padding(-(montanaTouchTarget - layout) / 2)
    }
}

// SSOT transport identity ([I-10]/[C-1]): one place defines the transport categories, their display
// symbol, and the classification.
enum MontanaTransport: String {
    case internet, wifi, cellular
    // Canonical priority order, left -> right: internet > Wi-Fi > cellular.
    static let ordered: [MontanaTransport] = [.internet, .wifi, .cellular]
    // SF Symbol name. SINGLE source of the icon shape.
    var sfSymbol: String {
        switch self {
        case .internet: return "globe"
        case .wifi: return "wifi"
        case .cellular: return "cellularbars"
        }
    }
    /// Physical delivery medium of a message: cellular egress -> .cellular, else Wi-Fi -> .wifi.
    /// (.internet is a header connectivity STATE, not a per-message transport.)
    static func delivery(cellularEgress: Bool) -> MontanaTransport { cellularEgress ? .cellular : .wifi }
    /// Our own loopback is the only address a node must tell from a neighbour: it is the node itself.
    /// The value is defined by the standard and has nowhere to move (CONFIG-OK).
    static func isLoopback(_ raw: String) -> Bool {
        let ip = raw.split(separator: ":").first.map(String.init) ?? raw
        return ip == "127.0.0.1" || ip.hasPrefix("127.") || ip == "::1"
    }

    static func isGlobalIP(_ raw: String) -> Bool {
        let ip = raw.split(separator: "%").first.map(String.init) ?? raw
        let low = ip.lowercased()
        if ip.hasPrefix("10.") || ip.hasPrefix("192.168.") || ip.hasPrefix("169.254.") || ip == "127.0.0.1" { return false }
        if ip.hasPrefix("172.") { let p = ip.split(separator: "."); if p.count > 1, let o = Int(p[1]), (16...31).contains(o) { return false } }
        if low.hasPrefix("fe80") || low.hasPrefix("fc") || low.hasPrefix("fd") || low == "::1" { return false }
        return true
    }
}

// SSOT canonical transport icon ([I-10]/[C-1]): the ONE place any transport icon is drawn — chats
// header, Montana Network page, and message bubbles all use this. Two colours only: green = on,
// red = off. Do NOT inline Image(systemName:) for a transport icon anywhere else.
struct MontanaTransportIcon: View {
    let transport: MontanaTransport
    var on: Bool = true
    var size: CGFloat = 15
    var tint: Color? = nil   // nil = state colours (green on / red off); set = fixed colour (white in bubbles)
    /// UNKNOWN IS NOT «NO». At birth the app has not yet knocked on a single door, and a red lamp
    /// there is a statement it has not earned: the person opens a notification and is told the
    /// network is dead a second before it turns out to be alive. Unknown wears grey — quiet,
    /// honest, and never mistaken for a verdict.
    var known: Bool = true
    var body: some View {
        let color: Color = tint ?? (known ? (on ? .green : .red) : Color(white: 0.45))
        Image(systemName: transport.sfSymbol).font(.system(size: size, weight: .semibold)).foregroundColor(color)
    }
}

// Stage-1 protocol layer (spec s.3 §5): NetMessage multiplex (§5.0), OverlayFrame (§5.2),
// registration frames (§5.3) and the §5.1 proof-of-ownership. All rides INSIDE the Noise_PQ
// stream. Byte-exact, big-endian length fields (matches the transport's 4-byte frame prefix).

enum MontanaNetMsg {
    static let registerInit: UInt8 = 0x10
    static let registerChallenge: UInt8 = 0x11
    static let registerProof: UInt8 = 0x12
    static let registerResult: UInt8 = 0x13
    /// The owner link a machine gives a neighbour at an introduction.
    ///
    /// The set: "at acquaintance each entry gives it an owner reference, derived from that owner's
    /// secret together with the secret the two of them share". It is given by THE SIDE whose owner is
    /// named -- computing it on their behalf is impossible: two machines of one owner would give two
    /// different values, and the bound on owner distinctness would stop protecting anything.
    static let ownerRef: UInt8 = 0x14
    static let overlayFrame: UInt8 = 0x20

    // NetMessage { msg_type 1B | body_len 4B u32 BE | body }
    static func encode(_ type: UInt8, _ body: Data) -> Data {
        var d = Data([type])
        var n = UInt32(body.count).bigEndian
        withUnsafeBytes(of: &n) { d.append(contentsOf: $0) }
        d.append(body)
        return d
    }
    static func decode(_ d: Data) -> (type: UInt8, body: Data)? {
        guard d.count >= 5 else { return nil }
        let b = d.startIndex
        let type = d[b]
        let len = (Int(d[b + 1]) << 24) | (Int(d[b + 2]) << 16) | (Int(d[b + 3]) << 8) | Int(d[b + 4])
        guard d.count == 5 + len else { return nil }
        return (type, d.subdata(in: (b + 5)..<(b + 5 + len)))
    }
}

// OverlayFrame { version 1B=0x01 | type 1B | dst_overlay 32B | src_overlay 32B | msg_id 16B | payload_len 4B u32 BE | payload }
/// A cell of the direct channel: the target, an identifier for dedup, and the body.
///
/// It used to carry the SENDER's node address as well. Nothing routed on it — the code says so
/// itself, «a node routes on dst only» — it existed so an acknowledgement knew where to go back to.
/// An acknowledgement goes back down the channel it arrived on, which needs no address at all, so
/// the field bought nothing and cost the one thing [I-16] forbids: a machine in transit could read
/// who originated the cell and tell an origin from a relay.
struct MontanaOverlayFrame {
    static let relay: UInt8 = 0x01
    static let deliver: UInt8 = 0x02
    static let ack: UInt8 = 0x03
    static let headerSize = 54

    let type: UInt8
    let dst: Data      // 32 — the target, which routing cannot do without
    let msgId: Data    // 16
    let payload: Data

    func encode() -> Data {
        var d = Data([0x02, type]); d.append(dst); d.append(msgId)
        var n = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: &n) { d.append(contentsOf: $0) }
        d.append(payload)
        return d
    }
    static func decode(_ d: Data) -> MontanaOverlayFrame? {
        guard d.count >= headerSize, d[d.startIndex] == 0x02 else { return nil }
        let b = d.startIndex
        let type = d[b + 1]
        let dst = d.subdata(in: (b + 2)..<(b + 34))
        let msgId = d.subdata(in: (b + 34)..<(b + 50))
        let plen = (Int(d[b + 50]) << 24) | (Int(d[b + 51]) << 16) | (Int(d[b + 52]) << 8) | Int(d[b + 53])
        guard d.count == headerSize + plen else { return nil }
        let payload = d.subdata(in: (b + 54)..<(b + 54 + plen))
        return MontanaOverlayFrame(type: type, dst: dst, msgId: msgId, payload: payload)
    }
}


// ── The quantities of delivery, as the set states them ───────────────────────────────────────
//
// A frame is addressed by a TAG of the current window, not by a standing name of a device: the
// tag stands on the secret two correspondents share and dies with the window. The step a frame
// takes carries a SEAL of the owner who took it, so distinctness of owners can be counted inside
// one delivery without naming anyone.
extension MontanaOverlayFrame {
    /// Where this frame is deposited in the given window. Both sides compute it and neither asks.
    static func destination(sharedSecret: Data, window: UInt64) -> Data {
        MTPipe.tag(sharedSecret: sharedSecret, window: window)
    }

    /// The machine that holds that deposit: the least commitment standing above the tag, and the
    /// lowest of all when none stands above it.
    static func holder(tag: Data, livingCommitments: [Data]) -> Data? {
        MTPipe.holder(of: tag, among: livingCommitments)
    }
}

/// What a MACHINE answers under while it is on the air, and nothing more than that.
///
/// It used to be derived from the seed. That made it a quantity of the PERSON: one seed gives one
/// key, so every device of one person answered under the same value, it never changed, and it
/// travelled in the clear in the header of every frame. An observer needed nothing else to join all
/// of that person's appearances — everywhere and forever. [I-17].2 forbids exactly that, and
/// [I-17].4 gives a machine no address of a person either.
///
/// So it is drawn at random by the core, once per device, and kept sealed beside the other local
/// secrets. It says nothing about who holds the device: a second device of the same person answers
/// under a different value, and a re-installed one under a third.
///
/// It is still constant between windows, and that debt is real and named: it is replaced by the tag
/// of a pipe (`mt-tag`) per window, and this type is the single seam where that replacement lands.
struct MontanaOverlayKey {
    let authPk: [UInt8]   // 1952
    let authSk: [UInt8]   // 4032
    let tag: Data         // 32 — the tag of this machine on the overlay, from its answering key

    private static let vaultKey = "mt.node.identity"
    private static var cache: MontanaOverlayKey?
    private static let lock = NSLock()

    /// The identity of THIS device: read from the local vault, or born there on first use. Nothing
    /// about the person enters it — not the seed, not the platform, not a name.
    static func device() -> MontanaOverlayKey? {
        lock.lock()   // LOCK-OK: the vault record of this device's identity is read or born once, then cached; the log line waits outside
        if let c = cache { lock.unlock(); return c }
        var out: MontanaOverlayKey? = nil
        var born = false
        if let d = MontanaLocalVault.getDecrypted(vaultKey), d.count == 32, let id = fromSeed([UInt8](d)) {
            cache = id; out = id
        } else {
            var seed = [UInt8](repeating: 0, count: 32)
            if mt_random_fast(&seed, 32) == 0, let id = fromSeed(seed), MontanaLocalVault.setEncrypted(vaultKey, Data(seed)) {
                cache = id; out = id; born = true
            }
        }
        lock.unlock()
        if born { MontanaLog.event("NODE identity born (device-local, never derived from the seed)") }
        return out
    }

    /// The device forgets what it answered under. Called where the device forgets the person: a
    /// value outliving an identity would join the two of them for anyone who was listening.
    static func forget() {
        lock.lock(); defer { lock.unlock() }   // LOCK-OK: the cache and the record forget as one step — a reader between them would revive the old identity
        cache = nil
        UserDefaults.standard.removeObject(forKey: vaultKey)
    }

    private static func fromSeed(_ seed: [UInt8]) -> MontanaOverlayKey? {
        var pk = [UInt8](repeating: 0, count: 1952), sk = [UInt8](repeating: 0, count: 4032)
        guard seed.count == 32, mt_mldsa_keypair_from_seed(seed, &pk, &sk) == 0 else { return nil }
        return MontanaOverlayKey(authPk: pk, authSk: sk, tag: Self.tag(fromAuthPub: pk))
    }

    /// The address of a node: the ONE place it is computed. It was written in four, and four
    /// writings of one quantity drift the day one of them is corrected.
    static func tag(fromAuthPub pub: [UInt8]) -> Data {
        MTPipe.domained("mt-overlay", [Data(pub)])
    }
    static func tag(fromAuthPub pub: Data) -> Data { tag(fromAuthPub: [UInt8](pub)) }
}

// §5.1 proof-of-ownership: sig = ML-DSA.Sign(overlay_auth_key, op_domain||0x00||resource_id||nonce||channel_hash)
enum MontanaOverlayProof {
    static func signable(opDomain: String, resourceId: Data, nonce: Data, channelHash: Data) -> Data {
        var d = Data(opDomain.utf8); d.append(0); d.append(resourceId); d.append(nonce); d.append(channelHash)
        return d
    }
    static func sign(authSk: [UInt8], opDomain: String, resourceId: Data, nonce: Data, channelHash: Data) -> Data? {
        let msg = [UInt8](signable(opDomain: opDomain, resourceId: resourceId, nonce: nonce, channelHash: channelHash))
        var sig = [UInt8](repeating: 0, count: 3309)
        let rc = authSk.withUnsafeBufferPointer { sk in msg.withUnsafeBufferPointer { m in
            mt_sign(sk.baseAddress, m.baseAddress, msg.count, &sig) } }
        return rc == 0 ? Data(sig) : nil
    }
    static func verify(authPub: Data, sig: Data, opDomain: String, resourceId: Data, nonce: Data, channelHash: Data) -> Bool {
        guard authPub.count == 1952, sig.count == 3309 else { return false }
        let msg = [UInt8](signable(opDomain: opDomain, resourceId: resourceId, nonce: nonce, channelHash: channelHash))
        let ok = [UInt8](authPub).withUnsafeBufferPointer { pk in msg.withUnsafeBufferPointer { m in
            [UInt8](sig).withUnsafeBufferPointer { sg in mt_verify(pk.baseAddress, m.baseAddress, msg.count, sg.baseAddress) } } }
        return ok == 0
    }
}

/// The sealing key of THIS machine: what a neighbour encapsulates to when it hands this device a
/// frame. Device-local and drawn at random for the same reason the identity above is — a key
/// derived from the seed is one key for every device of one person, forever, and a value like that
/// joins their appearances without anybody having to publish an edge.
enum MontanaNodeKem {
    private static let vaultKey = "mt.node.kem"
    private static var cache: (pk: [UInt8], sk: [UInt8])?
    private static let lock = NSLock()

    static func device() -> (pk: [UInt8], sk: [UInt8])? {
        lock.lock()   // LOCK-OK: the vault record of this device's key is read once, then cached
        if let c = cache { lock.unlock(); return c }
        if let d = MontanaLocalVault.getDecrypted(vaultKey), d.count == 64,
           let kp = fromSeed([UInt8](d)) { cache = kp; lock.unlock(); return kp }
        lock.unlock()
        // The seed of a newborn key is drawn with no lock in hand (19.09): the first draw of a
        // process gathers six sources, and a gather under a lock is a stalled thread (1614).
        var seed = [UInt8](repeating: 0, count: 64)
        guard mt_random_fast(&seed, 64) == 0, let kp = fromSeed(seed) else { return nil }
        lock.lock(); defer { lock.unlock() }   // LOCK-OK: the record is born as one step; a twin born meanwhile stands, this seed is dropped
        if let c = cache { return c }
        if let d = MontanaLocalVault.getDecrypted(vaultKey), d.count == 64,
           let twin = fromSeed([UInt8](d)) { cache = twin; return twin }
        guard MontanaLocalVault.setEncrypted(vaultKey, Data(seed)) else { return nil }
        cache = kp
        return kp
    }

    static func forget() {
        lock.lock(); defer { lock.unlock() }   // LOCK-OK: the cache and the record forget as one step — a reader between them would revive the old identity
        cache = nil
        UserDefaults.standard.removeObject(forKey: vaultKey)
    }

    private static func fromSeed(_ seed: [UInt8]) -> (pk: [UInt8], sk: [UInt8])? {
        var pk = [UInt8](repeating: 0, count: 1184), sk = [UInt8](repeating: 0, count: 2400)
        guard seed.count == 64, mt_mlkem_keypair_from_seed(seed, &pk, &sk) == 0 else { return nil }
        return (pk, sk)
    }
}
