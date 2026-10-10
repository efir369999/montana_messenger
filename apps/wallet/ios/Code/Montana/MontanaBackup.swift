import Foundation
import CryptoKit
import UIKit
import MontanaBindings

// THE COPY IS THE ARCHIVE UNDER ONE MORE SEAL (23.09, the author's word: a copy to the cloud or by
// hand, sealed with our post-quantum key).
//
// The history of this device already lies sealed: every letter under the history branch of the seed,
// every attachment under the media branch, and the folder a conversation lives in is named by a keyed
// hash of the same seed (MontanaArchive). What was missing is not encryption but a road OUT: the
// sealed archive travels into the platform's own device backup while the seed — by design — does not,
// so a person who restored a new phone from the vendor's copy held ciphertext and no key at all.
//
// So a copy adds exactly one thing to what already exists: one more seal over the whole of it, in a
// container that can leave the device. The key of that seal comes from the same twenty-four words:
//   the words are NOT in the copy — a file found without them is a heap of bytes;
//   nothing new is invented — ChaCha20-Poly1305 and SHA-256, the primitives the core already uses,
//   over a 256-bit root, and not one classical asymmetric primitive anywhere on this road ([I-1]);
//   what the seal hides beyond the archive's own is the SHAPE: how many conversations there are,
//   which folder is which, and how large each one is.
//
// What a keeper of a cloud sees and what cannot be closed: that a file exists, how many megabytes it
// holds, and the moment it was written. That is the physical limit of handing bytes to a keeper: a
// copy cannot be smaller than what it carries, and the keeper writes down when it arrived.
//
// THE CONTAINER, version 2, byte for byte (the critic, 23.09: a copy may lie anywhere, even in plain
// sight, and then the file must say nothing but its own length):
//   0  32  salt (drawn by the core). No mark of its own: without the words the file is noise.
//  32  ..  frames, every one exactly `frameBytes` long: ChaChaPoly combined (nonce 12, ciphertext, tag 16)
//
//   backup_key = HKDF-SHA-256(ikm = entropy 32, salt = salt 32, info = "mt-backup-key-v2", 32)
//   AAD of frame i = the salt, u64 LE i, and u8 1 on the final frame (0 on every other): a frame is
//   bound to THIS copy and to ITS place, and a copy cut at a frame's edge is told from a whole one.
//
//   The frames' plaintexts, joined, are ONE stream of records -- u8 kind, u8 more, u16 LE nameLen,
//   name, u32 LE dataLen, data -- cut wherever a frame ends. Kind 1 a sealed history block, 2 a piece
//   of an archive attachment (name = folder/blob), 3 the account card, 4 a file of the correspondence
//   store, 5 a file of one of the person's other places (name = place/file), 6 a piece of the feed (the
//   conversations' rows as the feed holds them), 0 the tail: the count and the SHA-256 of every record
//   before it. The tail closes the stream; the rest of the final frame is zeros.
//
// WHY ONE STREAM IN EQUAL FRAMES (measured 23.09 on version 1 of this engine, where every record was
// sealed on its own behind a length in the clear): read without the key, a copy gave 120, 7 and 4096,
// the exact size of every letter, and 1 234 567, 3 000 001 and 4321, the exact size of every photo,
// video and voice once the fixed 36 bytes and the name were taken off. The content was closed and the
// SHAPE was open, and a known file's size is enough to say it lies in someone's copy. A keeper now
// learns one number: how many megabytes.
//
// Version 1 -- magic "MTBAK" 0x00, version 1, kdf 1, salt 32, chunk size u64; then u32 LE lengths,
// each before one record sealed alone, AAD = that 48-byte header and u64 LE index, info
// "mt-backup-key-v1" -- is still READ and never written: every copy a person made before stays a copy.
enum MontanaBackup {
    static let ext = "mtbak"                     // NOT-UI: the container's own extension
    static let chunkBytes = 1 << 20              // a megabyte: nothing larger is ever held in memory
    /// Every frame of a version-2 copy, sealed, is exactly this long: a keeper counts frames and learns
    /// nothing else of what is inside.
    static let frameBytes = 1 << 20
    private static let framePlain = frameBytes - 28          // the nonce (12) and the tag (16) take the rest
    private static let saltBytes = 32
    private static let labelV2 = Data("mt-backup-key-v2".utf8)   // NOT-UI: the derivation's own label
    // Version 1, read and never written.
    private static let magic: [UInt8] = [0x4D, 0x54, 0x42, 0x41, 0x4B, 0x00]
    private static let version: UInt8 = 1
    private static let kdfId: UInt8 = 1
    private static let headerBytes = 48
    private static let label = Data("mt-backup-key-v1".utf8)   // NOT-UI: the derivation's own label
    private static let kindBlock: UInt8 = 1
    private static let kindMedia: UInt8 = 2
    private static let kindCard: UInt8 = 3
    private static let kindTail: UInt8 = 0
    /// A file of the correspondence store — the photos, videos, voices and documents themselves.
    /// They never lived in the archive (the archive holds letters, heads and faces), and a copy that
    /// took the archive alone went out with nine attachments of a whole history (T1, 1888, 23.09
    /// 22:28Z: chats=30 rec=3743 media=9 bytes=1377440). An older reader buries this kind in silence.
    private static let kindStore: UInt8 = 4
    /// THE PERSON'S OTHER PLACES (23.09, the author's word: «everything in the app»): the faces set by hand
    /// and received, the pictures the chats' grounds stand on, the stories, and the posters, small copies,
    /// waves and marks beside every attachment. None of them reached a copy: a restored contact kept its
    /// name and lost its face, and the next launch lifted the face's mark as a picture nobody has. Each
    /// place is named once, here; a record is named «place/file». An older reader buries this kind too.
    private static let kindPlace: UInt8 = 5
    static var places: [(name: String, dir: URL)] {
        [("avatars", avatarsDirURL()), ("wallpapers", MTWallpaper.folder()), ("stories", storiesDir()),
         ("pictures", MontanaPictures.dir)]
    }
    /// THE FEED ITSELF (the critic, 23.09: «restore on T3 and see no difference»): every row as the feed holds it
    /// — its name, its rung, its answers, its quote, its group — pieced like a file. The archive's transcript
    /// renames every letter and forgets what became of it; the feed is what the person saw. An older reader
    /// buries this kind as well, and rebuilds from the archive as before.
    private static let kindFeed: UInt8 = 6
    /// What stands beside an attachment in the pictures' place, named by the attachment's own name.
    static let pictureSuffixes = [".poster.jpg", ".frame.jpg", ".small.jpg", ".wave", ".mtc"]
    /// A name a copy may write: one plain file, never a path out of its place.
    static func plainName(_ n: String) -> Bool {
        !n.isEmpty && !n.contains("/") && !n.hasPrefix(".")
    }

