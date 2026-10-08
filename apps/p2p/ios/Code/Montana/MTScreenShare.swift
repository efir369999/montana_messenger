import Foundation
import CoreVideo

// The app side of screen sharing: a loopback TCP socket that the broadcast extension dials when the person starts the
// system broadcast. A loopback port is open to every app on the device, so nobody is taken at the port's word: the
// dialler and the listener prove the call's key to each other before a frame moves (MontanaScreenWire). One listener,
// one proven peer, armed only while a call lives -- outside a call nobody listens and the broadcast refuses to start.
// Frames never leave the device on this leg; outward they ride the standing encrypted video lane of the call. Every
// failure to arm, to prove or to read is named in the trace -- a silent one would read as "the button does nothing".
final class MTScreenShare {
    static let shared = MTScreenShare()

    private let q = DispatchQueue(label: "montana.screenshare")
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var key: Data?
    private var proving = 0          // diallers being proved right now; a crowd is turned away
    private var connFD: Int32 = -1
    private var connGen = 0          // the connection's own name: a reader that ended never lets a younger one go

    var onStart: (() -> Void)?
    var onFrame: ((CVPixelBuffer, UInt32, Int64) -> Void)?   // buffer, CGImagePropertyOrientation raw, pts ns
    var onStop: (() -> Void)?

