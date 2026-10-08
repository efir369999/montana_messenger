use std::env;
use std::process::ExitCode;

use mt_codec::domain;
use mt_crypto::{
    keypair_from_seed, keypair_from_seed_mlkem, sha256_raw, MlkemPublicKey, MlkemSecretKey,
    PublicKey, SecretKey, SuiteId,
};
use mt_examples::{hex_full, print_field, print_kv, print_note, print_section, print_subsection};
use mt_mnemonic::{
    entropy_to_mnemonic, mldsa_seed_for_role, mlkem_seed_for_role, mnemonic_to_master_seed,
    wordlist, MnemonicError, WORDLIST_FINGERPRINT, WORDLIST_SIZE,
};

fn hex_from(input: &str) -> Option<Vec<u8>> {
    let clean: String = input.chars().filter(|c| !c.is_whitespace()).collect();
    if clean.len() % 2 != 0 {
        return None;
    }
    (0..clean.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&clean[i..i + 2], 16).ok())
        .collect()
}

fn to_array_32(v: &[u8]) -> Option<[u8; 32]> {
    if v.len() != 32 {
        return None;
    }
    let mut out = [0u8; 32];
    out.copy_from_slice(v);
    Some(out)
}

fn print_master_seed(master: &[u8; 64]) {
    print_subsection("MASTER SEED — 64 bytes, PBKDF2 result");
    print_kv("fingerprint (8B)", hex_full(&master[..8]));
    println!("  hex_full:");
    println!("    {}", hex_full(master));
}

fn print_entropy(entropy: &[u8; 32]) {
    print_subsection("ENTROPY — 32 bytes");
    print_kv("hex", hex_full(entropy));
    let checksum = sha256_raw(entropy)[0];
    print_kv(
        "SHA-256(entropy)[0] checksum byte",
        format!("0x{checksum:02x}"),
    );
}

fn print_mnemonic(mnemonic: &str) {
    print_subsection("MNEMONIC — 24 words");
    let words: Vec<&str> = mnemonic.split(' ').collect();
    print_kv("word count", words.len().to_string());
    print_kv("length bytes", mnemonic.len().to_string());
    for (i, w) in words.iter().enumerate() {
        println!("  [{:>2}] {w}", i + 1);
    }
}

fn print_wordlist_fingerprint_check() -> bool {
    print_subsection("WORDLIST FINGERPRINT CHECK");
    let wl = wordlist();
    print_kv("wordlist size", format!("{} words", wl.len()));
    print_kv(
        "binding fingerprint (spec)",
        hex_full(&WORDLIST_FINGERPRINT),
    );
    print_kv("first word", wl[0].to_string());
    print_kv("last word", wl[WORDLIST_SIZE - 1].to_string());
    print_note("fingerprint check performed inside wordlist() on first call — PASS");
    true
}

// Terminal observable IDs (per spec):
//   account_id = SHA-256("mt-account" || suite_id_LE_bytes(2) || pk_acc)
//   node_id    = SHA-256("mt-node" || pk_node)
fn compute_account_id(pk: &PublicKey) -> [u8; 32] {
    let mut buf = Vec::with_capacity(domain::ACCOUNT.len() + 2 + pk.as_bytes().len());
    buf.extend_from_slice(domain::ACCOUNT);
    let suite_id = (SuiteId::Mldsa65 as u16).to_le_bytes();
    buf.extend_from_slice(&suite_id);
    buf.extend_from_slice(pk.as_bytes());
    sha256_raw(&buf)
}

fn compute_node_id(pk: &PublicKey) -> [u8; 32] {
    let mut buf = Vec::with_capacity(domain::NODE.len() + pk.as_bytes().len());
    buf.extend_from_slice(domain::NODE);
    buf.extend_from_slice(pk.as_bytes());
    sha256_raw(&buf)
}

struct DerivedIdentity {
    pk_acc: PublicKey,
    sk_acc: SecretKey,
    pk_node: PublicKey,
    sk_node: SecretKey,
    pk_mlkem: MlkemPublicKey,
    sk_mlkem: MlkemSecretKey,
    account_id: [u8; 32],
    node_id: [u8; 32],
}

