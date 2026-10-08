// spec, section "Network Layer → Genesis manifest" (M8 cross-machine peer discovery)
//
// GenesisManifest — deterministic list of known peers for the genesis cohort.
// On `montana-node start --genesis-manifest <path>` each node reads the manifest,
// dials the peers from the list, verifies that the libp2p PeerId matches the pinned value.
//
// **NOT genesis_state_hash binding.** The manifest is operational network metadata (JSON)
// (multiaddr, peer_id), not part of the Genesis Decree (`ProtocolParams`). Changing
// an IP / port / replacing a node needs no ceremony — only reissuing the manifest.
//
// Genesis Decree (`ProtocolParams::target_zero` /
// `genesis_content_data_hash`) is an immutable consensus binding, fixed by the
// ceremony and included in `compute_genesis_state_hash()`.

use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Eq, PartialEq, Deserialize, Serialize)]
pub struct GenesisPeer {
    /// Human-readable label ("moscow", "frankfurt", "vilnius").
    pub label: String,
    /// libp2p multiaddr shaped like `/ip4/<addr>/tcp/<port>`. Without the `/p2p/<peer_id>`
    /// suffix — peer_id is stored separately in the `peer_id` field for explicitness.
    pub multiaddr: String,
    /// libp2p PeerId in multihash base58 representation (e.g. `12D3KooW...`).
    /// Pinned at manifest load — connection rejected if the actual peer_id
    /// does not match.
    pub peer_id: String,
    /// account_id (32 bytes, SHA-256 of account_pk) in lowercase hex, 64 characters.
    pub account_id_hex: String,
    /// node_id (32 bytes, SHA-256 of node_pk) in lowercase hex, 64 characters.
    pub node_id_hex: String,
    /// `true` if this node is the bootstrap (operator with Day 1 emission, its
    /// account_pk + node_pk are finalized in `ProtocolParams`).
    /// Among the peers in the manifest there may be **exactly one** bootstrap.
    #[serde(default)]
    pub bootstrap: bool,
}

#[derive(Clone, Debug, Eq, PartialEq, Deserialize, Serialize)]
pub struct GenesisManifest {
    /// Network name for UX (mainnet is always `"montana"`, testnets are descriptive).
    pub network_name: String,
    /// List of genesis-cohort peers. Minimum 1 (singleton + ceremony deferred),
    /// typically 3 (initial Active + 2 candidates for the M8 ceremony).
    pub peers: Vec<GenesisPeer>,
}

#[derive(Debug)]
pub enum ManifestError {
    Json(serde_json::Error),
    NoBootstrap,
    MultipleBootstrap(usize),
    EmptyPeers,
    InvalidHexLength {
        field: &'static str,
        expected: usize,
        actual: usize,
    },
}

impl std::fmt::Display for ManifestError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Json(e) => write!(f, "JSON error: {e}"),
            Self::NoBootstrap => {
                write!(f, "manifest contains no bootstrap = true peer")
            },
            Self::MultipleBootstrap(n) => {
                write!(f, "manifest contains {n} bootstrap peers, expected exactly 1")
            },
            Self::EmptyPeers => write!(f, "manifest contains 0 peers, minimum 1"),
            Self::InvalidHexLength {
                field,
                expected,
                actual,
            } => write!(
                f,
                "field {field}: expected {expected} hex characters, got {actual}"
            ),
        }
    }
}

impl std::error::Error for ManifestError {}

impl GenesisManifest {
    /// Parses TOML text and validates invariants:
    ///   - peers is non-empty
    ///   - exactly one peer with `bootstrap = true`
    ///   - account_id_hex / node_id_hex are 64 characters long each
    pub fn parse(json_text: &str) -> Result<Self, ManifestError> {
        let manifest: GenesisManifest =
            serde_json::from_str(json_text).map_err(ManifestError::Json)?;
        manifest.validate()?;
        Ok(manifest)
    }

    pub fn to_json_string(&self) -> Result<String, ManifestError> {
        serde_json::to_string_pretty(self).map_err(ManifestError::Json)
    }

