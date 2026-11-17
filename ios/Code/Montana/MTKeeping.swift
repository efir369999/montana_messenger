import Foundation
import CryptoKit
import SwiftUI
import UIKit
import MontanaBindings

// THE COPY KEPT BY THE PEOPLE ONE WRITES TO (the author's words 08.10.2026, 16:2x-17:3x UTC: «restore by the words fully, byte
// for byte», «restore over the network from the phones, as it should be», «the orchestra builds the restore by the contacts, in
// their nodes, their phones», «build it»). The set states it -- Network «A copy kept by the people one speaks with», Canon «The
// keeping of a copy» -- and this file is its one owner on the phone.
//
// The copy is the one MontanaBackup seals under the words. It is cut and coded by the erasure code of a delivery; the keeper at
// slot k -- a correspondent whose person allows keeping -- holds cell p of every group for which p mod n = k, beside the head of
// its share, the seal of that head under a branch of the words it never sees, and the secret of its slot. A phone that opens the
// words derives the secret of every slot, calls in each pipe, checks every seal and builds the copy back. Every road here is one
// a letter already rides: the keeping words ride the correspondence, the parts ride the cargo road, and a call and its answer
// ride the box of a pipe.

/// THE ERASURE CODE OF A DELIVERY, as Canon states it: Reed-Solomon over the field of 256 elements with the modulus 0x11D, the
/// Cauchy matrix cauchy[i][j] = inverse((erasure_data + i) XOR j), the body blocks first and the parity after them. The set keeps
/// one code; the vectors below are the Canon's own, and the keeping refuses to start on a phone where they fail.
enum MTKeepCode {
    static let chunkBytes = 868   // Canon: chunk_bytes
    static let group = 16         // Canon: erasure_group
    static let data = 12          // Canon: erasure_data
    static let parityCount = group - data

    /// A product in the field without a branch on either operand, the core's own form (mt-wire, erasure.rs).
    static func mul(_ a: UInt8, _ b: UInt8) -> UInt8 {
        var product: UInt8 = 0, left = a, right = b
        for _ in 0..<8 {
            product ^= left & (0 &- (right & 1))
            let over: UInt8 = 0 &- (left >> 7)
            left = (left << 1) ^ (0x1D & over)
            right >>= 1
        }
        return product
    }
    /// The whole table of the field, walked once: a product is then one read of 64 KiB.
    static let table: [UInt8] = {
        var t = [UInt8](repeating: 0, count: 65536)
        for a in 0..<256 { for b in 0..<256 { t[(a << 8) | b] = mul(UInt8(a), UInt8(b)) } }
        return t
    }()
    static func inverse(_ a: UInt8) -> UInt8? {
        guard a != 0 else { return nil }
        for b in 1...255 where table[(Int(a) << 8) | b] == 1 { return UInt8(b) }
        return nil
    }
    static let cauchy: [[UInt8]] = (0..<parityCount).map { i in (0..<data).map { j in inverse(UInt8((data + i) ^ j)) ?? 0 } }

    /// The parity blocks of one group: every body block scaled by its coefficient and summed, byte by byte.
    static func parity(_ blocks: [[UInt8]]) -> [[UInt8]]? {
        guard blocks.count == data, let width = blocks.first?.count, blocks.allSatisfy({ $0.count == width }) else { return nil }
        var out = [[UInt8]](repeating: [UInt8](repeating: 0, count: width), count: parityCount)
        table.withUnsafeBufferPointer { t in
            for i in 0..<parityCount {
                out[i].withUnsafeMutableBufferPointer { o in
                    for j in 0..<data {
                        let row = Int(cauchy[i][j]) << 8
                        blocks[j].withUnsafeBufferPointer { b in
                            for x in 0..<width { o[x] ^= t[row | Int(b[x])] }
                        }
                    }
                }
            }
        }
        return out
    }

    /// Any twelve cells of a group give its twelve body blocks, and no fewer: the rows they stand for are inverted in the field
    /// and applied to what they carry. Twelve body cells in hand are the body itself, and nothing is computed.
    static func reconstruct(_ present: [(Int, [UInt8])]) -> [[UInt8]]? {
        var seen = Set<Int>()
        var taken: [(Int, [UInt8])] = []
        for (p, b) in present where (0..<group).contains(p) && seen.insert(p).inserted {
            taken.append((p, b))
            if taken.count == data { break }
        }
        guard taken.count == data, let width = taken.first?.1.count, taken.allSatisfy({ $0.1.count == width }) else { return nil }
        if taken.allSatisfy({ $0.0 < data }) {
            var out = [[UInt8]](repeating: [], count: data)
            for (p, b) in taken { out[p] = b }
            return out
        }
        var m: [[UInt8]] = taken.map { (p, _) in p < data ? (0..<data).map { $0 == p ? 1 : 0 } : cauchy[p - data] }
        var inv: [[UInt8]] = (0..<data).map { r in (0..<data).map { $0 == r ? 1 : 0 } }
        for col in 0..<data {
            guard let piv = (col..<data).first(where: { m[$0][col] != 0 }), let iv = inverse(m[piv][col]) else { return nil }
            m.swapAt(col, piv); inv.swapAt(col, piv)
            let s = Int(iv) << 8
            for x in 0..<data { m[col][x] = table[s | Int(m[col][x])]; inv[col][x] = table[s | Int(inv[col][x])] }
            for r in 0..<data where r != col && m[r][col] != 0 {
                let f = Int(m[r][col]) << 8
                for x in 0..<data { m[r][x] ^= table[f | Int(m[col][x])]; inv[r][x] ^= table[f | Int(inv[col][x])] }
            }
        }
        var out = [[UInt8]](repeating: [UInt8](repeating: 0, count: width), count: data)
        table.withUnsafeBufferPointer { t in
            for i in 0..<data {
                out[i].withUnsafeMutableBufferPointer { o in
                    for j in 0..<data where inv[i][j] != 0 {
                        let row = Int(inv[i][j]) << 8
                        taken[j].1.withUnsafeBufferPointer { b in for x in 0..<width { o[x] ^= t[row | Int(b[x])] } }
                    }
                }
            }
        }
        return out
    }

    /// THE CANON'S VECTORS OF THE WIRE, and one walk the frozen bytes cannot make alone: the body of the vector is twelve
    /// repeated bytes, so a second body of counting bytes is rebuilt across a loss that takes three parity cells and one body
    /// cell -- a matrix written in another order, or rows taken for the wrong positions, rebuilds neither.
    static func agreesWithCanon() -> Bool {
        let body: [[UInt8]] = (0..<data).map { [UInt8](repeating: UInt8(0xA0 + $0), count: chunkBytes) }
        guard let par = parity(body) else { return false }
        guard par.map({ $0.prefix(4).map { String(format: "%02x", $0) }.joined() }) == ["a5a5a5a5", "acacacac", "b7b7b7b7", "bebebebe"] else { return false }
        var h = SHA256()
        for p in par { h.update(data: Data(p)) }
        guard Data(h.finalize()).montanaHexString == "8963024273fc41fdf9afe063f3be77e7fbc312a7d8ede4f96a7fd99dd4fd0e69" else { return false }
        let lost: Set<Int> = [0, 5, 7, 11]
        let whole = body + par
        guard reconstruct(whole.enumerated().filter { !lost.contains($0.offset) }.map { ($0.offset, $0.element) }) == body else { return false }
        let counting: [[UInt8]] = (0..<data).map { j in (0..<64).map { UInt8((j * 64 + $0) % 251) } }
        guard let countingParity = parity(counting) else { return false }
        let loss: Set<Int> = [3, 12, 13, 15]
        return reconstruct((counting + countingParity).enumerated().filter { !loss.contains($0.offset) }.map { ($0.offset, $0.element) }) == counting
    }

    /// THE CUT (Canon «The keeping of a copy»): the container is cut into blocks of chunk_bytes, grouped twelve at a time, every
    /// group coded into sixteen cells, and cell p of every group laid into the share of slot p mod n, ascending. Streamed one
    /// group at a time: a copy of gigabytes never stands whole in memory.
    struct Cut { let length: UInt64; let digest: Data; let shares: [URL]; let shareDigests: [Data] }
    static func cut(_ container: URL, n: Int, into dir: URL) -> Cut? {
        guard [4, 8, 16].contains(n), let fh = try? FileHandle(forReadingFrom: container) else { return nil }
        defer { try? fh.close() }
        let fm = FileManager.default
        let shares = (0..<n).map { _ in dir.appendingPathComponent(UUID().uuidString + ".keep") }
        var outs: [FileHandle] = []
        for u in shares {
            guard fm.createFile(atPath: u.path, contents: nil), let o = try? FileHandle(forWritingTo: u) else {
                for o in outs { try? o.close() }
                for u in shares { try? fm.removeItem(at: u) }
                return nil
            }
            outs.append(o)
        }
        var whole = SHA256()
        var digests = [SHA256](repeating: SHA256(), count: n)
        var length: UInt64 = 0
        var ok = true
        while ok {
            let more: Bool = autoreleasepool {
                guard let d = try? fh.read(upToCount: data * chunkBytes), !d.isEmpty else { return false }
                whole.update(data: d)
                length += UInt64(d.count)
                var blocks: [[UInt8]] = []
                for j in 0..<data {
                    var b = [UInt8](repeating: 0, count: chunkBytes)
                    let lo = j * chunkBytes
                    if lo < d.count {
                        let piece = [UInt8](d[(d.startIndex + lo) ..< (d.startIndex + min(d.count, lo + chunkBytes))])
                        b.replaceSubrange(0..<piece.count, with: piece)
                    }
                    blocks.append(b)
                }
                guard let par = parity(blocks) else { ok = false; return false }
                let cells = blocks + par
                for p in 0..<group {
                    let cell = Data(cells[p])
                    do { try outs[p % n].write(contentsOf: cell) } catch { ok = false; return false }
                    digests[p % n].update(data: cell)
                }
                return d.count == data * chunkBytes
            }
            if !more { break }
        }
        for o in outs { try? o.close() }
        guard ok, length > 0 else { for u in shares { try? fm.removeItem(at: u) }; return nil }
        return Cut(length: length, digest: Data(whole.finalize()), shares: shares, shareDigests: digests.map { Data($0.finalize()) })
    }

    /// THE COPY BUILT BACK from the shares in hand: for every group, the cells of each share are read where the rule of positions
    /// laid them, any twelve rebuild the body, and the last group is cut at the container's own length. False when a group cannot
    /// stand -- a container with a hole in it is never laid.
    static func rebuild(_ parts: [(slot: Int, n: Int, url: URL)], length: UInt64, into dest: URL) -> Bool {
        guard let n = parts.first?.n, [4, 8, 16].contains(n), parts.allSatisfy({ $0.n == n }), length > 0 else { return false }
        let per = group / n
        let blocks = (length + UInt64(chunkBytes) - 1) / UInt64(chunkBytes)
        let groups = Int((blocks + UInt64(data) - 1) / UInt64(data))
        let fm = FileManager.default
        var ins: [(slot: Int, fh: FileHandle)] = []
        for p in parts { if let fh = try? FileHandle(forReadingFrom: p.url) { ins.append((p.slot, fh)) } }
        defer { for i in ins { try? i.fh.close() } }
        guard fm.createFile(atPath: dest.path, contents: nil), let out = try? FileHandle(forWritingTo: dest) else { return false }
        var written: UInt64 = 0
        var fine = true
        for g in 0..<groups where fine {
            fine = autoreleasepool {
                var present: [(Int, [UInt8])] = []
                for i in ins {
                    guard (try? i.fh.seek(toOffset: UInt64(g * per * chunkBytes))) != nil,
                          let d = try? i.fh.read(upToCount: per * chunkBytes), d.count == per * chunkBytes else { continue }
                    for c in 0..<per {
                        let lo = d.startIndex + c * chunkBytes
                        present.append((i.slot + c * n, [UInt8](d[lo ..< (lo + chunkBytes)])))
                    }
                }
                guard let body = reconstruct(present) else { return false }
                for b in body where written < length {
                    let take = Int(min(UInt64(chunkBytes), length - written))
                    do { try out.write(contentsOf: Data(b.prefix(take))) } catch { return false }
                    written += UInt64(take)
                }
                return true
            }
        }
        try? out.close()
        guard fine, written == length else { try? fm.removeItem(at: dest); return false }
        return true
    }
}

/// THE THREE QUANTITIES OF KEEPING, as Canon fixes them: the secret of a slot, the keeping key, and the seal of a share's head.
enum MTKeepDerive {
    static let slots = 16   // a group has sixteen cells: the slots of a copy (Canon: n is erasure_group)
    private static func expand(_ master: Data, _ info: [UInt8]) -> Data? {
        guard master.count == 64 else { return nil }
        var out = [UInt8](repeating: 0, count: 32)
        let rc = master.withUnsafeBytes { m -> Int32 in
            info.withUnsafeBufferPointer { i -> Int32 in
                guard let mb = m.bindMemory(to: UInt8.self).baseAddress, let ib = i.baseAddress else { return -1 }
                return mt_mldsa_seed_for_role(mb, ib, info.count, &out)   // HKDF-Expand(master_seed, info, 32): the branches' one road
            }
        }
        return rc == 0 ? Data(out) : nil
    }
    /// slot_secret(k) = HKDF-Expand(master_seed, "mt-keep-slot" || 0x00 || k_1B, 32)
    static func slotSecret(_ master: Data, _ k: Int) -> Data? {
        guard (0..<slots).contains(k) else { return nil }
        return expand(master, Array("mt-keep-slot".utf8) + [0, UInt8(k)])
    }
    /// keep_key = HKDF-Expand(master_seed, "mt-keep-key", 32): it seals every head and is handed to nobody.
    static func keepKey(_ master: Data) -> Data? { expand(master, Array("mt-keep-key".utf8)) }
    /// light_secret = HKDF-Expand(master_seed, "mt-keep-light", 32): the pipe of light, the owner's alone, in which the road of
    /// the light copy is named.
    static func lightSecret(_ master: Data) -> Data? { expand(master, Array("mt-keep-light".utf8)) }