    /// What kind an attachment is — named by the letter that carries it, or by the file's extension
    /// when no letter on this device names it. One owner of the question.
    enum Kind: String, CaseIterable { case photo, video, voice, file }
    static func kind(ofExtension name: String) -> Kind {
        switch (name as NSString).pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "heic", "heif", "gif", "webp": return .photo
        case "mov", "mp4", "m4v": return .video
        case "m4a", "aac", "caf", "opus", "wav": return .voice
        default: return .file
        }
    }

    /// WHAT A COPY TAKES (the author, 23.09: see what is inside and choose). Everything by default. A
    /// person may leave a conversation out, a kind of attachment, or one file; the owner map names, for every
    /// file of the store a letter on this device carries, its conversation and its kind.
    struct Scope {
        var skipConvs: Set<String> = []
        var skipKinds: Set<Kind> = []
        var skipFiles: Set<String> = []
        var owner: [String: (conv: String, kind: Kind)] = [:]
        /// EVERY NAME A LEFT-OUT CONVERSATION IS KNOWN BY — its reference and its row's name — and the files of
        /// its faces: none of its names, faces, marks or choices travel. The plan's page promises exactly that
        /// («none of its letters, names, faces or attachments go into the copy»), and the card carried every
        /// name and face of every peer regardless (the critic, 23.09).
        var skipPeople: Set<String> = []
        var skipFaces: Set<String> = []
        var excluding: Bool { !skipConvs.isEmpty || !skipKinds.isEmpty }
        var people: Set<String> { skipConvs.union(skipPeople) }
        func takes(file name: String) -> Bool {
            if skipFiles.contains(name) { return false }
            let o = owner[name]
            if let c = o?.conv, skipConvs.contains(c) { return false }
            return !skipKinds.contains(o?.kind ?? MontanaBackup.kind(ofExtension: name))
        }
        /// A conversation's own key — its ground, the ground's softness — leaves with the conversation.
        func takes(key k: String) -> Bool {
            guard let p = SeedScope.dataPrefixes.first(where: { k.hasPrefix($0) }) else { return true }
            return !people.contains(String(k.dropFirst(p.count)))
        }
        /// A poster, a small copy, a wave or a mark travels exactly when the attachment it stands beside does.
        func takes(picture name: String) -> Bool {
            for s in MontanaBackup.pictureSuffixes where name.hasSuffix(s) { return takes(file: String(name.dropLast(s.count))) }
            return takes(file: name)
        }
    }
    private static let pieceBytes = (1 << 20) - 4096   // room for a record's own head inside one chunk

    /// What a copy holds — COUNTED, never promised. A number shown to a person measures what actually
    /// happened, or it is a lie with a progress bar (the rule of the honest measure).
    struct Tally: Codable, Equatable {
        var chats = 0
        var records = 0
        var media = 0
        var bytes = 0
        var skipped = 0
    }
    private struct Tail: Codable { var tally: Tally; var digest: String }
    struct Made { let url: URL; let tally: Tally }

    /// Why a copy refused. Every one is spoken to the person: a copy that half happened is worse than
    /// none at all, because a person leans on it and wipes the device.
    enum Refusal: Error {
        case noSeed
        case noVault
        case noEntropy
        case empty
        case notOurs
        case version
        case wrongWords
        /// A copy of version 2 carries no mark: a file these words do not open is a copy of another
        /// phrase or no copy at all, and nothing in the file can tell the two apart.
        case unopened
        case torn
        /// PROVEN, not guessed: the system said there is no room. Nothing else may wear this name.
        case noSpace
        /// The person stopped it: iCloud copies switched off while sealing, or a fetch cancelled.
        case stopped
        /// The step that refused and the system's own code. A single catch-all cause — «the disk
        /// refused» over six different failures — sent a person to free space on a disk with room
        /// to spare and hid the real one (the author, 23.09 00:24).
        case diskRefused(String)
        case cloudRefused(String)
    }

    /// One reading of a system error, in one place: out of space is out of space wherever the system
    /// spells it, and everything else carries the step and the code it actually returned.
    private static func refuse(_ step: String, _ e: Error) -> Refusal {
        let ns = e as NSError
        if ns.domain == NSCocoaErrorDomain, ns.code == NSFileWriteOutOfSpaceError { return .noSpace }
        if let under = ns.userInfo[NSUnderlyingErrorKey] as? NSError,
           under.domain == NSPOSIXErrorDomain, under.code == 28 { return .noSpace }
        let why = step + " " + ns.domain + " " + String(ns.code)
        MontanaP2PTrace.mark("backup_refused", why)
        return .diskRefused(why)
    }

    // ── the seal ────────────────────────────────────────────────────────────────
    private static func key(entropy: Data, salt: Data, label: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: entropy),
                               salt: salt, info: label, outputByteCount: 32)
    }
    /// Version 1: the chunk's AAD is the 48-byte header and its index.
    private static func aad(_ head: Data, _ index: UInt64) -> Data {
        var a = head
        var i = index.littleEndian
        withUnsafeBytes(of: &i) { a.append(contentsOf: $0) }
        return a
    }
    /// Version 2: the salt, the frame's index, and whether it is the final frame.
    private static func aad2(_ salt: Data, _ index: UInt64, _ last: Bool) -> Data {
        var a = salt
        var i = index.littleEndian
        withUnsafeBytes(of: &i) { a.append(contentsOf: $0) }
        a.append(last ? 1 : 0)
        return a
    }
    private static func le16(_ v: Int) -> Data { var x = UInt16(v).littleEndian; return withUnsafeBytes(of: &x) { Data($0) } }
    private static func le32(_ v: Int) -> Data { var x = UInt32(v).littleEndian; return withUnsafeBytes(of: &x) { Data($0) } }
    private static func num(_ b: [UInt8], _ o: Int, _ n: Int) -> Int {
        var v = 0
        for k in 0..<n { v = v | (Int(b[o + k]) << (8 * k)) }
        return v
    }
    private static func hex(_ d: SHA256Digest) -> String { d.map { String(format: "%02x", $0) }.joined() }

    /// THE FROZEN VECTORS OF THE SEAL (Pass 25, an independent oracle). A container's key is a value a
    /// second implementation must reproduce byte for byte, or the two write copies neither can open.
    /// Each was computed OUTSIDE this code -- RFC 5869 HKDF-SHA-256, extract then expand -- and
    /// tools/mt-copy-roundtrip.py computes them again on every commit.
    ///
    /// The first vector stands on 0x55 x 32 and a salt of zeros, and both read the same from either
    /// end: an implementation that reverses the root, or the salt, passes it (the critic, 23.09 -- the
    /// comment here once said the opposite). So each label also stands on counting bytes, the root
    /// 0x00..0x1f and the salt 0x20..0x3f, which a reversed root, a reversed salt and the two swapped
    /// all fail.
    static func keyKAT() -> Bool {
        func hexKey(_ k: SymmetricKey) -> String { k.withUnsafeBytes { Data($0) }.map { String(format: "%02x", $0) }.joined() }
        let counting = Data((0..<32).map { UInt8($0) })
        let after = Data((32..<64).map { UInt8($0) })
        return hexKey(key(entropy: Data(repeating: 0x55, count: 32), salt: Data(count: 32), label: label))
                == "bdd50e3824fb05ed88e25d379fa70b2de845cc5de0d27f037d201b39a9fb6792"
            && hexKey(key(entropy: counting, salt: after, label: label))
                == "cb836de01e5c7468cf1b7f8e4c604a1d8ff5af1a2f683e9d9ea091713d04e6dd"
            && hexKey(key(entropy: counting, salt: after, label: labelV2))
                == "ec63f219255c63640c9916705b59e10f71ec3f8a296bb048db4ed08ed4ad48e4"
            // the owner's key (no salt: RFC 5869 then keys the extract with zeros) and one proof under it
            && hexKey(ownerKey(entropy: counting))
                == "a07f0e82f8b0d5a375684f7b23a9e8a5d9015b4207620f869c9c6aa1e28750bc"
            && proof("2026-09-23-143542", ownerKey(entropy: counting)) == "fc4380015be1598a"
    }

    /// The stream of records, cut into frames of one length and sealed. The stream digest walks with
    /// the records, so the tail signs everything before it and nothing of itself. A full frame waits
    /// for the next byte: only then is it known not to be the final one.
    private final class Framer {
        private let fh: FileHandle
        private let k: SymmetricKey
        private let salt: Data
        private var index: UInt64 = 0
        private var hash = SHA256()
        private var frame = Data()
        init(_ fh: FileHandle, _ k: SymmetricKey, _ salt: Data) {
            self.fh = fh; self.k = k; self.salt = salt
            frame.reserveCapacity(MontanaBackup.framePlain)
        }
        var digestHex: String { MontanaBackup.hex(hash.finalize()) }
        func put(_ kind: UInt8, _ name: String, _ data: Data, more: Bool) throws {
            var p = Data([kind, more ? UInt8(1) : UInt8(0)])
            let n = Data(name.utf8)
            p.append(MontanaBackup.le16(n.count))
            p.append(n)
            p.append(MontanaBackup.le32(data.count))
            p.append(data)
            if kind != MontanaBackup.kindTail { hash.update(data: p) }
            var at = p.startIndex
            while at != p.endIndex {
                if frame.count == MontanaBackup.framePlain { try seal(last: false) }
                let take = min(MontanaBackup.framePlain - frame.count, p.endIndex - at)
                frame.append(p[at..<(at + take)])
                at += take
            }
        }
        /// The final frame: what is left of the stream, then zeros to the frame's full length.
        func finish() throws {
            frame.append(Data(count: MontanaBackup.framePlain - frame.count))
            try seal(last: true)
        }
        private func seal(last: Bool) throws {
            let sealed = try ChaChaPoly.seal(frame, using: k,
                                             authenticating: MontanaBackup.aad2(salt, index, last)).combined
            index += 1
            frame.removeAll(keepingCapacity: true)
            try fh.write(contentsOf: sealed)
        }
    }

    // ── the shelf ───────────────────────────────────────────────────────────────
    /// Where a copy is built and where it waits to be handed on. Outside the vendor's backup: a copy
    /// of the copy has no business riding there.
    static func shelf() throws -> URL {
        let fm = FileManager.default
        var d = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MontanaBackup", isDirectory: true)
        // The plainest creation there is: every file written here carries its own protection at the
        // moment of writing, so asking for a protection class on the FOLDER buys nothing and adds one
        // more thing that can refuse — and refuse silently, as it did (the author, 23.09 00:25).
        if !fm.fileExists(atPath: d.path) {
            try fm.createDirectory(at: d, withIntermediateDirectories: true)
        }
        if (try? d.resourceValues(forKeys: [.isExcludedFromBackupKey]))?.isExcludedFromBackup != true {
            var rv = URLResourceValues()
            rv.isExcludedFromBackup = true
            try? d.setResourceValues(rv)
        }
        return d
    }
    /// An unfinished file is not a copy and must never be found under the name of one: a build the
    /// process did not finish leaves at the next launch (the critic, 23.09). A finished one leaves
    /// too once the hand it was made for has had its hour — it has already been handed on or saved
    /// elsewhere, and a whole history of a person weighs gigabytes for nothing on this shelf.
    /// The file this process is building RIGHT NOW. Queue-only: set when the unfinished file is born,
    /// cleared when it is moved under its name or thrown away.
    ///
    /// Build 1884 (T1, 23.09 00:24 and 00:25): a sweep stood between the last chunk and the move, and
    /// the sweep removes every unfinished file — it removed the one just finished, the move found no
    /// source, and the person read «the disk refused» over a disk with room to spare. Measured on the
    /// phone: the shelf created at 00:25 and empty. The sweep now cannot touch the file being built,
    /// wherever a future hand puts the call — the rule lives in the sweep, not in the order of lines.
    private static var building: String? = nil
    static func sweep() {
        let fm = FileManager.default
        guard let dir = try? shelf() else { return }
        let hourAgo = Date().addingTimeInterval(-3600)
        for n in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where n != building {
            let u = dir.appendingPathComponent(n)
            if n.hasSuffix(".part") {
                try? fm.removeItem(at: u)
            } else if n.hasSuffix(ext) {
                let born = (try? u.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                if born < hourAgo { try? fm.removeItem(at: u) }
            }
        }
    }
    /// A finished copy nobody will take leaves the shelf at once — the shelf is the engine's, and so is this.
    static func discard(_ m: Made) { try? FileManager.default.removeItem(at: m.url) }

    /// The name of a copy carries its moment, and the moment is read back from the name — one format,
    /// one owner. A copy still in the cloud and not yet on this device is a placeholder whose size is
    /// not the copy's, but its name is the copy's own.
    ///
    /// To the SECOND (the critic, 23.09): named to the minute, a copy made by hand and the daily copy
    /// in the same minute shared one name, and the second removed the first while a share sheet held
    /// it. A name written to the minute before is still read.
    private static func stamp(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f
    }
    private static let toSecond = "yyyy-MM-dd-HHmmss"   // NOT-UI: the file's own name
    private static let toMinute = "yyyy-MM-dd-HHmm"     // NOT-UI: the file's own name, before 23.09
    private static func nameNow(_ entropy: Data) -> String {
        let moment = stamp(toSecond).string(from: Date())
        return "montana-" + moment + "-" + proof(moment, ownerKey(entropy: entropy)) + "." + ext
    }
    /// The name's parts: the moment as written, and the owner's proof when the name carries one.
    private static func parts(_ n: String) -> (moment: String, proof: String?)? {
        guard n.hasPrefix("montana-"), n.hasSuffix("." + ext) else { return nil }
        let body = String(n.dropFirst(8).dropLast(ext.count + 1))
        if let dash = body.lastIndex(of: "-") {
            let tail = body[body.index(after: dash)...]
            if tail.count == 16, tail.allSatisfy({ $0.isHexDigit }) { return (String(body[..<dash]), String(tail)) }
        }
        return (body, nil)
    }
    static func born(ofName n: String) -> Date? {
        guard let p = parts(n) else { return nil }
        return stamp(toSecond).date(from: p.moment) ?? stamp(toMinute).date(from: p.moment)
    }

    // ── whose copy ──────────────────────────────────────────────────────────────
    /// WHOSE COPY IT IS, SAID BY ITS NAME TO ITS OWNER ALONE (the author, 23.09: «on any device»). One
    /// iCloud account may hold the copies of more than one set of words — a family's phones, a second
    /// identity — and a watcher that removes «older copies» would remove another person's, and a restore
    /// would reach for a copy these words cannot open. A copy's name carries sixteen hex of HMAC-SHA-256
    /// over its own moment, keyed from the words: the owner recomputes it, and to everyone else it is
    /// noise that differs from copy to copy, so no two copies can be tied together by it.
    private static let ownerLabel = Data("mt-backup-owner-v1".utf8)   // NOT-UI: the derivation's own label
    static func ownerKey(entropy: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: entropy), salt: Data(), info: ownerLabel, outputByteCount: 32)
    }
    private static func proof(_ moment: String, _ k: SymmetricKey) -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: Data(moment.utf8), using: k)
        return String(Data(mac).map { String(format: "%02x", $0) }.joined().prefix(16))
    }
    /// true — the name proves the copy ours; false — it proves the copy another's; nil — a name written
    /// before names carried a proof, which says nothing either way.
    static func owned(name n: String, by k: SymmetricKey) -> Bool? {
        guard let p = parts(n), let pr = p.proof else { return nil }
        return pr == proof(p.moment, k)
    }
    /// Whether THESE words open a copy lying on this device: its first frame (version 2) or first chunk
    /// (version 1), read without the rest and without asking iCloud for anything. nil when the file
    /// cannot be read here.
    static func opens(_ url: URL, entropy: Data) -> Bool? {
        var answer: Bool? = nil
        var err: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &err) { u in
            guard let fh = try? FileHandle(forReadingFrom: u) else { return }
            defer { try? fh.close() }
            guard let head = try? fh.read(upToCount: headerBytes), head.count == headerBytes else { answer = false; return }
            if [UInt8](head.prefix(6)) == magic {
                guard let lenD = try? fh.read(upToCount: 4), lenD.count == 4 else { answer = false; return }
                let len = num([UInt8](lenD), 0, 4)
                guard len >= 17, len <= chunkBytes + 4096, let sealed = try? fh.read(upToCount: len), sealed.count == len,
                      let box = try? ChaChaPoly.SealedBox(combined: sealed) else { answer = false; return }
                let k = key(entropy: entropy, salt: head.subdata(in: 8..<40), label: label)
                answer = (try? ChaChaPoly.open(box, using: k, authenticating: aad(head, 0))) != nil
            } else {
                try? fh.seek(toOffset: 0)
                guard let salt = try? fh.read(upToCount: saltBytes), salt.count == saltBytes,
                      let f = try? fh.read(upToCount: frameBytes), f.count == frameBytes,
                      let box = try? ChaChaPoly.SealedBox(combined: f) else { answer = false; return }
                let k = key(entropy: entropy, salt: salt, label: labelV2)
                answer = (try? ChaChaPoly.open(box, using: k, authenticating: aad2(salt, 0, false))) != nil
                    || (try? ChaChaPoly.open(box, using: k, authenticating: aad2(salt, 0, true))) != nil
            }
        }
        return answer
    }

    // ── which copies stay in iCloud ─────────────────────────────────────────────
    /// One copy of ours in iCloud, as iCloud describes it.
    struct CloudCopyFact { let born: Date; let held: Bool; let noRoom: Bool }
    /// WHICH OF OUR COPIES LEAVE iCLOUD — one pure decision, run by the watcher and proven by
    /// mt-copy-roundtrip. `copies` are this person's copies, the newest first.
    ///   what stays: the newest copy, and the newest one iCloud holds;
    ///   a copy iCloud holds leaves only behind a newer one it holds — or by the person's word;
    ///   a copy iCloud never took leaves whenever a newer one stands (nothing of it is in iCloud);
    ///   the newest leaves when iCloud has no room for it next to a copy it holds that is not a day old
    ///   (23.09 18:24: a second copy made minutes after the first fought it for the room of a 5 GB plan);
    ///   with no room and a held copy a day old, the held one leaves only by the person's standing word.
    static func leaving(_ copies: [CloudCopyFact], now: Date, alwaysReplace: Bool) -> Set<Int> {
        guard !copies.isEmpty else { return [] }
        let heldAt = copies.firstIndex { $0.held }
        var stay: Set<Int> = [0]
        if let h = heldAt { stay.insert(h) }
        var out = Set(copies.indices).subtracting(stay)
        if let h = heldAt, h != 0, copies[0].noRoom {
            if now.timeIntervalSince(copies[h].born) < 86_400 { out.insert(0) }
            else if alwaysReplace { out.insert(h) }
        }
        return out
    }

    // ── what iCloud's word means ────────────────────────────────────────────────
    /// ONE READING OF iCLOUD'S WORD, FOR EVERY iOS (the author, 23.09 17:35, iPhone 17 on mobile data:
    /// «iCloud refused the upload: NSFileProviderErrorDomain -1004»). -1004 is
    /// NSFileProviderErrorServerUnreachable, «Connecting to the servers failed» (FileProvider,
    /// NSFileProviderError.h): iCloud had refused nothing; it had not reached its servers, and it tries
    /// again on its own. The screen called a wait a refusal. The older iCloud speaks in NSCocoaErrorDomain
    /// (4354 over quota, 4355 server unavailable); the file-provider iCloud in NSFileProviderErrorDomain
    /// (-1003 over quota, -1004 unreachable, -1000 signed out, -2011 iCloud Drive off, -2012 busy for a
    /// while); either may carry the network's own error beneath it, and the whole chain is read.
    enum CloudVerdict: Equatable { case waiting, noRoom, signIn, driveOff, refused }
    static func verdict(_ e: NSError) -> CloudVerdict {
        var chain: [NSError] = []
        var cur: NSError? = e
        while let c = cur, chain.count < 8 {
            chain.append(c)
            cur = c.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        chain += (e.userInfo["NSMultipleUnderlyingErrorsKey"] as? [NSError]) ?? []   // NOT-UI: the system's key
        let provider = "NSFileProviderErrorDomain"   // NOT-UI: FileProvider's own domain
        func has(_ domain: String, _ codes: Set<Int>) -> Bool { chain.contains { $0.domain == domain && codes.contains($0.code) } }
        if has(NSCocoaErrorDomain, [4354]) || has(provider, [-1003]) { return .noRoom }
        if has(provider, [-1000]) { return .signIn }
        if has(provider, [-2011]) { return .driveOff }
        if has(provider, [-1004, -2012]) || has(NSCocoaErrorDomain, [4355])
            || chain.contains(where: { $0.domain == NSURLErrorDomain })
            || has(NSPOSIXErrorDomain, [50, 51, 54, 57, 60, 61, 64, 65]) { return .waiting }
        return .refused
    }

    // ── making one ──────────────────────────────────────────────────────────────
    /// A COPY IS BORN ON THE QUEUE THAT OWNS THE LOG (the critic, 23.09). The writer of a letter and
    /// the reader of the copy never cross there, so a block read in half cannot happen — by
    /// construction, not by luck. Nothing on this road is ever held whole in memory.
    ///
    /// The price is named rather than hidden: while a copy is being made, the archive's own writes
    /// wait behind it on that queue. A letter still lands in the feed and in the row journal at once —
    /// those roads are elsewhere — and its place in the sealed log follows the copy. The other choice
    /// was a queue of our own, and it buys speed with a block read in half.
    static func create(scope: Scope, urgent: Bool = false, progress: @escaping (Double) -> Void = { _ in },
                       done: @escaping (Result<Made, Refusal>) -> Void) {
        MontanaArchive.onOwnQueue(urgent: urgent) {
            let r = build(scope, progress)
            DispatchQueue.main.async { done(r) }
        }
    }

    private static func build(_ scope: Scope, _ progress: @escaping (Double) -> Void = { _ in }) -> Result<Made, Refusal> {
        guard let mn = MontanaSeed.mnemonic,
              let ent = MontanaSeedKeys.entropyFrom(mnemonic: mn), ent.count == 32 else { return .failure(.noSeed) }
        // The device key is asked ONCE and before anything is written: without it the account card
        // cannot be opened, and a copy without the card would go out calling itself whole.
        guard MontanaDeviceKey.key != nil, let card = seedCard(scope) else { return .failure(.noVault) }
        var salt = Data(count: 32)
        let drawn = salt.withUnsafeMutableBytes { p -> Int32 in
            guard let b = p.bindMemory(to: UInt8.self).baseAddress else { return -1 }
            return mt_random_fast(b, 32)
        }
        guard drawn == 0 else { return .failure(.noEntropy) }

        let fm = FileManager.default
        let dir: URL
        do { dir = try shelf() } catch { return .failure(refuse("shelf", error)) }
        // THE SHELF ANSWERS BEFORE THE WORK, NOT AFTER (the author, 23.09 00:25). A probe of two
        // bytes written, read back and removed names the place and the system's own code at a moment
        // when nothing has been built yet — the same order the identity store is proved in.
        let probe = dir.appendingPathComponent("probe")   // NOT-UI: the probe's own name
        do {
            try Data([0x6D, 0x74]).write(to: probe, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            let back = try Data(contentsOf: probe)
            try fm.removeItem(at: probe)
            guard back == Data([0x6D, 0x74]) else {
                MontanaP2PTrace.mark("backup_refused", "probe readback")
                return .failure(.diskRefused("probe readback"))
            }
        } catch { return .failure(refuse("probe", error)) }
        sweep()

        let part = dir.appendingPathComponent(UUID().uuidString + ".part")   // NOT-UI: the unfinished name
        building = part.lastPathComponent
        defer { building = nil }
        do {
            try Data().write(to: part, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch { return .failure(refuse("create", error)) }
        let fh: FileHandle
        do { fh = try FileHandle(forWritingTo: part) } catch { return .failure(refuse("open", error)) }
        func giveUp(_ step: String, _ e: Error) -> Result<Made, Refusal> {
            try? fh.close()
            try? fm.removeItem(at: part)
            return .failure(refuse(step, e))
        }
        do { try fh.write(contentsOf: salt) } catch { return giveUp("head", error) }
        let sealer = Framer(fh, key(entropy: ent, salt: salt, label: labelV2), salt)
        // THE BAR MEASURES WHAT IT NAMES: bytes sealed against the bytes this copy will take, both counted
        // from the disk. It moves only when a piece is written, and reaches its end only with the tail.
        let skipLabels = Set(scope.skipConvs.compactMap { MontanaArchive.labelOnQueue(for: $0) })
        var total = 0
        let chatsRoot = MontanaArchive.rootURL.appendingPathComponent(MontanaPaths.chats)
        for f in MontanaArchive.conversations() where !skipLabels.contains(f) {
            let d = chatsRoot.appendingPathComponent(MontanaArchive.sanitizeName(f))
            total += ((try? fm.attributesOfItem(atPath: d.appendingPathComponent(MontanaPaths.log).path)[.size] as? Int) ?? nil) ?? 0
            for n in (try? fm.contentsOfDirectory(atPath: d.appendingPathComponent(MontanaPaths.media).path)) ?? [] {
                total += ((try? fm.attributesOfItem(atPath: d.appendingPathComponent(MontanaPaths.media).appendingPathComponent(n).path)[.size] as? Int) ?? nil) ?? 0
            }
        }
        for n in (try? fm.contentsOfDirectory(atPath: MontanaMediaStore.dir.path)) ?? [] where !n.hasPrefix(".") && scope.takes(file: n) {
            total += ((try? fm.attributesOfItem(atPath: MontanaMediaStore.dir.appendingPathComponent(n).path)[.size] as? Int) ?? nil) ?? 0
        }
        let placed = placeFiles(scope)
        for p in placed { total += ((try? fm.attributesOfItem(atPath: p.url.path)[.size] as? Int) ?? nil) ?? 0 }
        let feed = SeedScope.feedNow().map { without(scope.people, json: $0) }
        total += feed?.count ?? 0
        // THE BAR STANDS FROM THE FIRST MOMENT (the author, 23.09 18:24: a spinner turned for minutes before any
        // bar appeared): zero is shown the moment the count is known, and the diary marks the start, so
        // the time a copy takes is read, not guessed.
        MontanaP2PTrace.mark("backup_start", "total=" + String(total))
        DispatchQueue.main.async { progress(0) }
        var sealed = 0
        var shown = -1
        func advance(_ n: Int) {
            sealed += n
            let pct = total > 0 ? min(99, sealed * 100 / total) : 0
            if pct != shown {
                shown = pct
                let f = Double(pct) / 100
                DispatchQueue.main.async { progress(f) }
            }
        }
        var tally = Tally()
        tally.skipped = card.skipped

        let chats = MontanaArchive.rootURL.appendingPathComponent(MontanaPaths.chats)
        // A conversation left out is left out whole: its folder is not read, not a block of it travels.
        let skipFolders = Set(scope.skipConvs.compactMap { MontanaArchive.labelOnQueue(for: $0) })
        for folderName in MontanaArchive.conversations() where !skipFolders.contains(folderName) {
            let folder = chats.appendingPathComponent(MontanaArchive.sanitizeName(folderName))
            var any = false
            if let rh = try? FileHandle(forReadingFrom: folder.appendingPathComponent(MontanaPaths.log)) {
                // EVERY PIECE LEAVES MEMORY WITH ITS TURN (the critic 23.09, T1 on 1891). A file handle's read
                // hands back an autoreleased buffer, and a loop on a queue releases nothing until the whole
                // block returns: the first copy that took every attachment (605 files, over a gigabyte) held
                // every piece it had read -- the app stood at 2.0-2.4 GB, the system warned six times, and the
                // main thread stood 5.9 s under the pressure while the person tapped the network tab. A pool
                // per piece keeps the copy at one piece in hand, whatever its size.
                var failed: Error? = nil
                while failed == nil {
                    let more: Bool = autoreleasepool {
                        guard let block = nextBlock(rh) else { return false }
                        do { try sealer.put(kindBlock, "", block, more: false) } catch { failed = error; return false }
                        tally.records += 1
                        tally.bytes += block.count
                        advance(block.count + 4)
                        any = true
                        return true
                    }
                    if !more { break }
                }
                try? rh.close()
                if let e = failed { return giveUp("block", e) }
            }
            let mdir = folder.appendingPathComponent(MontanaPaths.media)
            for n in ((try? fm.contentsOfDirectory(atPath: mdir.path)) ?? []).sorted() where !n.hasPrefix(".") {
                let f = mdir.appendingPathComponent(n)
                // AN ATTACHMENT THAT WILL NOT READ STOPS THE COPY (the author, 23.09: leave no remainder).
                // It used to be skipped in silence, and the copy went out one attachment short while
                // calling itself whole — the very shape a person leans on and loses.
                let size: Int
                let rh: FileHandle
                do {
                    size = (try fm.attributesOfItem(atPath: f.path)[.size] as? Int) ?? 0
                    rh = try FileHandle(forReadingFrom: f)
                } catch { return giveUp("attach", error) }
                // It leaves in pieces of a megabyte: three hundred megabytes taken whole is how this
                // app was killed before (the media road, 15.09).
                let pieces = max(1, (size + pieceBytes - 1) / pieceBytes)
                var failed: Error? = nil
                for i in 0..<pieces {
                    autoreleasepool {   // one piece in hand at a time (see the log loop above)
                        do {
                            let piece = (try rh.read(upToCount: pieceBytes)) ?? Data()
                            try sealer.put(kindMedia, folderName + "/" + n, piece, more: i + 1 < pieces)
                            advance(piece.count)
                        } catch { failed = error }
                    }
                    if failed != nil { break }
                }
                try? rh.close()
                if let e = failed { return giveUp("media", e) }
                tally.media += 1
                tally.bytes += size
                any = true
            }
            if any { tally.chats += 1 }
        }
        // THE ATTACHMENTS THEMSELVES — every file of the correspondence store the scope takes, in pieces.
        // They go LAST, after every letter, and this order is load-bearing: on the other side the store's
        // sweep carries off any file no letter names, and a file is spared only for its first minute.
        // The letters are filed first, the feed is rebuilt from them within seconds, and only then do
        // their files begin to land — so no restored attachment ever stands a minute without its letter.
        let store = MontanaMediaStore.dir
        let names = ((try? fm.contentsOfDirectory(atPath: store.path)) ?? []).sorted()
        for n in names where !n.hasPrefix(".") && scope.takes(file: n) {
            let f = store.appendingPathComponent(n)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: f.path, isDirectory: &isDir), !isDir.boolValue else { continue }
            let size: Int
            let rh: FileHandle
            do {
                size = (try fm.attributesOfItem(atPath: f.path)[.size] as? Int) ?? 0
                rh = try FileHandle(forReadingFrom: f)
            } catch { return giveUp("store", error) }
            let pieces = max(1, (size + pieceBytes - 1) / pieceBytes)
            var failed: Error? = nil
            for i in 0..<pieces {
                autoreleasepool {   // one piece in hand at a time (see the log loop above)
                    do {
                        let piece = (try rh.read(upToCount: pieceBytes)) ?? Data()
                        try sealer.put(kindStore, n, piece, more: i + 1 < pieces)
                        advance(piece.count)
                    } catch { failed = error }
                }
                if failed != nil { break }
            }
            try? rh.close()
            if let e = failed { return giveUp("store", e) }
            tally.media += 1
            tally.bytes += size
        }
        // THE PERSON'S OTHER PLACES go after the store, in pieces like every file: the faces, the grounds'
        // pictures, the stories, and the pictures beside the attachments the scope takes.
        var places = 0
        for p in placed {
            let size: Int
            let rh: FileHandle
            do {
                size = (try fm.attributesOfItem(atPath: p.url.path)[.size] as? Int) ?? 0
                rh = try FileHandle(forReadingFrom: p.url)
            } catch { return giveUp("place", error) }
            let pieces = max(1, (size + pieceBytes - 1) / pieceBytes)
            var failed: Error? = nil
            for i in 0..<pieces {
                autoreleasepool {   // one piece in hand at a time (see the log loop above)
                    do {
                        let piece = (try rh.read(upToCount: pieceBytes)) ?? Data()
                        try sealer.put(kindPlace, p.place + "/" + p.name, piece, more: i + 1 < pieces)
                        advance(piece.count)
                    } catch { failed = error }
                }
                if failed != nil { break }
            }
            try? rh.close()
            if let e = failed { return giveUp("place", e) }
            places += 1
            tally.bytes += size
        }
        // The feed goes after the files, in pieces of a megabyte.
        if let f = feed {
            let pieces = max(1, (f.count + pieceBytes - 1) / pieceBytes)
            for i in 0..<pieces {
                let lo = i * pieceBytes
                let hi = min(f.count, lo + pieceBytes)
                do { try sealer.put(kindFeed, "", f.subdata(in: lo..<hi), more: i + 1 < pieces) } catch { return giveUp("feed", error) }
                advance(hi - lo)
            }
        }
        guard tally.records + tally.media + card.count >= 1 else {
            try? fh.close()
            try? fm.removeItem(at: part)
            return .failure(.empty)
        }
        // THE CARD IS PIECED LIKE AN ATTACHMENT (the critic on the written code, 23.09): a profile
        // photo alone makes it larger than one chunk, and a chunk larger than the reader accepts is a
        // copy that writes cleanly and refuses to open — the worst shape a copy can take.
        let cardPieces = max(1, (card.data.count + pieceBytes - 1) / pieceBytes)
        for i in 0..<cardPieces {
            let lo = i * pieceBytes
            let hi = min(card.data.count, lo + pieceBytes)
            do { try sealer.put(kindCard, "", card.data.subdata(in: lo..<hi), more: i + 1 < cardPieces) } catch {
                return giveUp("card", error)
            }
        }
        let tail = Tail(tally: tally, digest: sealer.digestHex)
        do {
            let tailData = try JSONEncoder().encode(tail)
            try sealer.put(kindTail, "", tailData, more: false)
            try sealer.finish()
        } catch { return giveUp("tail", error) }
        do { try fh.close() } catch { return giveUp("close", error) }

        let out = dir.appendingPathComponent(nameNow(ent))
        do {
            if fm.fileExists(atPath: out.path) { try fm.removeItem(at: out) }
            try fm.moveItem(at: part, to: out)
        } catch {
            try? fm.removeItem(at: part)
            return .failure(refuse("move", error))
        }
        DispatchQueue.main.async { progress(1) }
        MontanaP2PTrace.mark("backup_made", "chats=" + String(tally.chats) + " rec=" + String(tally.records) + " media=" + String(tally.media) + " places=" + String(places) + " card=" + String(card.count) + " feed=" + String(feed?.count ?? 0) + " bytes=" + String(tally.bytes))
        MontanaLog.event("BACKUP made: chats=" + String(tally.chats) + " records=" + String(tally.records) + " media=" + String(tally.media))
        return .success(Made(url: out, tally: tally))
    }

    /// One sealed block of the log, in the layout the core writes: u32 LE length, then the block.
    private static func nextBlock(_ rh: FileHandle) -> Data? {
        guard let lenD = ((try? rh.read(upToCount: 4)) ?? nil), lenD.count == 4 else { return nil }
        let len = num([UInt8](lenD), 0, 4)
        guard len >= 1, len <= 4 << 20 else { return nil }
        guard let blk = ((try? rh.read(upToCount: len)) ?? nil), blk.count == len else { return nil }
        return blk
    }

    // ── the account card ────────────────────────────────────────────────────────
    private struct Card { let data: Data; let count: Int; let skipped: Int }
    private static let outboxTag = "q:outbox"
    /// WHAT THE CARD CARRIES IS NAMED ONCE, AND NOT HERE ([C-1]): SeedScope names the account's content and
    /// the person's settings — the VPN among them — and a copy takes exactly those, by name and by prefix,
    /// with the one set whose store is the shared keychain. A second list of its own would drift on the
    /// first edit.
    ///
    /// A value sealed under the device key is opened HERE and travels as plaintext under the seal of the
    /// container — the device key itself never leaves the device, by the rule it was born under. open and
    /// not getDecrypted: the reading one re-seals a plaintext value where it finds it, and a value the
    /// platform's own store keeps in the open would become unreadable to it. A value the vault sealed before
    /// it named its seals by key opens under the empty name, as the vault itself reads it.
    ///
    /// Every value that is not a string, a number, a list of strings, a map of strings or sealed bytes
    /// travels as a property list — the store's own form — so a map of numbers or a list of records is not
    /// left behind as «skipped».
    private static func seedCard(_ scope: Scope) -> Card? {
        var out: [String: String] = [:]
        var skipped = 0
        // A copy that leaves a conversation out does not carry the list that names it: the list is
        // rebuilt from the archive on the other side, and the archive of that copy has no such folder.
        let listKeys: Set<String> = scope.excluding ? ["chatsJSON", "archivedJSON"] : []
        let people = scope.people
        for (k, v) in SeedScope.carried() where !listKeys.contains(k) && scope.takes(key: k) {
            if let d = v as? Data {
                if let opened = MontanaLocalVault.open(d, Data(k.utf8)) ?? MontanaLocalVault.open(d, Data()) {
                    out["d:" + k] = without(people, json: opened).base64EncodedString()
                } else {
                    out["b:" + k] = d.base64EncodedString()
                }
            } else if let s = v as? String {
                out["s:" + k] = s
            } else if let n = v as? NSNumber {
                out["n:" + k] = n.stringValue
            } else if let a = v as? [String], let j = try? JSONEncoder().encode(a.filter { !people.contains($0) }) {
                out["a:" + k] = j.base64EncodedString()
            } else if let m = v as? [String: String], let j = try? JSONEncoder().encode(m.filter { !people.contains($0.key) }) {
                out["m:" + k] = j.base64EncodedString()
            } else if let p = try? PropertyListSerialization.data(fromPropertyList: without(people, v), format: .binary, options: 0) {
                out["p:" + k] = p.base64EncodedString()
            } else {
                skipped += 1
            }
        }
        for k in SeedScope.keychainSets {
            guard let d = MontanaKeychain.get(k), let a = try? JSONDecoder().decode([String].self, from: d),
                  let j = try? JSONEncoder().encode(a.filter { !people.contains($0) }) else { continue }
            out["k:" + k] = j.base64EncodedString()
        }
        // The letters still on their way: laid back into the queue once their pipes stand again.
        if let q = SeedScope.outboxNow() { out[outboxTag] = without(people, json: q).base64EncodedString() }
        guard let data = try? JSONEncoder().encode(out) else { return nil }
        return Card(data: data, count: out.count, skipped: skipped)
    }

    /// A LEFT-OUT CONVERSATION LEAVES NO WORD IN A COLLECTION: its key in a map, its name in a list, a record
    /// in a list of records that names it by one of the fields a record names a person with.
    static func without(_ people: Set<String>, _ v: Any) -> Any {
        if people.isEmpty { return v }
        if let m = v as? [String: Any] { return m.filter { !people.contains($0.key) } }
        if let a = v as? [Any] {
            return a.filter { x in
                if let s = x as? String { return !people.contains(s) }
                if let d = x as? [String: Any] {
                    return !["ref", "chat", "convRef", "convId", "name", "address", "to"].contains { f in (d[f] as? String).map { people.contains($0) } ?? false }
                }
                return true
            }
        }
        return v
    }
    private static func without(_ people: Set<String>, json d: Data) -> Data {
        guard !people.isEmpty, let v = try? JSONSerialization.jsonObject(with: d, options: [.fragmentsAllowed]),
              JSONSerialization.isValidJSONObject(without(people, v)),
              let out = try? JSONSerialization.data(withJSONObject: without(people, v)) else { return d }
        return out
    }

    /// THE UNION OF TWO COLLECTIONS, what stands here first: a map keeps its own entries and takes the copy's
    /// others; a list keeps its own and takes each entry of the copy's it lacks — a string by itself, a
    /// record by what it is known by (SeedScope.unionKnownBy: a chat row by its conversation, whether the
    /// row names it as convId or as name). Two values that are not collections of one shape: the copy's.
    static func union(_ mine: Any, _ theirs: Any, by fields: [String] = SeedScope.unionKnownByDefault) -> Any {
        if let m = mine as? [String: Any], let t = theirs as? [String: Any] { return t.merging(m) { _, kept in kept } }
        guard let m = mine as? [Any], let t = theirs as? [Any] else { return theirs }
        func id(_ x: Any) -> String? {
            if let s = x as? String { return "s:" + s }
            if let d = x as? [String: Any] {
                for f in fields { if let v = d[f] as? String, !v.isEmpty { return "r:" + v } }
            }
            guard JSONSerialization.isValidJSONObject([x]),
                  let j = try? JSONSerialization.data(withJSONObject: [x], options: [.sortedKeys]) else { return nil }
            return "j:" + String(decoding: j, as: UTF8.self)
        }
        var seen = Set(m.compactMap(id))
        var out = m
        for x in t {
            guard let i = id(x) else { out.append(x); continue }
            if seen.insert(i).inserted { out.append(x) }
        }
        return out
    }
    private static func union(json mine: Data, _ theirs: Data, by fields: [String]) -> Data {
        guard let m = try? JSONSerialization.jsonObject(with: mine), let t = try? JSONSerialization.jsonObject(with: theirs) else { return theirs }
        let u = union(m, t, by: fields)
        guard JSONSerialization.isValidJSONObject(u), let out = try? JSONSerialization.data(withJSONObject: u) else { return theirs }
        return out
    }

    private static func layCard(_ d: Data) -> Bool {
        guard MontanaDeviceKey.key != nil,
              let map = try? JSONDecoder().decode([String: String].self, from: d) else { return false }
        let ud = UserDefaults.standard
        for (tagged, v) in map {
            let k = String(tagged.dropFirst(2))
            let joins = SeedScope.unionKeys.contains(k)
            let fields = SeedScope.unionKnownBy[k] ?? SeedScope.unionKnownByDefault
            switch tagged.prefix(2) {
            case "d:":
                guard let raw = Data(base64Encoded: v) else { continue }
                if MontanaCard.owns(k) {   // the card's records go in by their owner's door: in order after every write on its way (25.09)
                    MontanaCard.lay(k, raw, merge: joins ? { union(json: $0, raw, by: fields) } : nil)
                    continue
                }
                let have = joins ? MontanaLocalVault.getDecrypted(k) : nil
                MontanaLocalVault.setEncrypted(k, have.map { union(json: $0, raw, by: fields) } ?? raw)
            case "b:":
                guard let raw = Data(base64Encoded: v) else { continue }
                let have = joins ? ud.data(forKey: k) : nil
                ud.set(have.map { union(json: $0, raw, by: fields) } ?? raw, forKey: k)
            case "s:": ud.set(v, forKey: k)
            case "n:": ud.set(Double(v) ?? 0, forKey: k)
            case "a:":
                if let raw = Data(base64Encoded: v), let a = try? JSONDecoder().decode([String].self, from: raw) {
                    let have = joins ? ud.stringArray(forKey: k) : nil
                    ud.set(have.map { union($0, a, by: fields) } ?? a, forKey: k)
                }
            case "m:":
                if let raw = Data(base64Encoded: v), let m = try? JSONDecoder().decode([String: String].self, from: raw) {
                    let have = joins ? ud.dictionary(forKey: k) : nil
                    ud.set(have.map { union($0, m, by: fields) } ?? m, forKey: k)
                }
            case "p:":
                if let raw = Data(base64Encoded: v),
                   let p = try? PropertyListSerialization.propertyList(from: raw, options: [], format: nil) {
                    let have = joins ? ud.object(forKey: k) : nil
                    ud.set(have.map { union($0, p, by: fields) } ?? p, forKey: k)
                }
            case "k:":
                // The shared keychain's own set, laid back as a union: a copy adds a deletion, never lifts one.
                if let raw = Data(base64Encoded: v), let a = try? JSONDecoder().decode([String].self, from: raw) {
                    let have = MontanaKeychain.get(k).flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
                    let all = (union(have, a) as? [String]) ?? a
                    MontanaKeychain.set(k, (try? JSONEncoder().encode(all)) ?? raw)
                }
            default: break
            }
        }
        return true
    }

    /// The letters on their way a card carried, or nil.
    private static func cardOutbox(_ d: Data) -> Data? {
        guard let map = try? JSONDecoder().decode([String: String].self, from: d), let v = map[outboxTag] else { return nil }
        return Data(base64Encoded: v)
    }

    /// The files of the person's other places this copy takes: every file of every place, less the faces of a
    /// left-out conversation, the picture its ground stood on, and the pictures beside attachments left out.
    private static func placeFiles(_ scope: Scope) -> [(place: String, name: String, url: URL)] {
        let fm = FileManager.default
        var grounds = Set<String>()
        for p in scope.people {
            if let f = MTWallpaper.photoFile(for: p) { grounds.insert(f) }
            if let f = MTWallpaper.photoFile(for: MTWallpaper.pageKey(.peer(p))) { grounds.insert(f) }   // their page's ground (25.09)
        }
        var out: [(place: String, name: String, url: URL)] = []
        for (place, dir) in places {
            for n in ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).sorted() where plainName(n) {
                var isDir: ObjCBool = false
                let u = dir.appendingPathComponent(n)
                guard fm.fileExists(atPath: u.path, isDirectory: &isDir), !isDir.boolValue else { continue }
                if place == "avatars" && scope.skipFaces.contains(n) { continue }
                if place == "wallpapers" && grounds.contains(n) { continue }
                if place == "pictures" && !scope.takes(picture: n) { continue }
                out.append((place, n, u))
            }
        }
        return out
    }

    // ── taking one back ─────────────────────────────────────────────────────────
    /// A copy is taken back BY THE ROAD A TWIN'S HISTORY TAKES: every block goes through the core's
    /// own ingest, which drops a block it already holds by (writer_tag, block_seq). So a restore
    /// MERGES — it never erases — a second restore costs nothing, and letters that live only on this
    /// device stay where they are.
    /// THE BAR OF A RESTORE MEASURES WHAT IT NAMES (the critic, 23.09: 2.9 GB came back under a spinner that
    /// stood on «Create backup»): the share of the copy's own frames already read and filed, from the first one.
    /// The person waits for it, so it runs at the priority of a person waiting.
    static func restore(from url: URL, progress: @escaping (Double) -> Void = { _ in },
                        done: @escaping (Result<Tally, Refusal>) -> Void) {
        MontanaArchive.onOwnQueue(urgent: true) {
            let r = apply(url, progress)
            DispatchQueue.main.async { done(r) }
        }
    }

    /// THE CARD OF A COPY, READ AND NOT LAID (the author's words 10.10.2026 12:4x and 12:47 MSK: the wallet keeps no person of
    /// its own and shows the person of the same words). The copy is opened by this phone's words and proved whole by its tail
    /// exactly as a restore proves it; every other record passes by unfiled, and nothing on this phone changes. Nil for a copy
    /// these words do not open, a copy cut or torn, or a copy without a card. Version 2 alone is read: a copy laid on the
    /// nodes is never of version 1.
    static func cardOf(_ url: URL) -> [String: String]? {
        guard let mn = MontanaSeed.mnemonic, let ent = MontanaSeedKeys.entropyFrom(mnemonic: mn), ent.count == 32,
              let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        let size = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil) ?? 0
        let taker = Taker(peek: true)
        guard case .success = applyV2(fh, size, ent, Share { _ in }, taker),
              let tail = taker.tail, hex(taker.hash.finalize()) == tail.digest, let card = taker.card else { return nil }
        return try? JSONDecoder().decode([String: String].self, from: card)
    }

    /// One reporter for both shapes: a share, spoken only when the whole percent moves.
    private final class Share {
        private let say: (Double) -> Void
        private var shown = -1
        init(_ say: @escaping (Double) -> Void) { self.say = say }
        func at(_ f: Double) {
            let pct = Int(min(1, max(0, f)) * 100)
            guard pct != shown else { return }
            shown = pct
            let s = say
            DispatchQueue.main.async { s(Double(pct) / 100) }
        }
    }

    private static func apply(_ url: URL, _ progress: @escaping (Double) -> Void = { _ in }) -> Result<Tally, Refusal> {
        guard let mn = MontanaSeed.mnemonic,
              let ent = MontanaSeedKeys.entropyFrom(mnemonic: mn), ent.count == 32 else { return .failure(.noSeed) }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let fh: FileHandle
        do { fh = try FileHandle(forReadingFrom: url) } catch { return .failure(refuse("open", error)) }
        defer { try? fh.close() }
        let size = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil) ?? 0
        guard let head = ((try? fh.read(upToCount: headerBytes)) ?? nil), head.count == headerBytes else { return .failure(.notOurs) }
        // A copy of version 1 carries its mark; a copy of version 2 carries none and answers only to the words.
        let share = Share(progress)
        share.at(0)
        if [UInt8](head.prefix(6)) == magic { return applyV1(fh, head, ent, size, share) }
        do { try fh.seek(toOffset: 0) } catch { return .failure(refuse("seek", error)) }
        return applyV2(fh, size, ent, share)
    }

    /// Version 1, read and never written: one record per chunk, each behind its own length.
    private static func applyV1(_ fh: FileHandle, _ head: Data, _ ent: Data, _ size: Int, _ share: Share) -> Result<Tally, Refusal> {
        let hb = [UInt8](head)
        guard hb[6] == version, hb[7] == kdfId else { return .failure(.version) }
        let k = key(entropy: ent, salt: head.subdata(in: 8..<40), label: label)
        let taker = Taker()
        var index: UInt64 = 0
        while taker.tail == nil {
            // The same law on the way back: a read taken inside its own pool leaves nothing behind it, so a
            // gigabyte of copy passes through with one chunk in hand (see the pool in build).
            let lenRead: Data? = autoreleasepool { (try? fh.read(upToCount: 4)) ?? nil }
            guard let lenD = lenRead, lenD.count == 4 else { break }
            let len = num([UInt8](lenD), 0, 4)
            let fits = len >= 17 && len <= chunkBytes + 4096   // the length is judged BEFORE a byte of it is read
            let sealedRead: Data? = fits ? autoreleasepool { (try? fh.read(upToCount: len)) ?? nil } : nil
            guard fits, let sealed = sealedRead, sealed.count == len else {
                taker.close()
                return .failure(.torn)
            }
            guard let box = try? ChaChaPoly.SealedBox(combined: sealed),
                  let opened = try? ChaChaPoly.open(box, using: k, authenticating: aad(head, index)) else {
                // THE FIRST CHUNK IS THE QUESTION «DO THESE WORDS OPEN THIS COPY?» (the critic, 23.09).
                // A copy made under another phrase is not damaged, and calling it damaged is how a
                // person deletes the only copy they had. A later refusal is damage, and is named so.
                taker.close()
                return .failure(index == 0 ? .wrongWords : .torn)
            }
            index += 1
            if let r = taker.take(Data(opened)) { taker.close(); return .failure(r) }
            if 0 < size { share.at(Double((try? fh.offset()) ?? 0) / Double(size)) }
        }
        return finish(taker, index)
    }

    /// Version 2: frames of one length; inside them, one stream of records.
    private static func applyV2(_ fh: FileHandle, _ size: Int, _ ent: Data, _ share: Share, _ taker: Taker = Taker()) -> Result<Tally, Refusal> {
        let body = size - saltBytes
        guard body >= frameBytes,
              let salt = ((try? fh.read(upToCount: saltBytes)) ?? nil), salt.count == saltBytes else { return .failure(.notOurs) }
        let n = body / frameBytes
        let whole = body % frameBytes == 0
        func last(_ i: Int) -> Bool { whole && i == n - 1 }
        let k = key(entropy: ent, salt: salt, label: labelV2)
        var stream = Data()
        var ended = false
        for i in 0..<n {
            let read: Data? = autoreleasepool { (try? fh.read(upToCount: frameBytes)) ?? nil }
            guard !ended, let f = read, f.count == frameBytes, let box = try? ChaChaPoly.SealedBox(combined: f) else {
                taker.close()   // a frame after the tail's frame is not the writer's either
                return .failure(.torn)
            }
            guard let opened = try? ChaChaPoly.open(box, using: k, authenticating: aad2(salt, UInt64(i), last(i))) else {
                taker.close()
                // THE FIRST FRAME IS THE QUESTION «DO THESE WORDS OPEN THIS FILE?». The file carries no
                // mark, so a copy of another phrase and no copy at all look alike, and they are named
                // together. A first frame that opens only under the other end-mark belongs to a copy
                // cut at a frame's edge: that is damage, and is named so.
                guard i == 0 else { return .failure(.torn) }
                let cut = (try? ChaChaPoly.open(box, using: k, authenticating: aad2(salt, 0, !last(0)))) != nil
                return .failure(cut ? .torn : .unopened)
            }
            stream.append(opened)
            share.at(Double(i + 1) / Double(n))
            var at = 0
            func field(_ o: Int, _ width: Int) -> Int {
                var v = 0
                for b in 0..<width { v = v | (Int(stream[o + b]) << (8 * b)) }
                return v
            }
            while taker.tail == nil, stream.count - at >= 8 {
                let nl = field(at + 2, 2)
                guard stream.count - at >= 8 + nl else { break }
                let dl = field(at + 4 + nl, 4)
                guard dl <= chunkBytes + 4096 else { taker.close(); return .failure(.torn) }
                let len = 8 + nl + dl
                guard stream.count - at >= len else { break }
                if let r = taker.take(stream.subdata(in: at..<(at + len))) { taker.close(); return .failure(r) }
                at += len
            }
            if taker.tail != nil {
                // What follows the tail is the final frame's padding, and nothing else.
                ended = true
                guard stream[at...].allSatisfy({ $0 == 0 }) else { taker.close(); return .failure(.torn) }
                stream = Data()
            } else {
                stream = stream.subdata(in: at..<stream.count)
            }
        }
        guard ended, whole else { taker.close(); return .failure(.torn) }
        // A copy only read lays nothing: its card goes to the reader, never to the store (cardOf).
        return taker.peek ? .success(taker.tally) : finish(taker, UInt64(n))
    }

    /// A COPY HANDED BACK, RECORD BY RECORD — one reading for both shapes of the container, so the old
    /// and the new cannot file an attachment two different ways.
    private final class Taker {
        /// A COPY ONLY READ (cardOf, 10.10.2026): every record is hashed and passed by unfiled -- no block absorbed, no file
        /// written -- and the card and the tail alone are kept.
        let peek: Bool
        init(peek: Bool = false) { self.peek = peek }
        private let fm = FileManager.default
        private let chats = MontanaArchive.rootURL.appendingPathComponent(MontanaPaths.chats)
        var hash = SHA256()
        var tally = Tally()
        var card: Data? = nil
        var feed: Data? = nil
        var tail: Tail? = nil
        /// The files of the person's other places laid back, and the store's files laid back — the second held
        /// from the store's sweep until their letters and shelves stand (see finish).
        var placed = 0
        var landed: [String] = []
        private var sink: FileHandle? = nil
        private var dropping = false
        func close() { try? sink?.close(); sink = nil }

        /// One whole record: nil once it is filed, or the refusal that stops the copy.
        func take(_ p: Data) -> Refusal? {
            guard p.count >= 8 else { return .torn }
            let b = [UInt8](p)
            let kind = b[0]
            let more = b[1] == 1
            let nl = MontanaBackup.num(b, 2, 2)
            guard p.count >= 8 + nl else { return .torn }
            let name = String(bytes: b[4..<(4 + nl)], encoding: .utf8) ?? ""
            let dl = MontanaBackup.num(b, 4 + nl, 4)
            guard p.count == 8 + nl + dl else { return .torn }
            let data = p.subdata(in: (8 + nl)..<(8 + nl + dl))
            if kind != MontanaBackup.kindTail { hash.update(data: p) }
            if peek, kind != MontanaBackup.kindCard, kind != MontanaBackup.kindTail { return nil }
            switch kind {
            case MontanaBackup.kindBlock:
                _ = MontanaArchive.absorb(data)
                tally.records += 1
            case MontanaBackup.kindMedia, MontanaBackup.kindStore, MontanaBackup.kindPlace:
                if dropping {
                    if !more { dropping = false }
                    break
                }
                let dir: URL
                let dst: URL
                if kind == MontanaBackup.kindStore {
                    // THE ATTACHMENT GOES BACK WHERE A LETTER LOOKS FOR IT: the correspondence store,
                    // under the very name the letter carries.
                    dir = MontanaMediaStore.dir
                    dst = dir.appendingPathComponent(MontanaArchive.sanitizeName(name))
                } else if kind == MontanaBackup.kindPlace {
                    // One of the named places, and one plain file in it: a copy writes nowhere else.
                    let parts = name.split(separator: "/", maxSplits: 1).map(String.init)
                    guard parts.count == 2, MontanaBackup.plainName(parts[1]),
                          let d = MontanaBackup.places.first(where: { $0.name == parts[0] })?.dir else { break }
                    dir = d
                    dst = d.appendingPathComponent(parts[1])
                } else {
                    let parts = name.split(separator: "/")
                    guard parts.count == 2 else { break }
                    dir = chats.appendingPathComponent(MontanaArchive.sanitizeName(String(parts[0])))
                        .appendingPathComponent(MontanaPaths.media)
                    dst = dir.appendingPathComponent(MontanaArchive.sanitizeName(String(parts[1])))
                }
                if sink == nil {
                    // An attachment already here is never overwritten: a copy adds, it does not erase.
                    if fm.fileExists(atPath: dst.path) {
                        dropping = more
                        break
                    }
                    do {
                        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                        try Data().write(to: dst, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                        sink = try FileHandle(forWritingTo: dst)
                    } catch { return MontanaBackup.refuse("media", error) }
                    if kind == MontanaBackup.kindPlace {
                        placed += 1
                    } else {
                        tally.media += 1
                    }
                    if kind == MontanaBackup.kindStore {
                        // A sticker, a kept picture or an attachment whose letter is not filed yet is named by
                        // nobody for its first minutes here, and the store's sweep lifts what nobody names.
                        landed.append(dst.lastPathComponent)
                        MontanaMediaStore.hold([dst.lastPathComponent])
                    }
                }
                do { try sink?.write(contentsOf: data) } catch {
                    close()
                    return MontanaBackup.refuse("write", error)
                }
                if !more { close() }
            case MontanaBackup.kindCard:
                card = (card ?? Data()) + data
            case MontanaBackup.kindFeed:
                feed = (feed ?? Data()) + data
            case MontanaBackup.kindTail:
                guard let t = try? JSONDecoder().decode(Tail.self, from: data) else { return .torn }
                tail = t
            default:
                break   // a kind this build does not know is buried in silence
            }
            return nil
        }
    }

    /// The copy has been read to its end: it is whole only if its tail meets the stream it closes.
    private static func finish(_ taker: Taker, _ chunks: UInt64) -> Result<Tally, Refusal> {
        taker.close()
        guard let t = taker.tail, hex(taker.hash.finalize()) == t.digest else {
            MontanaP2PTrace.mark("backup_torn", "chunks=\(chunks) rec=\(taker.tally.records) media=\(taker.tally.media)")
            return .failure(.torn)
        }
        // THE CARD IS LAID ONLY ONCE THE WHOLE COPY HAS PROVED ITSELF, AND BEFORE THE FEED IS REBUILT
        // (the critic, 23.09): the tombstones it carries must already stand when the archive is read
        // back, or a conversation deleted long ago rises out of the blocks.
        if let c = taker.card, !layCard(c) { return .failure(.noVault) }
        let laid = taker.card != nil
        let landed = taker.landed
        let feed = taker.feed.flatMap { SeedScope.decodeFeed($0) }
        let outbox = taker.card.flatMap { cardOutbox($0) }
        // The number shown is the one counted HERE, not the one the copy promised.
        var tally = taker.tally
        let folders = MontanaArchive.conversations()
        tally.chats = folders.count
        tally.skipped = t.tally.skipped
        DispatchQueue.main.async {
            // THE STORE CHANGED UNDER THE LIVING: every owner of a stored value reads it again BEFORE the feed
            // is rebuilt, so the tombstones and blocks the card carries stand when the letters are read back,
            // and no memory of the moment before writes itself over what was just laid.
            if laid { SeedScope.reread(restored: true, feed: feed, outbox: outbox) }
            for f in folders {
                NotificationCenter.default.post(name: .montanaArchiveIngested, object: nil, userInfo: ["folder": f])
            }
            // The files laid back are held from the sweep until their letters are filed and their shelves read.
            DispatchQueue.main.asyncAfter(deadline: .now() + 120) { MontanaMediaStore.release(landed) }
        }
        MontanaP2PTrace.mark("backup_taken", "chunks=\(chunks) rec=\(tally.records) media=\(tally.media) places=\(taker.placed) chats=\(tally.chats) card=\(laid ? 1 : 0) feed=\(taker.feed?.count ?? 0) queue=\(outbox?.count ?? 0)")
        MontanaLog.event("BACKUP taken: records=\(tally.records) media=\(tally.media) chats=\(tally.chats)")
        return .success(tally)
    }
}

