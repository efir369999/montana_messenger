//! Stage 6 — double ratchet state machine (KEM ratchet on ML-KEM-768).
//! Crypto — via crate::crypto (cfg branch). Reception — on trial-decrypt logic:
//! state changes only on AEAD success.

use crate::crypto::{kem_decapsulate, kem_encapsulate, kem_keypair_from_seed};
use crate::ratchet::{ad_bytes, kdf_ck, kdf_rk, msg_key, open, seal, MLKEM_PUBKEY_SIZE};
use zeroize::Zeroize;

pub const MLKEM_CT_SIZE: usize = 1088;
pub const MLKEM_SK_SIZE: usize = 2400;
pub const MAX_SKIP: u32 = 1000;
pub const MAX_MKSKIPPED: usize = 2000;
pub const MAX_PLAINTEXT: usize = 1_048_576;

/// DEV-049(c) §490: padding-to-bucket inside AEAD — hides the exact message length.
/// Marker 0x80 (ISO/IEC 7816-4) + zeros up to pad_len; cap at MAX_PLAINTEXT.
fn pad_message(pt: &[u8]) -> Vec<u8> {
    let target = crate::media::pad_len(pt.len() + 1)
        .min(MAX_PLAINTEXT)
        .max(pt.len() + 1);
    let mut out = Vec::with_capacity(target);
    out.extend_from_slice(pt);
    out.push(0x80);
    out.resize(target, 0x00);
    out
}

fn unpad_message(mut padded: Vec<u8>) -> Result<Vec<u8>, RatchetError> {
    while let Some(&last) = padded.last() {
        padded.pop();
        if last == 0x80 {
            return Ok(padded);
        }
        if last != 0x00 {
            return Err(RatchetError::BadFormat);
        }
    }
    Err(RatchetError::BadFormat)
}

#[derive(Debug, PartialEq, Eq)]
pub enum RatchetError {
    BadFormat,
    TooManySkipped,
    TooLarge,
    Decrypt,
    Replay,
    Crypto,
}

pub struct SessionState {
    session_id: [u8; 32],
    rk: [u8; 32],
    dhs_pub: [u8; MLKEM_PUBKEY_SIZE],
    dhs_sk: Vec<u8>,
    dhr: Option<[u8; MLKEM_PUBKEY_SIZE]>,
    cks: Option<[u8; 32]>,
    send_ct: Option<[u8; MLKEM_CT_SIZE]>,
    ckr: Option<[u8; 32]>,
    ns: u32,
    nr: u32,
    pn: u32,
    ratchet_pending: bool,
    mkskipped: Vec<(Vec<u8>, u32, [u8; 32])>,
}

fn put_opt_pub(o: &mut Vec<u8>, v: &Option<[u8; MLKEM_PUBKEY_SIZE]>) {
    match v {
        Some(x) => {
            o.push(1);
            o.extend_from_slice(x);
        },
        None => o.push(0),
    }
}
fn put_opt_ct(o: &mut Vec<u8>, v: &Option<[u8; MLKEM_CT_SIZE]>) {
    match v {
        Some(x) => {
            o.push(1);
            o.extend_from_slice(x);
        },
        None => o.push(0),
    }
}
fn put_opt32(o: &mut Vec<u8>, v: &Option<[u8; 32]>) {
    match v {
        Some(x) => {
            o.push(1);
            o.extend_from_slice(x);
        },
        None => o.push(0),
    }
}
fn get_opt_pub(b: &[u8], p: &mut usize) -> Result<Option<[u8; MLKEM_PUBKEY_SIZE]>, RatchetError> {
    if b.len() < *p + 1 {
        return Err(RatchetError::BadFormat);
    }
    let f = b[*p];
    *p += 1;
    match f {
        0 => Ok(None),
        1 => {
            if b.len() < *p + MLKEM_PUBKEY_SIZE {
                return Err(RatchetError::BadFormat);
            }
            let a: [u8; MLKEM_PUBKEY_SIZE] = b[*p..*p + MLKEM_PUBKEY_SIZE].try_into().unwrap();
            *p += MLKEM_PUBKEY_SIZE;
            Ok(Some(a))
        },
        _ => Err(RatchetError::BadFormat),
    }
}
fn get_opt_ct(b: &[u8], p: &mut usize) -> Result<Option<[u8; MLKEM_CT_SIZE]>, RatchetError> {
    if b.len() < *p + 1 {
        return Err(RatchetError::BadFormat);
    }
    let f = b[*p];
    *p += 1;
    match f {
        0 => Ok(None),
        1 => {
            if b.len() < *p + MLKEM_CT_SIZE {
                return Err(RatchetError::BadFormat);
            }
            let a: [u8; MLKEM_CT_SIZE] = b[*p..*p + MLKEM_CT_SIZE].try_into().unwrap();
            *p += MLKEM_CT_SIZE;
            Ok(Some(a))
        },
        _ => Err(RatchetError::BadFormat),
    }
}
fn get_opt32(b: &[u8], p: &mut usize) -> Result<Option<[u8; 32]>, RatchetError> {
    if b.len() < *p + 1 {
        return Err(RatchetError::BadFormat);
    }
    let f = b[*p];
    *p += 1;
    match f {
        0 => Ok(None),
        1 => {
            if b.len() < *p + 32 {
                return Err(RatchetError::BadFormat);
            }
            let a: [u8; 32] = b[*p..*p + 32].try_into().unwrap();
            *p += 32;
            Ok(Some(a))
        },
        _ => Err(RatchetError::BadFormat),
    }
}

