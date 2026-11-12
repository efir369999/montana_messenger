// spec, section "Cryptography" + "Cryptographic implementation → Primitive layer"
//
// Internals are delegated to mt-crypto-native (a thin FFI shim over OpenSSL 3.5.5 LTS
// vendored via openssl-src). The mt-crypto public API is byte-stable per [C-6] hard
// requirement #8 (pluggability via the mt-crypto API): the implementation library can be swapped
// without re-architecting the protocol.

use mt_crypto_native::{
    mt_keypair_from_seed_mldsa, mt_keypair_from_seed_mlkem, mt_mlkem_decapsulate,
    mt_mlkem_encapsulate, mt_sign_mldsa, mt_verify_mldsa, MT_ERR_INVALID_INPUT,
    MT_ERR_INVALID_PUBLIC_KEY, MT_ERR_INVALID_SECRET_KEY, MT_ERR_KEYGEN_FAILED,
    MT_ERR_OPENSSL_INIT, MT_ERR_PARAM_FETCH_FAILED, MT_ERR_PARAM_QUERY_FAILED,
    MT_ERR_PARAM_SIZE_MISMATCH, MT_ERR_SIGN_FAILED, MT_ERR_SIGN_LENGTH_MISMATCH, MT_OK,
};
use sha2::{Digest, Sha256};
use zeroize::Zeroize;

#[derive(Debug, Clone, Eq, PartialEq)]
pub enum CryptoError {
    InvalidInput,
    OpensslInit,
    KeygenFailed,
    SignFailed,
    SignLengthMismatch,
    ParamQueryFailed,
    ParamSizeMismatch,
    ParamFetchFailed,
    InvalidSecretKey,
    InvalidPublicKey,
    Other(i32),
}

impl CryptoError {
    fn from_code(c: i32) -> Self {
        match c {
            MT_ERR_INVALID_INPUT => Self::InvalidInput,
            MT_ERR_OPENSSL_INIT => Self::OpensslInit,
            MT_ERR_KEYGEN_FAILED => Self::KeygenFailed,
            MT_ERR_SIGN_FAILED => Self::SignFailed,
            MT_ERR_SIGN_LENGTH_MISMATCH => Self::SignLengthMismatch,
            MT_ERR_PARAM_QUERY_FAILED => Self::ParamQueryFailed,
            MT_ERR_PARAM_SIZE_MISMATCH => Self::ParamSizeMismatch,
            MT_ERR_PARAM_FETCH_FAILED => Self::ParamFetchFailed,
            MT_ERR_INVALID_SECRET_KEY => Self::InvalidSecretKey,
            MT_ERR_INVALID_PUBLIC_KEY => Self::InvalidPublicKey,
            other => Self::Other(other),
        }
    }
}

impl std::fmt::Display for CryptoError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::InvalidInput => write!(f, "invalid input"),
            Self::OpensslInit => write!(f, "OpenSSL init failed"),
            Self::KeygenFailed => write!(f, "keygen failed"),
            Self::SignFailed => write!(f, "sign failed"),
            Self::SignLengthMismatch => write!(f, "signature length mismatch"),
            Self::ParamQueryFailed => write!(f, "OSSL param query failed"),
            Self::ParamSizeMismatch => write!(f, "OSSL param size mismatch"),
            Self::ParamFetchFailed => write!(f, "OSSL param fetch failed"),
            Self::InvalidSecretKey => write!(f, "invalid ML-DSA secret key bytes"),
            Self::InvalidPublicKey => write!(f, "invalid ML-DSA public key bytes"),
            Self::Other(c) => write!(f, "crypto error code {}", c),
        }
    }
}

impl std::error::Error for CryptoError {}

pub const HASH_SIZE: usize = 32;
// spec: ML-DSA-65 (FIPS 204 level 3) — pubkey/secret/signature sizes
pub const PUBLIC_KEY_SIZE: usize = 1952;
pub const SECRET_KEY_SIZE: usize = 4032;
pub const SIGNATURE_SIZE: usize = 3309;
// spec: ML-DSA seed (FIPS 204 §3.1, ξ ∈ B32) for deterministic KeyGen_internal
pub const KEYPAIR_SEED_SIZE: usize = 32;
// spec: ML-KEM-768 (FIPS 203 security level 3) — pubkey/secret/seed sizes
pub const MLKEM_PUBLIC_KEY_SIZE: usize = 1184;
pub const MLKEM_SECRET_KEY_SIZE: usize = 2400;
pub const MLKEM_SEED_SIZE: usize = 64;
pub const MLKEM_CIPHERTEXT_SIZE: usize = 1088;
pub const MLKEM_SHARED_SECRET_SIZE: usize = 32;

pub type Hash32 = [u8; HASH_SIZE];

pub fn hash(domain: &[u8], parts: &[&[u8]]) -> Hash32 {
    let mut hasher = Sha256::new();
    hasher.update(domain);
    hasher.update([0u8]);
    for part in parts {
        hasher.update(part);
    }
    hasher.finalize().into()
}