    /// head = k_1B || n_1B || generation_8B_LE || length_8B_LE || SHA-256(container) || SHA-256(share): eighty-two bytes.
    struct Head: Equatable {
        var slot: Int, n: Int, generation: UInt64, length: UInt64, copyDigest: Data, shareDigest: Data
        static let bytesCount = 82
        var bytes: Data {
            var d = Data([UInt8(slot), UInt8(n)])
            d.append(Self.le(generation)); d.append(Self.le(length)); d.append(copyDigest); d.append(shareDigest)
            return d
        }
        init(slot: Int, n: Int, generation: UInt64, length: UInt64, copyDigest: Data, shareDigest: Data) {
            self.slot = slot; self.n = n; self.generation = generation; self.length = length
            self.copyDigest = copyDigest; self.shareDigest = shareDigest
        }
        init?(_ d: Data) {
            guard d.count == Self.bytesCount else { return nil }
            let b = [UInt8](d)
            func u64(_ at: Int) -> UInt64 { (0..<8).reduce(UInt64(0)) { $0 | (UInt64(b[at + $1]) << (8 * $1)) } }
            guard [4, 8, 16].contains(Int(b[1])), Int(b[0]) < Int(b[1]) else { return nil }
            slot = Int(b[0]); n = Int(b[1]); generation = u64(2); length = u64(10)
            copyDigest = Data(b[18..<50]); shareDigest = Data(b[50..<82])
        }
        private static func le(_ v: UInt64) -> Data { var x = v.littleEndian; return withUnsafeBytes(of: &x) { Data($0) } }
    }
    /// seal = SHA-256("mt-keep-seal" || 0x00 || keep_key || head), by the set's one composition.
    static func seal(_ key: Data, _ head: Head) -> Data { MTPipe.domained("mt-keep-seal", [key, head.bytes]) }

    /// THE CANON'S VECTORS OF KEEPING, from the master seed of sixty-four distinct bytes. What they reject is named in the set: a
    /// slot written as eight bytes, a missing NUL, a seed read backwards, integers written big-endian, the slot and n exchanged.
    static func agreesWithCanon() -> Bool {
        let master = Data((0..<64).map { UInt8($0) })
        guard slotSecret(master, 0)?.montanaHexString == "f57057fdd34a297a072f161d54105f98ec23cbbaf6229662b36efb9ae4aaa9d7",
              slotSecret(master, 1)?.montanaHexString == "c534306aa283d19c8e83f392bda37a7e59b7ccd7868b8df455bb9b6716e1ab91",
              slotSecret(master, 15)?.montanaHexString == "4573fb5ad5dc3b579049f304cc95cf5f3765ceaf07caab730d986c034788edab",
              let s3 = slotSecret(master, 3), MTPipe.tag(sharedSecret: s3, window: 1000).montanaHexString == "ae67484d6abdb555a43159fc9386d753",
              let key = keepKey(master), key.montanaHexString == "9945bec54d8f26ab7859b3e6eb886456ff529fd2637aa2650626b3595e88970c" else { return false }
        let head = Head(slot: 2, n: 8, generation: 0x1112131415161718, length: 0x0102030405060708,
                        copyDigest: Data((0x20...0x3F).map { UInt8($0) }), shareDigest: Data((0x40...0x5F).map { UInt8($0) }))
        // The light secret over the counting seed and over the same seed read backwards: an implementation reading the seed
        // backwards gives each the other's value.
        let backwards = Data(master.reversed())
        guard let light = lightSecret(master), light.montanaHexString == "23d9bfa1a0151598ea710a15492cb9f8fcb46e5c86d39ba0e8824a69511a3776",
              lightSecret(backwards)?.montanaHexString == "8d14528b640e1d7b114c2d299cf85f4ba7813a2308255dfba6025f01e4f288b9",
              MTPipe.tag(sharedSecret: light, window: 1000).montanaHexString == "7b957934998d5c0ad69415e43616020c" else { return false }
        return Head(head.bytes) == head
            && seal(key, head).montanaHexString == "80b0b97f66a8ef64fce6d692935a82b37bf978c0e215cd8b190bb7a1100475ae"
    }
}

/// THE KEEPING ON THIS PHONE, its three sides in one owner: the owner's (my copy with the people I write to), the keeper's (the
/// parts this phone holds for them), and the side of a phone that opens the words (the copy taken back). One token of the one
/// vocabulary of service words, keepMark, JSON with «w»: «ask», «yes», «part», «held» and «release» ride the correspondence of
/// the owner and the keeper, «back» and «given» the correspondence of a person and anyone they write to; «call» and «answer»
/// ride the pipe of a slot.
@MainActor final class MTKeeping: ObservableObject {
    static let shared = MTKeeping()

    // ── the person's choices, settings of this device (SeedScope.settingKeys) ──
    nonisolated static let mineKey = "mt.keep.mine"           // NOT-UI: my copy is kept by the people I write to
    nonisolated static let othersKey = "mt.keep.others"       // NOT-UI: this phone keeps parts for the people who write to me
    nonisolated static let budgetKey = "mt.keep.budget.mb"    // NOT-UI: what this phone keeps for others, in megabytes
    /// ON BY DEFAULT, ASKED AT THE OPENING (the author's word 08.10.2026 20:2x UTC: «on by default, and a question at the
    /// opening; when it is off, a crossed glyph like the muted sound, with the way to the settings»). Nothing leaves before the
    /// person has been told what each keeper learns (App: «before a person keeps a copy with correspondents, they are told»):
    /// the question at the opening, or the switch in Data and Storage under its own explanation, is that telling.
    static var mine: Bool { UserDefaults.standard.object(forKey: mineKey) as? Bool ?? true }
    nonisolated static let toldKey = "mt.keep.mine.told"   // NOT-UI: the person was told and chose
    static var told: Bool { UserDefaults.standard.bool(forKey: toldKey) }
    /// The crossed glyph in the bar's first slot: the person chose to keep no copy with their contacts.
    var offShown: Bool { Self.told && !Self.mine }
    /// The answer to the question at the opening.
    func answer(keep: Bool) {
        UserDefaults.standard.set(true, forKey: Self.toldKey)
        setMine(keep)
    }
    static var others: Bool { UserDefaults.standard.object(forKey: othersKey) as? Bool ?? true }
    static var budget: Int { (UserDefaults.standard.object(forKey: budgetKey) as? Int ?? 1024) * 1_048_576 }
    /// The names a slot's pipe is heard under in the box: never a conversation of the feed.
    nonisolated static let pipePrefix = "keep:"   // NOT-UI: the pipe of a slot this phone holds
    nonisolated static let callPrefix = "kslot:"  // NOT-UI: the pipes a phone opening the words calls in
    /// The keeping starts only where the Canon's vectors hold: a code or a derivation off by one byte would scatter parts nobody
    /// can rebuild.
    nonisolated static let agrees: Bool = MTKeepCode.agreesWithCanon() && MTKeepDerive.agreesWithCanon() && MTKeepRing.agrees()

    // ── the owner's side ──
    /// A keeper of the ring holds the slots of its position and of the next (MTKeepRing); a keeper of an older build held one.
    struct Keeper: Codable, Equatable { var slot: Int; var held: Bool; var slots: [Int]? = nil; var heldSlots: [Int]? = nil }
    struct Owner: Codable, Equatable {
        var generation: UInt64 = 0                 // the copy the keepers hold
        var asking: UInt64? = nil                  // a renewal asking for keepers
        var askedAt: Double = 0
        var yes: [String] = []                     // who said yes to it, in the order they said it
        var n = 0
        var keepers: [String: Keeper] = [:]
        var renewedAt: Double = 0
        var short = false                          // the last asking found nobody
        var lightGen: UInt64? = nil                // the light copy last named in the pipe of light
        var lightAt: Double? = nil
        /// THE ATTEMPT IS THE MOMENT THE RHYTHM COUNTS FROM (the author's words 18.10.2026 11:1x-11:4x UTC: «on T1 check why my
        /// phone heats up -- a deep closure at the root»; «at launch T1 lags at first»; «the chats lag»). Only a renewal that
        /// came to its end wrote renewedAt, so one refused on the way -- no room, the cut refused, a run killed while it laid its
        /// shares -- left the renewal due, and the next tick asked again: T1 began fourteen copies of its whole store on 17.10
        /// and four more by 11:00Z on 18.10, every one refused. A renewal or a light copy begun is one tried: the next waits the day.
        var triedAt: Double? = nil
        var lightTriedAt: Double? = nil
        /// THE PROFILE THE LIGHT COPY CARRIES (decision 866 a; OZ 1 p.2-3, the author's word 19993): the tags of one's own face and name
        /// when the copy was gathered. A copy laid at birth carried «Demo» without a face for a day: «Demo Akk» and the face never reached it.
        var lightFace: String? = nil
        var lightName: String? = nil
        /// THE PEOPLE THE LIGHT COPY CARRIES (decision 866 a): one digest of the correspondents' names and faces and of the groups.
        var lightPeople: String? = nil
        /// THE CARD'S SHAPE THE LIGHT COPY WAS LAID IN (OZ 1 p.3.5): a build whose card first carries the values' moments lays its
        /// light copy anew at once, so a device given an older value meets this one's moment and keeps the later.
        var lightEngine: Int? = nil
        /// THE ASKING A NEW ATTACHMENT MADE DUE (decision 872 = v, OZ 1 p.10.2): its copy goes on the battery (MontanaPower.bulkHeld).
        var urgent: Bool? = nil
        /// THE ROADS THIS PERSON LAID ON THE NODES (OZ 1, the author's words 23321 and 23332, 16.11.2026: «it cannot be that a week
        /// left so many pieces -- they are cleaned wrongly»; «fix the root so the system does not allow it»). Every generation laid
        /// sixteen shares anew -- 3.4 GB on T1, again ten minutes after a new attachment -- and nobody took the older ones off:
        /// one relay machine held 22 GB of them. The roads (the list's piece and its key) of the generation the keepers hold, and of the last
        /// two light copies, are kept here; a newer one takes the older off the nodes (unlay).
        var laid: [[String: String]]? = nil
        var lightLaid: [[String: String]]? = nil
    }
    private static let ownerKey = "mt.keep.owner"  // NOT-UI: sealed under the device key; the person's own (SeedScope.dataKeys)
    @Published private(set) var owner = Owner()

    // ── the keeper's side ──
    struct Held: Codable, Equatable {
        var slot: Int; var n: Int; var secret: Data; var head: Data; var seal: Data; var bytes: Int; var at: Double
        var answeredAt: Double = 0
        /// The owner's own road of this part on the nodes, and when it was laid: an answer within the pieces' week rides it
        /// whole, with nothing to send again -- a phone woken for seconds by a push answers in those seconds.
        var road: [String: String]? = nil
        var roadAt: Double? = nil
    }
    nonisolated private static let heldKey = "mt.keep.held"   // NOT-UI: this device's own (SeedScope.deviceKeys)
    @Published private(set) var held: [String: Held] = [:]

    // ── a phone that opened the words ──
    /// fetching: the light copy coming down from the nodes, its share of bytes -- set the moment the words open, so the page shows
    /// a bar from its first frame (the author's word 09.10.2026: «the progress bar must show at once, now it spins long before»).
    enum Taking: Equatable { case idle, fetching(Double), calling(have: Int, need: Int), laying(Double), done, failed }
    @Published fileprivate(set) var taking: Taking = .idle

    /// The first screen waits for the copy (MontanaOnboardingView.takeFromKeepers) until the person walks on without it.
    var onboardingWaits = false
    private var renewing = false
    private var lighting = false
    private var lightJoining = false   // a phone gave its words while a light copy was on its way: that copy holds for the joining
    /// The first screen lets the person in the moment the light copy is laid (App: «once the light copy is laid»).
    var onLight: (() -> Void)? = nil
    private var takingTask: Task<Void, Never>? = nil
    /// The light roads tried in this taking, by digest (a laid one, or an old one that did not come whole): never fetched again.
    private var lightSeen: Set<String> = []
    /// A light copy of another device laid in this taking: ten minutes without the phone's own let the person in with it.
    private var lightLaid = false
    /// What the phone's light copy laid in this taking: the tally a joined device's walk ends with.
    private var lightTally = MontanaBackup.Tally()
    private var roads: [String: (at: Double, road: [String: Any])] = [:]

