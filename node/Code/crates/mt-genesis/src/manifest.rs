// spec, раздел "Сетевой уровень → Genesis manifest" (M8 cross-machine peer discovery)
//
// GenesisManifest — детерминированный список known peers для генезис-cohort.
// Каждый узел при `montana-node start --genesis-manifest <path>` читает manifest,
// dial-ит peers из списка, верифицирует libp2p PeerId совпадает с pinned значением.
//
// **NOT genesis_state_hash binding.** Manifest — операционные метаданные network (JSON формат)
// (multiaddr, peer_id), не входит в Genesis Decree (`ProtocolParams`). Изменение
// IP / port / replacement узла не требует ceremony — только переиздание manifest-а.
//
// Genesis Decree (`ProtocolParams::target_zero` /
// `genesis_content_data_hash`) — это immutable consensus binding, фиксируется
// ceremony-ой и попадает в `compute_genesis_state_hash()`.

use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Eq, PartialEq, Deserialize, Serialize)]
pub struct GenesisPeer {
    /// Человекочитаемая метка («moscow», «frankfurt», «vilnius»).
    pub label: String,
    /// libp2p multiaddr вида `/ip4/<addr>/tcp/<port>`. Без `/p2p/<peer_id>`
    /// suffix — peer_id хранится отдельно в поле `peer_id` для явности.
    pub multiaddr: String,
    /// libp2p PeerId в multihash base58 представлении (например `12D3KooW...`).
    /// Pinned при загрузке manifest-а — connection rejected если actual peer_id
    /// не совпадает.
    pub peer_id: String,
    /// account_id (32 байта SHA-256 от account_pk) в lowercase hex 64 символа.
    pub account_id_hex: String,
    /// node_id (32 байта SHA-256 от node_pk) в lowercase hex 64 символа.
    pub node_id_hex: String,
    /// `true` если этот узел = bootstrap (operator с эмиссией Day 1, его
    /// account_pk + node_pk финализированы в `ProtocolParams`).
    /// Среди peers в manifest-е может быть **ровно один** bootstrap.
    #[serde(default)]
    pub bootstrap: bool,
}

#[derive(Clone, Debug, Eq, PartialEq, Deserialize, Serialize)]
pub struct GenesisManifest {
    /// Имя сети для UX (mainnet всегда `"montana"`, тестнеты — описательно).
    pub network_name: String,
    /// Список генезис-cohort peers. Минимум 1 (singleton + ceremony deferred),
    /// типично 3 (initial Active + 2 candidates для М8 ceremony).
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
            Self::Json(e) => write!(f, "ошибка JSON: {e}"),
            Self::NoBootstrap => {
                write!(f, "manifest не содержит ни одного bootstrap = true peer")
            },
            Self::MultipleBootstrap(n) => {
                write!(f, "manifest содержит {n} bootstrap peers, ожидался ровно 1")
            },
            Self::EmptyPeers => write!(f, "manifest содержит 0 peers, минимум 1"),
            Self::InvalidHexLength {
                field,
                expected,
                actual,
            } => write!(
                f,
                "поле {field}: ожидалось {expected} hex-символов, получили {actual}"
            ),
        }
    }
}

impl std::error::Error for ManifestError {}

impl GenesisManifest {
    /// Парсит TOML-текст и валидирует invariants:
    ///   - peers непустой
    ///   - ровно один peer с `bootstrap = true`
    ///   - account_id_hex / node_id_hex длиной 64 символа каждый
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
