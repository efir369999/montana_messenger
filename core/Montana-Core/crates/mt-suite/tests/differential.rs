// The differential check: what this tree computes is put to a second, independent
// implementation of the same standards — OpenSSL, a C codebase written by other people from
// the same documents — and the two must agree byte for byte. Published vectors say the code
// matches the standard's own answers; this says two living implementations meet on values
// neither of them published.
//
// A machine without the second implementation cannot run this check — and a check that did not
// run is not a check that passed. Absence therefore fails and names what is missing, because a
// green run that never compared anything is the one state this whole layer exists to forbid.
// Every run ends by stating who took part and on what, so the record of a build says which two
// implementations met rather than that a test was green.

use mt_suite::{aead, kem, sign};
use std::process::Command;

// A raw key becomes a SubjectPublicKeyInfo the way every DER encoder builds one: the algorithm
// identifier of the standard, then the key as a bit string. Both objects here are of a fixed
// size, so every length is known before a byte is written.
fn spki(oid: &[u8], key: &[u8]) -> Vec<u8> {
    let mut bitstring = vec![0x00];
    bitstring.extend_from_slice(key);
    let mut inner = Vec::new();
    inner.extend_from_slice(oid);
    inner.push(0x03);
    inner.extend_from_slice(&der_len(bitstring.len()));
    inner.extend_from_slice(&bitstring);
    let mut out = vec![0x30];
    out.extend_from_slice(&der_len(inner.len()));
    out.extend_from_slice(&inner);
    out
}

fn der_len(n: usize) -> Vec<u8> {
    if n < 0x80 {
        vec![n as u8]
    } else if n < 0x100 {
        vec![0x81, n as u8]
    } else {
        vec![0x82, (n >> 8) as u8, (n & 0xFF) as u8]
    }
}

// The algorithm identifier OpenSSL prints for the signature standard. The KEM needs none: its
// public half is read out of what OpenSSL itself wrote.
const ML_DSA_65_ALGID: &[u8] = &[
    0x30, 0x0b, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x03, 0x12,
];

fn openssl_speaks(algorithm: &str, list: &str) -> bool {
    Command::new("openssl")
        .args(["list", &format!("-{list}")])
        .output()
        .map(|o| String::from_utf8_lossy(&o.stdout).contains(algorithm))
        .unwrap_or(false)
}

fn write_temp(name: &str, bytes: &[u8]) -> std::path::PathBuf {
    let path = std::env::temp_dir().join(format!("mt-suite-differential-{name}"));
    std::fs::write(&path, bytes).expect("a temporary file is writable");
    path
}

#[test]
fn openssl_verifies_what_this_tree_signs() {
    assert!(
        openssl_speaks("ML-DSA-65", "signature-algorithms"),
        "the second implementation is absent: this machine's openssl carries no ML-DSA-65, so \
         nothing was compared. Install an openssl of 3.5 or later and run again."
    );
    let seed = [0x5Au8; sign::SEED_BYTES];
    let (public, secret) = sign::keypair_from_seed(&seed);
    let message = b"two implementations meet on a value neither of them published";
    let signature = sign::sign(&secret, message).expect("signs");

    let key_path = write_temp("pk.der", &spki(ML_DSA_65_ALGID, public.as_bytes()));
    let sig_path = write_temp("sig.bin", signature.as_bytes());
    let msg_path = write_temp("msg.bin", message);

    let run = |sig: &std::path::Path, msg: &std::path::Path| -> bool {
        Command::new("openssl")
            .args(["pkeyutl", "-verify", "-pubin", "-keyform", "DER", "-inkey"])
            .arg(&key_path)
            .args(["-rawin", "-in"])
            .arg(msg)
            .arg("-sigfile")
            .arg(sig)
            .output()
            .map(|o| o.status.success())
            .unwrap_or(false)
    };
    assert!(
        run(&sig_path, &msg_path),
        "openssl refuses a signature this tree produced"
    );

    // And it refuses a doctored one, which is what says the check above was a check.
    let mut doctored = *signature.as_bytes();
    doctored[0] ^= 1;
    let doctored_path = write_temp("sig-doctored.bin", &doctored);
    assert!(
        !run(&doctored_path, &msg_path),
        "openssl accepts a signature nobody produced"
    );
    ledger(
        "ML-DSA-65",
        "libcrux-ml-dsa",
        &openssl_version(),
        "signature verified, doctored refused",
    );
}

