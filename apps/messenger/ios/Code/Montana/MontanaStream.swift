//
//  MontanaStream.swift
//  Montana — a Montana messenger
//
//  THE CARGO COMES IN PIECES, AND A FILE PLAYS FROM ITS FIRST ONES (the author's word 25.09: «everything in a streaming
//  form, in pieces, not all at once and not in the way of the rest; a tap on a track or a video starts it at once, with a
//  buffer; a video in the feed plays by itself»). Two things live here: the one lane every piece of cargo passes through,
//  and the loader the system player reads a file through before the file is whole.
//

import Foundation
import AVFoundation
import UniformTypeIdentifiers

/// THE ONE LANE FOR THE NODE'S CARGO. Every piece this phone asks the doors for passes here — a look at a tile, a tap on a
/// track, the feed's playing clip, a chat's attachment: three questions in flight for the whole phone, never more, so the
/// letters, the calls and the screen keep their road. The piece a player is WAITING FOR goes first, then what stands on the
/// screen, then what is only brought ahead; among equals, the earlier ask. A piece already asked is joined, never asked
/// twice; a piece nobody waits for any more is not asked at all. The doors' own answers (found, gone, busy, unreachable)
/// and their patience stay where they were (MontanaWakePush.bringChunk); the lane decides only when and how many.
actor MTCargoLane {
    static let shared = MTCargoLane()
    static let width = 3
    enum Need: Int { case ahead = 0, look = 1, play = 2 }
    enum Answer { case found(Data), gone, unreachable }

    private struct Ask {
        var need: Need
        let seq: Int
        var waiters: [(ticket: Int, c: CheckedContinuation<Answer, Never>)]
    }
    private var asks: [String: Ask] = [:]
    private var inFlight: Set<String> = []
    private var seq = 0
    private var tickets = 0
    private var served = 0

    /// The piece: from the store when it lies here, else from the doors in the lane's turn.
    func bring(_ bid: String, need: Need) async -> Answer {
        if let d = MontanaBlobStore.get(bid) { return .found(d) }
        tickets += 1
        let mine = tickets
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (c: CheckedContinuation<Answer, Never>) in
                self.enqueue(bid, need: need, ticket: mine, c)
            }
        } onCancel: {
            Task { await self.leave(bid, ticket: mine) }
        }
    }

    private func enqueue(_ bid: String, need: Need, ticket: Int, _ c: CheckedContinuation<Answer, Never>) {
        if var a = asks[bid] {
            a.waiters.append((ticket, c))
            if a.need.rawValue < need.rawValue { a.need = need }
            asks[bid] = a
        } else {
            seq += 1
            asks[bid] = Ask(need: need, seq: seq, waiters: [(ticket, c)])
        }
        // A WAIT IN THE LINE HAS A TERM (29.09): a piece still unasked past it is answered «unreachable» — the road that asked fails
        // honestly and retries later, instead of a download that neither ends nor speaks while its in-flight mark keeps every retry
        // away. A piece already asked is the doors' own term (bringChunk, under two minutes).
        Task { [ticket] in
            try? await Task.sleep(nanoseconds: Self.waitLimitNs)
            self.expire(bid, ticket: ticket)   // the task inherits the actor: a plain call
        }
        pump()
    }

    /// The asker left (the tile scrolled away, the player closed): its wait ends now; a piece nobody else waits for
    /// is dropped from the queue before it is asked.
    private func leave(_ bid: String, ticket: Int) {
        guard var a = asks[bid], let i = a.waiters.firstIndex(where: { $0.ticket == ticket }) else { return }
        let gone = a.waiters.remove(at: i)
        if a.waiters.isEmpty, !inFlight.contains(bid) { asks[bid] = nil } else { asks[bid] = a }
        gone.c.resume(returning: .unreachable)
    }
    static let waitLimitNs: UInt64 = 180_000_000_000
    /// The term of a wait in the line: an unasked piece leaves as «unreachable»; one in flight is left to the doors.
    private func expire(_ bid: String, ticket: Int) {
        guard !inFlight.contains(bid) else { return }
        leave(bid, ticket: ticket)
    }

    private func pump() {
        while inFlight.count < Self.width {
            let waiting = asks.filter { !inFlight.contains($0.key) }
            guard let next = waiting.max(by: { a, b in
                a.value.need.rawValue != b.value.need.rawValue ? a.value.need.rawValue < b.value.need.rawValue : a.value.seq > b.value.seq
            }) else { return }
            inFlight.insert(next.key)
            Task { await self.run(next.key) }
        }
    }

    private func run(_ bid: String) async {
        let answer = await MontanaWakePush.bringChunk(bid)
        settle(bid, answer)
    }

    private func settle(_ bid: String, _ answer: Answer) {
        inFlight.remove(bid)
        served += 1
        if let a = asks.removeValue(forKey: bid) {
            for w in a.waiters { w.c.resume(returning: answer) }
        }
        if served % 25 == 0 || asks.isEmpty {
            MontanaTrace.markFolded("cargo_lane", "served=\(served) queued=\(asks.count) flying=\(inFlight.count)", window: 30)
        }
        pump()
    }
}

