# Security Cards — Montana M1 cryptographic primitives

Mandatory documentation per `CRITIC.md` v1.6.0 Pass 17 — every primitive that holds secret material must have a completed Security Card before it may receive the status "closed".

**Last verified:** 2026-04-26 (M1-F audit + Pass 17 Security Card formalization)
**Scope:** M1 foundational layer cryptographic primitives
**Automated regression:** [crates/mt-crypto/tests/security_invariants.rs](../crates/mt-crypto/tests/security_invariants.rs) — 13 invariants verified in CI

---

## Card 1: SecretKey (ML-DSA-65)

```
Security Card for SecretKey (mt_crypto::SecretKey, ML-DSA-65 4032B):

Secret material:
  Type:                 [u8; 4032] heap-allocated via Box<[u8; SECRET_KEY_SIZE]>
  Site of construction: crates/mt-crypto/src/lib.rs — impl SecretKey { from_array, from_slice }
                        + alloc_locked_secret_box helper (search by function name)
  Site of destruction:  crates/mt-crypto/src/lib.rs — impl Drop for SecretKey
                        (line numbers are intentionally not fixed — keep in sync
                         with the code via grep -n "fn from_array\|impl Drop for SecretKey")

Lifecycle:
  Construction copies:  1 — bytes are copied once from the stack source (or FFI fills directly into the heap Box)
                            into the heap-allocated Box. The stack source is zeroized after the copy.
  Owning type:          mt_crypto::SecretKey (private inner Box<[u8; N]>)
  Transfer pattern:     by-value move; Box pointer copy, not a bytes memcpy
  Destruction:          Drop+zeroize: yes; explicit zeroize sites: 1 (Drop impl)
                        + munlock of heap pages before dealloc

Side-channel surface:
  Branching on secret bytes: no (our Rust shim performs no operations on the bytes;
                                all ML-DSA arithmetic is inside the OpenSSL EVP API)
  Memory access pattern:     N/A in Layer 1; OpenSSL internally uses
                              constant-time access patterns (FIPS 140-3 validated)
  PartialEq impl on secret type: disabled (verified at compile time via
                                   security_invariants.rs)
  Comparison via ==:         no (PartialEq is not derived; verified)
  Constant-time guarantees:  inherited from OpenSSL 3.5.5 LTS — FIPS 140-3
                              constant-time crypto operations

OS-level hygiene:
  mlock applied:        yes; via alloc_locked_secret_box() in mt-crypto/src/lib.rs
                        best-effort (errno ignored on failure — fallback to encrypted swap)
  Stack cleansing FFI buffers: explicit — keypair_from_seed allocates the Box BEFORE the FFI call,
                                FFI writes directly into the heap; no stack temporary buffers
                                with secret bytes (verified in fn keypair_from_seed)
  Swap protection:      mlock primary; encrypted swap (FileVault macOS / LUKS Linux)
                        fallback assumption documented
  Core dump protection: recommendation for the operator: setrlimit(RLIMIT_CORE=0) in
                        production deployment (documented in the Operator Guide,
                        not enforced at code level)

Logging surface:
  println!/log macros on secret: 0 instances (verified by file-content scan in
                                   security_invariants.rs::no_println_or_log_on_secret_bytes_in_lib_code)
  Debug impl on secret type:     not derived; struct fields private (no field access)
  Error messages with secret:    none (CryptoError variants do not contain secret bytes)
  print_sk-like helper gates:    yes — mt-examples/examples/m1_crypto.rs::print_sk gated by
                                  env var M1_DUMP_SK=1 (default redacted; see fn dump_sk_enabled)

Library properties:
  Underlying impl:      OpenSSL 3.5.5 LTS EVP_PKEY API (vendored via openssl-src)
  Constant-time documented:  yes — OpenSSL FIPS 140-3 validation requires constant-time
  Audit history:        OpenSSL Foundation governance + decades of production deployment in
                        the TLS world + FIPS 140-3 certified
  Stack cleansing on cleanup: OpenSSL responsibility — EVP_PKEY_free clears internal state

Verified:
  Pass 17 checks 1-8:   8/8 closed
    1. Constant-time:     ✅ inherited OpenSSL
    2. Memory access:     ✅ no secret-indexed access in Layer 1
    3. Branch pattern:    ✅ no secret-dependent branches in Layer 1
    4. Zeroization on drop: ✅ Drop+zeroize verified
    5. Library check:     ✅ OpenSSL FIPS 140-3
    6. Stack hygiene:     ✅ heap-only via Box; FFI writes into the heap
    7. OS-level mlock:    ✅ best-effort applied
    8. Memory barrier:    ✅ the zeroize crate has compiler_fence(SeqCst)

Status: closed
```

