// spec, раздел "Вход и регистрация → Genesis State"

pub mod manifest;

pub use manifest::{GenesisManifest, GenesisPeer, ManifestError};

use std::sync::OnceLock;

use mt_codec::{
    domain, write_bytes, write_u128, write_u16, write_u32, write_u64, write_u8, CanonicalEncode,
};
use mt_crypto::{hash, Hash32};

// PARAMS_ENCODED_SIZE: layout sum для protocol_params (см. spec раздел "Указ Генезиса").
// Layout (LE):
// d0(8) + reserved(8) + tau2(8) + emission(16) + target_zero(32) + quorum_num(1)
// + quorum_den(1) + dead_zone(2+2) + d_adj(2+2) + ssha_entry(8) + sel_interval(8)
// + admission_divisor(8) + cand_expiry(8) + adapt_thr(2) + adapt_mult(2) + pruning(8)
// + max_payload(4) + max_sf(4) + app_id(32) + content_hash(32)
// = 198 bytes. Genesis = empty window 0: no baked bootstrap operator, no
// N_SEED cohort, no proof-of-work difficulty. The first node bootstraps via
// the existing admission path (selection_slots(0)=1 self-admit, quorum(1)=1
// self-cement).
pub const PARAMS_ENCODED_SIZE: usize = 198;

/// 32 байта initial SSHA target. SHA-256("mt-genesis" || account_pk || node_pk
/// || "montana-genesis-mainnet-2026-06-11").
pub const TARGET_ZERO_BYTES: [u8; 32] = [
    0x31, 0x30, 0xB7, 0xD8, 0x5F, 0x4A, 0x41, 0xB9, 0xFB, 0xD3, 0xEC, 0xE4, 0x70, 0xC8, 0x8A, 0x29,
    0x4C, 0xEC, 0x37, 0xD7, 0x01, 0x3F, 0x0E, 0x1B, 0xDC, 0xD3, 0xF4, 0x5B, 0xF9, 0x52, 0x7C, 0xBE,
];

/// 32 байта хэш Genesis content. SHA-256("montana-genesis-content-2026-06-11-mainnet").
pub const GENESIS_CONTENT_DATA_HASH_BYTES: [u8; 32] = [
    0xB4, 0x27, 0x19, 0x43, 0xE5, 0x34, 0x16, 0x85, 0xAF, 0x67, 0x1B, 0xA3, 0xD0, 0x4E, 0x9E, 0x83,
    0x2B, 0x65, 0xD6, 0xCB, 0xA9, 0xA6, 0x2C, 0x46, 0x59, 0xDA, 0x37, 0x28, 0xEC, 0xD4, 0x78, 0xDC,
];

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ProtocolParams {
    pub d0: u64,
    pub reserved_m0: [u8; 8],
    pub tau2_windows: u64,
    // spec, раздел "Эмиссия": const emission `reward_moneta(W) = EMISSION_moneta`.
    pub emission_moneta: u128,
    pub target_zero: [u8; 32],
    pub confirmation_quorum_num: u8,
    pub confirmation_quorum_den: u8,
    pub participation_dead_zone_low: u16,
    pub participation_dead_zone_high: u16,
    pub d_adjustment_rate_num: u16,
    pub d_adjustment_rate_den: u16,
    pub ssha_entry_windows: u64,
    pub selection_interval: u64,
    // spec v33.1.6+: slots = max(1, floor(active_nodes / admission_divisor))
    // per selection event. Pin 130 даёт 1/130 ≈ 0.77% steady-state admission
    // rate < 1% upper bound. [C-1] SSOT: ранее жил как hardcoded const в
    // mt-entry::ADMISSION_DIVISOR (M4-LOW-7 closure).
    pub admission_divisor: u64,
    pub candidate_expiry_windows: u64,
    pub adaptive_ssha_threshold: u16,
    pub adaptive_ssha_multiplier: u16,
    pub pruning_idle_windows: u64,
    pub max_protocol_payload_bytes: u32,
    pub max_sf_ciphertext_bytes: u32,
    pub genesis_content_app_id: Hash32,
    pub genesis_content_data_hash: Hash32,
}

impl CanonicalEncode for ProtocolParams {
    fn encode(&self, buf: &mut Vec<u8>) {
        write_u64(buf, self.d0);
        write_bytes(buf, &self.reserved_m0);
        write_u64(buf, self.tau2_windows);
        write_u128(buf, self.emission_moneta);
        write_bytes(buf, &self.target_zero);
        write_u8(buf, self.confirmation_quorum_num);
        write_u8(buf, self.confirmation_quorum_den);
        write_u16(buf, self.participation_dead_zone_low);
        write_u16(buf, self.participation_dead_zone_high);
        write_u16(buf, self.d_adjustment_rate_num);
        write_u16(buf, self.d_adjustment_rate_den);
        write_u64(buf, self.ssha_entry_windows);
        write_u64(buf, self.selection_interval);
        write_u64(buf, self.admission_divisor);
        write_u64(buf, self.candidate_expiry_windows);
        write_u16(buf, self.adaptive_ssha_threshold);
        write_u16(buf, self.adaptive_ssha_multiplier);
        write_u64(buf, self.pruning_idle_windows);
        write_u32(buf, self.max_protocol_payload_bytes);
        write_u32(buf, self.max_sf_ciphertext_bytes);
        write_bytes(buf, &self.genesis_content_app_id);
        write_bytes(buf, &self.genesis_content_data_hash);
    }
}

