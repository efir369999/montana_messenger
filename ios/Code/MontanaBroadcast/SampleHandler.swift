import ReplayKit
import AVFoundation
import Photos

// The system broadcast picks THIS handler to receive the device screen. The frames ride a loopback TCP socket into the
// running call, which sends them down the standing encrypted video lane. A loopback port is open to every app on the
// device, so the listener proves the call's key before a frame leaves (MontanaScreenWire): no proven call on any port --
// the broadcast refuses to start, and the screen never leaves the device outside a live call. The app's stop word ends
// the share quietly; an end without it means the app is gone, and the person is told so. The extension's own lines wait
// in the shared keychain for the app's diary. Where no call stands, the press was the system's screen recording with
// Montana as its last chosen target: the screen is recorded on the device into Photos instead (ScreenRecorder).
final class SampleHandler: RPBroadcastSampleHandler {
    private let q = DispatchQueue(label: "montana.broadcast")   // every touch of the socket, one after another
    private var fd: Int32 = -1
    private var stopWatch: DispatchSourceRead?
    private var ended = false
    private var frames = 0
    private var aliveAt: CFAbsoluteTime = 0
    private var diary: [String] = []
    private let gate = NSLock()                  // between ReplayKit's thread and q: one frame in flight
    private var live = false
    private var sending = false
    private var lastSent: CFAbsoluteTime = 0
    private var recorder: ScreenRecorder?        // under gate: set once at the start, taken once at the end