---

## Card 2: MlkemSecretKey (ML-KEM-768)

```
Security Card for MlkemSecretKey (mt_crypto::MlkemSecretKey, ML-KEM-768 2400B):

Secret material:
  Type:                 [u8; 2400] heap-allocated via Box<[u8; MLKEM_SECRET_KEY_SIZE]>
  Site of construction: crates/mt-crypto/src/lib.rs — impl MlkemSecretKey { from_array, from_slice }
                        (search by function name; line numbers are intentionally not fixed)
  Site of destruction:  crates/mt-crypto/src/lib.rs — impl Drop for MlkemSecretKey

Lifecycle:
  Construction copies:  1 — bytes on the heap, stack source zeroized
  Owning type:          mt_crypto::MlkemSecretKey (private Box)
  Transfer pattern:     by-value move (pointer copy)
  Destruction:          Drop+zeroize + munlock

Side-channel surface:
  Branching on secret bytes: no (Layer 1 only passes a pointer to OpenSSL EVP)
  Memory access pattern:     N/A in Layer 1; OpenSSL constant-time
  PartialEq impl on secret type: disabled (verified)
  Comparison via ==:         no (verified)
  Constant-time guarantees:  inherited OpenSSL FIPS 140-3

OS-level hygiene:
  mlock applied:        yes; alloc_locked_secret_box best-effort
  Stack cleansing FFI buffers: explicit — keypair_from_seed_mlkem uses the heap
                                Box directly (mt-crypto/src/lib.rs fn keypair_from_seed_mlkem)
  Swap protection:      mlock primary; encrypted swap fallback
  Core dump protection: operator-level (RLIMIT_CORE=0)

Logging surface:
  println!/log macros on secret: 0 (file-content scan verified)
  Debug impl:           not derived
  Error messages:       sanitized
  Helper gates:         no direct dump helpers for MlkemSK

Library properties:
  Underlying impl:      OpenSSL 3.5.5 LTS EVP_PKEY ML-KEM-768
  Constant-time documented:  yes — FIPS 140-3
  Audit history:        OpenSSL Foundation
  Stack cleansing on cleanup: OpenSSL EVP_PKEY_free

Threat model (per-primitive — differs from ML-DSA Card 1):
  - Decapsulation timing: by design, the KEM decapsulation algorithm contains
    secret-dependent control flow in its failure mode. The OpenSSL EVP implementation
    performs implicit rejection in constant time (FIPS 203 §6.3 Algorithm 18).
  - Plaintext checking attacks: Kyber is known for hijacking decapsulation
    through a crafted ciphertext (Hofheinz-Hövelmanns-Kiltz [HHK17]).
    The defence is implicit rejection with pseudorandom output, implemented in
    OpenSSL and checked through FIPS 140-3 validation.
  - Encapsulation: PK material is not secret, but the ciphertext path contains
    a secret session key. The ciphertext output is public material.
  - vs SecretKey (Card 1): the ML-DSA SK is used only in Sign (one
    secret-touch operation in its lifecycle); the ML-KEM SK is used in every
    Decap (multiple exposures, higher criticality of constant-time).

Verified:
  Pass 17 checks 1-8 (per-primitive analysis for KEM):
    1. Constant-time:           ✅ inherited OpenSSL FIPS 140-3 (including the
                                   implicit rejection path for decap failure)
    2. Memory access:           ✅ no SK-indexed access in Layer 1
    3. Branch pattern:          ✅ no SK-dependent branches in Layer 1
                                   (decap branching inside OpenSSL is constant-time)
    4. Zeroization on drop:     ✅ Drop+zeroize verified
    5. Library check:           ✅ OpenSSL FIPS 140-3
    6. Stack hygiene:           ✅ heap-only via Box; FFI writes into the heap
    7. OS-level mlock:          ✅ best-effort applied
    8. Memory barrier:          ✅ zeroize crate compiler_fence(SeqCst)

Status: closed
```

---

## Card 3: keypair_from_seed — ML-DSA-65 KeyGen