// spec: genesis_content_app_id = SHA-256("mt-app" || "montana")
pub fn genesis_app_id() -> Hash32 {
    hash(domain::APP, &[b"montana"])
}

pub fn genesis_params() -> &'static ProtocolParams {
    static INSTANCE: OnceLock<ProtocolParams> = OnceLock::new();
    INSTANCE.get_or_init(|| ProtocolParams {
        d0: 325_000_000,
        reserved_m0: [0u8; 8],
        tau2_windows: 20_160,
        emission_moneta: 13_000_000_000,
        target_zero: TARGET_ZERO_BYTES,
        confirmation_quorum_num: 67,
        confirmation_quorum_den: 100,
        participation_dead_zone_low: 85,
        participation_dead_zone_high: 95,
        d_adjustment_rate_num: 3,
        d_adjustment_rate_den: 100,
        // TEST CONFIG (devnet, spec 2387): кандидат входит за 1 окно.
        // БОЕВОЙ = 20_160 (= τ₂). Развязано от tau2_windows в required_ssha_length.
        ssha_entry_windows: 1,
        // TEST CONFIG: приём в Active каждое окно. БОЕВОЙ = 336.
        selection_interval: 1,
        admission_divisor: 130,
        candidate_expiry_windows: 60_480,
        adaptive_ssha_threshold: 1,
        adaptive_ssha_multiplier: 100,
        pruning_idle_windows: 80_640,
        max_protocol_payload_bytes: 1_048_576,
        max_sf_ciphertext_bytes: 65_536,
        genesis_content_app_id: genesis_app_id(),
        genesis_content_data_hash: GENESIS_CONTENT_DATA_HASH_BYTES,
    })
}

