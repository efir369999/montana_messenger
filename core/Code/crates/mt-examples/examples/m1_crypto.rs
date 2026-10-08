use std::env;
use std::process::ExitCode;
use std::time::Instant;

use mt_codec::domain;
use mt_crypto::{
    hash, keypair, keypair_from_seed, sha256_raw, sign, verify, Hash32, PublicKey, SecretKey,
    Signature, KEYPAIR_SEED_SIZE, PUBLIC_KEY_SIZE, SECRET_KEY_SIZE, SIGNATURE_SIZE,
};
use mt_examples::{
    hex_full, print_field, print_kv, print_note, print_section, print_subsection, print_warn,
    xxd_dump,
};
use mt_merkle::{empty_internal, internal_hash, leaf_hash, TREE_DEPTH};

// Debug fingerprint via a domain-separated hash. The label «fingerprint (debug)»
// makes explicit that this is NOT raw SHA-256 — the mt-fingerprint-debug domain is used
// to avoid confusion with consensus hashes.
fn fingerprint(bytes: &[u8]) -> String {
    let h: Hash32 = hash(b"mt-fingerprint-debug", &[bytes]);
    let short: Vec<u8> = h[..8].to_vec();
    hex_full(&short)
}

fn debug_hash(bytes: &[u8]) -> String {
    let h: Hash32 = hash(b"mt-fingerprint-debug", &[bytes]);
    hex_full(&h)
}

// Raw SHA-256 without domain separation — for FIPS 180-4 conformance checks
// and for comparison with standalone `shasum -a 256` output.
fn raw_sha256(bytes: &[u8]) -> String {
    hex_full(&sha256_raw(bytes))
}

// Dump SK only if explicitly enabled via env var M1_DUMP_SK=1.
// By default — redacted fingerprint only. Prevents accidental leak via
// cargo run --release --example m1_crypto > shared.log.
fn dump_sk_enabled() -> bool {
    std::env::var("M1_DUMP_SK").ok().as_deref() == Some("1")
}

// cmd_keypair_deterministic replaces the old print_recovery_disclosure (soft note):
// a real test of deterministic KeyGen — two runs of keypair_from_seed(seed) with the
// same seed → byte-exact equality, with a different seed → different keys. This is an actual
// demonstration of the recovery flow at the primitive level (not just a note about the mnemonic crate).

fn print_pk(pk: &PublicKey) {
    print_subsection("PUBLIC KEY — sent to the network, lands in AccountTable/NodeTable");
    print_kv("size", format!("{PUBLIC_KEY_SIZE} bytes"));
    print_kv(
        "fingerprint (8B, domain=mt-fingerprint-debug)",
        fingerprint(pk.as_bytes()),
    );
    print_kv(
        "debug_hash (domain=mt-fingerprint-debug)",
        debug_hash(pk.as_bytes()),
    );
    print_kv("sha256_raw (no domain)", raw_sha256(pk.as_bytes()));
    println!("  hex_full:");
    println!("    {}", hex_full(pk.as_bytes()));
    println!("  xxd dump:");
    for line in xxd_dump(pk.as_bytes()).lines() {
        println!("    {line}");
    }
}

fn print_sk(sk: &SecretKey) {
    print_subsection("SECRET KEY — NEVER leaves the node, stored locally only");
    print_kv("size", format!("{SECRET_KEY_SIZE} bytes"));
    print_kv(
        "fingerprint (8B, domain=mt-fingerprint-debug)",
        fingerprint(sk.as_bytes()),
    );

    if !dump_sk_enabled() {
        print_warn(
            "SK bytes REDACTED — set M1_DUMP_SK=1 to show (dev-only, unsafe for shared output)",
        );
        return;
    }

    print_kv(
        "debug_hash (domain=mt-fingerprint-debug)",
        debug_hash(sk.as_bytes()),
    );
    print_kv("sha256_raw (no domain)", raw_sha256(sk.as_bytes()));
    println!("  hex_full:");
    println!("    {}", hex_full(sk.as_bytes()));
    println!("  xxd dump:");
    for line in xxd_dump(sk.as_bytes()).lines() {
        println!("    {line}");
    }
    print_warn("SK is shown only because M1_DUMP_SK=1 is set");
    print_warn("In production SK is never logged, never serialized in the clear");
}