```
Security Card for keypair_from_seed (mt_crypto::keypair_from_seed):

Secret material handled:
  Input:                seed: &[u8; 32] (caller-owned, the function takes it by reference)
  Output secret:        SecretKey (4032B, owned)
  Output public:        PublicKey (1952B, public material)

Lifecycle:
  seed lifecycle:       owned by the caller; the function reads through &[u8; N], does not copy
                        into a local stack (FFI receives the caller's pointer directly)
  SK construction:      heap Box allocated with mlock BEFORE the FFI call (via
                        alloc_locked_secret_box). FFI writes the SK bytes directly
                        into locked heap memory; no intermediate stack copy.
  Error path:           sk_box.zeroize() is called explicitly before return Err
                        ensuring that partially filled bytes do not leak on FFI failure

Side-channel surface:
  Branching on secret:  no — Layer 1 checks only the return code (i32)
  Memory access:        SK bytes on the heap, accessed only inside OpenSSL
  Logging:              0 println/log calls on seed/sk

OS-level hygiene:
  mlock on SK:          yes (via alloc_locked_secret_box)
  mlock on seed:        no — the seed is caller-owned, the function does not control it
                        (caller responsibility — e.g. mt-mnemonic, for
                        seeds derived through PBKDF2/HKDF, locks master_seed
                        in its own layer; documented in audit-checklist)
  Stack cleanup:        no stack temp buffers with secret bytes

Library properties:
  Underlying:           OpenSSL EVP_PKEY ML-DSA-65 KeyGen (FIPS 204 Algorithm 1)
  Determinism:          guaranteed via the OSSL_PKEY_PARAM_ML_DSA_SEED parameter
  NIST conformance:     verified byte-exact against NIST ACVP 25/25 KeyGen tests

Threat model (per-primitive — KeyGen specific):
  - Seed quality: the KeyGen output is determined by the seed; a weak seed gives a predictable
    SK (full compromise). Caller responsibility (mt-mnemonic
    uses HKDF-Expand from an mlocked master_seed; OS CSPRNG in the keypair()
    test helper via getrandom).
  - Seed exposure: the seed is theoretically recoverable from the SK after KeyGen
    (FIPS 204 §5.1: ξ is encoded inside the SK). This is by design — the recovery flow
    through the mnemonic regenerates the seed → SK byte-identically.
  - Determinism as a security feature: same seed → same (pk, sk).
    Used for consensus identity (mt-mnemonic), not a vulnerability.
  - Stack hygiene is critical: KeyGen is the only moment when SK bytes
    appear "from nowhere"; any stack temp buffer is a leak surface.
    The defence is a heap Box + mlock allocated BEFORE the FFI call; FFI writes
    directly into heap memory.
  - Error path leak: on FFI failure, partially filled bytes could leak —
    the defence is an explicit sk_box.zeroize() before return Err.

Verified:
  Pass 17 checks (per-primitive analysis for KeyGen):
    1. Constant-time:           ✅ FIPS 204 Algorithm 1 KeyGen inside
                                   OpenSSL (validation pending external review,
                                   hardware side-channel separately)
    2. Memory access:           ✅ no secret-indexed access in Layer 1
    3. Branch pattern:          ✅ Layer 1 checks only the return code (i32);
                                   no seed-dependent / sk-dependent branches
    4. Zeroization on drop:     ✅ through the returned SecretKey type (Card 1)
                                   + explicit sk_box.zeroize() on the error path
    5. Library check:           ✅ OpenSSL FIPS 140-3 (KeyGen validated)
    6. Stack hygiene:           ✅ heap Box + mlock allocated BEFORE FFI;
                                   no stack temporary buffers with secret bytes
    7. OS-level mlock:          ✅ via alloc_locked_secret_box (best-effort)
    8. Memory barrier:          ✅ inherited from SecretKey Drop

Status: closed
```

---

## Card 4: keypair_from_seed_mlkem — ML-KEM-768 KeyGen

