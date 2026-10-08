import Foundation
import NetworkExtension
import Darwin
import UIKit

// Stage 10 (spec s.3 §4.2, §12.3): app-side control of the built-in VPN tunnel. The app installs a
// NETunnelProviderManager profile pointing at the Montana packet-tunnel extension and starts/stops it.
// The chosen MontanaVPNConfig is passed to the extension via providerConfiguration (Xray outbound JSON).
// Every atom of the flow is written to this module's own log (MontanaVPNLog) so failures are
// diagnosable off-device; the extension's own failure reason is pulled back via fetchLastDisconnectError.
@MainActor
final class MontanaVPNTunnel: ObservableObject {
    static let shared = MontanaVPNTunnel()
    static let extensionBundleId = (Bundle.main.bundleIdentifier ?? "p2p.montana.app") + ".PacketTunnel"   // packet-tunnel extension target

    /// THE LIVING TUNNEL WAKES THE MINTING, HOWEVER IT IS FOUND (T3 05.10.2026 11:30Z): a tunnel standing at the app's launch is
    /// read by load(), not announced by the system, and the beat that pays its seconds (MTVPNWallMint) was woken only by the
    /// announcement -- twelve hours of a living tunnel paid nothing. Every turn to connected, read or announced, wakes it here.
    @Published private(set) var status: NEVPNStatus = .invalid {
        didSet { if status == .connected, oldValue != .connected { MTVPNWallMint.shared.count() } }
    }
    @Published private(set) var activeName: String = ""
    @Published private(set) var lastError: String = ""
    @Published private(set) var backgroundError: String = ""
    /// The chosen row, as the page draws it: spoken by MontanaVPNSelection (the one writer of the choice), read at birth
    /// from the store. A write of the store's dotted key alone never reached the page's observation (25.09).
    @Published private(set) var selectedId: String = UserDefaults.standard.string(forKey: MontanaVPNSelection.key) ?? ""
    func noteSelection(_ id: String) { if selectedId != id { selectedId = id } }
    private var manager: NETunnelProviderManager?
    private var commandGeneration = 0
    @Published private(set) var requested = false
    /// Start of the running session, as a date the native timer label can take. Derived, not stored:
    /// the truth is the monotonic reading below, and this is recomputed from it, so a wall-clock
    /// correction moves the derived date rather than the elapsed time it represents.
    @Published private(set) var connectedAt: Date?

    // The moment the button was pressed, read from the system's continuous clock — the one that keeps
    // counting while the device sleeps. `Date()` is wall-clock and moves when the clock is corrected or
    // the time zone changes; `ProcessInfo.systemUptime` stops during sleep and would have lost the seven
    // and a half minutes this tablet spent asleep. Kept in UserDefaults so an app relaunch cannot lose
    // it — losing it is exactly how the old anchor came to be re-read from the system and re-dated.
    private static let startTicksKey = "mtVPNStartTicks"
    private static let startWallKey  = "mtVPNStartWall"

    private static var nowSeconds: Double {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return Double(mach_continuous_time()) * Double(tb.numer) / Double(tb.denom) / 1_000_000_000
    }

    /// Stamps the press. Called before the tunnel is asked to start, so the count runs from the button
    /// and not from whenever the system finished negotiating.
    private func stampStart() {
        let d = UserDefaults.standard
        d.set(Self.nowSeconds, forKey: Self.startTicksKey)
        d.set(Date().timeIntervalSince1970, forKey: Self.startWallKey)
    }

    private func clearStart() {
        let d = UserDefaults.standard
        d.removeObject(forKey: Self.startTicksKey)
        d.removeObject(forKey: Self.startWallKey)
        connectedAt = nil
    }

    /// Elapsed since the press. Nil when nothing was stamped. A reboot restarts the continuous clock, so
    /// a stamp from before it reads as negative and falls back to the wall-clock copy — after a reboot
    /// the tunnel is down anyway, and this only keeps the arithmetic honest rather than absurd.
    private var elapsedSincePress: TimeInterval? {
        let d = UserDefaults.standard
        guard d.object(forKey: Self.startTicksKey) != nil else { return nil }
        let e = Self.nowSeconds - d.double(forKey: Self.startTicksKey)
        if e >= 0 { return e }
        let wall = d.double(forKey: Self.startWallKey)
        return wall > 0 ? max(0, Date().timeIntervalSince1970 - wall) : nil
    }

    /// Recomputes the date handed to the native label. Called whenever the status moves, so a wall-clock
    /// jump corrects itself on the next transition instead of being baked in for the session.
    private func refreshAnchor() {
        guard let e = elapsedSincePress else { connectedAt = nil; return }
        connectedAt = Date().addingTimeInterval(-e)
    }

