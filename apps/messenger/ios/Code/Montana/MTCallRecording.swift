import Foundation
import AVFoundation
import CoreImage
import CryptoKit
import SwiftUI
import WebRTC

// A reader of the call's existing media. It never opens a microphone, camera or audio session.
// The SDK owns processing; AVAssetWriter/AVAssetExportSession own encoding, timing and mixing.
// A call's identity survives native call UUID replacement on process restoration.
enum MTCallName {
    static func name(_ secret: Data) -> String {
        SHA256.hash(data: Data("montana.call.identity.v1:".utf8) + secret).map { String(format: "%02x", $0) }.joined()
    }
}

enum MTCallRecordingPolicy {
    static let key = "callRecordingEnabled"
    static let consentKey = "callRecordingConsent.v1"
    static var enabled: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
    static var consented: Bool { UserDefaults.standard.bool(forKey: consentKey) }
    /// THE CORRESPONDENT'S SWITCH HOLDS BY LEVEL (the author's word 20.10.2026 17:2x UTC: «if the user's checkmark allowing the recording
    /// of a conversation is off, the level decides: lower or equal -- the checkmark holds and no recording happens; if I am level 7 and
    /// the user 6, in the chat and the call with me the recording happens on my side, and on theirs nothing happens»). Their switch is
    /// the one their person sees on Access by level, off below its level. A build that says nothing of it forbids nothing; a forbidding
    /// correspondent whose level or mine is unknown holds.
    static func mayRecord(theirSwitch: Bool?, theirLevel: Int?, mine: Int?) -> Bool {
        guard theirSwitch == false else { return true }
        guard let theirLevel, let mine else { return false }
        return mine > theirLevel
    }
}

/// THE CALL AS THE PERSON SAW IT (the author's word 16.10.2026 15:27 UTC: «the video call must be recorded as I saw it -- now the
/// recording's format is crooked»): the call screen tells the recorder what stands where -- the screen's shape, which picture fills
/// it, where the corner picture stands, whether my picture is mirrored and whether the peer's is a shared screen shown whole -- and
/// the recorder draws exactly that (MTCallTape.seen). Its writers are the screen's own owners (CallUIModel.applySides, MTCallMini).
/// Only short memory operations under its lock.
enum MTCallRecordingLayout {
    struct Shape: Equatable {
        var screen = CGSize(width: 9, height: 16)
        var bigLocal = false
        var mini: CGRect? = nil       // the corner picture in the screen's points, nil while none stands
        var mirrorLocal = true
        var remoteFits = false
    }
    private static let lock = NSLock()
    private static var held = Shape()
    static var now: Shape { lock.withLock { held } }
    static func update(_ change: (inout Shape) -> Void) { lock.withLock { change(&held) } }
}

// Only short memory operations under this lock. No SDK, disk or queue operation runs under it.
// A parked call has a file, but never owns the microphone of the next call.
enum MTCallRecordingGate {
    private static let lock = NSLock()
    private static var holder: UUID?
    private static var held = Set<UUID>()
    private static var muted = Set<UUID>()
    private static var tapes: [UUID: MTCallTape] = [:]
    static func select(_ id: UUID?) { lock.withLock { holder = id } }
    static func release(_ id: UUID) { lock.withLock { if holder == id { holder = nil }; held.remove(id); muted.remove(id) } }
    static func hold(_ id: UUID, _ on: Bool) { lock.withLock { if on { held.insert(id) } else { held.remove(id) } } }
    static func mute(_ id: UUID, _ on: Bool) { lock.withLock { if on { muted.insert(id) } else { muted.remove(id) } } }
    static func add(_ id: UUID, _ tape: MTCallTape) { lock.withLock { tapes[id] = tape } }
    static func remove(_ id: UUID) { lock.withLock { _ = tapes.removeValue(forKey: id) } }
    static func current(local: Bool) -> MTCallTape? {
        lock.withLock {
            guard let id = holder, !held.contains(id), !local || !muted.contains(id) else { return nil }
            return tapes[id]
        }
    }
    static func allows(_ id: UUID) -> Bool { lock.withLock { holder == id && !held.contains(id) && tapes[id] != nil } }
}

// The processing delegates are retained for the factory's lifetime. SDK buffers never escape their callback.
final class MTCallRecordingProcessor: NSObject, RTCAudioCustomProcessingDelegate {
    static let local = MTCallRecordingProcessor(local: true)
    static let remote = MTCallRecordingProcessor(local: false)
    private let local: Bool
    private var rate: Double = 0
    init(local: Bool) { self.local = local }
    func audioProcessingInitialize(sampleRate: Int, channels: Int) { rate = Double(sampleRate) }
    func audioProcessingRelease() { rate = 0 }
    func audioProcessingProcess(audioBuffer: RTCAudioBuffer) {
        guard rate > 0, (1...2).contains(audioBuffer.channels), (1...1920).contains(audioBuffer.frames), let tape = MTCallRecordingGate.current(local: local),
              tape.reserveAudio() else { return }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: AVAudioChannelCount(audioBuffer.channels)),
              let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(audioBuffer.frames)),
              let channels = copy.floatChannelData else { tape.releaseAudio(); return }
        copy.frameLength = copy.frameCapacity
        // The SDK's floating point samples use the Int16 amplitude range; AVFoundation uses -1...1.
        for channel in 0..<audioBuffer.channels {
            let input = audioBuffer.rawBuffer(forChannel: channel)
            for frame in 0..<audioBuffer.frames { channels[channel][frame] = input[frame] / 32768 }
        }
        tape.audio(copy, source: local ? "local" : "remote", at: ProcessInfo.processInfo.systemUptime)
    }
}

