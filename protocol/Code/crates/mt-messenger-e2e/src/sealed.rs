//! Stage 7 — sealed envelope of first contact (sealed-sender).
//! Crypto — via crate::crypto (cfg fork).

use sha2::{Digest, Sha256};

use crate::crypto::{kem_decapsulate, kem_encapsulate, MLKEM_PUB};
use crate::kdf::hkdf_sha256;
use crate::ratchet::{open, seal};

pub const CT_SEAL_SIZE: usize = 1088;
pub const ITEM_ID_SIZE: usize = 16;
pub const COMMITMENT_SIZE: usize = 32;
pub const POT_PROOF_SIZE: usize = 32;
pub const INBOX_POT_STEPS: u32 = 1_048_576;

fn seal_key_nonce(ss_seal: &[u8; 32]) -> ([u8; 32], [u8; 12]) {
    let okm = hkdf_sha256(&[0u8; 32], ss_seal, b"mt-seal", 44);
    let mut k = [0u8; 32];
    let mut n = [0u8; 12];
    k.copy_from_slice(&okm[..32]);
    n.copy_from_slice(&okm[32..44]);
    (k, n)
}

pub fn compute_pot(
    inbox_label: &[u8; 16],
    item_id: &[u8; ITEM_ID_SIZE],
    delete_commitment: &[u8; COMMITMENT_SIZE],
    ct_seal: &[u8; CT_SEAL_SIZE],
    sealed: &[u8],
    steps: u32,
) -> [u8; 32] {
    let mut h = Sha256::new();
    h.update(b"mt-pot");
    h.update([0u8]);
    h.update(inbox_label);
    h.update(item_id);
    h.update(delete_commitment);
    h.update(ct_seal);
    h.update(sealed);
    let mut y: [u8; 32] = h.finalize().into();
    for _ in 0..steps {
        y = Sha256::digest(y).into();
    }
    y
}

pub fn verify_pot(
    inbox_label: &[u8; 16],
    item_id: &[u8; ITEM_ID_SIZE],
    delete_commitment: &[u8; COMMITMENT_SIZE],
    ct_seal: &[u8; CT_SEAL_SIZE],
    sealed: &[u8],
    steps: u32,
    proof: &[u8; POT_PROOF_SIZE],
) -> bool {
    &compute_pot(
        inbox_label,
        item_id,
        delete_commitment,
        ct_seal,
        sealed,
        steps,
    ) == proof
}

pub struct Envelope {
    pub bytes: Vec<u8>,
    pub delete_commitment: [u8; COMMITMENT_SIZE],
}

#[allow(clippy::too_many_arguments)]
#[allow(clippy::result_unit_err)]
pub fn seal_envelope(
    app_kem_pub_b: &[u8; MLKEM_PUB],
    account_id_b: &[u8; 32],
    inbox_label: &[u8; 16],
    inner: &[u8],
    item_id: &[u8; ITEM_ID_SIZE],
    delete_preimage: &[u8; 32],
    pot_steps: u32,
) -> Result<Envelope, ()> {
    let (ct_seal, ss_seal) = kem_encapsulate(app_kem_pub_b).ok_or(())?;
    let (seal_k, seal_n) = seal_key_nonce(&ss_seal);

    let mut plaintext = Vec::with_capacity(32 + inner.len());
    plaintext.extend_from_slice(delete_preimage);
    plaintext.extend_from_slice(inner);

    let mut ad = b"mt-seal".to_vec();
    ad.push(0u8);
    ad.extend_from_slice(account_id_b);
    let sealed = seal(&seal_k, &seal_n, &plaintext, &ad);

    let delete_commitment: [u8; 32] = Sha256::digest(delete_preimage).into();
    let pot = compute_pot(
        inbox_label,
        item_id,
        &delete_commitment,
        &ct_seal,
        &sealed,
        pot_steps,
    );

    let mut out = Vec::new();
    out.extend_from_slice(&ct_seal);
    out.extend_from_slice(item_id);
    out.extend_from_slice(&delete_commitment);
    out.extend_from_slice(&pot);
    out.extend_from_slice(&sealed);
    Ok(Envelope {
        bytes: out,
        delete_commitment,
    })
}

pub struct Opened {
    pub delete_preimage: [u8; 32],
    pub inner: Vec<u8>,
}

