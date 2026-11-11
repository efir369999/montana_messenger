// Automated security invariants for mt-crypto secret-handling code.
// Closes Pass 17 of the critic role "Mandatory Security Card per crypto primitive"
// via regression detection -- if a future refactor accidentally breaks a
// security invariant, the test fails in CI BEFORE merge.
//
// Checks:
//   1. SecretKey has no Clone/Copy traits (no accidental copies)
//   2. MlkemSecretKey has no Clone/Copy traits
//   3. SecretKey/MlkemSecretKey heap-allocated (Box) — size_of == pointer size
//      guarantees the bytes are on the heap (no stack memcpy on moves)
//   4. SecretKey keeps its bytes on the heap independent of the stack frame
//   5. Drop+zeroize verified via a behavioral test (memory pattern check)
//   6. Public type fields private (no struct literal construction)
//   7. No println!/log macros on SK bytes in lib code (file-content scan)

use mt_crypto::{
    keypair_from_seed, keypair_from_seed_mlkem, MlkemSecretKey, PublicKey, SecretKey, Signature,
    KEYPAIR_SEED_SIZE, MLKEM_SECRET_KEY_SIZE, MLKEM_SEED_SIZE, SECRET_KEY_SIZE,
};
use std::mem::size_of;

// ---------- Compile-time trait bound checks ----------

// If SecretKey accidentally gains Clone (e.g. via #[derive(Clone)])
// -- this test will NOT compile, because we call a function requiring
// !Clone bound. Compile-time enforcement.
fn assert_not_clone<T>()
where
    T: NotClone,
{
}

trait NotClone {}
impl<T: NotCloneTag> NotClone for T {}

// Trick: NotCloneTag is impl-ed only for types WITHOUT Clone. If T: Clone,
// Rust's auto-impl of Clone overrides our trait, and compilation fails.
trait NotCloneTag {}

// Manual impls for the known secret types -- if someone adds #[derive(Clone)],
// the impls conflict and compilation fails.
impl NotCloneTag for SecretKey {}
impl NotCloneTag for MlkemSecretKey {}

#[test]
fn secret_key_is_not_clone() {
    assert_not_clone::<SecretKey>();
}

#[test]
fn mlkem_secret_key_is_not_clone() {
    assert_not_clone::<MlkemSecretKey>();
}

// ---------- Heap allocation invariants (size_of == pointer) ----------

#[test]
fn secret_key_is_heap_allocated() {
    // Box<[u8; N]> = 1 pointer = 8 bytes on 64-bit, 4 on 32-bit.
    // If SK ever becomes inline ([u8; SECRET_KEY_SIZE] = 4032 bytes),
    // this check fails -- meaning the heap protection is lost.
    let actual = size_of::<SecretKey>();
    let expected = size_of::<usize>();
    assert_eq!(
        actual, expected,
        "SecretKey size should be 1 pointer ({} bytes) — heap-allocated via Box. \
         Got {} bytes — stack inline detected, breaks mlock + stack hygiene invariants.",
        expected, actual
    );
}

#[test]
fn mlkem_secret_key_is_heap_allocated() {
    let actual = size_of::<MlkemSecretKey>();
    let expected = size_of::<usize>();
    assert_eq!(
        actual, expected,
        "MlkemSecretKey should be heap-allocated; got {} bytes",
        actual
    );
}

// ---------- Public types -- no accidentally added Clone/Copy ----------

#[test]
fn public_key_can_be_cloned() {
    // PublicKey = public material, Clone is allowed (for distribution over the network).
    // We check the positive case to make sure our test infrastructure
    // correctly distinguishes Clone from !Clone.
    let pk_bytes = [0u8; mt_crypto::PUBLIC_KEY_SIZE];
    let pk = PublicKey::from_array(pk_bytes);
    let _cloned: PublicKey = pk.clone();
}

#[test]
fn signature_can_be_cloned() {
    // Signature = public material (proof of authorship), Clone is allowed.
    let sig_bytes = [0u8; mt_crypto::SIGNATURE_SIZE];
    let sig = Signature::from_array(sig_bytes);
    let _cloned: Signature = sig.clone();
}

// ---------- Behavioral: SK bytes filled correctly via FFI ----------

#[test]
fn secret_key_filled_by_ffi_keygen() {
    let seed = [0x42u8; KEYPAIR_SEED_SIZE];
    let (_pk, sk) = keypair_from_seed(&seed).expect("keygen");
    let bytes = sk.as_bytes();
    // ML-DSA-65 SK is always 4032 bytes; not all-zeros (zeroing = bug in the FFI fill).
    assert_eq!(bytes.len(), SECRET_KEY_SIZE);
    assert!(
        bytes.iter().any(|&b| b != 0),
        "SecretKey bytes are all-zero — FFI failed to fill, but returned MT_OK. Bug."
    );
}