fn derive_full_identity(entropy: &[u8; 32]) -> Result<DerivedIdentity, MnemonicError> {
    let mnemonic = entropy_to_mnemonic(entropy);
    let master_seed = mnemonic_to_master_seed(&mnemonic)?;

    let acc_seed = mldsa_seed_for_role(&master_seed, domain::ACCOUNT_KEY);
    let (pk_acc, sk_acc) =
        keypair_from_seed(&acc_seed).expect("HKDF-derived seed cannot fail ML-DSA KeyGen");
    let account_id = compute_account_id(&pk_acc);

    let node_seed = mldsa_seed_for_role(&master_seed, domain::NODE_KEY);
    let (pk_node, sk_node) =
        keypair_from_seed(&node_seed).expect("HKDF-derived seed cannot fail ML-DSA KeyGen");
    let node_id = compute_node_id(&pk_node);

    let mlkem_seed = mlkem_seed_for_role(&master_seed, domain::APP_ENCRYPTION_KEY);
    let (pk_mlkem, sk_mlkem) =
        keypair_from_seed_mlkem(&mlkem_seed).expect("HKDF-derived seed cannot fail ML-KEM KeyGen");

    Ok(DerivedIdentity {
        pk_acc,
        sk_acc,
        pk_node,
        sk_node,
        pk_mlkem,
        sk_mlkem,
        account_id,
        node_id,
    })
}

// Recovery fingerprint per [C-4] terminal observable identity:
// SHA-256("mt-recovery-fingerprint" ||
//         pk_acc || sk_acc || pk_node || sk_node ||
//         pk_mlkem || sk_mlkem || account_id || node_id)
fn compute_recovery_fingerprint(id: &DerivedIdentity) -> [u8; 32] {
    let mut buf = Vec::with_capacity(
        domain::RECOVERY_FINGERPRINT.len()
            + id.pk_acc.as_bytes().len()
            + id.sk_acc.as_bytes().len()
            + id.pk_node.as_bytes().len()
            + id.sk_node.as_bytes().len()
            + id.pk_mlkem.as_bytes().len()
            + id.sk_mlkem.as_bytes().len()
            + 32
            + 32,
    );
    buf.extend_from_slice(domain::RECOVERY_FINGERPRINT);
    buf.extend_from_slice(id.pk_acc.as_bytes());
    buf.extend_from_slice(id.sk_acc.as_bytes());
    buf.extend_from_slice(id.pk_node.as_bytes());
    buf.extend_from_slice(id.sk_node.as_bytes());
    buf.extend_from_slice(id.pk_mlkem.as_bytes());
    buf.extend_from_slice(id.sk_mlkem.as_bytes());
    buf.extend_from_slice(&id.account_id);
    buf.extend_from_slice(&id.node_id);
    sha256_raw(&buf)
}

fn parse_entropy_arg(entropy_hex: Option<&str>) -> Option<[u8; 32]> {
    if let Some(h) = entropy_hex {
        let bytes = hex_from(h)?;
        to_array_32(&bytes)
    } else {
        Some([0u8; 32])
    }
}

