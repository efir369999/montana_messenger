//! Stage 8 -- path-selection arbiter (direct vs relay). Reachability classification is
//! the result of libp2p AutoNAT v2 + Identify observed-address; selection rule (§6):
//! a direct path is possible when at least one end is behind a non-symmetric NAT (home
//! Wi-Fi / IPv6); double symmetric CGNAT -> relay via the postman (Stage 1).
//! DCUtR hole-punching and AutoNAT probing are libp2p machinery on top of this decision;
//! the stage introduces no wire formats of its own.

/// Reachability class of a node (result of AutoNAT v2 + Identify observed-address).
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum NatClass {
    /// Reachability undetermined -- AutoNAT has not finished probing yet.
    Unknown,
    /// Public address (IPv4 without NAT / IPv6 global) -- direct dial-in.
    Public,
    /// Cone NAT (full / restricted / port-restricted) -- DCUtR hole-punch works.
    Cone,
    /// Symmetric NAT (CGNAT) -- the external port is unpredictable, hole-punch is practically impossible.
    Symmetric,
}

impl NatClass {
    /// Whether the end can take part in a direct hole-punch (non-symmetric and determined).
    pub fn punchable(&self) -> bool {
        matches!(self, NatClass::Public | NatClass::Cone)
    }
}

/// Connection path selection.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum PathChoice {
    /// Direct connection (DCUtR hole-punch / public dial); the postman is out of the loop.
    Direct,
    /// Relay via the postman (Stage 1) -- direct hole-punching is unreachable.
    Relay,
}

/// Arbiter §6: a direct path is reachable when at least one end is non-symmetric.
/// Double symmetric CGNAT -> relay. Unknown is conservatively not treated as punchable
/// (we do not risk direct until AutoNAT has confirmed reachability of at least one end).
pub fn select_path(local: NatClass, peer: NatClass) -> PathChoice {
    if local.punchable() || peer.punchable() {
        PathChoice::Direct
    } else {
        PathChoice::Relay
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn punchable_matrix() {
        assert!(NatClass::Public.punchable());
        assert!(NatClass::Cone.punchable());
        assert!(!NatClass::Symmetric.punchable());
        assert!(!NatClass::Unknown.punchable());
    }

    #[test]
    fn direct_when_one_end_punchable() {
        assert_eq!(
            select_path(NatClass::Public, NatClass::Symmetric),
            PathChoice::Direct
        );
        assert_eq!(
            select_path(NatClass::Symmetric, NatClass::Cone),
            PathChoice::Direct
        );
        assert_eq!(
            select_path(NatClass::Public, NatClass::Public),
            PathChoice::Direct
        );
        assert_eq!(
            select_path(NatClass::Unknown, NatClass::Public),
            PathChoice::Direct
        );
    }

    #[test]
    fn relay_on_double_symmetric_cgnat() {
        // Two pockets on a cellular network -- direct hole-punching is practically impossible (§6).
        assert_eq!(
            select_path(NatClass::Symmetric, NatClass::Symmetric),
            PathChoice::Relay
        );
    }

    #[test]
    fn relay_when_unknown_unresolved() {
        assert_eq!(
            select_path(NatClass::Unknown, NatClass::Unknown),
            PathChoice::Relay
        );
        assert_eq!(
            select_path(NatClass::Unknown, NatClass::Symmetric),
            PathChoice::Relay
        );
    }
}