fn print_sig(sig: &Signature) {
    print_subsection("SIGNATURE — ML-DSA-65 deterministic");
    print_kv("size", format!("{SIGNATURE_SIZE} bytes"));
    print_kv(
        "fingerprint (8B, domain=mt-fingerprint-debug)",
        fingerprint(sig.as_bytes()),
    );
    print_kv(
        "debug_hash (domain=mt-fingerprint-debug)",
        debug_hash(sig.as_bytes()),
    );
    print_kv("sha256_raw (no domain)", raw_sha256(sig.as_bytes()));
    println!("  hex_full:");
    println!("    {}", hex_full(sig.as_bytes()));
    println!("  xxd dump:");
    for line in xxd_dump(sig.as_bytes()).lines() {
        println!("    {line}");
    }
}

fn cmd_keypair_random(n: usize) -> bool {
    print_section(&format!(
        "KEYPAIR RANDOM — ML-DSA-65 (OS rng entropy) × {n} (sanity check primitive)"
    ));
    print_subsection("Algorithm");
    print_kv(
        "scheme",
        "ML-DSA-65 (NIST FIPS 204 finalized 2024-08, lattice-based, [I-1] compliant)",
    );
    print_kv(
        "library",
        "OpenSSL 3.5.5 LTS via own thin C FFI wrapper (mt-crypto-native)",
    );
    print_kv(
        "entropy source",
        "time+pid+stack-addr → SHA-256 (test/tool only; production via keypair_from_seed from HKDF)",
    );
    print_kv("pk size", format!("{PUBLIC_KEY_SIZE} bytes"));
    print_kv("sk size", format!("{SECRET_KEY_SIZE} bytes"));
    print_kv("sig size", format!("{SIGNATURE_SIZE} bytes"));

    let mut pks: Vec<PublicKey> = Vec::with_capacity(n);
    let mut sks: Vec<Vec<u8>> = Vec::with_capacity(n);
    let mut all_verify_ok = true;

    for i in 0..n {
        print_section(&format!("KEYPAIR #{} / {}", i + 1, n));
        let t0 = Instant::now();
        let (pk, sk) = keypair();
        let elapsed = t0.elapsed();
        print_kv(
            "generation time",
            format!("{:.2}ms", elapsed.as_secs_f64() * 1000.0),
        );

        print_pk(&pk);
        print_sk(&sk);

        let msg = format!("keypair#{i} self-test");
        let sig = sign(&sk, msg.as_bytes()).expect("sign self-test");
        let ok = verify(&pk, msg.as_bytes(), &sig);
        print_subsection("Self-test sign+verify");
        print_kv("test message", format!("{:?} ({} bytes)", msg, msg.len()));
        print_kv("verify(pk,msg,sig)", format!("{ok}"));
        if !ok {
            all_verify_ok = false;
        }

        pks.push(pk);
        sks.push(sk.as_bytes().to_vec());
    }

    print_section("UNIQUENESS INVARIANT");
    let mut pks_distinct = true;
    let mut sks_distinct = true;
    for i in 0..pks.len() {
        for j in (i + 1)..pks.len() {
            if pks[i].as_bytes() == pks[j].as_bytes() {
                pks_distinct = false;
                print_warn(&format!("pk[{i}] == pk[{j}] !!!"));
            }
            if sks[i] == sks[j] {
                sks_distinct = false;
                print_warn(&format!("sk[{i}] == sk[{j}] !!!"));
            }
        }
    }
    print_kv("all_public_keys_distinct", format!("{pks_distinct}"));
    print_kv("all_secret_keys_distinct", format!("{sks_distinct}"));

    print_section("RECOVERY MECHANISM POINTER");
    print_note("Production identity flow — via m1_mnemonic (deterministic from 24 words)");
    print_note("This command is a RANDOM keypair sanity check of the ML-DSA-65 primitive (test/dev only)");
    print_note(
        "For the deterministic recovery test: subcommand `keypair` (without --random) or `m1_mnemonic`",
    );

    let pass = all_verify_ok && pks_distinct && sks_distinct;
    println!(
        "\n[result] KEYPAIR-RANDOM: {}",
        if pass { "PASS" } else { "FAIL" }
    );
    pass
}