    private init() {
        NotificationCenter.default.addObserver(self, selector: #selector(statusChanged),
                                               name: .NEVPNStatusDidChange, object: nil)
        // A move of the reconnect made outside the app is written down as such: the tunnel's own arm and lift
        // (ExtReconnect, its one owner), or the panel's own switch.
        NotificationCenter.default.addObserver(self, selector: #selector(configurationChanged),
                                               name: .NEVPNConfigurationChange, object: nil)
        // Tunnel throughput, every 30 s while the tunnel stands: the app asks its own extension
        // over the native provider message and journals the delta — bytes and packets, nothing else.
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.pollTunnelStats()
        }
    }

    // The VPN keeps its own record and nothing else's. It is a reference client for one job, and a
    // client that writes into the mesh's telemetry has taken a dependency on the mesh to do that job.
    private func tg(_ m: String) { MontanaVPNLog.write(m) }

    // Physical uplink under the tunnel (Wi-Fi en0 / cellular pdp_ip0), read directly so it is the REAL
    // network even when the tunnel's utun holds the default route.
    nonisolated static func physicalLink() -> String {
        var wifi = false, cell = false
        var ifa: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifa) == 0 else { return "?" }
        defer { freeifaddrs(ifa) }
        var p = ifa
        while let c = p {
            let name = String(cString: c.pointee.ifa_name)
            let flags = Int32(c.pointee.ifa_flags)
            let up = (flags & Int32(IFF_UP)) != 0 && (flags & Int32(IFF_RUNNING)) != 0
            let fam = c.pointee.ifa_addr?.pointee.sa_family
            if up, fam == UInt8(AF_INET) || fam == UInt8(AF_INET6) {
                if name == "en0" { wifi = true } else if name.hasPrefix("pdp_ip") { cell = true }
            }
            p = c.pointee.ifa_next
        }
        if wifi && cell { return "Wi-Fi+LTE" }
        return wifi ? "Wi-Fi" : (cell ? "LTE" : "none")
    }
    /// ASK THE DOOR. The measurement belongs to the process that holds the carrier (MIP s 4.5); this
    /// side carries the two things it alone has -- the reflectors and the core's randomness -- and takes
    /// the answer back as atoms on the stats beat. No second road, no second timer.
    // Under a standing tunnel the provider measures a candidate, not the app: it is the one process whose socket dials the
    // outer connection as the tunnel itself will. The provider is the sole
    // process allowed to dial the outer connection: it measures a whole batch through one engine instance (29.09) and
    // answers every row in the batch's order; «busy» for the batch is its word about itself, not the servers' verdict.
    func measureCandidates(_ outbounds: [[String: Any]], stun: String? = nil) async -> [(ms: Int?, err: String?)]? {
        guard isOn else { return nil }
        let all = { (word: String) -> [(ms: Int?, err: String?)] in outbounds.map { _ in (nil, word) } }
        guard status == .connected, let session = manager?.connection as? NETunnelProviderSession,
              let data = try? JSONSerialization.data(withJSONObject: ["outbounds": outbounds, "stun": stun ?? "", "width": MontanaVPNDelay.width]) else {
            return all("unreachable")
        }
        return await withCheckedContinuation { continuation in
            let reply = MTVPNMeasureReply(continuation)
            // The engine bounds the batch at 8 s; this is the road's own last word should the provider never answer.
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 30) { reply.finish(all("timeout")) }
            do {
                try session.sendProviderMessage(Data("probes:".utf8) + data) { data in
                    guard let data, let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        reply.finish(all("unreachable")); return
                    }
                    if let word = value["error"] as? String { reply.finish(all(word)); return }
                    guard let rows = value["answers"] as? [[String: Any]], rows.count == outbounds.count else { reply.finish(all("unreachable")); return }
                    reply.finish(rows.map { row in
                        if let ms = row["ms"] as? Int, 0 <= ms { return (ms, nil) }
                        return (nil, MontanaEngineDelay.classified((row["err"] as? String) ?? "no answer"))
                    })
                }
            } catch { reply.finish(all("unreachable")) }
        }
    }

    /// THE SYSTEM'S WORD FOR EVERY APP, CARRIED TO THE TUNNEL (29.09, the critic's blind spot): the moment this app's own
    /// path went unsatisfied while a tunnel stands. The tunnel sees its own bytes and the phone's own network, never whether
    /// the system lets an app through it; this is the witness it judges a block by (MTTunnelDeath). Written by the path's
    /// observer on its own queue, read on the beat -- a word in memory under the lock and nothing else.
    private nonisolated static let pathLock = NSLock()
    private nonisolated(unsafe) static var blockedSince: TimeInterval?
    nonisolated static func notePath(satisfied: Bool, tunnel: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        pathLock.lock()
        let began = !satisfied && tunnel && blockedSince == nil
        if satisfied || !tunnel { blockedSince = nil } else if blockedSince == nil { blockedSince = now }
        pathLock.unlock()
        if began { Task { @MainActor in shared.quickenWhileBlocked() } }
    }
    nonisolated static var blockedSeconds: Int {
        pathLock.lock(); defer { pathLock.unlock() }
        return blockedSince.map { Int(ProcessInfo.processInfo.systemUptime - $0) } ?? 0
    }
    /// While the system says no under a standing tunnel, the witness is carried every ten seconds, the tunnel's own sample,
    /// not at the next beat of thirty; the quick beat ends with the block.
    private var blockBeat: Task<Void, Never>?
    private func quickenWhileBlocked() {
        guard blockBeat == nil else { return }
        blockBeat = Task { @MainActor [weak self] in
            repeat {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                self?.pollTunnelStats()
            } while !Task.isCancelled && 0 < Self.blockedSeconds
            self?.blockBeat = nil
        }
    }

    private var lastStats: (txb: Int, rxb: Int, at: Date)?
    private func pollTunnelStats() {
        guard status == .connected,
              let session = manager?.connection as? NETunnelProviderSession else { lastStats = nil; return }
        let generation = commandGeneration
        let witness = (try? JSONSerialization.data(withJSONObject: ["blocked_s": Self.blockedSeconds])) ?? Data("{}".utf8)
        try? session.sendProviderMessage(Data("stats:".utf8) + witness) { [weak self] d in
            guard let self, let d,
                  let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
            if self.commandGeneration == generation, let row = o["row"] as? String,
               row != self.selectedId, MontanaVPNStore.load().contains(where: { $0.id == row }) {
                MontanaVPNSelection.adopt(row)
            }
            // THE ROAD BEHIND THE TUNNEL, IN THE APP'S OWN DIARY (25.09): the tunnel's watchdog names an upstream that
            // swallows bytes and returns none (dead_s) and how many times it raised the engine for it (raised); the
            // app writes it beside vpn_stats, so a knock that times out under a standing tunnel has its cause on the
            // same page (the iPhone 15, 22:27-22:38: eleven minutes of node_shut with the tunnel "connected").
            let deadS = o["dead_s"] as? Int ?? 0, raised = o["raised"] as? Int ?? 0
            if deadS > 0 || raised > 0 {
                MontanaP2PTrace.markChanged("vpn_dead", deadS > 0
                    ? "no byte in for \(deadS / 10 * 10)s while bytes go out raised=\(raised)"
                    : "bytes come in again raised=\(raised)")
            }
            guard let txb = o["txb"] as? Int, let rxb = o["rxb"] as? Int else { return }
            defer { self.lastStats = (txb, rxb, Date()) }
            guard let prev = self.lastStats else { return }
            let ms = max(1, Int(Date().timeIntervalSince(prev.at) * 1000))
            let dtx = max(0, txb - prev.txb), drx = max(0, rxb - prev.rxb)
            MontanaP2PTrace.mark("vpn_stats",
                "out_kb=\(txb / 1024) in_kb=\(rxb / 1024) out_kbps=\(dtx * 8 / ms) in_kbps=\(drx * 8 / ms)")
        }
    }

    /// The tunnel's own count of its living seconds, whether it holds itself alive now and the epoch of the count (MTTunnelAlive);
    /// no answer when no session stands or the tunnel cannot tell.
    func askAlive(_ answer: @escaping @MainActor (_ seconds: Int, _ held: Bool, _ epoch: String) -> Void) {
        guard status == .connected, let session = manager?.connection as? NETunnelProviderSession else { return }
        do {
            try session.sendProviderMessage(Data("alive".utf8)) { d in
                guard let d, let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                      let s = o["alive_s"] as? Int, let epoch = o["epoch"] as? String else {
                    let size = d?.count ?? -1
                    Task { @MainActor in MontanaP2PTrace.markFolded("vpn_wall_ask", "the tunnel gave no count bytes=\(size)", window: 60) }
                    return
                }
                let held = o["held"] as? Bool ?? false
                Task { @MainActor in answer(s, held, epoch) }
            }
        } catch {
            MontanaP2PTrace.markFolded("vpn_wall_ask", "the question did not leave code=\((error as NSError).code)", window: 60)
        }
    }

    private func statusName(_ s: NEVPNStatus) -> String {
        switch s {
        case .invalid: return "invalid"; case .disconnected: return "disconnected"
        case .connecting: return "connecting"; case .connected: return "connected"
        case .reasserting: return "reasserting"; case .disconnecting: return "disconnecting"
        @unknown default: return "unknown"
        }
    }

    @objc private func statusChanged() {
        Task { @MainActor in
            guard let s = self.manager?.connection.status else { return }
            let prev = self.status
            self.status = s
            // A CHANGE IS WHAT IS ACTED UPON, NOT A NOTICE (22.09). The system delivers this notification
            // several times for one transition -- measured on T1: four "CONNECTED" lines, four reads of the
            // extension's diary (forty lines each, which is why the VPN record grew from 34 to 60 KB in one
            // session) and four calls to the door probe, three of them answering "busy". The flag inside the
            // probe caught the repeats; the diary caught nothing. One transition, one act.
            guard prev != s else { return }
            let net = Self.physicalLink()
            switch s {
            case .connected:
                // Who brought it up: a press of ours stamps the start; the system (the reconnect, or the switch in
                // its own panel) stamps nothing. After a break, the time the tunnel lay is said with it.
                let byApp = UserDefaults.standard.object(forKey: Self.startTicksKey) != nil
                let gap = self.breakAt.map { " gap=\(Int(Self.nowSeconds - $0))s" } ?? ""
                self.breakAt = nil
                self.ourStop = false
                self.requested = true
                MTVPNSupervisor.shared.interrupt()
                MTVPNWhitelistRoad.shared.tunnelMoved(up: true)
                MontanaP2PTrace.mark("vpn_ui", "tunnel connected net=\(net) after=\(self.elapsedSincePress.map { Int($0 * 1000) } ?? -1)ms by=\(byApp ? "app" : "system")\(gap)")
                // No stamp means this session predates the change (or the app was reinstalled while the
                // tunnel ran): adopt the system's date once and stamp it, after which it stops moving.
                if UserDefaults.standard.object(forKey: Self.startTicksKey) == nil {
                    let d = self.manager?.connection.connectedDate ?? Date()
                    let back = max(0, Date().timeIntervalSince(d))
                    UserDefaults.standard.set(Self.nowSeconds - back, forKey: Self.startTicksKey)
                    UserDefaults.standard.set(d.timeIntervalSince1970, forKey: Self.startWallKey)
                }
                self.askReconnect(why: "up")   // the tunnel arms it as it stands; the app writes only what the platform refused the tunnel
                self.refreshAnchor()
                self.tg("CONNECTED ✅ net=\(net) since=\(self.connectedAt.map { ISO8601DateFormatter().string(from: $0) } ?? "-")")
                // The tunnel is alive and can speak: ask it how the PREVIOUS session ended. A death of
                // this process leaves no line in the app's diary — the reason lives in the extension's
                // own container — so it is carried over here at the first moment there is someone to ask.
                self.fetchTunnelDiary()
            case .disconnected, .invalid:
                let held = self.elapsedSincePress.map { Int($0) }
                let hs = held.map { "\($0 / 3600)h\(($0 % 3600) / 60)m\($0 % 60)s" } ?? "n/a"
                // Ours or not: a stop of this app (the person's off, a switch of server) is chosen; anything else --
                // a death, the network, or the person's off in the system's panel, which this side cannot tell apart
                // (the tunnel's own record names it) -- is written as other, and its moment is kept so the next up
                // says how long the tunnel lay.
                let byApp = self.ourStop
                self.ourStop = false
                if !byApp, prev == .connected || prev == .reasserting || prev == .connecting { self.breakAt = Self.nowSeconds }
                // The reconnect's state is not said here: its owner is the tunnel, which writes its own lift at a stop by
                // the person, and this side's copy goes stale the moment the tunnel writes -- the platform tells the app
                // nothing of the tunnel's saves (T1, 1927: «reconnect=off» at 23:00:10, six seconds after the arm).
                // The app's own recovery names its stop (29.09): «other» is the system's panel or a death, nothing of ours.
                let who = "by=\(byApp ? "app" : (Date().timeIntervalSince(MTVPNRecoveryHooks.lastStopAt) < 90 ? "recovery" : "other"))"
                self.tg("DISCONNECTED ⛔ heldFor=\(hs) net=\(net) prevStatus=\(self.statusName(prev)) \(who)")
                MontanaP2PTrace.mark("vpn_ui", "tunnel down net=\(net) held=\(held ?? -1)s from=\(self.statusName(prev)) \(who)")
                self.clearStart()
                self.fetchDisconnectError()
                await self.refreshRequested()
                MTVPNWhitelistRoad.shared.tunnelMoved(up: false)
                self.readDeadMark()
                self.watchStartup()
            default:
                self.refreshAnchor()
                self.watchStartup()
                self.tg("status -> \(self.statusName(s)) net=\(net)")
                MontanaP2PTrace.mark("vpn_ui", "tunnel \(self.statusName(s)) net=\(net)")
            }
        }
    }

    /// Every profile of ours the system holds, read afresh; a reading that fails throws and is never taken for none.
    private func ourProfiles() async throws -> [NETunnelProviderManager] {
        try await NETunnelProviderManager.loadAllFromPreferences().filter {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == Self.extensionBundleId
        }
    }

    /// ONE PROFILE ON THIS DEVICE (the author's word 30.09): the one whose session stands, else the one switched on, else the
    /// first; a second of ours leaves the Settings list, so the system panel and the app never drive two «Montana» at once.
    private func oneProfile(_ ours: [NETunnelProviderManager]) async -> NETunnelProviderManager? {
        let live: [NEVPNStatus] = [.connected, .connecting, .reasserting, .disconnecting]
        guard let keep = ours.first(where: { live.contains($0.connection.status) }) ?? ours.first(where: { $0.isEnabled }) ?? ours.first
        else { return nil }
        for twin in ours where twin !== keep {
            tg("profile: a second Montana profile leaves -- one profile on this device")
            MontanaP2PTrace.mark("vpn_ui", "profile twin removed of=\(ours.count)")
            try? await twin.removeFromPreferences()
        }
        return keep
    }

    // Load the existing Montana tunnel profile (or nil if none installed yet).
    func load() async {
        // D-4 (16.1.2): reading the profile is not a tunnel event — these lines wrote a pair
        // on every app activation with the tunnel OFF (338 lines of nothing). Status changes
        // and connect/disconnect keep speaking above.
        await inLine {
            // A reading that failed is not an absence: the manager in hand stays, and nothing is decided from a list the
            // system never gave (an empty list read in silence, then a new manager, was the second «Montana» in Settings).
            let ours: [NETunnelProviderManager]
            do { ours = try await self.ourProfiles() }
            catch { self.tg("profiles: the system's reading failed \((error as NSError).domain)#\((error as NSError).code) -- nothing assumed"); return }
            self.manager = await self.oneProfile(ours)
            if let m = self.manager {
                self.status = m.connection.status
                self.armed = m.isOnDemandEnabled
                self.requested = m.isEnabled && m.isOnDemandEnabled
                // The defect this replaces: the anchor lived only in memory, so a relaunch made it nil and
                // this line re-read it from the system — which re-dates a session it re-establishes after
                // the device sleeps. The tablet ran thirty-one minutes and the screen said sixteen.
                if self.status == .connected {
                    if UserDefaults.standard.object(forKey: Self.startTicksKey) == nil,
                       let d = m.connection.connectedDate {
                        let back = max(0, Date().timeIntervalSince(d))
                        UserDefaults.standard.set(Self.nowSeconds - back, forKey: Self.startTicksKey)
                        UserDefaults.standard.set(d.timeIntervalSince1970, forKey: Self.startWallKey)
                    }
                    self.refreshAnchor()
                    // What the extension wrote while this app was away -- a death, a raise by the system -- rides
                    // now, and the tunnel is asked what its reconnect says (after an update the app meets it up).
                    self.fetchTunnelDiary()
                    self.askReconnect(why: "return")
                }
                if self.status == .disconnected || self.status == .invalid { self.clearStart() }
                self.activeName = m.localizedDescription ?? ""
                self.adoptInstalledRow()
                self.watchStartup()
            } else { self.requested = false }
        }
        // Upgrade an already-requested profile once: the recovery version, and the rule that no longer holds every route (30.09:
        // a profile saved before it kept the mesh inside the tunnel until the person's next tap). A saved OFF is never migrated
        // into an ON.
        if requested, let proto = manager?.protocolConfiguration as? NETunnelProviderProtocol,
           (proto.providerConfiguration?["recoveryVersion"] as? Int != 1 || proto.includeAllNetworks),
           let row = MontanaVPNStore.load().first(where: { $0.id == selectedId }) {
            do { try await start(row, preservingRequest: true) }
            catch { tg("recovery profile migration failed: \((error as NSError).code)") }
        }
        // THE VPN RISES AGAIN AFTER AN INSTALL (the author's word 29.09: «an update must not throw the VPN out; it must come up again
        // without conflicts»). The install road's prepare has to stop the tunnel and lift the reconnect before the install (28.09: a
        // tunnel killed by the install held every byte until the system raised it, and the app could not be verified); it leaves its
        // moment behind (MTInstallPrepare.offKey), and the first return of the app after the install raises the chosen row by the
        // ordinary start road: a fresh profile of the new build, saved before the session, never a hot swap under a live one.
        // Never in the prepare's own process (MTInstallPrepare.run reads the tunnel through this load): two installs one after
        // the other would raise the tunnel there only to stop it, and the raise's start would clear the mark the second prepare
        // has to leave behind. A mark that is dropped without a raise says why in the diary: on T1 29.09 seven raises were lost
        // and not one line said so.
        if MTInstallPrepare.offSince != nil, !MTInstallPrepare.asked {
            if !isOn, let row = MontanaVPNStore.load().first(where: { $0.id == selectedId && $0.proto != .unsupported }) {
                tg("raise after install: the install road had switched the tunnel off; raising it again")
                MontanaP2PTrace.mark("vpn_ui", "raise after install row=\(String(row.id.prefix(8)))")
                do { try await start(row) } catch { tg("raise after install failed: \((error as NSError).code)") }
            } else {
                tg("raise after install: nothing to raise -- \(isOn ? "the tunnel already stands" : "no chosen row the engine speaks")")
                MontanaP2PTrace.mark("vpn_ui", "raise after install skipped on=\(isOn ? 1 : 0)")
                MTInstallPrepare.clearOff()
            }
        }
        readDeadMark()   // a dead session released while the app was away is learned at its return (30.09)
    }

    /// The installed profile is a witness, never a writer of the person's choice.  An extension of an
    /// older build may have raised a fallback row; accepting that row here overwrote the one row the
    /// person selected with their hand.
    func adoptInstalledRow() {
        guard let m = manager, let proto = m.protocolConfiguration as? NETunnelProviderProtocol else { return }
        let stored = UserDefaults.standard.string(forKey: MontanaVPNSelection.key) ?? ""
        let installed = proto.providerConfiguration?["row"] as? String ?? ""
        guard !installed.isEmpty, installed != stored else { return }
        MontanaP2PTrace.mark("vpn_ui", "installed row differs from the person's choice; kept=\(String(stored.prefix(8))) installed=\(String(installed.prefix(8)))")
    }

    // Install / update the tunnel profile for the chosen server and enable it. The answer: whether the kernel's rule of the
    // profile (the protection of all networks, the local network left out) changed under the previous profile.
    @discardableResult
    private func install(_ cfg: MontanaVPNConfig, preservingRequest: Bool, byHand: Bool, generation: Int) async throws -> Bool {
        // The transport is named, not only the protocol: a plan mixes tcp and xhttp under one flag, and
        // "vless [ip4]:40001" did not say which of them the session that died had been carrying.
        tg("install: \(cfg.proto.rawValue) \(cfg.network)\(cfg.security == "none" ? "" : " " + cfg.security)\(cfg.flow.isEmpty ? "" : " " + cfg.flow) \(cfg.host):\(cfg.port)")
        // THE ONE PROFILE (the author's word 30.09: «our app always has one profile on this device; if the profile is deleted it
        // offers to create one when the VPN is switched on, when it does not find ours; a duplicate it never creates»). The
        // system is asked afresh -- a manager in hand says nothing of a profile the person deleted, an empty hand nothing of one
        // that stands -- and a failed reading throws here, so nothing is created on it. A profile is born only by the person's
        // hand switching the VPN on, and the system then asks the person to allow it; an automatic raise finds none and stops.
        let found = try await oneProfile(ourProfiles())
        if found == nil, !byHand {
            tg("install: no profile of ours stands; a profile is born only by the person's hand")
            MontanaP2PTrace.mark("vpn_ui", "profile absent -- not created without the hand")
            throw CancellationError()
        }
        let m = found ?? NETunnelProviderManager()
        // The tunnel writes the reconnect into this same configuration (ExtReconnect): a copy read before its write is
        // stale, and the platform refuses to save a stale one (NEVPNErrorConfigurationStale), so it is read again.
        if found != nil { try await m.loadFromPreferences() }
        guard generation == commandGeneration,
              !preservingRequest || (m.isEnabled && m.isOnDemandEnabled) else { throw CancellationError() }
        let before = m.protocolConfiguration as? NETunnelProviderProtocol   // the rule a live session was established under
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = Self.extensionBundleId
        proto.serverAddress = cfg.host
        // Only the Xray outbound the extension needs — no name / description / link in the stored config.
        proto.providerConfiguration = [
            "xray": try JSONSerialization.data(withJSONObject: MontanaXrayConfig.outbound(cfg)).base64EncodedString(),
            "host": cfg.host,
            "recoveryVersion": 1,
            "row": cfg.id   // the row this configuration was made from: the chosen row follows it (adoptInstalledRow)
        ]
        // One installed outbound is one explicitly selected server.  Do not carry a hidden rotation
        // into the extension; it would make a transport recovery change the person's VPN choice.
        proto.providerConfiguration?["fallbacks"] = []
        // THE TUNNEL DOES NOT HOLD EVERY ROUTE (the author's word 30.09, «do it»): the protection of all networks is off, so a
        // socket bound to a physical interface may leave the tunnel -- the call's own adapters, and the mesh once such a binding
        // is measured (a bare interface ban left every node dial without a path, T1 30.09 20:58 MSK).
        proto.includeAllNetworks = false
        proto.disconnectOnSleep = false
        // Kept from the reverted work because it has nothing to do with the switch: the local network
        // stays out of the tunnel: printers, routers and everything else on the local network are
        // reached directly rather than wrapped, which is what a client is expected to do with a LAN.
        proto.excludeLocalNetworks = true
        let ruleChanged = before.map { b in
            b.includeAllNetworks != proto.includeAllNetworks || b.excludeLocalNetworks != proto.excludeLocalNetworks
        } ?? false
        m.protocolConfiguration = proto
        m.localizedDescription = "Montana"     // the config's title in iOS Settings = app name only
        m.isEnabled = true                     // enabled -> the system VPN toggle (Control Center / Settings) drives it
        m.onDemandRules = Self.reconnectRules
        m.isOnDemandEnabled = true
        armed = true
        tg("install: saveToPreferences…")
        do { try await m.saveToPreferences() }
        catch { tg("install: saveToPreferences FAILED \((error as NSError).domain)#\((error as NSError).code) \(error.localizedDescription)"); throw error }
        tg("install: saved; loadFromPreferences")
        try await m.loadFromPreferences()      // re-load so the connection object is valid
        manager = m
        activeName = m.localizedDescription ?? ""
        status = m.connection.status
        MontanaVPNSelection.adopt(cfg.id)   // what is installed is what is chosen
        tg("install: done, status \(statusName(status))\(ruleChanged ? " rule=changed" : "")")
        return ruleChanged
    }

    // The command generation invalidates work suspended at an await when a newer hand arrives.
    func start(_ cfg: MontanaVPNConfig? = nil, preservingRequest: Bool = false, byHand: Bool = false) async throws {
        MTInstallPrepare.clearOff()   // the person raises the tunnel: the install's word on the page is done (29.09)
        MTVPNWhitelistRoad.shared.clear()   // a new start is a new word; the wall's road says its own after its raise
        commandGeneration += 1
        MTVPNSupervisor.shared.interrupt()
        let generation = commandGeneration
        requested = true
        lastError = ""
        ourStop = false
        stampStart()
        var failure: Error?
        await inLine {
            guard generation == self.commandGeneration else { failure = CancellationError(); return }
            do {
                if preservingRequest {
                    guard let m = self.manager else { throw CancellationError() }
                    try await m.loadFromPreferences()
                    guard m.isEnabled, m.isOnDemandEnabled, generation == self.commandGeneration else {
                        throw CancellationError()
                    }
                }
                var ruleChanged = false
                if let cfg { ruleChanged = try await self.install(cfg, preservingRequest: preservingRequest, byHand: byHand, generation: generation) }
                guard generation == self.commandGeneration else { throw CancellationError() }
                guard let m = self.manager, let session = m.connection as? NETunnelProviderSession else {
                    throw NSError(domain: "montana.vpn", code: 1)
                }
                try await m.loadFromPreferences()
                guard generation == self.commandGeneration else { throw CancellationError() }
                // An install already saved ON. A later system-panel OFF must not be overwritten
                // by this continuation or by an automatic server switch.
                if preservingRequest || cfg != nil {
                    guard m.isEnabled, m.isOnDemandEnabled else { throw CancellationError() }
                } else {
                    m.isEnabled = true
                    m.onDemandRules = Self.reconnectRules
                    m.isOnDemandEnabled = true
                    try await m.saveToPreferences()
                    try await m.loadFromPreferences()
                    guard m.isEnabled, m.isOnDemandEnabled else { throw CancellationError() }
                }
                guard generation == self.commandGeneration else { throw CancellationError() }
                self.armed = true
                for _ in 0..<100 where m.connection.status == .disconnecting {
                    try await Task.sleep(nanoseconds: 100_000_000)
                    guard generation == self.commandGeneration else { throw CancellationError() }
                }
                if ruleChanged, [NEVPNStatus.connected, .reasserting, .connecting].contains(m.connection.status) {
                    self.restartForRule(session)
                } else if m.connection.status == .connected || m.connection.status == .reasserting {
                    if let proto = m.protocolConfiguration as? NETunnelProviderProtocol,
                       let config = proto.providerConfiguration,
                       let data = try? JSONSerialization.data(withJSONObject: config) {
                        try session.sendProviderMessage(Data("plan:".utf8) + data) { _ in }
                    }
                } else if m.connection.status != .connecting {
                    try session.startTunnel(options: ["mt.by": "app" as NSString])
                }
                self.tg("start: requested connection saved")
            } catch { failure = error }
        }
        if generation == commandGeneration {
            await refreshRequested()
            watchStartup()
        }
        if let failure { throw failure }
    }

    /// THE KERNEL'S RULE IS NEVER CHANGED UNDER A LIVE SESSION (29.09, the critic, three measurements: T1 27.09 23:58Z, a
    /// tester's phone 28.09 13:42Z, the iPhone 15 28.09 23:40Z). Each was the first launch after an update from a profile
    /// without the protection of all networks; each saved the new profile over the running tunnel and hot-swapped the plan
    /// into it; each phone's path went unsatisfied within 300 ms, the tunnel was handed no packet (pkts=0), and the phone
    /// stood without any network for 8 s, 13 min and 3 min 22 s -- until a hand or chance ended the session. Neither the
    /// tunnel's watch (no bytes out reads as idleness) nor the supervisor (the provider answers «alive») could see it. The
    /// save is the rule's one birth, so the session established under the old rule ends at once, by the provider's own
    /// technical stop that keeps the reconnect armed: the system raises a new session under the saved rule.
    private func restartForRule(_ session: NETunnelProviderSession) {
        ourStop = true
        tg("start: the protection's rule changed under a live session -- the session restarts under the saved rule")
        MontanaP2PTrace.mark("vpn_ui", "restart why=rule-changed")
        do {
            try session.sendProviderMessage(Data("restart".utf8)) { [weak self] reply in
                guard reply != Data([1]) else { return }
                // A provider that did not take the word: the session is ended from this side; the network comes back either way.
                Task { @MainActor in
                    self?.tg("start: the tunnel did not take the restart -- the session is stopped from the app")
                    session.stopTunnel()
                }
            }
        } catch {
            tg("start: the restart could not be asked \((error as NSError).code) -- the session is stopped from the app")
            session.stopTunnel()
        }
    }

    // Keep the interface while changing servers. The provider owns the engine and the fallback.
    func restart(_ cfg: MontanaVPNConfig) async {
        do { try await start(cfg, preservingRequest: true) }
        catch { lastError = error.localizedDescription; tg("server switch failed: \((error as NSError).code)") }
    }

    func stop(why: String = "the person's off") async {
        commandGeneration += 1
        requested = false
        MTVPNWhitelistRoad.shared.clear()
        MTVPNSupervisor.shared.interrupt()
        ourStop = true
        tg("stop: stopTunnel -- \(why)")
        await setOnDemand(false, why: why, stopping: true)
    }

    // On Demand is the durable intent, shared with the system panel. No app preference can re-enable it.
    nonisolated static var reconnectRules: [NEOnDemandRule] {
        let rule = NEOnDemandRuleConnect()
        rule.interfaceTypeMatch = .any
        return [rule]
    }
    private var ourStop = false            // the next down is a stop of ours, not a break
    private var breakAt: Double?           // the moment of the last break, on the continuous clock
    private var armed = false              // the reconnect as last written or read: our own save's echo is no news
    private var reconnectLine: Task<Void, Never>?
    /// Every read and write of the reconnect stands in one line, in order: a save of ours and the reload after
    /// the system's notice never interleave on the one manager object.
    private func inLine(_ work: @escaping @MainActor () async -> Void) async {
        let prior = reconnectLine
        let t = Task { @MainActor in await prior?.value; await work() }
        reconnectLine = t
        await t.value
    }

    /// Serialized profile change before stopping, so an earlier stop cannot overtake a later start.
    private func setOnDemand(_ on: Bool, why: String, stopping: Bool = false) async {
        let generation = commandGeneration
        await inLine {
            defer {
                if stopping { (self.manager?.connection as? NETunnelProviderSession)?.stopTunnel() }
            }
            guard let m = self.manager else { return }
            try? await m.loadFromPreferences()        // the tunnel or the system's panel may have moved it since
            if on, generation != self.commandGeneration || !self.requested || m.connection.status != .connected { return }
            guard m.isOnDemandEnabled != on else { self.armed = on; return }
            if on { m.onDemandRules = Self.reconnectRules }
            m.isOnDemandEnabled = on
            self.armed = on                            // before the save: its echo must read as no news
            do {
                try await m.saveToPreferences()
                try? await m.loadFromPreferences()     // a saved manager answers for its connection again
                self.tg("reconnect: \(on ? "armed" : "lifted") -- \(why)")
                MontanaP2PTrace.mark("vpn_ui", "reconnect \(on ? "armed" : "lifted") why=\(why)")
            } catch {
                self.armed = !on
                let e = error as NSError
                self.tg("reconnect: the \(on ? "arm" : "lift") was not saved \(e.domain)#\(e.code)")
                MontanaP2PTrace.mark("vpn_ui", "reconnect save failed on=\(on) err=\(e.domain)#\(e.code)")
            }
        }
    }

    /// THE RECOVERY'S OWN STOP IS MARKED IN THE PROFILE (29.09): the moment of the stop the app's recovery is about to send,
    /// written into the tunnel's configuration a moment before -- the tunnel's lift reads it and keeps the reconnect standing
    /// (ExtReconnect). The ON/OFF choice is not touched; the write stands in the one line with every other write of the profile.
    func markRecoveryStop() async {
        await inLine {
            guard let m = self.manager else { return }
            try? await m.loadFromPreferences()
            guard let proto = m.protocolConfiguration as? NETunnelProviderProtocol else { return }
            var config = proto.providerConfiguration ?? [:]
            config["recoveryStop"] = Date().timeIntervalSince1970
            proto.providerConfiguration = config
            m.protocolConfiguration = proto
            do { try await m.saveToPreferences(); self.tg("recovery stop: marked in the profile") }
            catch { self.tg("recovery stop: the mark was not saved \((error as NSError).code)") }
        }
    }

    /// The provider reports its saved reconnect state for diagnostics; a late answer cannot enable it.
    private func askReconnect(why: String) {
        guard let session = manager?.connection as? NETunnelProviderSession else { return }
        do {
            try session.sendProviderMessage(Data("reconnect?".utf8)) { [weak self] d in
                let word = d.flatMap { String(data: $0, encoding: .utf8) } ?? "no answer"
                Task { @MainActor in
                    guard let self else { return }
                    self.tg("reconnect: the tunnel says \(word) -- \(why)")
                    MontanaP2PTrace.mark("vpn_ui", "reconnect tunnel=\(word) why=\(why)")
                    // This answer can outlive a system-panel OFF. Only a new explicit start may arm it here.
                }
            }
        } catch {
            let e = error as NSError
            tg("reconnect: the tunnel was not asked \(e.domain)#\(e.code) -- \(why)")
        }
    }

    /// The system's notice that the configuration moved. Our own save echoes here and reads as no news; a move made
    /// outside the app -- the tunnel's own arm and lift, or the panel's own switch -- is written down as such.
    @objc nonisolated private func configurationChanged() {
        Task { @MainActor in
            await self.inLine {
                guard let m = self.manager else { return }
                try? await m.loadFromPreferences()
                let now = m.isOnDemandEnabled
                self.adoptInstalledRow()
                guard now != self.armed || self.requested != (m.isEnabled && now) else { return }
                self.armed = now
                self.requested = m.isEnabled && now
                if !self.requested { self.commandGeneration += 1; MTVPNSupervisor.shared.interrupt() }
                self.tg("reconnect: \(now ? "armed" : "lifted") outside the app")
                MontanaP2PTrace.mark("vpn_ui", "reconnect \(now ? "armed" : "lifted") by=outside the app")
            }
        }
    }

    // Pull the reason the provider (extension) last stopped — this carries the extension-side error
    // (e.g. Xray start failure) back to the app UI without needing to scrape device logs.
    private func fetchDisconnectError(_ then: ((Error?) -> Void)? = nil) {
        guard #available(iOS 16.0, *), let s = manager?.connection as? NETunnelProviderSession else { then?(nil); return }
        s.fetchLastDisconnectError { [weak self] err in
            if let err {
                let e = err as NSError, msg = e.localizedDescription
                Task { @MainActor in
                    // ONE RULE OF WHAT THE PERSON READS (29.09): a technical restart (montana.tunnel 8) keeps the reconnect and
                    // comes back by itself -- written, never shown; a released dead session (montana.tunnel 7) is theirs to
                    // know, in their language; anything else is shown as the platform said it.
                    let ours = e.domain == "montana.tunnel"
                    if !(ours && e.code == 8) {
                        self?.lastError = ours && e.code == 7
                            ? String(localized: "The VPN carried nothing and was turned off", bundle: MTLanguage.bundle) : msg
                    }
                    self?.tg("lastDisconnectError: \(msg)\(ours && e.code == 8 ? " -- a technical restart, not shown" : "")")
                }
            }
            then?(err)
        }
    }

    /// THE TUNNEL'S DEAD MARK (30.09), named once on this side: the tunnel writes it at the release of a dead session and takes it
    /// away at every session's arm (ExtReconnect.deadKey, in the extension's own target).
    static let deadKey = "deadAt"
    /// Read where the VPN stands off -- at the fall, and at every load: the app that slept through the release learns it at its
    /// return. The VPN wall's road decides what rises (MTVPNWhitelistRoad). Never in the install road's prepare, which only stops.
    private func readDeadMark() {
        guard !isOn, !MTInstallPrepare.asked,
              let config = (manager?.protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration,
              let at = config[Self.deadKey] as? Double else { return }
        MTVPNWhitelistRoad.shared.deadMarked(at: at, row: config["row"] as? String ?? "")
    }
    /// The mark as the profile holds it now, read afresh: gone once a session was raised since (its arm takes it away), so the
    /// wall's road raises nothing over a newer choice.
    func deadMarkStands(_ at: Double) async -> Bool {
        var stands = false
        await inLine {
            guard let m = self.manager else { return }
            try? await m.loadFromPreferences()
            stands = (m.protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration?[Self.deadKey] as? Double == at
        }
        return stands
    }

    private func refreshRequested() async {
        await inLine {
            guard let m = self.manager else { self.requested = false; return }
            do { try await m.loadFromPreferences() }
            catch { self.tg("connection choice could not be read"); return }
            self.armed = m.isOnDemandEnabled
            self.requested = m.isEnabled && m.isOnDemandEnabled
            self.status = m.connection.status
        }
    }

    private func watchStartup() {
        MTVPNSupervisor.shared.startObserving()
        guard requested else { return }
        Task { @MainActor in
            self.backgroundError = await MTMacVPNService.register() ?? ""
        }
    }

    nonisolated func foreignTunnelChanged(present: Bool, satisfied: Bool) {
        // A different VPN is a device choice. Montana must never take over after the person turned it off.
        Task { @MainActor in await self.refreshRequested() }
    }

    /// The extension's own record, written into the same diary the app keeps, so a failure of the tunnel
    /// names itself off-device instead of arriving as "an internal error occurred" and nothing else.
    /// ONCE, NOT AT EVERY UP (24.09): the tail used to be written again at every connect -- T1 on 22.09, 1242
    /// lines of which 488 were distinct. Every line of the extension is dated by it; only the lines newer than
    /// the last one carried are written, and the moment of that one is kept.
    private static let extCursorKey = "mt.vpn.extCursor"
    private func fetchTunnelDiary() {
        guard let s = manager?.connection as? NETunnelProviderSession else { return }
        try? s.sendProviderMessage(Data("diary".utf8)) { [weak self] d in
            guard let self, let d, let text = String(data: d, encoding: .utf8), text != "no record" else { return }
            Task { @MainActor in
                let ud = UserDefaults.standard
                let carried = ud.string(forKey: Self.extCursorKey) ?? ""
                var newest = carried
                for line in text.split(separator: "\n") {
                    let at = String(line.prefix(24))            // 2026-09-23T19:11:37.229Z
                    guard at.count == 24, at.hasSuffix("Z"), carried < at else { continue }
                    if newest < at { newest = at }
                    self.tg("[ext] " + line)
                }
                ud.set(newest, forKey: Self.extCursorKey)
            }
        }
    }

    // Remove the profile entirely.
    func remove() async {
        tg("remove: removeFromPreferences")
        try? await manager?.removeFromPreferences()
        manager = nil; status = .invalid; activeName = ""
    }

    var isOn: Bool { requested || status == .connected || status == .connecting || status == .reasserting }
    var connectedDate: Date? { manager?.connection.connectedDate }
    var statusText: String {
        switch status {
        case .connected: return "connected"
        case .connecting: return "connecting…"
        case .disconnecting: return "disconnecting…"
        case .reasserting: return "reconnecting…"
        case .disconnected, .invalid: return requested ? "reconnecting…" : "off"
        @unknown default: return "off"
        }
    }
}

/// THE DEAD ROWS (25.09): a server the tunnel judged dead, or one whose tunnel broke three times in three minutes, is
/// raised by nothing automatic for ten minutes -- not the calls' pick, not the cascade, not the reconnect. A finger on
/// the row clears its mark: the person always outranks the record.
enum MontanaVPNDead {
    private static let key = "mt.vpn.dead"
    static let cooldown: TimeInterval = 600
    private static func table() -> [String: Double] { UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:] }
    static func mark(_ id: String) {
        let now = Date().timeIntervalSince1970
        var t = table().filter { entry in now < entry.value }
        t[id] = now + cooldown
        UserDefaults.standard.set(t, forKey: key)
    }
    static func clear(_ id: String) {
        var t = table()
        t[id] = nil
        UserDefaults.standard.set(t, forKey: key)
    }
    static func isDead(_ id: String) -> Bool { (table()[id] ?? 0) > Date().timeIntervalSince1970 }
}