struct MTCallTapeManifest: Codable {
    var id: String
    var owner: String
    var chat: String
    var started: Double
    // Missing in older manifests: retain their files without guessing who may publish.
    var sendsToChat: Bool? = nil
    struct File: Codable { var name: String; var source: String }
    var files: [File] = []
    var partial = false
    var stopped = false
    var queued = false
    var output: String?
    var notice = false
    var failureMid: String?
    var unavailableReason: String?
    var localFrames = 0
    var remoteFrames = 0
}

enum MTCallTapeStore {
    static var ids: [String] {
        ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "recording" }.map { $0.deletingPathExtension().lastPathComponent }
    }
    static func load(_ id: String) -> MTCallTapeManifest? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(id + ".recording")),
              let plain = MontanaLocalVault.open(data, Data(id.utf8)) else { return nil }
        return try? JSONDecoder().decode(MTCallTapeManifest.self, from: plain)
    }
    @discardableResult static func save(_ item: MTCallTapeManifest) -> Bool {
        guard let data = try? JSONEncoder().encode(item), let sealed = MontanaLocalVault.seal(data, Data(item.id.utf8)) else { return false }
        do {
            try sealed.write(to: directory.appendingPathComponent(item.id + ".recording"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch { return false }
    }
    static var directory: URL {
        var url = MontanaMediaStore.dir.appendingPathComponent("CallRecordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return url
    }
}

// One serial file writer for a call; bounded inputs never hold the real-time audio callback behind disk I/O.
final class MTCallTape {
    private final class Part {
        let writer: AVAssetWriter
        let input: AVAssetWriterInput
        let adaptor: AVAssetWriterInputPixelBufferAdaptor?
        var end = CMTime.zero
        init(url: URL, video: Bool, size: CGSize) throws {
            writer = try AVAssetWriter(outputURL: url, fileType: .mov)
            writer.movieFragmentInterval = CMTime(seconds: 2, preferredTimescale: 600)
            if video {
                input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height),
                    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 400_000, AVVideoMaxKeyFrameIntervalKey: 20]])
                adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: Int(size.width), kCVPixelBufferHeightKey as String: Int(size.height),
                    kCVPixelBufferIOSurfacePropertiesKey as String: [:]])
            } else {
                input = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 48_000])
                adaptor = nil
            }
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else { throw CocoaError(.fileWriteUnknown) }
            writer.add(input)
            guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
            writer.startSession(atSourceTime: .zero)
        }
    }
    let id: UUID
    private let queue = DispatchQueue(label: "montana.call.recording", qos: .utility)
    // Up to 2.56 seconds of the two 10 ms streams: bounded headroom for a cold system encoder.
    private let audioSlots = DispatchSemaphore(value: 512)
    private let videoSlots = DispatchSemaphore(value: 4)
    private let origin = ProcessInfo.processInfo.systemUptime
    private let offset: Double
    private let pixels = MTCallFramePixels()
    private let ci = CIContext(options: [.cacheIntermediates: false])
    private var item: MTCallTapeManifest
    private var parts: [String: Part] = [:]
    private var refusedParts = Set<String>()
    private var latest: [String: (frame: RTCVideoFrame, at: Double)] = [:]   // the newest frame of each picture, as it came
    private var size = CGSize(width: 360, height: 640)   // the picture's shape, the screen's own, fixed when its file is born
    private var ending = false
    private var firstFailure = false
    private var receivedAudio = false
    private let faultLock = NSLock()
    private var faultQueued = false
    let timeline: MTCallTimeline?
    private let onFailure: () -> Void
    private let onAudio: () -> Void
    init(id: UUID, manifest: MTCallTapeManifest, timeline: MTCallTimeline? = nil,
         onAudio: @escaping () -> Void = {}, onFailure: @escaping () -> Void) {
        self.id = id; item = manifest; offset = max(0, Date().timeIntervalSince1970 - manifest.started)
        self.onFailure = onFailure; self.timeline = timeline
        self.onAudio = onAudio
    }
    func reserveAudio() -> Bool {
        guard audioSlots.wait(timeout: .now()) == .success else { failAsync(); return false }
        return true
    }
    func releaseAudio() { audioSlots.signal() }
    private func failAsync() {
        let first = faultLock.withLock { if faultQueued { return false }; faultQueued = true; return true }
        if first { queue.async { self.fail() } }
    }
    private func fail() {
        item.partial = true
        guard !firstFailure else { return }
        firstFailure = true; _ = MTCallTapeStore.save(item)
        DispatchQueue.main.async(execute: onFailure)
        timeline?.mark("record.partial")
        MontanaLog.event("CALL_RECORD partial")
    }
    private func part(_ source: String, video: Bool) throws -> Part {
        if let p = parts[source] { return p }
        guard !refusedParts.contains(source) else { throw CocoaError(.fileWriteUnknown) }
        let name = UUID().uuidString + ".mov"
        item.files.append(.init(name: name, source: source))
        guard MTCallTapeStore.save(item) else { throw CocoaError(.fileWriteUnknown) }
        timeline?.mark("record.codec.begin", "source=\(source)", operation: source)
        let p: Part
        do { p = try Part(url: MTCallTapeStore.directory.appendingPathComponent(name), video: video, size: size) }
        catch {
            refusedParts.insert(source)
            timeline?.mark("record.codec.fail", "source=\(source)", operation: source)
            throw error
        }
        timeline?.mark("record.codec.ok", "source=\(source)", operation: source)
        parts[source] = p
        return p
    }
    func audio(_ pcm: AVAudioPCMBuffer, source: String, at: Double) {
        queue.async {
            defer { self.audioSlots.signal() }
            guard !self.ending, !self.firstFailure else { return }
            do {
                let p = try self.part(source, video: false)
                let duration = Double(pcm.frameLength) / pcm.format.sampleRate
                let point = CMTime(seconds: max(0, self.offset + at - self.origin - duration), preferredTimescale: 48_000)
                let start = CMTimeMaximum(point, p.end)
                guard p.input.isReadyForMoreMediaData, let sample = Self.sample(pcm, at: start), p.input.append(sample) else {
                    self.fail(); return
                }
                self.timeline?.mark("record.audio.\(source).first", once: true)
                if !self.receivedAudio {
                    self.receivedAudio = true
                    DispatchQueue.main.async(execute: self.onAudio)
                }
                p.end = start + CMTime(seconds: duration, preferredTimescale: 48_000)
                if source == "local" { self.item.localFrames += Int(pcm.frameLength) }
                else { self.item.remoteFrames += Int(pcm.frameLength) }
            } catch { self.fail() }
        }
    }
    static func sample(_ pcm: AVAudioPCMBuffer, at: CMTime) -> CMSampleBuffer? {
        var description: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: pcm.format.streamDescription,
            layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil,
            formatDescriptionOut: &description) == noErr, let description else { return nil }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: CMTimeScale(pcm.format.sampleRate)),
            presentationTimeStamp: at, decodeTimeStamp: .invalid)
        var result: CMSampleBuffer?
        guard CMSampleBufferCreate(allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false,
            makeDataReadyCallback: nil, refcon: nil, formatDescription: description, sampleCount: Int(pcm.frameLength),
            sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil,
            sampleBufferOut: &result) == noErr, let result,
            CMSampleBufferSetDataBufferFromAudioBufferList(result, blockBufferAllocator: kCFAllocatorDefault,
                blockBufferMemoryAllocator: kCFAllocatorDefault, flags: 0, bufferList: pcm.audioBufferList) == noErr else { return nil }
        CMSampleBufferSetDataReady(result)
        return result
    }
    func video(_ frame: RTCVideoFrame, source: String, at: Double) {
        guard videoSlots.wait(timeout: .now()) == .success else { return } // video may shed frames; it never delays voice
        queue.async {
            defer { self.videoSlots.signal() }
            guard !self.ending, !self.firstFailure else { return }
            guard self.latest[source] != nil || self.latest.count < 14 else { return }
            // THE FRAME IS ADMITTED BEFORE IT COSTS ANYTHING (16.10.2026, No.70, the fleet's heat: on the days of their video
            // calls the phones' graphics ran up to 2.2 times their screen time). Every frame of every picture -- thirty a second
            // each -- was turned into pixels and drawn into a thumbnail, and the ten-a-second check after that work threw two of
            // three away: seventy drawings a second for ten frames written. A frame now only takes its source's place; the tenth
            // that is written draws once, from the newest frame of each source.
            self.latest[source] = (frame, at)
            // UNDER THE PHONE'S HEAT THE PICTURE SLOWS AND THE VOICE STAYS (the one owner of the heat's answer, MontanaPower):
            // under pressure one picture a second, at the critical state none -- the file keeps the call's voice whole.
            let floor = MontanaPower.floorNow
            guard floor < 4 else { return }
            let step = floor == 0 ? CMTime(value: 1, timescale: 10) : CMTime(value: 1, timescale: 1)
            do {
                let shape = MTCallRecordingLayout.now
                if self.parts["video"] == nil { self.size = Self.canvas(shape.screen) }   // the file takes the screen's shape at its birth
                let p = try self.part("video", video: true)
                let point = CMTime(seconds: max(0, self.offset + at - self.origin), preferredTimescale: 600)
                guard let adaptor = p.adaptor, let pool = adaptor.pixelBufferPool,
                      point - p.end >= step, p.input.isReadyForMoreMediaData else { return }
                // A stopped camera leaves the picture. The file cannot reveal its last frame through the next call.
                self.latest = self.latest.filter { at - $0.value.at < 1 }
                var images: [String: CIImage] = [:]
                // Only the pictures the screen showed are turned into pixels: a corner nobody saw costs nothing.
                for source in Self.drawn(Set(self.latest.keys), shape: shape) {
                    guard let entry = self.latest[source] else { continue }
                    // One native encoder for the whole call, including a room. A camera never opens another encoder.
                    guard let original = self.pixels.buffer(entry.frame) else { self.fail(); return }
                    let turn = entry.frame.rotation
                    let orientation: Int32 = turn == ._90 ? 6 : turn == ._180 ? 3 : turn == ._270 ? 8 : 1
                    images[source] = CIImage(cvPixelBuffer: original).oriented(forExifOrientation: orientation)
                }
                let canvas = Self.seen(images, shape: shape, size: self.size)
                    .composited(over: CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: self.size)))
                var output: CVPixelBuffer?
                guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &output) == kCVReturnSuccess, let output else { self.fail(); return }
                self.ci.render(canvas, to: output)
                guard adaptor.append(output, withPresentationTime: point) else { self.fail(); return }
                p.end = point
            } catch { self.fail() }
        }
    }
    /// The file's picture has the shape of the screen the person looked at: its long side 640 pixels, the short one by the screen's
    /// proportion, both even for the encoder (a phone's 428x926 screen records at 296x640).
    static func canvas(_ screen: CGSize) -> CGSize {
        let w = max(1, screen.width), h = max(1, screen.height)
        func even(_ v: CGFloat) -> CGFloat { max(2, (v / 2).rounded() * 2) }
        return w <= h ? CGSize(width: even(640 * w / h), height: 640) : CGSize(width: 640, height: even(640 * h / w))
    }
    /// The pictures the screen showed: of a call's two, the big one and the corner one while it stood; a room's, all of them.
    static func drawn(_ have: Set<String>, shape: MTCallRecordingLayout.Shape) -> [String] {
        guard have.isSubset(of: ["video-local", "video-remote"]) else { return have.sorted() }
        let big = shape.bigLocal ? "video-local" : "video-remote", mini = shape.bigLocal ? "video-remote" : "video-local"
        guard have.contains(big) else { return have.contains(mini) ? [mini] : [] }
        return shape.mini != nil && have.contains(mini) ? [big, mini] : [big]
    }
    /// THE CALL AS IT WAS SEEN (the author's word 16.10.2026 15:27 UTC): a call's two pictures are drawn as its screen stood -- the
    /// big one filling the frame (a shared screen whole, on black), the corner one where and as large as it stood, rounded with its
    /// rim, my own mirrored as the screen mirrors it; a room's pictures share the frame in a grid, each filling its cell as its tile.
    static func seen(_ images: [String: CIImage], shape: MTCallRecordingLayout.Shape, size: CGSize) -> CIImage {
        let frame = CGRect(origin: .zero, size: size)
        guard Set(images.keys).isSubset(of: ["video-local", "video-remote"]) else {
            let ordered = images.sorted { a, b in a.key < b.key }
            let columns = ordered.count < 2 ? 1 : Int(ceil(sqrt(Double(ordered.count))))
            let rows = Int(ceil(Double(ordered.count) / Double(columns)))
            let cellW = size.width / CGFloat(columns), cellH = size.height / CGFloat(max(1, rows))
            var out = CIImage.empty()
            for (index, entry) in ordered.enumerated() {
                let cell = CGRect(x: CGFloat(index % columns) * cellW, y: size.height - CGFloat(index / columns + 1) * cellH, width: cellW, height: cellH)
                out = placed(entry.value, in: cell, fit: false, mirror: false).composited(over: out)
            }
            return out
        }
        let bigKey = shape.bigLocal ? "video-local" : "video-remote", miniKey = shape.bigLocal ? "video-remote" : "video-local"
        let bigIsLocal = images[bigKey] != nil ? shape.bigLocal : !shape.bigLocal
        guard let big = images[bigKey] ?? images[miniKey] else { return CIImage.empty() }
        var out = placed(big, in: frame, fit: !bigIsLocal && shape.remoteFits, mirror: bigIsLocal && shape.mirrorLocal)
        if images[bigKey] != nil, let small = images[miniKey], let r = shape.mini, 0 < shape.screen.width, 0 < shape.screen.height {
            let sx = size.width / shape.screen.width, sy = size.height / shape.screen.height
            // The screen counts from its top, the picture from its bottom.
            let box = CGRect(x: r.minX * sx, y: size.height - r.maxY * sy, width: r.width * sx, height: r.height * sy)
            let local = !shape.bigLocal
            let picture = placed(small, in: box, fit: !local && shape.remoteFits, mirror: local && shape.mirrorLocal)
            let radius = 12 * min(sx, sy)
            let rim = rounded(box.insetBy(dx: -1, dy: -1), radius + 1, CIColor(red: 1, green: 1, blue: 1, alpha: 0.25))
            let corner = picture.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: rim,
                                                                                 kCIInputMaskImageKey: rounded(box, radius, .white)])
            out = corner.composited(over: out)
        }
        return out
    }
    /// A picture in its place: filling it and losing its edges, as a camera's picture stands on the screen, or whole inside it.
    private static func placed(_ image: CIImage, in r: CGRect, fit: Bool, mirror: Bool) -> CIImage {
        var img = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        let w = img.extent.width, h = img.extent.height
        guard 0 < w, 0 < h else { return CIImage.empty() }
        if mirror { img = img.transformed(by: CGAffineTransform(scaleX: -1, y: 1).concatenating(CGAffineTransform(translationX: w, y: 0))) }
        let k = fit ? min(r.width / w, r.height / h) : max(r.width / w, r.height / h)
        return img.transformed(by: CGAffineTransform(scaleX: k, y: k)
            .concatenating(CGAffineTransform(translationX: r.midX - w * k / 2, y: r.midY - h * k / 2))).cropped(to: r)
    }
    private static func rounded(_ r: CGRect, _ radius: CGFloat, _ color: CIColor) -> CIImage {
        let made = CIFilter(name: "CIRoundedRectangleGenerator",
                            parameters: ["inputExtent": CIVector(cgRect: r), "inputRadius": radius, "inputColor": color])?.outputImage
        return made ?? CIImage(color: color).cropped(to: r)
    }
    func finish(_ completion: @escaping (MTCallTapeManifest) -> Void) {
        queue.async {
            guard !self.ending else { return }
            self.ending = true
            self.timeline?.mark("record.finish.begin")
            let group = DispatchGroup()
            for p in self.parts.values {
                p.input.markAsFinished(); group.enter()
                p.writer.finishWriting { group.leave() }
            }
            group.notify(queue: self.queue) {
                if self.parts.values.contains(where: { $0.writer.status != .completed }) { self.fail() }
                self.item.stopped = true
                _ = MTCallTapeStore.save(self.item)
                self.timeline?.mark("record.finish.ok", "local_frames=\(self.item.localFrames) remote_frames=\(self.item.remoteFrames)")
                completion(self.item)
            }
        }
    }
}