pub fn sha256_raw(bytes: &[u8]) -> Hash32 {
    let mut hasher = Sha256::new();
    hasher.update(bytes);
    hasher.finalize().into()
}

#[derive(Clone, Eq, PartialEq, Debug)]
pub struct PublicKey([u8; PUBLIC_KEY_SIZE]);

impl PublicKey {
    pub fn from_array(bytes: [u8; PUBLIC_KEY_SIZE]) -> Self {
        Self(bytes)
    }

    pub fn from_slice(bytes: &[u8]) -> Option<Self> {
        if bytes.len() != PUBLIC_KEY_SIZE {
            return None;
        }
        let mut arr = [0u8; PUBLIC_KEY_SIZE];
        arr.copy_from_slice(bytes);
        Some(Self(arr))
    }

    pub fn as_bytes(&self) -> &[u8; PUBLIC_KEY_SIZE] {
        &self.0
    }
}

// SecretKey keeps the SK on the heap (Box), not the stack -- two advantages:
//   (a) the bytes live in a single heap location from construction to drop, with no
//       stack memcpy on moves (only a pointer copy)
//   (b) mlock is applied to the heap page once at construction;
//       the page is protected from swap-out for the whole life of the SK
// The public API returns &[u8; N] via as_bytes() (auto-deref), equivalent to
// the previous stack-based variant.
pub struct SecretKey(Box<[u8; SECRET_KEY_SIZE]>);

impl SecretKey {
    // Construction from a stack array: the bytes are taken by value (Rust move). After
    // copying to the heap, the stack copy is explicitly zeroized so the bytes do not remain in the
    // stack frame after return.
    pub fn from_array(mut bytes: [u8; SECRET_KEY_SIZE]) -> Self {
        let mut boxed = alloc_locked_secret_box(SECRET_KEY_SIZE);
        boxed.copy_from_slice(&bytes);
        bytes.zeroize();
        let arr_box: Box<[u8; SECRET_KEY_SIZE]> =
            boxed.try_into().expect("box size matches SECRET_KEY_SIZE");
        Self(arr_box)
    }

    pub fn from_slice(bytes: &[u8]) -> Option<Self> {
        if bytes.len() != SECRET_KEY_SIZE {
            return None;
        }
        let mut boxed = alloc_locked_secret_box(SECRET_KEY_SIZE);
        boxed.copy_from_slice(bytes);
        let arr_box: Box<[u8; SECRET_KEY_SIZE]> =
            boxed.try_into().expect("box size matches SECRET_KEY_SIZE");
        Some(Self(arr_box))
    }

    pub fn as_bytes(&self) -> &[u8; SECRET_KEY_SIZE] {
        &self.0
    }
}

impl Drop for SecretKey {
    fn drop(&mut self) {
        self.0.zeroize();
        unsafe {
            // SAFETY: self.0 — owned heap-allocated Box<[u8; SECRET_KEY_SIZE]>,
            // pointer valid for SECRET_KEY_SIZE bytes at the time of Drop. munlock
            // takes const void* and does not mutate the data. errno EINVAL
            // (if mlock was not applied in the fallback path) is ignored
            // as a no-op.
            libc::munlock(self.0.as_ptr() as *const libc::c_void, SECRET_KEY_SIZE);
        }
    }
}

// Best-effort heap allocation for secret bytes with mlock protection against swap.
// Under memory pressure the OS does not page locked pages out to the swap file.
// If mlock fails (RLIMIT_MEMLOCK exceeded on Linux, kern.maxlockedmem
// on macOS, or a process without CAP_IPC_LOCK on Linux) we return
// a non-locked Box. This is best-effort: secret bytes do not leak into swap on a
// successful mlock; on failure we rely on encrypted swap (FileVault
// macOS / LUKS Linux).
//
// TODO (F-5 closure pending mt-telemetry crate): runtime warning hook on
// mlock failure. The current implementation silently falls back to a non-locked Box
// without logging. Once the mt-telemetry crate exists -- emit a structured
// event `crypto.mlock.failure` with errno, so the operator sees that secret bytes
// may be in plaintext swap and decides (raise
// RLIMIT_MEMLOCK / enable FileVault). Without a telemetry hook, a log to stderr
// is read by nobody in production -- hence deferred until the telemetry framework.
fn alloc_locked_secret_box(size: usize) -> Box<[u8]> {
    let boxed = vec![0u8; size].into_boxed_slice();
    unsafe {
        // SAFETY: boxed — freshly allocated heap-buffer of `size` bytes
        // (vec![0u8; size].into_boxed_slice() guarantees a valid pointer +
        // exact size). mlock takes const void* and does not mutate the data;
        // operates on the page-aligned region containing the buffer. Return
        // code 0 = success, -1 = failure (errno set: ENOMEM when exceeding
        // RLIMIT_MEMLOCK, EPERM without CAP_IPC_LOCK on Linux,
        // kern.maxlockedmem on macOS). Best-effort: on failure we return a
        // non-locked Box and rely on encrypted swap (FileVault/LUKS).
        let _ = libc::mlock(boxed.as_ptr() as *const libc::c_void, size);
    }
    boxed
}

