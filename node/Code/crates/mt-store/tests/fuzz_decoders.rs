// Pseudo-fuzz harness для mt-store wire decoders.
// Pass 11 / Pass 22 (CRITIC.md): wire decoders должны иметь fuzz target —
// `decode_*` принимают `&[u8]` от filesystem (potential attacker if disk
// compromised, либо disk corruption) и должны never panic, only return
// Result<T, StoreError>.
//
// Полный cargo-fuzz harness требует nightly toolchain (libfuzzer-sys) что
// конфликтует с `rust-toolchain.toml minimum 1.70 stable` workspace policy
// (Code/CLAUDE.md "Rust stable, минимум 1.70"). Используем deterministic
// PRNG-based pseudo-fuzz: generates 1000+ pseudorandom byte arrays
// различных длин, проверяет что decode_* возвращает либо Ok либо
// StoreError::CorruptedLength — НИКОГДА panic / index out of bounds /
// silent corruption.
//
// Запускается как обычный `cargo test`, входит в workspace тестовую
// suite. При появлении nightly toolchain — заменить на libfuzzer-sys
// harness в crates/mt-store/fuzz/fuzz_targets/ для intelligent coverage-
// guided fuzzing.

use mt_state::{ACCOUNT_RECORD_SIZE, CANDIDATE_RECORD_SIZE, NODE_RECORD_SIZE};
use mt_store::{FsStore, StoreError};

// Deterministic PRNG (xorshift64) — reproducible, не привносит
// non-determinism в test runs (важно для CI repeatability).
struct Xorshift64(u64);

impl Xorshift64 {
    fn new(seed: u64) -> Self {
        Self(if seed == 0 {
            0xDEAD_BEEF_CAFE_BABE
        } else {
            seed
        })
    }
    fn next_u64(&mut self) -> u64 {
        let mut x = self.0;
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        self.0 = x;
        x
    }
    fn next_byte(&mut self) -> u8 {
        (self.next_u64() & 0xFF) as u8
    }
    fn fill(&mut self, buf: &mut [u8]) {
        for b in buf.iter_mut() {
            *b = self.next_byte();
        }
    }
}

fn unique_tmp_dir(seed: &str) -> std::path::PathBuf {
    let pid = std::process::id();
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.subsec_nanos() as u64)
        .unwrap_or(0);
    let path = std::env::temp_dir().join(format!("mt-store-fuzz-{seed}-{pid}-{nanos}"));
    let _ = std::fs::remove_dir_all(&path);
    path
}

// Test invariant: decode_X(arbitrary bytes) → never panic, always Result.
// Corruption / wrong length → StoreError::CorruptedLength либо ParseFailed.
// Valid length + arbitrary content → Ok (decode succeeds на любом byte
// pattern of expected length, потому что decode не валидирует semantic
// invariants — это caller responsibility validate_*).