    // LEFTOVER-ACK: ReplayKit calls this, not our tree -- an override of RPBroadcastSampleHandler
    // has no caller in the repository by construction.
    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        q.sync { self.start() }
    }

    private func start() {
        note("started")
        guard let key = MontanaScreenWire.key() else {
            note("no call key -- no call stands")
            record()
            return
        }
        for port in MontanaScreenWire.ports {
            if let s = dial(port, key: key) { adopt(s, port: port); return }
        }
        note("no listener proved the call's key")
        record()
    }

    /// No call stands, so the person pressed the system's screen recording while Montana was the target it last chose
    /// (the share in a call picks it). That is a recording, not an error: the screen and its sound are written on the
    /// device and laid into Photos, as the system's own recorder does; nothing leaves the device. Without the right to
    /// add to Photos the person is told at once, before anything is recorded for nowhere.
    private func record() {
        // The movie is written on the app group's shelf, so the app can carry it into Photos with its own right (T1 18:15: the
        // broadcast's own right to Photos was refused); without the group it is written in the extension's own folder.
        let place = MontanaScreenShelf.dir ?? FileManager.default.temporaryDirectory
        let name = "Montana-" + String(Int(Date().timeIntervalSince1970)) + "-" + String(UUID().uuidString.prefix(8))
        gate.lock(); recorder = ScreenRecorder(url: place.appendingPathComponent(name + ".mov.part")); gate.unlock()
        note("recording to \(MontanaScreenShelf.dir == nil ? "the extension's own folder" : "the shelf")")
    }

    /// The movie goes where the system's own recorder puts it; the copy on the device is let go only once Photos says
    /// it holds the movie. Whole, the movie is named «.mov» on the shelf; Photos takes it here when the broadcast has the
    /// right to add, else the app takes it at its next activation (MTScreenShelfTake).
    private func lay(_ r: ScreenRecorder) {
        guard r.close() else {
            q.sync { note("the recording did not close whole frames=\(r.frames)") }
            return
        }
        let whole = r.url.deletingPathExtension()
        guard (try? FileManager.default.moveItem(at: r.url, to: whole)) != nil else {
            q.sync { note("the whole movie could not be named frames=\(r.frames)") }
            return
        }
        let access = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard access == .authorized || access == .limited else {
            q.sync { note("the movie waits on the shelf for the app access=\(access.rawValue) frames=\(r.frames)") }
            return
        }
        let answered = DispatchSemaphore(value: 0)
        var held = false
        PHPhotoLibrary.shared().performChanges({
            PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: whole, options: nil)
        }) { ok, _ in
            held = ok
            answered.signal()
        }
        let inTime = answered.wait(timeout: .now() + 20) == .success
        q.sync { note("photos \(held ? "hold" : "refused") the recording in time=\(inTime) frames=\(r.frames)") }
        if held { try? FileManager.default.removeItem(at: whole) }
    }

    /// The dialler's half of the proof: our hello and nonce, the listener's nonce and proof, our proof. A listener that
    /// cannot prove the call's key is a stranger: the next port is tried, and nothing of the screen reaches it.
    private func dial(_ port: UInt16, key: Data) -> Int32? {
        let s = socket(AF_INET, SOCK_STREAM, 0)
        guard s >= 0 else { return nil }
        var endpoint = MontanaScreenWire.loopback(port)
        let len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let r = withUnsafePointer(to: &endpoint) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(s, $0, len) }
        }
        guard r == 0 else { close(s); return nil }
        var on: Int32 = 1
        setsockopt(s, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        MontanaScreenWire.deadline(s, read: 2, write: 5)   // a silent listener cannot hold the start; a stuck app cannot hold a frame
        let extNonce = MontanaScreenWire.fresh(MontanaScreenWire.nonceSize)
        guard extNonce.count == MontanaScreenWire.nonceSize,
              MontanaScreenWire.writeAll(s, MontanaScreenWire.le32(MontanaScreenWire.helloMagic) + extNonce),
              let reply = MontanaScreenWire.readData(s, MontanaScreenWire.nonceSize + MontanaScreenWire.proofSize) else {
            close(s); note("port \(port): no answer to the hello"); return nil
        }
        let appNonce = Data(reply.prefix(MontanaScreenWire.nonceSize))
        let theirs = Data(reply.suffix(MontanaScreenWire.proofSize))
        guard MontanaScreenWire.proves(theirs, key, .app, ext: extNonce, app: appNonce) else {
            close(s); note("port \(port): the listener did not prove the call's key -- a stranger, passed by"); return nil
        }
        guard MontanaScreenWire.writeAll(s, MontanaScreenWire.proof(key, .ext, ext: extNonce, app: appNonce)) else {
            close(s); return nil
        }
        return s
    }

    private func adopt(_ s: Int32, port: UInt16) {
        fd = s
        note("proven on port \(port)")
        // The app's stop word, or its end, is heard the moment it comes -- not at the next changed screen.
        let w = DispatchSource.makeReadSource(fileDescriptor: s, queue: q)
        w.setEventHandler { [weak self] in self?.heard() }
        w.setCancelHandler { close(s) }   // the descriptor's one close
        w.resume()
        stopWatch = w
        gate.lock(); live = true; gate.unlock()
    }

    private func heard() {
        guard fd >= 0 else { return }
        var b: UInt8 = 0
        let n = recv(fd, &b, 1, MSG_DONTWAIT)
        if n == 1 { end(word: b); return }
        if n == 0 { end(word: nil, why: "the app closed without a word"); return }
        let e = errno
        if e == EAGAIN || e == EWOULDBLOCK || e == EINTR { return }
        end(word: nil, why: "read errno=\(e)")
    }

    // LEFTOVER-ACK: ReplayKit delivers every frame here; no caller in the tree by construction.
    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        gate.lock(); let r = recorder; gate.unlock()
        if let r { r.append(sampleBuffer, sampleBufferType); return }
        guard sampleBufferType == .video else { return }
        let now = CFAbsoluteTimeGetCurrent()
        gate.lock()
        // 30 fps: below it motion tears, above it the encoder outruns the uplink; one frame in flight at a time.
        let take = live && !sending && now - lastSent >= 1.0 / 30.0
        if take { sending = true; lastSent = now }
        gate.unlock()
        guard take else { return }
        var orientation: UInt32 = 1   // CGImagePropertyOrientation.up
        if let a = CMGetAttachment(sampleBuffer, key: RPVideoSampleOrientationKey as CFString,
                                   attachmentModeOut: nil) as? NSNumber {
            orientation = a.uint32Value
        }
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer),
              let frame = Self.frameBytes(pb, pts: CMSampleBufferGetPresentationTimeStamp(sampleBuffer), orientation: orientation) else {
            gate.lock(); sending = false; gate.unlock()
            return
        }
        q.async { self.send(frame) }
    }

    private func send(_ frame: Data) {
        defer { gate.lock(); sending = false; gate.unlock() }
        guard fd >= 0, !ended else { return }
        guard MontanaScreenWire.writeAll(fd, frame) else {
            let e = errno
            var b: UInt8 = 0
            if recv(fd, &b, 1, MSG_DONTWAIT) == 1 { end(word: b); return }   // the app said its word before it let go
            end(word: nil, why: e == EAGAIN || e == EWOULDBLOCK ? "the app took no frame for 5 s" : "write errno=\(e)")
            return
        }
        frames += 1
        if frames == 1 { note("first frame bytes=\(frame.count)") }
        let now = CFAbsoluteTimeGetCurrent()
        if now - aliveAt >= 15 { aliveAt = now; note("alive frames=\(frames)") }
    }

    /// One header both sides share (MontanaScreenWire): magic, w, h, format, planes, orientation, pts64; then each
    /// plane's row bytes, its rows and its bytes.
    private static func frameBytes(_ pb: CVPixelBuffer, pts: CMTime, orientation: UInt32) -> Data? {
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        let planar = CVPixelBufferIsPlanar(pb)
        let planes = planar ? CVPixelBufferGetPlaneCount(pb) : 1
        guard planes <= 3 else { return nil }
        var d = Data()
        d.append(MontanaScreenWire.le32(MontanaScreenWire.frameMagic))
        d.append(MontanaScreenWire.le32(UInt32(CVPixelBufferGetWidth(pb))))
        d.append(MontanaScreenWire.le32(UInt32(CVPixelBufferGetHeight(pb))))
        d.append(MontanaScreenWire.le32(UInt32(CVPixelBufferGetPixelFormatType(pb))))
        d.append(MontanaScreenWire.le32(UInt32(planes)))
        d.append(MontanaScreenWire.le32(orientation))
        let ns = pts.isValid ? Int64(pts.seconds * 1_000_000_000) : 0
        d.append(withUnsafeBytes(of: UInt64(bitPattern: ns).littleEndian) { Data($0) })
        for i in 0..<planes {
            let bpr = planar ? CVPixelBufferGetBytesPerRowOfPlane(pb, i) : CVPixelBufferGetBytesPerRow(pb)
            let ph  = planar ? CVPixelBufferGetHeightOfPlane(pb, i)      : CVPixelBufferGetHeight(pb)
            guard let base = planar ? CVPixelBufferGetBaseAddressOfPlane(pb, i) : CVPixelBufferGetBaseAddress(pb) else { return nil }
            d.append(MontanaScreenWire.le32(UInt32(bpr)))
            d.append(MontanaScreenWire.le32(UInt32(ph)))
            d.append(Data(bytes: base, count: bpr * ph))
        }
        return d
    }

    /// The share is over (on q). The app's word ends it quietly -- the app chose it; an end without a word means the app
    /// is gone, and the person is told so rather than left with the system's own error.
    private func end(word: UInt8?, why: String = "") {
        guard !ended else { return }
        ended = true
        gate.lock(); live = false; gate.unlock()
        let s = fd; fd = -1
        if let w = stopWatch { stopWatch = nil; w.cancel() } else if s >= 0 { close(s) }
        guard let word else {
            note("the app is gone -- \(why) frames=\(frames)")
            finish(String(localized: "Montana closed, so the screen share stopped.", bundle: MTLanguage.bundle))
            return
        }
        if MontanaScreenWire.Stop(rawValue: word) == .streamBroken {
            note("the app could not read the stream frames=\(frames)")
            finish(String(localized: "Montana could not read the screen stream.", bundle: MTLanguage.bundle))
            return
        }
        note("the app let it go: word=\(word) frames=\(frames)")
        // A nil error finishes the broadcast with no system alert; nil rides the objc selector because
        // the Swift signature refuses it.
        perform(#selector(RPBroadcastSampleHandler.finishBroadcastWithError(_:)), with: nil)
    }
    private func finish(_ reason: String) {
        finishBroadcastWithError(NSError(domain: "MontanaBroadcast", code: 1, userInfo: [NSLocalizedFailureReasonErrorKey: reason]))
    }

    // LEFTOVER-ACK: ReplayKit calls this on stop; no caller in the tree by construction.
    override func broadcastFinished() {
        gate.lock(); let r = recorder; recorder = nil; gate.unlock()
        // The extension may be let go the moment this returns, so the movie is closed and laid here, in step.
        if let r { lay(r); return }
        q.async {
            guard !self.ended else { return }
            self.ended = true
            self.gate.lock(); self.live = false; self.gate.unlock()
            let s = self.fd; self.fd = -1
            if let w = self.stopWatch { self.stopWatch = nil; w.cancel() } else if s >= 0 { close(s) }
            self.note("the system finished it frames=\(self.frames)")
        }
    }
    // LEFTOVER-ACK: ReplayKit calls this on a pause; no caller in the tree by construction.
    override func broadcastPaused() { q.async { self.note("paused by the system") } }
    // LEFTOVER-ACK: ReplayKit calls this on a resume; no caller in the tree by construction.
    override func broadcastResumed() { q.async { self.note("resumed by the system") } }

    /// A line into the box the app reads (on q).
    private func note(_ text: String) {
        if !diary.isEmpty, MontanaScreenWire.diaryTaken { diary.removeAll() }   // the app read them: the box starts anew
        diary.append(Self.stamp.string(from: Date()) + " " + text)
        if diary.count > 40 { diary.removeFirst(diary.count - 40) }
        MontanaScreenWire.keepDiary(diary)
    }
    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "HH:mm:ss.SSS'Z'"
        return f
    }()
}