/// WHAT A PLAYER READS BEFORE THE FILE IS WHOLE: the file's pieces — their sizes in order, the key that opens them — and
/// the folder the whole file stands in under its name. One shape for a post's file, a chat's attachment and a track.
struct MTStreamSource: Equatable {
    let name: String            // the file's name on this phone, given at its birth
    let ext: String
    let size: Int
    let key: Data
    let chunks: [MTBoardChunk]  // bid and the piece's own length, in order
    let folder: URL

    var url: URL {
        let safe = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        return URL(string: MTStreamLoader.scheme + "://file/" + safe) ?? URL(fileURLWithPath: "/" + name)
    }
}

/// A FILE PLAYS FROM ITS FIRST PIECES. The system player reads a file of its own scheme by byte ranges through this loader; a
/// range is served from the pieces already laid in the file on disk, and the rest are brought by the lane — the piece the
/// player waits for first (Need.play). Every piece brought is laid into the file at its place and marked in the file's own
/// ledger beside it, so a play that stops half-way keeps what it brought and a launch later goes on from there; when every
/// piece lies there the file is whole: it takes its name, and whoever asked is told. The container is the player's business,
/// not ours: a video exported for the network (its header first) starts in a second; a track with its header at the end asks
/// for the last piece first, and gets it. Nothing is brought that the player did not ask for.
final class MTStreamLoader: NSObject, AVAssetResourceLoaderDelegate {
    static let scheme = "montana-stream"
    /// The two files a stream lays beside its file's name: the bytes while they come, and the ledger of the pieces.
    static let partTail = ".part", ledgerTail = ".have"
    /// The file a name on disk belongs to: a part's or a ledger's own file, else the name itself.
    static func fileOf(_ n: String) -> String {
        for tail in [partTail, ledgerTail] where n.hasSuffix(tail) { return String(n.dropLast(tail.count)) }
        return n
    }
    let source: MTStreamSource
    private let starts: [Int]           // each piece's first byte
    private let part: URL               // the file being laid, «name.part»
    private let ledger: URL             // «name.have»: one byte per piece, 1 where the piece lies in the file
    private let lock = NSLock()
    private var body: URL               // where the file's bytes lie now: the part while it is laid, the name once whole
    private var have: [UInt8]
    private var bringing: [Int: Task<Data?, Never>] = [:]
    private var serving: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var whole = false
    private var onWhole: [() -> Void] = []
    private let queue = DispatchQueue(label: "montana.stream.loader", qos: .userInitiated)

    init(_ s: MTStreamSource) {
        source = s
        var st: [Int] = []
        var off = 0
        for c in s.chunks { st.append(off); off += c.cs }
        starts = st
        part = s.folder.appendingPathComponent(s.name + Self.partTail)
        ledger = s.folder.appendingPathComponent(s.name + Self.ledgerTail)
        body = part
        let n = s.chunks.count
        let fm = FileManager.default
        if let d = try? Data(contentsOf: ledger), d.count == n, fm.fileExists(atPath: part.path) {
            have = [UInt8](d)   // a play that stopped half-way: what it brought is still here
        } else {
            have = [UInt8](repeating: 0, count: n)
            fm.createFile(atPath: part.path, contents: nil)
            if let h = try? FileHandle(forWritingTo: part) { try? h.truncate(atOffset: UInt64(s.size)); try? h.close() }
            try? Data(have).write(to: ledger)
        }
        super.init()
        MontanaTrace.mark("stream_open", "name=\(String(s.name.prefix(20))) bytes=\(s.size) pieces=\(n) laid=\(have.filter { $0 == 1 }.count)")
    }