fn cmd_keypair_deterministic() -> bool {
    print_section("KEYPAIR DETERMINISTIC — ML-DSA-65.KeyGen(seed) byte-exact recovery test");

    print_subsection("Algorithm");
    print_kv(
        "scheme",
        "ML-DSA-65 (NIST FIPS 204 finalized 2024-08, FIPS 204 §3.1 ξ ∈ B32)",
    );
    print_kv(
        "seed source",
        "fixed test value [0x42; 32] (production: HKDF-Expand from master_seed)",
    );
    print_kv("pk size", format!("{PUBLIC_KEY_SIZE} bytes"));
    print_kv("sk size", format!("{SECRET_KEY_SIZE} bytes"));

    let seed = [0x42u8; KEYPAIR_SEED_SIZE];
    print_subsection("DERIVATION TRACE — two independent runs of keypair_from_seed(seed)");
    print_kv("seed hex", hex_full(&seed));

    let (pk_a, sk_a) = keypair_from_seed(&seed).expect("keygen run A");
    let (pk_b, sk_b) = keypair_from_seed(&seed).expect("keygen run B");

    let pk_match = pk_a.as_bytes() == pk_b.as_bytes();
    let sk_match = sk_a.as_bytes() == sk_b.as_bytes();

    print_kv(
        "Run A pk fingerprint (8B)",
        hex_full(&sha256_raw(pk_a.as_bytes())[..8]),
    );
    print_kv(
        "Run B pk fingerprint (8B)",
        hex_full(&sha256_raw(pk_b.as_bytes())[..8]),
    );
    print_kv(
        "Run A sk fingerprint (8B)",
        hex_full(&sha256_raw(sk_a.as_bytes())[..8]),
    );
    print_kv(
        "Run B sk fingerprint (8B)",
        hex_full(&sha256_raw(sk_b.as_bytes())[..8]),
    );

    print_subsection("BYTE-EXACT EQUALITY ASSERTIONS");
    print_kv("pk_a == pk_b", if pk_match { "OK ✓" } else { "FAIL ✗" });
    print_kv("sk_a == sk_b", if sk_match { "OK ✓" } else { "FAIL ✗" });

    print_subsection("DIFFERENT SEED → DIFFERENT KEYPAIR (sanity)");
    let seed2 = [0x43u8; KEYPAIR_SEED_SIZE];
    let (pk_c, _) = keypair_from_seed(&seed2).expect("keygen seed2");
    let pk_differs = pk_a.as_bytes() != pk_c.as_bytes();
    print_kv("seed2 hex", hex_full(&seed2));
    print_kv(
        "pk_a != pk_c (different seed)",
        if pk_differs { "OK ✓" } else { "FAIL ✗" },
    );

    print_subsection("FINGERPRINTS — for cross-impl byte-exact verification");
    print_kv("pk sha256", hex_full(&sha256_raw(pk_a.as_bytes())));
    print_kv("sk sha256", hex_full(&sha256_raw(sk_a.as_bytes())));

    print_section("RECOVERY MECHANISM");
    print_note(
        "This command is an actual byte-exact test, not a description. The same seed → always the same keypair.",
    );
    print_note(
        "In production the seed is derived from the 24-word mnemonic via mt-mnemonic (HKDF-Expand role-keyed).",
    );
    print_note("Full recovery flow down to terminal IDs — m1_mnemonic recovery-fingerprint");

    let pass = pk_match && sk_match && pk_differs;
    println!(
        "\n[result] KEYPAIR-DETERMINISTIC: {}",
        if pass { "PASS" } else { "FAIL" }
    );
    pass
}