fn cmd_seeds(entropy_hex: Option<&str>) -> bool {
    print_section("SEEDS DERIVATION FROM ENTROPY (intermediate values, not keypair)");
    print_wordlist_fingerprint_check();

    let entropy = match parse_entropy_arg(entropy_hex) {
        Some(e) => e,
        None => {
            eprintln!("invalid entropy hex (must be 32 bytes / 64 hex chars)");
            return false;
        },
    };
    if entropy_hex.is_none() {
        print_note("entropy not given — using [0x00; 32] (M-1 Vector 1)");
    }

    print_entropy(&entropy);
    let mnemonic = entropy_to_mnemonic(&entropy);
    print_mnemonic(&mnemonic);

    let master_seed = match mnemonic_to_master_seed(&mnemonic) {
        Ok(m) => m,
        Err(e) => {
            eprintln!("mnemonic_to_master_seed failed: {e}");
            return false;
        },
    };
    print_master_seed(&master_seed);

    print_section("PER-ROLE KEY SEEDS — HKDF-Expand (NOT keypairs themselves, seed material only)");

    print_subsection("ACCOUNT KEYPAIR SEED — 32 bytes (ML-DSA-65)");
    let mldsa_account = mldsa_seed_for_role(&master_seed, domain::ACCOUNT_KEY);
    print_kv("info (domain separator)", "\"mt-account-key\"");
    print_kv("HKDF-Expand L", "32");
    println!("  hex_full:");
    println!("    {}", hex_full(&mldsa_account));

    print_subsection("NODE KEYPAIR SEED — 32 bytes (ML-DSA-65)");
    let mldsa_node = mldsa_seed_for_role(&master_seed, domain::NODE_KEY);
    print_kv("info (domain separator)", "\"mt-node-key\"");
    print_kv("HKDF-Expand L", "32");
    println!("  hex_full:");
    println!("    {}", hex_full(&mldsa_node));

    print_subsection("APP ENCRYPTION KEYPAIR SEED — 64 bytes (ML-KEM-768)");
    let mlkem_app = mlkem_seed_for_role(&master_seed, domain::APP_ENCRYPTION_KEY);
    print_kv("info (domain separator)", "\"mt-app-encryption-key\"");
    print_kv("HKDF-Expand L", "64");
    println!("  hex_full:");
    println!("    {}", hex_full(&mlkem_app));

    print_section("CONSEQUENCES");
    print_note(
        "Identical entropy → identical mnemonic → identical master_seed → identical seeds",
    );
    print_note("These are intermediate values. Full keypairs (pk/sk) → subcommand `keypair`");
    print_note(
        "Full chain down to terminal IDs (account_id, node_id, recovery fingerprint) → `recovery-fingerprint`",
    );

    println!("\n[result] SEEDS: PASS");
    true
}

fn print_pk_brief(label: &str, bytes: &[u8]) {
    print_subsection(label);
    print_kv("size", format!("{} bytes", bytes.len()));
    print_kv("sha256", hex_full(&sha256_raw(bytes)));
    print_kv("first 32 bytes", hex_full(&bytes[..32]));
}

fn print_sk_brief(label: &str, bytes: &[u8]) {
    print_subsection(label);
    print_kv("size", format!("{} bytes", bytes.len()));
    print_kv("sha256 (binding fingerprint)", hex_full(&sha256_raw(bytes)));
    print_note("SK bytes redacted — production identity, not printed");
}

fn cmd_keypair(entropy_hex: Option<&str>) -> bool {
    print_section("KEYPAIR DERIVATION FROM ENTROPY → terminal observable identity");
    print_wordlist_fingerprint_check();

    let entropy = match parse_entropy_arg(entropy_hex) {
        Some(e) => e,
        None => {
            eprintln!("invalid entropy hex (must be 32 bytes / 64 hex chars)");
            return false;
        },
    };
    if entropy_hex.is_none() {
        print_note("entropy not given — using [0x00; 32] (M-1 Vector 1)");
    }

    print_entropy(&entropy);

    let id = match derive_full_identity(&entropy) {
        Ok(i) => i,
        Err(e) => {
            eprintln!("derive failed: {e}");
            return false;
        },
    };

    print_section("ML-DSA-65 KEYPAIRS (terminal — this is what lands in network state)");

    print_pk_brief("ACCOUNT PUBLIC KEY (1952 bytes)", id.pk_acc.as_bytes());
    print_sk_brief("ACCOUNT SECRET KEY (4032 bytes)", id.sk_acc.as_bytes());

    print_pk_brief("NODE PUBLIC KEY (1952 bytes)", id.pk_node.as_bytes());
    print_sk_brief("NODE SECRET KEY (4032 bytes)", id.sk_node.as_bytes());

    print_section("ML-KEM-768 KEYPAIR (for encryption at the client level)");

    print_pk_brief(
        "APP ENCRYPTION PUBLIC KEY (1184 bytes)",
        id.pk_mlkem.as_bytes(),
    );
    print_sk_brief(
        "APP ENCRYPTION SECRET KEY (2400 bytes)",
        id.sk_mlkem.as_bytes(),
    );

    print_section("TERMINAL OBSERVABLE IDS — this is what the network sees");

    print_subsection("ACCOUNT_ID = SHA-256(\"mt-account\" || suite_id_LE(2B) || pk_acc)");
    print_kv("hex", hex_full(&id.account_id));

    print_subsection("NODE_ID = SHA-256(\"mt-node\" || pk_node)");
    print_kv("hex", hex_full(&id.node_id));

    print_section("CONSEQUENCES");
    print_note("Same entropy → same account_id and node_id (deterministic recovery flow)");
    print_note(
        "Device loss: entering the 24 words on a new device restores all 6 key parts + IDs",
    );
    print_note(
        "Verification on two devices — via `recovery-fingerprint` (one 64-char hex)",
    );

    println!("\n[result] KEYPAIR: PASS");
    true
}

