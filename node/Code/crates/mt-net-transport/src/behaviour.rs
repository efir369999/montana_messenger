// MontanaBehaviour — composed libp2p NetworkBehaviour для request-response
// (Phase C.2). One-way gossip (Transfer, Anchor, NodeRegistration, ...)
// — defer to Phase C.3 (Dandelion++ stem-fluff либо floodsub).

use libp2p::{
    request_response::{
        Behaviour as RequestResponseBehaviour, Config as RrConfig, ProtocolSupport,
    },
    swarm::NetworkBehaviour,
};

use crate::codec::{MontanaCodec, MONTANA_PROTOCOL_NAME};

#[derive(NetworkBehaviour)]
pub struct MontanaBehaviour {
    pub request_response: RequestResponseBehaviour<MontanaCodec>,
}

impl MontanaBehaviour {
    pub fn new() -> Self {
        let protocols = std::iter::once((MONTANA_PROTOCOL_NAME, ProtocolSupport::Full));
        let cfg = RrConfig::default();
        MontanaBehaviour {
            request_response: RequestResponseBehaviour::with_codec(MontanaCodec, protocols, cfg),
        }
    }
}

impl Default for MontanaBehaviour {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn behaviour_constructs() {
        let _b = MontanaBehaviour::new();
    }
}