/// THE VPN WALL'S ROAD UNDER THE PERMITTED LIST (the author's word 30.09: the VPN wall must tell when it stands under the white
/// lists and raise a live node of the wall by itself, if there is one). Under the list only permitted destinations pass and the
/// person's own servers die with the rest; a correspondent's row on the wall may enter through a permitted address. One owner of
/// the raise, woken by one fact -- the tunnel's own dead mark (MontanaVPNTunnel.deadKey), never a guess of this side -- and
/// deciding by one verdict, the line's, measured afresh (MontanaNetProbe.settle). The wall's rows then race as every list
/// A former implementation searched the wall after a dead row. The current rule is stricter: one
/// person chooses one server, and a dead mark may only warn about that row, never select another.
@MainActor final class MTVPNWhitelistRoad: ObservableObject {
    static let shared = MTVPNWhitelistRoad()
    enum Word: Equatable { case manual, noneLive }
    @Published private(set) var word: Word?
    private var walking = false
    private var last: (at: Double, when: Date)?

    /// What the page says under the power, in the person's language, or nil.
    var line: String? {
        switch word {
        case .manual?: return String(localized: "VPN server stopped; choose a live server yourself", bundle: MTLanguage.bundle)
        case .noneLive?: return String(localized: "Whitelists: no live node on the wall", bundle: MTLanguage.bundle)
        case nil: return nil
        }
    }
    func clear() { if word != nil { word = nil } }
    /// A session stood up or fell: the passive warning never outlives a new session.
    func tunnelMoved(up: Bool) {
        if !walking { clear() }
    }