/// The device's own recording where no call stands: one movie begun at the first picture, the screen scaled as the
/// system's recorder scales it (1920 high at most), the sound of the apps and of the microphone each on its own track.
/// Every append and the close take one lock, so ReplayKit's threads and the close never meet halfway.
private final class ScreenRecorder {
    let url: URL
    private let lock = NSLock()
    private var writer: AVAssetWriter?
    private var picture: AVAssetWriterInput?
    private var appSound: AVAssetWriterInput?
    private var micSound: AVAssetWriterInput?
    private var closed = false
    private(set) var frames = 0

    init(url: URL) { self.url = url }

    func append(_ buffer: CMSampleBuffer, _ kind: RPSampleBufferType) {
        lock.lock(); defer { lock.unlock() }
        guard !closed, CMSampleBufferDataIsReady(buffer) else { return }
        if writer == nil {
            guard kind == .video else { return }
            guard begin(buffer) else { closed = true; return }
        }
        guard writer?.status == .writing else { return }
        switch kind {
        case .video:
            if let p = picture, p.isReadyForMoreMediaData, p.append(buffer) { frames += 1 }
        case .audioApp:
            if let a = appSound, a.isReadyForMoreMediaData { _ = a.append(buffer) }
        case .audioMic:
            if let m = micSound, m.isReadyForMoreMediaData { _ = m.append(buffer) }
        @unknown default:
            break
        }
    }

