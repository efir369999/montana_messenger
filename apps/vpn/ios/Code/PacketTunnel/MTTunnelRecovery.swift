import Foundation

// The profile is the durable choice. This state only owns one running provider's work.
final class MTTunnelLifetime: @unchecked Sendable {
    private let lock = NSLock()
    private var alive = true
    private var startup: ((Error?) -> Void)?

    init(completion: ((Error?) -> Void)? = nil) { startup = completion }
    var isAlive: Bool { lock.lock(); defer { lock.unlock() }; return alive }

    @discardableResult
    func finish(_ error: Error?) -> Bool {
        lock.lock()
        let reply = alive ? startup : nil
        startup = nil
        lock.unlock()
        reply?(error)
        return reply != nil
    }

    func stop() {
        lock.lock()
        alive = false
        let reply = startup
        startup = nil
        lock.unlock()
        reply?(CancellationError())
    }
}

struct MTTunnelCandidate {
    let row: String
    let host: String
    let outbound: [String: Any]

    init?(_ value: [String: Any]) {
        guard let row = value["row"] as? String,
              let host = value["host"] as? String,
              let encoded = value["xray"] as? String,
              let data = Data(base64Encoded: encoded),
              let outbound = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        self.row = row; self.host = host; self.outbound = outbound
    }
}

struct MTTunnelRetry {
    private(set) var failures = 0
    private(set) var next: TimeInterval = 0
    mutating func failed(at now: TimeInterval) {
        failures = min(failures + 1, 6)
        next = now + min(300, 10 * pow(2, Double(failures - 1)))
    }
    mutating func reset() { failures = 0; next = 0 }
    func ready(at now: TimeInterval) -> Bool { now >= next }
}

/// WHEN A SESSION IS DEAD, AND WHAT IT OWES THE PHONE (29.09: the author's word «let a dead session release itself», and the
/// critic's blind spot «the watch does not tell "the system gives the tunnel nothing" from idleness»). Under the protection
/// of all networks a dead session holds every byte of the phone, so each death is judged by the thing it names:
///  · the road behind the tunnel is dead when bytes go out and none come in -- counted from the first such sample through
///    every raise of the engine and every candidate the recovery tries -- for `upstreamLimit`: the session is released;
///  · the system carries nothing into the tunnel when the app's own path -- the system's word for every app -- has stood
///    unsatisfied for `blockedAfter` while the phone's own network is up: the session is restarted once, and blocked
///    again within `blockedRepeat` of that restart it is released.
/// Zero packets alone is never a verdict: healthy sessions of the fleet stood two to seven minutes without one (29 such
/// stretches in 7365 minutes, measured 29.09), so idleness and a block look the same from inside the tunnel -- only a
/// witness that tried to go out can tell them apart. With the phone's own network down nothing is judged: the tunnel is
/// not what cuts the phone off then.
struct MTTunnelDeath {
    /// Twenty seconds of silence, one raise with its thirty, and forty for the recovery's candidates.
    static let upstreamLimit: TimeInterval = 90
    /// Above the longest block that healed by itself (8 s, T1 27.09 after a profile save) with room for a handover.
    static let blockedAfter: TimeInterval = 20
    /// A fresh session blocked again this soon was not healed by the restart.
    static let blockedRepeat: TimeInterval = 180
    enum Verdict: Equatable { case alive, restart, release(String) }
    private(set) var silentSince: TimeInterval?

    mutating func reset() { silentSince = nil }

    mutating func judge(now: TimeInterval, phonePath: Bool, bytesIn: Bool, bytesOut: Bool,
                        blocked: TimeInterval, lastBlockedRestart: TimeInterval?) -> Verdict {
        guard phonePath else { silentSince = nil; return .alive }
        if bytesIn { silentSince = nil } else if bytesOut, silentSince == nil { silentSince = now }
        if let since = silentSince, Self.upstreamLimit <= now - since { return .release("upstream") }
        guard Self.blockedAfter <= blocked else { return .alive }
        if let at = lastBlockedRestart, now - at < Self.blockedRepeat { return .release("blocked") }
        return .restart
    }
}

/// THE TUNNEL'S LIVING SECONDS (the author's words 04.10.2026 17:13-17:24 MSK: «while the VPN tunnel is on and alive, the same auto
/// minting as in the wallet -- alive it mints, not alive it does not, by the level each second»; «every minting's TimeChain stands
/// by itself: sitting with the VPN is x1, minting with the VPN is x2»). The tunnel is the one witness of its own life, so it alone
/// counts: the stretch from a judge that held it alive to the next judge counts, whatever that next judge says -- the life watch's
/// own word, alive until it says otherwise. The clock runs through sleep and ignores the wall clock's changes; one stretch counts an
/// hour at most. The count outlives the session and the process under its epoch, a name born with it; the app pays what it has not
/// paid of the epoch it knows (MTVPNWallMint) and arms anew at an epoch it does not.
struct MTTunnelAlive {
    static let totalKey = "tunnelAlive.total"
    static let epochKey = "tunnelAlive.epoch"
    static let longest: Double = 3600
    private(set) var total: Double
    private(set) var last: Double?
    init(total: Double) { self.total = max(0, total) }
    static func clock() -> Double { Double(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000 }
    static func epoch() -> String {
        let store = UserDefaults.standard
        if let e = store.string(forKey: epochKey) { return e }
        let e = UUID().uuidString
        store.set(e, forKey: epochKey)
        return e
    }
    mutating func judge(alive: Bool, now: Double) {
        total += stretch(now)
        last = alive ? now : nil
    }
    func told(now: Double) -> Int { Int(total + stretch(now)) }
    private func stretch(_ now: Double) -> Double { last.map { at in min(Self.longest, max(0, now - at)) } ?? 0 }
}