final class MTCallRecordingVideo: NSObject, RTCVideoRenderer {
    let tape: MTCallTape
    let source: String
    init(_ tape: MTCallTape, source: String) { self.tape = tape; self.source = source }
    func setSize(_ size: CGSize) {}
    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame, MTCallRecordingGate.allows(tape.id) else { return }
        tape.video(frame, source: source, at: ProcessInfo.processInfo.systemUptime)
    }
}

@MainActor final class MTCallRecording: ObservableObject {
    static let shared = MTCallRecording()
    @Published private(set) var recording = Set<UUID>()
    @Published private(set) var failures = Set<UUID>()
    @Published var askConsent = false
    /// THE CALL SCREEN'S OWN MARK (MTCallRecordMark; the author's words 16.10.2026 15:2x UTC: «from level 7 the option of automatic
    /// recording turns on -- below it the person presses it by hand on the call's page if they wish»): the calls the person started by
    /// it, and those they ended by it -- an ended one is not recorded again by itself.
    @Published private(set) var byHand = Set<UUID>()
    @Published private(set) var stoppedByHand = Set<UUID>()
    /// The calls whose correspondent's switch holds against this phone (MTCallRecordingPolicy.mayRecord): recorded neither by
    /// themselves nor by the mark, and the mark is not shown. Their word comes with the offer and the answer, before the call connects.
    @Published private(set) var forbidden = Set<UUID>()
    func forbid(_ uuid: UUID, _ on: Bool) {
        guard on != forbidden.contains(uuid) else { return }
        if on { forbidden.insert(uuid) } else { forbidden.remove(uuid) }
    }
    /// RECORDING BY ITSELF OPENS AT ITS LEVEL (MTLevelAccess.autoRecord): the person's switch, once the level opens it.
    /// Read off the main actor too: the call's caps say it (MontanaCall.myCaps); its inputs are the defaults and the level.
    nonisolated static var automatic: Bool { MTCallRecordingPolicy.enabled && MTLevelAccess.opens(.autoRecord) }
    private struct Active {
        var tape: MTCallTape
        var manifestID: String
        var token: UUID
        var videos: [(RTCVideoTrack, MTCallRecordingVideo)] = []
    }
    private struct Pending { var uuid: UUID; var id: String; var chat: String; var since: Date; var sendsToChat: Bool; var timeline: MTCallTimeline? }
    private var active: [UUID: Active] = [:]
    private var pending: [UUID: Pending] = [:]
    private var exporting = Set<String>()
    private var backlog: [MTCallTapeManifest] = []
    private var recovering = false
    private var closing: [UUID: Bool] = [:]
    private var timelines: [String: MTCallTimeline] = [:]
    private var closed: [UUID: MTCallTapeManifest] = [:]