fn cmd_sign(msg: &str) -> bool {
    print_section(&format!(
        "SIGN + VERIFY — ML-DSA-65 deterministic signature on message {msg:?}"
    ));

    print_subsection("Message preparation");
    let msg_bytes = msg.as_bytes();
    print_kv("len", format!("{} bytes", msg_bytes.len()));
    print_kv("ascii", msg.to_string());
    print_kv("hex", hex_full(msg_bytes));

    let (pk, sk) = keypair();
    print_pk(&pk);
    print_sk(&sk);

    print_subsection("Sign call trace");
    print_kv(
        "function",
        format!("mt_crypto::sign(sk, msg) → Signature[{SIGNATURE_SIZE}B]"),
    );
    print_kv(
        "internal",
        "OpenSSL EVP_DigestSign + OSSL_SIGNATURE_PARAM_DETERMINISTIC=1 (FIPS 204 Algorithm 2, deterministic variant)",
    );
    let t0 = Instant::now();
    let sig = sign(&sk, msg_bytes).expect("sign happy path");
    let sign_ms = t0.elapsed().as_secs_f64() * 1000.0;
    print_kv("sign latency", format!("{sign_ms:.2}ms"));
    print_sig(&sig);

    print_subsection("Verify call trace (happy path)");
    let t1 = Instant::now();
    let ok = verify(&pk, msg_bytes, &sig);
    let verify_ms = t1.elapsed().as_secs_f64() * 1000.0;
    print_kv("verify latency", format!("{verify_ms:.2}ms"));
    print_kv("result", format!("{ok}"));

    print_section("ADVERSARIAL TESTS");

    print_subsection("1. Mutation at 4 positions must all reject");
    let positions = [0usize, 166, 333, 665];
    let mut mut_all_rejected = true;
    for &pos in &positions {
        let mut bad = *sig.as_bytes();
        bad[pos] ^= 0xFF;
        let bad_sig = Signature::from_array(bad);
        let rejected = !verify(&pk, msg_bytes, &bad_sig);
        print_kv(
            &format!("mutate byte {pos}"),
            format!(
                "sig[{pos}]=0x{:02x} → 0x{:02x}, verify={}",
                sig.as_bytes()[pos],
                bad[pos],
                if rejected {
                    "REJECTED ✓"
                } else {
                    "ACCEPTED ✗"
                }
            ),
        );
        if !rejected {
            mut_all_rejected = false;
        }
    }

    print_subsection("2. Mutated message must be rejected");
    let mut bad_msg = msg_bytes.to_vec();
    if !bad_msg.is_empty() {
        bad_msg[0] ^= 0x01;
    } else {
        bad_msg.push(0x01);
    }
    let msg_rejected = !verify(&pk, &bad_msg, &sig);
    print_kv("orig msg hex", hex_full(msg_bytes));
    print_kv("bad msg  hex", hex_full(&bad_msg));
    print_kv(
        "verify(pk, bad_msg, sig)",
        if msg_rejected {
            "REJECTED ✓"
        } else {
            "ACCEPTED ✗"
        },
    );

    print_subsection("3. Cross-key: verify with wrong pubkey must fail");
    let (other_pk, _) = keypair();
    let cross_rejected = !verify(&other_pk, msg_bytes, &sig);
    print_kv("other_pk fingerprint", fingerprint(other_pk.as_bytes()));
    print_kv(
        "verify(other_pk, msg, sig)",
        if cross_rejected {
            "REJECTED ✓"
        } else {
            "ACCEPTED ✗"
        },
    );

    print_subsection(
        "4. Determinism: same (sk, msg) twice → identical σ (FIPS 204 §3.7, RND = 0x00 × 32)",
    );
    let sig2 = sign(&sk, msg_bytes).expect("sign sample 2");
    let identical = sig.as_bytes() == sig2.as_bytes();
    let sig2_verifies = verify(&pk, msg_bytes, &sig2);
    print_kv("sig1 fingerprint", fingerprint(sig.as_bytes()));
    print_kv("sig2 fingerprint", fingerprint(sig2.as_bytes()));
    print_kv("sig1 == sig2", format!("{identical}"));
    print_kv("verify(pk, msg, sig2)", format!("{sig2_verifies}"));

    let pass =
        ok && mut_all_rejected && msg_rejected && cross_rejected && identical && sig2_verifies;
    println!("\n[result] SIGN: {}", if pass { "PASS" } else { "FAIL" });
    pass
}