    /// The tunnel's dead mark is a verdict about the selected row, not permission to select another.
    func deadMarked(at: Double, row: String) {
        guard !walking else { return }
        if let last, last.at == at, Date().timeIntervalSince(last.when) < MontanaVPNDead.cooldown { return }
        last = (at, Date())
        if !row.isEmpty { MontanaVPNDead.mark(row) }
        word = .manual
        say("dead selected row; automatic wall selection suppressed")
    }

    private func say(_ m: String) {
        MontanaVPNLog.write("whitelist road: " + m)
        MontanaP2PTrace.mark("vpn_ui", "whitelist " + m)
    }

    private func walk(at: Double, row: String) async {
        deadMarked(at: at, row: row)
    }

    /// The walk still speaks for the tunnel's verdict: the VPN stands off, no hand touched it since the walk began, and the dead
    /// mark is the one the walk began on (a session raised since -- from the app or the system's panel -- took it away).
    private func stands(_ at: Double, since began: Double) async -> Bool {
        let tunnel = MontanaVPNTunnel.shared
        guard !tunnel.isOn, MontanaVPNSelection.handAt < began else { return false }
        return await tunnel.deadMarkStands(at)
    }
}

// Dedicated VPN log: Documents/Montana/Diagnostics/vpn.log — VPN events only, easy to pull for a soak
// test, and paired with the extension's ext.log (which carries the memory samples) by timestamp. Bounded
// on disk (past 512 KB it keeps the last 256 KB) and written straight through, so it never grows RAM.
enum MontanaVPNLog {
    static var url: URL { MontanaLog.url(.vpn) }
    static func write(_ m: String) { MontanaLog.write(.vpn, " [app] " + m) }
}

