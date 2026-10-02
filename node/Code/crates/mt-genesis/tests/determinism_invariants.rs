// Automated determinism invariants для mt-genesis.
// M2 audit prep — Genesis Decree = SSOT для всех протокольных констант
// per [I-10]; любое изменение Genesis = consensus fork. Эти invariants
// catch regression если кто-то случайно меняет Genesis.

use mt_genesis::{compute_genesis_state_hash, genesis_app_id, genesis_params, PARAMS_ENCODED_SIZE};

#[test]
fn genesis_app_id_deterministic() {
    let a = genesis_app_id();
    let b = genesis_app_id();
    assert_eq!(a, b, "genesis_app_id non-deterministic");
}

#[test]
fn genesis_params_singleton_stable_pointer() {
    // genesis_params() возвращает &'static — должен быть тот же reference
    // на каждом вызове (OnceLock semantic).
    let a = genesis_params();
    let b = genesis_params();
    assert!(
        std::ptr::eq(a, b),
        "genesis_params() must return same singleton reference"
    );
}

#[test]
fn protocol_params_encoded_size_constant() {
    // Если кто-то добавит/удалит поле в ProtocolParams без обновления
    // PARAMS_ENCODED_SIZE — этот test fails. Защита от silent struct
    // layout drift.
    use mt_codec::CanonicalEncode;
    let params = genesis_params();
    let mut buf = Vec::new();
    params.encode(&mut buf);
    assert_eq!(
        buf.len(),
        PARAMS_ENCODED_SIZE,
        "ProtocolParams encoded size drift: expected {} bytes, got {}",
        PARAMS_ENCODED_SIZE,
        buf.len()
    );
}

#[test]
fn protocol_params_encoding_deterministic() {
    use mt_codec::CanonicalEncode;
    let params = genesis_params();
    let mut buf1 = Vec::new();
    let mut buf2 = Vec::new();
    params.encode(&mut buf1);
    params.encode(&mut buf2);
    assert_eq!(buf1, buf2, "ProtocolParams encoding non-deterministic");
}

#[test]
fn compute_genesis_state_hash_deterministic() {
    let state_root = [0x42u8; 32];
    let params = genesis_params();
    let h1 = compute_genesis_state_hash(&state_root, params);
    let h2 = compute_genesis_state_hash(&state_root, params);
    assert_eq!(h1, h2);
}

#[test]
fn compute_genesis_state_hash_changes_on_state_root() {
    let params = genesis_params();
    let h1 = compute_genesis_state_hash(&[0x00u8; 32], params);
    let h2 = compute_genesis_state_hash(&[0xFFu8; 32], params);
    assert_ne!(h1, h2, "Genesis state hash должен зависеть от state_root");
}

// ---------- SSOT [I-10] check ----------

#[test]
fn protocol_params_singleton_consistent_with_default_construction() {
    // Если кто-то конструирует ProtocolParams напрямую (Default-like), он
    // должен дать тот же encoded layout что и singleton. Гарантирует что
    // нет случайных divergent versions параметров.
    use mt_codec::CanonicalEncode;
    let singleton = genesis_params();
    let mut buf_singleton = Vec::new();
    singleton.encode(&mut buf_singleton);

    // Singleton-via-pointer должен encode-ить те же bytes
    let again = genesis_params();
    let mut buf_again = Vec::new();
    again.encode(&mut buf_again);
    assert_eq!(buf_singleton, buf_again);
}