// The signature standard is the one primitive of the three whose agreement can be read in bytes
// rather than in a verdict, and that is the whole point of taking it in its deterministic form:
// an identifier of this protocol is taken over signed scope, so two implementations signing one
// act with one key must write one signature or they write two different objects. Acceptance says
// only that the second implementation parses ours; this says the two produce the same bytes from
// the same seed, which is the property the objects stand on.
#[test]
fn two_implementations_write_one_key_and_one_signature_from_one_seed() {
    assert!(
        openssl_speaks("ML-DSA-65", "signature-algorithms"),
        "the second implementation is absent: this machine's openssl carries no ML-DSA-65, so \
         nothing was compared. Install an openssl of 3.5 or later and run again."
    );
    let seed = [0x5Au8; sign::SEED_BYTES];
    let (public, secret) = sign::keypair_from_seed(&seed);

    // The same seed on the other side: the standard derives a key from thirty-two bytes, so the
    // two implementations hold one key rather than two keys that verify each other.
    let key_path = std::env::temp_dir().join("mt-suite-differential-mldsa-seeded.pem");
    let generated = Command::new("openssl")
        .args([
            "genpkey",
            "-algorithm",
            "ML-DSA-65",
            "-pkeyopt",
            &format!("hexseed:{}", hex(&seed)),
            "-out",
        ])
        .arg(&key_path)
        .status()
        .map(|s| s.success())
        .unwrap_or(false);
    assert!(
        generated,
        "this openssl draws no ML-DSA-65 key from a stated seed, so the key generation of the two \
         implementations was not compared"
    );

    // The public half OpenSSL wrote, read out of its own encoding: the raw key is the tail of the
    // structure, whose width the set fixes.
    let printed = Command::new("openssl")
        .args(["pkey", "-pubout", "-outform", "DER", "-in"])
        .arg(&key_path)
        .output()
        .expect("openssl prints the public half");
    assert!(printed.status.success(), "openssl prints the public half");
    let der = printed.stdout;
    let theirs = &der[der.len() - mt_codec::size::SIGNING_PUBLIC_KEY..];
    assert_eq!(
        theirs,
        public.as_bytes(),
        "one seed, two public keys: the two implementations do not generate alike"
    );

    let message = b"two implementations meet on a value neither of them published";
    let ours = sign::sign(&secret, message).expect("signs");
    let msg_path = write_temp("mldsa-seeded-msg.bin", message);
    let sig_path = std::env::temp_dir().join("mt-suite-differential-mldsa-seeded.sig");
    let signed = Command::new("openssl")
        .args(["pkeyutl", "-sign", "-inkey"])
        .arg(&key_path)
        .args(["-rawin", "-in"])
        .arg(&msg_path)
        .args(["-pkeyopt", "deterministic:1", "-out"])
        .arg(&sig_path)
        .status()
        .map(|s| s.success())
        .unwrap_or(false);
    assert!(
        signed,
        "this openssl signs no ML-DSA-65 in the deterministic form the set takes, so the two \
         signatures were not compared"
    );
    let theirs = std::fs::read(&sig_path).expect("the signature is readable");
    assert_eq!(
        theirs.len(),
        mt_codec::size::SIGNATURE,
        "the second implementation wrote a signature of another width"
    );
    assert_eq!(
        theirs,
        ours.as_bytes().to_vec(),
        "one key and one message, two signatures: the deterministic form is not deterministic \
         across the two implementations, and every identifier taken over signed scope parts with it"
    );
    ledger(
        "ML-DSA-65",
        "libcrux-ml-dsa",
        &openssl_version(),
        "key and signature agreed byte for byte from one seed",
    );
}