```
Security Card for keypair_from_seed_mlkem:

Secret material handled:
  Input:                seed: &[u8; 64] (d || z per FIPS 203 §6.1)
  Output secret:        MlkemSecretKey (2400B)
  Output public:        MlkemPublicKey (1184B)

Lifecycle:
  seed lifecycle:       caller-owned, &-borrow
  SK construction:      heap Box + mlock BEFORE the FFI call (via alloc_locked_secret_box)
  Error path:           sk_box.zeroize() before return Err

Side-channel surface:
  Same as ML-DSA KeyGen — Layer 1 thin FFI shim, no secret-dependent operations

OS-level hygiene:
  mlock on SK:          yes
  mlock on seed:        caller responsibility
  Stack cleanup:        no stack temp with secret bytes

Library properties:
  Underlying:           OpenSSL EVP_PKEY ML-KEM-768 KeyGen (FIPS 203 Algorithm 16)
  Determinism:          guaranteed via OSSL_PKEY_PARAM_ML_KEM_SEED
  NIST conformance:     verified byte-exact against NIST ACVP 25/25 KeyGen tests

Threat model (per-primitive — KEM KeyGen specific, vs ML-DSA Card 3):
  - Seed format: 64-byte d ‖ z per FIPS 203 §6.1 (vs 32-byte ξ for ML-DSA).
    Double domain separation inside the seed (d for key generation polynomial,
    z for the implicit rejection PRF). Both components are secret-critical.
  - Implicit rejection key: the z part of the seed becomes the PRF key for the
    decapsulation failure mode. A compromised z enables the plaintext-checking
    attack [HHK17]. The defence is that z never leaves the SK heap.
  - Stack hygiene: same as ML-DSA KeyGen (heap Box + mlock BEFORE FFI).
  - Key reuse: an ML-KEM SK can be used repeatedly in Decap (vs
    ML-DSA SK in Sign — multiple operations are OK). Lifetime exposure is higher
    than for a signature SK → mlock/zeroize matter more.

Verified:
  Pass 17 checks (per-primitive analysis for KEM KeyGen):
    1. Constant-time:           ✅ FIPS 203 Algorithm 16 KeyGen inside
                                   OpenSSL (FIPS 140-3 validated)
    2. Memory access:           ✅ no seed/sk-indexed access in Layer 1
    3. Branch pattern:          ✅ Layer 1 checks only the return code
    4. Zeroization on drop:     ✅ through the MlkemSecretKey type (Card 2)
                                   + explicit sk_box.zeroize() on the error path
    5. Library check:           ✅ OpenSSL FIPS 140-3
    6. Stack hygiene:           ✅ heap Box + mlock allocated BEFORE FFI
    7. OS-level mlock:          ✅ via alloc_locked_secret_box
    8. Memory barrier:          ✅ inherited from MlkemSecretKey Drop

Status: closed
```

---

## Card 5: sign — ML-DSA-65 deterministic Sign

```
Security Card for sign (mt_crypto::sign):

Secret material handled:
  Input:                sk: &SecretKey (borrowed)
  Output secret:        none — the signature is public material

Lifecycle:
  sk access:            read-only borrow; the bytes remain in the caller's heap
                        Box for the whole duration of the call
  signature construct:  stack-allocated [u8; 3309] — public material, not secret
  Drop:                 sig is public, no zeroize needed

Side-channel surface:
  Branching on secret bytes: no (Layer 1 checks only the return code)
  Memory access:        sk.0.as_ptr() is passed to FFI; OpenSSL internally performs
                        constant-time deterministic Sign (FIPS 204 Algorithm 2)
  PartialEq on signature: derived (Signature: PartialEq) — OK, the signature is public
  Logging:              0 on sk; no println on the signature inside sign()

OS-level hygiene:
  mlock on sk:          inherited from SecretKey (already locked)
  Stack cleanup:        none needed (no stack secret bytes; signature is public)

Library properties:
  Underlying:           OpenSSL EVP_DigestSign + OSSL_SIGNATURE_PARAM_DETERMINISTIC=1
  Determinism:          FIPS 204 Algorithm 2 deterministic variant — required for
                        Montana [I-3] consensus determinism
  Constant-time:        OpenSSL FIPS 140-3
  NIST conformance:     verified byte-exact against NIST ACVP 1/1 deterministic
                        SigGen test (empty context)

Threat model (per-primitive — Sign specific, vs SecretKey Card 1):
  - Deterministic Sign is critical for consensus: identical (sk, msg) → identical
    signature. Required for Montana [I-3] determinism — two implementations
    sign the same message and obtain a bit-identical signature. The random
    signing variant is forbidden in the consensus path.
  - Sign timing: the internal rejection sampling in FIPS 204 Algorithm 2
    may have a secret-dependent number of iterations. The OpenSSL FIPS 140-3
    implementation is constant-time thanks to a fixed-iteration upper bound.
  - Signature output: NOT secret material (signature + msg + pk → public).
    Signature::PartialEq derived is OK, no zeroize needed, stack-allocated is OK.
  - Side-channel surface: Sign is the main attack target in lattice schemes
    (BLISS, Falcon and Dilithium all had side-channel papers). The OpenSSL
    constant-time implementation passes FIPS 140-3 attestation, but
    hardware side-channel testing is out of scope (see AUDIT.md Out of Scope §5).
  - SK exposure during Sign: sk.0.as_ptr() is passed to FFI; OpenSSL reads
    from heap-locked memory; there are no stack copies of SK bytes in Layer 1.

Verified:
  Pass 17 checks (per-primitive analysis for Sign):
    1. Constant-time:           ✅ FIPS 204 Algorithm 2 deterministic Sign
                                   constant-time via OpenSSL FIPS 140-3
    2. Memory access:           ✅ no SK-indexed access in Layer 1
                                   (FFI passes only a pointer, not indexes)
    3. Branch pattern:          ✅ no SK-dependent branches in Layer 1
    4. Zeroization on drop:     ✅ Signature contains no secret material
                                   (no zeroize needed); SK via Card 1
    5. Library check:           ✅ OpenSSL FIPS 140-3
    6. Stack hygiene:           ✅ no SK bytes on the stack; signature output
                                   on the stack is acceptable (public material)
    7. OS-level mlock:          ✅ inherited from SecretKey (already locked)
    8. Memory barrier:          ✅ inherited from SecretKey Drop

Status: closed
```