#[derive(Clone, Eq, PartialEq, Debug)]
pub struct Signature([u8; SIGNATURE_SIZE]);

impl Signature {
    pub fn from_array(bytes: [u8; SIGNATURE_SIZE]) -> Self {
        Self(bytes)
    }

    pub fn from_slice(bytes: &[u8]) -> Option<Self> {
        if bytes.len() != SIGNATURE_SIZE {
            return None;
        }
        let mut arr = [0u8; SIGNATURE_SIZE];
        arr.copy_from_slice(bytes);
        Some(Self(arr))
    }

    pub fn as_bytes(&self) -> &[u8; SIGNATURE_SIZE] {
        &self.0
    }
}

pub fn keypair_from_seed(
    seed: &[u8; KEYPAIR_SEED_SIZE],
) -> Result<(PublicKey, SecretKey), CryptoError> {
    let mut pk = [0u8; PUBLIC_KEY_SIZE];
    // SK alloc on the heap with mlock -- the FFI writes directly into the locked heap,
    // no stack temporary buffers with secret bytes.
    let mut sk_box = alloc_locked_secret_box(SECRET_KEY_SIZE);
    let r = unsafe {
        // SAFETY: seed/pk — valid pointers (stack); sk_box — heap-allocated
        // buffer of SECRET_KEY_SIZE bytes (mlock-protected). The sizes
        // match the mt-crypto-native FFI contract (seed =
        // MLDSA65_SEED_SIZE = 32, pk_out = MLDSA65_PUBKEY_SIZE = 1952,
        // sk_out = MLDSA65_SECRETKEY_SIZE = 4032). The C wrapper applies a
        // (void*)seed cast for the OpenSSL EVP API convention (see mt_crypto.c
        // keypair_from_seed_generic) -- read-only, does not mutate the seed bytes.
        mt_keypair_from_seed_mldsa(seed.as_ptr(), pk.as_mut_ptr(), sk_box.as_mut_ptr())
    };
    if r != MT_OK {
        // sk_box drops here, bytes are zeroized via Vec drop (no zeroize
        // on raw Box<[u8]>) — explicitly zeroize before drop:
        sk_box.zeroize();
        return Err(CryptoError::from_code(r));
    }
    let arr_box: Box<[u8; SECRET_KEY_SIZE]> =
        sk_box.try_into().expect("box size matches SECRET_KEY_SIZE");
    Ok((PublicKey(pk), SecretKey(arr_box)))
}

#[cfg(any(test, feature = "testing"))]
pub fn keypair() -> (PublicKey, SecretKey) {
    // Test-only helper. Entropy via `getrandom` -- the OS CSPRNG (on Linux:
    // getrandom(2) syscall, fallback to /dev/urandom; on macOS:
    // SecRandomCopyBytes; on Windows: BCryptGenRandom). This is a
    // production-grade entropy source, unlike the old implementation
    // via `SystemTime::now() + PID + stack address` (~50 bits of entropy,
    // theoretically brute-forceable).
    //
    // Gated by `#[cfg(any(test, feature = "testing"))]` -- even with a
    // CSPRNG source the function must not be in the production binary, because
    // real identity always goes through `keypair_from_seed` from HKDF-derived
    // master_seed (deterministic recovery flow).
    let mut seed = [0u8; KEYPAIR_SEED_SIZE];
    getrandom::getrandom(&mut seed).expect("OS CSPRNG (getrandom) unavailable");
    keypair_from_seed(&seed).expect("keypair: random seed cannot fail ML-DSA KeyGen")
}

pub fn sign(sk: &SecretKey, msg: &[u8]) -> Result<Signature, CryptoError> {
    let mut sig = [0u8; SIGNATURE_SIZE];
    let r = unsafe {
        // SAFETY: sk.0 is a valid pointer to an array of SECRET_KEY_SIZE bytes; msg is a
        // valid slice, msg.len() is correct; sig is a valid pointer to a buffer of
        // SIGNATURE_SIZE bytes. mt-crypto-native emits exactly SIGNATURE_SIZE
        // bytes of a deterministic ML-DSA signature (FIPS 204 Algorithm 2 deterministic
        // variant -- mandatory per [I-3] consensus determinism). The C wrapper
        // applies a (void*)sk cast in mldsa_pkey_from_secret for the OpenSSL EVP
        // convention -- read-only, does not mutate the SK bytes.
        mt_sign_mldsa(sk.0.as_ptr(), msg.as_ptr(), msg.len(), sig.as_mut_ptr())
    };
    if r != MT_OK {
        return Err(CryptoError::from_code(r));
    }
    Ok(Signature(sig))
}