// spec v29.7.1+: Genesis State Hash = SHA-256("mt-genesis" || genesis_state_root || canonical_encode(protocol_params))
pub fn compute_genesis_state_hash(state_root: &Hash32, params: &ProtocolParams) -> Hash32 {
    let mut encoded = Vec::with_capacity(PARAMS_ENCODED_SIZE);
    params.encode(&mut encoded);
    hash(domain::GENESIS, &[state_root, &encoded])
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn params_encoded_size_matches_layout() {
        let mut buf = Vec::new();
        genesis_params().encode(&mut buf);
        assert_eq!(buf.len(), PARAMS_ENCODED_SIZE);
        assert_eq!(PARAMS_ENCODED_SIZE, 198);
    }

    #[test]
    fn spec_constants_match() {
        let p = genesis_params();
        assert_eq!(p.d0, 325_000_000);
        assert_eq!(p.reserved_m0, [0u8; 8]);
        assert_eq!(p.tau2_windows, 20_160);
        assert_eq!(p.emission_moneta, 13_000_000_000);
        assert_eq!(p.confirmation_quorum_num, 67);
        assert_eq!(p.confirmation_quorum_den, 100);
        assert_eq!(p.participation_dead_zone_low, 85);
        assert_eq!(p.participation_dead_zone_high, 95);
        assert_eq!(p.d_adjustment_rate_num, 3);
        assert_eq!(p.d_adjustment_rate_den, 100);
        // devnet TEST CONFIG: ssha_entry_windows=1, selection_interval=1
        // (production = 20_160 / 336). Calibration values are author-chosen and
        // decoupled from tau2_windows in required_ssha_length / is_selection_window.
        assert_eq!(p.ssha_entry_windows, 1);
        assert_eq!(p.selection_interval, 1);
        assert_eq!(p.admission_divisor, 130);
        assert_eq!(p.candidate_expiry_windows, 60_480);
        assert_eq!(p.adaptive_ssha_threshold, 1);
        assert_eq!(p.adaptive_ssha_multiplier, 100);
        assert_eq!(p.pruning_idle_windows, 80_640);
        assert_eq!(p.max_protocol_payload_bytes, 1_048_576);
        assert_eq!(p.max_sf_ciphertext_bytes, 65_536);
    }

    #[test]
    fn ssha_entry_is_devnet_one_window() {
        // devnet TEST CONFIG: a candidate enters in 1 window (production = τ₂).
        let p = genesis_params();
        assert_eq!(p.ssha_entry_windows, 1);
    }

    #[test]
    fn candidate_expiry_is_3_tau2() {
        let p = genesis_params();
        assert_eq!(p.candidate_expiry_windows, 3 * p.tau2_windows);
    }

    #[test]
    fn pruning_idle_is_4_tau2() {
        let p = genesis_params();
        assert_eq!(p.pruning_idle_windows, 4 * p.tau2_windows);
    }

    #[test]
    fn selection_interval_divides_tau2() {
        // devnet TEST CONFIG: selection_interval=1 divides τ₂; ratio = τ₂
        // (production selection_interval=336 → ratio 60).
        let p = genesis_params();
        assert_eq!(p.tau2_windows % p.selection_interval, 0);
        assert_eq!(p.tau2_windows / p.selection_interval, p.tau2_windows);
    }

    #[test]
    fn genesis_app_id_deterministic() {
        assert_eq!(genesis_app_id(), genesis_app_id());
    }

    #[test]
    fn genesis_app_id_matches_formula() {
        let expected = hash(domain::APP, &[b"montana"]);
        assert_eq!(genesis_app_id(), expected);
        assert_eq!(genesis_params().genesis_content_app_id, genesis_app_id());
    }

    #[test]
    fn first_8_bytes_encode_d0_little_endian() {
        let mut buf = Vec::new();
        genesis_params().encode(&mut buf);
        assert_eq!(&buf[..8], &genesis_params().d0.to_le_bytes());
        assert_eq!(&buf[..8], &[0x40, 0x1B, 0x5F, 0x13, 0, 0, 0, 0]);
    }

    #[test]
    fn bytes_8_to_16_are_reserved_zeros() {
        let mut buf = Vec::new();
        genesis_params().encode(&mut buf);
        assert_eq!(&buf[8..16], &[0u8; 8]);
    }

    #[test]
    fn bytes_16_to_24_encode_tau2() {
        let mut buf = Vec::new();
        genesis_params().encode(&mut buf);
        assert_eq!(&buf[16..24], &20_160u64.to_le_bytes());
    }

    #[test]
    fn bytes_24_to_40_encode_emission_moneta() {
        let mut buf = Vec::new();
        genesis_params().encode(&mut buf);
        assert_eq!(&buf[24..40], &13_000_000_000u128.to_le_bytes());
    }

    #[test]
    fn encode_deterministic() {
        let mut a = Vec::new();
        genesis_params().encode(&mut a);
        let mut b = Vec::new();
        genesis_params().encode(&mut b);
        assert_eq!(a, b);
    }

    #[test]
    fn compute_hash_deterministic() {
        let root = [0xABu8; 32];
        let a = compute_genesis_state_hash(&root, genesis_params());
        let b = compute_genesis_state_hash(&root, genesis_params());
        assert_eq!(a, b);
    }

    #[test]
    fn compute_hash_detects_param_mutation() {
        let root = [0xABu8; 32];
        let h1 = compute_genesis_state_hash(&root, genesis_params());

        let mut mutated = genesis_params().clone();
        mutated.d0 = 325_000_001;
        let h2 = compute_genesis_state_hash(&root, &mutated);
        assert_ne!(h1, h2);
    }

    #[test]
    fn compute_hash_detects_state_root_mutation() {
        let r1 = [0xABu8; 32];
        let r2 = [0xCDu8; 32];
        let h1 = compute_genesis_state_hash(&r1, genesis_params());
        let h2 = compute_genesis_state_hash(&r2, genesis_params());
        assert_ne!(h1, h2);
    }

    #[test]
    fn encode_detects_field_mutations() {
        let mut orig = Vec::new();
        genesis_params().encode(&mut orig);

        let mutations: Vec<fn(&mut ProtocolParams)> = vec![
            |p| p.d0 += 1,
            |p| p.tau2_windows += 1,
            |p| p.emission_moneta += 1,
            |p| p.target_zero[0] = 0xFF,
            |p| p.confirmation_quorum_num = 68,
            |p| p.confirmation_quorum_den = 101,
            |p| p.participation_dead_zone_low = 86,
            |p| p.participation_dead_zone_high = 96,
            |p| p.selection_interval = 370,
            |p| p.candidate_expiry_windows += 1,
            |p| p.adaptive_ssha_multiplier = 101,
            |p| p.pruning_idle_windows += 1,
            |p| p.genesis_content_app_id[0] = 0xFF,
            |p| p.genesis_content_data_hash[0] = 0xFF,
        ];

        for (i, m) in mutations.iter().enumerate() {
            let mut mutated = genesis_params().clone();
            m(&mut mutated);
            let mut buf = Vec::new();
            mutated.encode(&mut buf);
            assert_ne!(orig, buf, "mutation {} did not affect encoding", i);
        }
    }

    #[test]
    fn reserved_m0_enforced_zeros_in_default() {
        assert_eq!(genesis_params().reserved_m0, [0u8; 8]);
    }

    #[test]
    fn genesis_target_and_content_finalized() {
        // Genesis = empty window 0: no baked bootstrap operator. The only
        // ceremony-controlled values left are the initial SSHA target and the
        // genesis content hash; both are non-placeholder.
        let p = genesis_params();
        assert_ne!(p.target_zero, [0u8; 32]);
        assert_ne!(p.genesis_content_data_hash, [0u8; 32]);
    }
}