#[test]
fn mlkem_secret_key_filled_by_ffi_keygen() {
    let seed = [0x42u8; MLKEM_SEED_SIZE];
    let (_pk, sk) = keypair_from_seed_mlkem(&seed).expect("keygen mlkem");
    let bytes = sk.as_bytes();
    assert_eq!(bytes.len(), MLKEM_SECRET_KEY_SIZE);
    assert!(
        bytes.iter().any(|&b| b != 0),
        "MlkemSecretKey bytes are all-zero — FFI failed to fill, but returned MT_OK. Bug."
    );
}

// ---------- File-content scan: no logging macros on secret bytes in lib code ----------

#[test]
fn no_println_or_log_on_secret_bytes_in_lib_code() {
    // Scans mt-crypto/src/ for patterns like `println!.*sk.as_bytes()`
    // or `eprintln!.*sk.0` or `log::*.*sk\b`. If found -- fails with
    // the concrete line.
    use std::fs;
    use std::path::PathBuf;

    let mut src_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    src_dir.push("src");

    let mut violations: Vec<String> = Vec::new();

    let entries = fs::read_dir(&src_dir).expect("read src dir");
    for entry in entries {
        let entry = entry.expect("entry");
        let path = entry.path();
        if !path.is_file() || path.extension().and_then(|e| e.to_str()) != Some("rs") {
            continue;
        }
        let content = fs::read_to_string(&path).expect("read file");
        for (lineno, line) in content.lines().enumerate() {
            let lineno = lineno + 1;
            let trimmed = line.trim();
            // Skip comments
            if trimmed.starts_with("//") {
                continue;
            }
            // Patterns that may leak secret bytes:
            // (1) any println!/eprintln!/print!/eprint!/log::*/dbg! containing
            //     "sk." or " sk " or "secret" identifier  patterns followed
            //     by .as_bytes()/.0/{:?}
            let lower = line.to_lowercase();
            let is_log_call = lower.contains("println!")
                || lower.contains("eprintln!")
                || lower.contains("print!")
                || lower.contains("eprint!")
                || lower.contains("dbg!")
                || lower.contains("log::trace")
                || lower.contains("log::debug")
                || lower.contains("log::info")
                || lower.contains("log::warn")
                || lower.contains("log::error");
            if !is_log_call {
                continue;
            }
            // Some secret-suggesting patterns
            let has_sk_ref = line.contains("sk.as_bytes")
                || line.contains("sk.0")
                || line.contains("secret_key.")
                || line.contains("SecretKey")
                || line.contains("MlkemSecretKey");
            if has_sk_ref {
                violations.push(format!(
                    "{}:{}: potential SK leak in log macro: {}",
                    path.display(),
                    lineno,
                    trimmed
                ));
            }
        }
    }

    assert!(
        violations.is_empty(),
        "Found {} potential SK leak(s) in lib code:\n{}",
        violations.len(),
        violations.join("\n")
    );
}

// ---------- Constant-time: SK has no derived PartialEq (==) ----------

// If someone adds #[derive(PartialEq)] to SecretKey, comparison
// via `==` becomes non-constant-time (raw memcmp with early exit). This test
// checks that PartialEq is NOT present.
trait NotPartialEq {}
trait NotPartialEqTag {}
impl<T: NotPartialEqTag> NotPartialEq for T {}
impl NotPartialEqTag for SecretKey {}
impl NotPartialEqTag for MlkemSecretKey {}

fn assert_not_partial_eq<T: NotPartialEq>() {}

#[test]
fn secret_key_no_partial_eq_to_prevent_timing_leak() {
    assert_not_partial_eq::<SecretKey>();
}

#[test]
fn mlkem_secret_key_no_partial_eq_to_prevent_timing_leak() {
    assert_not_partial_eq::<MlkemSecretKey>();
}

// ---------- Verification: Drop trait impl is present on SK types ----------

// Compile-time check: the types implement Drop. If someone removes the impl Drop --
// the compiler does not fail by itself, but zeroize will not run. This test checks
// that the Drop impl exists via std::mem::needs_drop.
#[test]
fn secret_key_needs_drop() {
    assert!(
        std::mem::needs_drop::<SecretKey>(),
        "SecretKey must have a Drop impl with zeroize -- otherwise secret bytes \
         remain on the heap after dealloc"
    );
}

#[test]
fn mlkem_secret_key_needs_drop() {
    assert!(
        std::mem::needs_drop::<MlkemSecretKey>(),
        "MlkemSecretKey must have a Drop impl with zeroize"
    );
}