pub fn verify(pk: &PublicKey, msg: &[u8], sig: &Signature) -> bool {
    let r = unsafe {
        // SAFETY: pk.0 / sig.0 are valid pointers to fixed-size arrays
        // (PUBLIC_KEY_SIZE / SIGNATURE_SIZE); msg is a valid slice
        // of length msg.len(). mt-crypto-native returns MT_OK on successful
        // verify, any other code means an invalid signature. The C wrapper applies a
        // (void*)pk cast in mldsa_pkey_from_public for the OpenSSL EVP convention
        // -- read-only, does not mutate the PK bytes.
        mt_verify_mldsa(pk.0.as_ptr(), msg.as_ptr(), msg.len(), sig.0.as_ptr())
    };
    r == MT_OK
}

// spec: ML-KEM-768 (FIPS 203 level 3) — encapsulation/decapsulation keys
// for message encryption (Application Layer). Used via
// deterministic from_seed(64B) for the recovery flow per HKDF-Expand
// per-role derivation ("mt-app-encryption-key").
#[derive(Clone, Eq, PartialEq, Debug)]
pub struct MlkemPublicKey([u8; MLKEM_PUBLIC_KEY_SIZE]);

impl MlkemPublicKey {
    pub fn from_array(bytes: [u8; MLKEM_PUBLIC_KEY_SIZE]) -> Self {
        Self(bytes)
    }

    pub fn from_slice(bytes: &[u8]) -> Option<Self> {
        if bytes.len() != MLKEM_PUBLIC_KEY_SIZE {
            return None;
        }
        let mut arr = [0u8; MLKEM_PUBLIC_KEY_SIZE];
        arr.copy_from_slice(bytes);
        Some(Self(arr))
    }

    pub fn as_bytes(&self) -> &[u8; MLKEM_PUBLIC_KEY_SIZE] {
        &self.0
    }
}

pub struct MlkemSecretKey(Box<[u8; MLKEM_SECRET_KEY_SIZE]>);

impl MlkemSecretKey {
    pub fn from_array(mut bytes: [u8; MLKEM_SECRET_KEY_SIZE]) -> Self {
        let mut boxed = alloc_locked_secret_box(MLKEM_SECRET_KEY_SIZE);
        boxed.copy_from_slice(&bytes);
        bytes.zeroize();
        let arr_box: Box<[u8; MLKEM_SECRET_KEY_SIZE]> = boxed
            .try_into()
            .expect("box size matches MLKEM_SECRET_KEY_SIZE");
        Self(arr_box)
    }

    pub fn from_slice(bytes: &[u8]) -> Option<Self> {
        if bytes.len() != MLKEM_SECRET_KEY_SIZE {
            return None;
        }
        let mut boxed = alloc_locked_secret_box(MLKEM_SECRET_KEY_SIZE);
        boxed.copy_from_slice(bytes);
        let arr_box: Box<[u8; MLKEM_SECRET_KEY_SIZE]> = boxed
            .try_into()
            .expect("box size matches MLKEM_SECRET_KEY_SIZE");
        Some(Self(arr_box))
    }

    pub fn as_bytes(&self) -> &[u8; MLKEM_SECRET_KEY_SIZE] {
        &self.0
    }
}

impl Drop for MlkemSecretKey {
    fn drop(&mut self) {
        self.0.zeroize();
        unsafe {
            // SAFETY: self.0 — owned heap-allocated Box<[u8;
            // MLKEM_SECRET_KEY_SIZE]>, pointer valid for
            // MLKEM_SECRET_KEY_SIZE bytes at the time of Drop. munlock does not mutate
            // the data. errno EINVAL with no prior mlock is ignored (no-op
            // semantics in the fallback path).
            libc::munlock(
                self.0.as_ptr() as *const libc::c_void,
                MLKEM_SECRET_KEY_SIZE,
            );
        }
    }
}

pub fn keypair_from_seed_mlkem(
    seed: &[u8; MLKEM_SEED_SIZE],
) -> Result<(MlkemPublicKey, MlkemSecretKey), CryptoError> {
    let mut pk = [0u8; MLKEM_PUBLIC_KEY_SIZE];
    let mut sk_box = alloc_locked_secret_box(MLKEM_SECRET_KEY_SIZE);
    let r = unsafe {
        // SAFETY: seed/pk — valid pointers (stack); sk_box — heap-allocated
        // buffer of MLKEM_SECRET_KEY_SIZE bytes (mlock-protected). The sizes
        // match the mt-crypto-native FFI contract (seed =
        // MLKEM768_SEED_SIZE = 64, pk_out = MLKEM768_PUBKEY_SIZE = 1184,
        // sk_out = MLKEM768_SECRETKEY_SIZE = 2400). FIPS 203
        // ML-KEM.KeyGen_internal(d, z) deterministic with d=seed[0..32],
        // z=seed[32..64]. The C wrapper applies a (void*)seed cast for the OpenSSL
        // EVP API convention -- read-only, does not mutate the seed bytes.
        mt_keypair_from_seed_mlkem(seed.as_ptr(), pk.as_mut_ptr(), sk_box.as_mut_ptr())
    };
    if r != MT_OK {
        sk_box.zeroize();
        return Err(CryptoError::from_code(r));
    }
    let arr_box: Box<[u8; MLKEM_SECRET_KEY_SIZE]> = sk_box
        .try_into()
        .expect("box size matches MLKEM_SECRET_KEY_SIZE");
    Ok((MlkemPublicKey(pk), MlkemSecretKey(arr_box)))
}

