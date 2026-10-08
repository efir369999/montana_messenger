// ML-DSA-65 in its deterministic form. The set states it in `docs/Montana Canon.md`,
// "Primitives": the deterministic variant of FIPS 204 with RND = 0x00 x 32, so that under one
// (secret key, message) the signature is bit-exactly the same — which is what lets an
// identifier be taken over signed scope and stand still when an object is re-signed.
//
// A key of a person is generated from a branch of their seed and from nothing else, so the
// same words on another device answer with the same key.

use libcrux_ml_dsa::{ml_dsa_65, MLDSASigningKey};
use mt_codec::size;
use zeroize::{Zeroize, Zeroizing};

// The randomness of the deterministic variant: thirty-two zero bytes, the value FIPS 204 names
// for it. It is not a choice of ours and never varies.
const DETERMINISTIC_RND: [u8; 32] = [0u8; 32];

mt_codec::constants! {
    SIGNING_WIDTHS:
    /// The branch of a seed a signing key is generated from.
    pub const SEED_BYTES: usize = 32, writes "HKDF-Expand(master_seed, \"mt-account-key\",        32)";
}

#[derive(Debug, PartialEq, Eq)]
pub enum SignError {
    Signing,
}

#[derive(Debug, PartialEq, Eq)]
pub struct VerifyError;

// A public value: what it holds is meant to be shown, so it derives what a test needs.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct PublicKey([u8; size::SIGNING_PUBLIC_KEY]);

// The secret half wipes itself and never prints: what a Debug of it would show is the key. It
// holds the form the primitive signs from, so signing borrows it rather than copying four
// kilobytes of key onto the stack at every signature — a frame that is reused by the next call
// and wiped by nobody.
pub struct SecretKey(Box<MLDSASigningKey<{ size::SIGNING_SECRET_KEY }>>);

// A public value: what it holds is meant to be shown, so it derives what a test needs.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct Signature([u8; size::SIGNATURE]);

impl PublicKey {
    pub fn as_bytes(&self) -> &[u8; size::SIGNING_PUBLIC_KEY] {
        &self.0
    }

    pub fn from_bytes(bytes: [u8; size::SIGNING_PUBLIC_KEY]) -> Self {
        Self(bytes)
    }
}

impl core::fmt::Debug for SecretKey {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        f.write_str("SecretKey(<wiped on drop, never shown>)")
    }
}

impl Drop for SecretKey {
    fn drop(&mut self) {
        self.0.as_ref_mut().zeroize();
    }
}

impl SecretKey {
    // The one door of the type: the bytes are moved in and the caller's copy is wiped, so no
    // reachable path holds a second copy this type does not own.
    fn of(bytes: &mut [u8; size::SIGNING_SECRET_KEY]) -> Self {
        let held = Self(Box::new(MLDSASigningKey::new(*bytes)));
        bytes.zeroize();
        held
    }
}

impl Signature {
    pub fn as_bytes(&self) -> &[u8; size::SIGNATURE] {
        &self.0
    }

    pub fn from_bytes(bytes: [u8; size::SIGNATURE]) -> Self {
        Self(bytes)
    }
}

// The pair a branch of a seed generates: deterministic in the branch and in nothing else. The
// generation writes into buffers this function owns rather than answering a pair by value, so
// the only intermediate holding the key is the one wiped on the line after it.
pub fn keypair_from_seed(seed: &[u8; SEED_BYTES]) -> (PublicKey, SecretKey) {
    let mut signing = Zeroizing::new([0u8; size::SIGNING_SECRET_KEY]);
    let mut verification = [0u8; size::SIGNING_PUBLIC_KEY];
    ml_dsa_65::portable::generate_key_pair_mut(*seed, &mut signing, &mut verification);
    (PublicKey(verification), SecretKey::of(&mut signing))
}

// The context of FIPS 204 is empty for every signature of this protocol: what separates one
// class of object from another is the domain its identifier is taken under, and a second
// separator in the signature would be a second place that rule lives.
const EMPTY_CONTEXT: &[u8] = &[];

pub fn sign(secret: &SecretKey, message: &[u8]) -> Result<Signature, SignError> {
    sign_in_context(secret, message, EMPTY_CONTEXT)
}

// The standard admits a context of its own; the protocol fixes it empty, and this door exists
// so the published vectors — which exercise the primitive with and without one — are checked
// as the standard defines them rather than only in the shape we use.
fn sign_in_context(
    secret: &SecretKey,
    message: &[u8],
    context: &[u8],
) -> Result<Signature, SignError> {
    let signature = ml_dsa_65::sign(&secret.0, message, context, DETERMINISTIC_RND)
        .map_err(|_| SignError::Signing)?;
    Ok(Signature(*signature.as_ref()))
}

pub fn verify(
    public: &PublicKey,
    message: &[u8],
    signature: &Signature,
) -> Result<(), VerifyError> {
    verify_in_context(public, message, EMPTY_CONTEXT, signature)
}

