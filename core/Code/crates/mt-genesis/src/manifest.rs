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
use std::collections::BTreeSet;

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
    InvalidHex {
        field: &'static str,
    },
    RepeatedIdentity {
        field: &'static str,
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
                write!(
                    f,
                    "manifest contains {n} bootstrap peers, expected exactly 1"
                )
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
            Self::InvalidHex { field } => {
                write!(f, "field {field}: expected lowercase hexadecimal")
            },
            Self::RepeatedIdentity { field } => write!(f, "field {field}: repeated identity"),
        }
    }
}

impl std::error::Error for ManifestError {}

impl GenesisManifest {
    /// Parses JSON text and validates invariants:
    ///   - peers is non-empty
    ///   - exactly one peer with `bootstrap = true`
    ///   - account_id_hex / node_id_hex are canonical 32-byte hexadecimal identities
    ///   - each peer, account and node identity occurs once
    ///
    /// The transport validates PeerId and Multiaddr syntax before startup succeeds.
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
        let mut identities = BTreeSet::new();
        for peer in &self.peers {
            for (field, value) in [
                ("account_id_hex", peer.account_id_hex.as_str()),
                ("node_id_hex", peer.node_id_hex.as_str()),
            ] {
                if value.len() != 64 {
                    return Err(ManifestError::InvalidHexLength {
                        field,
                        expected: 64,
                        actual: value.len(),
                    });
                }
                if !value
                    .bytes()
                    .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
                {
                    return Err(ManifestError::InvalidHex { field });
                }
                if !identities.insert((field, value)) {
                    return Err(ManifestError::RepeatedIdentity { field });
                }
            }
            if !identities.insert(("peer_id", peer.peer_id.as_str())) {
                return Err(ManifestError::RepeatedIdentity { field: "peer_id" });
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
                  "peer_id": "12D3KooWFirstExamplePeerId",
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
    fn identities_must_be_hexadecimal_and_canonical() {
        for invalid in ["g".repeat(64), "A".repeat(64), "é".repeat(32)] {
            for account in [true, false] {
                let mut m = GenesisManifest::parse(&three_peer_manifest_json()).unwrap();
                let field = if account {
                    m.peers[0].account_id_hex = invalid.clone();
                    "account_id_hex"
                } else {
                    m.peers[0].node_id_hex = invalid.clone();
                    "node_id_hex"
                };
                assert!(
                    matches!(m.validate(), Err(ManifestError::InvalidHex { field: f }) if f == field)
                );
            }
        }
    }

    #[test]
    fn a_second_peer_cannot_reuse_an_identity() {
        for field in ["peer_id", "account_id_hex", "node_id_hex"] {
            let mut m = GenesisManifest::parse(&three_peer_manifest_json()).unwrap();
            match field {
                "peer_id" => m.peers[1].peer_id = m.peers[0].peer_id.clone(),
                "account_id_hex" => m.peers[1].account_id_hex = m.peers[0].account_id_hex.clone(),
                _ => m.peers[1].node_id_hex = m.peers[0].node_id_hex.clone(),
            }
            assert!(
                matches!(m.validate(), Err(ManifestError::RepeatedIdentity { field: f }) if f == field)
            );
        }
    }

    #[test]
    fn bootstrap_peer_returns_none_when_no_bootstrap() {
        let mut m: GenesisManifest = serde_json::from_str(&three_peer_manifest_json()).unwrap();
        m.peers[0].bootstrap = false;
        assert!(m.bootstrap_peer().is_none());
    }
}
