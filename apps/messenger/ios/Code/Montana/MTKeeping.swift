import Foundation
import CryptoKit
import SwiftUI
import UIKit
import UserNotifications
import MontanaBindings

// THE COPY KEPT BY THE PEOPLE ONE WRITES TO (the author's words 08.10.2026, 19:2x-20:3x MSK: «restore by the words fully, byte
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
    /// ON BY DEFAULT, ASKED AT THE OPENING (the author's word 08.10.2026 23:2x MSK: «on by default, and a question at the
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
    /// The first screen lets the person in the moment the light copy is laid (App: «once the light copy is laid»).
    var onLight: (() -> Void)? = nil
    private var takingTask: Task<Void, Never>? = nil
    private var roads: [String: (at: Double, road: [String: Any])] = [:]

    private init() { reread() }
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
    private func say(_ conv: String, _ o: [String: Any]) {
        guard let d = try? JSONSerialization.data(withJSONObject: o), let s = String(data: d, encoding: .utf8) else { return }
        MontanaDeliveryEngine.shared.enqueue(to: conv, chat: conv, mid: UUID().uuidString, text: keepMark + s, silent: true)
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
            owner.renewedAt = 0; saveOwner(); tick()
        } else {
            for conv in owner.keepers.keys { say(conv, ["w": "release"]) }
            owner = Owner(generation: owner.generation); saveOwner()
        }
    }
    /// THE OWNER'S RHYTHM: a renewal is due a day after the last; it asks the people I write to, waits ten minutes for one yes
    /// at least (a full ring goes at once), and an hour without one leaves the copy where it stands until tomorrow.
    func tickSoon() { DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in self?.tick() } }
    func tick() {
        guard Self.mine, Self.told, Self.agrees, MontanaSeed.hasSeed else { return }
        let now = Date().timeIntervalSince1970
        if !lighting, now - (owner.lightAt ?? 0) >= 86_400 { layLight() }
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
        guard now - owner.renewedAt >= 86_400 else { return }
        ask()
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
        renewing = true
        owner.asking = nil; saveOwner()
        // THE RING IN THE ORDER OF THE LATEST LETTER (Network): the people written to last stand first, a full ring at most.
        let rank: [String: Int] = Dictionary(people().enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        let chosen = Array(owner.yes.sorted { (rank[$0] ?? Int.max) < (rank[$1] ?? Int.max) }.prefix(MTKeepRing.most))
        CopyInventory.gather { inv in
            MontanaBackup.create(scope: inv.scope(CopyPlan.load()), urgent: false) { r in
                let me = MTKeeping.shared
                switch r {
                case .failure(let e):
                    me.renewing = false
                    MontanaTrace.mark("keep_copy", "refused " + String(describing: e))
                case .success(let made):
                    Task { await me.hand(made, g: g, keepers: chosen) }
                }
            }
        }
    }
    /// THE COPY HANDED AROUND THE RING: cut at the sixteen slots of a group (Canon: n is erasure_group), every share laid on the
    /// nodes ONCE and its road handed to each keeper of its slot -- the ring costs the network a copy and a third, whatever the
    /// number of keepers.
    private func hand(_ made: MontanaBackup.Made, g: UInt64, keepers: [String]) async {
        defer { MontanaBackup.discard(made); renewing = false }
        let n = MTKeepCode.group
        guard let m = MontanaSeed.mnemonic, let master = MontanaQueueKeys.masterSeed(m), let key = MTKeepDerive.keepKey(master),
              let dir = try? MontanaBackup.shelf() else { return }
        let url = made.url
        guard let cut = await Task.detached(priority: .utility, operation: { MTKeepCode.cut(url, n: n, into: dir) }).value else {
            return MontanaTrace.mark("keep_cut", "refused n=\(n)")
        }
        defer { for u in cut.shares { try? FileManager.default.removeItem(at: u) } }
        var roads: [Int: [String: Any]] = [:]
        for k in 0..<n { if let road = await Self.lay(cut.shares[k]) { roads[k] = road } }
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
        owner.keepers = sent; owner.n = n; owner.generation = g; owner.yes = []; owner.short = false
        owner.renewedAt = Date().timeIntervalSince1970
        saveOwner()
        MontanaTrace.mark("keep_hand", "g=\(g) keepers=\(sent.count) parts=\(parts) laid=\(roads.count) bytes=\(cut.length)")
    }

    // ── the light copy (Network «The light copy»; the author's word 08.10.2026 23:5x MSK: «the person, the face, the name and
    // everything else back by the words, down to the chess games») ──
    /// THE COPY WITHOUT ITS ATTACHMENTS -- every letter, every room, the profile, the faces and the head of every
    /// correspondence -- sealed as every copy is, laid on the nodes and named by one letter in the pipe of light, once a day while
    /// the copy is kept. The pieces live a week there and the letter in the box as long, so a phone lost today is opened by the
    /// words alone tomorrow.
    private func layLight() {
        guard !lighting else { return }
        lighting = true
        let g = (owner.lightGen ?? 0) + 1
        CopyInventory.gather { inv in
            var scope = inv.scope(CopyPlan.load())
            scope.skipKinds = Set(MontanaBackup.Kind.allCases)   // every letter, no attachment: the attachments come from the keepers
            MontanaBackup.create(scope: scope, urgent: false) { r in
                let me = MTKeeping.shared
                switch r {
                case .failure(let e):
                    me.lighting = false
                    MontanaTrace.mark("keep_light", "refused " + String(describing: e))
                case .success(let made):
                    Task { await me.nameLight(made, g: g) }
                }
            }
        }
    }
    private func nameLight(_ made: MontanaBackup.Made, g: UInt64) async {
        defer { MontanaBackup.discard(made); lighting = false }
        guard let m = MontanaSeed.mnemonic, let master = MontanaQueueKeys.masterSeed(m), let secret = MTKeepDerive.lightSecret(master),
              let digest = MontanaHomeNode.digest(of: made.url), var road = await Self.lay(made.url) else {
            return MontanaTrace.mark("keep_light", "the light copy did not reach the nodes")
        }
        road["w"] = "light"; road["g"] = Int(g); road["d"] = digest; road["v"] = MontanaArchive.writerTagHex()   // the device that laid it
        road["a"] = Bundle.main.bundleIdentifier ?? ""   // and the app on it: two apps of one phone are two writers of the same words
        // The sender of the pipe of light is named «light», never this person's own reference: a phone opening the same words reads
        // the box under that reference, and a letter of its own name the node would keep from it.
        guard await Self.knock(secret, road, sender: Self.lightName) else { return MontanaTrace.mark("keep_light", "no door boxed the road") }
        owner.lightGen = g; owner.lightAt = Date().timeIntervalSince1970; saveOwner()
        MontanaTrace.mark("keep_light", "named g=\(g) bytes=\(made.tally.bytes) chats=\(made.tally.chats)")
    }
    nonisolated static let lightName = "light"   // NOT-UI: the name the pipe of light is heard and sent under
    /// THE LIGHT COPY TAKEN BACK: the pipe of light read, and the newest road OF EVERY DEVICE that names one there taken -- two
    /// devices of the same words count their generations each from one, so the highest number is no measure across them, and
    /// the poorer copy could stand in for the richer. Each is checked by its digest and laid, the largest first; a copy
    /// laid merges and erases nothing, so one laid after another adds only what it alone holds. The person stands in their
    /// correspondences from the first laid. The box keeps the letters: the next phone of the same words reads them too.
    private func takeLight(_ secret: Data, dir: URL) async -> Bool {
        var rows: [[String: String]] = []
        let ear = MontanaWakePush.BoxEar(invites: [], pipes: [Self.lightName: secret], owner: MontanaSeed.twin ?? "")
        _ = await MontanaWakePush.pickup(ear, buries: nil, keep: { row in rows.append(row); return false })
        var newest: [String: [String: Any]] = [:]
        for o in rows.compactMap({ Self.word($0["t"] ?? "") }) where (o["w"] as? String) == "light" {
            // THE NEWEST ROAD OF EVERY WRITER, A DEVICE AND THE APP ON IT (09.10.2026): two apps of one phone and the same words
            // count their generations each from one, and one standing for both laid a copy without the other's profile (T1:
            // the name, the face and the page's ground stayed behind).
            let v = (o["v"] as? String ?? "") + "/" + (o["a"] as? String ?? "")
            if (o["g"] as? Int ?? 0) >= (newest[v]?["g"] as? Int ?? -1) { newest[v] = o }
        }
        let roads = newest.values.sorted { ($0["z"] as? Int ?? 0) > ($1["z"] as? Int ?? 0) }
        guard !roads.isEmpty else {
            MontanaTrace.mark("keep_light", "the pipe of light holds no road")
            return false
        }
        var laid = 0
        for road in roads {
            guard let d = road["d"] as? String else { continue }
            let url = dir.appendingPathComponent(UUID().uuidString + "." + MontanaBackup.ext)
            defer { try? FileManager.default.removeItem(at: url) }
            taking = .fetching(0)
            guard await Self.fetch(road, to: url, progress: { f in Task { @MainActor in MTKeeping.shared.taking = .fetching(f) } }),
                  MontanaHomeNode.digest(of: url) == d else {
                MontanaTrace.mark("keep_light", "a light copy did not come whole")
                continue
            }
            taking = .laying(0)
            let r: Result<MontanaBackup.Tally, MontanaBackup.Refusal> = await withCheckedContinuation { c in
                MontanaBackup.restore(from: url, progress: { f in Task { @MainActor in MTKeeping.shared.taking = .laying(f) } }) { c.resume(returning: $0) }
            }
            reread()
            MontanaTrace.mark("keep_light", "laid=\(String(describing: r)) devices=\(roads.count)")
            guard case .success = r else { continue }
            laid += 1
            if laid == 1 { let letIn = onLight; onLight = nil; letIn?() }
        }
        return laid > 0
    }

    // ── the cargo road of a part ──
    /// A PART ON THE CARGO ROAD: sealed in pieces under a fresh key and put on the nodes, and its list of pieces sealed as one
    /// more piece -- the word that names a part carries that piece's name and key, never the list (a list outgrows a letter).
    nonisolated static func lay(_ url: URL) async -> [String: Any]? {
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
        guard await Self.fetch(o, to: landing), MontanaHomeNode.digest(of: landing) == head.shareDigest.montanaHexString else {
            try? FileManager.default.removeItem(at: landing)
            return MontanaTrace.mark("keep_part", "the part did not come whole")
        }
        try? FileManager.default.removeItem(at: dest)
        guard (try? FileManager.default.moveItem(at: landing, to: dest)) != nil else { return }
        let first = !held.keys.contains { Self.convOf($0) == conv }
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
        if first { tell(conv, size) }
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
    /// THE PERSON IS TOLD whose part this phone holds and how many bytes, the moment it first holds one (App, «What a client
    /// owes the person»).
    private func tell(_ conv: String, _ bytes: Int) {
        let name = ChatStore.live?.peerNames[conv] ?? ""
        let c = UNMutableNotificationContent()
        c.title = String(localized: "Keeping a copy", bundle: MTLanguage.bundle)
        c.body = String(format: String(localized: "%@ keeps a sealed part of their copy on this phone (%@). Nobody can open it here.", bundle: MTLanguage.bundle), name, mtSize(bytes))
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "keep-" + UUID().uuidString, content: c, trigger: nil))
    }
    /// The pipes of the slots this phone holds, heard in the box beside every correspondence (MontanaWakePush.fetchBox).
    nonisolated static func listening() -> [String: Data] {
        guard agrees else { return [:] }
        var out: [String: Data] = [:]
        for (conv, h) in heldNow() { out[pipePrefix + conv] = h.secret }
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
        // THE CALL CAME BY A PUSH (the author's word 08.10.2026 22:4x MSK: «the whole restore by silent pushes»): the phone is
        // awake for seconds, and the system is asked for the time the answer takes.
        let task = UIApplication.shared.beginBackgroundTask(withName: "keep-answer")
        defer { if task != .invalid { UIApplication.shared.endBackgroundTask(task) } }
        var road: [String: Any]
        if let r = h.road, let at = h.roadAt, now - at < 6 * 86_400, let z = Int(r["z"] ?? ""), z == h.bytes {
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
        guard let twin = sender ?? MontanaSeed.twin, let d = try? JSONSerialization.data(withJSONObject: o),
              let s = String(data: d, encoding: .utf8) else { return false }
        let mid = UUID().uuidString
        guard let plain = MTNodeWire.padEnvelope(MTNodeWire.letterHead(mid: mid, text: keepMark + s, name: "", glyph: "")) else { return false }
        let k = await MTNodeWire.knockLetter(secret: secret, twinRef: twin, mid: mid, plain: plain,
                                             doors: MontanaWakePush.oneDoorPerNode(MontanaWakePush.orderedBases(for: "box")), silent: silent)
        return k.boxed
    }

    // ── the correspondence given back (Network «The correspondence given back»; the author's word 08.10.2026 23:5x MSK: «by
    // default every correspondent keeps the conversation with their correspondent and, if it is saved, gives it to the one who
    // restores») ──
    nonisolated static let askedBackKey = "mt.keep.back.asked"   // NOT-UI: the correspondences this phone asked to give back, and when (SeedScope.deviceKeys)
    private var answeredBack: [String: Double] = [:]
    private func askedBack() -> [String: Double] { (UserDefaults.standard.dictionary(forKey: Self.askedBackKey) as? [String: Double]) ?? [:] }
    private func lastLetter(_ conv: String) -> Double { ChatStore.live?.messages[conv]?.map(\.createdAt).max() ?? 0 }
    /// THE REQUEST: once a copy is laid, every correspondence of a person it names is asked in its own pipe, with the moment of
    /// the last letter laid there; the answer is awaited a week, as long as the pieces it rides live.
    private func askBack() {
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
            $0.createdAt > since && !$0.text.isEmpty && $0.imageFile == nil && $0.videoFile == nil && $0.audioFile == nil && $0.docFile == nil
        }
        guard !rows.isEmpty else { return say(conv, ["w": "given", "c": 0]) }
        let list: [[String: Any]] = rows.map { ["i": $0.msgId ?? "", "m": $0.isFromMe ? 1 : 0, "t": $0.createdAt, "x": $0.text] }
        guard let body = try? JSONSerialization.data(withJSONObject: list), let dir = try? MontanaBackup.shelf() else { return }
        let url = dir.appendingPathComponent(UUID().uuidString + ".given")
        defer { try? FileManager.default.removeItem(at: url) }
        guard (try? body.write(to: url)) != nil, let digest = MontanaHomeNode.digest(of: url), var road = await Self.lay(url) else {
            return MontanaTrace.mark("keep_back", "the letters did not reach the nodes")
        }
        road["w"] = "given"; road["c"] = rows.count; road["d"] = digest
        say(conv, road)
        MontanaTrace.mark("keep_back", "gave=\(rows.count) bytes=\(body.count) conv=" + String(conv.prefix(10)))
    }
    /// THE CORRESPONDENCE TAKEN BACK: only an answer to this phone's own request, only the letters later than the last one in that
    /// correspondence here -- a letter erased before the copy stays erased -- each on the side of the one who wrote it.
    private func takeGiven(_ conv: String, _ o: [String: Any]) async {
        guard let at = askedBack()[conv], Date().timeIntervalSince1970 - at < 7 * 86_400, (o["c"] as? Int ?? 0) > 0,
              let d = o["d"] as? String, let dir = try? MontanaBackup.shelf() else { return }
        let url = dir.appendingPathComponent(UUID().uuidString + ".given")
        defer { try? FileManager.default.removeItem(at: url) }
        guard await Self.fetch(o, to: url), MontanaHomeNode.digest(of: url) == d, let data = try? Data(contentsOf: url),
              let list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]], let store = ChatStore.live else {
            return MontanaTrace.mark("keep_back", "the given letters did not come whole")
        }
        // The copies' last letter is the last one older than the request: a letter that came live after it is no measure.
        let since = store.messages[conv]?.filter { $0.createdAt < at }.map(\.createdAt).max() ?? 0
        let rows: [Message] = list.compactMap { e in
            guard let t = e["t"] as? Double, t > since, let x = e["x"] as? String, !x.isEmpty else { return nil }
            let mine = (e["m"] as? Int ?? 0) == 0   // the other side's own letter is the other side's here
            let mid = "given:" + ((e["i"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? String(t))
            return Message(text: x, isFromMe: mine, time: hhmm(at: t), isRead: true, deliveryStatus: mine ? .sent : .read, msgId: mid, createdAt: t)
        }
        let laid = store.layGivenBack(conv, rows)
        MontanaTrace.mark("keep_back", "took=\(laid) of \(list.count) conv=" + String(conv.prefix(10)))
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

    private struct Answer { let head: MTKeepDerive.Head; let url: URL }
    private func callAndBuild() async -> Result<MontanaBackup.Tally, MontanaBackup.Refusal> {
        guard Self.agrees, let m = MontanaSeed.mnemonic, let master = MontanaQueueKeys.masterSeed(m),
              let key = MTKeepDerive.keepKey(master), let dir = try? MontanaBackup.shelf() else { taking = .failed; return .failure(.noSeed) }
        let secrets = (0..<MTKeepDerive.slots).compactMap { MTKeepDerive.slotSecret(master, $0) }
        guard secrets.count == MTKeepDerive.slots else { taking = .failed; return .failure(.noSeed) }
        var pipes: [String: Data] = [:]
        for (k, s) in secrets.enumerated() { pipes[Self.callPrefix + String(k)] = s }
        var answers: [String: Answer] = [:]
        var lastCall = 0.0, lastLoud = 0.0
        let began = Date().timeIntervalSince1970
        taking = .fetching(0)
        // THE LIGHT COPY FIRST (Network «The light copy»): the pipe of light is read before any call, and the person is let in.
        if let ls = MTKeepDerive.lightSecret(master), await takeLight(ls, dir: dir) { askBack() }   // the pipes it named are asked to give back
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
            // IF NEEDED, A LOUD PUSH (the author's word 08.10.2026 22:4x MSK): six minutes of silence from a slot, and the call
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
            let ear = MontanaWakePush.BoxEar(invites: [], pipes: pipes, owner: MontanaSeed.twin ?? "")
            _ = await MontanaWakePush.pickup(ear, buries: nil, keep: { row in rows.append(row); return true })
            for row in rows {
                guard let c = row["c"], c.hasPrefix(Self.callPrefix), let k = Int(c.dropFirst(Self.callPrefix.count)),
                      let o = Self.word(row["t"] ?? ""), (o["w"] as? String) == "answer",
                      let hd = (o["h"] as? String).flatMap({ Data(montanaHex: $0) }), let head = MTKeepDerive.Head(hd), head.slot == k,
                      let seal = (o["e"] as? String).flatMap({ Data(montanaHex: $0) }), seal == MTKeepDerive.seal(key, head) else { continue }
                let id = head.copyDigest.montanaHexString + "." + String(k)
                guard answers[id] == nil else { continue }
                let url = dir.appendingPathComponent(UUID().uuidString + ".keep")
                guard await Self.fetch(o, to: url), MontanaHomeNode.digest(of: url) == head.shareDigest.montanaHexString else {
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
                guard built, MontanaHomeNode.digest(of: out) == h0.copyDigest.montanaHexString else {
                    try? FileManager.default.removeItem(at: out)
                    MontanaTrace.mark("keep_build", "generation=\(h0.generation) did not stand")
                    continue
                }
                taking = .laying(0)
                let r: Result<MontanaBackup.Tally, MontanaBackup.Refusal> = await withCheckedContinuation { c in
                    MontanaBackup.restore(from: out, progress: { f in Task { @MainActor in MTKeeping.shared.taking = .laying(f) } }) { c.resume(returning: $0) }
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

/// THE RING OF KEEPERS (Network «The keepers are correspondents, and they stand on a ring»; the author's word 08.10.2026 23:5x
/// MSK: «not 4, 8 and so on ... between contacts in a ring, so that if someone is offline the restore is full»): every
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
        let sig: (Message) -> String = { String(Int($0.createdAt)) + "@" + ($0.isFromMe ? "1" : "0") + "@" + $0.text }
        let had = Set(feed.compactMap { $0.msgId }), seen = Set(feed.map(sig))
        let add = ChatStore.allRead(rows.filter { m in !seen.contains(sig(m)) && (m.msgId.map { !had.contains($0) } ?? true) })
        guard !add.isEmpty else { return 0 }
        feed.append(contentsOf: add)
        feed.sort(by: ChatStore.before)
        messages[conv] = feed
        for m in add { _ = MTRowJournal.put(conv, m); archiveRow(conv, m) }
        if let last = feed.max(by: ChatStore.before) {
            noteListState(conv, last: last)
            noteOrder(conv, at: Int(last.createdAt * 1000))
        }
        Self.writeSnapshotNow(messages)
        return add.count
    }
}

/// THE KEEPING IN SETTINGS, native rows: two switches, what a keeper learns said beneath them, the state in the keepers' own
/// words (a part is «held» only on its keeper's «held»), the parts this phone holds by name and size, and the road back.
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
            Text("Your copy is sealed with your 24 words and cut into parts. The people you write to keep the parts around a ring, each part with two of them: they see only its size and when it changes, and cannot open it. With your words on a new phone, the parts come back from them, and each of them gives back the conversation you share.")
        }
        .listRowBackground(MTGlassRowPlate())
        Section {
            Toggle(isOn: Binding(get: { MTKeeping.others }, set: { keep.setOthers($0) })) {
                settingsToggleLabel("Keep parts for my contacts", "tray.full.fill", .gray)
            }
            ForEach(keep.keptFor, id: \.self) { conv in   // one row a person, their parts summed
                HStack {
                    Text(verbatim: ChatStore.live?.peerNames[conv] ?? "").foregroundColor(.white)   // USER-DATA: a correspondent's name
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
                Text("Asking the people you write to…").foregroundColor(.secondary)
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
            Text("Parts of other people's copies are sealed: this phone cannot open them, and each goes back only to its owner's words.")
        }
        .listRowBackground(MTGlassRowPlate())
    }
}