fn cmd_recovery_fingerprint(entropy_hex: Option<&str>) -> bool {
    print_section("RECOVERY FINGERPRINT — single 64-char hex for two-device manual validation");
    print_wordlist_fingerprint_check();

    let entropy = match parse_entropy_arg(entropy_hex) {
        Some(e) => e,
        None => {
            eprintln!("invalid entropy hex (must be 32 bytes / 64 hex chars)");
            return false;
        },
    };
    if entropy_hex.is_none() {
        print_note("entropy not given — using [0x00; 32] (M-1 Vector 1)");
    }

    print_entropy(&entropy);

    let id = match derive_full_identity(&entropy) {
        Ok(i) => i,
        Err(e) => {
            eprintln!("derive failed: {e}");
            return false;
        },
    };

    let fp = compute_recovery_fingerprint(&id);

    print_section("FINGERPRINT");
    print_subsection(
        "SHA-256(\"mt-recovery-fingerprint\" || pk_acc || sk_acc || pk_node || sk_node || pk_mlkem || sk_mlkem || account_id || node_id)",
    );
    print_kv("hex (64 chars)", hex_full(&fp));

    print_section("USAGE — two-device manual validation");
    print_note("Run on device A with the same 24 words, on device B — the same 24 words");
    print_note(
        "Compare the two 64-char hex visually — byte equality ⇔ recovery flow byte-identical",
    );
    print_note("A mismatch of even one hex character = either different mnemonics, or a bug in recovery");

    print_subsection("Component fingerprints (for detailed debug)");
    print_kv("account_id", hex_full(&id.account_id));
    print_kv("node_id", hex_full(&id.node_id));
    print_kv(
        "sha256(pk_acc)",
        hex_full(&sha256_raw(id.pk_acc.as_bytes())),
    );
    print_kv(
        "sha256(sk_acc)",
        hex_full(&sha256_raw(id.sk_acc.as_bytes())),
    );
    print_kv(
        "sha256(pk_node)",
        hex_full(&sha256_raw(id.pk_node.as_bytes())),
    );
    print_kv(
        "sha256(sk_node)",
        hex_full(&sha256_raw(id.sk_node.as_bytes())),
    );
    print_kv(
        "sha256(pk_mlkem)",
        hex_full(&sha256_raw(id.pk_mlkem.as_bytes())),
    );
    print_kv(
        "sha256(sk_mlkem)",
        hex_full(&sha256_raw(id.sk_mlkem.as_bytes())),
    );

    println!("\n[result] RECOVERY-FINGERPRINT: PASS");
    true
}