    func isRecording(_ call: String) -> Bool {
        active.contains { recording.contains($0.key) && $0.value.manifestID == call }
    }

    func begin(uuid: UUID, id: String, chat: String, since: Date, sendsToChat: Bool, timeline: MTCallTimeline? = nil) {
        guard Self.automatic || byHand.contains(uuid), !stoppedByHand.contains(uuid), active[uuid] == nil else { return }
        guard !forbidden.contains(uuid) else { MontanaTrace.markFolded("call_record_held", "the correspondent's switch holds", window: 60); return }
        if closing[uuid] != nil {
            pending[uuid] = Pending(uuid: uuid, id: id, chat: chat, since: since, sendsToChat: sendsToChat, timeline: timeline); return
        }
        closed.removeValue(forKey: uuid)
        // A press of the call's own mark is the person's consent for this call; recording by itself asks once.
        guard MTCallRecordingPolicy.consented || byHand.contains(uuid) else {
            pending[uuid] = Pending(uuid: uuid, id: id, chat: chat, since: since, sendsToChat: sendsToChat, timeline: timeline)
            askConsent = true; return
        }
        guard let owner = MontanaSeed.twin, !owner.isEmpty else { return }
        let previous = MTCallTapeStore.load(id)
        var item = previous ?? MTCallTapeManifest(id: id, owner: owner, chat: chat, started: Date().timeIntervalSince1970)
        guard item.owner == owner, !item.queued else { return }
        // Only the live call can supply a missing role. Recovery never promotes a recording.
        if item.sendsToChat == nil { item.sendsToChat = sendsToChat }
        if previous != nil && !item.stopped && !item.files.isEmpty { item.partial = true }
        item.stopped = false
        item.unavailableReason = nil
        if !item.notice {
            guard let store = ChatStore.live else { return }
            let text = item.sendsToChat == true
                ? String(localized: "This call is being recorded. The recording will be sent to this chat after the call.")
                : String(localized: "This phone is recording the call locally. Only the caller sends a recording to the chat.")
            if MTGroup.isKey(chat) {
                let row = MTGroup.shared.send(text, in: chat, replyText: nil, replyToId: nil, replyWireMid: nil, store: store)
                guard !row.text.isEmpty else { failures.insert(uuid); return }
            } else {
                let mid = ChatStore.mintMid().mid
                let row = Message(text: text, isFromMe: true, time: nowHHMM(), deliveryStatus: .sending, msgId: "mid:" + mid)
                guard store.append(chat, row) else { return }
                MontanaDeliveryEngine.shared.enqueue(to: chat, chat: chat, mid: mid, text: text, silent: false)
            }
            item.notice = true
        }
        guard MTCallTapeStore.save(item) else { failures.insert(uuid); return }
        let token = UUID()
        let tape = MTCallTape(id: uuid, manifest: item, timeline: timeline, onAudio: { [weak self] in
            guard let self, self.active[uuid]?.token == token else { return }
            self.recording.insert(uuid)
        }) { [weak self] in
            guard let self, self.active[uuid]?.token == token else { return }
            self.recording.remove(uuid)
            MTCallRecordingGate.remove(uuid)
            self.failures.insert(uuid)
        }
        timelines[id] = timeline
        timeline?.mark("record.start")
        active[uuid] = Active(tape: tape, manifestID: id, token: token)
        MTCallRecordingGate.add(uuid, tape)
        if item.partial { failures.insert(uuid) }
        MontanaLog.event("CALL_RECORD start call=\(MTCallTimeline.diagnosticToken(uuid.uuidString))")
    }
    func consent(_ allow: Bool) {
        UserDefaults.standard.set(allow, forKey: MTCallRecordingPolicy.consentKey)
        UserDefaults.standard.set(allow, forKey: MTCallRecordingPolicy.key)
        askConsent = false
        let waiting = pending.values; pending = [:]
        if allow {
            for p in waiting { begin(uuid: p.uuid, id: p.id, chat: p.chat, since: p.since, sendsToChat: p.sendsToChat, timeline: p.timeline) }
            MontanaCall.shared.refreshRecording()
            MTGroupRoom.shared.refreshRecording()
        }
    }
    func changed(_ enabled: Bool) {
        if enabled {
            if !MTCallRecordingPolicy.consented { askConsent = true }
            else { MontanaCall.shared.refreshRecording(); MTGroupRoom.shared.refreshRecording() }
        } else {
            pending = [:]; askConsent = false
            for id in Array(active.keys) where !byHand.contains(id) { finish(id, deliver: false) }   // a call started by hand stays the hand's
        }
    }
    /// The call screen's mark pressed: a call not being recorded starts by the person's hand; one being recorded -- by itself or by
    /// hand -- ends, and its recording is delivered as at the call's end.
    func toggleByHand(_ uuid: UUID) {
        if active[uuid] != nil || pending[uuid] != nil {
            stoppedByHand.insert(uuid); byHand.remove(uuid)
            MontanaTrace.mark("call_record_hand", "stop")
            finish(uuid)
        } else if !stoppedByHand.contains(uuid), !forbidden.contains(uuid) {
            byHand.insert(uuid)
            MontanaTrace.mark("call_record_hand", "start level=" + String(MTLevelAccess.level ?? -1))
            MontanaCall.shared.refreshRecording(); MTGroupRoom.shared.refreshRecording()
        }
    }
    func video(_ track: RTCVideoTrack?, uuid: UUID, source: String) {
        guard var entry = active[uuid] else { return }
        if let track, entry.videos.contains(where: { $0.0 === track }) { return }
        let previous = entry.videos.filter { $0.1.source == source }
        entry.videos.removeAll { $0.1.source == source }
        for (old, sink) in previous { old.remove(sink) }
        guard let track else { active[uuid] = entry; return }
        let renderer = MTCallRecordingVideo(entry.tape, source: source)
        entry.videos.append((track, renderer)); active[uuid] = entry
        track.add(renderer)
    }
    func finish(_ uuid: UUID, deliver: Bool = true) {
        pending.removeValue(forKey: uuid)
        if pending.isEmpty { askConsent = false }
        MTCallRecordingGate.remove(uuid)
        recording.remove(uuid); failures.remove(uuid)
        if closing[uuid] != nil { if deliver { closing[uuid] = true }; return }
        guard let entry = active.removeValue(forKey: uuid) else {
            if deliver, let item = closed.removeValue(forKey: uuid) { export(item) }
            return
        }
        closing[uuid] = deliver
        for (track, renderer) in entry.videos { track.remove(renderer) }
        entry.tape.finish { item in Task { @MainActor in
            let deliver = self.closing.removeValue(forKey: uuid) ?? true
            if deliver { self.export(item) }
            else {
                self.closed[uuid] = item
                if Self.automatic || self.byHand.contains(uuid), let p = self.pending.removeValue(forKey: uuid) {
                    self.begin(uuid: p.uuid, id: p.id, chat: p.chat, since: p.since, sendsToChat: p.sendsToChat, timeline: p.timeline)
                    MontanaCall.shared.refreshRecording(); MTGroupRoom.shared.refreshRecording()
                }
            }
        } }
    }
    func recover() {
        guard !recovering, ChatStore.live?.historyLoaded == true, let owner = MontanaSeed.twin else { return }
        recovering = true
        Task {
            defer { recovering = false }
            let items = await Task.detached(priority: .utility) {
                MTCallTapeStore.ids.compactMap(MTCallTapeStore.load).filter { $0.owner == owner && $0.sendsToChat == true && !$0.queued && $0.unavailableReason == nil }
            }.value
            guard MontanaSeed.twin == owner else { return }
            let reserved = Set(active.values.map(\.manifestID)).union(MontanaCall.shared.recordingReservedIDs)
            for var item in items where !reserved.contains(item.id) {
                if !item.stopped { item.stopped = true; item.partial = true; _ = MTCallTapeStore.save(item) }
                export(item)
            }
        }
    }
    private func export(_ item: MTCallTapeManifest) {
        guard item.sendsToChat == true, !item.queued, item.unavailableReason == nil, !exporting.contains(item.id) else { return }
        if !exporting.isEmpty {
            if !backlog.contains(where: { $0.id == item.id }) { backlog.append(item) }
            return
        }
        guard MontanaSeed.twin == item.owner else { return }
        exporting.insert(item.id)
        Task {
            let timeline = timelines[item.id]
            timeline?.mark("record.export.begin")
            let assertion = MTSendAssertion("call-recording")
            defer {
                assertion.end(); exporting.remove(item.id); timelines.removeValue(forKey: item.id)
                backlog.removeAll { $0.owner != MontanaSeed.twin }
                if !backlog.isEmpty { let next = backlog.removeFirst(); export(next) }
            }
            do {
                let result = try await Task.detached(priority: .utility) { try await MTCallTapeExport.run(item) }.value
                guard MontanaSeed.twin == item.owner, let store = ChatStore.live else { return }
                // Identity is checked before the file and its row enter the live person's media store, with no await between.
                let file = result.file, chat = MTSamePair.root(item.chat)
                if result.url != MontanaMediaStore.url(file), !MontanaMediaStore.adopt(from: result.url, name: file) {
                    throw CocoaError(.fileWriteUnknown)
                }
                if result.video { MontanaVideoMark.mark(file) }
                let exists = (store.messages[chat] ?? []).contains { ChatStore.rowMediaFile($0) == file }
                if !exists {
                    let caption = result.partial ? String(localized: "Call recording — incomplete") : String(localized: "Call recording")
                    let row = Message(text: caption, isFromMe: true, time: nowHHMM(),
                        videoFile: result.video ? file : nil, audioFile: result.video ? nil : file, audioDuration: result.duration, deliveryStatus: .sending)
                    guard store.append(chat, row) else { return }
                }
                MontanaMediaSender(store: store).sendMediaOverE2E(fileName: file, kind: result.video ? "vid" : "aud",
                    caption: result.partial ? String(localized: "Call recording — incomplete") : String(localized: "Call recording"), peer: chat, chatKey: chat)
                var done = item; done.queued = true; done.output = file; done.partial = result.partial
                _ = MTCallTapeStore.save(done)
                timeline?.mark("record.export.ok", "video=\(result.video ? 1 : 0) partial=\(result.partial ? 1 : 0)")
                MontanaLog.event("CALL_RECORD queued video=\(result.video ? 1 : 0) partial=\(result.partial ? 1 : 0)")
            } catch {
                let empty = (error as? MTCallTapeExport.Failure) == .noSamples
                let error = error as NSError
                timeline?.mark("record.export.fail", "domain=\(error.domain) code=\(error.code) empty=\(empty ? 1 : 0)")
                MontanaLog.event("CALL_RECORD export.fail domain=\(error.domain) code=\(error.code) empty=\(empty ? 1 : 0)")
                // A failed export is visible in its own chat, once. The files stay local and foreground recovery retries.
                if MontanaSeed.twin == item.owner, let store = ChatStore.live {
                    var failed = MTCallTapeStore.load(item.id) ?? item
                    if empty, failed.unavailableReason == nil { failed.failureMid = nil }
                    if empty { failed.unavailableReason = "no-audio-samples" }
                    let mid = failed.failureMid ?? ChatStore.mintMid().mid
                    failed.failureMid = mid
                    if MTCallTapeStore.save(failed), !(store.messages[item.chat] ?? []).contains(where: { $0.msgId == "mid:" + mid }) {
                        let text = empty
                            ? String(localized: "This call has no recording because no audio was received.")
                            : String(localized: "The call recording could not be saved yet. Montana will try again when you return to the app.")
                        _ = store.append(item.chat, Message(text: text,
                            isFromMe: true, time: nowHHMM(), deliveryStatus: .sent, msgId: "mid:" + mid))
                    }
                }
            }
        }
    }
}