pub fn open_envelope(
    app_kem_sk_b: &[u8],
    account_id_b: &[u8; 32],
    envelope: &[u8],
) -> Option<Opened> {
    let min = CT_SEAL_SIZE + ITEM_ID_SIZE + COMMITMENT_SIZE + POT_PROOF_SIZE;
    if envelope.len() < min + 16 {
        return None;
    }
    let mut p = 0;
    let ct_seal = &envelope[p..p + CT_SEAL_SIZE];
    p += CT_SEAL_SIZE;
    p += ITEM_ID_SIZE;
    let delete_commitment = &envelope[p..p + COMMITMENT_SIZE];
    p += COMMITMENT_SIZE;
    p += POT_PROOF_SIZE;
    let sealed = &envelope[p..];

    let ss = kem_decapsulate(app_kem_sk_b, ct_seal)?;
    let (seal_k, seal_n) = seal_key_nonce(&ss);

    let mut ad = b"mt-seal".to_vec();
    ad.push(0u8);
    ad.extend_from_slice(account_id_b);
    let plaintext = open(&seal_k, &seal_n, sealed, &ad)?;
    if plaintext.len() < 32 {
        return None;
    }
    let mut dp = [0u8; 32];
    dp.copy_from_slice(&plaintext[..32]);
    if Sha256::digest(dp).as_slice() != delete_commitment {
        return None;
    }
    Some(Opened {
        delete_preimage: dp,
        inner: plaintext[32..].to_vec(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::crypto::kem_keypair_from_seed;
    use crate::labels::inbox_label;

    #[test]
    fn seal_and_pot_spec_kat() {
        // Binding production functions to spec hex (Stage 7, "Test vectors"), not re-deriving formulas
        let (k, n) = seal_key_nonce(&[0x44; 32]);
        assert_eq!(
            hex::encode(k),
            "5f9f4ccf25e7ba4921c0bc004406af5b743c49783a5989bf185c58844c8d6e5b"
        );
        assert_eq!(hex::encode(n), "02b49c7b9e94ca37b1aed2ac");
        let acc = hex::decode("9f199584ed120b987b617ba5bff829e176f23e5465dd70cfac5c141dfb131a21")
            .unwrap();
        let mut ad = b"mt-seal".to_vec();
        ad.push(0u8);
        ad.extend_from_slice(&acc);
        let body = seal(&k, &n, b"handshake", &ad);
        assert_eq!(
            hex::encode(&body),
            "488b64548e48d192e145fc04ae32ceb07c991c959a05c6b594"
        );
        let ib: [u8; 16] = hex::decode("7d5db70fa1b5f7e7902bba6bbbd626ba")
            .unwrap()
            .try_into()
            .unwrap();
        let pot = compute_pot(&ib, &[0x44; 16], &[0x55; 32], &[0x66; 1088], &[0x77; 64], 4);
        assert_eq!(
            hex::encode(pot),
            "ed47bd474d18e22ef2ff96811fa08c26193e9ac597515be2d96920f72de0a17f"
        );
    }

    #[test]
    fn envelope_roundtrip() {
        let (pk, sk) = kem_keypair_from_seed(&[0x11; 64]).unwrap();
        let account_id_b = [0x44u8; 32];
        let label = inbox_label(&account_id_b);
        let inner = b"pretend-InitialHandshake-bytes";
        let env = seal_envelope(
            &pk,
            &account_id_b,
            &label,
            inner,
            &[0x01; 16],
            &[0x02; 32],
            8,
        )
        .unwrap();
        let opened = open_envelope(&sk, &account_id_b, &env.bytes).unwrap();
        assert_eq!(&opened.inner, inner);
        assert_eq!(opened.delete_preimage, [0x02; 32]);
    }

    #[test]
    fn pot_binds_envelope() {
        let (pk, _sk) = kem_keypair_from_seed(&[0x11; 64]).unwrap();
        let account_id_b = [0x44u8; 32];
        let label = inbox_label(&account_id_b);
        let env = seal_envelope(
            &pk,
            &account_id_b,
            &label,
            b"x",
            &[0x01; 16],
            &[0x02; 32],
            8,
        )
        .unwrap();
        let ct_seal: [u8; CT_SEAL_SIZE] = env.bytes[..CT_SEAL_SIZE].try_into().unwrap();
        let item_id: [u8; 16] = env.bytes[CT_SEAL_SIZE..CT_SEAL_SIZE + 16]
            .try_into()
            .unwrap();
        let off = CT_SEAL_SIZE + 16;
        let commit: [u8; 32] = env.bytes[off..off + 32].try_into().unwrap();
        let pot: [u8; 32] = env.bytes[off + 32..off + 64].try_into().unwrap();
        let sealed = &env.bytes[off + 64..];
        assert!(verify_pot(
            &label, &item_id, &commit, &ct_seal, sealed, 8, &pot
        ));
        let mut bad = sealed.to_vec();
        bad[0] ^= 1;
        assert!(!verify_pot(
            &label, &item_id, &commit, &ct_seal, &bad, 8, &pot
        ));
    }

    #[test]
    fn wrong_key_fails_open() {
        let (pk, _sk) = kem_keypair_from_seed(&[0x11; 64]).unwrap();
        let (_pk2, sk2) = kem_keypair_from_seed(&[0x99; 64]).unwrap();
        let account_id_b = [0x44u8; 32];
        let label = inbox_label(&account_id_b);
        let env = seal_envelope(
            &pk,
            &account_id_b,
            &label,
            b"x",
            &[0x01; 16],
            &[0x02; 32],
            8,
        )
        .unwrap();
        assert!(open_envelope(&sk2, &account_id_b, &env.bytes).is_none());
    }
}