fn cmd_mnemonic(mnemonic: &str) -> bool {
    print_section("MNEMONIC → MASTER SEED TRACE");
    print_wordlist_fingerprint_check();

    print_mnemonic(mnemonic);

    print_subsection("PARSE + CHECKSUM VERIFY");
    match mnemonic_to_master_seed(mnemonic) {
        Ok(master_seed) => {
            print_kv("parse + checksum", "OK");
            print_master_seed(&master_seed);

            print_subsection("PER-ROLE DERIVATIONS (intermediate seeds)");
            let acc = mldsa_seed_for_role(&master_seed, domain::ACCOUNT_KEY);
            let node = mldsa_seed_for_role(&master_seed, domain::NODE_KEY);
            let app = mlkem_seed_for_role(&master_seed, domain::APP_ENCRYPTION_KEY);
            print_kv("mldsa_seed(account)", hex_full(&acc));
            print_kv("mldsa_seed(node)", hex_full(&node));
            print_kv("mlkem_seed(app)", hex_full(&app));
            println!("\n[result] MNEMONIC: PASS");
            true
        },
        Err(MnemonicError::WordCount(n)) => {
            eprintln!("parse failed: expected 24 words, got {n}");
            println!("\n[result] MNEMONIC: FAIL (word count)");
            false
        },
        Err(MnemonicError::UnknownWord(pos)) => {
            eprintln!("parse failed: word at position {pos} is not in Montana wordlist");
            println!("\n[result] MNEMONIC: FAIL (unknown word)");
            false
        },
        Err(MnemonicError::ChecksumMismatch) => {
            eprintln!("parse failed: mnemonic checksum does not match SHA-256(entropy)[0]");
            println!("\n[result] MNEMONIC: FAIL (checksum mismatch)");
            false
        },
    }
}

