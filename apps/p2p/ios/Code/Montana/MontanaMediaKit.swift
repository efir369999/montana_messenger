import Foundation
import AVFoundation
import CoreGraphics
import UIKit
import AudioToolbox
import VideoToolbox
import MontanaBindings
import Security

// Self-contained media kit (Stage 12): content-addressed blobs are sealed into the on-device store
// and travel to the recipient over the mesh; the receiving side reassembles them into a file. Also the
// bridge "extension ↔ app". Compiles both in the app and in the "Share" extension (no host
// dependencies).

// THE cryptographic random-bytes helper ([I-10]/[C-1]): one definition, both targets, and the
// bytes come from the core — six sources folded, a refusal when fewer than three are alive.
// A refusal is a broken machine, not a situation a person can answer: returning zeros here would
// seal a blob and a call under a key anyone can guess, and nothing would say so. The work stops.
func montanaRandom(_ n: Int) -> Data {
    var d = Data(count: n)
    let drawn = d.withUnsafeMutableBytes { p -> Bool in
        guard let base = p.bindMemory(to: UInt8.self).baseAddress else { return false }
        return mt_random_fast(base, n) == 0
    }
    precondition(drawn, "the machine refuses randomness — nothing may be sealed under it")
    return d
}

// The media-letter mark ([C-1]): one definition for every process that writes it —
// the app and the Share sheet; the NSE only reads envelopes and never composes one.
let mediaMark = "\u{200B}\u{200B}MD:"

/// One definition for «this name is music», both targets ([C-1]).
func mtIsAudioName(_ name: String) -> Bool {
    ["mp3", "m4a", "aac", "wav", "flac", "aif", "aiff", "caf"]
        .contains((name as NSString).pathExtension.lowercased())
}

/// A post's measures, one owner for the app and the share sheet: the sheet's preview shows what the wall will take.
enum MTPostMeasure {
    static let files = 10
    static let narrowest = 9.0 / 16.0   // a picture's shape in a post, width over height: from upright 9:16 to wide 16:9
    static let widest = 16.0 / 9.0
    static func kind(ofExtension ext: String) -> String {
        let e = ext.lowercased()
        if ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp"].contains(e) { return "img" }
        if ["mov", "mp4", "m4v"].contains(e) { return "vid" }
        if mtIsAudioName("x." + e) { return "aud" }
        return "doc"
    }
}

/// THE TRACK'S WAVE IS BORN WITH THE LETTER ([C-1], the author's word 16.09: the bars must stand
/// at the send and at the receipt, from the chat and from the share sheet alike — never empty).
/// The sender probes the file once — sixty points, the same probes the bubble draws — and the
/// manifest carries them («wv», sixty bytes in base64; an old reader skips the key); the
/// receiver keeps them by the file's name and draws them on the first frame, before a byte of
/// the file has arrived. One probe, one shape, both sides. The shelf (memory and the durable
/// copy) lives in the app (MontanaMedia.swift); the probe lives here, where the sheet probes too.
enum MTWaveform {
    static let bars = 60
    static func pack(_ s: [Float]) -> Data { Data(s.map { UInt8(max(0, min(255, ($0 * 255).rounded()))) }) }
    static func unpack(_ d: Data) -> [Float] { d.map { Float($0) / 255 } }

    /// The probe over a source: a file by its path; bytes in hand through a temporary file (the
    /// audio reader opens paths, and the name's extension tells it the container).
    static func compute(source: MediaSource, ext: String) -> [Float]? {
        switch source {
        case .file(let u): return compute(u, bars: bars)
        case .memory(let d):
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("wave_\(UUID().uuidString)" + (ext.isEmpty ? "" : "." + ext))
            guard (try? d.write(to: tmp)) != nil else { return nil }
            defer { try? FileManager.default.removeItem(at: tmp) }
            return compute(tmp, bars: bars)
        }
    }

    // The track's waveform — as in the native player: 60 point probes across the file (only the
    // probes are decoded, not the whole file — 300 MB and 3 MB cost the same).
    static func compute(_ url: URL, bars: Int) -> [Float]? {
        guard let f = try? AVAudioFile(forReading: url) else { return nil }
        let total = f.length
        guard total > 256,
              let buf = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: 4096)
        else { return nil }
        var raw: [Float] = []
        for i in 0..<bars {
            f.framePosition = AVAudioFramePosition(Double(total) * Double(i) / Double(bars))
            buf.frameLength = 0
            guard (try? f.read(into: buf, frameCount: 4096)) != nil, buf.frameLength > 0,
                  let ch = buf.floatChannelData?[0] else { raw.append(0); continue }
            let n = Int(buf.frameLength)
            var acc: Float = 0; var cnt = 0
            for j in stride(from: 0, to: n, by: 8) { acc += abs(ch[j]); cnt += 1 }
            raw.append(cnt > 0 ? acc / Float(cnt) : 0)
        }
        // Scaled to a loud probe, not the single loudest one: one clap used to flatten the
        // whole voice into a line of three-point bars. The soft curve lifts quiet speech.
        let sorted = raw.sorted()
        let ref = max(sorted[Int(Double(sorted.count - 1) * 0.92)], 1e-6)
        return raw.map { Float(pow(Double(min(1, $0 / ref)), 0.7)) }
    }
}

actor MediaCounter { var value = 0; func inc() -> Int { value += 1; return value } }


// The source of media to send. The file is NEVER read into memory whole: each piece is taken at
// its offset through its own descriptor. The peak while sending is the window of parallelism
// (3 x 512 KiB), not the size of the file. Precedent: a 305 MB video peaked at about 610 MB —
// the file as data plus an array of every sealed piece — and the system killed the app, leaving a
// journal that stopped between the start of the media and any ending at all.
enum MediaSource {
    case memory(Data)
    case file(URL)

    var byteCount: Int {
        switch self {
        case .memory(let d): return d.count
        case .file(let u):
            return (try? FileManager.default.attributesOfItem(atPath: u.path)[.size] as? Int) as? Int ?? 0
        }
    }

    func slice(offset: Int, length: Int) -> Data? {
        switch self {
        case .memory(let d):
            let end = min(offset + length, d.count)
            guard offset < end else { return nil }
            return d.subdata(in: offset..<end)
        case .file(let u):
            guard let h = try? FileHandle(forReadingFrom: u) else { return nil }
            defer { try? h.close() }
            guard (try? h.seek(toOffset: UInt64(offset))) != nil else { return nil }
            return try? h.read(upToCount: length)
        }
    }
}

enum MontanaMedia {
    static let chunkSize = 512 * 1024   // 512 KiB — chunk
    static let parallel = 3

    struct SealedChunk { let sealed: Data; let blobId: String; let size: Int }