    private init() {
        reread()
        // A renewal held for the charger (MontanaPower.bulkHeld) begins when the phone is put on it, not at the next launch.
        NotificationCenter.default.addObserver(forName: UIDevice.batteryStateDidChangeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in MTKeeping.shared.tickSoon() }
        }
        // One's own name or face changed (decision 866 a): the rhythm looks again in a minute, once for any number of changes.
        _ = peopleWatch
        // Heard on the writer's thread, never on .main: a write off main would wait for main (P-212, MTTwinSelf.watch).
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: nil) { _ in
            Task { @MainActor in MTKeeping.shared.profileSoon() }
        }
    }
    private var profilePending = false
    func profileSoon() {
        guard !profilePending else { return }
        profilePending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in self?.profilePending = false; self?.tick() }
    }
    /// The people are not in UserDefaults: while the app lives, the rhythm looks at them every ten minutes (decision 866 a).
    private lazy var peopleWatch: Timer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { _ in
        Task { @MainActor in MTKeeping.shared.tick() }
    }
    /// What the vault holds, read again: at launch, and after a copy laid this person's state of keeping.
    func reread() {
        if let d = MontanaLocalVault.getDecrypted(Self.ownerKey), let o = try? JSONDecoder().decode(Owner.self, from: d) { owner = o } else { owner = Owner() }
        held = Self.heldNow()
    }
    private func saveOwner() { if let d = try? JSONEncoder().encode(owner) { MontanaLocalVault.setEncrypted(Self.ownerKey, d) } }
    private func saveHeld() { if let d = try? JSONEncoder().encode(held) { MontanaLocalVault.setEncrypted(Self.heldKey, d) } }
    nonisolated static func heldNow() -> [String: Held] {
        guard let d = MontanaLocalVault.getDecrypted(heldKey) else { return [:] }
        return (try? JSONDecoder().decode([String: Held].self, from: d)) ?? [:]
    }

    /// THE PARTS THIS PHONE KEEPS FOR OTHERS lie in a folder of their own, never in this person's copy and never in the vendor's
    /// backup: they are another person's, and they go back only to that person's words.
    nonisolated static var folder: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        var d = base.appendingPathComponent("MontanaKeeping", isDirectory: true)
        if !FileManager.default.fileExists(atPath: d.path) {
            try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true,
                                                     attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            var v = URLResourceValues(); v.isExcludedFromBackup = true; try? d.setResourceValues(v)
        }
        return d
    }
    nonisolated static func partURL(_ conv: String) -> URL? {
        guard let name = conv.addingPercentEncoding(withAllowedCharacters: .alphanumerics), !name.isEmpty else { return nil }
        return folder?.appendingPathComponent(name + ".keep")
    }

    // ── the words ──
    nonisolated static func word(_ text: String) -> [String: Any]? {
        guard text.hasPrefix(keepMark), let d = String(text.dropFirst(keepMark.count)).data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }
    /// The word's letter name, so a caller may wait for it to leave (releaseAllForDeletion).
    @discardableResult private func say(_ conv: String, _ o: [String: Any]) -> String? {
        guard let d = try? JSONSerialization.data(withJSONObject: o), let s = String(data: d, encoding: .utf8) else { return nil }
        let mid = UUID().uuidString
        MontanaDeliveryEngine.shared.enqueue(to: conv, chat: conv, mid: mid, text: keepMark + s, silent: true)
        return mid
    }
    /// A keeping word lives in the queue while it can still mean something: a question an hour (an older build buries it
    /// unread and never receipts it), every other word two days -- the pieces of a part live a week on the nodes.
    nonisolated static func expired(_ text: String, age: Double) -> Bool {
        guard text.hasPrefix(keepMark) else { return false }
        return age > ((word(text)?["w"] as? String) == "ask" ? 3600 : 172_800)
    }
    /// A keeping word landed in a correspondence (ChatStore): never a row, answered here.
    func heard(_ text: String, from conv: String) {
        guard Self.agrees, let o = Self.word(text), let w = o["w"] as? String else { return }
        MontanaTrace.mark("keep_word", "w=" + w + " conv=" + String(conv.prefix(10)))
        switch w {
        case "ask": answerAsk(conv, o)
        case "yes": tookYes(conv, o)
        case "part": Task { await takePart(conv, o) }
        case "held": tookHeld(conv, o)
        case "release": drop(conv)
        case "back": Task { await answerBack(conv, o) }
        case "given": Task { await takeGiven(conv, o) }
        default: break
        }
    }

    // ── the owner ──
    func setMine(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Self.mineKey)
        UserDefaults.standard.set(true, forKey: Self.toldKey)   // the switch stands under its own explanation
        objectWillChange.send()
        if on {
            owner.renewedAt = 0; owner.triedAt = nil; saveOwner(); tick()
        } else {
            for conv in owner.keepers.keys { say(conv, ["w": "release"]) }
            let gone = (owner.laid ?? []) + (owner.lightLaid ?? [])
            owner = Owner(generation: owner.generation); saveOwner()
            Task.detached(priority: .utility) { await Self.unlay(gone) }   // no copy kept: its pieces leave the nodes too
        }
    }
    /// THE ACCOUNT LEAVES, ITS PARTS LEAVE WITH IT (Guideline 5.1.1(v); the author's decision (a), 10.11.2026: «Delete account»
    /// erases the history, takes the parts back from the keepers and removes the iCloud copy). Every keeper is told «release» and
    /// drops my part (heard, drop); the words are waited for while they are still in the queue, `within` seconds at most, because
    /// the queue leaves with the seed. A keeper who is away keeps a sealed part nothing but these 24 words can open -- the alert says so.
    func releaseAllForDeletion(within: Double) async {
        let mids = Set(owner.keepers.keys.compactMap { say($0, ["w": "release"]) })
        let gone = (owner.laid ?? []) + (owner.lightLaid ?? [])
        owner = Owner(generation: owner.generation); saveOwner()
        await Self.unlay(gone)
        UserDefaults.standard.set(false, forKey: Self.mineKey)
        objectWillChange.send()
        MontanaTrace.mark("keep_release_all", "keepers=\(mids.count)")
        let until = Date().addingTimeInterval(within)
        while Date() < until, await MontanaDeliveryEngine.shared.stillQueued(mids) {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        let left = await MontanaDeliveryEngine.shared.stillQueued(mids)
        MontanaTrace.mark("keep_release_all", left ? "some words still wait: their keepers are away" : "every keeper was told")
    }
    /// THE OWNER'S RHYTHM: a renewal is due a day after the last; it asks the people I write to, waits ten minutes for one yes
    /// at least (a full ring goes at once), and an hour without one leaves the copy where it stands until tomorrow.
    func tickSoon() { DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in self?.tick() } }
    func tick() {
        guard Self.mine, Self.told, Self.agrees, MontanaSeed.hasSeed else { return }
        let now = Date().timeIntervalSince1970
        let tags = Self.profileTags()
        let moved = owner.lightFace != tags.face || owner.lightName != tags.name || owner.lightEngine != MontanaBackup.cardEngine
        let since = now - max(owner.lightAt ?? 0, owner.lightTriedAt ?? 0)
        let people = Self.peopleTag()
        let met = owner.lightPeople != people
        // A JOINED DEVICE NAMES NO COPY WHILE IT TAKES ONE, NOR ONE WITHOUT A CHAT (decision 989 = a): the Mac named its empty copy,
        // 127 MB without a chat, three times in seven minutes while the phone's was coming (16.11), and filled the doors with it.
        let named = MTLinkedDevices.joinedPhone == nil || (!isTaking && !(ChatStore.live?.messages.isEmpty ?? true))
        if !lighting, named, since >= 86_400 || (moved && since >= 60) || (met && since >= 600) {
            layLight(tags, people: people)   // one's own name or face: a minute; the people and the groups: ten minutes
        }
        guard !renewing else { return }
        if let g = owner.asking {
            if owner.yes.count >= MTKeepRing.most || (!owner.yes.isEmpty && now - owner.askedAt >= 600) { return renew(g) }
            if now - owner.askedAt >= 3600 {
                owner.short = true; owner.asking = nil; owner.yes = []; owner.renewedAt = now; saveOwner()
                return MontanaTrace.mark("keep_ask", "nobody said yes in an hour")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 120) { [weak self] in self?.tick() }
            return
        }
        let fresh = attachmentDue(now)
        guard fresh || now - max(owner.renewedAt, owner.triedAt ?? 0) >= 86_400 else { return }
        if let why = MontanaPower.bulkHeld(onBattery: fresh) { return MontanaTrace.markChanged("keep_ask", "held: " + why + " -- the copy waits") }
        owner.urgent = fresh ? true : nil
        ask()
    }
    /// THE FULL COPY FOLLOWS A NEW ATTACHMENT (decision 872 = v, OZ 1 p.10.2): the gif of 11.11.2026 19:21 UTC never reached the
    /// restored iPad -- T1 laid no copy with it, its renewal waited the day and the charger. A letter whose attachment is newer
    /// than the last copy asked or tried makes the copy due at once, ten minutes after that one at the least, so a run of
    /// photos folds into one copy; the rhythm looks every ten minutes while the app lives (peopleWatch).
    private func attachmentDue(_ now: Double) -> Bool {
        let last = max(owner.renewedAt, owner.triedAt ?? 0, owner.askedAt)
        guard now - last >= 600, let store = ChatStore.live else { return false }
        return store.messages.values.contains { rows in (rows.last { r in r.attachment != nil }?.createdAt ?? 0) > last }
    }
    private func ask() {
        let people = candidates()
        let now = Date().timeIntervalSince1970
        guard !people.isEmpty else {
            owner.short = true; owner.renewedAt = now; saveOwner()
            return MontanaTrace.mark("keep_ask", "people=0: nobody to ask")
        }
        let g = owner.generation + 1
        owner.asking = g; owner.askedAt = now; owner.yes = []; saveOwner()
        for conv in people { say(conv, ["w": "ask", "g": Int(g)]) }
        MontanaTrace.mark("keep_ask", "g=\(g) people=\(people.count)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) { [weak self] in self?.tick() }
    }
    /// The people I write to, the latest first: a correspondence of a person -- never my own twin, a group, or someone I block.
    private func people() -> [String] {
        let twin = MontanaSeed.twin ?? ""
        let store = ChatStore.live
        let people = MTPipeBook.all().filter { $0 != twin && !MTGroup.isKey($0) && MontanaConv.holds($0) && !ChatStore.refusesNow($0) }
        let last: [String: Double] = Dictionary(uniqueKeysWithValues: people.map { ($0, store?.messages[$0]?.last?.createdAt ?? 0) })
        return people.sorted { (last[$0] ?? 0) > (last[$1] ?? 0) }
    }
    /// Those asked to keep: twice a full ring, so that the ring fills when some stay silent.
    private func candidates() -> [String] { Array(people().prefix(2 * MTKeepRing.most)) }
    private func tookYes(_ conv: String, _ o: [String: Any]) {
        guard let g = o["g"] as? Int, let a = owner.asking, UInt64(g) == a, !owner.yes.contains(conv) else { return }
        owner.yes.append(conv); saveOwner()
        if owner.yes.count >= MTKeepRing.most { renew(a) }
    }
    /// The keeper's own word: only this makes a part «held» on my screen (the rule of the external keeper).
    /// A keeper of the ring names the slot it holds, and is whole once it holds every slot of its place.
    private func tookHeld(_ conv: String, _ o: [String: Any]) {
        guard let g = o["g"] as? Int, UInt64(g) == owner.generation, var k = owner.keepers[conv] else { return }
        if let s = o["k"] as? Int {
            let have = Set(k.heldSlots ?? []).union([s])
            k.heldSlots = have.sorted()
            k.held = Set(k.slots ?? [k.slot]).isSubset(of: have)
        } else {
            k.held = true   // a keeper of an older build holds one part and names no slot
        }
        owner.keepers[conv] = k; saveOwner()
        MontanaTrace.mark("keep_held", "slot=\(o["k"] as? Int ?? k.slot) whole=\(k.held)")
    }
    private func renew(_ g: UInt64) {
        guard !owner.yes.isEmpty, !renewing else { return }
        let urgent = owner.urgent == true
        if let why = MontanaPower.bulkHeld(onBattery: urgent) {
            MontanaTrace.markChanged("keep_copy", "held: " + why + " -- the copy waits for the charger")
            DispatchQueue.main.asyncAfter(deadline: .now() + 300) { [weak self] in self?.tick() }
            return
        }
        renewing = true
        owner.asking = nil; owner.urgent = nil; owner.triedAt = Date().timeIntervalSince1970; saveOwner()
        // THE RING IN THE ORDER OF THE LATEST LETTER (Network): the people written to last stand first, a full ring at most.
        let rank: [String: Int] = Dictionary(people().enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        let chosen = Array(owner.yes.sorted { (rank[$0] ?? Int.max) < (rank[$1] ?? Int.max) }.prefix(MTKeepRing.most))
        CopyInventory.gather { inv in
            var scope = inv.scope(CopyPlan.load())
            scope.after = (MTKeepCode.group + 1, MTKeepCode.data)   // the shares, a third more, and the crates of one share as it is laid
            MontanaBackup.create(scope: scope, urgent: false) { r in
                let me = MTKeeping.shared
                switch r {
                case .failure(let e):
                    me.renewing = false
                    MontanaTrace.mark("keep_copy", "refused " + String(describing: e))
                case .success(let made):
                    Task { await me.hand(made, g: g, keepers: chosen, urgent: urgent) }
                }
            }
        }
    }
    /// THE COPY HANDED AROUND THE RING: cut at the sixteen slots of a group (Canon: n is erasure_group), every share laid on the
    /// nodes ONCE and its road handed to each keeper of its slot -- the ring costs the network a copy and a third, whatever the
    /// number of keepers.
    private func hand(_ made: MontanaBackup.Made, g: UInt64, keepers: [String], urgent: Bool) async {
        defer { MontanaBackup.discard(made); renewing = false }
        let n = MTKeepCode.group
        guard let master = MontanaSeed.root, let key = MTKeepDerive.keepKey(master),
              let dir = try? MontanaBackup.shelf() else { return }
        let url = made.url
        guard let cut = await Task.detached(priority: .utility, operation: { MTKeepCode.cut(url, n: n, into: dir) }).value else {
            return MontanaTrace.mark("keep_cut", "refused n=\(n)")
        }
        defer { for u in cut.shares { try? FileManager.default.removeItem(at: u) } }
        var roads: [Int: [String: Any]] = [:]
        var handed = false
        // A ROUND THAT DID NOT END TAKES ITS SHARES BACK: a share laid before the charger went away was nobody's road.
        defer { if !handed, !roads.isEmpty { let r = Self.roadsOf(Array(roads.values)); Task.detached(priority: .utility) { await Self.unlay(r) } } }
        for k in 0..<n {
            // The charger taken away (unless a new attachment made the copy due), the phone grown hot, a metered path: the rest
            // of the copy waits for the next renewal.
            if let why = MontanaPower.bulkHeld(onBattery: urgent) {
                return MontanaTrace.mark("keep_hand", "held at share \(k) of \(n): " + why + " -- the rest waits for the next renewal")
            }
            if let road = await Self.lay(cut.shares[k]) { roads[k] = road }
        }
        var sent: [String: Keeper] = [:]
        var parts = 0
        for (i, conv) in keepers.enumerated() {
            let slots = MTKeepRing.slots(place: i, of: keepers.count).filter { roads[$0] != nil }
            for k in slots {
                guard let secret = MTKeepDerive.slotSecret(master, k), let road = roads[k] else { continue }
                let head = MTKeepDerive.Head(slot: k, n: n, generation: g, length: cut.length, copyDigest: cut.digest, shareDigest: cut.shareDigests[k])
                var o: [String: Any] = ["w": "part", "k": k, "n": n, "s": secret.base64EncodedString(),
                                        "h": head.bytes.montanaHexString, "e": MTKeepDerive.seal(key, head).montanaHexString]
                for (a, b) in road { o[a] = b }
                say(conv, o)
                parts += 1
            }
            if let first = slots.first { sent[conv] = Keeper(slot: first, held: false, slots: slots, heldSlots: []) }
        }
        guard !sent.isEmpty else { return MontanaTrace.mark("keep_hand", "no part left the phone") }
        for conv in owner.keepers.keys where sent[conv] == nil { say(conv, ["w": "release"]) }
        let older = owner.laid ?? []
        handed = true
        owner.keepers = sent; owner.n = n; owner.generation = g; owner.yes = []; owner.short = false
        owner.renewedAt = Date().timeIntervalSince1970
        owner.laid = Self.roadsOf(Array(roads.values))
        saveOwner()
        Task.detached(priority: .utility) { await Self.unlay(older) }   // the generation before leaves the nodes
        MontanaTrace.mark("keep_hand", "g=\(g) keepers=\(sent.count) parts=\(parts) laid=\(roads.count) bytes=\(cut.length)")
    }

    // ── the light copy (Network «The light copy»; the author's word 08.10.2026 20:5x UTC: «the person, the face, the name and
    // everything else back by the words [...]») ──
    /// THE COPY WITHOUT ITS ATTACHMENTS -- every letter, every room, the profile, the faces and the head of every
    /// correspondence -- sealed as every copy is, laid on the nodes and named by one letter in the pipe of light, once a day while
    /// the copy is kept. The pieces live a week there and the letter in the box as long, so a phone lost today is opened by the
    /// words alone tomorrow.
    /// THE COPY IS A PICTURE ON THE MIRROR'S CURSOR (OZ 1 p.6): the cursors are read before the copy is gathered, so a word
    /// after them rides the mirror again and none falls between; a copy for a joining is sealed at once (urgent).
    private func layLight(_ tags: (face: String, name: String), people: String, joining: Bool = false) {
        guard !lighting else { return }
        lighting = true
        owner.lightTriedAt = Date().timeIntervalSince1970; saveOwner()
        let g = (owner.lightGen ?? 0) + 1
        MontanaArchive.copyCursors(holding: joining) { lc in Task { @MainActor in
            if joining { MontanaArchive.tellJoining(lc) }
            CopyInventory.gather { inv in
                var scope = inv.scope(CopyPlan.load())
                scope.skipKinds = Set(MontanaBackup.Kind.allCases)   // every letter, no attachment: the attachments come from the keepers
                scope.after = (1, 1)   // the crates the copy is sealed into as it is laid
                MontanaBackup.create(scope: scope, urgent: joining) { r in
                    let me = MTKeeping.shared
                    switch r {
                    case .failure(let e):
                        me.lighting = false
                        MontanaTrace.mark("keep_light", "refused " + String(describing: e))
                    case .success(let made):
                        Task { await me.nameLight(made, g: g, tags: tags, people: people, lc: lc, held: joining) }
                    }
                }
            }
        } }
    }
    /// THE COPY FOR A JOINING (decision 989 = a; the author's words 23015, 23019):
    /// the phone that gave its words names a light copy at once, whatever the day's rhythm -- the history has one owner at a joining,
    /// the phone, and the joined device waits for a copy named after the gift, never an old one the doors may have let go (the
    /// copy a day old was evicted by a node's full shelf, and the Mac found every door «gone»). A copy already on its way is
    /// named after the gift too.
    func lightForLink() {
        guard Self.agrees, MontanaSeed.hasSeed else { return }
        if lighting { lightJoining = true } else { layLight(Self.profileTags(), people: Self.peopleTag(), joining: true) }
        MontanaTrace.mark("keep_light", "for a joining")
    }
    /// One's own face and name as their tags -- the very tags a correspondent's word compares (E2E.heardHeld).
    static func profileTags() -> (face: String, name: String) {
        (MontanaDeliveryEngine.Announced.wireTag(E2E.myAvatarData()), MontanaDeliveryEngine.Announced.nameWireTag(E2E.myDisplayName()))
    }
    /// The correspondents' names and faces (MTNameBook, the mirrors of ChatStore) and the groups (MTGroup) as one digest:
    /// it moves when a person is met, a group is born, or someone shows a new name or face.
    static func peopleTag() -> String {
        let names = MTNameBook.declared.sorted { $0.key < $1.key }.map { $0.key + "=" + $0.value }
        let faces = MTNameBook.published.sorted { $0.key < $1.key }.map { $0.key + "=" + $0.value }
        let groups = MTGroup.shared.groups.keys.sorted()
        let all = (names + [""] + faces + [""] + groups).joined(separator: "\n")
        return SHA256.hash(data: Data(all.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private func nameLight(_ made: MontanaBackup.Made, g: UInt64, tags: (face: String, name: String), people: String,
                           lc: [String: Int], held: Bool) async {
        defer {
            MontanaBackup.discard(made); lighting = false
            if lightJoining, !held { MontanaArchive.tellJoining(lc, here: true) }   // a joining that came while this copy was on its way
            lightJoining = false
        }
        guard let master = MontanaSeed.root, let secret = MTKeepDerive.lightSecret(master),
              let digest = MontanaBackup.digest(of: made.url), var road = await Self.lay(made.url) else {
            return MontanaTrace.mark("keep_light", "the light copy did not reach the nodes")
        }
        road["w"] = "light"; road["g"] = Int(g); road["d"] = digest; road["v"] = MontanaArchive.writerTagHex()   // the device that laid it
        road["a"] = Bundle.main.bundleIdentifier ?? ""   // and the app on it: two apps of one phone are two writers of the same words
        road["at"] = Int(Date().timeIntervalSince1970)   // the moment it was named: a joined device waits for one named after its gift
        if !lc.isEmpty { road["lc"] = lc }   // the mirror's cursors the copy stands on: the joined device goes on from them (OZ 1 p.6)
        // The sender of the pipe of light is named «light», never this person's own reference: a phone opening the same words reads
        // the box under that reference, and a letter of its own name the node would keep from it.
        guard await Self.knock(secret, road, sender: Self.lightName) else { return MontanaTrace.mark("keep_light", "no door boxed the road") }
        owner.lightGen = g; owner.lightAt = Date().timeIntervalSince1970; owner.lightFace = tags.face; owner.lightName = tags.name; owner.lightPeople = people; owner.lightEngine = MontanaBackup.cardEngine
        // THE LAST TWO LIGHT COPIES STAY: a device in the middle of taking the one before still finds it whole.
        let lights = (owner.lightLaid ?? []) + Self.roadsOf([road])
        owner.lightLaid = Array(lights.suffix(2))
        saveOwner()
        let older = Array(lights.dropLast(2))
        if !older.isEmpty { Task.detached(priority: .utility) { await Self.unlay(older) } }
        MontanaTrace.mark("keep_light", "named g=\(g) bytes=\(made.tally.bytes) chats=\(made.tally.chats)")
    }
    nonisolated static let lightName = "light"   // NOT-UI: the name the pipe of light is heard and sent under
    /// THE LIGHT COPY TAKEN BACK: the pipe of light read, and the newest road OF EVERY DEVICE that names one there taken -- two
    /// devices of the same words count their generations each from one, so the highest number is no measure across them, and
    /// the poorer copy could stand in for the richer. Each is checked by its digest and laid, the largest first; a copy
    /// laid merges and erases nothing, so one laid after another adds only what it alone holds. The box keeps the letters: the
    /// next phone of the same words reads them too.
    /// ONE OWNER OF THE HISTORY AT A JOINING (decision 989 = a; the author's words 23015, 23019): on a device joined by QR the
    /// phone is that owner -- its copy named after the gift (lightForLink; two minutes of slack for the two clocks) is laid first
    /// and alone lets the person in, and the device's own copies are never taken back (the Mac took its own empty one, 16.11).
    /// On a phone that opened its words any copy is the owner's, and the first laid lets the person in. True once the owner's copy
    /// is laid. A road tried once is not fetched again (lightSeen) -- the phone's own fresh one alone, if it did not come whole.
    /// THE WORDS OPENED ON A NEW DEVICE TAKE ONE PICTURE, AS A JOINING BY QR DOES (the author's words 23891 and 23893, 16.11.2026:
    /// «in Bob's chat the texts doubled and the group's old face stayed»; «Alice's chat came back old by the words, not the last that
    /// is on T1 -- it must sync as the sign-in by QR does»). The demo identity's iPad laid another device's copy and then its own
    /// copy of an earlier life with the same words on top of it (keep_light own=true): 23 rows of that life came back into three
    /// chats, and the group's face with them. A device that opened its words now asks the seed's other devices for a picture of
    /// now (askTwinsLight, the word lw); `since` is that asking: only another device's copy named after it is taken, and it alone
    /// is the history. When none comes, the newest copy by its moment is the history, alone. No older picture is laid over the
    /// owner's -- it would bring back what the person deleted since. The owner's cursors are this device's own (cursorsFromCopy),
    /// so every letter after the picture comes from the books, as on a joined device.
    private func takeLight(_ secret: Data, dir: URL, phone: (tag: String, at: Double)?, since: Double? = nil) async -> Bool {
        var rows: [[String: String]] = []
        let ear = MontanaWakePush.BoxEar(invites: [], pipes: [Self.lightName: MTPipeKey(secret)], owner: MontanaSeed.twin ?? "")
        _ = await MontanaWakePush.pickup(ear, buries: nil, keep: { row in rows.append(row); return false })
        var newest: [String: [String: Any]] = [:]
        for o in rows.compactMap({ Self.word($0["t"] ?? "") }) where (o["w"] as? String) == "light" {
            // THE NEWEST ROAD OF EVERY WRITER, A DEVICE AND THE APP ON IT (09.10.2026): two apps of one phone and the same words
            // count their generations each from one, and one standing for both laid a copy without the other's profile (T1:
            // the name, the face and the page's ground stayed behind).
            let v = (o["v"] as? String ?? "") + "/" + (o["a"] as? String ?? "")
            if (newest[v]?["g"] as? Int ?? -1) <= (o["g"] as? Int ?? 0) { newest[v] = o }
        }
        let mine = MontanaArchive.writerTagHex()
        func fresh(_ o: [String: Any]) -> Bool {
            let at = Double(o["at"] as? Int ?? 0)
            if let phone { return (o["v"] as? String) == phone.tag && phone.at - 120 <= at }
            if let since { return (o["v"] as? String) != mine && since - 120 <= at }   // another device's picture named after the asking
            return true
        }
        let roads = newest.values.filter { o in
            guard let d = o["d"] as? String, !lightSeen.contains(d) else { return false }
            if phone != nil, (o["v"] as? String) == mine { return false }   // a joined device's own copy is never the history
            if phone == nil, since != nil, !fresh(o) { return false }   // words opened here wait for the picture of now
            return true
        }.sorted { a, b in
            if phone == nil, since == nil { return (b["at"] as? Int ?? 0) < (a["at"] as? Int ?? 0) }   // the newest picture first
            return fresh(a) == fresh(b) ? (b["z"] as? Int ?? 0) < (a["z"] as? Int ?? 0) : fresh(a)
        }
        guard !roads.isEmpty else {
            MontanaTrace.mark("keep_light", phone == nil ? "the pipe of light holds no road" : "no new road; the phone's copy is awaited")
            return false
        }
        var owned = false
        for road in roads {
            guard let d = road["d"] as? String else { continue }
            let url = dir.appendingPathComponent(UUID().uuidString + "." + MontanaBackup.ext)
            defer { try? FileManager.default.removeItem(at: url) }
            taking = .fetching(0)
            guard await Self.fetch(road, to: url, progress: { f in Task { @MainActor in MTKeeping.shared.taking = .fetching(f) } }),
                  MontanaBackup.digest(of: url) == d else {
                if !fresh(road) || (phone == nil && since == nil) { lightSeen.insert(d) }   // the fresh copy awaited is fetched again
                MontanaTrace.mark("keep_light", "a light copy did not come whole")
                continue
            }
            lightSeen.insert(d)
            taking = .laying(0)
            let r: Result<MontanaBackup.Tally, MontanaBackup.Refusal> = await withCheckedContinuation { c in
                MontanaBackup.restore(from: url, ofMany: true, progress: { f in Task { @MainActor in MTKeeping.shared.taking = .laying(f) } }) { c.resume(returning: $0) }
            }
            reread()
            let own = (road["v"] as? String) == mine   // this device's own copy, or another's
            MontanaTrace.mark("keep_light", "laid=\(String(describing: r)) devices=\(roads.count) own=\(own) phone=\(phone == nil ? "-" : fresh(road) ? "1" : "0") a=\(road["a"] as? String ?? "")")
            guard case .success(let tally) = r else { continue }
            lightLaid = true
            if fresh(road), !owned {
                owned = true; lightTally = tally; letIn()
                MontanaArchive.cursorsFromCopy(road["lc"] as? [String: Int] ?? [:])   // the same book from here, joined or opened (OZ 1 p.6)
                if phone == nil { break }   // words opened here: the owner's picture alone is the history
            }
        }
        return owned
    }
    /// The first screen lets the person in (onLight), once.
    private func letIn() { let l = onLight; onLight = nil; l?() }

    // ── the cargo road of a part ──
    /// A PART ON THE CARGO ROAD: sealed in pieces under a fresh key and put on the nodes, and its list of pieces sealed as one
    /// more piece -- the word that names a part carries that piece's name and key, never the list (a list outgrows a letter).
    /// The keeping's cargo is quiet (MontanaWakePush.quietCargo): the person's media coming in goes first, the copy after it.
    nonisolated static func lay(_ url: URL) async -> [String: Any]? {
        await MontanaWakePush.$quietCargo.withValue(true) { await layPieces(url) }
    }
    /// THE PERSON'S OWN FILE ON THE SAME ROAD, NOT QUIET (OZ 1 p.9, the author's word 23159: «in 2413 the media of Saved
    /// Messages still do not arrive»): a file laid in Saved Messages rides to the seed's other devices as the person's own put,
    /// and so do the mirror's words. Quiet, they stood in the service's places behind the keeping's copy -- the Mac,
    /// 16.11.2026 14:34 UTC: a copy of 253 pieces in line, and the photo's word waiting in memory for its file.
    nonisolated static func layOwn(_ url: URL) async -> [String: Any]? {
        await MontanaWakePush.$quietCargo.withValue(false) { await layPieces(url) }
    }
    nonisolated private static func layPieces(_ url: URL) async -> [String: Any]? {
        let size = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int) ?? 0
        guard size > 0, let up = await MontanaMedia.sealAndUpload(source: .file(url), progress: { _ in }) else { return nil }
        guard await MontanaWakePush.uploadChunks(["chunks": up.manifest]) else { return nil }
        guard let list = try? JSONSerialization.data(withJSONObject: up.manifest) else { return nil }
        let mk = montanaRandom(32)
        guard let sealed = MTNodeWire.sealBlob(key: [UInt8](mk), list) else { return nil }
        let mref = MontanaMedia.blobIdHex(sealed)
        guard await MontanaWakePush.putBlob(mref, data: sealed) else { return nil }
        return ["z": size, "bk": up.blobKey.base64EncodedString(), "mref": mref, "mk": mk.base64EncodedString()]
    }
    /// A road's name and key alone: enough to find its pieces again and take them off the nodes.
    nonisolated static func roadsOf(_ roads: [[String: Any]]) -> [[String: String]] {
        roads.compactMap { r in
            guard let mref = r["mref"] as? String, let mk = r["mk"] as? String else { return nil }
            return ["mref": mref, "mk": mk]
        }
    }
    /// THE ROADS TAKEN OFF THE NODES (OZ 1): each list is read under its key, and its pieces and the list itself are dropped from
    /// every store, a slice the store takes at a time. A list already gone leaves only its own name to drop.
    nonisolated static func unlay(_ roads: [[String: String]]) async {
        guard !roads.isEmpty else { return }
        var bids: [String] = []
        for r in roads {
            guard let mref = r["mref"], !mref.isEmpty else { continue }
            if let mk = r["mk"].flatMap({ Data(base64Encoded: $0) }), let list = await MontanaWakePush.getBlob(mref),
               MontanaMedia.blobIdHex(list) == mref, let opened = MTNodeWire.openBlob(key: [UInt8](mk), sealed: list),
               let manifest = (try? JSONSerialization.jsonObject(with: opened)) as? [[String: Any]] {
                bids += manifest.compactMap { $0["bid"] as? String }
            }
            bids.append(mref)
        }
        for start in stride(from: 0, to: bids.count, by: unlaySlice) {
            await MontanaWakePush.dropBids(Array(bids[start..<min(start + unlaySlice, bids.count)]))
        }
        MontanaTrace.mark("keep_unlay", "roads=\(roads.count) pieces=\(bids.count)")
    }
    nonisolated static let unlaySlice = 4096   // the names one /blob-drop takes (the node store refuses more)
    /// Whether a road still stands on the nodes: its list asked of every store. No answer is no verdict -- the road is used.
    nonisolated static func stands(_ mref: String) async -> Bool {
        guard !mref.isEmpty else { return false }
        guard let have = await MontanaWakePush.blobsPresent([mref], everyStore: true) else { return true }
        return have.contains(mref)
    }
    /// The part comes back piece by piece from the nodes, each opened under its key and checked by its name, written in order.
    nonisolated static func fetch(_ o: [String: Any], to dest: URL, progress: (@Sendable (Double) -> Void)? = nil) async -> Bool {
        guard let size = o["z"] as? Int, size > 0,
              let bk = (o["bk"] as? String).flatMap({ Data(base64Encoded: $0) }),
              let mref = o["mref"] as? String,
              let mk = (o["mk"] as? String).flatMap({ Data(base64Encoded: $0) }),
              let list = await MontanaWakePush.getBlob(mref), MontanaMedia.blobIdHex(list) == mref,
              let opened = MTNodeWire.openBlob(key: [UInt8](mk), sealed: list),
              let manifest = (try? JSONSerialization.jsonObject(with: opened)) as? [[String: Any]] else { return false }
        let fm = FileManager.default
        try? fm.removeItem(at: dest)
        guard fm.createFile(atPath: dest.path, contents: nil), let fh = try? FileHandle(forWritingTo: dest) else { return false }
        defer { try? fh.close() }
        var written = 0
        for m in manifest {
            guard let bid = m["bid"] as? String, let cs = m["cs"] as? Int else { return false }
            var piece: Data? = nil
            for attempt in 0..<3 where piece == nil {
                if let s = await MontanaWakePush.getBlob(bid) { piece = MontanaMedia.openChunk(sealed: s, blobKey: bk, expectedIdHex: bid, size: cs) }
                if piece == nil, attempt < 2 { try? await Task.sleep(nanoseconds: 800_000_000) }
            }
            guard let piece, (try? fh.write(contentsOf: piece)) != nil else { return false }
            written += piece.count
            progress?(Double(min(written, size)) / Double(size))
        }
        return written == size
    }

    // ── the keeper ──
    /// A part is held under the name of its correspondence and its slot: a keeper of the ring holds several of one owner. A name
    /// without a slot is a part an older build handed.
    nonisolated static func keyOf(_ conv: String, _ k: Int) -> String { conv + "#" + String(k) }
    nonisolated static func convOf(_ key: String) -> String { String(key.prefix(while: { $0 != "#" })) }
    private func generation(_ h: Held) -> UInt64 { MTKeepDerive.Head(h.head)?.generation ?? 0 }
    private func heldBytes(except conv: String) -> Int { held.filter { Self.convOf($0.key) != conv }.reduce(0) { $0 + $1.value.bytes } }
    /// The people whose parts this phone holds, and how much of each.
    var keptFor: [String] { Array(Set(held.keys.map(Self.convOf))).sorted() }
    func bytes(for conv: String) -> Int { held.filter { Self.convOf($0.key) == conv }.reduce(0) { $0 + $1.value.bytes } }
    /// A question is answered only by a phone whose person allows keeping and whose budget has room: anything else is silence,
    /// and no refusal produces a reply.
    private func answerAsk(_ conv: String, _ o: [String: Any]) {
        guard Self.others, let g = o["g"] as? Int, heldBytes(except: conv) < Self.budget else {
            return MontanaTrace.mark("keep_quiet", "conv=" + String(conv.prefix(10)))
        }
        say(conv, ["w": "yes", "g": g])
    }
    private func takePart(_ conv: String, _ o: [String: Any]) async {
        guard Self.others, let k = o["k"] as? Int, let n = o["n"] as? Int,
              let secret = (o["s"] as? String).flatMap({ Data(base64Encoded: $0) }), secret.count == 32,
              let hd = (o["h"] as? String).flatMap({ Data(montanaHex: $0) }), let head = MTKeepDerive.Head(hd), head.slot == k, head.n == n,
              let seal = (o["e"] as? String).flatMap({ Data(montanaHex: $0) }), seal.count == 32,
              let size = o["z"] as? Int, size > 0 else { return MontanaTrace.mark("keep_part", "refused in silence") }
        let key = Self.keyOf(conv, k)
        // The budget counts every other person's parts and this person's parts of the same copy: an older copy leaves below.
        let sameCopy = held.filter { Self.convOf($0.key) == conv && $0.key != key && generation($0.value) == head.generation }
        guard heldBytes(except: conv) + sameCopy.values.reduce(0, { $0 + $1.bytes }) + size <= Self.budget,
              let dest = Self.partURL(key) else { return MontanaTrace.mark("keep_part", "refused in silence") }
        let landing = dest.appendingPathExtension("part")
        guard await Self.fetch(o, to: landing), MontanaBackup.digest(of: landing) == head.shareDigest.montanaHexString else {
            try? FileManager.default.removeItem(at: landing)
            return MontanaTrace.mark("keep_part", "the part did not come whole")
        }
        try? FileManager.default.removeItem(at: dest)
        guard (try? FileManager.default.moveItem(at: landing, to: dest)) != nil else { return }
        // A RENEWAL REPLACES (Network): this person's parts of an older copy leave as the newer one arrives.
        for (old, h) in held where Self.convOf(old) == conv && old != key && generation(h) < head.generation { dropKey(old) }
        let now = Date().timeIntervalSince1970
        var road: [String: String] = ["z": String(size)]
        for name in ["bk", "mref", "mk"] { road[name] = o[name] as? String ?? "" }
        held[key] = Held(slot: k, n: n, secret: secret, head: hd, seal: seal, bytes: size, at: now, road: road, roadAt: now)
        roads[key] = nil
        saveHeld()
        MontanaWakePush.registerConvs()   // the slot's pipe rings this phone from now on: a call wakes it by a push
        say(conv, ["w": "held", "g": Int(head.generation), "d": head.shareDigest.montanaHexString, "k": k])
        MontanaTrace.mark("keep_part", "held slot=\(k) of \(n) bytes=\(size)")
    }
    private func dropKey(_ key: String) {
        held[key] = nil; roads[key] = nil
        if let u = Self.partURL(key) { try? FileManager.default.removeItem(at: u) }
    }
    func drop(_ conv: String) {
        let c = Self.convOf(conv)
        let keys = held.keys.filter { Self.convOf($0) == c }
        guard !keys.isEmpty else { return }
        for key in keys { dropKey(key) }
        saveHeld()
        MontanaWakePush.registerConvs()   // and the slots' pipes ring it no more
        MontanaTrace.mark("keep_drop", "conv=" + String(c.prefix(10)) + " parts=\(keys.count)")
    }
    func setOthers(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Self.othersKey)
        objectWillChange.send()
        if !on { for conv in keptFor { drop(conv) } }
    }
    /// The pipes of the slots this phone holds, heard in the box beside every correspondence (MontanaWakePush.fetchBox).
    nonisolated static func listening() -> [String: MTPipeKey] {
        guard agrees else { return [:] }
        var out: [String: MTPipeKey] = [:]
        for (conv, h) in heldNow() { out[pipePrefix + conv] = MTPipeKey(h.secret) }
        return out
    }
    /// A row of the box under the pipe of a slot is this file's own: a call is answered, and the row is in hand either way.
    nonisolated static func takes(_ row: [String: String]) -> Bool {
        guard let c = row["c"], c.hasPrefix(pipePrefix) else { return false }
        let conv = String(c.dropFirst(pipePrefix.count))
        if (word(row["t"] ?? "")?["w"] as? String) == "call" {
            Task { @MainActor in await MTKeeping.shared.answerCall(conv) }
        }
        return true
    }
    private func answerCall(_ conv: String) async {
        guard Self.others, var h = held[conv], let url = Self.partURL(conv), FileManager.default.fileExists(atPath: url.path) else { return }
        let now = Date().timeIntervalSince1970
        guard now - h.answeredAt >= 600 else { return }   // a call repeats every two minutes; one answer serves ten
        // THE CALL CAME BY A PUSH (the author's word 08.10.2026 19:4x UTC: «the whole restore by silent pushes»): the phone is
        // awake for seconds, and the system is asked for the time the answer takes.
        let task = UIApplication.shared.beginBackgroundTask(withName: "keep-answer")
        defer { if task != .invalid { UIApplication.shared.endBackgroundTask(task) } }
        var road: [String: Any]
        // The owner's road is ridden while it stands: a newer generation takes the older off the nodes (unlay), and a keeper
        // that missed the newer part lays its own.
        if let r = h.road, let at = h.roadAt, now - at < 6 * 86_400, let z = Int(r["z"] ?? ""), z == h.bytes, await Self.stands(r["mref"] ?? "") {
            road = ["z": z, "bk": r["bk"] ?? "", "mref": r["mref"] ?? "", "mk": r["mk"] ?? ""]   // the owner's pieces, alive a week
        } else if let r = roads[conv], now - r.at < 86_400 {
            road = r.road   // the pieces live a week on the nodes: a day's answers share them
        } else {
            guard let fresh = await Self.lay(url) else { return MontanaTrace.mark("keep_answer", "the part did not reach the nodes") }
            road = fresh; roads[conv] = (now, fresh)
        }
        road["w"] = "answer"; road["h"] = h.head.montanaHexString; road["e"] = h.seal.montanaHexString
        guard await Self.knock(h.secret, road) else { return MontanaTrace.mark("keep_answer", "no door boxed it") }
        h.answeredAt = now; held[conv] = h; saveHeld()
        MontanaTrace.mark("keep_answer", "slot=\(h.slot) of \(h.n)")
    }
    /// One letter in the pipe of a slot, boxed like every letter of a pipe. Silent, the node wakes the keeper by a background push
    /// (the keeper registers its slots' pipes, MontanaWakePush.registerRound); loud, the keeper's phone shows one banner with
    /// the owner's name (the notification extension), for a keeper whose app the system does not wake.
    nonisolated static func knock(_ secret: Data, _ o: [String: Any], silent: Bool = true, sender: String? = nil) async -> Bool {
        guard let d = try? JSONSerialization.data(withJSONObject: o), let s = String(data: d, encoding: .utf8) else { return false }
        return await knockText(secret, keepMark + s, silent: silent, sender: sender)
    }
    /// THE SAME WORD ON THE LIVE WIRE (OZ 1 p.1.8, the author's words 23559 and 23560, 16.11.2026: «the nodes are an additional
    /// channel, the main one must be direct», «build»): the word a knock boxes at a node's door rides at the same instant as a
    /// letter's envelope under the pipe's tag of this minute on every standing channel -- a channel to the other device itself
    /// where one stands, the carriers' wire else. Its form and its size are a letter's own: the same frame byte, tag and sealed
    /// fields, and no padding to one measure, which would mark the seed's word among letters; the carriers' threshold is a
    /// letter's too. False: no carrier stands, or the word is past one letter's measure -- the knock carries it alone then.
    nonisolated static func wire(_ secret: Data, _ o: [String: Any]) -> Bool {
        guard let d = try? JSONSerialization.data(withJSONObject: o), let s = String(data: d, encoding: .utf8) else { return false }
        guard MontanaPath.networkPathAssembled(owners: MontanaDirect.shared.ownerRefsOfLiveChannels(excluding: MontanaSeed.twin ?? "")) else { return false }
        let mid = UUID().uuidString, key = MTPipeKey(secret), w = MTPipe.window()
        let head = MTNodeWire.letterHead(mid: mid, text: keepMark + s, name: "", glyph: "")
        guard head.count <= MTNodeWire.envelopeSize, let sealed = MTPipe.sealBody(head, sharedSecret: key, window: w) else { return false }
        let tag = key.tag(window: w)
        var envelope = Data([MontanaPhoneNode.letterFrame]); envelope.append(tag); envelope.append(sealed)
        return MontanaDirect.shared.sendUnderTag(tag, payload: envelope, mid: mid)
    }
    /// One word of this person's own in a pipe, its text as given (a keeping word above; the seed's read word, MTTwinRead): the
    /// one place here that seals such a letter's head.
    nonisolated static func knockText(_ secret: Data, _ text: String, silent: Bool = true, sender: String? = nil) async -> Bool {
        guard let twin = sender ?? MontanaSeed.twin else { return false }
        let mid = UUID().uuidString
        guard let plain = MTNodeWire.padEnvelope(MTNodeWire.letterHead(mid: mid, text: text, name: "", glyph: "")) else { return false }
        let k = await MTNodeWire.knockLetter(secret: MTPipeKey(secret), twinRef: twin, mid: mid, plain: plain,
                                             doors: MontanaWakePush.oneDoorPerNode(MontanaWakePush.orderedBases(for: "box")), silent: silent)
        return k.boxed
    }

    // ── the correspondence given back (Network «The correspondence given back»; the author's word 08.10.2026 20:5x UTC: «by
    // default every correspondent keeps the conversation with their correspondent and, if it is saved, gives it to the one who
    // restores») ──
    nonisolated static let askedBackKey = "mt.keep.back.asked"   // NOT-UI: the correspondences this phone asked to give back, and when (SeedScope.deviceKeys)
    private var answeredBack: [String: Double] = [:]
    private func askedBack() -> [String: Double] { (UserDefaults.standard.dictionary(forKey: Self.askedBackKey) as? [String: Double]) ?? [:] }
    private func lastLetter(_ conv: String) -> Double { ChatStore.live?.messages[conv]?.map(\.createdAt).max() ?? 0 }
    /// THE REQUEST: once a copy is laid, every correspondence of a person it names is asked in its own pipe, with the moment of
    /// the last letter laid there; the answer is awaited a week, as long as the pieces it rides live.
    private func askBack() {
        // A JOINED DEVICE ASKS NOBODY (the author's word 23053 p.2): its history comes from the phone alone; the people one writes
        // to are never asked to give letters back to it.
        guard MTLinkedDevices.joinedPhone == nil else { return MontanaTrace.mark("keep_back", "a joined device asks nobody") }
        let now = Date().timeIntervalSince1970
        var asked = askedBack().filter { now - $0.value < 7 * 86_400 }
        var n = 0
        for conv in people() where now - (asked[conv] ?? 0) >= 600 {
            say(conv, ["w": "back", "a": lastLetter(conv)])
            asked[conv] = now; n += 1
        }
        UserDefaults.standard.set(asked, forKey: Self.askedBackKey)
        MontanaTrace.mark("keep_back", "asked=\(n)")
    }
    /// THE ANSWER: the letters of this correspondence this phone holds, later than the asker's last, on the cargo road and named
    /// in the same correspondence -- nothing kept for the purpose, nothing but this correspondence, and nothing while the person
    /// keeps nothing for others.
    private func answerBack(_ conv: String, _ o: [String: Any]) async {
        let now = Date().timeIntervalSince1970
        guard Self.others, now - (answeredBack[conv] ?? 0) >= 600, let store = ChatStore.live else {
            return MontanaTrace.mark("keep_back", "quiet conv=" + String(conv.prefix(10)))
        }
        answeredBack[conv] = now
        let since = (o["a"] as? Double) ?? 0
        let rows = (store.messages[conv] ?? []).filter {
            // A FILE'S ROW OF MINE RIDES TOO (OZ 2 p.1.4.1, the author's words 22141, 22151): the file I sent, under the wire name it
            // went by -- the asker takes it as its received letter and asks the file by the seal of that name (serveKeptFile).
            $0.createdAt > since && (($0.attachment == nil && !$0.text.isEmpty)
                || ($0.isFromMe && $0.attachment != nil && ($0.msgId ?? "").hasPrefix("mid:")))
        }
        guard !rows.isEmpty else { say(conv, ["w": "given", "c": 0]); return }
        // A letter of the asker rides with the author field it came with (Message.authorTag): their phone names it theirs by
        // their own key, never by this phone's word.
        let list: [[String: Any]] = rows.map { r in
            var e: [String: Any] = ["i": r.msgId ?? "", "m": r.isFromMe ? 1 : 0, "t": r.createdAt, "x": r.attachment == nil ? r.text : ""]
            if r.attachment != nil, let md = ChatStore.archivedText(r) { e["md"] = md }   // no "x": a build before this one skips the row
            if !r.isFromMe, let a = r.authorTag, !a.isEmpty { e["a"] = a }
            return e
        }
        guard let body = try? JSONSerialization.data(withJSONObject: list), let dir = try? MontanaBackup.shelf() else { return }
        let url = dir.appendingPathComponent(UUID().uuidString + ".given")
        defer { try? FileManager.default.removeItem(at: url) }
        guard (try? body.write(to: url)) != nil, let digest = MontanaBackup.digest(of: url), var road = await Self.lay(url) else {
            return MontanaTrace.mark("keep_back", "the letters did not reach the nodes")
        }
        road["w"] = "given"; road["c"] = rows.count; road["d"] = digest
        say(conv, road)
        MontanaTrace.mark("keep_back", "gave=\(rows.count) bytes=\(body.count) conv=" + String(conv.prefix(10)))
    }
    /// THE CORRESPONDENCE TAKEN BACK: only an answer to this phone's own request, only the letters later than the last one in that
    /// correspondence here -- a letter erased before the copy stays erased -- each on the side of the one who wrote it.
    /// WHICH LETTER IS MINE IS SAID BY MY OWN WORDS (the critic R-6; the author's words 11.10.2026 17:1x UTC: «check the whole
    /// architecture of the chats' time chains, so there are no holes by the constitution», 18:5x: «carry out all 13»): the side
    /// was the correspondent's flag alone, and a correspondent could lay words on this phone as the person's own. A letter they
    /// name as theirs is theirs; one they name as mine stands as mine only when the author field it rode with is made again
    /// under this person's key (MTLetterAuthor.mine) -- else it is not laid at all, and the count says so.
    private func takeGiven(_ conv: String, _ o: [String: Any]) async {
        guard let at = askedBack()[conv], Date().timeIntervalSince1970 - at < 7 * 86_400, (o["c"] as? Int ?? 0) > 0,
              let d = o["d"] as? String, let dir = try? MontanaBackup.shelf() else { return }
        let url = dir.appendingPathComponent(UUID().uuidString + ".given")
        defer { try? FileManager.default.removeItem(at: url) }
        guard await Self.fetch(o, to: url), MontanaBackup.digest(of: url) == d, let data = try? Data(contentsOf: url),
              let list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]], let store = ChatStore.live else {
            return MontanaTrace.mark("keep_back", "the given letters did not come whole")
        }
        // The copies' last letter is the last one older than the request: a letter that came live after it is no measure.
        let since = store.messages[conv]?.filter { $0.createdAt < at }.map(\.createdAt).max() ?? 0
        var unproven = 0
        let rows: [Message] = list.compactMap { e in
            guard let t = e["t"] as? Double, t > since else { return nil }
            // A FILE'S ROW OF THE OTHER SIDE (OZ 2 p.1.4.1): the giver's own sent file is this phone's received one, named by the
            // letter's wire name as a received file is (mediaFileName), so its seal finds the letter on the giver (serveKeptFile).
            if let md = e["md"] as? String, md.hasPrefix(mediaMark) {
                guard (e["m"] as? Int ?? 0) == 1, let wire = e["i"] as? String, wire.hasPrefix("mid:"),
                      let rec = try? JSONDecoder().decode(ArchivedMedia.self, from: Data(md.dropFirst(mediaMark.count).utf8)),
                      ["img", "vid", "aud", "doc"].contains(rec.k) else { return nil }
                let name = store.mediaFileName(kind: rec.k, ext: (rec.f as NSString).pathExtension, seed: wire)
                return Message(text: rec.cap ?? "", isFromMe: false, time: hhmm(at: t), isRead: true,
                               imageFile: rec.k == "img" ? name : nil, videoFile: rec.k == "vid" ? name : nil,
                               audioFile: rec.k == "aud" ? name : nil, audioDuration: rec.d ?? 0,
                               docFile: rec.k == "doc" ? name : nil, docName: rec.n,
                               deliveryStatus: .read, msgId: MTRestoredMid.given + wire, createdAt: t)
            }
            guard let x = e["x"] as? String, !x.isEmpty else { return nil }
            let wire = (e["i"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let claimedMine = (e["m"] as? Int ?? 0) == 0   // the other side's own letter is the other side's here
            if claimedMine {
                let bare = wire.map { w in MTMid.bare(w) } ?? ""
                guard !bare.isEmpty, MTLetterAuthor.mine((e["a"] as? String) ?? "", conv: conv, mid: bare, text: x) else {
                    unproven += 1
                    return nil
                }
            }
            let mid = MTRestoredMid.given + (wire ?? String(t))
            return Message(text: x, isFromMe: claimedMine, time: hhmm(at: t), isRead: true, deliveryStatus: claimedMine ? .sent : .read, msgId: mid, createdAt: t)
        }
        let laid = store.layGivenBack(conv, rows)
        MontanaTrace.mark("keep_back", "took=\(laid) of \(list.count) unproven_mine=\(unproven) conv=" + String(conv.prefix(10)))
    }

    // ── a phone that opened the words ──
    /// THE COPY TAKEN BACK FROM THE PEOPLE ONE WRITES TO: the pipe of every slot is called, every answer's seal is checked against
    /// the words, and the copy of the highest generation whose every group stands is built, checked against its digest and laid
    /// by the one road of a copy (MontanaBackup.restore). The calls repeat every two minutes; the walk ends with the copy laid,
    /// or after six hours without one.
    func takeBack(_ done: @escaping (Result<MontanaBackup.Tally, MontanaBackup.Refusal>) -> Void = { _ in }) {
        guard takingTask == nil else { return }
        takingTask = Task {
            let r = await callAndBuild()
            takingTask = nil
            done(r)
        }
    }
    func stopTaking() {
        takingTask?.cancel(); takingTask = nil
        if case .calling = taking { taking = .idle }
    }
    var isTaking: Bool { takingTask != nil }

    /// THE PHONE'S COPY IS THE HISTORY OF A JOINED DEVICE (decision 989 = a; the author's word 23053 p.2: only from the phone, and
    /// whole): the pipe of light is read every 30 seconds until the phone's copy for this joining lies, every two minutes after
    /// ten; ten minutes without it let the person in with what another device's copy laid, and the reading goes on. Nobody the
    /// person writes to is asked and no keeper is called; six hours without the phone's copy end the walk.
    private func takeFromPhone(_ ls: Data?, dir: URL, phone: (tag: String, at: Double), began: Double) async
        -> Result<MontanaBackup.Tally, MontanaBackup.Refusal> {
        guard let ls else { taking = .failed; return .failure(.noSeed) }
        var last = 0.0
        while !Task.isCancelled {
            let now = Date().timeIntervalSince1970
            if (now - began < 600 ? 30.0 : 120.0) <= now - last {
                last = now
                if await takeLight(ls, dir: dir, phone: phone) { taking = .done; return .success(lightTally) }
                if 600 <= now - began, lightLaid { letIn() }
                taking = .calling(have: 0, need: 0)
            }
            if 6 * 3600 < Date().timeIntervalSince1970 - began { taking = .failed; return .failure(.empty) }
            try? await Task.sleep(nanoseconds: 15_000_000_000)
        }
        taking = .idle
        return .failure(.stopped)
    }

    /// The words opened here (the author's words 23891, 23893): the seed's other devices are asked for a picture of now, and it is
    /// awaited a while -- a device whose app sleeps hears the asking only when it wakes; then the newest copy there stands for it.
    private static let freshWait: Double = 90
    private func takeOpened(_ ls: Data, dir: URL, began: Double) async -> Bool {
        MontanaArchive.askTwinsLight()
        while !Task.isCancelled, Date().timeIntervalSince1970 - began < Self.freshWait {
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            if await takeLight(ls, dir: dir, phone: nil, since: began) { return true }
        }
        return await takeLight(ls, dir: dir, phone: nil)
    }

    private struct Answer { let head: MTKeepDerive.Head; let url: URL }
    private func callAndBuild() async -> Result<MontanaBackup.Tally, MontanaBackup.Refusal> {
        guard Self.agrees, let master = MontanaSeed.root,
              let key = MTKeepDerive.keepKey(master), let dir = try? MontanaBackup.shelf() else { taking = .failed; return .failure(.noSeed) }
        let secrets = (0..<MTKeepDerive.slots).compactMap { MTKeepDerive.slotSecret(master, $0) }
        guard secrets.count == MTKeepDerive.slots else { taking = .failed; return .failure(.noSeed) }
        var pipes: [String: Data] = [:]
        for (k, s) in secrets.enumerated() { pipes[Self.callPrefix + String(k)] = s }
        var answers: [String: Answer] = [:]
        var lastCall = 0.0, lastLoud = 0.0
        let began = Date().timeIntervalSince1970
        taking = .fetching(0)
        let ls = MTKeepDerive.lightSecret(master)
        lightSeen = []; lightLaid = false
        // A JOINED DEVICE TAKES ITS HISTORY FROM THE PHONE ALONE (the author's word 23053 p.2): no keeper is called, no push rings.
        if let phone = MTLinkedDevices.joinedPhone { return await takeFromPhone(ls, dir: dir, phone: phone, began: began) }
        // THE LIGHT COPY FIRST (Network «The light copy»): the pipe of light is read before any call, and the person is let in.
        if let ls, await takeOpened(ls, dir: dir, began: began) { askBack() }   // the pipes it named are asked to give back
        taking = .calling(have: 0, need: 0)
        defer { for a in answers.values { try? FileManager.default.removeItem(at: a.url) } }
        while !Task.isCancelled {
            let now = Date().timeIntervalSince1970
            if now - lastCall >= 120 {
                lastCall = now
                var boxed = 0
                for s in secrets { if await Self.knock(s, ["w": "call"]) { boxed += 1 } }
                MontanaTrace.mark("keep_call", "slots=\(secrets.count) boxed=\(boxed)")
            }
            // IF NEEDED, A LOUD PUSH (the author's word 08.10.2026 19:4x UTC): six minutes of silence from a slot, and the call
            // in its pipe rings the keeper's screen with the owner's name, every ten minutes -- a phone whose app the person
            // closed hears no silent push at all. The slots that answered the newest copy are rung no more.
            if now - began >= 360, now - lastLoud >= 600 {
                lastLoud = now
                let newest = answers.values.max(by: { $0.head.generation < $1.head.generation })?.head
                let heard = Set(answers.values.filter { $0.head.copyDigest == newest?.copyDigest }.map { $0.head.slot })
                var rung = 0
                for k in 0..<(newest?.n ?? MTKeepDerive.slots) where !heard.contains(k) {
                    if await Self.knock(secrets[k], ["w": "call", "loud": 1], silent: false) { rung += 1 }
                }
                MontanaTrace.mark("keep_call", "loud rung=\(rung) heard=\(heard.count)")
            }
            var rows: [[String: String]] = []
            let ear = MontanaWakePush.BoxEar(invites: [], pipes: pipes.mapValues(MTPipeKey.init), owner: MontanaSeed.twin ?? "")
            _ = await MontanaWakePush.pickup(ear, buries: nil, keep: { row in rows.append(row); return true })
            for row in rows {
                guard let c = row["c"], c.hasPrefix(Self.callPrefix), let k = Int(c.dropFirst(Self.callPrefix.count)),
                      let o = Self.word(row["t"] ?? ""), (o["w"] as? String) == "answer",
                      let hd = (o["h"] as? String).flatMap({ Data(montanaHex: $0) }), let head = MTKeepDerive.Head(hd), head.slot == k,
                      let seal = (o["e"] as? String).flatMap({ Data(montanaHex: $0) }), seal == MTKeepDerive.seal(key, head) else { continue }
                let id = head.copyDigest.montanaHexString + "." + String(k)
                guard answers[id] == nil else { continue }
                let url = dir.appendingPathComponent(UUID().uuidString + ".keep")
                guard await Self.fetch(o, to: url), MontanaBackup.digest(of: url) == head.shareDigest.montanaHexString else {
                    try? FileManager.default.removeItem(at: url); continue
                }
                answers[id] = Answer(head: head, url: url)
                MontanaTrace.mark("keep_took", "slot=\(k) of \(head.n) generation=\(head.generation)")
            }
            // The copies in hand, the newest first; a copy stands when its parts hold twelve cells of every group.
            let copies = Dictionary(grouping: Array(answers.values), by: { $0.head.copyDigest })
            let ranked = copies.values.sorted { ($0.first?.head.generation ?? 0) > ($1.first?.head.generation ?? 0) }
            if let best = ranked.first, let h = best.first?.head { taking = .calling(have: best.count, need: 3 * h.n / 4) }
            for parts in ranked {
                guard let h0 = parts.first?.head else { continue }
                let same = parts.filter { $0.head.n == h0.n && $0.head.length == h0.length }
                guard same.count * (MTKeepCode.group / h0.n) >= MTKeepCode.data else { continue }
                let out = dir.appendingPathComponent(UUID().uuidString + "." + MontanaBackup.ext)
                let list = same.map { (slot: $0.head.slot, n: $0.head.n, url: $0.url) }
                let length = h0.length
                let built = await Task.detached(priority: .userInitiated, operation: { MTKeepCode.rebuild(list, length: length, into: out) }).value
                guard built, MontanaBackup.digest(of: out) == h0.copyDigest.montanaHexString else {
                    try? FileManager.default.removeItem(at: out)
                    MontanaTrace.mark("keep_build", "generation=\(h0.generation) did not stand")
                    continue
                }
                taking = .laying(0)
                let r: Result<MontanaBackup.Tally, MontanaBackup.Refusal> = await withCheckedContinuation { c in
                    MontanaBackup.restore(from: out, ofMany: true, progress: { f in Task { @MainActor in MTKeeping.shared.taking = .laying(f) } }) { c.resume(returning: $0) }
                }
                try? FileManager.default.removeItem(at: out)
                reread()   // the copy laid this person's state of keeping too
                if case .success = r {
                    owner.generation = max(owner.generation, h0.generation); saveOwner()
                    askBack()   // the pipes the full copy named, the ones the light copy did not already ask
                    taking = .done
                } else {
                    taking = .failed
                }
                MontanaTrace.mark("keep_build", "generation=\(h0.generation) laid=\(String(describing: r))")
                return r
            }
            if Date().timeIntervalSince1970 - began > 6 * 3600 { taking = .failed; return .failure(.empty) }
            try? await Task.sleep(nanoseconds: 15_000_000_000)
        }
        taking = .idle
        return .failure(.stopped)
    }
}

/// THE RING OF KEEPERS (Network «The keepers are correspondents, and they stand on a ring»; the author's word 08.10.2026 20:5x UTC:
/// «not 4, 8 and so on ... between contacts in a ring, so that if someone is offline the restore is full»): every
/// correspondent that allows keeping, two at each position at most, and every share at two neighbouring positions.
enum MTKeepRing {
    static let most = 2 * MTKeepCode.group
    /// The slots the keeper at place i of m keeps: those whose position, k mod q, is its own or the next one around the ring.
    static func slots(place i: Int, of m: Int) -> [Int] {
        let q = min(m, MTKeepCode.group)
        guard q > 0, i >= 0, i < m else { return [] }
        let j = i % q
        return (0..<MTKeepCode.group).filter { $0 % q == j || $0 % q == (j + 1) % q }
    }
    /// The rule as cases a wrong reading fails: a ring that does not close (place 3 of 4 keeps slot 0), the neighbour taken
    /// backwards (place 0 of 4 keeps 1 and never 3), one or two keepers holding all sixteen, and the seventeenth keeper of
    /// twenty standing beside the first.
    static func agrees() -> Bool {
        slots(place: 0, of: 4) == [0, 1, 4, 5, 8, 9, 12, 13]
            && slots(place: 3, of: 4) == [0, 3, 4, 7, 8, 11, 12, 15]
            && slots(place: 0, of: 1) == Array(0..<16) && slots(place: 1, of: 2) == Array(0..<16)
            && slots(place: 16, of: 20) == [0, 1] && slots(place: 15, of: 16) == [0, 15]
    }
}

extension ChatStore {
    /// THE LETTERS A CORRESPONDENT GAVE BACK (MTKeeping): rows later than the feed's last join it by the fold's own road -- the
    /// journal and the archive take each, the list follows -- and nothing is receipted, rung or counted unread: it is history the
    /// person already lived.
    @MainActor
    func layGivenBack(_ conv: String, _ rows: [Message]) -> Int {
        guard !rows.isEmpty, !deletedChats.contains(conv), !refuses(conv) else { return 0 }
        var feed = messages[conv] ?? []
        // A letter both sides hold is known by its moment, its side and its words, as the archive's rows are: the other side
        // names it by its own identity, never by this one's.
        let sig: (Message) -> String = { ChatStore.rowSig($0.createdAt, $0.isFromMe, $0.text) }
        let had = Set(feed.compactMap { $0.msgId }), seen = Set(feed.map(sig))
        // A GIVEN-BACK LETTER ASKS THE GRAVES OF ITS CONVERSATION (the critic R-6): its wire name -- inside the restored one -- and the
        // restored name itself, and the conversation's funeral; a letter erased here stays erased whoever gives it back.
        let wire: (Message) -> String = { MTRestoredMid.wire($0.mid) }
        let add = ChatStore.allRead(rows.filter { m in
            !seen.contains(sig(m)) && !had.contains(m.mid) && !had.contains(wire(m))
                && !buried(wire(m), in: conv) && !buried(m.mid, in: conv) && !diedBefore(wire(m), in: conv)
        })
        guard !add.isEmpty else { return 0 }
        feed.append(contentsOf: add)
        feed.sort(by: ChatStore.before)
        messages[conv] = feed
        for m in add { _ = MTRowJournal.put(conv, m); archiveRow(conv, m) }
        if let last = feed.max(by: ChatStore.before) {
            noteListState(conv, last: last)
            noteOrder(conv, at: Int(last.createdAt * 1000))
        }
        persist(messages, why: "given")
        return add.count
    }
}

/// THE KEEPING IN SETTINGS, native rows: two switches, what a keeper learns said beneath them, the state in the keepers' own
/// words (a part is «held» only on its keeper's «held»), the parts this phone holds by name and size, and the road back.
/// SAID HERE AND NOWHERE ELSE (the author's word 17977-17978, 09.11.2026): the notice «N keeps a sealed part of their copy on
/// this phone» is gone -- a banner about someone's part on your phone read as control. The footers below say it plainly, as
/// what it is: Montana's own way of keeping copies with no cloud in between.
struct MTKeepingSection: View {
    @ObservedObject private var keep = MTKeeping.shared
    private var mineState: LocalizedStringKey {
        if keep.owner.asking != nil { return "Asking the people you write to…" }
        if keep.owner.keepers.isEmpty { return keep.owner.short ? "None of your contacts can keep a part yet" : "Not kept yet" }
        return "Kept by \(keep.owner.keepers.values.filter { $0.held }.count) of \(keep.owner.keepers.count)"
    }
    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { MTKeeping.mine }, set: { keep.setMine($0) })) {
                settingsToggleLabel("Keep my copy with my contacts", "person.3.fill", .teal)
            }
            if MTKeeping.mine {
                Text(mineState).foregroundColor(.secondary)
            }
        } header: {
            Text("COPY WITH CONTACTS")
        } footer: {
            Text("Your copy lives only on phones, never in a cloud: this is Montana's own way of keeping it. It is sealed with your 24 words and cut into parts, and the people you write to keep the parts for you: each sees only a size, never a word. On a new phone your 24 words bring the parts back, and your conversations with them.")
        }
        .listRowBackground(MTGlassRowPlate())
        Section {
            Toggle(isOn: Binding(get: { MTKeeping.others }, set: { keep.setOthers($0) })) {
                settingsToggleLabel("Keep parts for my contacts", "tray.full.fill", .gray)
            }
            ForEach(keep.keptFor, id: \.self) { conv in   // one row a person, their parts summed
                HStack {
                    Text(verbatim: ChatStore.live?.peerNames[conv] ?? "").foregroundColor(.primary)   // USER-DATA: a correspondent's name
                    Spacer()
                    Text(verbatim: mtSize(keep.bytes(for: conv))).foregroundColor(.secondary)   // USER-DATA: a size
                }
                .swipeActions(edge: .trailing) {
                    Button { keep.drop(conv) } label: { Label("Stop keeping this part", systemImage: "trash") }
                        .tint(.red)
                }
            }
            Button { keep.takeBack() } label: {
                HStack {
                    settingsToggleLabel("Take my copy back from my contacts", "arrow.down.circle.fill", .blue)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .disabled(keep.isTaking)
            switch keep.taking {
            case .calling(let have, let need) where need > 0:
                Text("Parts in hand: \(have) of \(need)").foregroundColor(.secondary)
            case .calling:
                Text("Restoring the identity chain").foregroundColor(.secondary)
            case .fetching(let f), .laying(let f):
                ProgressView(value: f)
            case .done:
                Text("The copy came back").foregroundColor(.secondary)
            case .failed:
                Text("No copy came back").foregroundColor(.secondary)
            case .idle:
                EmptyView()
            }
        } footer: {
            Text("The parts your contacts leave with you are sealed the same way: this phone cannot open them, and only their own 24 words can. This is how Montana keeps copies with no cloud in between: people hold each other's sealed parts, and no one but the owner can ever read them.")
        }
        .listRowBackground(MTGlassRowPlate())
    }
}


