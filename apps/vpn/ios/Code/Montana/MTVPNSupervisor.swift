import Foundation
import NetworkExtension
import os

struct MTVPNSnapshot: Equatable {
    let requested: Bool
    let status: NEVPNStatus
    let signature: Data
}

@MainActor
protocol MTVPNRecoveryControl: AnyObject {
    func read() async throws -> MTVPNSnapshot?
    func message(_ word: String) async -> Bool
    func stop()
    func start() throws
}

/// THE RECOVERY'S HOOKS INTO THE APP (29.09). This file is compiled on its own by its guard, so the call's word and the
/// diary reach it through hooks the app's wiring sets: a recovery never raises a tunnel under a live call, and it marks its
/// own stop a moment before it stops -- the tunnel reads the mark and keeps the reconnect standing (PacketTunnelProvider).
enum MTVPNRecoveryHooks {
    static var callBusy: () -> Bool = { false }
    static var diary: (String) -> Void = { _ in }
    static var lastStopAt = Date.distantPast
    /// The mark of a technical stop, written into the tunnel's own profile by its owner (MontanaVPNTunnel.markRecoveryStop)
    /// and read by the tunnel's lift (ExtReconnect). This file writes no preference itself, by its guard.
    static var markStop: () async -> Void = {}
}

@MainActor
final class MTVPNSupervisor {
    static let shared = MTVPNSupervisor(control: MTVPNSystemControl())
    private let control: MTVPNRecoveryControl
    private let sleep: (TimeInterval) async throws -> Void
    private let now: () -> TimeInterval
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Montana", category: "vpn-recovery")
    private var window = MTVPNRecoveryWindow()
    private var generation = 0
    private var task: Task<Void, Never>?
    private var pause: Task<Void, Never>?
    private var notices: [NSObjectProtocol] = []
    private var interval = MTVPNRecoveryWindow.deadline
    private let lease = MTVPNRecoveryLease()

    init(control: MTVPNRecoveryControl, now: @escaping () -> TimeInterval = { MTVPNRecoveryWindow.now },
         sleep: @escaping (TimeInterval) async throws -> Void = {
             try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000))
         }) {
        self.control = control; self.now = now; self.sleep = sleep
    }

    func startObserving() {
        guard task == nil else { wake(); return }
        for name in [Notification.Name.NEVPNStatusDidChange, .NEVPNConfigurationChange] {
            notices.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.wake() }
            })
        }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.ownsRecovery() { await self.step() }
                let duration = self.interval
                self.pause = Task { try? await self.sleep(duration) }
                await self.pause?.value
            }
        }
    }

    func interrupt() { generation += 1; window.reset(); wake() }

    func handoffToService() {
        interrupt()
        task?.cancel(); task = nil
        pause?.cancel(); pause = nil
        for notice in notices { NotificationCenter.default.removeObserver(notice) }
        notices.removeAll()
        lease.release()
    }

    private func wake() { interval = MTVPNRecoveryWindow.interval; pause?.cancel() }

    private func ownsRecovery() -> Bool {
        #if targetEnvironment(macCatalyst)
        do {
            let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
            return lease.acquire(at: folder.appendingPathComponent("vpn-recovery.lock"))
        } catch {
            log.error("Recovery lease unavailable") // NOT-UI: system diagnostics only
            return false
        }
        #else
        return true
        #endif
    }

    func step() async {
        let turn = generation
        do {
            let read = try await control.read()
            guard turn == generation, !Task.isCancelled else { return }
            guard let snapshot = read else {
                window.reset(); interval = MTVPNRecoveryWindow.deadline; return
            }
            interval = snapshot.requested && [.connecting, .reasserting, .disconnected].contains(snapshot.status)
                ? MTVPNRecoveryWindow.interval : MTVPNRecoveryWindow.deadline
            guard window.due(requested: snapshot.requested, status: snapshot.status.rawValue,
                             signature: snapshot.signature, now: now()) else { return }
            defer { window.postpone(at: now()) }
            if snapshot.status != .disconnected {
                if await control.message("health") { return }
                guard try await stillCurrent(snapshot, turn: turn) else { return }
                // A provider that can answer performs a technical stop, preserving On Demand.
                if await control.message("restart") { return }
                guard try await stillCurrent(snapshot, turn: turn) else { return }
                log.notice("Unresponsive VPN startup: requesting a serialized stop") // NOT-UI: system diagnostics only
                // THE STOP IS MARKED BEFORE IT IS SENT (29.09, T1 28.09: nine such stops in a day, each read by the tunnel as
                // the person's off, each lifting the reconnect -- and this very recovery could not raise what it had stopped,
                // since it asks for a standing reconnect; the tunnel lay until a finger). A fresh mark keeps the reconnect.
                MTVPNRecoveryHooks.lastStopAt = Date()
                await MTVPNRecoveryHooks.markStop()
                MTVPNRecoveryHooks.diary("recovery stop: the tunnel answered neither health nor restart")
                control.stop()
                let until = now() + MTVPNRecoveryWindow.deadline
                while now() < until {
                    try await sleep(MTVPNRecoveryWindow.interval)
                    guard turn == generation, !Task.isCancelled,
                          let current = try await control.read(), current.requested,
                          current.signature == snapshot.signature else { return }
                    if current.status == .disconnected { break }
                    // On Demand may already have started the replacement. Never stop it twice.
                    if current.status != .disconnecting && current.status != snapshot.status { return }
                }
            }
            guard turn == generation, !Task.isCancelled,
                  let current = try await control.read(), current.requested,
                  current.signature == snapshot.signature, current.status == .disconnected else { return }
            // No preference write here: a saved OFF always wins over an automatic retry.
            try control.start()
            log.notice("Requested VPN restart submitted to the system") // NOT-UI: system diagnostics only
        } catch {
            window.postpone(at: now())
            log.error("VPN recovery operation failed: \((error as NSError).code)")
        }
    }

    private func stillCurrent(_ snapshot: MTVPNSnapshot, turn: Int) async throws -> Bool {
        guard turn == generation, !Task.isCancelled else { return false }
        let current = try await control.read()
        return turn == generation && !Task.isCancelled && current == snapshot && current?.requested == true
    }
}