private final class MTVPNMeasureReply: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<[(ms: Int?, err: String?)]?, Never>?
    init(_ continuation: CheckedContinuation<[(ms: Int?, err: String?)]?, Never>) { self.continuation = continuation }
    func finish(_ rows: [(ms: Int?, err: String?)]) {
        lock.lock(); let reply = continuation; continuation = nil; lock.unlock()
        reply?.resume(returning: rows)
    }
}

/// THE INSTALL ROAD'S PREPARE (28.09; T1 at 17:25, 17:51 and 18:09: «Unable to verify app -- requires a network connection»,
/// standing until the tunnel came up). An install from the build machine kills the tunnel without a stop (the extension's
/// diary: «PREVIOUS SESSION DID NOT STOP CLEANLY», no stopTunnel line), so the reconnect stays armed; the system holds every
/// byte (includeAllNetworks) until it raises the new tunnel, and it raised it 90 s and 337 s after the kill -- the whole
/// time the dialog stood. Nobody alive after the kill can lift the reconnect, so the install road (tools/mt-install-verified.sh)
/// launches this app first with one word in its environment: the app lifts the reconnect, stops the tunnel and leaves.
/// After the install the VPN stands off until the app's first return raises the chosen row again (MontanaVPNTunnel.load; the
/// author's word 29.09: «after a reinstall it must raise the VPN normally», which replaced «do not try to raise it» of 28.09).
enum MTInstallPrepare {
    static let word = "MT_INSTALL_PREPARE"
    static var asked: Bool { !yielded && ProcessInfo.processInfo.environment[word] == "1" }
    /// THE PREPARE LEAVES ITS MOMENT BEHIND (29.09, T1 at 15:08 MSK: the install switched the tunnel off and it stood off for twenty
    /// minutes): the app's first return after the install raises the tunnel again (MontanaVPNTunnel.load). Kept under this
    /// device's own key until the raise.
    static let offKey = "mt.vpn.installOff"
    /// THE PREPARE NEVER LEAVES UNDER THE PERSON'S HANDS (T1 30.09 07:48: a refused step left this task alive, the system froze
    /// the process in the background, and the wait finished at 07:55 under the person, who had opened the app and was playing
    /// music -- the app left by exit(0) in his hands). The task leaves only inside this window and only while nobody holds the
    /// app; a process the person resumed yields the prepare's word and goes on as his app, raising the tunnel it switched off.
    static let window: TimeInterval = 20
    nonisolated(unsafe) private static var yielded = false
    nonisolated(unsafe) private static var slept = false   // the process has been in the background at least once
    static var offSince: Double? {
        let at = UserDefaults.standard.double(forKey: offKey)
        return 0 < at ? at : nil
    }
    static func clearOff() { UserDefaults.standard.removeObject(forKey: offKey) }