/// THE COPY IN THE CLOUD — IN THE PLATFORM'S OWN STORAGE, WHERE EVERY APP KEEPS ITS COPY (the author,
/// 23.09 01:05). Not a folder in Files: the app's own iCloud container, hidden from the document browser
/// and shown where a person looks for what their apps keep — Settings, their name, iCloud, Storage —
/// under the app's name with its size and its own delete. Taken back from inside the app, the way such
/// copies are taken back everywhere on this platform.
///
/// The switch does not lie: without the container on the build, or without a person signed in with
/// iCloud Drive on, there is nothing to write to; it does not turn on and says why.
enum MontanaBackupCloud {
    static let switchKey = "mt.backup.icloud"                 // NOT-UI
    private static let lastKey = "mt.backup.icloud.at"        // NOT-UI
    /// Which engine made the copy the cloud holds. Engine 1 carried the archive alone — nine
    /// attachments of a whole history on T1 — so a copy it made is replaced at once, not in a day.
    /// Engine 2 wrote version 1, whose chunk lengths gave the keeper the size of every letter and every
    /// attachment (the critic, 23.09); engine 3 writes version 2, and a copy of engine 2 is made again at
    /// once. The copy of engine 2 leaves only when iCloud holds the new one (CloudWatch).
    private static let engineKey = "mt.backup.icloud.engine"  // NOT-UI
    ///
    /// Engine 4 writes into the container named Montana (see `container`): the copy of engine 3 lies in
    /// the first one and is made again at once, and it too leaves only once iCloud holds the new one.
    /// Engine 5 carries the whole app (23.09): every setting, the VPN, the people, the places' files, the feed
    /// itself and the letters still on their way. A copy of engine 4 knows none of it, and is made again at once.
    private static let engine = 5
    /// THE CONTAINER WHOSE LAST WORD IS THE NAME (the author, 23.09: «it still says app»). Apple's storage
    /// page names a copy by the tail of the container's identifier, lower case as it is written: the
    /// phone's own fallback would have written «App» with a capital (read in CloudDocs, 23.09), and the
    /// page wrote «app» — so the word comes from Apple's side, and the one word of it in our hands is the
    /// identifier. The copy lives in iCloud.quest.montana.wallet (Montana Wallet keeps its own, never the Messenger's),
    /// its ONE container: Montana Wallet has no copies made before a named container, so the app's identifier
    /// names the only one.
    /// The places that spell the name — this line, the two entitlements and
    /// Info.plist — are held equal by tools/mt-cloud-truth-check.py (rule 7).
    static let container = "iCloud.quest.montana.wallet"                                 // NOT-UI
    static var on: Bool { UserDefaults.standard.bool(forKey: switchKey) }
    /// WHETHER THIS DEVICE HAS MET A COPY OF ITS OWN — made one, or taken one back (the critic, 23.09). A device
    /// that has met none and finds one in iCloud is a device that has not been restored yet: its first copy would
    /// be a copy of an empty app, and once iCloud held it the keep rule would take the real one away.
    static var met: Bool { UserDefaults.standard.double(forKey: lastKey) > 0 }
    /// The person's own word on such a device: begin anew from this device. The copy iCloud holds stays until
    /// the new one is held, by the keep rule, as every copy does.
    static func beginAnew() { UserDefaults.standard.set(1, forKey: lastKey) }
    /// A COPY TAKEN BACK IS THE LAST COPY (23.09): the daily clock starts from the moment the restored copy was
    /// made, and a copy whose name proves its owner was made by this engine. Otherwise the first launch after
    /// a restore sealed everything again at once — the double work the author named at 18:27.
    static func tookBack(_ url: URL) {
        let name = url.lastPathComponent
        // A copy renamed by hand says nothing of its birth: the moment it was taken back stands in.
        let born = MontanaBackup.born(ofName: name) ?? Date()
        UserDefaults.standard.set(born.timeIntervalSince1970, forKey: lastKey)
        guard let mn = MontanaSeed.mnemonic, let ent = MontanaSeedKeys.entropyFrom(mnemonic: mn),
              MontanaBackup.owned(name: name, by: MontanaBackup.ownerKey(entropy: ent)) == true else { return }
        UserDefaults.standard.set(engine, forKey: engineKey)
    }