    /// The letter key: it is derived FROM THE LETTER NAME instead of being taken fresh on every attempt.
    /// Hence resumability: the same file under the same letter name gives THE SAME chunk names, and what
    /// is already uploaded is not uploaded twice. Privacy does not suffer -- the node never sees the
    /// device seed, so one file in two DIFFERENT letters gives different names and cannot be linked.
    static func letterBlobKey(_ letterMid: String) -> Data {
        var seed = MontanaKeychain.get("blobKeySeed")
        if seed == nil || seed!.count != 32 {
            let fresh = Data(montanaRandom(32)); MontanaKeychain.set("blobKeySeed", fresh); seed = fresh
        }
        var material = Data("mt-blob-key".utf8)
        material.append(Data(letterMid.utf8))
        material.append(seed!)
        var out = [UInt8](repeating: 0, count: 32)
        _ = material.withUnsafeBytes { m in mt_e2e_blob_id(m.bindMemory(to: UInt8.self).baseAddress, material.count, &out) }
        return Data(out)
    }

    private static func sealOne(_ piece: Data, blobKey: Data, index: Int) -> SealedChunk? {
        let target = mt_e2e_pad_len(piece.count)
        var padded = piece
        if target > piece.count { padded.append(Data(count: target - piece.count)) }
        // THE NONCE IS DERIVED, NOT THROWN. A random number per attempt changed the sealed bytes, and
        // with them the chunk name -- so a retry recognised NOT ONE of its own chunks and uploaded
        // everything anew. The derivation goes from the letter key, the chunk number AND THE BYTES
        // THEMSELVES: the same bytes give the same number (hence the same name -- one can continue),
        // different bytes give a different number (hence a repeat of one number on different content is
        // impossible by construction -- the only way to kill this seal).
        var material = blobKey
        material.append(contentsOf: withUnsafeBytes(of: UInt64(index).littleEndian, Array.init))
        material.append(padded)
        var nb = [UInt8](repeating: 0, count: 32)
        _ = material.withUnsafeBytes { m in mt_e2e_blob_id(m.bindMemory(to: UInt8.self).baseAddress, material.count, &nb) }
        let nonce = Data(nb.prefix(12))
        var outPtr: UnsafeMutablePointer<UInt8>? = nil; var outLen = 0
        let rc = blobKey.withUnsafeBytes { bk in nonce.withUnsafeBytes { n in padded.withUnsafeBytes { pp -> Int32 in
            mt_e2e_seal_blob(bk.bindMemory(to: UInt8.self).baseAddress, n.bindMemory(to: UInt8.self).baseAddress,
                             pp.bindMemory(to: UInt8.self).baseAddress, padded.count, &outPtr, &outLen)
        }}}
        guard rc == 0, let ptr = outPtr else { return nil }
        let sealed = Data(bytes: ptr, count: outLen); mt_e2e_free(ptr, outLen)
        return SealedChunk(sealed: sealed, blobId: blobIdHex(sealed), size: piece.count)
    }
    static func blobIdHex(_ sealed: Data) -> String {
        var out = [UInt8](repeating: 0, count: 32)
        _ = sealed.withUnsafeBytes { s in mt_e2e_blob_id(s.bindMemory(to: UInt8.self).baseAddress, sealed.count, &out) }
        return out.map { String(format: "%02x", $0) }.joined()
    }

    // ── THE one decision point: how a manifest becomes a letter ([C-1]) ─────
    // The chat, the Share sheet and the pending-share ingest all ask HERE. A manifest that
    // fits rides inside the letter; a bigger one is sealed under a fresh key, parked as a
    // blob (the node stays blind) and the letter carries {mref, mk} — the receiver's road
    // for both shapes is the one the chat path has always used. Only the blob transport is
    // the caller's: the app leg knows its hand-off window, the sheet rides MTNodeWire.
    static func manifestLetter(_ json: Data,
                               putBlob: (String, Data) async -> Bool) async -> (letter: String, manifestBid: String?)? {
        guard let body = String(data: json, encoding: .utf8) else { return nil }
        let plain = mediaMark + body
        if plain.utf8.count <= 1900 { return (plain, nil) }
        let mkey = montanaRandom(32)
        guard let sealed = MTNodeWire.sealBlob(key: [UInt8](mkey), json) else { return nil }
        let mbid = blobIdHex(sealed)
        guard await putBlob(mbid, sealed) else { return nil }
        // THE CARGO'S SIZE RIDES THE LETTER TOO (measured 15.09 10:16): every picture carries a
        // thumbnail, so every manifest outgrows the letter and takes this sealed road — and the
        // store gate, reading no size here, weighed every media as a whole budget and queued a
        // 222-kilobyte photo behind a 224-kilobyte one for thirty-six minutes. [P2P-COMPAT] an
        // unknown JSON key is invisible to every reader: each takes «mref» and «mk» by name.
        let sz = ((try? JSONSerialization.jsonObject(with: json)) as? [String: Any])?["sz"] as? Int
        let szPart = sz.map { ",\"sz\":\($0)" } ?? ""
        return (mediaMark + "{\"mref\":\"\(mbid)\",\"mk\":\"\(mkey.base64EncodedString())\"\(szPart)}", mbid)
    }
    static func openChunk(sealed: Data, blobKey: Data, expectedIdHex: String, size: Int) -> Data? {
        guard blobIdHex(sealed) == expectedIdHex else { return nil }   // integrity
        var outPtr: UnsafeMutablePointer<UInt8>? = nil; var outLen = 0
        let rc = blobKey.withUnsafeBytes { bk in sealed.withUnsafeBytes { s -> Int32 in
            mt_e2e_open_blob(bk.bindMemory(to: UInt8.self).baseAddress,
                             s.bindMemory(to: UInt8.self).baseAddress, sealed.count, &outPtr, &outLen)
        }}
        guard rc == 0, let ptr = outPtr else { return nil }
        let padded = Data(bytes: ptr, count: outLen); mt_e2e_free(ptr, outLen)
        return size <= padded.count ? padded.prefix(size) : padded
    }

    // Sealing and sending are ONE pipeline: a piece is read, sealed, put on the wire and released
    // at once. Sealing the whole file first put nothing on the wire for minutes — the progress bar
    // stood at two per cent — and only then began the transfer.
    static func sealAndUpload(source: MediaSource, letterMid: String? = nil, key: Data? = nil,
                              progress: @escaping @Sendable (Double) -> Void)
        async -> (blobKey: Data, manifest: [[String: Any]])? {
        // There is a letter name -> the key is derived from it, and the second attempt recognises the chunks of the first.
        // There is no name (the Share extension) -> the old behaviour, a fresh key.
        // A KEEPER'S KEY (24.09, the wall): a post's keeper lays the same file under the post's own key — the same bytes,
        // the same key, the same pieces give the same chunk names the post's manifest already carries.
        let blobKey = key ?? letterMid.map { letterBlobKey($0) } ?? Data(montanaRandom(32))
        let total = source.byteCount
        guard total > 0 else { return nil }
        let count = (total + chunkSize - 1) / chunkSize
        let counter = MediaCounter()

        var manifest = [[String: Any]?](repeating: nil, count: count)
        let ok = await withTaskGroup(of: (Int, [String: Any]?).self) { group -> Bool in
            var next = 0
            func launch(_ i: Int) {
                group.addTask {
                    let off = i * chunkSize
                    let len = min(chunkSize, total - off)
                    guard let piece = source.slice(offset: off, length: len),
                          let sc = sealOne(piece, blobKey: blobKey, index: i) else { return (i, nil) }
                    if Task.isCancelled { return (i, nil) }
                    // The piece is filed on this device under its content name and travels to the
                    // recipient over the mesh. This is a write to disk, not a send, so there is no
                    // retry and no waiting here: it can only fail together with the disk.
                    MontanaBlobStore.put(sc.blobId, sc.sealed)
                    let n = await counter.inc(); progress(Double(n) / Double(count))
                    return (i, ["bid": sc.blobId, "cs": sc.size])
                }
            }
            for _ in 0..<min(parallel, count) { launch(next); next += 1 }
            var good = true
            for await (i, m) in group {
                if let m { manifest[i] = m } else { good = false; group.cancelAll() }
                if good, next < count { launch(next); next += 1 }
            }
            return good
        }
        guard ok else { return nil }
        var out: [[String: Any]] = []
        for m in manifest { guard let m else { return nil }; out.append(m) }
        return (blobKey, out)
    }


