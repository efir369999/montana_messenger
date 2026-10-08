import Foundation

/// The path an envelope is allowed to leave by.
///
/// The set says so directly and without options: "Every envelope crosses at least the number of
/// **distinct owners** Canon fixes, and no direct path exists — not as a default, not as a retreat,
/// and not as a choice offered to a person. When fewer distinct owners are reachable, the envelope
/// is not sent: it waits in the sender's queue until the path assembles.»
///
/// And there too is why the check stands here, at the sender: "The check belongs to the sender because
/// the property protects the sender, and no second party verifies it.»
///
/// Owner distinctness is measured NOT by endpoints and not by the number of connections. Every entry
/// point at an introduction gives **its own owner link** -- a value derived from ITS owner's secret
/// together with the secret the two of them share. Two machines of one owner give one sender ONE link,
/// so a fleet does not pass itself off as a crowd. Counting anything else here means counting the wrong
/// value: the number of channels grows with the number of machines, while what protects is the number of owners.
enum MontanaPath {
    /// The Canon's `hop_min`. One place for the whole tree.
    // TEMPORARILY ONE, by the author's decision and for the duration of the live two-phone check. The
    // set fixes three distinct machines of the active set, and that value will return here: while there
    // are fewer than three owners, the path property does not hold, and that is said aloud instead of
    // being hidden behind a green indicator. One machine in a path is ONE carrier, not privacy.
    static let hopMin = 1

    /// How many DISTINCT owners stand among these entry points.
    ///
    /// Only those whose owner link the entry point itself gave at an introduction are counted. Ours,
    /// computed on its behalf, will not do and is worse than nothing: two machines of one owner would
    /// give two different values, the count would grow and the protection would not. A measure must
    /// measure what it names, so an unknown link counts as nothing.
    ///
    /// BOUND-OK: the set lives inside one call and dies with it -- it has nowhere to grow between calls,
    /// and inside it is bounded by the number of entry points passed in.
    static func distinctOwners(among owners: [Data]) -> Int { Set(owners).count }

    /// Whether the path has assembled for the network. Until it has, a letter waits in the sender queue,
    /// and that is a normal state, not a fault: a short path, an automatic fallback and asking the person
    /// "wait or go faster" are forbidden by the set outright.
    static func networkPathAssembled(owners: [Data]) -> Bool { distinctOwners(among: owners) >= hopMin }
}


/// A machine's position in this window -- what it is named by on the wire.
///
/// A machine claim is unchanged between windows, and while a frame was addressed by it, it was exactly
/// what the set calls a direct correlator: "A constant crossing the whole path would be a direct correlator:
/// two hops on the route — or one, when the receiving device is hostile — would bring the ends
/// together by its coincidence". A carrier that saw one and the same value twice joined two ends
/// without breaking anything.
///
/// The window position removes that without breaking the step: it is derived from the claim and the
/// window height, so everyone ACQUAINTED with the machine computes it themselves and recognises it,
/// while an outsider sees thirty-two bytes that differ in the next window and join with nothing. The
/// order holds: a position is a permutation of the same space, and the step to the nearest converges in it the same way.
enum MontanaWindowPos {
    static func of(_ overlay: Data, _ w: UInt64) -> Data {
        MTPipe.domained("mt-pos", [overlay, MTPipe.windowLE(w)])
    }
    /// My position in the accepted windows -- the neighbouring ones too, because clocks drift.
    static func mine(_ overlay: Data, at: Date = Date()) -> Set<Data> {
        Set(MTPipe.windows(at: at).map { of(overlay, $0) })
    }
}