    /// The asset the player reads through this loader. The player holds the delegate weakly; MTStreams holds the loader.
    func asset() -> AVURLAsset {
        let a = AVURLAsset(url: source.url)
        a.resourceLoader.setDelegate(self, queue: queue)
        return a
    }

    func tell(whenWhole f: @escaping () -> Void) {
        lock.lock()
        let already = whole
        if !already { onWhole.append(f) }
        lock.unlock()
        if already { DispatchQueue.main.async(execute: f) }
    }

    // MARK: the player's requests

    func resourceLoader(_ loader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource r: AVAssetResourceLoadingRequest) -> Bool {
        if let info = r.contentInformationRequest {
            info.contentType = UTType(filenameExtension: source.ext)?.identifier
            info.contentLength = Int64(source.size)
            info.isByteRangeAccessSupported = true
        }
        guard let dr = r.dataRequest else { r.finishLoading(); return true }
        let key = ObjectIdentifier(r)
        let t = Task { await self.serve(r, dr) }
        lock.lock(); serving[key] = t; lock.unlock()
        return true
    }

    func resourceLoader(_ loader: AVAssetResourceLoader, didCancel r: AVAssetResourceLoadingRequest) {
        let key = ObjectIdentifier(r)
        lock.lock(); let t = serving.removeValue(forKey: key); lock.unlock()
        t?.cancel()
    }

    private func serve(_ r: AVAssetResourceLoadingRequest, _ dr: AVAssetResourceLoadingDataRequest) async {
        var at = Int(dr.currentOffset)
        let end = dr.requestsAllDataToEndOfResource ? source.size : min(source.size, Int(dr.requestedOffset) + Int(dr.requestedLength))
        while at < end {
            if Task.isCancelled { done(r); return }
            guard let i = index(of: at), let piece = await piece(i) else {
                if !Task.isCancelled { r.finishLoading(with: NSError(domain: "montana.stream", code: 1)) }
                done(r)
                return
            }
            let from = at - starts[i]
            let take = min(end - at, piece.count - from)
            guard 0 < take else {
                if !Task.isCancelled { r.finishLoading(with: NSError(domain: "montana.stream", code: 2)) }
                done(r)
                return
            }
            dr.respond(with: piece.subdata(in: from..<(from + take)))
            at += take
        }
        if !Task.isCancelled { r.finishLoading() }
        done(r)
    }

    private func done(_ r: AVAssetResourceLoadingRequest) {
        lock.lock(); serving[ObjectIdentifier(r)] = nil; lock.unlock()
    }