    // Receiving as a stream: a piece arrives, is opened, APPENDED to the file and released.
    // Memory is bounded by the window (3 x 512 KiB) whatever the size of the file. Holding the
    // whole file in memory collapsed on video exactly as sending did, only on the receiving side.
    static func downloadToFile(manifest: [[String: Any]], blobKey: Data, totalSize: Int, dest: URL,
                               progress: @escaping @Sendable (Double) -> Void = { _ in }) async -> Bool {
        let t0 = Date()
        defer {
            let ms = max(1, Int(Date().timeIntervalSince(t0) * 1000))
            MontanaP2PTrace.mark("blob_dl", "bytes=\(totalSize) ms=\(ms) kbps=\(totalSize * 8 / ms)")
        }
        let parts: [(String, Int)] = manifest.compactMap { m in
            guard let bid = m["bid"] as? String, let cs = m["cs"] as? Int else { return nil }
            return (bid, cs)
        }
        guard parts.count == manifest.count, !parts.isEmpty else { return false }

        try? FileManager.default.removeItem(at: dest)
        guard FileManager.default.createFile(atPath: dest.path, contents: nil),
              let h = try? FileHandle(forWritingTo: dest) else { return false }
        defer { try? h.close() }

        // Pieces arrive out of order; they are written strictly in order, the early ones held back.
        var pending: [Int: Data] = [:]
        var writeNext = 0
        let ok = await withTaskGroup(of: (Int, Data?).self) { group -> Bool in
            var next = 0
            func launch(_ i: Int) {
                group.addTask {
                    for attempt in 0..<3 {
                        if let sealed = await MontanaBlobStore.awaitChunk(parts[i].0),
                           let d = openChunk(sealed: sealed, blobKey: blobKey, expectedIdHex: parts[i].0, size: parts[i].1) {
                            return (i, d)
                        }
                        if Task.isCancelled { return (i, nil) }
                        if attempt < 2 { try? await Task.sleep(nanoseconds: UInt64(500_000_000 << attempt)) }
                    }
                    return (i, nil)
                }
            }
            for _ in 0..<min(parallel, parts.count) { launch(next); next += 1 }
            var good = true
            for await (i, d) in group {
                guard let d else { good = false; group.cancelAll(); break }
                pending[i] = d
                progress(Double(writeNext + pending.count) / Double(parts.count))
                while let ready = pending.removeValue(forKey: writeNext) {
                    do { try h.write(contentsOf: ready) } catch { good = false; group.cancelAll(); break }
                    writeNext += 1
                }
                if next < parts.count { launch(next); next += 1 }
            }
            return good && writeNext == parts.count
        }
        guard ok else { try? FileManager.default.removeItem(at: dest); return false }
        if totalSize > 0 { try? h.truncate(atOffset: UInt64(totalSize)) }
        // The file is assembled and lies sealed in the archive -- the container is no longer needed for anything.
        MontanaBlobStore.drop(parts.map { $0.0 })
        return true
    }

}

// Deterministic avatar color/initial — stable across launches and IDENTICAL
// in the app and in the extension. Swift String.hashValue is randomized per-process,
// therefore we use FNV-1a and a pinned hex palette (SSOT for the avatar color).
// MontanaAvatar lives in MontanaAvatarKit.swift -- the SSOT of a face for BOTH targets (App + NSE) [C-1].

// Video compression before sending — parameters's (LegacyComponents
// TGMediaVideoConverter, preset CompressedMedium): long side ≤848,
// video H.264 1600 kbps, audio AAC 64 kbps. AVAssetReader/Writer (export presets
// do not provide the system bitrate). progress 0..1 by track time.
// A wait that ends exactly once: the previous hand-rolled read-write pairing resumed its
// continuation twice and killed the app. Here resuming a second time is physically impossible.
// The hardware HEVC encoder gives the same quality at roughly a third less bitrate. The check is
// not cheap, so it is computed ONCE per process.
// The transcoding queue holds strictly ONE video at a time. Two compressions at once hold two
// encoder sessions and two decode streams, and the system kills the app for memory without leaving
// a crash in the journal. Precedent: two clips ten seconds apart, and nineteen seconds later the
// process died and restarted.
// The gate understands cancellation: a waiter whose task dies is evicted from the queue at
// once (acquire returns false — the seat was never taken), and a holder always reaches its
// release because compress() now resumes its continuation on every exit. Precedent 23.08:
// a holder whose codec the system revoked hung forever, the queue behind it grew, and a
// release woke CANCELLED waiters that happily ran multi-minute ghost encodes.
actor VideoCompressGate {
    static let shared = VideoCompressGate()
    private var busy = false
    private var waiting: [(id: UUID, c: CheckedContinuation<Bool, Never>)] = []

    func acquire() async -> Bool {
        if Task.isCancelled { return false }
        if !busy { busy = true; return true }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
                if Task.isCancelled { c.resume(returning: false); return }
                waiting.append((id, c))
            }
        } onCancel: {
            Task { await self.evict(id) }
        }
    }
    private func evict(_ id: UUID) {
        if let i = waiting.firstIndex(where: { $0.id == id }) {
            waiting.remove(at: i).c.resume(returning: false)
        }
    }
    func release() {
        if waiting.isEmpty { busy = false }
        else { waiting.removeFirst().c.resume(returning: true) }
    }
}

private let hasHardwareHEVC: Bool = {
    var outID: CFString?
    var props: CFDictionary?
    let r = VTCopySupportedPropertyDictionaryForEncoder(
        width: 1920, height: 1080, codecType: kCMVideoCodecType_HEVC,
        encoderSpecification: [:] as CFDictionary, encoderIDOut: &outID, supportedPropertiesOut: &props)
    return r == noErr
}()

private final class ResumeOnce: @unchecked Sendable {
    private var done = false
    private let lock = NSLock()
    /// Resume exactly once: a continuation resumed twice traps, and the second caller here is a
    /// racing callback rather than a mistake in the call site.
    func fire(_ body: () -> Void) {
        lock.lock(); let first = !done; done = true; lock.unlock()
        if first { body() }
    }
}