/// ML-KEM-768 ciphertext (FIPS 203 §6.2 output of encapsulate).
#[derive(Debug, Clone, Eq, PartialEq)]
pub struct MlkemCiphertext([u8; MLKEM_CIPHERTEXT_SIZE]);

impl MlkemCiphertext {
    pub fn from_array(bytes: [u8; MLKEM_CIPHERTEXT_SIZE]) -> Self {
        MlkemCiphertext(bytes)
    }

    pub fn from_slice(bytes: &[u8]) -> Option<Self> {
        if bytes.len() != MLKEM_CIPHERTEXT_SIZE {
            return None;
        }
        let mut arr = [0u8; MLKEM_CIPHERTEXT_SIZE];
        arr.copy_from_slice(bytes);
        Some(MlkemCiphertext(arr))
    }

    pub fn as_bytes(&self) -> &[u8; MLKEM_CIPHERTEXT_SIZE] {
        &self.0
    }
}

/// ML-KEM-768 shared-secret output. Secret material; held briefly during
/// handshake then derived into per-direction session keys via HKDF and zeroized.
pub struct MlkemSharedSecret(Box<[u8; MLKEM_SHARED_SECRET_SIZE]>);

impl MlkemSharedSecret {
    pub fn as_bytes(&self) -> &[u8; MLKEM_SHARED_SECRET_SIZE] {
        &self.0
    }

    pub fn into_bytes(mut self) -> [u8; MLKEM_SHARED_SECRET_SIZE] {
        let out = *self.0;
        self.0.zeroize();
        out
    }
}

impl Drop for MlkemSharedSecret {
    fn drop(&mut self) {
        self.0.zeroize();
    }
}

/// ML-KEM-768 encapsulate (FIPS 203 §6.2). Given a recipient public key,
/// generate a fresh ciphertext and the shared secret. The ciphertext is
/// transmitted to the recipient; the shared secret is the symmetric key
/// for the Noise_PQ handshake.
pub fn mlkem_encapsulate(
    pk: &MlkemPublicKey,
) -> Result<(MlkemCiphertext, MlkemSharedSecret), CryptoError> {
    let mut ct = [0u8; MLKEM_CIPHERTEXT_SIZE];
    let mut ss_box = alloc_locked_secret_box(MLKEM_SHARED_SECRET_SIZE);
    let r = unsafe {
        // SAFETY: pk — valid 1184-byte input; ct — 1088-byte output buffer;
        // ss_box — 32-byte heap-allocated mlock-protected buffer matching
        // MT_MLKEM768_SS_SIZE from the C FFI contract.
        mt_mlkem_encapsulate(pk.as_bytes().as_ptr(), ct.as_mut_ptr(), ss_box.as_mut_ptr())
    };
    if r != MT_OK {
        ss_box.zeroize();
        return Err(CryptoError::from_code(r));
    }
    let arr_box: Box<[u8; MLKEM_SHARED_SECRET_SIZE]> = ss_box
        .try_into()
        .expect("box size matches MLKEM_SHARED_SECRET_SIZE");
    Ok((MlkemCiphertext(ct), MlkemSharedSecret(arr_box)))
}

/// ML-KEM-768 decapsulate (FIPS 203 §6.3) with FIPS 203 implicit-rejection
/// semantics: a malformed ciphertext yields a pseudo-random shared secret
/// indistinguishable from a valid one. The downstream handshake MUST verify
/// an identity-bound MAC or signature to detect this case.
pub fn mlkem_decapsulate(
    sk: &MlkemSecretKey,
    ct: &MlkemCiphertext,
) -> Result<MlkemSharedSecret, CryptoError> {
    let mut ss_box = alloc_locked_secret_box(MLKEM_SHARED_SECRET_SIZE);
    let r = unsafe {
        // SAFETY: sk.as_bytes() — 2400-byte heap-locked secret; ct — 1088-byte
        // input; ss_box — 32-byte heap-allocated mlock-protected buffer.
        mt_mlkem_decapsulate(
            sk.as_bytes().as_ptr(),
            ct.as_bytes().as_ptr(),
            ss_box.as_mut_ptr(),
        )
    };
    if r != MT_OK {
        ss_box.zeroize();
        return Err(CryptoError::from_code(r));
    }
    let arr_box: Box<[u8; MLKEM_SHARED_SECRET_SIZE]> = ss_box
        .try_into()
        .expect("box size matches MLKEM_SHARED_SECRET_SIZE");
    Ok(MlkemSharedSecret(arr_box))
}