#[test]
fn this_tree_and_openssl_land_on_one_shared_secret() {
    assert!(
        openssl_speaks("ML-KEM-768", "kem-algorithms"),
        "the second implementation is absent: this machine's openssl carries no ML-KEM-768, so \
         nothing was compared. Install an openssl of 3.5 or later and run again."
    );
    // OpenSSL draws the pair, this tree encapsulates to it, OpenSSL decapsulates: the secret
    // is a value neither implementation published and both must reach.
    let key_path = std::env::temp_dir().join("mt-suite-differential-kem.pem");
    let generated = Command::new("openssl")
        .args(["genpkey", "-algorithm", "ML-KEM-768", "-out"])
        .arg(&key_path)
        .status()
        .map(|s| s.success())
        .unwrap_or(false);
    assert!(generated, "openssl draws a pair");

    let spki_der = Command::new("openssl")
        .args(["pkey", "-pubout", "-outform", "DER", "-in"])
        .arg(&key_path)
        .output()
        .expect("openssl prints the public half");
    let der = spki_der.stdout;
    let raw = &der[der.len() - mt_codec::size::KEM_PUBLIC_KEY..];
    let public = kem::PublicKey::from_bytes(raw.try_into().expect("a key of its size"));

    let (ciphertext, ours) =
        kem::encapsulate_with_randomness(&public, [0x77u8; kem::SHARED_SECRET_BYTES]);
    let ct_path = write_temp("ct.bin", ciphertext.as_bytes());

    let out = Command::new("openssl")
        .args(["pkeyutl", "-decap", "-inkey"])
        .arg(&key_path)
        .arg("-in")
        .arg(&ct_path)
        .output()
        .expect("openssl decapsulates");
    assert!(out.status.success(), "openssl refuses our ciphertext");
    assert_eq!(
        out.stdout,
        ours.as_bytes().to_vec(),
        "the two implementations reach two different secrets"
    );

    // A doctored ciphertext must not land on our secret either — the standard answers with an
    // implicit rejection value rather than an error, and that value is not ours.
    let mut doctored = *ciphertext.as_bytes();
    doctored[0] ^= 1;
    let doctored_path = write_temp("ct-doctored.bin", &doctored);
    let other = Command::new("openssl")
        .args(["pkeyutl", "-decap", "-inkey"])
        .arg(&key_path)
        .arg("-in")
        .arg(&doctored_path)
        .output()
        .expect("openssl answers");
    if other.status.success() {
        assert_ne!(other.stdout, ours.as_bytes().to_vec());
    }
    ledger(
        "ML-KEM-768",
        "libcrux-ml-kem",
        &openssl_version(),
        "shared secret agreed",
    );
}

#[test]
fn a_second_implementation_seals_and_opens_what_this_tree_does() {
    // The sealing standard's second implementation here is the one in the Python
    // cryptography library, which stands on OpenSSL's own primitive through a different
    // binding. A machine without it cannot run the check, which is not a check that failed.
    let probe = Command::new("python3")
        .args(["-c", "import cryptography"])
        .status()
        .map(|s| s.success())
        .unwrap_or(false);
    assert!(
        probe,
        "the second implementation is absent: this machine's python3 carries no cryptography \
         module, so nothing was compared. Install it and run again."
    );
    let key_bytes = [0x31u8; aead::KEY_BYTES];
    let nonce = [0x32u8; mt_codec::size::AEAD_NONCE];
    let associated = b"the header two implementations read alike";
    let plaintext = b"a body neither of them published";
    let key = aead::SealingKey::new(key_bytes);
    let ours = aead::seal(&key, &nonce, associated, plaintext).expect("seals");

    let script = format!(
        "import sys\n\
         from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305\n\
         k=bytes.fromhex('{}')\n\
         n=bytes.fromhex('{}')\n\
         a=bytes.fromhex('{}')\n\
         p=bytes.fromhex('{}')\n\
         c=bytes.fromhex('{}')\n\
         theirs=ChaCha20Poly1305(k).encrypt(n,p,a)\n\
         assert theirs==c, 'the two sealings differ'\n\
         assert ChaCha20Poly1305(k).decrypt(n,c,a)==p, 'the opening differs'\n\
         sys.stdout.write('agreed')\n",
        hex(&key_bytes),
        hex(&nonce),
        hex(associated),
        hex(plaintext),
        hex(&ours)
    );
    let out = Command::new("python3")
        .args(["-c", &script])
        .output()
        .expect("python answers");
    assert!(
        out.status.success() && out.stdout == b"agreed",
        "the second implementation disagrees: {}",
        String::from_utf8_lossy(&out.stderr)
    );
    ledger(
        "ChaCha20-Poly1305",
        "chacha20poly1305",
        "python cryptography",
        "sealing and opening agreed",
    );
}