impl Drop for SessionState {
    fn drop(&mut self) {
        self.rk.zeroize();
        self.dhs_sk.zeroize();
        if let Some(k) = self.cks.as_mut() {
            k.zeroize();
        }
        if let Some(k) = self.ckr.as_mut() {
            k.zeroize();
        }
        for (_, _, mk) in self.mkskipped.iter_mut() {
            mk.zeroize();
        }
    }
}

impl SessionState {
    #[allow(clippy::too_many_arguments)]
    pub fn init_initiator(
        session_id: [u8; 32],
        initial_root_key: [u8; 32],
        initial_sending_chain_key: [u8; 32],
        eph_kem_pub_a: [u8; MLKEM_PUBKEY_SIZE],
        eph_kem_sk_a: Vec<u8>,
        signed_prekey_pub_b: [u8; MLKEM_PUBKEY_SIZE],
    ) -> Self {
        Self {
            session_id,
            rk: initial_root_key,
            dhs_pub: eph_kem_pub_a,
            dhs_sk: eph_kem_sk_a,
            dhr: Some(signed_prekey_pub_b),
            cks: Some(initial_sending_chain_key),
            send_ct: None,
            ckr: None,
            ns: 0,
            nr: 0,
            pn: 0,
            ratchet_pending: false,
            mkskipped: Vec::new(),
        }
    }

    #[allow(clippy::too_many_arguments)]
    pub fn init_responder(
        session_id: [u8; 32],
        initial_root_key: [u8; 32],
        initial_sending_chain_key: [u8; 32],
        eph_kem_pub_a: [u8; MLKEM_PUBKEY_SIZE],
        signed_prekey_pub_b: [u8; MLKEM_PUBKEY_SIZE],
        signed_prekey_sk_b: Vec<u8>,
    ) -> Self {
        Self {
            session_id,
            rk: initial_root_key,
            dhs_pub: signed_prekey_pub_b,
            dhs_sk: signed_prekey_sk_b,
            dhr: Some(eph_kem_pub_a),
            cks: None,
            send_ct: None,
            ckr: Some(initial_sending_chain_key),
            ns: 0,
            nr: 0,
            pn: 0,
            ratchet_pending: true,
            mkskipped: Vec::new(),
        }
    }

    pub fn to_bytes(&self) -> Vec<u8> {
        let mut o = Vec::new();
        o.extend_from_slice(&self.session_id);
        o.extend_from_slice(&self.rk);
        o.extend_from_slice(&self.dhs_pub);
        o.extend_from_slice(&(self.dhs_sk.len() as u32).to_le_bytes());
        o.extend_from_slice(&self.dhs_sk);
        put_opt_pub(&mut o, &self.dhr);
        put_opt32(&mut o, &self.cks);
        put_opt_ct(&mut o, &self.send_ct);
        put_opt32(&mut o, &self.ckr);
        o.extend_from_slice(&self.ns.to_le_bytes());
        o.extend_from_slice(&self.nr.to_le_bytes());
        o.extend_from_slice(&self.pn.to_le_bytes());
        o.push(self.ratchet_pending as u8);
        o.extend_from_slice(&(self.mkskipped.len() as u32).to_le_bytes());
        for (rp, n, mk) in &self.mkskipped {
            o.extend_from_slice(rp);
            o.extend_from_slice(&n.to_le_bytes());
            o.extend_from_slice(mk);
        }
        o
    }

