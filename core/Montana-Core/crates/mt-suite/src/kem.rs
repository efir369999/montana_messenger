// ML-KEM-768. The set states it in `docs/Montana Canon.md`, "Primitives": the encapsulation of
// the application plane and of the handshake, at the sizes the table fixes.
//
// A key of a person is generated from a branch of their seed, sixty-four bytes wide, and from
// nothing else — the same words on another device answer with the same key, which is what makes
// stored content readable again after a loss.

use libcrux_ml_kem::mlkem768;
use libcrux_ml_kem::MlKemPrivateKey;
use mt_codec::size;
use zeroize::Zeroize;

mt_codec::constants! {
    KEM_WIDTHS:
    /// The branch of a seed this scheme is generated from.
    pub const SEED_BYTES: usize = 64, writes "HKDF-Expand(master_seed, \"mt-app-encryption-key\", 64)";
    /// The shared secret the standard gives, which the set does not restate.
    pub const SHARED_SECRET_BYTES: usize = 32, code "the shared secret of ML-KEM-768, fixed by FIPS 203";
}
// The width lives with the other sizes of the set; this is the name this module reads it by.
pub const CIPHERTEXT_BYTES: usize = size::KEM_CIPHERTEXT;

#[derive(Debug, PartialEq, Eq)]
pub struct DecapsulationKeyRejected;

// A value this primitive requires to be drawn could not be drawn. Nothing proceeds without it:
// two encapsulations to one key under one randomness land on one secret.
#[derive(Debug, PartialEq, Eq)]
pub struct Undrawn;

// A public value: what it holds is meant to be shown, so it derives what a test needs.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct PublicKey([u8; size::KEM_PUBLIC_KEY]);

// The secret half holds its own bytes rather than the form the primitive takes, and for one
// reason: the type of that form exposes no mutable access, so a key held in it could not be
// wiped when it is dropped. Between a key that lives on in freed memory and one copy on a
// frame per decapsulation, the wipe is the one that must hold. The copy is named in the
// security card of this primitive, and it closes upstream — with a borrowing entry point or a
// mutable accessor — rather than here.
pub struct SecretKey(Box<[u8; size::KEM_SECRET_KEY]>);

// A public value: what it holds is meant to be shown, so it derives what a test needs.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct Ciphertext([u8; CIPHERTEXT_BYTES]);

// The shared secret wipes itself: it is the key every later tag of a correspondence stands on.
pub struct SharedSecret([u8; SHARED_SECRET_BYTES]);

impl PublicKey {
    pub fn as_bytes(&self) -> &[u8; size::KEM_PUBLIC_KEY] {
        &self.0
    }

    pub fn from_bytes(bytes: [u8; size::KEM_PUBLIC_KEY]) -> Self {
        Self(bytes)
    }
}

impl Ciphertext {
    pub fn as_bytes(&self) -> &[u8; CIPHERTEXT_BYTES] {
        &self.0
    }

    pub fn from_bytes(bytes: [u8; CIPHERTEXT_BYTES]) -> Self {
        Self(bytes)
    }
}

impl SharedSecret {
    pub fn as_bytes(&self) -> &[u8; SHARED_SECRET_BYTES] {
        &self.0
    }
}

impl core::fmt::Debug for SecretKey {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        f.write_str("SecretKey(<wiped on drop, never shown>)")
    }
}

impl core::fmt::Debug for SharedSecret {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        f.write_str("SharedSecret(<wiped on drop, never shown>)")
    }
}

impl Drop for SecretKey {
    fn drop(&mut self) {
        self.0.zeroize();
    }
}

impl SecretKey {
    // The one door of the type: the bytes are moved in and the caller's copy is wiped.
    fn of(bytes: &mut [u8; size::KEM_SECRET_KEY]) -> Self {
        let held = Self(Box::new(*bytes));
        bytes.zeroize();
        held
    }
}

impl Drop for SharedSecret {
    fn drop(&mut self) {
        self.0.zeroize();
    }
}

pub fn keypair_from_seed(seed: &[u8; SEED_BYTES]) -> (PublicKey, SecretKey) {
    let pair = mlkem768::generate_key_pair(*seed);
    let public = PublicKey(*pair.public_key().as_slice());
    let mut bytes = *pair.private_key().as_slice();
    let secret = SecretKey::of(&mut bytes);
    (public, secret)
}

// The randomness of an encapsulation is drawn here and by nobody else. A door that asked its
// caller for it would be inviting the one mistake this primitive cannot survive: two letters to
// one key under one randomness land on one secret, and a caller with a counter or a constant
// makes that happen without ever seeing it.
pub fn encapsulate(public: &PublicKey) -> Result<(Ciphertext, SharedSecret), Undrawn> {
    let mut randomness = [0u8; SHARED_SECRET_BYTES];
    getrandom::getrandom(&mut randomness).map_err(|_| Undrawn)?;
    let held = encapsulate_with_randomness(public, randomness);
    randomness.zeroize();
    Ok(held)
}

// The same, with the randomness stated. It exists for the published vectors of the standard,
// which fix one, and a caller of the protocol that reached for it would be choosing a value the
// standard requires to be drawn.
pub fn encapsulate_with_randomness(
    public: &PublicKey,
    randomness: [u8; SHARED_SECRET_BYTES],
) -> (Ciphertext, SharedSecret) {
    let key = libcrux_ml_kem::MlKemPublicKey::from(public.0);
    let (ciphertext, shared) = mlkem768::encapsulate(&key, randomness);
    (Ciphertext(*ciphertext.as_slice()), SharedSecret(shared))
}