// ── A DEVICE JOINS BY QR (OZ 1 p.3-4; the author's words 22607 and 22627: an identity is born only on the phone; the Mac and the web
// sign in by QR) ──
// The new device draws a QR of 64 bytes: a one-time secret L and the SHA-256 of a one-time ML-KEM-768 key whose secret half lives in
// this process alone. It lays the key in a box named by L; the phone that scanned the QR takes the key from there, checks it against
// the QR -- a node cannot swap it -- and lays back the 24 words sealed to that key. Nothing new is made: the seal is MTRoomSeal, the box
// is a pipe of the keeping road (MTKeeping.knock, the pickup), and the words open by the one function of «Restore». A photo of the QR
// opens the box but not the gift: it is sealed to a key whose secret half never leaves the new device's memory. The box lives ten
// minutes; the QR is one-time. Both screens show one number of six digits, so the person sees they joined these two screens.
enum MTDeviceLink {
    static let scheme = "montana:link:1:"   // NOT-UI: the QR's own prefix
    static let boxName = "link"   // NOT-UI: the name the link box is heard under, never a pipe of the book
    static let life: TimeInterval = 600
    /// The new device's side of one joining: the secret of the box, the one-time key, and the name it knocks under.
    struct Offer {
        let l: Data, pub: Data, sec: Data, ref: String, at: Date
        var code: String { MTDeviceLink.scheme + (l + MTDeviceLink.digest(pub)).base64urlNoPad }
        var check: String { MTDeviceLink.check(l, pub) }
    }
    /// What the phone gives: the words, the phone's writer tag, the days after which a device the phone has not heard ends itself, and
    /// the phone's clock at the giving -- the joining's own moment: a word end said before it never reaches it (MTLinkedDevices.end).
    struct Gift { let words: String; let phone: String; let days: Int; let at: Double? }
    /// What the phone took from the box, held against the QR: the new device's key, and the number of both screens.
    struct Key { let l: Data, pub: Data; var check: String { MTDeviceLink.check(l, pub) } }