    pub fn from_bytes(b: &[u8]) -> Result<Self, RatchetError> {
        let mut p = 0usize;
        let take = |p: &mut usize, n: usize| -> Result<&[u8], RatchetError> {
            if b.len() < *p + n {
                return Err(RatchetError::BadFormat);
            }
            let s = &b[*p..*p + n];
            *p += n;
            Ok(s)
        };
        let session_id: [u8; 32] = take(&mut p, 32)?.try_into().unwrap();
        let rk: [u8; 32] = take(&mut p, 32)?.try_into().unwrap();
        let dhs_pub: [u8; MLKEM_PUBKEY_SIZE] = take(&mut p, MLKEM_PUBKEY_SIZE)?.try_into().unwrap();
        let sk_len = u32::from_le_bytes(take(&mut p, 4)?.try_into().unwrap()) as usize;
        if sk_len != MLKEM_SK_SIZE {
            return Err(RatchetError::BadFormat);
        }
        let dhs_sk = take(&mut p, sk_len)?.to_vec();
        let dhr = get_opt_pub(b, &mut p)?;
        let cks = get_opt32(b, &mut p)?;
        let send_ct = get_opt_ct(b, &mut p)?;
        let ckr = get_opt32(b, &mut p)?;
        let ns = u32::from_le_bytes(take(&mut p, 4)?.try_into().unwrap());
        let nr = u32::from_le_bytes(take(&mut p, 4)?.try_into().unwrap());
        let pn = u32::from_le_bytes(take(&mut p, 4)?.try_into().unwrap());
        let ratchet_pending = take(&mut p, 1)?[0] != 0;
        let count = u32::from_le_bytes(take(&mut p, 4)?.try_into().unwrap()) as usize;
        let mut mkskipped = Vec::with_capacity(count);
        for _ in 0..count {
            let rp = take(&mut p, MLKEM_PUBKEY_SIZE)?.to_vec();
            let n = u32::from_le_bytes(take(&mut p, 4)?.try_into().unwrap());
            let mk: [u8; 32] = take(&mut p, 32)?.try_into().unwrap();
            mkskipped.push((rp, n, mk));
        }
        Ok(Self {
            session_id,
            rk,
            dhs_pub,
            dhs_sk,
            dhr,
            cks,
            send_ct,
            ckr,
            ns,
            nr,
            pn,
            ratchet_pending,
            mkskipped,
        })
    }

    pub fn encrypt(
        &mut self,
        plaintext: &[u8],
        rng_seed: &[u8; 64],
    ) -> Result<Vec<u8>, RatchetError> {
        if plaintext.len() > MAX_PLAINTEXT {
            return Err(RatchetError::TooLarge);
        }
        if self.ratchet_pending {
            self.pn = self.ns;
            self.ns = 0;
            let (new_pub, new_sk) = kem_keypair_from_seed(rng_seed).ok_or(RatchetError::Crypto)?;
            let dhr = self.dhr.ok_or(RatchetError::BadFormat)?;
            let (ct, ss) = kem_encapsulate(&dhr).ok_or(RatchetError::Crypto)?;
            let (new_rk, new_cks) = kdf_rk(&self.rk, &ss);
            self.rk = new_rk;
            self.cks = Some(new_cks);
            self.dhs_pub = new_pub;
            self.dhs_sk = new_sk;
            self.send_ct = Some(ct);
            self.ratchet_pending = false;
        }
        let cks = self.cks.ok_or(RatchetError::BadFormat)?;
        let (mut mk, next_cks) = kdf_ck(&cks);
        self.cks = Some(next_cks);
        let (mut enc_key, nonce) = msg_key(&mk);
        let ad = ad_bytes(&self.session_id, self.pn, self.ns, &self.dhs_pub);
        let padded = pad_message(plaintext);
        let body = seal(&enc_key, &nonce, &padded, &ad);
        mk.zeroize();
        enc_key.zeroize();

        let has_ct = self.send_ct.is_some();
        let mut out = Vec::new();
        out.extend_from_slice(&self.dhs_pub);
        out.push(if has_ct { 0x01 } else { 0x00 });
        if let Some(ct) = &self.send_ct {
            out.extend_from_slice(ct);
        }
        out.extend_from_slice(&self.pn.to_le_bytes());
        out.extend_from_slice(&self.ns.to_le_bytes());
        out.extend_from_slice(&(body.len() as u32).to_le_bytes());
        out.extend_from_slice(&body);
        self.ns += 1;
        Ok(out)
    }