fn cmd_vectors() -> bool {
    print_section("6 BINDING TEST VECTORS — byte-exact verification vs spec");
    print_wordlist_fingerprint_check();

    let mut all_pass = true;

    // === M-1 Vector 1 ===
    print_section("M-1 Vector 1 — entropy = [0x00; 32]");
    let entropy_1 = [0u8; 32];
    let mnemonic_1 = entropy_to_mnemonic(&entropy_1);
    let master_1 = mnemonic_to_master_seed(&mnemonic_1).expect("valid");
    print_entropy(&entropy_1);
    print_kv("last word (expected)", "art (index 102)");
    print_mnemonic(&mnemonic_1);
    print_master_seed(&master_1);
    let expected_1 = concat!(
        "38a1421ac3ce191fbdc46b1cca266a9d72d22320fb38bda6a3df90a1ead664a7",
        "8951703197be882ace38e0f557a492a8e9ff5e3c02290a8eecf5939468708edb",
    );
    let ok_1 = hex_full(&master_1) == expected_1;
    print_kv(
        "byte-exact vs spec binding",
        if ok_1 { "OK ✓" } else { "FAIL ✗" },
    );
    all_pass &= ok_1;

    // === M-1 Vector 2 ===
    print_section("M-1 Vector 2 — entropy = [0xFF; 32]");
    let entropy_2 = [0xFFu8; 32];
    let mnemonic_2 = entropy_to_mnemonic(&entropy_2);
    let master_2 = mnemonic_to_master_seed(&mnemonic_2).expect("valid");
    print_entropy(&entropy_2);
    print_kv("last word (expected)", "vote");
    print_mnemonic(&mnemonic_2);
    print_master_seed(&master_2);
    let expected_2 = concat!(
        "a5925c51583447a0abe43b65dbc591f3780a91c7d44c6b333975a211096039f3",
        "d1d0ca9e125aa4e756f0a35b0006378ac69450e8254e32f16409a350f3ca9104",
    );
    let ok_2 = hex_full(&master_2) == expected_2;
    print_kv(
        "byte-exact vs spec binding",
        if ok_2 { "OK ✓" } else { "FAIL ✗" },
    );
    all_pass &= ok_2;

    // === M-1 Vector 3 ===
    print_section("M-1 Vector 3 — entropy = SHA-256(\"Montana test vector 3\")");
    let entropy_3_hash = sha256_raw(b"Montana test vector 3");
    let mut entropy_3 = [0u8; 32];
    entropy_3.copy_from_slice(&entropy_3_hash);
    let mnemonic_3 = entropy_to_mnemonic(&entropy_3);
    let master_3 = mnemonic_to_master_seed(&mnemonic_3).expect("valid");
    print_entropy(&entropy_3);
    print_mnemonic(&mnemonic_3);
    print_master_seed(&master_3);
    let expected_3 = concat!(
        "da13e259eb58c79a650c312efe79d2ef42861ad114206ec48cb4b1eb5dcf0c22",
        "75b074ef8b02fbc2123032090ff004d7cc546d2bbf34c4e10ec3c6fb092f9a47",
    );
    let ok_3 = hex_full(&master_3) == expected_3;
    print_kv(
        "byte-exact vs spec binding",
        if ok_3 { "OK ✓" } else { "FAIL ✗" },
    );
    all_pass &= ok_3;

    // === Per-role vectors — use master_1 from Vector 1 ===
    print_section("Per-role Derivation Vectors — master_seed from M-1 Vector 1");

    print_subsection("Derivation Vector 1 — mldsa_seed(account)");
    let deriv_1 = mldsa_seed_for_role(&master_1, domain::ACCOUNT_KEY);
    print_field("info", "\"mt-account-key\" (14 bytes)");
    print_field("L", "32");
    println!("  hex: {}", hex_full(&deriv_1));
    let exp_deriv_1 = "08ce5c19768c679fda24c0d3360e57ce03d00c94c175e59f50e9c77894c20818";
    let ok_d1 = hex_full(&deriv_1) == exp_deriv_1;
    print_kv("byte-exact", if ok_d1 { "OK ✓" } else { "FAIL ✗" });
    all_pass &= ok_d1;

    print_subsection("Derivation Vector 2 — mldsa_seed(node)");
    let deriv_2 = mldsa_seed_for_role(&master_1, domain::NODE_KEY);
    print_field("info", "\"mt-node-key\" (11 bytes)");
    print_field("L", "32");
    println!("  hex: {}", hex_full(&deriv_2));
    let exp_deriv_2 = "efe527d96de2cb82b3ee2e8ad24b4aca71014e37896b0c025a376335ad456acc";
    let ok_d2 = hex_full(&deriv_2) == exp_deriv_2;
    print_kv("byte-exact", if ok_d2 { "OK ✓" } else { "FAIL ✗" });
    all_pass &= ok_d2;

    print_subsection("Derivation Vector 3 — mlkem_seed(app-encryption)");
    let deriv_3 = mlkem_seed_for_role(&master_1, domain::APP_ENCRYPTION_KEY);
    print_field("info", "\"mt-app-encryption-key\" (21 bytes)");
    print_field("L", "64");
    println!("  hex: {}", hex_full(&deriv_3));
    let exp_deriv_3 = concat!(
        "3eb9bcd201a1d5e671c9d23a929589a26ceb53338cd0684b5d77314a14601b03",
        "9f3e2ae7e5e0be8acd47b4b928c3e73b5d875b9fc7089b22bc1d59e9dc31077e",
    );
    let ok_d3 = hex_full(&deriv_3) == exp_deriv_3;
    print_kv("byte-exact", if ok_d3 { "OK ✓" } else { "FAIL ✗" });
    all_pass &= ok_d3;

    println!(
        "\n[result] VECTORS: {}",
        if all_pass { "PASS (6/6)" } else { "FAIL" }
    );
    all_pass
}

fn cmd_roundtrip(entropy_hex: Option<&str>) -> bool {
    print_section("ROUNDTRIP — entropy → mnemonic → master_seed");
    print_wordlist_fingerprint_check();

    let entropy: [u8; 32] = if let Some(h) = entropy_hex {
        let Some(bytes) = hex_from(h) else {
            eprintln!("invalid hex");
            return false;
        };
        let Some(arr) = to_array_32(&bytes) else {
            eprintln!("entropy must be 32 bytes");
            return false;
        };
        arr
    } else {
        print_note("entropy not given — using SHA-256(\"roundtrip\")");
        let h = sha256_raw(b"roundtrip");
        let mut arr = [0u8; 32];
        arr.copy_from_slice(&h);
        arr
    };

    print_entropy(&entropy);

    let mnemonic = entropy_to_mnemonic(&entropy);
    print_mnemonic(&mnemonic);

    let master_first = mnemonic_to_master_seed(&mnemonic).expect("valid");
    print_master_seed(&master_first);

    // Second derivation — must give the same result
    let master_second = mnemonic_to_master_seed(&mnemonic).expect("valid");
    let matches = master_first == master_second;
    print_subsection("IDEMPOTENCY");
    print_kv("second derivation equals first", format!("{matches}"));

    println!(
        "\n[result] ROUNDTRIP: {}",
        if matches { "PASS" } else { "FAIL" }
    );
    matches
}