#[test]
fn fuzz_account_record_decode_no_panic() {
    let dir = unique_tmp_dir("fuzz-acct");
    let store = FsStore::open(&dir).expect("open");
    let mut rng = Xorshift64::new(0xACC7);

    for iter in 0..2000 {
        // Random length: mix valid (ACCOUNT_RECORD_SIZE) и invalid (random)
        let length = if iter % 5 == 0 {
            ACCOUNT_RECORD_SIZE
        } else if iter % 3 == 0 {
            (rng.next_u64() % 5000) as usize
        } else {
            // Boundaries: 0, 1, near-correct, double, off-by-one
            match iter % 7 {
                0 => 0,
                1 => 1,
                2 => ACCOUNT_RECORD_SIZE - 1,
                3 => ACCOUNT_RECORD_SIZE + 1,
                4 => ACCOUNT_RECORD_SIZE * 2,
                5 => ACCOUNT_RECORD_SIZE / 2,
                _ => (rng.next_u64() % (3 * ACCOUNT_RECORD_SIZE as u64)) as usize,
            }
        };
        let mut bytes = vec![0u8; length];
        rng.fill(&mut bytes);
        std::fs::write(dir.join("accounts.bin"), &bytes).expect("write");

        // Single-record load attempts
        let result = std::panic::catch_unwind(|| store.load_account_table());
        assert!(
            result.is_ok(),
            "decode_account_record paniked at iter={iter} length={length}"
        );
        // Также verify что error либо Ok возвращены — не silent unwrap
        match result.unwrap() {
            Ok(_) => {
                // Длина кратна ACCOUNT_RECORD_SIZE → decoded successfully
                assert_eq!(length % ACCOUNT_RECORD_SIZE, 0);
            },
            Err(StoreError::CorruptedLength(_)) => {
                assert_ne!(length % ACCOUNT_RECORD_SIZE, 0);
            },
            Err(other) => panic!("unexpected error variant for length={length}: {:?}", other),
        }
    }
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn fuzz_node_record_decode_no_panic() {
    let dir = unique_tmp_dir("fuzz-node");
    let store = FsStore::open(&dir).expect("open");
    let mut rng = Xorshift64::new(0x0DE0);

    for iter in 0..2000 {
        let length = match iter % 8 {
            0 => 0,
            1 => 1,
            2 => NODE_RECORD_SIZE,
            3 => NODE_RECORD_SIZE - 1,
            4 => NODE_RECORD_SIZE + 1,
            5 => NODE_RECORD_SIZE * 2,
            6 => (rng.next_u64() % 10000) as usize,
            _ => (rng.next_u64() % (3 * NODE_RECORD_SIZE as u64)) as usize,
        };
        let mut bytes = vec![0u8; length];
        rng.fill(&mut bytes);
        std::fs::write(dir.join("nodes.bin"), &bytes).expect("write");

        let result = std::panic::catch_unwind(|| store.load_node_table());
        assert!(
            result.is_ok(),
            "decode_node_record paniked at iter={iter} length={length}"
        );
        match result.unwrap() {
            Ok(_) => assert_eq!(length % NODE_RECORD_SIZE, 0),
            Err(StoreError::CorruptedLength(_)) => {
                assert_ne!(length % NODE_RECORD_SIZE, 0)
            },
            Err(other) => panic!("unexpected error: {other:?}"),
        }
    }
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn fuzz_candidate_record_decode_no_panic() {
    let dir = unique_tmp_dir("fuzz-cand");
    let store = FsStore::open(&dir).expect("open");
    let mut rng = Xorshift64::new(0xCAFE);

    for iter in 0..2000 {
        let length = match iter % 8 {
            0 => 0,
            1 => CANDIDATE_RECORD_SIZE,
            2 => CANDIDATE_RECORD_SIZE - 1,
            3 => CANDIDATE_RECORD_SIZE + 1,
            4 => CANDIDATE_RECORD_SIZE * 2,
            5 => CANDIDATE_RECORD_SIZE * 3,
            6 => (rng.next_u64() % 10000) as usize,
            _ => (rng.next_u64() % (3 * CANDIDATE_RECORD_SIZE as u64)) as usize,
        };
        let mut bytes = vec![0u8; length];
        rng.fill(&mut bytes);
        std::fs::write(dir.join("candidates.bin"), &bytes).expect("write");

        let result = std::panic::catch_unwind(|| store.load_candidate_pool());
        assert!(
            result.is_ok(),
            "decode_candidate_record paniked at iter={iter} length={length}"
        );
        match result.unwrap() {
            Ok(_) => assert_eq!(length % CANDIDATE_RECORD_SIZE, 0),
            Err(StoreError::CorruptedLength(_)) => {
                assert_ne!(length % CANDIDATE_RECORD_SIZE, 0)
            },
            Err(other) => panic!("unexpected error: {other:?}"),
        }
    }
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn fuzz_proposal_header_decode_no_panic() {
    use mt_consensus::PROPOSAL_HEADER_SIZE;
    let dir = unique_tmp_dir("fuzz-prop");
    let store = FsStore::open(&dir).expect("open");
    let mut rng = Xorshift64::new(0xDEAD);

    let proposals_dir = dir.join("proposals");
    let _ = std::fs::create_dir_all(&proposals_dir);

    for iter in 0..1000 {
        let length = match iter % 8 {
            0 => 0,
            1 => PROPOSAL_HEADER_SIZE,
            2 => PROPOSAL_HEADER_SIZE - 1,
            3 => PROPOSAL_HEADER_SIZE + 1,
            4 => PROPOSAL_HEADER_SIZE / 2,
            5 => PROPOSAL_HEADER_SIZE * 2,
            6 => (rng.next_u64() % 10000) as usize,
            _ => (rng.next_u64() % (3 * PROPOSAL_HEADER_SIZE as u64)) as usize,
        };
        let mut bytes = vec![0u8; length];
        rng.fill(&mut bytes);
        let target = proposals_dir.join(format!("{:020}.bin", 42));
        std::fs::write(&target, &bytes).expect("write proposal");

        let result = std::panic::catch_unwind(|| store.get_proposal_by_window(42));
        assert!(
            result.is_ok(),
            "decode_proposal_header paniked at iter={iter} length={length}"
        );
        match result.unwrap() {
            Ok(Some(_)) => assert_eq!(length, PROPOSAL_HEADER_SIZE),
            Ok(None) => panic!("expected file present"),
            Err(StoreError::CorruptedLength(_)) => {
                assert_ne!(length, PROPOSAL_HEADER_SIZE)
            },
            Err(other) => panic!("unexpected error: {other:?}"),
        }
    }
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn fuzz_meta_last_cemented_decode_no_panic() {
    let dir = unique_tmp_dir("fuzz-meta");
    let store = FsStore::open(&dir).expect("open");
    let mut rng = Xorshift64::new(0xBEEF);

    for iter in 0..500 {
        let length = match iter % 6 {
            0 => 0,
            1 => 8, // valid
            2 => 7, // off-by-one
            3 => 9,
            4 => 16,
            _ => (rng.next_u64() % 100) as usize,
        };
        let mut bytes = vec![0u8; length];
        rng.fill(&mut bytes);
        std::fs::write(dir.join("meta_last_cemented.bin"), &bytes).expect("write");

        let result = std::panic::catch_unwind(|| store.load_meta_last_cemented());
        assert!(
            result.is_ok(),
            "load_meta_last_cemented paniked at iter={iter} length={length}"
        );
        match result.unwrap() {
            Ok(Some(_)) => assert_eq!(length, 8),
            Ok(None) => panic!("expected file present"),
            Err(StoreError::CorruptedLength(_)) => assert_ne!(length, 8),
            Err(other) => panic!("unexpected error: {other:?}"),
        }
    }
    let _ = std::fs::remove_dir_all(&dir);
}