// Every stage of the video conveyor is VISIBLE in the metric (the author's word 23.08:
// «the metric must show these processes too»). The app wires the sink to telemetry;
// extensions leave it nil and the marks fall back to the system log.
enum MTVideoTrace {
    nonisolated(unsafe) static var sink: (@Sendable (String) -> Void)? = nil
    static func mark(_ m: String) {
        if let sink { sink("[video] " + m) } else { NSLog("[video] %@", m) }
    }
}

// AVAssetExportSession is not Sendable; the box carries it into the progress poll and the
// cancellation handler of one export — a single owner, no shared mutation.
private final class MTExportBox: @unchecked Sendable {
    let ex: AVAssetExportSession
    init(_ e: AVAssetExportSession) { ex = e }
}

// The finish line of one compression pass: reachable from FOUR places (writer completion,
// task cancellation, the stall watchdog, a cancel arriving before the continuation exists)
// and crossable exactly once. Cancellation resuming the continuation is the load-bearing
// bolt: without it a pass whose frame pump silently died (codec revoked in the background)
// never returned, its defer never released the encoder gate, and every later video queued
// behind the corpse forever (trace 23.08: a START with no END).
private final class MTFinishLine: @unchecked Sendable {
    private var c: CheckedContinuation<Void, Never>?
    private var crossed = false
    private let lock = NSLock()
    func set(_ cont: CheckedContinuation<Void, Never>) {
        lock.lock()
        if crossed { lock.unlock(); cont.resume(); return }
        c = cont; lock.unlock()
    }
    func fire() {
        lock.lock()
        if crossed { lock.unlock(); return }
        crossed = true
        let cc = c; c = nil
        lock.unlock()
        cc?.resume()
    }
}

// A heartbeat of the frame pump: ticks on every sample. The stall watchdog compares stamps
// over ACTIVE seconds only — a background freeze is a pause, and after thaw a living encoder
// beats again within a second while a dead one stays silent and is failed fast.
private final class MTBeat: @unchecked Sendable {
    private var n = 0
    private let lock = NSLock()
    func tick() { lock.lock(); n += 1; lock.unlock() }
    func stamp() -> Int { lock.lock(); defer { lock.unlock() }; return n }
}

// The app flips this with its scene phase; extensions never touch it and keep it true.
// Watchdogs that bound ACTIVE work read it: a process frozen in the background is a pause,
// not a hang — counting wall time made a watchdog kill a living export right after thaw,
// and compression restarted from zero on each return to the app (precedent 23.08).
enum MTForeground { nonisolated(unsafe) static var active = true }

enum MontanaVideo {
    static let maxSide: CGFloat = 848

    // Compression with an EXPLICIT bitrate. The system export session gives no control over it:
    // a measurement showed 305 MB coming out of "compression", meaning none happened, and a file
    // like that can be neither sent nor received. Here frames are re-encoded to H.264 with a
    // ceiling on the bitrate and a side no larger than 848, audio as AAC at 64 kbit/s.
    static func compress(_ src: URL, range: CMTimeRange? = nil,
                         progress: @escaping @Sendable (Double) -> Void,
                         onStart: @escaping @Sendable () -> Void = {}) async -> URL? {
        // While another compression runs this one waits. The caller is told the moment work
        // actually starts: a timeout must count work and not waiting, or the fifth video expires
        // standing in the queue and goes out uncompressed.
        guard await VideoCompressGate.shared.acquire() else { return nil }
        defer { Task { await VideoCompressGate.shared.release() } }
        if Task.isCancelled { return nil }
        onStart()
        let asset = AVURLAsset(url: src)
        guard let vTrack = asset.tracks(withMediaType: .video).first else { return nil }
        let oriented = vTrack.naturalSize.applying(vTrack.preferredTransform)
        let ow = abs(oriented.width), oh = abs(oriented.height)
        guard ow >= 1, oh >= 1 else { return nil }

        // The encoder needs even sides or the frame skews. A multiple of sixteen is the H.264
        // macroblock: other sizes make the encoder pad edge macroblocks — slower and dirtier at
        // the edges.
        let k = min(1.0, maxSide / max(ow, oh))
        let w = max(16, Int((ow * k / 16).rounded()) * 16)
        let h = max(16, Int((oh * k / 16).rounded()) * 16)
        let fps = vTrack.nominalFrameRate > 1 ? min(30, Int(vTrack.nominalFrameRate.rounded())) : 30

        // The bitrate follows frame density against a reference of 848x478 at 1600 kbit/s. The
        // previous formula gave 891 kbit/s at the same frame size — a little over half — which is
        // where the difference in quality came from.
        let refPixels = 848.0 * 478.0
        var bitrate = 1_600_000.0 * (Double(w * h) / refPixels)
        // A short clip gets more: the file stays small either way and the difference shows.
        let dur = CMTimeGetSeconds(asset.duration)
        if dur.isFinite, dur > 0 {
            if dur < 10 { bitrate *= 1.4 } else if dur < 20 { bitrate *= 1.25 } else if dur < 30 { bitrate *= 1.1 }
        }
        let useHEVC = hasHardwareHEVC
        if useHEVC { bitrate *= 0.7 }   // the same look at a lower bitrate
        let videoBitrate = min(4_000_000, max(500_000, Int(bitrate)))

        // A video already within the target needs no re-encoding. A full pass over a long clip
        // takes minutes, and on an already small file that is time and battery for nothing. The
        // judgement is by frame side and the track's actual bitrate.
        let srcBitrate = Double(vTrack.estimatedDataRate)
        // A ranged pass (a segment) must produce a real piece FILE: returning the whole
        // source here would let the segment loop MOVE the original into seg_0 and destroy it.
        if range == nil, max(ow, oh) <= maxSide * 1.05, srcBitrate > 0, srcBitrate <= Double(2_500_000) * 1.3,
           (src.pathExtension.lowercased() == "mp4" || src.pathExtension.lowercased() == "m4v") {
            progress(1.0)
            return src
        }

        let out = FileManager.default.temporaryDirectory.appendingPathComponent("cmp_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: out)

        guard let reader = try? AVAssetReader(asset: asset),
              let writer = try? AVAssetWriter(outputURL: out, fileType: .mp4) else { return nil }
        writer.shouldOptimizeForNetworkUse = true

        // The composition carries both rotation and scale — one layer instead of hand-built matrices.
        let comp = AVMutableVideoComposition()
        comp.renderSize = CGSize(width: w, height: h)
        comp.frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
        let inst = AVMutableVideoCompositionInstruction()
        inst.timeRange = CMTimeRange(start: .zero, duration: asset.duration)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: vTrack)
        layer.setTransform(vTrack.preferredTransform
            .concatenating(CGAffineTransform(scaleX: CGFloat(w) / ow, y: CGFloat(h) / oh)), at: .zero)
        inst.layerInstructions = [layer]
        comp.instructions = [inst]
        // The phone camera shoots in an extended dynamic range (10-bit HDR). Without an explicit
        // conversion to 709 the composition hands out frames an 8-bit encoder cannot take, and the
        // output is a black picture with living sound. These three properties turn the conversion on.
        comp.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        comp.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        comp.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2

        let vOut = AVAssetReaderVideoCompositionOutput(videoTracks: [vTrack],
            videoSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                AVVideoColorPropertiesKey: [
                    AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                    AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
                ]
            ])
        vOut.videoComposition = comp
        vOut.alwaysCopiesSampleData = false
        guard reader.canAdd(vOut) else { return nil }
        reader.add(vOut)