    private func begin(_ first: CMSampleBuffer) -> Bool {
        guard let pb = CMSampleBufferGetImageBuffer(first),
              let w = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return false }
        let width = CVPixelBufferGetWidth(pb), height = CVPixelBufferGetHeight(pb)
        let scale = min(1.0, 1920.0 / Double(max(width, height, 1)))
        let even = { (side: Int) -> Int in max(2, Int((Double(side) * scale / 2).rounded()) * 2) }
        let p = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: even(width),
            AVVideoHeightKey: even(height),
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspect,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: even(width) * even(height) * 4],
        ])
        p.expectsMediaDataInRealTime = true
        p.transform = Self.transform(first)
        let a = Self.sound(channels: 2), m = Self.sound(channels: 1)
        for input in [p, a, m] {
            guard w.canAdd(input) else { return false }
            w.add(input)
        }
        guard w.startWriting() else { return false }
        w.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(first))
        writer = w; picture = p; appSound = a; micSound = m
        return true
    }

    private static func sound(channels: Int) -> AVAssetWriterInput {
        let s = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: 64_000 * channels,
        ])
        s.expectsMediaDataInRealTime = true
        return s
    }

    /// ReplayKit hands the screen as it lies in the panel and names the turn of the device beside it; the movie keeps
    /// the turn, as a camera's movie does.
    private static func transform(_ b: CMSampleBuffer) -> CGAffineTransform {
        guard let n = CMGetAttachment(b, key: RPVideoSampleOrientationKey as CFString, attachmentModeOut: nil) as? NSNumber,
              let o = CGImagePropertyOrientation(rawValue: n.uint32Value) else { return .identity }
        switch o {
        case .right: return CGAffineTransform(rotationAngle: .pi / 2)
        case .left: return CGAffineTransform(rotationAngle: -.pi / 2)
        case .down: return CGAffineTransform(rotationAngle: .pi)
        default: return .identity
        }
    }

    /// Ends the movie on the caller's thread, in step; true when the file is whole.
    func close() -> Bool {
        lock.lock()
        closed = true
        let w = writer
        let inputs = [picture, appSound, micSound].compactMap { input in input }
        lock.unlock()
        guard let w, w.status == .writing else { return false }
        inputs.forEach { input in input.markAsFinished() }
        let done = DispatchSemaphore(value: 0)
        w.finishWriting { done.signal() }
        done.wait()
        return w.status == .completed
    }
}