fn cmd_hash() -> bool {
    print_section("HASH — SHA-256 (FIPS 180-4) + domain-separated composition");

    print_subsection("1. FIPS 180-4 §B.1 vector: SHA-256(\"abc\")");
    let input = b"abc";
    print_kv("input ascii", "abc");
    print_kv("input hex", hex_full(input));
    print_kv("input len", format!("{} bytes", input.len()));
    let got = sha256_raw(input);
    let expected_hex = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad";
    print_kv("mt_crypto::sha256_raw(b\"abc\")", hex_full(&got));
    print_kv("FIPS 180-4 expected", expected_hex.to_string());
    let fips_ok = hex_full(&got) == expected_hex;
    print_kv("byte-exact match", format!("{fips_ok}"));
    print_note("NOTE: mt_crypto::hash(domain, parts) uses a NUL separator and a self-delimiting");
    print_note("formula SHA-256(domain || 0x00 || parts) — not raw SHA-256. For FIPS compatibility");
    print_note("the separate function sha256_raw() without domain separation is used.");

    print_subsection("2. Empty-parts collapse: hash(d,[]) == hash(d,[b\"\"])");
    let a = hash(domain::OP, &[]);
    let b = hash(domain::OP, &[&[] as &[u8]]);
    print_kv("hash(OP, [])", hex_full(&a));
    print_kv("hash(OP, [b\"\"])", hex_full(&b));
    let collapse_ok = a == b;
    print_kv("equal", format!("{collapse_ok}"));

    print_subsection("3. Part concatenation: hash(d,[a,b,c]) == hash(d,[a||b||c])");
    let h_parts = hash(domain::OP, &[b"aa", b"bb", b"cc"]);
    let h_concat = hash(domain::OP, &[b"aabbcc"]);
    print_kv("hash(OP, [aa,bb,cc])", hex_full(&h_parts));
    print_kv("hash(OP, [aabbcc])", hex_full(&h_concat));
    let concat_ok = h_parts == h_concat;
    print_kv("equal", format!("{concat_ok}"));

    print_subsection("4. Domain separation — all R2 class domains with input=x");
    let x: &[u8] = b"x";
    let class_domains: &[(&str, &[u8])] = &[
        ("mt-op", domain::OP),
        ("mt-nodereg", domain::NODEREG),
        ("mt-proposal", domain::PROPOSAL),
        ("mt-bundle", domain::BUNDLE),
        ("mt-ssha-reveal", domain::SSHA_REVEAL),
    ];
    let mut outputs: Vec<Hash32> = Vec::new();
    for (name, d) in class_domains {
        let h = hash(d, &[x]);
        print_kv(&format!("{name:<16} input=x"), hex_full(&h));
        outputs.push(h);
    }
    let mut class_distinct = true;
    for i in 0..outputs.len() {
        for j in (i + 1)..outputs.len() {
            if outputs[i] == outputs[j] {
                class_distinct = false;
                print_warn(&format!(
                    "collision: {} == {}",
                    class_domains[i].0, class_domains[j].0
                ));
            }
        }
    }
    print_kv("all_class_domains_distinct", format!("{class_distinct}"));

    print_subsection("5. Domain separator registry — full list of 32");
    let all_domains: &[(&str, &[u8])] = &[
        ("mt-op", domain::OP),
        ("mt-nodereg", domain::NODEREG),
        ("mt-proposal", domain::PROPOSAL),
        ("mt-bundle", domain::BUNDLE),
        ("mt-ssha-reveal", domain::SSHA_REVEAL),
        ("mt-account", domain::ACCOUNT),
        ("mt-candidate-ssha-init", domain::CANDIDATE_SSHA_INIT),
        ("mt-merkle-leaf", domain::MERKLE_LEAF),
        ("mt-merkle-node", domain::MERKLE_NODE),
        ("mt-state-root", domain::STATE_ROOT),
        ("mt-timechain", domain::TIMECHAIN),
        ("mt-lottery", domain::LOTTERY),
        ("mt-bc-aggregate", domain::BC_AGGREGATE),
        ("mt-bc-aggregate-empty", domain::BC_AGGREGATE_EMPTY),
        ("mt-selection", domain::SELECTION),
        ("mt-nodereg-sort", domain::NODEREG_SORT),
        ("mt-confirmation", domain::CONFIRMATION),
        ("mt-app", domain::APP),
        ("mt-node", domain::NODE),
        ("mt-genesis", domain::GENESIS),
        ("mt-seed", domain::SEED),
        ("mt-account-key", domain::ACCOUNT_KEY),
        ("mt-node-key", domain::NODE_KEY),
        ("mt-content-chunk", domain::CONTENT_CHUNK),
        ("mt-content-manifest", domain::CONTENT_MANIFEST),
        ("mt-profile", domain::PROFILE),
        ("mt-encryption-key", domain::ENCRYPTION_KEY),
        ("mt-app-encryption-key", domain::APP_ENCRYPTION_KEY),
        ("mt-prekeys", domain::PREKEYS),
        ("mt-tunnel-online", domain::TUNNEL_ONLINE),
        ("mt-tunnel-mesh", domain::TUNNEL_MESH),
        ("mt-recovery-fingerprint", domain::RECOVERY_FINGERPRINT),
    ];
    print_kv("registry size", format!("{}", all_domains.len()));
    for (name, bytes) in all_domains {
        print_field(
            name,
            &format!("{} bytes, hex={}", bytes.len(), hex_full(bytes)),
        );
    }

    let pass = fips_ok && collapse_ok && concat_ok && class_distinct;
    println!("\n[result] HASH: {}", if pass { "PASS" } else { "FAIL" });
    pass
}

