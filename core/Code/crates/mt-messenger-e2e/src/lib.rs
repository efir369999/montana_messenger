//! Montana Messenger E2E — shared Rust engine for end-to-end encryption.
//! Montana Messenger spec v0.40.0. Clients (iOS/Web/Python) link this crate
//! instead of reimplementing the cryptography — byte-identity is locked by the spec's KAT vectors.
//!
//! - `pqxdh`   — Stage 5: post-quantum session establishment (ML-KEM-768 PQXDH).
//! - `ratchet` — Stage 6: double ratchet (KEM ratchet), message AEAD.
//! - `labels`  — Stage 7: blind delivery, rotating queue labels.
//! - `safety`  — Stage 8: identity fingerprint verification (safety number).
//! - `call`    — Stage 13: post-quantum media key for calls (SFrame over SRTP).
//! - `content` — Stage 9: Content codec for 1-on-1 private chat.
//! - `contacts` — Stage 11: @name request, contacts key, ContactRecord/List.
//! - `device_registry` — Stage 10: signed device registry (multi-device).

pub mod archive;
pub mod archive_sync;
pub mod call;
pub mod compaction;
pub mod contacts;
pub mod content;
pub mod crypto;
pub mod device_registry;
pub mod handshake;
pub mod kdf;
pub mod labels;
pub mod media;
pub mod media_pin;
pub mod merkle;
pub mod peer_recovery;
pub mod pqxdh;
pub mod ratchet;
pub mod reconcile;
pub mod relay_policy;
pub mod safety;
pub mod sealed;
pub mod session;