        // Frame reordering is off: bidirectional frames buy about five per cent of density and
        // cost noticeably more encoding time — an exchange in favour of speed. The key-frame
        // interval is set explicitly; without it seeking hunts for the nearest key frame blindly.
        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: videoBitrate,
            AVVideoMaxKeyFrameIntervalKey: fps * 2,
            AVVideoAllowFrameReorderingKey: false,
            AVVideoExpectedSourceFrameRateKey: fps
        ]
        if useHEVC {
            compression[AVVideoProfileLevelKey] = kVTProfileLevel_HEVC_Main_AutoLevel
        } else {
            compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
            compression[AVVideoH264EntropyModeKey] = AVVideoH264EntropyModeCABAC
        }
        let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: useHEVC ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: w, AVVideoHeightKey: h,
            AVVideoCompressionPropertiesKey: compression,
            // Colour is stated explicitly: without it a receiver reads the frame its own way and
            // the picture drifts in tone.
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
            ]
        ])
        vIn.expectsMediaDataInRealTime = false
        guard writer.canAdd(vIn) else { return nil }
        writer.add(vIn)

        var aOut: AVAssetReaderTrackOutput? = nil
        var aIn: AVAssetWriterInput? = nil
        if let aTrack = asset.tracks(withMediaType: .audio).first {
            // The channel layout and the sample rate come FROM THE SOURCE. A hard-coded "two
            // channels, 44100" without a layout is refused by the AAC encoder — the input was
            // simply never added, and the video went out silent without saying so.
            var channels = 2
            var rate = 44_100.0
            if let fd = aTrack.formatDescriptions.first,
               let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fd as! CMAudioFormatDescription)?.pointee {
                if asbd.mChannelsPerFrame > 0 { channels = Int(asbd.mChannelsPerFrame) }
                if asbd.mSampleRate > 0 { rate = asbd.mSampleRate }
            }
            channels = max(1, min(2, channels))
            var layout = AudioChannelLayout()
            layout.mChannelLayoutTag = channels == 1 ? kAudioChannelLayoutTag_Mono : kAudioChannelLayoutTag_Stereo
            let layoutData = Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size)

            let o = AVAssetReaderTrackOutput(track: aTrack, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
                AVSampleRateKey: rate, AVNumberOfChannelsKey: channels
            ])
            let i = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: channels,
                AVSampleRateKey: rate,
                AVEncoderBitRateKey: channels == 1 ? 48_000 : 64_000,
                AVChannelLayoutKey: layoutData
            ])
            i.expectsMediaDataInRealTime = false
            if reader.canAdd(o), writer.canAdd(i) {
                reader.add(o); writer.add(i); aOut = o; aIn = i
            } else {
                // Sound is never dropped in silence: if the track cannot be configured the whole
                // re-encoding is refused and the original goes out with its sound.
                NSLog("[MEDIA] compress: audio track cannot be configured — abort")
                try? FileManager.default.removeItem(at: out)
                return nil
            }
        }

        if let range { reader.timeRange = range }
        guard writer.startWriting(), reader.startReading() else {
            try? FileManager.default.removeItem(at: out); return nil
        }
        writer.startSession(atSourceTime: range?.start ?? .zero)

        let total = max(CMTimeGetSeconds(range?.duration ?? asset.duration), 0.001)
        let rangeStartSec = CMTimeGetSeconds(range?.start ?? .zero)
        let group = DispatchGroup()
        let beat = MTBeat()

        func pump(_ input: AVAssetWriterInput, _ output: AVAssetReaderTrackOutput?,
                  _ compOutput: AVAssetReaderVideoCompositionOutput?, label: String, reportProgress: Bool) {
            group.enter()
            // Leaving the group exactly once: the block is called many times, and one leave more
            // than enter kills the process on the spot.
            let left = ResumeOnce()
            input.requestMediaDataWhenReady(on: DispatchQueue(label: "mt.video.\(label)")) {
                while input.isReadyForMoreMediaData {
                    guard let sb = output?.copyNextSampleBuffer() ?? compOutput?.copyNextSampleBuffer() else {
                        input.markAsFinished(); left.fire { group.leave() }; return
                    }
                    beat.tick()
                    if reportProgress {
                        // The PTS is absolute source time: a ranged read (a segment) starts at
                        // range.start, and without subtracting it the fraction froze at 0.99.
                        let t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb)) - rangeStartSec
                        if t.isFinite, t > 0 { progress(min(0.99, t / total)) }
                    }
                    if !input.append(sb) { input.markAsFinished(); left.fire { group.leave() }; return }
                }
            }
        }
        pump(vIn, nil, vOut, label: "v", reportProgress: true)
        if let aIn, let aOut { pump(aIn, aOut, nil, label: "a", reportProgress: false) }

        let finish = MTFinishLine()
        // The stall watchdog: the system revokes the hardware codec from a backgrounded app
        // WITHOUT an error — the pump callbacks simply stop coming, nobody cancels anything.
        // Liveness is judged here: twenty active seconds without a single frame is a dead
        // encoder, and the pass is failed fast so the segment can be retaken.
        let stall = Task.detached {
            var lastSeen = beat.stamp()
            var quiet = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard MTForeground.active else { continue }
                let s = beat.stamp()
                if s != lastSeen { lastSeen = s; quiet = 0; continue }
                quiet += 1
                if quiet >= 20 {
                    MTVideoTrace.mark("STALL: no frame for 20 active seconds — failing this pass")
                    reader.cancelReading(); writer.cancelWriting()
                    finish.fire()
                    return
                }
            }
        }
        await withTaskCancellationHandler {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                finish.set(c)
                group.notify(queue: .global()) {
                    // finishWriting after a cancel raises — the status is judged first.
                    if writer.status == .writing {
                        writer.finishWriting { finish.fire() }
                    } else {
                        finish.fire()
                    }
                }
            }
        } onCancel: {
            reader.cancelReading(); writer.cancelWriting()
            finish.fire()
        }
        stall.cancel()

        guard writer.status == .completed, reader.status == .completed else {
            try? FileManager.default.removeItem(at: out); return nil
        }
        // The frozen-vector rule applied to video: a black output against a living source IS the
        // named wrong implementation (an HDR/DV profile slipping past the 709 conversion), and it
        // must be caught HERE — the receiver plays exactly what we hand over. The ladder: our
        // writer -> the system preset (it tone-maps on its own) -> the untouched source (plays
        // everywhere, just bigger). Precedent 23.08: compressed=true, sound alive, picture black.
        if range != nil { progress(1.0); return out }   // a piece is judged after the stitch, on the whole file
        if isBlackOutput(out, against: src, duration: dur) {
            MTVideoTrace.mark("VALIDATE black output — falling back to the system preset")
            try? FileManager.default.removeItem(at: out)
            if let sys = await systemPresetExport(asset: asset), !isBlackOutput(sys, against: src, duration: dur) {
                progress(1.0)
                return sys
            }
            let mb = (((try? FileManager.default.attributesOfItem(atPath: src.path))?[.size] as? Int) ?? 0) / 1_048_576
            MTVideoTrace.mark("VALIDATE system preset failed too — sending the source (\(mb) MB)")
            progress(1.0)
            return src
        }
        progress(1.0)
        return out
    }

    /// Three sample frames, output against source: the output is broken when every sampled
    /// output frame is near-black while the source frame at the same moment is not. A genuinely
    /// dark movie stays accepted — the source is dark at those moments too.
    private static func isBlackOutput(_ out: URL, against src: URL, duration: Double,
                                      srcOffset: Double = 0) -> Bool {
        let d = duration.isFinite && duration > 0 ? duration : 1
        let points = [0.1, 0.5, 0.9].map { d * $0 }
        func luma(_ url: URL, _ t: CMTime) -> Double? {
            let g = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            g.appliesPreferredTrackTransform = true
            g.maximumSize = CGSize(width: 48, height: 48)
            g.requestedTimeToleranceBefore = .positiveInfinity
            g.requestedTimeToleranceAfter = .positiveInfinity
            guard let cg = try? g.copyCGImage(at: t, actualTime: nil) else { return nil }
            guard let data = cg.dataProvider?.data as Data? else { return nil }
            var sum = 0.0; var n = 0
            let bpp = max(1, cg.bitsPerPixel / 8)
            var i = 0
            while i + 2 < data.count { sum += Double(Int(data[i]) + Int(data[i + 1]) + Int(data[i + 2])); n += 3; i += bpp }
            return n > 0 ? sum / Double(n) / 255.0 : nil
        }
        var anyJudged = false
        for p in points {
            let t = CMTime(seconds: p, preferredTimescale: 600)
            guard let lo = luma(out, t) else { continue }
            guard let ls = luma(src, CMTime(seconds: p + srcOffset, preferredTimescale: 600)) else { continue }
            anyJudged = true
            if lo > 0.03 || ls <= 0.03 { return false }   // a living frame, or the source is dark here too
        }
        return anyJudged   // every judged pair: output black, source alive
    }

    /// The system export session as the fallback encoder: no bitrate control, but it handles
    /// HDR/Dolby profiles itself — the property our writer just failed on this source.
    private static func systemPresetExport(asset: AVURLAsset,
                                           preset: String = AVAssetExportPreset1280x720,
                                           range: CMTimeRange? = nil,
                                           progress: (@Sendable (Double) -> Void)? = nil) async -> URL? {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("cmp_sys_\(UUID().uuidString).mp4")
        guard let ex = AVAssetExportSession(asset: asset, presetName: preset) else { return nil }
        ex.outputURL = out
        ex.outputFileType = .mp4
        ex.shouldOptimizeForNetworkUse = true
        if let range { ex.timeRange = range }
        let box = MTExportBox(ex)
        let poll: Task<Void, Never>? = progress.map { report in
            Task.detached {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    report(Double(box.ex.progress))
                }
            }
        }
        await withTaskCancellationHandler {
            await box.ex.export()
        } onCancel: {
            box.ex.cancelExport()
        }
        poll?.cancel()
        guard ex.status == .completed else {
            MTVideoTrace.mark("system export FAILED preset=\(preset) status=\(ex.status.rawValue) err=\(ex.error?.localizedDescription ?? "-")")
            try? FileManager.default.removeItem(at: out)
            return nil
        }
        return out
    }

    // A 10-bit HDR / Dolby Vision source. Our hand-built writer converts such frames to 709
    // on the CPU — measured ~25× slower than realtime (precedent 23.08: one per cent after
    // minutes, zero finished segments). The system export session tone-maps in HARDWARE.
    /// One HDR piece through the system encoder: hardware tone-map, hardware encode — the
    /// fast road for what the phone camera actually shoots. Sits under the same gate and
    /// honours cancellation like the hand-built pass.
    static func hdrPass(asset: AVURLAsset, range: CMTimeRange?,
                        progress: @escaping @Sendable (Double) -> Void,
                        onStart: @escaping @Sendable () -> Void) async -> URL? {
        guard await VideoCompressGate.shared.acquire() else { return nil }
        defer { Task { await VideoCompressGate.shared.release() } }
        if Task.isCancelled { return nil }
        onStart()
        let t0 = Date()
        var out = await systemPresetExport(asset: asset, preset: AVAssetExportPreset960x540,
                                           range: range, progress: progress)
        if out == nil, !Task.isCancelled {
            out = await systemPresetExport(asset: asset, preset: AVAssetExportPreset1280x720,
                                           range: range, progress: progress)
        }
        guard let out else {
            MTVideoTrace.mark("hdr pass FAILED ms=\(Int(Date().timeIntervalSince(t0) * 1000))")
            return nil
        }
        progress(1.0)
        MTVideoTrace.mark("hdr pass done ms=\(Int(Date().timeIntervalSince(t0) * 1000))")
        return out
    }
}

