import Foundation
#if targetEnvironment(macCatalyst)
import ServiceManagement
import os
import Darwin
#endif

@MainActor
enum MTMacVPNService {
    #if targetEnvironment(macCatalyst)
    private static var registration: Task<String?, Never>?
    private static var registeredThisRun = false
    private static var executableWatch: DispatchSourceFileSystemObject?
    static var isAgent: Bool { ProcessInfo.processInfo.arguments.contains("--vpn-supervisor") }

    static func register() async -> String? {
        if let registration { return await registration.value }
        let work = Task<String?, Never> {
            guard let bundleId = Bundle.main.bundleIdentifier else { return String(localized: "Background VPN recovery is unavailable", bundle: MTLanguage.bundle) }
            let service = SMAppService.agent(plistName: bundleId + ".VPNRecovery.plist")
            do {
                if service.status == .enabled, registeredThisRun { return nil }
                if service.status == .requiresApproval {
                    return String(localized: "Allow Montana to run in the background in System Settings", bundle: MTLanguage.bundle)
                }
                // Re-register once per UI process so the service uses this installed executable.
                if service.status == .enabled { try await service.unregister() }
                try service.register()
                registeredThisRun = service.status == .enabled
                if service.status == .requiresApproval { return String(localized: "Allow Montana to run in the background in System Settings", bundle: MTLanguage.bundle) }
                return service.status == .enabled ? nil : String(localized: "Background VPN recovery is unavailable", bundle: MTLanguage.bundle)
            } catch {
                Logger(subsystem: bundleId, category: "vpn-recovery").error("Background registration failed: \((error as NSError).code)")
                return String(localized: "Background VPN recovery is unavailable", bundle: MTLanguage.bundle)
            }
        }
        registration = work
        let result = await work.value
        registration = nil
        // Once launchd owns the approved service, a suspended UI must not hold its lease.
        if result == nil { MTVPNSupervisor.shared.handoffToService() }
        return result
    }

    static func run() {
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "Montana", category: "vpn-recovery").notice("VPN supervisor entered")
        if let executable = Bundle.main.executableURL {
            let fd = open(executable.path, O_EVTONLY | O_CLOEXEC)
            if fd >= 0 {
                let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd,
                    eventMask: [.delete, .rename, .revoke], queue: .main)
                // The old image must not keep supervising after an installer replaces it.
                // launchd restarts the registered bundle program with its throttle interval.
                source.setEventHandler { exit(EXIT_FAILURE) }
                source.setCancelHandler { close(fd) }
                executableWatch = source
                source.resume()
            }
        }
        MTVPNSupervisor.shared.startObserving()
        RunLoop.main.run()
    }
    #else
    static func register() async -> String? { nil }
    #endif
}