    @MainActor static func run() {
        let began = Date()
        // The road launches this app in the foreground, so being active says nothing; what tells the person's hands from
        // the road is a process that went to sleep in the background and woke up later.
        let watch = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                                          object: nil, queue: .main) { _ in slept = true }
        Task { @MainActor in
            let tunnel = MontanaVPNTunnel.shared
            await tunnel.load()   // reads the tunnel; the raise after an install is never asked in this process (MontanaVPNTunnel.load)
            let was = tunnel.status
            await tunnel.stop(why: "the install road's prepare")   // lifts the reconnect first, then stops the tunnel
            // The tunnel's own stop finishes after this process leaves only if the process waits for it: T1 at 15:34Z
            // stood «disconnecting» past five seconds, the road left, and the extension's diary ends without its stop.
            for _ in 0..<150 where tunnel.status != .disconnected && tunnel.status != .invalid {
                if window < Date().timeIntervalSince(began) { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            // THE MARK OUTLIVES THE PROCESS (the author's word 29.09: «after a reinstall it must raise the VPN normally»; T1 29.09:
            // seven prepares with the tunnel up, not one raise at the first return after them). The mark went to the defaults and
            // the process left at once; the defaults write is asynchronous and lost to the exit, while this prepare's line in the
            // file diary arrived every time. The write is waited for before the exit. A mark an earlier install left and no
            // return has raised yet is kept: the tunnel it names is still off, whatever this prepare found.
            let held = offSince != nil
            if !held, was != .disconnected && was != .invalid { UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: offKey) }
            UserDefaults.standard.synchronize()   // the one wait for the defaults database before the leave
            let mark = offSince == nil ? "none" : (held ? "kept" : "set")
            guard Date().timeIntervalSince(began) < window, !slept else {
                NotificationCenter.default.removeObserver(watch)
                yielded = true
                MontanaVPNLog.write("install prepare: the person holds the app; mark=\(mark); staying")
                MontanaP2PTrace.mark("vpn_ui", "install prepare: the person holds the app, staying")
                await tunnel.load()   // the word is yielded, so this load raises the tunnel the prepare switched off
                return
            }
            MontanaVPNLog.write("install prepare: the tunnel was \(was.rawValue), stands \(tunnel.status.rawValue); mark=\(mark); leaving")
            MontanaP2PTrace.mark("vpn_ui", "install prepare: reconnect lifted, tunnel \(tunnel.status.rawValue), mark=\(mark), leaving")
            NotificationCenter.default.removeObserver(watch)
            MontanaLog.drain()   // the road's own lines reach the diary before the process leaves
            // the leave runs no static teardown: the diary is drained and nothing else has to be said
            _exit(0)
        }
    }
}

