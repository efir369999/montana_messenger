// spec, раздел "Сетевой уровень → NAT Traversal"
//
// Operator choice триада (не default+fallback):
//   (a) UPnP/PCP — стандартный port mapping request
//   (b) AutoNAT detection + hole punching через rendezvous peer
//   (c) Circuit relay через third peer (для симметричных NAT)
//
// State machine локальной reachability hint и attempted methods. Реальные
// platform-specific вызовы (UPnP / AutoNAT / relay setup) делегируются
// transport layer (Phase C); эта модуль фиксирует state + invariants.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ReachabilityHint {
    Unknown,
    Public,
    NatPortMapped { external_port: u16 },
    NatHolePunched,
    BehindRelay,
    Unreachable,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NatMethod {
    UpnpPcp,
    AutoNatHolePunch,
    CircuitRelay,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct UpnpMapping {
    pub external_port: u16,
    pub renew_at_window: u64,
}

pub const UPNP_RENEW_INTERVAL_LOCAL_SECONDS: u64 = 1800;

#[derive(Debug)]
pub struct NatState {
    hint: ReachabilityHint,
    last_method: Option<NatMethod>,
    upnp: Option<UpnpMapping>,
}

impl NatState {
    pub fn new() -> Self {
        NatState {
            hint: ReachabilityHint::Unknown,
            last_method: None,
            upnp: None,
        }
    }

    pub fn hint(&self) -> ReachabilityHint {
        self.hint
    }

    pub fn last_method(&self) -> Option<NatMethod> {
        self.last_method
    }

    pub fn record_upnp_success(&mut self, external_port: u16, current_window: u64) {
        self.upnp = Some(UpnpMapping {
            external_port,
            renew_at_window: current_window + UPNP_RENEW_INTERVAL_LOCAL_SECONDS,
        });
        self.hint = ReachabilityHint::NatPortMapped { external_port };
        self.last_method = Some(NatMethod::UpnpPcp);
    }

    pub fn record_holepunch_success(&mut self) {
        self.hint = ReachabilityHint::NatHolePunched;
        self.last_method = Some(NatMethod::AutoNatHolePunch);
    }

    pub fn record_relay_setup(&mut self) {
        self.hint = ReachabilityHint::BehindRelay;
        self.last_method = Some(NatMethod::CircuitRelay);
    }

    pub fn record_unreachable(&mut self) {
        self.hint = ReachabilityHint::Unreachable;
    }

    pub fn record_public_directly(&mut self) {
        self.hint = ReachabilityHint::Public;
        self.upnp = None;
    }

    pub fn upnp_renew_due(&self, current_window: u64) -> bool {
        match self.upnp {
            Some(m) => current_window >= m.renew_at_window,
            None => false,
        }
    }

    pub fn upnp_release(&mut self) {
        self.upnp = None;
        if matches!(self.hint, ReachabilityHint::NatPortMapped { .. }) {
            self.hint = ReachabilityHint::Unknown;
        }
    }
}

impl Default for NatState {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn initial_state_is_unknown() {
        let s = NatState::new();
        assert_eq!(s.hint(), ReachabilityHint::Unknown);
        assert!(s.last_method().is_none());
    }

    #[test]
    fn upnp_success_sets_port_mapped_and_renew_schedule() {
        let mut s = NatState::new();
        s.record_upnp_success(443, 100);
        assert_eq!(
            s.hint(),
            ReachabilityHint::NatPortMapped { external_port: 443 }
        );
        assert_eq!(s.last_method(), Some(NatMethod::UpnpPcp));
        assert!(!s.upnp_renew_due(100 + 1500));
        assert!(s.upnp_renew_due(100 + UPNP_RENEW_INTERVAL_LOCAL_SECONDS));
    }

    #[test]
    fn holepunch_success_sets_hint_and_method() {
        let mut s = NatState::new();
        s.record_holepunch_success();
        assert_eq!(s.hint(), ReachabilityHint::NatHolePunched);
        assert_eq!(s.last_method(), Some(NatMethod::AutoNatHolePunch));
    }

    #[test]
    fn relay_setup_sets_hint() {
        let mut s = NatState::new();
        s.record_relay_setup();
        assert_eq!(s.hint(), ReachabilityHint::BehindRelay);
        assert_eq!(s.last_method(), Some(NatMethod::CircuitRelay));
    }

    #[test]
    fn upnp_release_resets_hint() {
        let mut s = NatState::new();
        s.record_upnp_success(443, 0);
        s.upnp_release();
        assert_eq!(s.hint(), ReachabilityHint::Unknown);
    }

    #[test]
    fn upnp_renew_due_only_after_interval() {
        let mut s = NatState::new();
        s.record_upnp_success(443, 1000);
        assert!(!s.upnp_renew_due(1500));
        assert!(!s.upnp_renew_due(2799));
        assert!(s.upnp_renew_due(2800));
    }

    #[test]
    fn record_public_clears_upnp() {
        let mut s = NatState::new();
        s.record_upnp_success(443, 0);
        s.record_public_directly();
        assert_eq!(s.hint(), ReachabilityHint::Public);
        assert!(!s.upnp_renew_due(u64::MAX));
    }
}