extension MontanaVideo {
    // Resumable encoding: the source is encoded in SEGMENTS (~15 s each), every finished
    // segment is a file on disk that survives backgrounding AND process death — the platform
    // revokes the hardware codec from a backgrounded app, so a single long export can only
    // die and restart from zero (precedent 23.08: "started from 0 again"). Work continues
    // from the first missing segment; the final file is stitched WITHOUT re-encoding.
    static let segmentSeconds: Double = 15

    static func compressResumable(_ src: URL, workDir: URL,
                                  progress: @escaping @Sendable (Double) -> Void,
                                  onStart: @escaping @Sendable () -> Void = {}) async -> URL? {
        let asset = AVURLAsset(url: src)
        let dur = CMTimeGetSeconds(asset.duration)
        guard dur.isFinite, dur > 0 else { return await compress(src, progress: progress, onStart: onStart) }
        let vTrack = asset.tracks(withMediaType: .video).first
        if let vTrack {
            let o = vTrack.naturalSize.applying(vTrack.preferredTransform)
            let side = max(abs(o.width), abs(o.height))
            let br = Double(vTrack.estimatedDataRate)
            MTVideoTrace.mark("plan \(src.lastPathComponent) dur=\(Int(dur))s side=\(Int(side)) br=\(Int(br/1000))k")
            // Already within the target: the source goes as it is — re-encoding it segment
            // by segment was minutes of work for nothing (and the old in-pass shortcut is
            // closed for ranged reads, so the judgement lives HERE now).
            if side <= maxSide * 1.05, br > 0, br <= Double(2_500_000) * 1.3,
               (src.pathExtension.lowercased() == "mp4" || src.pathExtension.lowercased() == "m4v") {
                MTVideoTrace.mark("road=source (already within target)")
                progress(1.0)
                return src
            }
        }
        // Short clips take the single-pass road: one segment would only add a stitch.
        guard dur > segmentSeconds * 2 else {
            MTVideoTrace.mark("road=system-single")
            return await hdrPass(asset: asset, range: nil, progress: progress, onStart: onStart)
        }
        MTVideoTrace.mark("road=system-segments")
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        // Deterministic per file (derived from its duration alone), so a resumed run slices
        // the same way and finished segments stay valid.
        let segLen = max(segmentSeconds, dur / 40)
        let n = Int(ceil(dur / segLen))
        // "Compressing" is announced by the FIRST segment that actually starts work (after the
        // encoder gate), not by this wrapper: announcing it while queued showed a frozen word
        // with no percentages (precedent 23.08 23:07).
        final class Once: @unchecked Sendable { var done = false; let lock = NSLock() }
        let announced = Once()
        let announceOnce: @Sendable () -> Void = {
            announced.lock.lock(); let first = !announced.done; announced.done = true; announced.lock.unlock()
            if first { onStart() }
        }
        var parts: [URL] = []
        for k in 0..<n {
            if Task.isCancelled { return nil }
            let segURL = workDir.appendingPathComponent("seg_\(k).mp4")
            let done = workDir.appendingPathComponent("seg_\(k).ok")
            if FileManager.default.fileExists(atPath: done.path),
               FileManager.default.fileExists(atPath: segURL.path) {
                // A reused FIRST segment faces the same probe as a fresh one: segments left
                // by a run whose writer encoded black would otherwise survive the fix and
                // stitch into a black whole.
                if k == 0,
                   isBlackOutput(segURL, against: src,
                                 duration: min(segLen, dur), srcOffset: 0) {
                    MTVideoTrace.mark("reused first segment is black (writer-era leftover) — wiping segments")
                    try? FileManager.default.removeItem(at: workDir)
                    try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
                } else {
                    MTVideoTrace.mark("seg \(k + 1)/\(n) reused")
                    parts.append(segURL)
                    progress(Double(k + 1) / Double(n))
                    continue
                }
            }
            let start = CMTime(seconds: Double(k) * segLen, preferredTimescale: 600)
            let len = CMTime(seconds: min(segLen, dur - Double(k) * segLen), preferredTimescale: 600)
            let base = Double(k) / Double(n)
            let segT0 = Date()
            let range = CMTimeRange(start: start, duration: len)
            let segProgress: @Sendable (Double) -> Void = { p in progress(base + p / Double(n)) }
            let piece = await hdrPass(asset: asset, range: range, progress: segProgress, onStart: announceOnce)
            guard let piece else {
                MTVideoTrace.mark("seg \(k + 1)/\(n) FAILED ms=\(Int(Date().timeIntervalSince(segT0) * 1000)) — the next run continues from here")
                return nil
            }
            MTVideoTrace.mark("seg \(k + 1)/\(n) done ms=\(Int(Date().timeIntervalSince(segT0) * 1000))")
            try? FileManager.default.removeItem(at: segURL)
            guard (try? FileManager.default.moveItem(at: piece, to: segURL)) != nil else { return nil }
            FileManager.default.createFile(atPath: done.path, contents: Data())
            parts.append(segURL)
        }
        // Stitch: a passthrough export over a composition — seconds, no re-encoding.
        let stitchT0 = Date()
        MTVideoTrace.mark("stitch START n=\(parts.count)")
        let comp = AVMutableComposition()
        var cursor = CMTime.zero
        for u in parts {
            let a = AVURLAsset(url: u)
            let r = CMTimeRange(start: .zero, duration: a.duration)
            guard (try? await comp.insertTimeRange(r, of: a, at: cursor)) != nil else { return nil }
            cursor = CMTimeAdd(cursor, a.duration)
        }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("cmp_all_\(UUID().uuidString).mp4")
        guard let ex = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetPassthrough) else { return nil }
        ex.outputURL = out
        ex.outputFileType = .mp4
        ex.shouldOptimizeForNetworkUse = true
        await ex.export()
        guard ex.status == .completed else {
            MTVideoTrace.mark("stitch FAILED ms=\(Int(Date().timeIntervalSince(stitchT0) * 1000))")
            try? FileManager.default.removeItem(at: out)
            return nil
        }
        MTVideoTrace.mark("stitch done ms=\(Int(Date().timeIntervalSince(stitchT0) * 1000))")
        // The frozen-vector rule on the assembled WHOLE: sample times are valid here, so a
        // black result against a living source is judged where the judgement is honest.
        if isBlackOutput(out, against: src, duration: dur) {
            MTVideoTrace.mark("VALIDATE stitched output black — system preset over the whole")
            try? FileManager.default.removeItem(at: out)
            // Under the gate: an export fighting a running encode for the hardware died with
            // «Operation Interrupted» (precedent 23.08 00:09).
            var sys: URL? = nil
            if await VideoCompressGate.shared.acquire() {
                if !Task.isCancelled {
                    sys = await systemPresetExport(asset: asset, progress: progress)
                }
                Task { await VideoCompressGate.shared.release() }
            }
            if let sys, !isBlackOutput(sys, against: src, duration: dur) {
                try? FileManager.default.removeItem(at: workDir)
                return sys
            }
            let mb = (((try? FileManager.default.attributesOfItem(atPath: src.path))?[.size] as? Int) ?? 0) / 1_048_576
            MTVideoTrace.mark("VALIDATE system preset failed too — sending the source (\(mb) MB)")
            return src
        }
        try? FileManager.default.removeItem(at: workDir)   // the segments served their one purpose
        return out
    }
}