    static func digest(_ d: Data) -> Data { Data(SHA256.hash(data: d)) }
    static func boxSecret(_ l: Data) -> Data {
        var d = Data("mt-link-box".utf8); d.append(0); d.append(l)   // LOCAL-HASH-OK: the link box's own label
        return digest(d)
    }
    static func bind(_ l: Data, _ pub: Data) -> Data {
        var d = Data("mt-link".utf8); d.append(0); d.append(l); d.append(digest(pub))
        return d
    }
    static func check(_ l: Data, _ pub: Data) -> String {
        var d = Data("mt-link-check".utf8); d.append(0); d.append(l); d.append(pub)   // LOCAL-HASH-OK: the number both screens show
        let n = digest(d).prefix(4).reduce(UInt32(0)) { a, b in a &* 256 &+ UInt32(b) } % 1_000_000
        return String(format: "%06u", n)   // NOT-UI: six digits
    }
    static func parse(_ code: String) -> (l: Data, commit: Data)? {
        guard code.hasPrefix(scheme), let d = Data(base64urlNoPad: String(code.dropFirst(scheme.count))), d.count == 64 else { return nil }
        return (Data(d.prefix(32)), Data(d.suffix(32)))
    }
    private static func freshRef() -> String { "link#" + montanaRandom(8).montanaHexString }   // NOT-UI: a name for one joining
    private static func words(in l: Data, ref: String, keep: Bool) async -> [[String: Any]] {
        var rows: [[String: String]] = []
        let ear = MontanaWakePush.BoxEar(invites: [], pipes: [boxName: MTPipeKey(boxSecret(l))], owner: ref)
        _ = await MontanaWakePush.pickup(ear, buries: nil, keep: { row in rows.append(row); return keep })
        return rows.compactMap { r in MTKeeping.word(r["t"] ?? "") }
    }