@MainActor
private final class MTVPNSystemControl: MTVPNRecoveryControl {
    private var manager: NETunnelProviderManager?
    private var providerId: String { (Bundle.main.bundleIdentifier ?? "") + ".PacketTunnel" }

    func read() async throws -> MTVPNSnapshot? {
        let result: Result<[NETunnelProviderManager], Error> = await withCheckedContinuation { continuation in
            let reply = MTVPNRecoveryReply(continuation)
            reply.expire(with: .failure(NSError(domain: "montana.vpn.recovery", code: 1)))
            NETunnelProviderManager.loadAllFromPreferences { managers, error in
                if let error { reply.finish(.failure(error)) }
                else { reply.finish(.success(managers ?? [])) }
            }
        }
        manager = try result.get().first {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == providerId
        }
        guard let manager, let proto = manager.protocolConfiguration as? NETunnelProviderProtocol else { return nil }
        var config = proto.providerConfiguration ?? [:]
        config["recoveryStop"] = nil   // the mark of this recovery's own stop is no change of the profile
        config["deadAt"] = nil         // nor the mark the tunnel leaves at the release of a dead session (ExtReconnect.deadKey)
        let signature = try JSONSerialization.data(withJSONObject: config, options: [.sortedKeys])
        return MTVPNSnapshot(requested: manager.isEnabled && manager.isOnDemandEnabled,
                             status: manager.connection.status, signature: signature)
    }

    func message(_ word: String) async -> Bool {
        guard let session = manager?.connection as? NETunnelProviderSession else { return false }
        return await withCheckedContinuation { continuation in
            let reply = MTVPNRecoveryReply(continuation)
            reply.expire(with: false)
            do { try session.sendProviderMessage(Data(word.utf8)) { reply.finish($0 == Data([1])) } }
            catch { reply.finish(false) }
        }
    }
    func stop() { (manager?.connection as? NETunnelProviderSession)?.stopTunnel() }
    func start() throws {
        // NO ROAD CHANGES UNDER A CALL (29.09): a tunnel raised in the middle of a call takes every route with it
        // (includeAllNetworks), and the call's pairs die under the person. The recovery waits for the call to end.
        guard !MTVPNRecoveryHooks.callBusy() else { MTVPNRecoveryHooks.diary("recovery start held -- a call stands"); return }
        guard let manager, manager.isEnabled, manager.isOnDemandEnabled,
              manager.connection.status == .disconnected,
              let session = manager.connection as? NETunnelProviderSession else { return }
        try session.startTunnel(options: ["mt.by": "supervisor" as NSString])
    }
}

private final class MTVPNRecoveryReply<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?
    init(_ continuation: CheckedContinuation<Value, Never>) { self.continuation = continuation }
    func finish(_ value: Value) {
        lock.lock(); let reply = continuation; continuation = nil; lock.unlock()
        reply?.resume(returning: value)
    }
    func expire(with value: Value) {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + MTVPNRecoveryWindow.interval) {
            self.finish(value)
        }
    }
}
