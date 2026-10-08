import Foundation
import Darwin

struct MTVPNRecoveryWindow {
    static let deadline: TimeInterval = 45
    static let interval: TimeInterval = 3
    private var signature: Data?
    private var status: Int?
    private var since: TimeInterval = 0

    mutating func due(requested: Bool, status: Int, signature: Data, now: TimeInterval) -> Bool {
        // NEVPNStatus: invalid=0, disconnected=1, connecting=2, connected=3,
        // reasserting=4, disconnecting=5. An explicit stop is never a stalled start.
        guard requested, [1, 2, 4].contains(status) else { reset(); return false }
        if self.status != status || self.signature != signature {
            self.status = status; self.signature = signature; since = now
        }
        return now - since >= Self.deadline
    }
    mutating func postpone(at now: TimeInterval) { since = now }
    mutating func reset() { status = nil; signature = nil; since = 0 }

    static var now: TimeInterval {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        return Double(mach_continuous_time()) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
    }
}

// The UI and the headless Mac process run the same controller. Only one can own it;
// the kernel releases the lease even when an update terminates its process.
final class MTVPNRecoveryLease {
    private var descriptor: Int32 = -1
    func acquire(at url: URL) -> Bool {
        if descriptor >= 0 { return true }
        let fd = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { return false }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { close(fd); return false }
        descriptor = fd
        return true
    }
    func release() { if descriptor >= 0 { close(descriptor); descriptor = -1 } }
    deinit { release() }
}