// The third implementation: liboqs, whose ML-KEM is mlkem-native and whose ML-DSA is
// mldsa-native — C code from neither the libcrux nor the OpenSSL family. Two agreements with
// OpenSSL say two implementations meet; a third, written apart from both, is what tells a shared
// misreading of the standard from the standard. It is reached through its own C interface rather
// than a binding, so nothing between the two sides translates a byte. The library is named by
// MT_LIBOQS, the path of the shared object; a machine without it compared nothing and says so.
const LIBOQS_PROBE: &str = r#"
import ctypes, sys
lib = ctypes.CDLL(sys.argv[1])
lib.OQS_init()
lib.OQS_version.restype = ctypes.c_char_p
lib.OQS_KEM_new.restype = ctypes.c_void_p
lib.OQS_SIG_new.restype = ctypes.c_void_p
def ok(rc, what):
    if rc != 0:
        raise SystemExit(what + ' refused')
def say(name, value):
    sys.stdout.write(name + ' ' + value + chr(10))
say('version', lib.OQS_version().decode())
mode = sys.argv[2]
if mode == 'kem':
    pk_n, sk_n, ct_n, ss_n = (int(a) for a in sys.argv[3:7])
    seed, m, ours = (bytes.fromhex(a) for a in sys.argv[7:10])
    kem = ctypes.c_void_p(lib.OQS_KEM_new(b'ML-KEM-768'))
    if not kem.value:
        raise SystemExit('ML-KEM-768 is not enabled in this liboqs')
    pk, sk = ctypes.create_string_buffer(pk_n), ctypes.create_string_buffer(sk_n)
    ct, ss = ctypes.create_string_buffer(ct_n), ctypes.create_string_buffer(ss_n)
    ok(lib.OQS_KEM_keypair_derand(kem, pk, sk, seed), 'keypair_derand')
    ok(lib.OQS_KEM_encaps_derand(kem, ct, ss, pk, m), 'encaps_derand')
    opened = ctypes.create_string_buffer(ss_n)
    ok(lib.OQS_KEM_decaps(kem, opened, ours, sk), 'decaps')
    doctored = bytes([ours[0] ^ 1]) + ours[1:]
    rejected = ctypes.create_string_buffer(ss_n)
    ok(lib.OQS_KEM_decaps(kem, rejected, doctored, sk), 'decaps of the doctored')
    say('pk', pk.raw.hex()); say('ct', ct.raw.hex()); say('ss', ss.raw.hex())
    say('opened', opened.raw.hex()); say('rejected', rejected.raw.hex())