    private func index(of byte: Int) -> Int? {
        guard 0 <= byte, byte < source.size, !starts.isEmpty else { return nil }
        var lo = 0, hi = starts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if starts[mid] <= byte { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    // MARK: the pieces

    /// The piece's bytes: from the file when it lies there; else brought once — by whichever request asked first — laid
    /// into the file and marked.
    private func piece(_ i: Int) async -> Data? {
        let (laid, task) = claim(i)
        if laid { return read(i) }
        return await task?.value
    }
    /// Whether the piece lies in the file, else the one task bringing it — born here when nobody brings it yet.
    private func claim(_ i: Int) -> (Bool, Task<Data?, Never>?) {
        lock.lock(); defer { lock.unlock() }
        if have[i] == 1 { return (true, nil) }
        if let t = bringing[i] { return (false, t) }
        let t: Task<Data?, Never> = Task { await self.lay(i) }
        bringing[i] = t
        return (false, t)
    }
    private func release(_ i: Int) { lock.lock(); bringing[i] = nil; lock.unlock() }
    /// The piece is in the file: marked; the ledger's word and whether the file is whole now.
    private func laid(_ i: Int) -> (Data, Bool) {
        lock.lock(); defer { lock.unlock() }
        have[i] = 1
        return (Data(have), !have.contains(0))
    }

    private func read(_ i: Int) -> Data? {
        lock.lock(); let at = body; lock.unlock()
        guard let h = try? FileHandle(forReadingFrom: at) else { return nil }
        defer { try? h.close() }
        guard (try? h.seek(toOffset: UInt64(starts[i]))) != nil else { return nil }
        return try? h.read(upToCount: source.chunks[i].cs)
    }

    private func lay(_ i: Int) async -> Data? {
        defer { release(i) }
        let c = source.chunks[i]
        let t0 = Date()
        guard case .found(let sealed) = await MTCargoLane.shared.bring(c.bid, need: .play),
              let plain = MontanaMedia.openChunk(sealed: sealed, blobKey: source.key, expectedIdHex: c.bid, size: c.cs) else {
            MontanaTrace.markFolded("stream_piece", "FAIL i=\(i) of \(source.chunks.count) name=\(String(source.name.prefix(20)))",
                                       window: 10, key: source.name)
            return nil
        }
        // The disk refusing the piece costs the player nothing: it gets its bytes; the piece is simply not kept.
        if let h = try? FileHandle(forWritingTo: part), (try? h.seek(toOffset: UInt64(starts[i]))) != nil,
           (try? h.write(contentsOf: plain)) != nil {
            try? h.close()
            let (snapshot, all) = laid(i)
            try? snapshot.write(to: ledger)
            MontanaTrace.markFolded("stream_piece", "i=\(i) of \(source.chunks.count) ms=\(Int(Date().timeIntervalSince(t0) * 1000)) name=\(String(source.name.prefix(20)))",
                                       window: 5, key: source.name)
            if all { becomeWhole() }
        }
        return plain
    }

    /// Every piece lies in the file: it takes its name. A rename keeps every open handle on the same bytes. A file already
    /// standing under the name (another road finished first) is left as it is; the part goes.
    private func becomeWhole() {
        lock.lock()
        if whole { lock.unlock(); return }
        whole = true
        lock.unlock()
        let final = source.folder.appendingPathComponent(source.name)
        let fm = FileManager.default
        if fm.fileExists(atPath: final.path) { try? fm.removeItem(at: part) }
        else if (try? fm.moveItem(at: part, to: final)) == nil { return }
        try? fm.removeItem(at: ledger)
        lock.lock(); body = final; let told = onWhole; onWhole = []; lock.unlock()
        MontanaTrace.mark("stream_whole", "name=\(String(source.name.prefix(20))) bytes=\(source.size) pieces=\(source.chunks.count)")
        DispatchQueue.main.async { for f in told { f() } }
    }
}

/// THE LOADERS, ONE PER FILE: the feed's tile and the full player of one video read through one loader, and a file half
/// brought is never brought twice. A loader lives until its file is whole; a phone that looks at a hundred clips keeps
/// the latest thirty-two — the others' ledgers stay on disk, and a look later goes on from them.
enum MTStreams {
    private static let lock = NSLock()
    private static var loaders: [String: MTStreamLoader] = [:]
    private static var order: [String] = []
    static let kept = 32

    static func asset(_ s: MTStreamSource, whole: (() -> Void)? = nil) -> AVURLAsset {
        lock.lock(); let held = loaders[s.name]; lock.unlock()
        var l: MTStreamLoader
        if let held, held.source == s { l = held }
        else {
            let born = MTStreamLoader(s)   // the file and its ledger are opened off the lock
            lock.lock()
            if let again = loaders[s.name], again.source == s { l = again }
            else {
                loaders[s.name] = born
                order.removeAll { $0 == s.name }
                order.append(s.name)
                if Self.kept < order.count { let old = order.removeFirst(); loaders[old] = nil }
                l = born
            }
            lock.unlock()
        }
        if let whole { l.tell(whenWhole: whole) }
        return l.asset()
    }

    /// Whether a file's pieces are still being laid — a player may read it through the loader even while another road
    /// brings the whole (the lane joins the two).
    static func holds(_ name: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return loaders[name] != nil
    }
}