/// Postquantum sealing to the recipient: ML-KEM-768 encapsulate +
/// ChaCha20-Poly1305 AEAD. Format: ct(1088) ‖ AEAD(plaintext)+tag(16). Only the holder of the
/// ML-KEM secret key can decrypt -- the courier/transit is crypto-blind to the content (recv_id, etc.).
/// ss is fresh for every encapsulate, so the key is unique per message and a fixed nonce=0 is safe.
pub fn seal_to(recipient_pk: &MlkemPublicKey, plaintext: &[u8]) -> Result<Vec<u8>, CryptoError> {
    use chacha20poly1305::aead::Aead;
    use chacha20poly1305::{ChaCha20Poly1305, KeyInit, Nonce};
    let (ct, ss) = mlkem_encapsulate(recipient_pk)?;
    let cipher =
        ChaCha20Poly1305::new_from_slice(ss.as_bytes()).map_err(|_| CryptoError::InvalidInput)?;
    let nonce = Nonce::from_slice(&[0u8; 12]);
    let aead = cipher
        .encrypt(nonce, plaintext)
        .map_err(|_| CryptoError::InvalidInput)?;
    let mut out = Vec::with_capacity(MLKEM_CIPHERTEXT_SIZE + aead.len());
    out.extend_from_slice(ct.as_bytes());
    out.extend_from_slice(&aead);
    Ok(out)
}

/// Unseal a sealed blob (ct ‖ AEAD) by the holder of the ML-KEM secret key. The AEAD tag guarantees
/// integrity; a wrong key / corruption yields Err (the transit's crypto-blindness is absolute).
pub fn open_from(recipient_sk: &MlkemSecretKey, sealed: &[u8]) -> Result<Vec<u8>, CryptoError> {
    use chacha20poly1305::aead::Aead;
    use chacha20poly1305::{ChaCha20Poly1305, KeyInit, Nonce};
    if sealed.len() < MLKEM_CIPHERTEXT_SIZE + 16 {
        return Err(CryptoError::InvalidInput);
    }
    let ct = MlkemCiphertext::from_slice(&sealed[..MLKEM_CIPHERTEXT_SIZE])
        .ok_or(CryptoError::InvalidInput)?;
    let ss = mlkem_decapsulate(recipient_sk, &ct)?;
    let cipher =
        ChaCha20Poly1305::new_from_slice(ss.as_bytes()).map_err(|_| CryptoError::InvalidInput)?;
    let nonce = Nonce::from_slice(&[0u8; 12]);
    cipher
        .decrypt(nonce, &sealed[MLKEM_CIPHERTEXT_SIZE..])
        .map_err(|_| CryptoError::InvalidInput)
}

#[repr(u16)]
#[derive(Copy, Clone, Eq, PartialEq, Debug)]
pub enum SuiteId {
    // spec: "Active scheme at launch: ML-DSA-65", suite_id = 0x0001
    Mldsa65 = 0x0001,
}

pub fn suite_id_from_u16(v: u16) -> Option<SuiteId> {
    match v {
        0x0001 => Some(SuiteId::Mldsa65),
        _ => None,
    }
}

#[derive(Debug, Clone, Eq, PartialEq)]
pub enum CryptoSelfTestError {
    KeyGenSizeMismatch,
    KeyGenDeterminismFailure,
    SignVerifyFailure,
    KatPubkeyMismatch,
    KatSignatureMismatch,
    PrimitiveError(CryptoError),
}

impl From<CryptoError> for CryptoSelfTestError {
    fn from(e: CryptoError) -> Self {
        Self::PrimitiveError(e)
    }
}

// KAT 1 binding fingerprints — ML-DSA-65.KeyGen(seed=[0x00; 32]) per spec
// "KeyGen output binding vectors". Full pk/sk are checked via
// `crates/mt-mnemonic/tests/keygen_vectors.rs::kat_1_mldsa_seed_zero` —
// here the SHA-256 fingerprint is compared (collision resistance guarantees
// byte-equivalence). Cross-implementation conformance: identical pk/sk
// ⇔ identical SHA-256 → sufficient for the determinism check.
pub const EXPECTED_KAT_1_PK_SHA256: [u8; HASH_SIZE] = [
    0x08, 0x5b, 0xa3, 0x80, 0xff, 0x38, 0x6d, 0xd5, 0x2e, 0x42, 0x34, 0x9c, 0x6e, 0xb8, 0x84, 0x89,
    0xd6, 0x05, 0x8e, 0xa5, 0x41, 0xa4, 0xe3, 0xfb, 0x0d, 0xce, 0x9a, 0x3f, 0xd1, 0xf7, 0xa9, 0x11,
];
pub const EXPECTED_KAT_1_SK_SHA256: [u8; HASH_SIZE] = [
    0xcf, 0xcb, 0x5e, 0x7e, 0xdf, 0x43, 0x48, 0xf7, 0x12, 0xb7, 0x00, 0x2b, 0x05, 0x53, 0xd2, 0x89,
    0x29, 0x85, 0x69, 0x36, 0xc9, 0x8e, 0x4a, 0xdf, 0x17, 0x2e, 0x51, 0xd5, 0xc9, 0x93, 0x42, 0x62,
];