    // ── the new device ──
    static func offer() async -> Offer? {
        guard let kp = MTRoomSeal.keypair() else { return nil }
        let o = Offer(l: montanaRandom(32), pub: kp.pub, sec: kp.sec, ref: freshRef(), at: Date())
        // THE KEY ALONE RIDES THE BOX (OZ 2, 16.11.2026): before the words this device has no writer tag of its own -- E2E.deviceTag
        // reads the seed, and every new device named the one tag of «ios-pending». The phone listed that tag (a session no button
        // reached) while the device's own tag, ended before, stayed ended and was told end at each joining. The phone lists the device
        // by its first letter in the seed's pipe; a joining anew lifts an older end by the gift's moment (MTLinkedDevices.endedAgain).
        let word: [String: Any] = ["w": "lk", "v": 1, "pk": kp.pub.base64urlNoPad]
        let laid = await MTKeeping.knock(boxSecret(o.l), word, silent: true, sender: o.ref)
        MontanaTrace.mark("link_offer", "boxed=\(laid ? 1 : 0)")
        return laid ? o : nil
    }
    /// The gift of the phone, read every three seconds while the QR lives; nil when it did not come.
    static func gift(for o: Offer) async -> Gift? {
        let bound = bind(o.l, o.pub)
        while Date().timeIntervalSince(o.at) < life, !Task.isCancelled {
            for w in await words(in: o.l, ref: o.ref, keep: true) where (w["w"] as? String) == "lg" {
                guard let ct = (w["ct"] as? String).flatMap({ s in Data(base64urlNoPad: s) }),
                      let box = (w["b"] as? String).flatMap({ s in Data(base64urlNoPad: s) }),
                      let plain = MTRoomSeal.open(box, ct: ct, sec: o.sec, bind: bound),
                      let g = (try? JSONSerialization.jsonObject(with: plain)) as? [String: Any],
                      let s = g["s"] as? String else {
                    MontanaTrace.mark("link_gift", "a gift that does not open here")
                    continue
                }
                MontanaTrace.mark("link_gift", "opened")
                return Gift(words: s, phone: g["p"] as? String ?? "", days: g["e"] as? Int ?? MTLinkedDevices.defaultDays, at: g["t"] as? Double)
            }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }
        return nil
    }

