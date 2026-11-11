//! Mainline BitTorrent DHT transport for rendezvous (Stage 4): BEP5+BEP44 put/get of a real record.
//! Wrapper over the `mainline` crate (BEP44 mutable). The byte-exact core (lib.rs) provides RendezvousRecord;
//! this module is the network put/get. Testnet is a local DHT for a running test without a real network.

use mainline::{Dht, MutableItem};

use crate::{dht_pubkey, dht_signing_key, RendezvousRecord, RvError, DHT_SEED_LEN};

pub struct RvDht {
    dht: Dht,
}

impl RvDht {
    /// Client on the real Mainline DHT (public BitTorrent bootstrap nodes).
    pub fn client() -> Result<Self, RvError> {
        let dht = Dht::client().map_err(|e| RvError::Dht(format!("client: {e}")))?;
        Ok(Self { dht })
    }

    /// Client on a local Testnet DHT (running test without a real network).
    pub fn from_dht(dht: Dht) -> Self {
        Self { dht }
    }

    /// Put a rendezvous record into the DHT under target=SHA1(dk‖salt). mainline signs BEP44 with
    /// our dht_key (ed25519). seq is monotonic (BEP44 anti-rollback).
    pub fn put(
        &self,
        dht_seed: &[u8; DHT_SEED_LEN],
        salt: &[u8; crate::SALT_LEN],
        seq: u64,
        record: &RendezvousRecord,
    ) -> Result<(), RvError> {
        record.validate(seq)?;
        let v = record.to_bytes();
        if v.len() > crate::MAX_RECORD_BYTES {
            return Err(RvError::TooLarge(v.len()));
        }
        let signer = dht_signing_key(dht_seed);
        let item = MutableItem::new(signer, &v, seq as i64, Some(salt));
        self.dht
            .put_mutable(item, None)
            .map_err(|e| RvError::Dht(format!("put: {e}")))?;
        Ok(())
    }

    /// Read a rendezvous record from the DHT by dk+salt. Takes the record with the highest seq
    /// (F-6: a stale/planted old version does not win: mainline
    /// get_mutable_most_recent) and drops one expired by valid_until relative to
    /// now_unix (F-5: freshness wall §593 R2: a dead leaf does not resolve). mainline
    /// has already verified the BEP44 signature against dk.
    pub fn get(
        &self,
        dk: &[u8; crate::DK_LEN],
        salt: &[u8; crate::SALT_LEN],
        now_unix: u64,
    ) -> Option<RendezvousRecord> {
        let item = self.dht.get_mutable_most_recent(dk, Some(salt))?;
        let r = RendezvousRecord::decode(item.value()).ok()?;
        if r.valid_until < now_unix {
            return None; // expired: refetch/other paths (R2)
        }
        Some(r)
    }
}

/// Pre-signed record (P2): the leaf signs offline with its dht_key, the postman
/// re-puts it WITHOUT the leaf secret (`put_presigned`). The dht_key secret never leaves the leaf.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct PresignedRecord {
    pub dk: [u8; crate::DK_LEN],
    pub salt: [u8; crate::SALT_LEN],
    pub seq: u64,
    pub value: Vec<u8>, // RendezvousRecord.to_bytes()
    pub sig: [u8; 64],
}

/// The leaf (holder of the dht_key secret) pre-signs a batch of records with increasing seq
/// and its own valid_until window; the postman re-announces without the secret (freshness wall P2).
pub fn prepare_batch(
    dht_seed: &[u8; DHT_SEED_LEN],
    salt: &[u8; crate::SALT_LEN],
    base_seq: u64,
    mut records: Vec<RendezvousRecord>,
) -> Result<Vec<PresignedRecord>, RvError> {
    let sk = dht_signing_key(dht_seed);
    let dk = dht_pubkey(&sk);
    let mut out = Vec::with_capacity(records.len());
    for (i, rec) in records.iter_mut().enumerate() {
        let seq = base_seq
            .checked_add(i as u64)
            .ok_or(RvError::SeqOutOfRange(base_seq))?;
        rec.seq = seq;
        rec.validate(seq)?;
        let v = rec.to_bytes(); // O-1: encode exactly once (signature + value)
        let sig = crate::sign_bep44(&sk, salt, seq, &v)?;
        out.push(PresignedRecord {
            dk,
            salt: *salt,
            seq,
            value: v,
            sig: sig.to_bytes(),
        });
    }
    Ok(out)
}

impl RvDht {
    /// The postman re-puts the leaf's pre-signed record WITHOUT its secret
    /// (mainline new_signed_unchecked with a ready ed25519 signature; DHT nodes verify it).
    pub fn put_presigned(&self, pre: &PresignedRecord) -> Result<(), RvError> {
        let item = MutableItem::new_signed_unchecked(
            pre.dk,
            pre.sig,
            &pre.value,
            pre.seq as i64,
            Some(&pre.salt),
        );
        self.dht
            .put_mutable(item, None)
            .map_err(|e| RvError::Dht(format!("put_presigned: {e}")))?;
        Ok(())
    }
}