enum MTCallTapeExport {
    enum Failure: Error { case noSamples }
    struct Result { var file: String; var url: URL; var video: Bool; var duration: Double; var partial: Bool }
    static func run(_ item: MTCallTapeManifest) async throws -> Result {
        guard !item.files.isEmpty else { throw Failure.noSamples }
        let composition = AVMutableComposition()
        var videoTracks: [AVCompositionTrack] = []
        var audioParameters: [AVAudioMixInputParameters] = []
        var voiceTracks: [AVCompositionTrack] = []
        var partial = item.partial
        var joined: [String: AVMutableCompositionTrack] = [:]
        for part in item.files {
            let asset = AVURLAsset(url: MTCallTapeStore.directory.appendingPathComponent(part.name))
            do {
                let tracks = try await asset.load(.tracks)
                for original in tracks {
                    let range = try await original.load(.timeRange)
                    guard range.duration > .zero else { continue }
                    let key = part.source + ":" + original.mediaType.rawValue
                    let previous = joined[key]
                    guard let track = previous ?? composition.addMutableTrack(withMediaType: original.mediaType, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
                    joined[key] = track
                    let start = previous == nil ? range.start : CMTimeMaximum(range.start, track.timeRange.end)
                    guard start < range.end else { partial = true; continue }
                    let remaining = CMTimeRange(start: start, end: range.end)
                    try track.insertTimeRange(remaining, of: original, at: start)
                    if previous == nil {
                        if original.mediaType == .video { videoTracks.append(track) }
                        else if original.mediaType == .audio {
                            let volume = AVMutableAudioMixInputParameters(track: track)
                            volume.setVolume(0.5, at: .zero); audioParameters.append(volume); voiceTracks.append(track)
                        }
                    }
                }
            } catch { partial = true }
        }
        guard composition.duration.isNumeric, composition.duration > .zero, !audioParameters.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        let video = !videoTracks.isEmpty
        let file = "call_" + item.id + (video ? ".mp4" : ".m4a")
        let destination = MontanaMediaStore.url(file)
        if FileManager.default.fileExists(atPath: destination.path) {
            let existing = AVURLAsset(url: destination)
            let duration = try await existing.load(.duration)
            guard duration > .zero else { throw CocoaError(.fileReadCorruptFile) }
            return Result(file: file, url: destination, video: video, duration: duration.seconds, partial: partial)
        }
        // THE PICTURE IS NOT ENCODED TWICE (16.10.2026, No.70, the fleet's heat): the call's one video track was written once,
        // at 640x360, by the live writer, and the export drew it again into 960x540 and encoded it a second time on the
        // caller's phone, the whole length of the call, after the call. One track is now copied as it was written and only the
        // voices are mixed and encoded; a copy the system refuses (a resumed part in another format) takes the drawing road.
        if video, videoTracks.count == 1 {
            let copy = MTCallTapeStore.directory.appendingPathComponent(UUID().uuidString + ".mp4")
            if (try? await copyPicture(composition, picture: videoTracks[0], voices: voiceTracks, levels: audioParameters, to: copy)) == true {
                return Result(file: file, url: copy, video: true, duration: composition.duration.seconds, partial: partial)
            }
            try? FileManager.default.removeItem(at: copy)
        }
        guard let export = AVAssetExportSession(asset: composition, presetName: video ? AVAssetExportPreset960x540 : AVAssetExportPresetAppleM4A) else { throw CocoaError(.fileWriteUnknown) }
        let audio = AVMutableAudioMix(); audio.inputParameters = audioParameters; export.audioMix = audio
        if video {
            let instructions = AVMutableVideoCompositionInstruction()
            instructions.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
            instructions.backgroundColor = CGColor(gray: 0, alpha: 1)
            let columns = videoTracks.count == 1 ? 1 : 2
            let rows = Int(ceil(Double(videoTracks.count) / Double(columns)))
            let cellW = 960 / CGFloat(columns), cellH = 540 / CGFloat(rows)
            instructions.layerInstructions = videoTracks.enumerated().map { index, track in
                let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
                let scale = min(cellW / 640, cellH / 360)
                let x = CGFloat(index % columns) * cellW + (cellW - 640 * scale) / 2
                let y = CGFloat(index / columns) * cellH + (cellH - 360 * scale) / 2
                layer.setTransform(CGAffineTransform(scaleX: scale, y: scale).concatenating(CGAffineTransform(translationX: x, y: y)), at: .zero)
                return layer
            }
            let videoComposition = AVMutableVideoComposition()
            videoComposition.renderSize = CGSize(width: 960, height: 540)
            videoComposition.frameDuration = CMTime(value: 1, timescale: 10)
            videoComposition.instructions = [instructions]; export.videoComposition = videoComposition
        }
        // A fresh path on each attempt: a failed native export never overwrites a retained source or finished file.
        let temporary = MTCallTapeStore.directory.appendingPathComponent(UUID().uuidString + (video ? ".mp4" : ".m4a"))
        export.outputURL = temporary; export.outputFileType = video ? .mp4 : .m4a
        await export.export()
        guard export.status == .completed else { throw export.error ?? CocoaError(.fileWriteUnknown) }
        return Result(file: file, url: temporary, video: video, duration: composition.duration.seconds, partial: partial)
    }
    /// The one video track copied sample for sample; the voices mixed once at their levels and encoded once.
    private static func copyPicture(_ composition: AVComposition, picture: AVCompositionTrack, voices: [AVCompositionTrack],
                                    levels: [AVAudioMixInputParameters], to url: URL) async throws -> Bool {
        guard let hint = try await picture.load(.formatDescriptions).first, !voices.isEmpty else { return false }
        let reader = try AVAssetReader(asset: composition)
        let frames = AVAssetReaderTrackOutput(track: picture, outputSettings: nil)
        frames.alwaysCopiesSampleData = false
        let mix = AVMutableAudioMix(); mix.inputParameters = levels
        let sound = AVAssetReaderAudioMixOutput(audioTracks: voices, audioSettings: [AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false, AVLinearPCMIsBigEndianKey: false])
        sound.audioMix = mix
        guard reader.canAdd(frames), reader.canAdd(sound) else { return false }
        reader.add(frames); reader.add(sound)
        let copyWriter = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let framesIn = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: hint)
        let soundIn = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64_000])
        guard copyWriter.canAdd(framesIn), copyWriter.canAdd(soundIn) else { return false }
        copyWriter.add(framesIn); copyWriter.add(soundIn)
        guard reader.startReading(), copyWriter.startWriting() else { return false }
        copyWriter.startSession(atSourceTime: .zero)
        // A lane is touched only on the one serial pump below -- the order the reader and the writer require of these objects.
        final class Lane: @unchecked Sendable {
            let input: AVAssetWriterInput, output: AVAssetReaderOutput
            var finished = false
            init(_ input: AVAssetWriterInput, _ output: AVAssetReaderOutput) { self.input = input; self.output = output }
        }
        let pump = DispatchQueue(label: "montana.call.recording.copy")
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            let group = DispatchGroup()
            for lane in [Lane(framesIn, frames), Lane(soundIn, sound)] {
                group.enter()
                lane.input.requestMediaDataWhenReady(on: pump) {
                    while !lane.finished, lane.input.isReadyForMoreMediaData {
                        guard let sample = lane.output.copyNextSampleBuffer(), lane.input.append(sample) else {
                            lane.finished = true; lane.input.markAsFinished(); group.leave(); return
                        }
                    }
                }
            }
            group.notify(queue: pump) { done.resume() }
        }
        guard reader.status == .completed else { copyWriter.cancelWriting(); return false }
        await copyWriter.finishWriting()
        return copyWriter.status == .completed
    }
}

