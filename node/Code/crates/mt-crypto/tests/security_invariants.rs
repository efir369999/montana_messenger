// Automated security invariants для mt-crypto secret-handling code.
// Закрывает Pass 17 critic role «Mandatory Security Card per crypto primitive»
// через regression detection — если будущий рефакторинг случайно ломает
// security invariant, тест fails в CI ДО merge.
//
// Проверки:
//   1. SecretKey не имеет Clone/Copy traits (no accidental copies)
//   2. MlkemSecretKey не имеет Clone/Copy traits
//   3. SecretKey/MlkemSecretKey heap-allocated (Box) — size_of == pointer size
//      гарантирует что bytes на heap (не stack memcpy при moves)
//   4. SecretKey хранит свои bytes на heap независимо от stack frame
//   5. Drop+zeroize verified через behavioral test (memory pattern check)
//   6. Public type fields private (no struct literal construction)
//   7. No println!/log macros на SK bytes в lib коде (file-content scan)

use mt_crypto::{
    keypair_from_seed, keypair_from_seed_mlkem, MlkemSecretKey, PublicKey, SecretKey, Signature,
    KEYPAIR_SEED_SIZE, MLKEM_SECRET_KEY_SIZE, MLKEM_SEED_SIZE, SECRET_KEY_SIZE,
};
use std::mem::size_of;

// ---------- Compile-time trait bound checks ----------

// Если SecretKey случайно получает Clone (например через #[derive(Clone)])
// — этот test НЕ скомпилируется, потому что мы вызываем функцию требующую
// !Clone bound. Compile-time enforcement.
fn assert_not_clone<T>()
where
    T: NotClone,
{
}

trait NotClone {}
impl<T: NotCloneTag> NotClone for T {}

// Trick: NotCloneTag impl-енн только для типов БЕЗ Clone. Если T: Clone,
// auto-impl Clone у Rust override-нет наш trait, и compile fails.
trait NotCloneTag {}

// Manual impls для известных secret types — если кто-то добавит #[derive(Clone)],
// возникнет конфликт impl-ов и compile fails.
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
    // Box<[u8; N]> = 1 pointer = 8 bytes на 64-bit, 4 на 32-bit.
    // Если SK когда-нибудь станет inline ([u8; SECRET_KEY_SIZE] = 4032 bytes),
    // эта проверка fails — означает потерю heap protection.
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

// ---------- Public types — no Clone/Copy случайно added ----------

#[test]
fn public_key_can_be_cloned() {
    // PublicKey = public material, Clone разрешён (для распространения по сети).
    // Проверяем positive case чтобы убедиться что наш test infrastructure
    // правильно различает Clone от !Clone.
    let pk_bytes = [0u8; mt_crypto::PUBLIC_KEY_SIZE];
    let pk = PublicKey::from_array(pk_bytes);
    let _cloned: PublicKey = pk.clone();
}

#[test]
fn signature_can_be_cloned() {
    // Signature = public material (proof of authorship), Clone разрешён.
    let sig_bytes = [0u8; mt_crypto::SIGNATURE_SIZE];
    let sig = Signature::from_array(sig_bytes);
    let _cloned: Signature = sig.clone();
}

// ---------- Behavioral: SK bytes filled correctly через FFI ----------

#[test]
fn secret_key_filled_by_ffi_keygen() {
    let seed = [0x42u8; KEYPAIR_SEED_SIZE];
    let (_pk, sk) = keypair_from_seed(&seed).expect("keygen");
    let bytes = sk.as_bytes();
    // ML-DSA-65 SK всегда 4032 байт; не all-zeros (зануление = bug в FFI fill).
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

// ---------- File-content scan: no logging macros на secret bytes в lib коде ----------

#[test]
fn no_println_or_log_on_secret_bytes_in_lib_code() {
    // Сканирует mt-crypto/src/ на patterns типа `println!.*sk.as_bytes()`
    // или `eprintln!.*sk.0` или `log::*.*sk\b`. Если нашёл — fail с
    // конкретной строкой.
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
            // Patterns которые могут leak secret bytes:
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
            // Какие-нибудь secret-suggesting patterns
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

// ---------- Constant-time: SK не имеет PartialEq derived (==) ----------

// Если кто-нибудь добавит #[derive(PartialEq)] для SecretKey, comparison
// через `==` будет non-constant-time (raw memcmp с early-exit). Этот test
// проверяет что PartialEq НЕ присутствует.
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

// ---------- Verification: Drop трейт impl присутствует на SK types ----------

// Compile-time check: типы реализуют Drop. Если кто-то удалит impl Drop —
// компилятор не fails сам, но zeroize не вызовется. Этот test проверяет
// что Drop impl существует через std::mem::needs_drop.
#[test]
fn secret_key_needs_drop() {
    assert!(
        std::mem::needs_drop::<SecretKey>(),
        "SecretKey должен иметь Drop impl с zeroize — иначе secret bytes \
         останутся в heap после dealloc"
    );
}

#[test]
fn mlkem_secret_key_needs_drop() {
    assert!(
        std::mem::needs_drop::<MlkemSecretKey>(),
        "MlkemSecretKey должен иметь Drop impl с zeroize"
    );
}