fn cmd_merkle() -> bool {
    print_section("MERKLE — Sparse Merkle Tree depth=256, empty_internal table");

    print_subsection("Definitions");
    print_kv("TREE_DEPTH", format!("{TREE_DEPTH}"));
    print_kv("EMPTY_LEAF", hex_full(&empty_internal(0)));
    print_kv(
        "leaf_hash(x)",
        "= SHA-256(\"mt-merkle-leaf\" || x)".to_string(),
    );
    print_kv(
        "internal_hash(l,r)",
        "= SHA-256(\"mt-merkle-node\" || l || r)".to_string(),
    );
    print_kv(
        "empty_internal(k)",
        "= level 0: [0;32]; level k≥1: internal_hash(empty_internal(k-1), empty_internal(k-1))"
            .to_string(),
    );

    print_subsection("Derivation trace — first 3 levels");
    let lvl0 = empty_internal(0);
    let lvl1 = empty_internal(1);
    let lvl2 = empty_internal(2);
    println!("  level 0 = EMPTY_LEAF");
    println!("         = {}", hex_full(&lvl0));
    println!();
    println!("  level 1 = internal_hash(level_0, level_0)");
    println!("         = SHA-256(\"mt-merkle-node\" || level_0 || level_0)");
    println!("    input domain (14B): {}", hex_full(domain::MERKLE_NODE));
    println!(
        "    input data   (64B): {}",
        hex_full(&[&lvl0[..], &lvl0[..]].concat())
    );
    println!("    output       (32B): {}", hex_full(&lvl1));
    println!();
    println!("  level 2 = internal_hash(level_1, level_1)");
    println!("    input domain (14B): {}", hex_full(domain::MERKLE_NODE));
    println!(
        "    input data   (64B): {}",
        hex_full(&[&lvl1[..], &lvl1[..]].concat())
    );
    println!("    output       (32B): {}", hex_full(&lvl2));

    print_subsection("Full table empty_internal(0..=256)");
    for k in 0..=TREE_DEPTH {
        let v = empty_internal(k);
        println!("  level {k:>3}: {}", hex_full(&v));
    }

    print_subsection("Invariants");
    let lvl256 = empty_internal(TREE_DEPTH);
    let level0_zero = lvl0 == [0u8; 32];
    let mut monotonic_all_differ = true;
    for k in 0..TREE_DEPTH {
        if empty_internal(k) == empty_internal(k + 1) {
            monotonic_all_differ = false;
            print_warn(&format!("level {k} == level {}", k + 1));
        }
    }
    let determinism = empty_internal(TREE_DEPTH) == lvl256;
    print_kv("level_0_is_all_zero", format!("{level0_zero}"));
    print_kv("all_consecutive_differ", format!("{monotonic_all_differ}"));
    print_kv("determinism (re-query equal)", format!("{determinism}"));

    print_subsection("Sanity: leaf_hash(\"hello\") is defined and differs from EMPTY_LEAF");
    let leaf = leaf_hash(b"hello");
    let internal = internal_hash(&lvl0, &lvl0);
    print_kv("leaf_hash(b\"hello\")", hex_full(&leaf));
    print_kv("internal_hash(zeros,zeros)", hex_full(&internal));
    print_kv(
        "leaf_hash == internal_hash(z,z)",
        format!("{}", leaf == internal),
    );
    print_kv(
        "leaf_hash == empty_internal(1)",
        format!("{}", leaf == lvl1),
    );
    let leaf_vs_empty = leaf != lvl0;
    print_kv("leaf_hash != EMPTY_LEAF", format!("{leaf_vs_empty}"));

    let pass = level0_zero && monotonic_all_differ && determinism && leaf_vs_empty;
    println!("\n[result] MERKLE: {}", if pass { "PASS" } else { "FAIL" });
    pass
}