elif mode == 'sig':
    pk_n, sk_n, sig_n = (int(a) for a in sys.argv[3:6])
    pk_ours, sig_ours, msg = (bytes.fromhex(a) for a in sys.argv[6:9])
    sig = ctypes.c_void_p(lib.OQS_SIG_new(b'ML-DSA-65'))
    if not sig.value:
        raise SystemExit('ML-DSA-65 is not enabled in this liboqs')
    def verify(s, k):
        return lib.OQS_SIG_verify(sig, msg, ctypes.c_size_t(len(msg)), s, ctypes.c_size_t(len(s)), k) == 0
    doctored = bytes([sig_ours[0] ^ 1]) + sig_ours[1:]
    say('accepts', str(verify(sig_ours, pk_ours)))
    say('accepts_doctored', str(verify(doctored, pk_ours)))
    pk, sk = ctypes.create_string_buffer(pk_n), ctypes.create_string_buffer(sk_n)
    ok(lib.OQS_SIG_keypair(sig, pk, sk), 'keypair')
    out, out_n = ctypes.create_string_buffer(sig_n), ctypes.c_size_t(0)
    ok(lib.OQS_SIG_sign(sig, out, ctypes.byref(out_n), msg, ctypes.c_size_t(len(msg)), sk), 'sign')
    say('pk', pk.raw.hex()); say('sig', out.raw[:out_n.value].hex())
else:
    raise SystemExit('unknown mode ' + mode)
"#;

fn liboqs(mode: &str, args: &[String]) -> std::collections::BTreeMap<String, String> {
    let library = std::env::var("MT_LIBOQS").unwrap_or_default();
    assert!(
        !library.is_empty() && std::path::Path::new(&library).exists(),
        "the third implementation is absent: MT_LIBOQS names no liboqs shared object on this \
         machine, so nothing was compared. Build liboqs with OQS_USE_OPENSSL=OFF and \
         BUILD_SHARED_LIBS=ON and point MT_LIBOQS at the library."
    );
    let out = Command::new("python3")
        .args(["-c", LIBOQS_PROBE, &library, mode])
        .args(args)
        .output()
        .expect("python answers");
    assert!(
        out.status.success(),
        "liboqs refused: {}",
        String::from_utf8_lossy(&out.stderr)
    );
    String::from_utf8_lossy(&out.stdout)
        .lines()
        .filter_map(|l| l.split_once(' '))
        .map(|(k, v)| (k.to_string(), v.to_string()))
        .collect()
}

fn unhex(text: &str) -> Vec<u8> {
    (0..text.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&text[i..i + 2], 16).expect("liboqs writes hex"))
        .collect()
}

// A seed whose bytes all differ: a key generation that read `z || d` for `d || z`, or a half
// of the seed in reverse, lands on another key here, where a constant seed would hide it.
fn stepped<const N: usize>(start: u8, step: u8) -> [u8; N] {
    let mut out = [0u8; N];
    for (i, b) in out.iter_mut().enumerate() {
        *b = start.wrapping_add((i as u8).wrapping_mul(step));
    }
    out
}