pub fn self_test() -> Result<(), CryptoSelfTestError> {
    // Structural invariants + determinism + sign/verify roundtrip
    let seed = [0x42u8; KEYPAIR_SEED_SIZE];
    let (pk1, sk1) = keypair_from_seed(&seed)?;
    if pk1.as_bytes().len() != PUBLIC_KEY_SIZE || sk1.as_bytes().len() != SECRET_KEY_SIZE {
        return Err(CryptoSelfTestError::KeyGenSizeMismatch);
    }
    let (pk2, sk2) = keypair_from_seed(&seed)?;
    if pk1.as_bytes() != pk2.as_bytes() || sk1.as_bytes() != sk2.as_bytes() {
        return Err(CryptoSelfTestError::KeyGenDeterminismFailure);
    }
    let msg = b"mt-crypto self-test message";
    let sig = sign(&sk1, msg)?;
    if !verify(&pk1, msg, &sig) {
        return Err(CryptoSelfTestError::SignVerifyFailure);
    }

    // KAT 1 byte-exact conformance: ML-DSA-65.KeyGen([0x00; 32])
    let kat_seed = [0x00u8; KEYPAIR_SEED_SIZE];
    let (kat_pk, kat_sk) = keypair_from_seed(&kat_seed)?;
    let pk_hash = sha256_raw(kat_pk.as_bytes());
    if pk_hash != EXPECTED_KAT_1_PK_SHA256 {
        return Err(CryptoSelfTestError::KatPubkeyMismatch);
    }
    let sk_hash = sha256_raw(kat_sk.as_bytes());
    if sk_hash != EXPECTED_KAT_1_SK_SHA256 {
        return Err(CryptoSelfTestError::KatSignatureMismatch);
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    #[test]
    fn seal_open_roundtrip_and_wrong_key_fails() {
        let (pk, sk) = keypair_from_seed_mlkem(&[0x11u8; MLKEM_SEED_SIZE]).unwrap();
        let pt = b"recv_id-and-subscribe-secret";
        let sealed = seal_to(&pk, pt).unwrap();
        assert!(sealed.len() >= MLKEM_CIPHERTEXT_SIZE + 16);
        assert_eq!(open_from(&sk, &sealed).unwrap(), pt);
        // another party's ML-KEM key cannot open it -- the courier/transit is crypto-blind
        let (_pk2, sk2) = keypair_from_seed_mlkem(&[0x22u8; MLKEM_SEED_SIZE]).unwrap();
        assert!(open_from(&sk2, &sealed).is_err());
        // corrupted AEAD -- caught by the tag
        let mut bad = sealed.clone();
        *bad.last_mut().unwrap() ^= 1;
        assert!(open_from(&sk, &bad).is_err());
    }

    use super::*;

    #[test]
    fn sizes_match_spec() {
        assert_eq!(HASH_SIZE, 32);
        assert_eq!(PUBLIC_KEY_SIZE, 1952);
        assert_eq!(SECRET_KEY_SIZE, 4032);
        assert_eq!(SIGNATURE_SIZE, 3309);
        assert_eq!(KEYPAIR_SEED_SIZE, 32);
    }

    #[test]
    fn hash_determinism() {
        let a = hash(b"mt-account", &[b"hello"]);
        let b = hash(b"mt-account", &[b"hello"]);
        assert_eq!(a, b);
    }

    #[test]
    fn hash_different_domain_different_output() {
        let a = hash(b"mt-account", &[b"hello"]);
        let b = hash(b"mt-node", &[b"hello"]);
        assert_ne!(a, b);
    }

    #[test]
    fn hash_different_input_different_output() {
        let a = hash(b"mt-account", &[b"hello"]);
        let b = hash(b"mt-account", &[b"world"]);
        assert_ne!(a, b);
    }

    #[test]
    fn hash_nist_vector_abc() {
        let expected = [
            0xBA, 0x78, 0x16, 0xBF, 0x8F, 0x01, 0xCF, 0xEA, 0x41, 0x41, 0x40, 0xDE, 0x5D, 0xAE,
            0x22, 0x23, 0xB0, 0x03, 0x61, 0xA3, 0x96, 0x17, 0x7A, 0x9C, 0xB4, 0x10, 0xFF, 0x61,
            0xF2, 0x00, 0x15, 0xAD,
        ];
        assert_eq!(sha256_raw(b"abc"), expected);
    }

    #[test]
    fn hash_parts_concatenate() {
        let a = hash(b"mt-op", &[b"aa", b"bb", b"cc"]);
        let b = hash(b"mt-op", &[b"aabbcc"]);
        assert_eq!(a, b);
    }

    #[test]
    fn keypair_correct_sizes() {
        let (pk, sk) = keypair();
        assert_eq!(pk.as_bytes().len(), PUBLIC_KEY_SIZE);
        assert_eq!(sk.as_bytes().len(), SECRET_KEY_SIZE);
    }

    #[test]
    fn keypair_from_seed_deterministic() {
        let seed = [0x37u8; KEYPAIR_SEED_SIZE];
        let (pk1, sk1) = keypair_from_seed(&seed).expect("keygen");
        let (pk2, sk2) = keypair_from_seed(&seed).expect("keygen");
        assert_eq!(pk1.as_bytes(), pk2.as_bytes());
        assert_eq!(sk1.as_bytes(), sk2.as_bytes());
    }

    #[test]
    fn keypair_from_seed_different_seeds_different_keys() {
        let s1 = [0x11u8; KEYPAIR_SEED_SIZE];
        let s2 = [0x22u8; KEYPAIR_SEED_SIZE];
        let (pk1, _) = keypair_from_seed(&s1).expect("keygen s1");
        let (pk2, _) = keypair_from_seed(&s2).expect("keygen s2");
        assert_ne!(pk1.as_bytes(), pk2.as_bytes());
    }

    #[test]
    fn keypair_returns_different_keys_on_consecutive_calls() {
        let (pk1, _) = keypair();
        let (pk2, _) = keypair();
        // Random seed-based -- two consecutive calls return different keys
        assert_ne!(pk1.as_bytes(), pk2.as_bytes());
    }

    #[test]
    fn sign_verify_roundtrip() {
        let (pk, sk) = keypair();
        let msg = b"Montana protocol test message";
        let sig = sign(&sk, msg).expect("sign");
        assert_eq!(sig.as_bytes().len(), SIGNATURE_SIZE);
        assert!(verify(&pk, msg, &sig));
    }

    #[test]
    fn sign_deterministic() {
        let seed = [0x55u8; KEYPAIR_SEED_SIZE];
        let (_, sk) = keypair_from_seed(&seed).expect("keygen");
        let msg = b"determinism check";
        let s1 = sign(&sk, msg).expect("sign s1");
        let s2 = sign(&sk, msg).expect("sign s2");
        assert_eq!(s1.as_bytes(), s2.as_bytes());
    }

    #[test]
    fn verify_rejects_mutated_message() {
        let (pk, sk) = keypair();
        let msg = b"original";
        let sig = sign(&sk, msg).expect("sign");
        assert!(!verify(&pk, b"mutated", &sig));
    }

    #[test]
    fn verify_rejects_mutated_signature() {
        let (pk, sk) = keypair();
        let msg = b"payload";
        let sig = sign(&sk, msg).expect("sign");
        let mut bad = *sig.as_bytes();
        bad[0] ^= 0xFF;
        bad[100] ^= 0xAA;
        let bad_sig = Signature::from_array(bad);
        assert!(!verify(&pk, msg, &bad_sig));
    }

    #[test]
    fn verify_rejects_wrong_public_key() {
        let (_, sk) = keypair();
        let (other_pk, _) = keypair();
        let msg = b"cross-key test";
        let sig = sign(&sk, msg).expect("sign");
        assert!(!verify(&other_pk, msg, &sig));
    }

    #[test]
    fn public_key_from_slice_rejects_wrong_size() {
        assert!(PublicKey::from_slice(&[0u8; PUBLIC_KEY_SIZE - 1]).is_none());
        assert!(PublicKey::from_slice(&[0u8; PUBLIC_KEY_SIZE + 1]).is_none());
        assert!(PublicKey::from_slice(&[0u8; PUBLIC_KEY_SIZE]).is_some());
    }

    #[test]
    fn secret_key_from_slice_rejects_wrong_size() {
        assert!(SecretKey::from_slice(&[0u8; SECRET_KEY_SIZE - 1]).is_none());
        assert!(SecretKey::from_slice(&[0u8; SECRET_KEY_SIZE]).is_some());
    }

    #[test]
    fn signature_from_slice_rejects_wrong_size() {
        assert!(Signature::from_slice(&[0u8; SIGNATURE_SIZE - 1]).is_none());
        assert!(Signature::from_slice(&[0u8; SIGNATURE_SIZE + 1]).is_none());
        assert!(Signature::from_slice(&[0u8; SIGNATURE_SIZE]).is_some());
    }

    #[test]
    fn suite_id_mldsa65_value() {
        assert_eq!(SuiteId::Mldsa65 as u16, 0x0001);
    }

    #[test]
    fn suite_id_from_u16_valid() {
        assert_eq!(suite_id_from_u16(0x0001), Some(SuiteId::Mldsa65));
    }

    #[test]
    fn suite_id_from_u16_invalid() {
        assert_eq!(suite_id_from_u16(0x0000), None);
        assert_eq!(suite_id_from_u16(0x0002), None);
        assert_eq!(suite_id_from_u16(0xFFFF), None);
    }

    #[test]
    fn public_key_roundtrip_from_array_to_bytes() {
        let (pk, _) = keypair();
        let bytes = *pk.as_bytes();
        let reconstructed = PublicKey::from_array(bytes);
        assert_eq!(pk, reconstructed);
    }

    #[test]
    fn self_test_passes() {
        assert_eq!(self_test(), Ok(()));
    }
}
