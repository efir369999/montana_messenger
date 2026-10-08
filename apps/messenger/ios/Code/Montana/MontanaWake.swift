import Foundation
import MontanaBindings

/// Waking a sleeping device.
///
/// A letter waits at its holder while the device it belongs to sleeps, and waiting is the whole of
/// the mechanism until something wakes that device. What wakes it is a rung, and the rungs are
/// ordered by how little they depend on anyone outside the network — the set states all four and
/// their two shapes on the wire.
///
/// The first three carry the queue itself and reach the device without anyone outside the network
/// learning of it. The fourth carries an opaque handle and belongs to the vendor of an operating
/// system; a second implementation of Montana cannot enter that node with its own key, so it is an
/// accelerator inside one implementation and never a step of the network. This client builds the
/// three that are the network's own.
enum MontanaWake {

    /// Which rung stands right now. The choice is made here, by the machine holding the letter, and
    /// never travels on the wire.
    enum Rung: UInt8 {
        case liveTunnel = 1     // a channel the device already holds
        case beaconHome = 2     // a machine standing where the device sleeps
        case unlockSync = 3     // the moment a person unlocks another device of their own
        case pushGateway = 4    // the vendor's notification service — an accelerator, not a step

        /// The first three carry the queue; the fourth never does.
        var carriesQueue: Bool { self != .pushGateway }
    }

    static func rung(liveTunnel: Bool, beaconHome: Bool, unlockSync: Bool) -> Rung {
        Rung(rawValue: mt_wake_select_rung(liveTunnel, beaconHome, unlockSync)) ?? .pushGateway
    }

    /// The mark that says "this is a wake" outright. Recognising a wake by its LENGTH would swallow
    /// any piece that happened to be forty bytes long, and a lost piece is worse than a missed wake.
    static let mark = Data("mt-wake".utf8)   // LOCAL-HASH-OK: a frame mark, not a composition of the set

    /// The shape the first three rungs carry: the queue and the window it waits for, forty bytes.
    /// The core lays it out, so a second implementation reading the set produces the same bytes.
    /// The queue is thirty-two bytes. A point of rendezvous is sixteen, and it is NOT stretched to
    /// fit: it is named as itself, so nothing of the set is bent to pass through a shape it does not
    /// belong to.
    static func inlineFrame(queue: Data, window: UInt64) -> Data? {
        guard queue.count == 32 else { return nil }
        var out = [UInt8](repeating: 0, count: 40)
        let ok = queue.withUnsafeBytes { q -> Bool in
            guard let qb = q.bindMemory(to: UInt8.self).baseAddress else { return false }
            return mt_wake_inline_encode(qb, window, &out)
        }
        return ok ? mark + Data(out) : nil
    }

    static func readInline(_ frame: Data) -> (queue: Data, window: UInt64)? {
        guard frame.count == mark.count + 40, frame.prefix(mark.count) == mark else { return nil }
        let body = frame.dropFirst(mark.count)
        var q = [UInt8](repeating: 0, count: 32)
        var w: UInt64 = 0
        let ok = body.withUnsafeBytes { f -> Bool in
            guard let fb = f.bindMemory(to: UInt8.self).baseAddress else { return false }
            return mt_wake_inline_decode(fb, body.count, &q, &w)
        }
        return ok ? (Data(q), w) : nil
    }

    /// Waking someone toward a point of rendezvous. The point is carried as a point — sixteen bytes
    /// under its own mark — and never dressed up as a queue.
    static let pointMark = Data("mt-wake-point".utf8)   // LOCAL-HASH-OK: a frame mark, not a composition of the set

    static func pointFrame(point: Data, window: UInt64) -> Data? {
        guard point.count == 16 else { return nil }
        var w = window.littleEndian
        var out = pointMark + point
        withUnsafeBytes(of: &w) { out.append(contentsOf: $0) }
        return out
    }

    static func readPoint(_ frame: Data) -> (point: Data, window: UInt64)? {
        guard frame.count == pointMark.count + 24, frame.prefix(pointMark.count) == pointMark else { return nil }
        let body = frame.dropFirst(pointMark.count)
        let point = body.prefix(16)
        let w = body.suffix(8).withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }
        return (Data(point), UInt64(littleEndian: w))
    }

    /// Wake a sleeping correspondent over the rungs this network owns. A wake carries no content,
    /// no sender and no name — only which queue holds something and for which window.
    @discardableResult
    static func wake(_ ref: String, queue: Data, window: UInt64) -> Rung {
        let live = MontanaPhoneNode.shared.canReach(ref)
        let chosen = rung(liveTunnel: live, beaconHome: false, unlockSync: false)
        guard chosen.carriesQueue, let frame = inlineFrame(queue: queue, window: window) else {
            // The fourth rung is not built here: its node answers only to the key of one publisher,
            // and a step of the network cannot depend on that. The letter waits until the device
            // wakes on its own, and the delivery is the same delivery.
            MontanaLog.event("WAKE → \(ref.prefix(10)) waits: no rung of the network stands")
            return .pushGateway
        }
        let sent = MontanaPhoneNode.shared.sendBlobDirect(to: ref, blobId: MontanaMedia.blobIdHex(frame), sealed: frame)
        MontanaLog.event("WAKE → \(ref.prefix(10)) rung=\(chosen.rawValue) sent=\(sent)")
        return chosen
    }

    /// A device that holds a name listens at the point strangers knock on for the current window.
    static func listenForKnocks(masterSeed: Data) {
        let w = MontanaRendezvous.window()
        guard let point = MontanaNames.knockPoint(masterSeed: masterSeed, window: w) else { return }
        MontanaTrace.mark("knock_listen", mid: nil,
                             "point=\(point.prefix(4).map { String(format: "%02x", $0) }.joined()) window=\(w)")
    }
}