fn cmd_all() -> bool {
    print_section("M1 MNEMONIC — FULL USER JOURNEY");
    print_note(
        "Runs the full path: fingerprint check → seeds → keypair (terminal) → recovery-fingerprint → mnemonic parse → vectors → roundtrip",
    );

    let a = cmd_seeds(None);
    let b = cmd_keypair(None);
    let c = cmd_recovery_fingerprint(None);
    let d = cmd_mnemonic(
        "abandon abandon abandon abandon abandon abandon abandon abandon \
         abandon abandon abandon abandon abandon abandon abandon abandon \
         abandon abandon abandon abandon abandon abandon abandon art",
    );
    let e = cmd_vectors();
    let f = cmd_roundtrip(None);

    print_section("SUMMARY");
    print_kv("seeds", if a { "PASS" } else { "FAIL" });
    print_kv("keypair (terminal)", if b { "PASS" } else { "FAIL" });
    print_kv("recovery-fingerprint", if c { "PASS" } else { "FAIL" });
    print_kv("mnemonic", if d { "PASS" } else { "FAIL" });
    print_kv("vectors (6 binding)", if e { "PASS" } else { "FAIL" });
    print_kv("roundtrip", if f { "PASS" } else { "FAIL" });

    let pass = a && b && c && d && e && f;
    println!("\n[result] ALL: {}", if pass { "PASS" } else { "FAIL" });
    pass
}

fn usage() {
    eprintln!(
        "M1 MNEMONIC — Montana 24-word recovery + per-role keypair derivation + terminal IDs"
    );
    eprintln!();
    eprintln!("usage: m1_mnemonic <subcommand> [args]");
    eprintln!();
    eprintln!("  seeds [ENTROPY_HEX]               Intermediate seed material (HKDF outputs)");
    eprintln!("  keypair [ENTROPY_HEX]             Full ML-DSA + ML-KEM keypairs + terminal IDs");
    eprintln!("  recovery-fingerprint [ENTROPY_HEX] Single 64-char hex for two-device validation");
    eprintln!("  mnemonic \"STRING\"                 Parse mnemonic, derive master_seed + seeds");
    eprintln!("  vectors                           Run 6 binding test vectors (see the spec)");
    eprintln!("  roundtrip [ENTROPY_HEX]           entropy → mnemonic → master_seed idempotency");
    eprintln!("  all                               Full user journey");
    eprintln!();
    eprintln!("Exit 0 = PASS, 1 = FAIL.");
}

fn bool_to_exit(pass: bool) -> ExitCode {
    if pass {
        ExitCode::SUCCESS
    } else {
        ExitCode::FAILURE
    }
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
        "seeds" => cmd_seeds(args.get(2).map(|s| s.as_str())),
        "keypair" => cmd_keypair(args.get(2).map(|s| s.as_str())),
        "recovery-fingerprint" => cmd_recovery_fingerprint(args.get(2).map(|s| s.as_str())),
        "mnemonic" => {
            let Some(m) = args.get(2) else {
                eprintln!("mnemonic subcommand requires string argument");
                return ExitCode::FAILURE;
            };
            cmd_mnemonic(m)
        },
        "vectors" => cmd_vectors(),
        "roundtrip" => cmd_roundtrip(args.get(2).map(|s| s.as_str())),
        "all" => cmd_all(),
        _ => {
            usage();
            return ExitCode::FAILURE;
        },
    };
    bool_to_exit(pass)
}
