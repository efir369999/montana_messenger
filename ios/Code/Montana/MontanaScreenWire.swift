import Foundation
import CryptoKit
import Security

/// THE SCREEN'S LOOPBACK CONTRACT (24.09). The app and its broadcast extension are two processes of one build, joined by a
/// loopback socket -- and a loopback port is open to every app on the device: a stranger listening on the port first would
/// have been handed the screen, a stranger dialling in would have painted the call's picture. Both sides now prove the
/// call's key before a frame moves: the app bears a key for every call it arms and keeps it in the shared keychain, which
/// the extension reads and no other app can; each side answers the other's fresh nonce with a MAC under that key. What both
/// sides must agree on is stated once, here, and both targets compile this file: the ports, the frame header, the proofs,
/// the app's stop words and the extension's diary box.
/// THE RECORDING'S SHELF (the author's words 05.10.2026: a screen recording without a call must land in Photos, not fail; T1 18:15,
/// 2116: the broadcast had no right to Photos of its own and said so). One folder of the app group: the broadcast writes the movie
/// as «.part» and names it «.mov» only when the movie is whole, and the app lays every whole movie into Photos with its own right
/// at its next activation (MTScreenShelfTake); a movie leaves the shelf only when Photos says it holds it.
enum MontanaScreenShelf {
    static var dir: URL? {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: MontanaContour.appGroup) else { return nil }
        let d = base.appendingPathComponent("screen-recordings", isDirectory: true)
        if !FileManager.default.fileExists(atPath: d.path) {
            try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true,
                                                     attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        }
        return d
    }
    /// The whole movies on the shelf, oldest first (a name begins with its second).
    static func movies() -> [URL] {
        guard let d = dir, let found = try? FileManager.default.contentsOfDirectory(at: d, includingPropertiesForKeys: nil) else { return [] }
        return found.filter { u in u.pathExtension == "mov" }.sorted { a, b in a.lastPathComponent < b.lastPathComponent }
    }
}

enum MontanaScreenWire {
    static let ports: [UInt16] = [47021, 47022, 47023]   // the app listens on the first free one; the extension dials them in order
    static let frameMagic: UInt32 = 0x4D54_5343            // 'MTSC'
    static let headerSize = 32                             // magic, w, h, format, planes, orientation, pts64
    static let helloMagic: UInt32 = 0x4D54_4849            // 'MTHI': the extension's first word, then its nonce
    static let nonceSize = 32
    static let proofSize = 32

    private static let keyName = "screen.key"
    private static let diaryName = "screen.diary"

    /// The app's side: a fresh key for the call being armed; nil when the keychain refuses it (then nothing listens).
    static func bearKey() -> Data? {
        let k = fresh(32)
        guard k.count == 32, MontanaKeychain.set(keyName, k) else { return nil }
        return k
    }
    /// The extension's side: the key of the call that stands, if one does.
    static func key() -> Data? { MontanaKeychain.get(keyName).flatMap { $0.count == 32 ? $0 : nil } }
    static func forgetKey() { MontanaKeychain.delete(keyName) }

    static func fresh(_ n: Int) -> Data {
        var b = [UInt8](repeating: 0, count: n)
        return SecRandomCopyBytes(kSecRandomDefault, n, &b) == errSecSuccess ? Data(b) : Data()
    }

    enum Side: String { case app, ext }
    private static func body(_ side: Side, ext: Data, app: Data) -> Data {
        Data(("mt-screen-" + side.rawValue).utf8) + Data([0]) + ext + app
    }
    /// A side's proof: the MAC of both nonces under the call's key, the side named first.
    static func proof(_ key: Data, _ side: Side, ext: Data, app: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: body(side, ext: ext, app: app), using: SymmetricKey(data: key)))
    }
    static func proves(_ got: Data, _ key: Data, _ side: Side, ext: Data, app: Data) -> Bool {
        got.count == proofSize
            && HMAC<SHA256>.isValidAuthenticationCode(got, authenticating: body(side, ext: ext, app: app), using: SymmetricKey(data: key))
    }

    /// Why the app lets a running share go: one byte the app says before it lets go. A share that ends WITHOUT a word
    /// ended because the app is gone -- and the extension says so to the person.
    enum Stop: UInt8 { case callEnded = 1, stoppedHere = 2, streamBroken = 3, replaced = 4 }

    /// THE EXTENSION'S DIARY BOX. The extension keeps no diary of its own and may outlive the app it serves; its lines wait
    /// in the shared keychain until the app reads them into its own diary. The box the app emptied starts anew.
    static func keepDiary(_ lines: [String]) {
        if let d = try? JSONEncoder().encode(lines) { MontanaKeychain.set(diaryName, d) }
    }
    static var diaryTaken: Bool { MontanaKeychain.get(diaryName) == nil }
    static func takeDiary() -> [String] {
        guard let d = MontanaKeychain.get(diaryName) else { return [] }
        MontanaKeychain.delete(diaryName)
        return (try? JSONDecoder().decode([String].self, from: d)) ?? []
    }

    // ── the socket's own words, the same on both sides ──
    static func loopback(_ port: UInt16) -> sockaddr_in {
        var a = sockaddr_in()
        a.sin_family = sa_family_t(AF_INET)
        a.sin_port = port.bigEndian
        a.sin_addr = in_addr(s_addr: UInt32(0x7F00_0001).bigEndian)   // loopback only — nothing off-device
        return a
    }
    /// A socket waits no longer than this for a word, or to hand one over (0: as long as it takes).
    static func deadline(_ fd: Int32, read: Int, write: Int) {
        var r = timeval(tv_sec: read, tv_usec: 0), w = timeval(tv_sec: write, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &r, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &w, socklen_t(MemoryLayout<timeval>.size))
    }
    static func readExact(_ fd: Int32, _ count: Int, into buf: UnsafeMutableRawPointer) -> Bool {
        var got = 0
        while got < count {
            let n = read(fd, buf + got, count - got)
            if n <= 0 { return false }
            got += n
        }
        return true
    }
    static func readData(_ fd: Int32, _ count: Int) -> Data? {
        var d = Data(count: count)
        let ok = d.withUnsafeMutableBytes { raw in raw.baseAddress.map { readExact(fd, count, into: $0) } ?? false }
        return ok ? d : nil
    }
    static func writeAll(_ fd: Int32, _ d: Data) -> Bool {
        var sent = 0
        return d.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
            guard let base = raw.baseAddress else { return false }
            while sent < d.count {
                let n = write(fd, base + sent, d.count - sent)
                if n <= 0 { return false }
                sent += n
            }
            return true
        }
    }
    static func le32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
    static func u32(_ b: [UInt8], _ o: Int) -> UInt32 {
        UInt32(b[o]) | UInt32(b[o+1]) << 8 | UInt32(b[o+2]) << 16 | UInt32(b[o+3]) << 24
    }
}