    pub fn decrypt(&mut self, msg: &[u8]) -> Result<Vec<u8>, RatchetError> {
        let mut p = 0;
        if msg.len() < MLKEM_PUBKEY_SIZE + 1 {
            return Err(RatchetError::BadFormat);
        }
        let ratchet_pub = &msg[p..p + MLKEM_PUBKEY_SIZE];
        p += MLKEM_PUBKEY_SIZE;
        let has_ct = match msg[p] {
            0x00 => false,
            0x01 => true,
            _ => return Err(RatchetError::BadFormat),
        };
        p += 1;
        let ct = if has_ct {
            if msg.len() < p + MLKEM_CT_SIZE {
                return Err(RatchetError::BadFormat);
            }
            let c = &msg[p..p + MLKEM_CT_SIZE];
            p += MLKEM_CT_SIZE;
            Some(c)
        } else {
            None
        };
        if msg.len() < p + 12 {
            return Err(RatchetError::BadFormat);
        }
        let m_pn = u32::from_le_bytes(msg[p..p + 4].try_into().unwrap());
        p += 4;
        let m_ns = u32::from_le_bytes(msg[p..p + 4].try_into().unwrap());
        p += 4;
        let body_len = u32::from_le_bytes(msg[p..p + 4].try_into().unwrap()) as usize;
        p += 4;
        if body_len > MAX_PLAINTEXT + 16 || msg.len() != p + body_len {
            return Err(RatchetError::BadFormat);
        }
        let body = &msg[p..p + body_len];
        let ad = {
            let mut rp = [0u8; MLKEM_PUBKEY_SIZE];
            rp.copy_from_slice(ratchet_pub);
            ad_bytes(&self.session_id, m_pn, m_ns, &rp)
        };

        if let Some(idx) = self
            .mkskipped
            .iter()
            .position(|(rp, n, _)| rp.as_slice() == ratchet_pub && *n == m_ns)
        {
            let mut mk = self.mkskipped[idx].2;
            let (mut enc_key, nonce) = msg_key(&mk);
            let pt = open(&enc_key, &nonce, body, &ad);
            mk.zeroize();
            enc_key.zeroize();
            let pt = pt.ok_or(RatchetError::Decrypt)?;
            let (_, _, mut used) = self.mkskipped.remove(idx);
            used.zeroize();
            return unpad_message(pt);
        }

        let is_kem_step = match &self.dhr {
            Some(d) => &d[..] != ratchet_pub,
            None => true,
        };
        // spec, Stage 6 "exactly-once rule": number in the current chain below the receive
        // cursor and the key already consumed/evicted -> replay, session is preserved.
        if !is_kem_step && m_ns < self.nr {
            return Err(RatchetError::Replay);
        }
        let mut rk = self.rk;
        let mut ckr = self.ckr;
        let mut nr = self.nr;
        let mut dhr = self.dhr;
        let mut pending = self.ratchet_pending;
        let mut new_skipped: Vec<(Vec<u8>, u32, [u8; 32])> = Vec::new();

        if is_kem_step {
            if !has_ct {
                return Err(RatchetError::BadFormat);
            }
            if let (Some(dr), Some(mut c)) = (dhr, ckr) {
                if m_pn.saturating_sub(nr) > MAX_SKIP {
                    return Err(RatchetError::TooManySkipped);
                }
                while nr < m_pn {
                    let (mk, nc) = kdf_ck(&c);
                    new_skipped.push((dr.to_vec(), nr, mk));
                    c = nc;
                    nr += 1;
                }
            }
            let ss = kem_decapsulate(&self.dhs_sk, ct.unwrap()).ok_or(RatchetError::Crypto)?;
            let (new_rk, new_ckr) = kdf_rk(&rk, &ss);
            rk = new_rk;
            ckr = Some(new_ckr);
            let mut ndr = [0u8; MLKEM_PUBKEY_SIZE];
            ndr.copy_from_slice(ratchet_pub);
            dhr = Some(ndr);
            nr = 0;
            pending = true;
        }

        let mut c = ckr.ok_or(RatchetError::BadFormat)?;
        if m_ns.saturating_sub(nr) > MAX_SKIP {
            return Err(RatchetError::TooManySkipped);
        }
        let dr = dhr.ok_or(RatchetError::BadFormat)?;
        while nr < m_ns {
            let (mk, nc) = kdf_ck(&c);
            new_skipped.push((dr.to_vec(), nr, mk));
            c = nc;
            nr += 1;
        }
        let (mut mk, next_c) = kdf_ck(&c);
        let (mut enc_key, nonce) = msg_key(&mk);
        let pt = open(&enc_key, &nonce, body, &ad);
        mk.zeroize();
        enc_key.zeroize();
        let pt = pt.ok_or(RatchetError::Decrypt)?;

        self.rk = rk;
        self.ckr = Some(next_c);
        self.dhr = dhr;
        self.nr = nr + 1;
        self.ratchet_pending = pending;
        for s in new_skipped {
            self.mkskipped.push(s);
        }
        while self.mkskipped.len() > MAX_MKSKIPPED {
            self.mkskipped.remove(0);
        }
        unpad_message(pt)
    }
}