    /// Asked OFF the main thread: the platform's own call reaches the account and the network.
    static func ready(_ done: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let u = FileManager.default.url(forUbiquityContainerIdentifier: container)
            DispatchQueue.main.async { done(u != nil) }
        }
    }
    /// The copies' own folder in the container. Not «Documents»: that one is what a document browser
    /// shows, and a copy is not a document a person opens — it is what the app keeps for them.
    private static func folder() throws -> URL {
        guard let base = FileManager.default.url(forUbiquityContainerIdentifier: container) else {
            throw NSError(domain: "montana.backup", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "no container"])   // NOT-UI: read by the diary
        }
        let d = base.appendingPathComponent("Backups", isDirectory: true)   // NOT-UI: a folder name
        if !FileManager.default.fileExists(atPath: d.path) {
            try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        }
        return d
    }

    /// Fetching a copy back from iCloud lives in CloudWatch.fetch: iCloud's own word says how much has
    /// come, why it waits, or that it refused (the critic, 23.09: a fixed three-minute wait here failed any
    /// copy of gigabytes on an ordinary network, and a new phone could not take its history back).

    /// Once a day, WHILE THE APP IS ON SCREEN. A copy built inside the system's background window
    /// would be killed on the half and leave a torn file under the right name (the critic, 23.09).
    /// What travels to the cloud is a FINISHED file, moved in one act.
    ///
    /// DUE: iCloud holds no copy of ours, or the engine has changed, or this device's last copy is a day
    /// old. The one caller is CopyInventory.tickNow, after iCloud has answered (23.09 18:24: the switch
    /// made a second copy of 2.9 GB while the copy of 18:06 was still waiting for room).
    static func due(holdsNone: Bool) -> Bool {
        let last = UserDefaults.standard.double(forKey: lastKey)
        let stale = UserDefaults.standard.integer(forKey: engineKey) < engine
        return holdsNone || stale || Date().timeIntervalSince1970 - last >= 86_400
    }
    static func copyNow(scope: MontanaBackup.Scope, urgent: Bool, progress: @escaping (Double) -> Void,
                        _ done: @escaping (Result<MontanaBackup.Tally, MontanaBackup.Refusal>) -> Void) {
        MontanaBackup.create(scope: scope, urgent: urgent, progress: progress) { r in
            switch r {
            case .failure(let e):
                done(.failure(e))   // the cause was already named and written where it happened
            case .success(let made):
                // TURNED OFF WHILE SEALING (the critic, 23.09): a copy sealed after the person switched the
                // copies off is not handed to iCloud; it leaves this device's shelf at once.
                guard on else {
                    MontanaBackup.discard(made)
                    MontanaP2PTrace.mark("backup_cloud", "switched off while sealing: not handed")
                    return done(.failure(.stopped))
                }
                DispatchQueue.global(qos: .utility).async {
                    let fm = FileManager.default
                    do {
                        let dir = try folder()
                        let dst = dir.appendingPathComponent(made.url.lastPathComponent)
                        try fm.setUbiquitous(true, itemAt: made.url, destinationURL: dst)
                        // NOTHING LEAVES THE CLOUD FROM HERE (the author, 23.09 03:41: «now it vanished from
                        // the iCloud storage altogether»). This line removed every older copy at the hand-
                        // over, the one iCloud held among them, before iCloud had taken this one. The copy
                        // iCloud holds now stays until iCloud confirms this one; the removal lives in
                        // CloudWatch, where that confirmation is read, and nowhere else.
                        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastKey)
                        UserDefaults.standard.set(engine, forKey: engineKey)
                        MontanaP2PTrace.mark("backup_cloud", "handed bytes=" + String(made.tally.bytes) + " (the cloud confirms the upload itself)")
                        DispatchQueue.main.async { done(.success(made.tally)) }
                    } catch {
                        let ns = error as NSError
                        let why = "put " + ns.domain + " " + String(ns.code)
                        MontanaP2PTrace.mark("backup_cloud", why)
                        DispatchQueue.main.async { done(.failure(.cloudRefused(why))) }
                    }
                }
            }
        }
    }
}
