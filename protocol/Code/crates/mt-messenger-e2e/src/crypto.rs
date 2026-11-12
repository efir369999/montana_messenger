//! Engine crypto backend with cfg branching (SSOT: one engine for both targets).
//! native → mt-crypto (OpenSSL FIPS); wasm → pure-Rust ml-dsa/ml-kem.
//! API is byte-oriented; secret keys are raw bytes (ML-KEM sk 2400, ML-DSA seed 32).
//! Byte-identity of backends is locked by cross-backend KAT (Stage 1).

pub const MLKEM_PUB: usize = 1184;
pub const MLKEM_SK: usize = 2400;
pub const MLKEM_CT: usize = 1088;
pub const MLDSA_PUB: usize = 1952;
pub const MLDSA_SIG: usize = 3309;

#[cfg(not(target_arch = "wasm32"))]
mod backend {
    use super::*;
    use mt_crypto::{
        keypair_from_seed, keypair_from_seed_mlkem, mlkem_decapsulate, mlkem_encapsulate,
        sign as mldsa_sign, verify as mldsa_verify, MlkemCiphertext, MlkemPublicKey,
        MlkemSecretKey, PublicKey, SecretKey, Signature,
    };

    pub fn kem_keypair_from_seed(seed: &[u8; 64]) -> Option<([u8; MLKEM_PUB], Vec<u8>)> {
        let (pk, sk) = keypair_from_seed_mlkem(seed).ok()?;
        Some((pk.as_bytes().to_owned(), sk.as_bytes().to_vec()))
    }
    pub fn kem_encapsulate(pk: &[u8]) -> Option<([u8; MLKEM_CT], [u8; 32])> {
        let pk = MlkemPublicKey::from_slice(pk)?;
        let (ct, ss) = mlkem_encapsulate(&pk).ok()?;
        let mut s = [0u8; 32];
        s.copy_from_slice(ss.as_bytes());
        Some((ct.as_bytes().to_owned(), s))
    }
    pub fn kem_decapsulate(sk: &[u8], ct: &[u8]) -> Option<[u8; 32]> {
        let sk = MlkemSecretKey::from_slice(sk)?;
        let ct = MlkemCiphertext::from_slice(ct)?;
        let ss = mlkem_decapsulate(&sk, &ct).ok()?;
        let mut s = [0u8; 32];
        s.copy_from_slice(ss.as_bytes());
        Some(s)
    }
    pub fn dsa_sign(account_seed: &[u8; 32], msg: &[u8]) -> Option<Vec<u8>> {
        let (_pk, sk) = keypair_from_seed(account_seed).ok()?;
        Some(mldsa_sign(&sk, msg).ok()?.as_bytes().to_vec())
    }
    pub fn dsa_verify(pk: &[u8], msg: &[u8], sig: &[u8]) -> bool {
        let (pk, sig) = match (PublicKey::from_slice(pk), Signature::from_slice(sig)) {
            (Some(p), Some(s)) => (p, s),
            _ => return false,
        };
        mldsa_verify(&pk, msg, &sig)
    }
    pub fn dsa_pub_from_seed(account_seed: &[u8; 32]) -> Option<[u8; MLDSA_PUB]> {
        let (pk, _sk) = keypair_from_seed(account_seed).ok()?;
        Some(pk.as_bytes().to_owned())
    }
    #[allow(dead_code)]
    fn _unused(_: SecretKey) {}
}

#[cfg(target_arch = "wasm32")]
mod backend {
    use super::*;
    use ml_dsa::{
        signature::{Signer, Verifier},
        EncodedVerifyingKey, Keypair, MlDsa65, Signature as DsaSig, SigningKey, VerifyingKey, B32,
    };
    use ml_kem::{
        kem::{Decapsulate, Encapsulate},
        Ciphertext, Encoded, EncodedSizeUser, KemCore, MlKem768, B32 as KemB32,
    };
    use rand_core::OsRng;

    type EkOf = <MlKem768 as KemCore>::EncapsulationKey;
    type DkOf = <MlKem768 as KemCore>::DecapsulationKey;

    pub fn kem_keypair_from_seed(seed: &[u8; 64]) -> Option<([u8; MLKEM_PUB], Vec<u8>)> {
        let d = KemB32::try_from(&seed[..32]).ok()?;
        let z = KemB32::try_from(&seed[32..]).ok()?;
        let (dk, ek) = MlKem768::generate_deterministic(&d, &z);
        Some((
            ek.as_bytes().as_slice().try_into().ok()?,
            dk.as_bytes().to_vec(),
        ))
    }
    pub fn kem_encapsulate(pk: &[u8]) -> Option<([u8; MLKEM_CT], [u8; 32])> {
        let enc = Encoded::<EkOf>::try_from(pk).ok()?;
        let ek = EkOf::from_bytes(&enc);
        let (ct, ss) = ek.encapsulate(&mut OsRng).ok()?;
        let mut s = [0u8; 32];
        s.copy_from_slice(ss.as_slice());
        Some((ct.as_slice().try_into().ok()?, s))
    }
    pub fn kem_decapsulate(sk: &[u8], ct: &[u8]) -> Option<[u8; 32]> {
        let enc = Encoded::<DkOf>::try_from(sk).ok()?;
        let dk = DkOf::from_bytes(&enc);
        let ctv = Ciphertext::<MlKem768>::try_from(ct).ok()?;
        let ss = dk.decapsulate(&ctv).ok()?;
        let mut s = [0u8; 32];
        s.copy_from_slice(ss.as_slice());
        Some(s)
    }
    pub fn dsa_sign(account_seed: &[u8; 32], msg: &[u8]) -> Option<Vec<u8>> {
        let seed = B32::try_from(&account_seed[..]).ok()?;
        let sk = SigningKey::<MlDsa65>::from_seed(&seed);
        let sig: DsaSig<MlDsa65> = sk.sign(msg);
        Some(sig.encode().as_slice().to_vec())
    }
    pub fn dsa_verify(pk: &[u8], msg: &[u8], sig: &[u8]) -> bool {
        let enc = match EncodedVerifyingKey::<MlDsa65>::try_from(pk) {
            Ok(e) => e,
            Err(_) => return false,
        };
        let vk = VerifyingKey::<MlDsa65>::decode(&enc);
        let s = match DsaSig::<MlDsa65>::try_from(sig) {
            Ok(s) => s,
            Err(_) => return false,
        };
        vk.verify(msg, &s).is_ok()
    }
    pub fn dsa_pub_from_seed(account_seed: &[u8; 32]) -> Option<[u8; MLDSA_PUB]> {
        let seed = B32::try_from(&account_seed[..]).ok()?;
        let sk = SigningKey::<MlDsa65>::from_seed(&seed);
        sk.verifying_key().encode().as_slice().try_into().ok()
    }
}

pub use backend::*;