    pub fn validate(&self) -> Result<(), ManifestError> {
        if self.peers.is_empty() {
            return Err(ManifestError::EmptyPeers);
        }
        let bootstrap_count = self.peers.iter().filter(|p| p.bootstrap).count();
        match bootstrap_count {
            0 => return Err(ManifestError::NoBootstrap),
            1 => (),
            n => return Err(ManifestError::MultipleBootstrap(n)),
        }
        for peer in &self.peers {
            if peer.account_id_hex.len() != 64 {
                return Err(ManifestError::InvalidHexLength {
                    field: "account_id_hex",
                    expected: 64,
                    actual: peer.account_id_hex.len(),
                });
            }
            if peer.node_id_hex.len() != 64 {
                return Err(ManifestError::InvalidHexLength {
                    field: "node_id_hex",
                    expected: 64,
                    actual: peer.node_id_hex.len(),
                });
            }
        }
        Ok(())
    }

    pub fn bootstrap_peer(&self) -> Option<&GenesisPeer> {
        self.peers.iter().find(|p| p.bootstrap)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn three_peer_manifest_json() -> String {
        format!(
            r#"{{
              "network_name": "montana",
              "peers": [
                {{
                  "label": "moscow",
                  "multiaddr": "/ip4/<front>/tcp/8444",
                  "peer_id": "12D3KooWMoscowExamplePeerId",
                  "account_id_hex": "{a}",
                  "node_id_hex": "{n}",
                  "bootstrap": true
                }},
                {{
                  "label": "frankfurt",
                  "multiaddr": "/ip4/<exit-de>/tcp/8444",
                  "peer_id": "12D3KooWFrankfurtExamplePeerId",
                  "account_id_hex": "{b}",
                  "node_id_hex": "{m}",
                  "bootstrap": false
                }}
              ]
            }}"#,
            a = "1".repeat(64),
            b = "2".repeat(64),
            n = "a".repeat(64),
            m = "b".repeat(64)
        )
    }

    #[test]
    fn parse_three_peer_manifest() {
        // helsinki removed from fixture 2026-05-30 → 2 peers
        let toml_text = three_peer_manifest_json();
        let m = GenesisManifest::parse(&toml_text).expect("valid manifest");
        assert_eq!(m.network_name, "montana");
        assert_eq!(m.peers.len(), 2);
        assert_eq!(m.peers[0].label, "moscow");
        assert!(m.peers[0].bootstrap);
        assert!(!m.peers[1].bootstrap);
        assert_eq!(m.bootstrap_peer().unwrap().label, "moscow");
    }

    #[test]
    fn parse_rejects_empty_peers() {
        let json_text = r#"{"network_name":"test","peers":[]}"#;
        let err = GenesisManifest::parse(json_text).unwrap_err();
        assert!(matches!(err, ManifestError::EmptyPeers));
    }

    #[test]
    fn parse_rejects_no_bootstrap() {
        let mut m: GenesisManifest = serde_json::from_str(&three_peer_manifest_json()).unwrap();
        m.peers[0].bootstrap = false;
        let err = m.validate().unwrap_err();
        assert!(matches!(err, ManifestError::NoBootstrap));
    }

    #[test]
    fn parse_rejects_multiple_bootstrap() {
        let mut m: GenesisManifest = serde_json::from_str(&three_peer_manifest_json()).unwrap();
        m.peers[1].bootstrap = true;
        let err = m.validate().unwrap_err();
        assert!(matches!(err, ManifestError::MultipleBootstrap(2)));
    }

    #[test]
    fn parse_rejects_short_account_id_hex() {
        let mut m: GenesisManifest = serde_json::from_str(&three_peer_manifest_json()).unwrap();
        m.peers[0].account_id_hex = "abc".to_string();
        let err = m.validate().unwrap_err();
        assert!(matches!(
            err,
            ManifestError::InvalidHexLength {
                field: "account_id_hex",
                expected: 64,
                actual: 3
            }
        ));
    }

    #[test]
    fn roundtrip_serialize_parse() {
        let original = GenesisManifest::parse(&three_peer_manifest_json()).unwrap();
        let serialized = original.to_json_string().unwrap();
        let reparsed = GenesisManifest::parse(&serialized).unwrap();
        assert_eq!(original, reparsed);
    }

    #[test]
    fn bootstrap_peer_returns_none_when_no_bootstrap() {
        let mut m: GenesisManifest = serde_json::from_str(&three_peer_manifest_json()).unwrap();
        m.peers[0].bootstrap = false;
        assert!(m.bootstrap_peer().is_none());
    }
}