    // ── the phone ──
    /// The new device's key, taken from the box and held against the QR: a key the QR does not name is never sealed to.
    static func key(of code: String) async -> Key? {
        guard let (l, commit) = parse(code) else { return nil }
        let ref = freshRef()
        for _ in 0..<10 {
            // The key stays in the box (a public key; the gift is sealed to a secret that never leaves the new device): a joining that
            // failed on the phone is scanned again from the same QR, never met with «not found» while the Mac still shows it.
            for w in await words(in: l, ref: ref, keep: true) where (w["w"] as? String) == "lk" {
                if let pk = (w["pk"] as? String).flatMap({ s in Data(base64urlNoPad: s) }), pk.count == MTRoomSeal.pubSize, digest(pk) == commit {
                    return Key(l: l, pub: pk)
                }
                MontanaTrace.mark("link_key", "a key the QR does not name")
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        return nil
    }
    /// The words, sealed to the new device's key alone; only after the person's own Face ID or passcode on the phone (the caller).
    static func give(_ k: Key) async -> Bool {
        guard let words = MontanaSeed.mnemonic else { return false }
        let g: [String: Any] = ["s": words, "p": MontanaArchive.writerTagHex(), "e": MTLinkedDevices.days, "t": Date().timeIntervalSince1970]
        guard let plain = try? JSONSerialization.data(withJSONObject: g),
              let sealed = MTRoomSeal.seal(plain, to: k.pub, bind: bind(k.l, k.pub)) else { return false }
        let o: [String: Any] = ["w": "lg", "v": 1, "ct": sealed.ct.base64urlNoPad, "b": sealed.box.base64urlNoPad]
        let laid = await MTKeeping.knock(boxSecret(k.l), o, silent: true, sender: freshRef())
        MontanaTrace.mark("link_give", "boxed=\(laid ? 1 : 0)")
        if laid { await MTKeeping.shared.lightForLink() }   // the history's one owner lays the copy for this joining (decision 989 = a)
        return laid
    }
}

/// THE DEVICES OF ONE IDENTITY (the author's word 22627: Settings -- Devices; a device not heard ends itself after 1 week, 1, 3 or 6
/// months). The phone's choice rides in each gift; the list of devices is the one book of the seed's devices heard (twinDevicesKey).
enum MTLinkedDevices {
    static let daysKey = "mt.link.days"   // NOT-UI: the phone's choice: a device not heard this many days ends itself
    static let defaultDays = 182
    static let choices = [7, 30, 91, 182]
    static var days: Int {
        let d = UserDefaults.standard.integer(forKey: daysKey)
        return 0 < d ? d : defaultDays
    }
    static let phoneKey = "mt.link.phone"   // NOT-UI: on a device joined by QR: the phone's writer tag, its days, when it was last heard
    /// THE MAC AND THE WEB ARE JOINED DEVICES (22627): they sign in by the phone's QR and never bring an identity into being.
    static var joinsOnly: Bool { ProcessInfo.processInfo.isMacCatalystApp || ProcessInfo.processInfo.isiOSAppOnMac }
    /// THE KIND OF A JOINED DEVICE (constitution 15): its letters name it so, and only a device of this kind erases itself on the
    /// word end -- a phone or an iPad of the same seed keeps its identity, so the phone never offers to end it.
    static let joinedKind = "Mac"   // NOT-UI: a product name
    /// The kind this device's letters name it by in the phone's list: the platform's own product name.
    static var kind: String {
        if joinsOnly { return joinedKind }
        return UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"   // NOT-UI: product names
    }
    /// THE ONE STAMP OF A LETTER IN THE SEED'S PIPE (constitution 15): its kind; on the phone the term of its joined devices, on a
    /// joined device the moment of its joining by the phone's clock (the phone lifts an end older than it, endedAgain).
    static func stamp(_ o: inout [String: Any]) {
        o["d"] = kind
        if joinsOnly { if let j = joinedAt { o["j"] = j } } else { o["e"] = days }
        let now = Date().timeIntervalSince1970
        let ed = ended.filter { e in now - e.value < endsRide }
        if !ed.isEmpty { o["ed"] = ed }   // the sessions this device ended: part of the history, on every letter (OZ 1 p.7)
    }
    /// THE SESSIONS ENDED ARE PART OF THE HISTORY (OZ 1 p.7; the author's words 23250, 23276): the word end was boxed once, a box
    /// keeps a day, and a device away longer heard of its end only when its own next letter made the phone tell it again; the
    /// seed's other devices kept an ended Mac in their lists. Now every letter of the seed's pipe carries the ends its device said
    /// within a month (stamp): the device ended hears it from any letter of any device and leaves at once, and every device's
    /// list loses an ended Mac. A device of the words is never taken off another's list by a word: only a joined kind leaves.
    static let endsRide: Double = 30 * 86_400
    static func heardEnds(_ ed: [String: Double]) {
        let mine = MontanaArchive.writerTagHex()
        var e = ended, added = 0
        for (t, at) in ed {
            if t == mine { end("a device of the seed ended this session", said: at); continue }
            guard e[t] == nil, names[t] == joinedKind else { continue }
            e[t] = at; added += 1
        }
        if 0 < added { UserDefaults.standard.set(e, forKey: endedKey) }
    }
    static let namesKey = "mt.link.names"   // NOT-UI: [writer tag: the kind its letters named]
    static let endedKey = "mt.link.ended"   // NOT-UI: on the phone: [writer tag: when the person ended its session]
    static var names: [String: String] { (UserDefaults.standard.dictionary(forKey: namesKey) as? [String: String]) ?? [:] }
    static var ended: [String: Double] { (UserDefaults.standard.dictionary(forKey: endedKey) as? [String: Double]) ?? [:] }
    /// One device of the seed in the phone's list: its writer tag, its kind, when it was last heard. EVERY SESSION ENDS (the author's
    /// word 22854): ending takes any device off the list; a joined one erases itself on the word end, a device that holds the words
    /// keeps them (MTLinkedDevices.end).
    struct Device: Identifiable {
        let id: String; let kind: String; let heard: Date
        var joined: Bool { kind == MTLinkedDevices.joinedKind }   // the one kind that erases itself on the word end
    }
    /// THE LIST IS THE BOOK OF THE SEED'S DEVICES HEARD (twinDevicesKey, its one owner MontanaArchive.heardTwin), within the term,
    /// without the sessions ended here, the last heard first.
    static var list: [Device] {
        let now = Date().timeIntervalSince1970, term = Double(days) * 86_400
        let book = (UserDefaults.standard.dictionary(forKey: MontanaArchive.twinDevicesKey) as? [String: [Double]]) ?? [:]
        let n = names, gone = ended
        return book.compactMap { e in
            guard e.value.count == 2, now - e.value[0] < term, gone[e.key] == nil else { return nil }
            return Device(id: e.key, kind: n[e.key] ?? "", heard: Date(timeIntervalSince1970: e.value[0]))
        }.sorted { a, b in b.heard < a.heard }
    }
    /// «End session»: the word end in the seed's pipe names the device; it erases itself on hearing it (MontanaArchive.twinTakes).
    static func endSession(_ tag: String) {
        var e = ended; e[tag] = Date().timeIntervalSince1970
        UserDefaults.standard.set(e, forKey: endedKey)
        tellEnd(tag)
    }
    /// «End all sessions» (the author's word 22854): every device of the list, each by the one door of a single end.
    static func endAll() { for d in list { endSession(d.id) } }
    /// The word end carries the moment of the ending: a device joined anew after it never obeys it (MTLinkedDevices.end).
    private static func tellEnd(_ tag: String) {
        let at = ended[tag] ?? Date().timeIntervalSince1970
        Task.detached(priority: .userInitiated) {
            guard let secret = MontanaArchive.twinSecret() else { return }
            let told = await MTKeeping.knock(secret, ["w": "end", "t": tag, "at": at], silent: true, sender: MontanaArchive.twinDeviceRef)
            MontanaTrace.mark("link_end", "told=\(told ? 1 : 0)")
        }
    }
    private static let toldLock = NSLock()
    private static var toldAt: [String: Double] = [:]
    /// AN ENDED DEVICE STILL HEARD IS TOLD AGAIN (a box keeps a day: a Mac away longer never read the first word): at most once in
    /// ten minutes; it never returns to the list -- unless a phone of the seed joined it anew after the end (its letter's moment of
    /// joining, `joined`, by the phone's clock): that session stands, and the end is lifted.
    static func endedAgain(_ tag: String, joined: Double?) -> Bool {
        guard let at = ended[tag] else { return false }
        if let joined, at < joined {
            var e = ended; e[tag] = nil
            UserDefaults.standard.set(e, forKey: endedKey)
            return false
        }
        let now = Date().timeIntervalSince1970
        let due: Bool = toldLock.withLock {
            guard 600 < now - (toldAt[tag] ?? 0) else { return false }
            toldAt[tag] = now
            return true
        }
        if due { tellEnd(tag) }
        return true
    }
    static func joined(_ g: MTDeviceLink.Gift) {
        let now = Date().timeIntervalSince1970
        UserDefaults.standard.set(["p": g.phone, "e": g.days, "h": now, "j": g.at ?? now], forKey: phoneKey)
    }
    /// On a joined device: the moment the phone gave it the words, by the phone's clock (an older phone's gift -- by this one's).
    static var joinedAt: Double? { UserDefaults.standard.dictionary(forKey: phoneKey)?["j"] as? Double }
    /// On a joined device: the phone that joined it, its writer tag and the gift's moment -- its copy is the history (decision 989 = a).
    static var joinedPhone: (tag: String, at: Double)? {
        guard let p = UserDefaults.standard.dictionary(forKey: phoneKey)?["p"] as? String, !p.isEmpty, let j = joinedAt else { return nil }
        return (p, j)
    }
    /// A letter of the seed's other device was heard: when it is the phone that joined this device, its days count again from now,
    /// under the choice its letter carries.
    static func heard(_ tag: String, days: Int?, kind: String?) {
        if let kind, !kind.isEmpty, kind.count < 17, names[tag] != kind {
            var n = names; n[tag] = kind
            UserDefaults.standard.set(n, forKey: namesKey)
        }
        guard var m = UserDefaults.standard.dictionary(forKey: phoneKey), (m["p"] as? String) == tag else { return }
        m["h"] = Date().timeIntervalSince1970
        if let days, MTLinkedDevices.choices.contains(days) { m["e"] = days }
        UserDefaults.standard.set(m, forKey: phoneKey)
    }
    /// THE DEVICE FORGETS THE PERSON HERE ALONE (constitution 15: one owner of the local erase): the shelf, the archive's folders,
    /// the store and the seed leave this device; nothing is asked of the keepers or the cloud. «Delete account» runs it after its
    /// own releases; an ended session and a term run out run it alone -- the person's copies stay for the phone.
    @MainActor static func eraseHere() async {
        MontanaBackup.sweep(all: true)
        let store = ChatStore.live
        let convs = store.map { s in Array(s.messages.keys) } ?? []
        await withCheckedContinuation { c in MontanaArchive.eraseForDeletion(convRefs: convs, alone: !MTSeats.anyParked) { c.resume() } }
        store?.wipeLocal()
        for k in [phoneKey, namesKey, endedKey] { UserDefaults.standard.removeObject(forKey: k) }
        SeedScope.forget()
    }
    /// The phone ended this device's session (its word «end» in the seed's pipe, `said` its moment), or the term ran out: only a
    /// joined device ends, and never on a word said before its joining -- the box keeps an older end a day (OZ 2, 16.11.2026).
    private static var erasing = false   // guarded by toldLock: every letter carries the end now, and one erase runs at a time
    static func end(_ why: String, said: Double? = nil) {
        guard joinsOnly else { return }
        if let said, let j = joinedAt, said < j {
            return MontanaTrace.mark("link_end", "older than the joining said=\(Int(said)) joined=\(Int(j))")
        }
        let first: Bool = toldLock.withLock {
            guard !erasing else { return false }
            erasing = true
            return true
        }
        guard first else { return }
        MontanaTrace.mark("link_end", why)
        Task { @MainActor in
            await eraseHere()
            toldLock.withLock { erasing = false }
        }
    }
    /// A joined device the phone has not heard for its days ends itself -- offline too (the author's word 22627).
    static var expired: Bool {
        guard let m = UserDefaults.standard.dictionary(forKey: phoneKey), let h = m["h"] as? Double, let e = m["e"] as? Int else { return false }
        return Double(e) * 86_400 < Date().timeIntervalSince1970 - h
    }
}