fn verify_in_context(
    public: &PublicKey,
    message: &[u8],
    context: &[u8],
    signature: &Signature,
) -> Result<(), VerifyError> {
    let key = libcrux_ml_dsa::MLDSAVerificationKey::new(public.0);
    let sig = libcrux_ml_dsa::MLDSASignature::new(signature.0);
    ml_dsa_65::verify(&key, message, context, &sig).map_err(|_| VerifyError)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::vectors;

    #[test]
    fn the_published_key_generation_vectors_reproduce() {
        // NIST ACVP-Server, ML-DSA-keyGen-FIPS204: the seed, the verification key and the
        // signing key, byte for byte. The fixture travels with this tree and names its source.
        let cases = vectors::mldsa65_keygen();
        assert!(cases.len() >= 3, "the fixture holds {} cases", cases.len());
        for case in &cases {
            let seed: [u8; SEED_BYTES] = case.seed[..].try_into().expect("a seed of 32 bytes");
            let (public, secret) = keypair_from_seed(&seed);
            assert_eq!(public.as_bytes()[..], case.pk[..], "tcId {}", case.id);
            assert_eq!(
                secret.0.as_ref().as_ref()[..],
                case.sk[..],
                "tcId {}",
                case.id
            );
        }
    }

    #[test]
    fn the_published_signing_vectors_reproduce_under_the_deterministic_rule() {
        // NIST ACVP-Server, ML-DSA-sigGen-FIPS204, deterministic and external with an empty
        // context: exactly the form the set fixes.
        let cases = vectors::mldsa65_siggen();
        assert!(cases.len() >= 3, "the fixture holds {} cases", cases.len());
        // The shape the protocol itself signs in — an empty context — stands among the cases,
        // so the vectors exercise the door this code actually uses and not only its neighbours.
        assert!(
            cases.iter().any(|c| c.context.is_empty()),
            "no case of the fixture carries an empty context"
        );
        for case in &cases {
            let mut bytes: [u8; size::SIGNING_SECRET_KEY] =
                case.sk[..].try_into().expect("a signing key of its size");
            let key = SecretKey::of(&mut bytes);
            let signature =
                sign_in_context(&key, &case.message, &case.context).expect("the vector signs");
            assert_eq!(
                signature.as_bytes()[..],
                case.signature[..],
                "tcId {}",
                case.id
            );
            // The published verification key accepts it, which checks the other half of the
            // primitive against the same case.
            let public = PublicKey(case.pk[..].try_into().expect("a key of its size"));
            verify_in_context(&public, &case.message, &case.context, &signature)
                .expect("the published key verifies its own vector");
        }
    }

    #[test]
    fn one_key_and_one_message_yield_one_signature_and_it_verifies() {
        // The property the identifier of a signed object rests on: re-signing moves nothing.
        let seed = [0x11u8; SEED_BYTES];
        let (public, secret) = keypair_from_seed(&seed);
        let message = b"the bytes of an object without its signature";
        let first = sign(&secret, message).expect("signs");
        let second = sign(&secret, message).expect("signs");
        assert_eq!(first, second);
        verify(&public, message, &first).expect("verifies");
        // A message of one byte more, a doctored signature and a stranger's key each fail.
        let mut longer = message.to_vec();
        longer.push(0);
        assert_eq!(verify(&public, &longer, &first), Err(VerifyError));
        let mut doctored = first.clone();
        doctored.0[0] ^= 1;
        assert_eq!(verify(&public, message, &doctored), Err(VerifyError));
        let (stranger, _) = keypair_from_seed(&[0x22u8; SEED_BYTES]);
        assert_eq!(verify(&stranger, message, &first), Err(VerifyError));
    }

    #[test]
    fn a_key_is_a_function_of_its_branch_and_of_nothing_else() {
        let a = keypair_from_seed(&[0x33u8; SEED_BYTES]).0;
        let b = keypair_from_seed(&[0x33u8; SEED_BYTES]).0;
        let other = keypair_from_seed(&[0x34u8; SEED_BYTES]).0;
        assert_eq!(a, b);
        assert_ne!(a, other);
    }

    #[test]
    fn the_sizes_are_the_ones_the_set_states() {
        let (public, secret) = keypair_from_seed(&[0x44u8; SEED_BYTES]);
        assert_eq!(public.as_bytes().len(), size::SIGNING_PUBLIC_KEY);
        assert_eq!(secret.0.as_ref().as_slice().len(), size::SIGNING_SECRET_KEY);
        let signature = sign(&secret, b"message").expect("signs");
        assert_eq!(signature.as_bytes().len(), size::SIGNATURE);
    }

    #[test]
    fn a_secret_key_shows_nothing_of_itself() {
        let (_, secret) = keypair_from_seed(&[0x55u8; SEED_BYTES]);
        let shown = format!("{secret:?}");
        assert!(!shown.contains("55"), "{shown}");
        assert!(shown.contains("never shown"), "{shown}");
    }
}
