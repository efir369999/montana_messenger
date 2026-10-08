import Foundation

/// A rendezvous for a call.
///
/// Neither side has an address, so neither can be dialled. What both of them CAN do is compute the
/// same value: the tag of their pipe for the current window, which stands on the secret only the
/// two of them hold. Each side deposits its readiness at that tag and looks for the other there;
/// the machine that both reached joins the pipe. Nobody is asked where anyone is.
enum MontanaRendezvous {

    /// One window of a rendezvous — the same length the set gives a tag, and the same one value:
    /// it is stated in MTPipe and read from there, never copied.
    static func window(_ at: Date = Date()) -> UInt64 { MTPipe.window(at) }

    /// Where both sides look for each other in this window. Derived, never asked for: the tag comes
    /// from the secret of their channel, so a third party computing it would already hold that secret.
    static func point(with ref: String, at: Date = Date()) -> Data? {
        guard let shared = MontanaDirect.shared.channelSecret(with: ref) else { return nil }
        return MTPipe.tag(sharedSecret: shared, window: window(at))
    }

    /// Clocks drift, so a side looks at the neighbouring windows too — the same tolerance a tag has.
    static func points(with ref: String, at: Date = Date()) -> [Data] {
        guard let shared = MontanaDirect.shared.channelSecret(with: ref) else { return [] }
        return MTPipe.windows(at: at).map { MTPipe.tag(sharedSecret: shared, window: $0) }
    }

    /// The machine that holds this window's point: the least commitment standing above the tag, and
    /// the lowest of all when none stands above it. A ring, so a rendezvous never has no holder.
    static func holder(of point: Data, among machines: [Data]) -> Data? {
        MTPipe.holder(of: point, among: machines)
    }
}