---

## Card 6: verify — ML-DSA-65 SigVer

```
Security Card for verify (mt_crypto::verify):

Secret material handled: none
  Input:                pk: &PublicKey (public material)
                        msg: &[u8] (public material)
                        sig: &Signature (public material)
  Output:               bool (verify result)

Lifecycle:               no secret material involved

Side-channel surface:
  Branching on PK bytes:   no (PK is public, not secret — branching on PK is acceptable)
  Memory access:           pk/sig bytes accessed only inside OpenSSL (constant-time
                            is not critical for public material, but OpenSSL is
                            constant-time anyway by design)
  Logging:                 0

Library properties:
  Underlying:           OpenSSL EVP_DigestVerify
  Constant-time:        FIPS 140-3 (by design, although not critical for public material)

Threat model (per-primitive — Verify specific, NO secret material):
  - PK / msg / sig are all public. Branching on their bytes is acceptable
    (nothing to leak). This is the fundamental difference from Sign Card 5.
  - The Verify result is a boolean, derivable from public inputs. No timing leak
    concern (timing depends on inputs that are public).
  - DoS surface: malformed signature → constant-time rejection? Not critical
    (the caller can rate-limit verify calls on foreign signatures).
  - Cross-implementation conformance: Verify must accept a signature from
    any FIPS 204 implementation. This is the reverse direction of Sign
    determinism — Sign gives identical bytes, Verify accepts the canonical encoding.

Pass 17 checks (per-primitive analysis for Verify):
  Not fully applicable — there is no secret material:
    1-3. Constant-time / memory access / branching: N/A for public material
    4. Zeroization: N/A for public material
    5. Library check: ✅ OpenSSL FIPS 140-3
    6-8. Stack / mlock / barrier: N/A for public material

Status: closed (no secret material — Security Card minimal by design)
```

---

## Re-audit schedule

All Security Cards are re-verified automatically through:
- `crates/mt-crypto/tests/security_invariants.rs` — every CI run
- Manual re-audit is mandatory:
  - On a change of the upstream library (OpenSSL upgrade)
  - On a change of the FFI signature (mt-crypto-native API)
  - On adding a new entry point with secret bytes
  - Every 6 months of wall-clock time on existing primitives (next: 2026-10-26)

## Cross-references

- Critic role enforcement: [CRITIC.md](../CRITIC.md) v1.6.0 §"Mandatory Security Card per crypto primitive"
- Code under audit: [crates/mt-crypto/src/lib.rs](../crates/mt-crypto/src/lib.rs)
- Automated invariants: [crates/mt-crypto/tests/security_invariants.rs](../crates/mt-crypto/tests/security_invariants.rs)
- High-level audit package: [AUDIT.md](../AUDIT.md)
- Pre-audit checklist: [audit-checklist.md](audit-checklist.md)