// The ONE builder of a media manifest, used by the app and by the share extension alike. It was
// once written twice, and the two copies had already begun to drift — a video preview existed in
// only one of them. The format of a manifest belongs to the protocol: two implementations of it
// drift by construction, and only the recipient ever sees the difference.
extension MontanaMedia {
    /// The preview a manifest carries: a small frame, bounded in size.
    /// THE ONE SHAPE OF A PHOTO ON ITS WAY OUT ([C-1], the author's word 09.09): the chat shrank
    /// a picture to 1600 px JPEG 0.85 while the share sheet sent the original bytes — a 12 MP
    /// HEIC decoded whole inside an extension with a 120 MB ceiling, and the sheet died between
    /// «SEND tapped» and «SAVED» with nothing in either chat. Both roads ask here now.
    static func photoForSend(_ data: Data, maxDim: CGFloat = 1600, quality: CGFloat = 0.85) -> Data? {
        // Downsampled AT DECODE (ImageIO), never the whole original in memory: a 12 MP frame
        // decoded whole is ~50 MB, and a share of eight from the gallery ran the extension into
        // its ~120 MB ceiling (10.09: the sheet flashed and vanished). The thumbnail path keeps
        // the peak near the output's own size and honours the orientation tag by itself.
        return autoreleasepool { () -> Data? in
            let opts: [CFString: Any] = [kCGImageSourceShouldCache: false]
            guard let src = CGImageSourceCreateWithData(data as CFData, opts as CFDictionary) else { return nil }
            let thumbOpts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: Int(maxDim)
            ]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOpts as CFDictionary) else { return nil }
            return UIImage(cgImage: cg).jpegData(compressionQuality: quality)
        }
    }
    static func previewBase64(_ imageData: Data, maxSide: CGFloat = 200, maxBytes: Int = 16_000) -> String? {
        guard let img = UIImage(data: imageData) else { return nil }
        let scale = min(1, maxSide / max(img.size.width, img.size.height))
        let sz = CGSize(width: img.size.width * scale, height: img.size.height * scale)
        let small = UIGraphicsImageRenderer(size: sz).image { _ in img.draw(in: CGRect(origin: .zero, size: sz)) }
        var q: CGFloat = 0.7
        var d = small.jpegData(compressionQuality: q)
        while let dd = d, dd.count > maxBytes, q > 0.2 { q -= 0.15; d = small.jpegData(compressionQuality: q) }
        guard let out = d, out.count <= maxBytes else { return nil }
        return out.base64EncodedString()
    }

}