pub fn decapsulate(secret: &SecretKey, ciphertext: &Ciphertext) -> SharedSecret {
    let key = MlKemPrivateKey::from(*secret.0);
    let ct = libcrux_ml_kem::MlKemCiphertext::from(ciphertext.0);
    SharedSecret(mlkem768::decapsulate(&key, &ct))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::vectors;

    #[test]
    fn the_published_key_generation_vectors_reproduce() {
        // NIST ACVP-Server, ML-KEM-keyGen-FIPS203: the seed is `d || z`, and both halves of
        // the pair stand byte for byte.
        let cases = vectors::mlkem768_keygen();
        assert!(cases.len() >= 3, "the fixture holds {} cases", cases.len());
        for case in &cases {
            let mut seed = [0u8; SEED_BYTES];
            seed[..32].copy_from_slice(&case.d);
            seed[32..].copy_from_slice(&case.z);
            let (public, secret) = keypair_from_seed(&seed);
            assert_eq!(public.as_bytes()[..], case.ek[..], "tcId {}", case.id);
            assert_eq!(secret.0[..], case.dk[..], "tcId {}", case.id);
        }
    }

    #[test]
    fn the_published_encapsulation_vectors_reproduce() {
        // NIST ACVP-Server, ML-KEM-encapDecap-FIPS203, encapsulation: the message is the
        // randomness, and both the ciphertext and the shared secret stand.
        let cases = vectors::mlkem768_encaps();
        assert!(cases.len() >= 3, "the fixture holds {} cases", cases.len());
        for case in &cases {
            let public = PublicKey(case.ek[..].try_into().expect("a key of its size"));
            let randomness: [u8; SHARED_SECRET_BYTES] =
                case.m[..].try_into().expect("a message of 32 bytes");
            let (ciphertext, shared) = encapsulate_with_randomness(&public, randomness);
            assert_eq!(ciphertext.as_bytes()[..], case.c[..], "tcId {}", case.id);
            assert_eq!(shared.as_bytes()[..], case.k[..], "tcId {}", case.id);
        }
    }

    #[test]
    fn the_published_decapsulation_vectors_reproduce() {
        // NIST ACVP-Server, ML-KEM-encapDecap-FIPS203, decapsulation.
        let cases = vectors::mlkem768_decaps();
        assert!(cases.len() >= 3, "the fixture holds {} cases", cases.len());
        for case in &cases {
            let mut bytes: [u8; size::KEM_SECRET_KEY] =
                case.dk[..].try_into().expect("a key of its size");
            let secret = SecretKey::of(&mut bytes);
            let ciphertext = Ciphertext(case.c[..].try_into().expect("a ciphertext of its size"));
            let shared = decapsulate(&secret, &ciphertext);
            assert_eq!(shared.as_bytes()[..], case.k[..], "tcId {}", case.id);
        }
    }

    #[test]
    fn two_encapsulations_to_one_key_do_not_land_on_one_secret() {
        let (public, secret) = keypair_from_seed(&[0x77u8; SEED_BYTES]);
        let (first, a) = encapsulate(&public).expect("this machine draws");
        let (second, b) = encapsulate(&public).expect("this machine draws");
        assert_ne!(first.as_bytes(), second.as_bytes());
        assert_ne!(a.as_bytes(), b.as_bytes());
        assert_eq!(decapsulate(&secret, &first).as_bytes(), a.as_bytes());
        assert_eq!(decapsulate(&secret, &second).as_bytes(), b.as_bytes());
    }

    #[test]
    fn what_one_side_encapsulates_the_other_decapsulates() {
        let seed = [0x11u8; SEED_BYTES];
        let (public, secret) = keypair_from_seed(&seed);
        let (ciphertext, theirs) =
            encapsulate_with_randomness(&public, [0x22u8; SHARED_SECRET_BYTES]);
        let ours = decapsulate(&secret, &ciphertext);
        assert_eq!(ours.as_bytes(), theirs.as_bytes());
        // A ciphertext of another randomness lands on another secret; a doctored one lands on
        // the implicit rejection value, which is neither and reveals nothing about which.
        let (other, _) = encapsulate_with_randomness(&public, [0x23u8; SHARED_SECRET_BYTES]);
        assert_ne!(other.as_bytes(), ciphertext.as_bytes());
        let mut doctored = ciphertext.clone();
        doctored.0[0] ^= 1;
        assert_ne!(decapsulate(&secret, &doctored).as_bytes(), ours.as_bytes());
    }

    #[test]
    fn a_key_is_a_function_of_its_branch_and_the_sizes_are_the_set_s() {
        let a = keypair_from_seed(&[0x33u8; SEED_BYTES]);
        let b = keypair_from_seed(&[0x33u8; SEED_BYTES]);
        assert_eq!(a.0, b.0);
        assert_ne!(a.0, keypair_from_seed(&[0x34u8; SEED_BYTES]).0);
        assert_eq!(a.0.as_bytes().len(), size::KEM_PUBLIC_KEY);
        assert_eq!(a.1 .0.len(), size::KEM_SECRET_KEY);
    }

    #[test]
    fn a_secret_and_a_shared_secret_show_nothing_of_themselves() {
        let (public, secret) = keypair_from_seed(&[0x55u8; SEED_BYTES]);
        let (_, shared) = encapsulate(&public).expect("this machine draws");
        for shown in [format!("{secret:?}"), format!("{shared:?}")] {
            assert!(shown.contains("never shown"), "{shown}");
        }
    }
}