struct MTCallRecordingConsent: ViewModifier {
    @ObservedObject private var recorder = MTCallRecording.shared
    func body(content: Content) -> some View {
        content.alert("Record calls automatically?", isPresented: $recorder.askConsent) {
            Button("Record calls") { recorder.consent(true) }
            Button("Do not record", role: .cancel) { recorder.consent(false) }
        } message: {
            Text("Audio and video are saved on this phone. For a one-to-one call, the caller sends the recording to the chat, or the one who answered when the caller does not record. Room participants send their own recordings. Participants are notified. You can turn this off in Settings, Access by level, at any time.")
        }
    }
}

/// THE CALL'S RECORD MARK (the author's words 16.10.2026 15:2x UTC: «below level 7 the person presses it by hand on the call's page if
/// they wish»): the call screen's own mark beside the fold, on a call that stands connected -- the record glyph starts this call's
/// recording, the stop glyph ends it; a call ended by it shows it no more.
struct MTCallRecordMark: View {
    let uuid: UUID?
    @ObservedObject private var recorder = MTCallRecording.shared
    var body: some View {
        if let uuid, !recorder.stoppedByHand.contains(uuid), !recorder.forbidden.contains(uuid) {
            let on = recorder.recording.contains(uuid) || recorder.byHand.contains(uuid)
            MontanaCallMark(glyph: on ? "stop.circle" : "record.circle", label: on ? "Stop recording" : "Record") {
                recorder.toggleByHand(uuid)
            }
        }
    }
}

struct MTCallRecordingStatus: View {
    @ObservedObject private var recorder = MTCallRecording.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false
    var body: some View {
        if !recorder.recording.isEmpty {
            Circle().fill(.red).frame(width: 8, height: 8)
                .opacity(reduceMotion || !dimmed ? 1 : 0.25)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.65).repeatForever(autoreverses: true), value: dimmed)
                .onAppear { dimmed = true }
                .accessibilityLabel(Text(recorder.failures.isEmpty ? "Recording" : "Recording interrupted"))
        }
    }
}