#[test]
fn liboqs_and_this_tree_draw_one_key_and_reach_one_secret_from_one_seed() {
    let seed: [u8; kem::SEED_BYTES] = stepped(0x11, 29);
    let randomness: [u8; kem::SHARED_SECRET_BYTES] = stepped(0xA3, 13);
    let (public, secret) = kem::keypair_from_seed(&seed);
    let (ciphertext, ours) = kem::encapsulate_with_randomness(&public, randomness);

    let theirs = liboqs(
        "kem",
        &[
            mt_codec::size::KEM_PUBLIC_KEY.to_string(),
            mt_codec::size::KEM_SECRET_KEY.to_string(),
            kem::CIPHERTEXT_BYTES.to_string(),
            kem::SHARED_SECRET_BYTES.to_string(),
            hex(&seed),
            hex(&randomness),
            hex(ciphertext.as_bytes()),
        ],
    );
    assert_eq!(
        unhex(&theirs["pk"]),
        public.as_bytes().to_vec(),
        "one seed, two public keys: liboqs and this tree do not generate alike"
    );
    assert_eq!(
        unhex(&theirs["ct"]),
        ciphertext.as_bytes().to_vec(),
        "one key and one randomness, two ciphertexts"
    );
    assert_eq!(
        unhex(&theirs["ss"]),
        ours.as_bytes().to_vec(),
        "one key and one randomness, two secrets"
    );
    assert_eq!(
        unhex(&theirs["opened"]),
        ours.as_bytes().to_vec(),
        "liboqs opens our ciphertext to another secret"
    );
    assert_ne!(
        unhex(&theirs["rejected"]),
        ours.as_bytes().to_vec(),
        "a doctored ciphertext lands on our secret in liboqs"
    );

    // And this tree opens what liboqs sealed, so the agreement runs in both directions.
    let their_ct: [u8; kem::CIPHERTEXT_BYTES] = unhex(&theirs["ct"])
        .try_into()
        .expect("a ciphertext of its size");
    let opened = kem::decapsulate(&secret, &kem::Ciphertext::from_bytes(their_ct));
    assert_eq!(
        opened.as_bytes().to_vec(),
        unhex(&theirs["ss"]),
        "this tree opens the liboqs ciphertext to another secret"
    );
    ledger(
        "ML-KEM-768",
        "libcrux-ml-kem",
        &format!("liboqs {} (mlkem-native)", theirs["version"]),
        "key, ciphertext and secret agreed byte for byte from one seed and one randomness; each opened the other's",
    );
}

// liboqs signs only in the hedged form and draws its keys only at random, so the signature is
// compared by verdicts in both directions rather than in bytes; the bytes are compared with
// OpenSSL above.
#[test]
fn liboqs_and_this_tree_verify_each_other_and_refuse_the_doctored() {
    let seed: [u8; sign::SEED_BYTES] = stepped(0x5A, 37);
    let (public, secret) = sign::keypair_from_seed(&seed);
    let message = b"a third implementation meets the two on a value none of them published";
    let ours = sign::sign(&secret, message).expect("signs");

    let theirs = liboqs(
        "sig",
        &[
            mt_codec::size::SIGNING_PUBLIC_KEY.to_string(),
            mt_codec::size::SIGNING_SECRET_KEY.to_string(),
            mt_codec::size::SIGNATURE.to_string(),
            hex(public.as_bytes()),
            hex(ours.as_bytes()),
            hex(message),
        ],
    );
    assert_eq!(
        theirs["accepts"], "True",
        "liboqs refuses a signature this tree produced"
    );
    assert_eq!(
        theirs["accepts_doctored"], "False",
        "liboqs accepts a signature nobody produced"
    );

    let their_key: [u8; mt_codec::size::SIGNING_PUBLIC_KEY] =
        unhex(&theirs["pk"]).try_into().expect("a key of its size");
    let their_sig: [u8; mt_codec::size::SIGNATURE] = unhex(&theirs["sig"])
        .try_into()
        .expect("liboqs wrote a signature of the set's width");
    let their_key = sign::PublicKey::from_bytes(their_key);
    assert!(
        sign::verify(&their_key, message, &sign::Signature::from_bytes(their_sig)).is_ok(),
        "this tree refuses a signature liboqs produced"
    );
    let mut doctored = their_sig;
    doctored[0] ^= 1;
    assert!(
        sign::verify(&their_key, message, &sign::Signature::from_bytes(doctored)).is_err(),
        "this tree accepts a doctored liboqs signature"
    );
    ledger(
        "ML-DSA-65",
        "libcrux-ml-dsa",
        &format!("liboqs {} (mldsa-native)", theirs["version"]),
        "each verified the other's signature and refused the doctored",
    );
}

// What a run states about itself: the primitive, the two implementations that met, and what
// they met on. A reader of a build log sees the comparison rather than a colour.
fn ledger(primitive: &str, ours: &str, theirs: &str, on: &str) {
    println!("differential | {primitive} | {ours} vs {theirs} | {on}");
}

fn openssl_version() -> String {
    Command::new("openssl")
        .arg("version")
        .output()
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .unwrap_or_else(|_| "openssl (version unread)".to_string())
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}