    func arm() {
        q.async { self.armLocked() }
    }
    private func armLocked() {
        if listenFD >= 0 { return }   // SILENT-OK: already armed — a repeated call-connect is the normal path
        guard let k = MontanaScreenWire.bearKey() else {
            MontanaP2PTrace.mark("call_screen", "arm FAIL the keychain refused the call's key")
            return
        }
        var s: Int32 = -1
        for port in MontanaScreenWire.ports {
            let c = socket(AF_INET, SOCK_STREAM, 0)
            guard c >= 0 else {
                MontanaP2PTrace.mark("call_screen", "arm FAIL socket errno=\(errno)")
                MontanaScreenWire.forgetKey()
                return
            }
            var on: Int32 = 1
            setsockopt(c, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.size))
            var endpoint = MontanaScreenWire.loopback(port)
            let len = socklen_t(MemoryLayout<sockaddr_in>.size)
            let bound = withUnsafePointer(to: &endpoint) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(c, $0, len) }
            }
            if bound == 0, listen(c, 4) == 0 { s = c; break }
            close(c)
        }
        guard s >= 0 else {
            MontanaP2PTrace.mark("call_screen", "arm FAIL all loopback ports busy")
            MontanaScreenWire.forgetKey()
            return
        }
        key = k
        listenFD = s
        let src = DispatchSource.makeReadSource(fileDescriptor: s, queue: q)
        src.setEventHandler { [weak self] in self?.acceptDialler() }
        src.resume()
        acceptSource = src
        MontanaP2PTrace.mark("call_screen", "socket armed")
    }

    // Ends the running broadcast from OUR side: the stop word tells the extension it was the app's
    // choice, and it finishes the system broadcast without an alarm.
    func dropPeer() {
        q.async { self.letGoLocked(.stoppedHere) }
    }

    func disarm() {
        q.async {
            self.letGoLocked(.callEnded, notify: false)
            self.acceptSource?.cancel(); self.acceptSource = nil
            if self.listenFD >= 0 { close(self.listenFD); self.listenFD = -1 }
            self.key = nil
            MontanaScreenWire.forgetKey()
        }
    }

    private func acceptDialler() {
        let c = accept(listenFD, nil, nil)
        guard c >= 0 else {
            MontanaP2PTrace.mark("call_screen", "accept FAIL errno=\(errno)")
            return
        }
        guard let k = key, proving < 2 else {
            close(c)
            MontanaP2PTrace.mark("call_screen", "dialler turned away -- \(key == nil ? "no call key" : "two already proving")")
            return
        }
        var on: Int32 = 1
        setsockopt(c, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        MontanaScreenWire.deadline(c, read: 2, write: 2)   // a dialler that says nothing cannot hold the door
        proving += 1
        DispatchQueue.global(qos: .userInitiated).async {
            let proven = Self.prove(c, key: k)
            self.q.async { self.proving -= 1; self.adopt(c, proven: proven) }
        }
    }

    /// The listener's half of the proof: the dialler's hello and nonce, our nonce and proof, the dialler's proof.
    private static func prove(_ fd: Int32, key: Data) -> Bool {
        guard let hello = MontanaScreenWire.readData(fd, 4 + MontanaScreenWire.nonceSize),
              MontanaScreenWire.u32([UInt8](hello), 0) == MontanaScreenWire.helloMagic else { return false }
        let extNonce = hello.subdata(in: 4..<hello.count)
        let appNonce = MontanaScreenWire.fresh(MontanaScreenWire.nonceSize)
        guard appNonce.count == MontanaScreenWire.nonceSize,
              MontanaScreenWire.writeAll(fd, appNonce + MontanaScreenWire.proof(key, .app, ext: extNonce, app: appNonce)),
              let theirs = MontanaScreenWire.readData(fd, MontanaScreenWire.proofSize) else { return false }
        return MontanaScreenWire.proves(theirs, key, .ext, ext: extNonce, app: appNonce)
    }

    private func adopt(_ c: Int32, proven: Bool) {
        guard proven else {
            close(c)
            MontanaP2PTrace.mark("call_screen", "dialler refused -- it did not prove the call's key")
            return
        }
        guard listenFD >= 0 else {
            close(c)
            MontanaP2PTrace.mark("call_screen", "a proven dialler came after the call")
            return
        }
        // One system broadcast runs at a time: a proven younger one means the older is over.
        if connFD >= 0 { letGoLocked(.replaced, notify: false) }
        MontanaScreenWire.deadline(c, read: 0, write: 2)   // the frames may pause as long as the screen stands still
        connFD = c
        connGen &+= 1
        let gen = connGen
        MontanaP2PTrace.mark("call_screen", "broadcast connected -- the key proven both ways")
        DispatchQueue.main.async { self.onStart?() }
        DispatchQueue.global(qos: .userInitiated).async { self.readLoop(c, gen: gen) }
    }

    /// Lets the running share go (on q): the stop word first, then the socket is shut, which wakes its reader. The
    /// descriptor itself is closed by its reader's end, on this queue (readerEnded): closing it under a blocked reader
    /// freed its number for the next socket, and the old reader's last close then shut a younger connection.
    private func letGoLocked(_ why: MontanaScreenWire.Stop?, notify: Bool = true) {
        guard connFD >= 0 else { return }   // SILENT-OK: nothing was connected — nothing to let go
        if let why {
            var b = why.rawValue
            _ = write(connFD, &b, 1)
        }
        shutdown(connFD, SHUT_RDWR)
        connFD = -1
        MontanaP2PTrace.mark("call_screen", "broadcast disconnected -- \(why.map { "\($0)" } ?? "the extension ended it")")
        if notify { DispatchQueue.main.async { self.onStop?() } }
    }
    private func readerEnded(_ fd: Int32, gen: Int, broke: Bool) {
        if gen == connGen, connFD == fd { letGoLocked(broke ? .streamBroken : nil) }
        close(fd)
        // The extension writes its last lines as it finishes: a moment later they are this app's diary's.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { Self.collectExtensionDiary() }
    }

    /// The broadcast extension's own lines, read into this app's diary: at launch (it may have outlived the previous
    /// run) and a moment after every share ends.
    static func collectExtensionDiary() {
        for line in MontanaScreenWire.takeDiary() { MontanaP2PTrace.mark("call_screen_ext", line) }
    }

    private func readLoop(_ fd: Int32, gen: Int) {
        var frames = 0
        var broke = false
        // The header both sides share: magic, w, h, format, planes, orientation, pts64 (MontanaScreenWire).
        var head = [UInt8](repeating: 0, count: MontanaScreenWire.headerSize)
        while true {
            let ok = head.withUnsafeMutableBytes { MontanaScreenWire.readExact(fd, MontanaScreenWire.headerSize, into: $0.baseAddress!) }
            guard ok else { break }   // EOF: the broadcast ended — reported below with the frame count
            guard MontanaScreenWire.u32(head, 0) == MontanaScreenWire.frameMagic else {
                MontanaP2PTrace.mark("call_screen", "stream FAIL bad magic")
                broke = true; break
            }
            let w = Int(MontanaScreenWire.u32(head, 4)), h = Int(MontanaScreenWire.u32(head, 8))
            let fmt = OSType(MontanaScreenWire.u32(head, 12)), planes = Int(MontanaScreenWire.u32(head, 16))
            let orientation = MontanaScreenWire.u32(head, 20)
            var pts: Int64 = 0
            for i in 0..<8 { pts |= Int64(head[24 + i]) << (8 * i) }
            guard w > 0, h > 0, w <= 4096, h <= 4096, planes >= 1, planes <= 3 else {
                MontanaP2PTrace.mark("call_screen", "stream FAIL bad frame w=\(w) h=\(h) planes=\(planes)")
                broke = true; break
            }
            var planeMeta: [(bpr: Int, ph: Int)] = []
            var planeData: [[UInt8]] = []
            var bad = false
            for _ in 0..<planes {
                var ph8 = [UInt8](repeating: 0, count: 8)
                guard ph8.withUnsafeMutableBytes({ MontanaScreenWire.readExact(fd, 8, into: $0.baseAddress!) }) else { bad = true; break }
                let bpr = Int(MontanaScreenWire.u32(ph8, 0)), ph = Int(MontanaScreenWire.u32(ph8, 4))
                guard bpr > 0, ph > 0, bpr * ph <= 32 * 1024 * 1024 else { bad = true; break }
                var data = [UInt8](repeating: 0, count: bpr * ph)
                guard data.withUnsafeMutableBytes({ MontanaScreenWire.readExact(fd, bpr * ph, into: $0.baseAddress!) }) else { bad = true; break }
                planeMeta.append((bpr, ph)); planeData.append(data)
            }
            if bad {
                MontanaP2PTrace.mark("call_screen", "stream FAIL plane read")
                broke = true; break
            }
            if let pb = Self.makeBuffer(w: w, h: h, fmt: fmt, meta: planeMeta, data: planeData) {
                frames += 1
                if frames == 1 { MontanaP2PTrace.mark("call_screen", "first frame \(w)x\(h) orient=\(orientation)") }
                onFrame?(pb, orientation, pts)
            } else {
                MontanaP2PTrace.mark("call_screen", "stream FAIL buffer make \(w)x\(h) fmt=\(fmt)")
            }
        }
        MontanaP2PTrace.mark("call_screen", "stream ended frames=\(frames)")
        q.async { self.readerEnded(fd, gen: gen, broke: broke) }
    }

    private static func makeBuffer(w: Int, h: Int, fmt: OSType,
                                   meta: [(bpr: Int, ph: Int)], data: [[UInt8]]) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        let attrs: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary]
        guard CVPixelBufferCreate(nil, w, h, fmt, attrs as CFDictionary, &pb) == kCVReturnSuccess,
              let out = pb else { return nil }
        CVPixelBufferLockBaseAddress(out, [])
        defer { CVPixelBufferUnlockBaseAddress(out, []) }
        let planar = CVPixelBufferIsPlanar(out)
        for i in 0..<data.count {
            let dstBpr = planar ? CVPixelBufferGetBytesPerRowOfPlane(out, i) : CVPixelBufferGetBytesPerRow(out)
            let dstH   = planar ? CVPixelBufferGetHeightOfPlane(out, i)      : CVPixelBufferGetHeight(out)
            guard let dst = planar ? CVPixelBufferGetBaseAddressOfPlane(out, i) : CVPixelBufferGetBaseAddress(out) else { return nil }
            let (srcBpr, srcH) = meta[i]
            let rows = min(srcH, dstH)
            let rowBytes = min(srcBpr, dstBpr)
            data[i].withUnsafeBytes { raw in
                guard let src = raw.baseAddress else { return }
                for r in 0..<rows {
                    memcpy(dst + r * dstBpr, src + r * srcBpr, rowBytes)
                }
            }
        }
        return out
    }
}