/// The poster's moment: the first frame — but a dual note's poster is its LAST frame (the
/// author's word 15.09): the note ends in the state the person chose, both circles in it.
func posterMoment(_ name: String, _ gen: AVAssetImageGenerator) -> CMTime {
    guard name.hasPrefix("vnote_D") else { return CMTime(seconds: 0.1, preferredTimescale: 600) }
    gen.requestedTimeToleranceBefore = .positiveInfinity
    gen.requestedTimeToleranceAfter = .zero
    let d = CMTimeGetSeconds(gen.asset.duration)
    return CMTime(seconds: max(0, (d.isFinite ? d : 0) - 0.05), preferredTimescale: 600)
}

extension MontanaMedia {
    /// A frame taken from a video for the preview — by file reference, without lifting the clip.
    static func videoPreviewBase64(_ url: URL) -> String? {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 640, height: 640)
        guard let cg = try? gen.copyCGImage(at: posterMoment(url.lastPathComponent, gen), actualTime: nil),
              let jpeg = UIImage(cgImage: cg).jpegData(compressionQuality: 0.8) else { return nil }
        return previewBase64(jpeg, maxSide: 320, maxBytes: 12_000)
    }

}

/// THE GROUP OF ONE PICK — the one owner for the chat and the share sheet ([C-1], the author's word
/// 20.09: six photos shared from the sheet stood as six bubbles while the same six from the chat stood
/// on one plate — the key was minted in a file the sheet does not compile). Pictures and videos picked
/// together leave under one key: every letter carries the key, its place and the group's size; the
/// caption rides with the first letter only. Ten is the ceiling of a group; the eleventh picture of a
/// pick opens the next key. The keys are written by ONE hand (stamp) and read by ONE hand (read) —
/// old readers skip them and draw the letters one by one.
enum MTMediaGroup {
    typealias Slot = (key: String, index: Int, count: Int)
    static let ceiling = 10
    /// One key for the letters of one pick: sixteen hex digits of the app's own randomness.
    static func mintKey() -> String {
        montanaRandom(8).map { String(format: "%02x", $0) }.joined()
    }
    /// The place of the i-th picture of a pick: its key (the pick's key, or the key of its tenfold),
    /// its ordinal inside that group and the group's size.
    static func slot(_ i: Int, of total: Int, key: String) -> Slot {
        let chunk = i / ceiling
        return (chunk == 0 ? key : key + "-\(chunk)", i % ceiling, min(ceiling, total - chunk * ceiling))
    }
    /// The slots of a whole pick under one fresh key; a pick of one is no group (every slot nil).
    static func slots(_ total: Int) -> [Slot?] {
        guard total > 1 else { return Array(repeating: nil, count: total) }
        let key = mintKey()
        return (0..<total).map { slot($0, of: total, key: key) }
    }
    static func stamp(_ ref: inout [String: Any], _ g: Slot) {
        ref["gk"] = g.key; ref["gi"] = g.index; ref["gn"] = g.count   // COMPAT-LOCAL: new keys, invisible to every older reader
    }
    static func read(_ ref: [String: Any]) -> Slot? {
        guard let k = ref["gk"] as? String, !k.isEmpty else { return nil }   // absent on an older letter
        return (k, (ref["gi"] as? Int) ?? 0, (ref["gn"] as? Int) ?? 0)
    }
}

extension MontanaMedia {
    /// Seal, upload and assemble the manifest. One path for both places that send.
    static func buildManifest(source: MediaSource, kind: String, ext: String,
                              docName: String? = nil, caption: String = "", thumb: String? = nil, round: Bool = false,
                              badge: String? = nil, forwarded: Bool = false, letterMid: String? = nil,
                              waveform: [Float]? = nil, duration: Double? = nil,
                              group: (key: String, index: Int, count: Int)? = nil,
                              progress: @escaping @Sendable (Double) -> Void) async -> [String: Any]? {
        let size = source.byteCount
        guard let up = await sealAndUpload(source: source, letterMid: letterMid, progress: progress) else { return nil }
        var ref: [String: Any] = ["k": kind, "e": ext,
                                  "bk": up.blobKey.base64EncodedString(),
                                  "sz": size, "chunks": up.manifest]
        if let docName { ref["n"] = docName }
        if round { ref["r"] = true }   // a round video note (the author's word 10.09); old readers skip the key
        if let badge { ref["rb"] = badge }   // the dual note's badge corner (tl|tr|bl|br); old readers skip the key
        if forwarded { ref["fw"] = true }   // a forwarded attachment (the author's word 16.09); old readers skip the key
        if let thumb { ref["th"] = thumb }
        if !caption.isEmpty { ref["cap"] = caption }
        // A MEDIA GROUP (19.09): the key shared by the letters of one pick, this letter's place in it and
        // the group's size — the sender's word, so the receiver folds the plate in the sender's order,
        // never in the order of arrival. Old readers skip the keys and draw the letters one by one.
        if let group { MTMediaGroup.stamp(&ref, group) }
        // The wave of a voice or a track rides with the letter (16.09); old readers skip the key.
        // The shape born with the row is carried as it is (18.09): one probe per file — the app hands
        // the remembered wave, the sheet probes here.
        if kind == "aud" || (kind == "doc" && (mtIsAudioName(docName ?? "") || mtIsAudioName("x." + ext))),
           let w = waveform ?? MTWaveform.compute(source: source, ext: ext) {
            ref["wv"] = MTWaveform.pack(w).base64EncodedString()   // COMPAT-LOCAL: a new key, invisible to every older reader
        }
        // THE DURATION IS THE SENDER'S WORD (18.09, [C-1]): measured by the recorder at the row's
        // birth, it rides with the letter so the receiver's row is born with it — before the file,
        // and even when the file arrived ahead of the manifest. Old readers skip the key.
        if kind == "aud", let du = duration, du > 0, du.isFinite {
            ref["du"] = (du * 10).rounded() / 10   // COMPAT-LOCAL: a new key, invisible to every older reader
        }
        return ref
    }
}

extension MontanaMedia {
    /// Whether a picture carries real transparency (the author's word 10.09): a see-through
    /// picture pasted into the field is a sticker, an opaque one is a photo. An alpha channel
    /// alone says nothing — screenshots carry one fully opaque — so the pixels are asked, on a
    /// small copy: any pixel under half opacity makes it a sticker.
    static func hasTransparency(_ ui: UIImage) -> Bool {
        guard let cg = ui.cgImage else { return false }
        switch cg.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: break
        }
        let w = 64, h = 64
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var i = 3
        while i < px.count {
            if px[i] < 128 { return true }
            i += 4
        }
        return false
    }
}