fn cmd_all() -> bool {
    print_section("M1 CRYPTO — FULL USER JOURNEY");
    print_note(
        "Runs the full path: deterministic keypair test + 3 random keypairs + sign + hash + merkle",
    );

    let a = cmd_keypair_deterministic();
    let b = cmd_keypair_random(3);
    let c = cmd_sign("Montana M1 crypto shakedown — production journey");
    let d = cmd_hash();
    let e = cmd_merkle();

    print_section("SUMMARY");
    print_kv("keypair-deterministic", if a { "PASS" } else { "FAIL" });
    print_kv("keypair-random", if b { "PASS" } else { "FAIL" });
    print_kv("sign", if c { "PASS" } else { "FAIL" });
    print_kv("hash", if d { "PASS" } else { "FAIL" });
    print_kv("merkle-empty", if e { "PASS" } else { "FAIL" });

    let pass = a && b && c && d && e;
    println!(
        "\n[result] ALL SCENARIOS: {}",
        if pass { "PASS" } else { "FAIL" }
    );
    pass
}

fn bool_to_exit(pass: bool) -> ExitCode {
    if pass {
        ExitCode::SUCCESS
    } else {
        ExitCode::FAILURE
    }
}

fn usage() {
    eprintln!("M1 CRYPTO — ML-DSA-65 + SHA-256 + Sparse Merkle shakedown binary");
    eprintln!();
    eprintln!("usage: m1_crypto <subcommand> [args]");
    eprintln!();
    eprintln!("  keypair                Deterministic keypair test (recovery sanity, default)");
    eprintln!("  keypair-random [N]     RANDOM N keypairs (default 1) + uniqueness check");
    eprintln!("  sign [MSG]             Keypair → sign(MSG) → verify + 4 adversarial tests");
    eprintln!("  hash                   FIPS 180-4 vector + domain separation + full registry");
    eprintln!("  merkle-empty           Sparse Merkle: all 257 levels + derivation trace");
    eprintln!("  all                    Run all subcommands in sequence (user journey)");
    eprintln!();
    eprintln!("Everything prints bytes in hex + xxd dump. Exit code 0=PASS, 1=FAIL.");
}

fn main() -> ExitCode {
    let args: Vec<String> = env::args().collect();
    let sub = match args.get(1) {
        Some(s) => s.as_str(),
        None => {
            usage();
            return ExitCode::FAILURE;
        },
    };
    let pass = match sub {
        "keypair" => cmd_keypair_deterministic(),
        "keypair-random" => {
            let n: usize = args.get(2).and_then(|s| s.parse().ok()).unwrap_or(1);
            cmd_keypair_random(n)
        },
        "sign" => {
            let default_msg = String::from("Montana M1 crypto shakedown");
            let msg = args.get(2).unwrap_or(&default_msg);
            cmd_sign(msg)
        },
        "hash" => cmd_hash(),
        "merkle-empty" => cmd_merkle(),
        "all" => cmd_all(),
        _ => {
            usage();
            return ExitCode::FAILURE;
        },
    };
    bool_to_exit(pass)
}