/// ANY VPN DOUBLES, FOR NOW (the author's word 04.10.2026 18:48 MSK: «for now make it from any VPN, so that the doubling is there»):
/// a VPN raised by another app is a link of the system (utun, ipsec, ppp) under a scoped proxy setting. While Montana's tunnel is
/// down the phone witnesses that link itself (constitution point 6: the phone is a full node) -- a second lives when bytes came in
/// through it within the quiet (MTVPNWallMint.quiet), the rule Montana's tunnel judges its own life by. Nothing of ours runs inside
/// another app's tunnel, so it is read only while the app stands in front.
enum MTForeignVPN {
    private static let kinds = ["utun", "ipsec", "ppp"]
    /// The name of the VPN link standing now, none when no VPN stands.
    static func link() -> String? {
        guard let all = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any],
              let scoped = all["__SCOPED__"] as? [String: Any] else { return nil }
        return scoped.keys.sorted().first { name in kinds.contains { kind in name.hasPrefix(kind) } }
    }
    /// The bytes the link took in since it rose, the platform's own count of it.
    static func bytesIn(_ name: String) -> UInt64? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }
        for p in sequence(first: first, next: { node in node.pointee.ifa_next }) {
            let a = p.pointee
            guard let endpoint = a.ifa_addr, endpoint.pointee.sa_family == UInt8(AF_LINK), String(cString: a.ifa_name) == name,
                  let data = a.ifa_data else { continue }
            return UInt64(data.assumingMemoryBound(to: if_data.self).pointee.ifi_ibytes)
        }
        return nil
    }
}
