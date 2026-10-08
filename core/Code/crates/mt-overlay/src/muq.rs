//! Montana Unlinkable Queues (MUQ, Stage 2) — unlinkable mailbox addressing.
//! Spec: Montana P2P Network v0.9.0, Stage 2. Separate random send_id/recv_id
//! (not derived from account_id), two-hop deposit. The storage mechanics (Reed-Solomon/TTL/drop)
//! are reused from inbox_store (buffer key = recv_id).

use mt_codec::{write_bytes, write_u16, write_u32, write_u8, CanonicalEncode};
use mt_crypto::{PUBLIC_KEY_SIZE, SIGNATURE_SIZE};

use crate::challenge::{ChannelHash, Nonce, CHANNEL_HASH_SIZE, NONCE_SIZE};
use crate::frame::{FrameError, MsgId, MAX_PAYLOAD_LEN, MSG_ID_SIZE};

pub const QUEUE_ID_SIZE: usize = 32;
pub type QueueId = [u8; QUEUE_ID_SIZE]; // send_id or recv_id

// recv_id 32 + send_id 32 + recv_pubkey 1952 + send_pubkey 1952 + rotation_epoch 8 + quota 4
pub const QUEUE_WIRE_SIZE: usize = QUEUE_ID_SIZE * 2 + PUBLIC_KEY_SIZE * 2 + 8 + 4;

/// Queue object on the host (off-chain [P2P-1]). recv_id/send_id are independent and random.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct Queue {
    pub recv_id: QueueId,
    pub send_id: QueueId,
    pub recv_pubkey: [u8; PUBLIC_KEY_SIZE],
    pub send_pubkey: Option<[u8; PUBLIC_KEY_SIZE]>, // None = unsecured
    pub rotation_epoch: u64,
    pub quota: u32,
}

impl Queue {
    /// Generation of independent random ids (host-side, OS CSPRNG). Tests use from_parts.
    pub fn generate(
        recv_pubkey: [u8; PUBLIC_KEY_SIZE],
        send_pubkey: Option<[u8; PUBLIC_KEY_SIZE]>,
        rotation_epoch: u64,
        quota: u32,
    ) -> Result<Self, FrameError> {
        let mut recv_id = [0u8; QUEUE_ID_SIZE];
        let mut send_id = [0u8; QUEUE_ID_SIZE];
        getrandom::getrandom(&mut recv_id).map_err(|_| FrameError::Truncated)?;
        getrandom::getrandom(&mut send_id).map_err(|_| FrameError::Truncated)?;
        Ok(Self {
            recv_id,
            send_id,
            recv_pubkey,
            send_pubkey,
            rotation_epoch,
            quota,
        })
    }
}

impl Queue {
    /// Wire serialization for registering a queue on the host (byte-exact §413).
    /// send_pubkey None → 0×1952 (unsecured queue).
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut b = Vec::with_capacity(QUEUE_WIRE_SIZE);
        b.extend_from_slice(&self.recv_id);
        b.extend_from_slice(&self.send_id);
        b.extend_from_slice(&self.recv_pubkey);
        match &self.send_pubkey {
            Some(pk) => b.extend_from_slice(pk),
            None => b.extend_from_slice(&[0u8; PUBLIC_KEY_SIZE]),
        }
        b.extend_from_slice(&self.rotation_epoch.to_le_bytes());
        b.extend_from_slice(&self.quota.to_le_bytes());
        b
    }

    pub fn decode(input: &[u8]) -> Result<Self, FrameError> {
        if input.len() != QUEUE_WIRE_SIZE {
            return Err(FrameError::Truncated);
        }
        let mut o = 0;
        let mut recv_id = [0u8; QUEUE_ID_SIZE];
        recv_id.copy_from_slice(&input[o..o + QUEUE_ID_SIZE]);
        o += QUEUE_ID_SIZE;
        let mut send_id = [0u8; QUEUE_ID_SIZE];
        send_id.copy_from_slice(&input[o..o + QUEUE_ID_SIZE]);
        o += QUEUE_ID_SIZE;
        let mut recv_pubkey = [0u8; PUBLIC_KEY_SIZE];
        recv_pubkey.copy_from_slice(&input[o..o + PUBLIC_KEY_SIZE]);
        o += PUBLIC_KEY_SIZE;
        let mut spk = [0u8; PUBLIC_KEY_SIZE];
        spk.copy_from_slice(&input[o..o + PUBLIC_KEY_SIZE]);
        o += PUBLIC_KEY_SIZE;
        let send_pubkey = if spk == [0u8; PUBLIC_KEY_SIZE] {
            None
        } else {
            Some(spk)
        };
        let rotation_epoch = u64::from_le_bytes(
            input[o..o + 8]
                .try_into()
                .map_err(|_| FrameError::Truncated)?,
        );
        o += 8;
        let quota = u32::from_le_bytes(
            input[o..o + 4]
                .try_into()
                .map_err(|_| FrameError::Truncated)?,
        );
        // Invariants §423: ids are independent (at least recv_id != send_id), rotation_epoch>0, quota>0.
        if recv_id == send_id || rotation_epoch == 0 || quota == 0 {
            return Err(FrameError::LengthMismatch);
        }
        Ok(Self {
            recv_id,
            send_id,
            recv_pubkey,
            send_pubkey,
            rotation_epoch,
            quota,
        })
    }
}

/// Deposit to the host (inside ProxyForward, sealed with an ML-KEM-768 sealed-box to the host).
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct HostDeposit {
    pub send_id: QueueId,
    pub msg_id: MsgId,
    pub ttl_windows: u32,
    pub shard_index: u8,
    pub shard_total: u8,
    pub nonce: Nonce,
    pub ct: Vec<u8>,
    pub sig: [u8; SIGNATURE_SIZE], // ML-DSA-65 send_key (secured) or 0×SIGNATURE_SIZE (unsecured)
}

// send_id 32 + msg_id 16 + ttl 4 + idx 1 + total 1 + nonce 16 + ct_len 4
const HD_HEADER: usize = QUEUE_ID_SIZE + MSG_ID_SIZE + 4 + 1 + 1 + NONCE_SIZE + 4;

impl CanonicalEncode for HostDeposit {
    fn encode(&self, buf: &mut Vec<u8>) {
        write_bytes(buf, &self.send_id);
        write_bytes(buf, &self.msg_id);
        write_u32(buf, self.ttl_windows);
        write_u8(buf, self.shard_index);
        write_u8(buf, self.shard_total);
        write_bytes(buf, &self.nonce);
        write_u32(buf, self.ct.len() as u32);
        write_bytes(buf, &self.ct);
        write_bytes(buf, &self.sig); // sig is fixed SIGNATURE_SIZE (§462), without a length prefix
    }
}

impl HostDeposit {
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut b = Vec::with_capacity(HD_HEADER + self.ct.len() + SIGNATURE_SIZE);
        self.encode(&mut b);
        b
    }

    pub fn decode(input: &[u8]) -> Result<Self, FrameError> {
        if input.len() < HD_HEADER {
            return Err(FrameError::Truncated);
        }
        let mut o = 0;
        let mut send_id = [0u8; QUEUE_ID_SIZE];
        send_id.copy_from_slice(&input[o..o + QUEUE_ID_SIZE]);
        o += QUEUE_ID_SIZE;
        let mut msg_id = [0u8; MSG_ID_SIZE];
        msg_id.copy_from_slice(&input[o..o + MSG_ID_SIZE]);
        o += MSG_ID_SIZE;
        let ttl_windows = u32::from_le_bytes(
            input[o..o + 4]
                .try_into()
                .map_err(|_| FrameError::Truncated)?,
        );
        o += 4;
        let shard_index = input[o];
        o += 1;
        let shard_total = input[o];
        o += 1;
        let mut nonce = [0u8; NONCE_SIZE];
        nonce.copy_from_slice(&input[o..o + NONCE_SIZE]);
        o += NONCE_SIZE;
        let ct_len = u32::from_le_bytes(
            input[o..o + 4]
                .try_into()
                .map_err(|_| FrameError::Truncated)?,
        ) as usize;
        o += 4;
        if ct_len > MAX_PAYLOAD_LEN || input.len() < o + ct_len + SIGNATURE_SIZE {
            return Err(FrameError::LengthMismatch);
        }
        let ct = input[o..o + ct_len].to_vec();
        o += ct_len;
        // sig is a fixed SIGNATURE_SIZE bytes (§462; unsecured = 0×SIGNATURE_SIZE)
        if input.len() - o != SIGNATURE_SIZE {
            return Err(FrameError::LengthMismatch);
        }
        let mut sig = [0u8; SIGNATURE_SIZE];
        sig.copy_from_slice(&input[o..o + SIGNATURE_SIZE]);
        Ok(Self {
            send_id,
            msg_id,
            ttl_windows,
            shard_index,
            shard_total,
            nonce,
            ct,
            sig,
        })
    }
}

/// Wrapping of a deposit for the entry-proxy (the proxy cannot decrypt sealed).
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct ProxyForward {
    pub host_addr: crate::OverlayAddr, // overlay address of the queue-host
    pub sealed: Vec<u8>,               // HostDeposit sealed with an ML-KEM-768 sealed-box for the host
}

impl ProxyForward {
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut b = Vec::with_capacity(32 + 4 + self.sealed.len());
        b.extend_from_slice(&self.host_addr);
        b.extend_from_slice(&(self.sealed.len() as u32).to_le_bytes());
        b.extend_from_slice(&self.sealed);
        b
    }

    pub fn decode(input: &[u8]) -> Result<Self, FrameError> {
        if input.len() < 36 {
            return Err(FrameError::Truncated);
        }
        let mut host_addr = [0u8; 32];
        host_addr.copy_from_slice(&input[..32]);
        let sealed_len = u32::from_le_bytes(
            input[32..36]
                .try_into()
                .map_err(|_| FrameError::Truncated)?,
        ) as usize;
        if input.len() - 36 != sealed_len {
            return Err(FrameError::LengthMismatch);
        }
        Ok(Self {
            host_addr,
            sealed: input[36..].to_vec(),
        })
    }
}

/// Two-hop FETCH: the recipient fetches through a courier (symmetric to ProxyForward).
/// The courier carries the sealed QueueSubscribe to the host and returns QueueResp without seeing recv_id.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct ReceiveProxy {
    pub host_addr: crate::OverlayAddr,
    pub sealed: Vec<u8>, // QueueSubscribe, sealed for the host (the courier cannot decrypt)
}

impl ReceiveProxy {
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut b = Vec::with_capacity(32 + 4 + self.sealed.len());
        b.extend_from_slice(&self.host_addr);
        b.extend_from_slice(&(self.sealed.len() as u32).to_le_bytes());
        b.extend_from_slice(&self.sealed);
        b
    }

    pub fn decode(input: &[u8]) -> Result<Self, FrameError> {
        if input.len() < 36 {
            return Err(FrameError::Truncated);
        }
        let mut host_addr = [0u8; 32];
        host_addr.copy_from_slice(&input[..32]);
        let sealed_len = u32::from_le_bytes(
            input[32..36]
                .try_into()
                .map_err(|_| FrameError::Truncated)?,
        ) as usize;
        if input.len() - 36 != sealed_len {
            return Err(FrameError::LengthMismatch);
        }
        Ok(Self {
            host_addr,
            sealed: input[36..].to_vec(),
        })
    }
}

/// channel_hash marker of a two-hop fetch: there is no direct B<->host channel, so 0×32 is
/// substituted for the TLS-Exporter. The TLS-Exporter yields random 32 B → a collision with 0×32
/// is excluded; anti-replay is carried by host nonce-tracking (QueueHost::subscribe_relay).
pub const RELAY_CHANNEL_MARKER: ChannelHash = [0u8; CHANNEL_HASH_SIZE];

/// Fetch signature through a courier: sign_subscribe with channel_hash = RELAY_CHANNEL_MARKER.
pub fn sign_subscribe_relay(
    recv_sk: &mt_crypto::SecretKey,
    recv_id: &QueueId,
    nonce: &Nonce,
) -> Result<mt_crypto::Signature, mt_crypto::CryptoError> {
    sign_subscribe(recv_sk, recv_id, nonce, &RELAY_CHANNEL_MARKER)
}

/// Fetch by the recipient (direct B<->host connection, the signature is bound to the channel — F3/R4).
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct QueueSubscribe {
    pub recv_id: QueueId,
    pub nonce: Nonce,
    pub sig: [u8; SIGNATURE_SIZE],
}

impl QueueSubscribe {
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut b = Vec::with_capacity(QUEUE_ID_SIZE + NONCE_SIZE + SIGNATURE_SIZE);
        b.extend_from_slice(&self.recv_id);
        b.extend_from_slice(&self.nonce);
        b.extend_from_slice(&self.sig);
        b
    }

    pub fn decode(input: &[u8]) -> Result<Self, FrameError> {
        if input.len() != QUEUE_ID_SIZE + NONCE_SIZE + SIGNATURE_SIZE {
            return Err(FrameError::Truncated);
        }
        let mut recv_id = [0u8; QUEUE_ID_SIZE];
        recv_id.copy_from_slice(&input[..QUEUE_ID_SIZE]);
        let mut nonce = [0u8; NONCE_SIZE];
        nonce.copy_from_slice(&input[QUEUE_ID_SIZE..QUEUE_ID_SIZE + NONCE_SIZE]);
        let mut sig = [0u8; SIGNATURE_SIZE];
        sig.copy_from_slice(&input[QUEUE_ID_SIZE + NONCE_SIZE..]);
        Ok(Self {
            recv_id,
            nonce,
            sig,
        })
    }
}

/// Host response to the recipient (shards from the recv_id buffer).
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct QueueResp {
    pub items: Vec<QueueItem>,
}

#[derive(Clone, PartialEq, Eq, Debug)]
pub struct QueueItem {
    pub msg_id: MsgId,
    pub shard_index: u8,
    pub shard_total: u8,
    pub ct: Vec<u8>,
}

impl QueueResp {
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut b = Vec::new();
        write_u16(&mut b, self.items.len() as u16);
        for it in &self.items {
            write_bytes(&mut b, &it.msg_id);
            write_u8(&mut b, it.shard_index);
            write_u8(&mut b, it.shard_total);
            write_u32(&mut b, it.ct.len() as u32);
            write_bytes(&mut b, &it.ct);
        }
        b
    }

    pub fn decode(input: &[u8]) -> Result<Self, FrameError> {
        if input.len() < 2 {
            return Err(FrameError::Truncated);
        }
        let count = u16::from_le_bytes([input[0], input[1]]) as usize;
        let mut o = 2;
        let mut items = Vec::with_capacity(count.min((input.len() - 2) / 22));
        for _ in 0..count {
            if input.len() < o + MSG_ID_SIZE + 1 + 1 + 4 {
                return Err(FrameError::Truncated);
            }
            let mut msg_id = [0u8; MSG_ID_SIZE];
            msg_id.copy_from_slice(&input[o..o + MSG_ID_SIZE]);
            o += MSG_ID_SIZE;
            let shard_index = input[o];
            o += 1;
            let shard_total = input[o];
            o += 1;
            let ct_len = u32::from_le_bytes(
                input[o..o + 4]
                    .try_into()
                    .map_err(|_| FrameError::Truncated)?,
            ) as usize;
            o += 4;
            if ct_len > MAX_PAYLOAD_LEN || input.len() < o + ct_len {
                return Err(FrameError::LengthMismatch);
            }
            items.push(QueueItem {
                msg_id,
                shard_index,
                shard_total,
                ct: input[o..o + ct_len].to_vec(),
            });
            o += ct_len;
        }
        if o != input.len() {
            return Err(FrameError::LengthMismatch);
        }
        Ok(Self { items })
    }
}

// --- signatures (reuse challenge_message from Stage 1) ---

/// Fetch signature: sig = ML-DSA-65(recv_key, "mt-queue-sub"‖0x00‖recv_id‖nonce‖channel_hash).
pub fn sign_subscribe(
    recv_sk: &mt_crypto::SecretKey,
    recv_id: &QueueId,
    nonce: &Nonce,
    channel_hash: &ChannelHash,
) -> Result<mt_crypto::Signature, mt_crypto::CryptoError> {
    let msg = crate::challenge::challenge_message(
        mt_codec::domain::QUEUE_SUB,
        recv_id,
        nonce,
        channel_hash,
    );
    mt_crypto::sign(recv_sk, &msg)
}

/// F3/E-2: fetch verification — signature against the STORED recv_pubkey of the queue + channel_hash.
/// Ownership is encapsulated (recv_pubkey is bound to the queue on the host, it cannot be forgotten).
pub fn verify_subscribe(
    recv_pubkey: &[u8; PUBLIC_KEY_SIZE],
    recv_id: &QueueId,
    nonce: &Nonce,
    channel_hash: &ChannelHash,
    sig: &mt_crypto::Signature,
) -> bool {
    let msg = crate::challenge::challenge_message(
        mt_codec::domain::QUEUE_SUB,
        recv_id,
        nonce,
        channel_hash,
    );
    mt_crypto::verify(&mt_crypto::PublicKey::from_array(*recv_pubkey), &msg, sig)
}

/// Deposit signature (secured): sig = ML-DSA-65(send_key, "mt-queue-send"‖0x00‖send_id‖msg_id‖nonce).
/// WITHOUT channel_hash — two hops, there is no direct sender<->host channel; replay is closed by send_key+nonce.
pub fn sign_deposit(
    send_sk: &mt_crypto::SecretKey,
    send_id: &QueueId,
    msg_id: &MsgId,
    nonce: &Nonce,
) -> Result<mt_crypto::Signature, mt_crypto::CryptoError> {
    let mut resource = Vec::with_capacity(QUEUE_ID_SIZE + MSG_ID_SIZE);
    resource.extend_from_slice(send_id);
    resource.extend_from_slice(msg_id);
    let mut msg = Vec::new();
    msg.extend_from_slice(mt_codec::domain::QUEUE_SEND);
    msg.push(0u8);
    msg.extend_from_slice(&resource);
    msg.extend_from_slice(nonce);
    mt_crypto::sign(send_sk, &msg)
}

pub fn verify_deposit(
    send_pubkey: &[u8; PUBLIC_KEY_SIZE],
    send_id: &QueueId,
    msg_id: &MsgId,
    nonce: &Nonce,
    sig: &mt_crypto::Signature,
) -> bool {
    let mut msg = Vec::new();
    msg.extend_from_slice(mt_codec::domain::QUEUE_SEND);
    msg.push(0u8);
    msg.extend_from_slice(send_id);
    msg.extend_from_slice(msg_id);
    msg.extend_from_slice(nonce);
    mt_crypto::verify(&mt_crypto::PublicKey::from_array(*send_pubkey), &msg, sig)
}

/// ML-DSA-65 keypair (pubkey, privkey).
pub type Keypair = (mt_crypto::PublicKey, mt_crypto::SecretKey);
/// Key pair of a queue (recv, send).
pub type QueueKeypairs = (Keypair, Keypair);

/// M-1: ephemeral per-queue authentication keys from the session routing_secret.
/// recv_pubkey/send_pubkey are NOT equal to account_pubkey — the host sees a queue key, not a wallet,
/// so it cannot derive account_id or link the queue to an identity. Both sides derive
/// deterministically (routing_secret is shared). First contact (no routing_secret) — CSPRNG.
pub fn derive_queue_keypairs(
    routing_secret: &[u8; 32],
    queue_index: u64,
) -> Result<QueueKeypairs, mt_crypto::CryptoError> {
    let qi = queue_index.to_le_bytes();
    let recv_seed = mt_crypto::hash(mt_codec::domain::QUEUE_RECV, &[routing_secret, &qi]);
    let send_seed = mt_crypto::hash(mt_codec::domain::QUEUE_SEND, &[routing_secret, &qi]);
    let recv = mt_crypto::keypair_from_seed(&recv_seed)?;
    let send = mt_crypto::keypair_from_seed(&send_seed)?;
    Ok((recv, send))
}

#[cfg(test)]
mod tests {
    use super::*;
    use mt_crypto::{keypair_from_seed, PublicKey, SecretKey};

    fn kp(seed: u8) -> ([u8; PUBLIC_KEY_SIZE], SecretKey) {
        let (pk, sk): (PublicKey, SecretKey) = keypair_from_seed(&[seed; 32]).unwrap();
        (*pk.as_bytes(), sk)
    }

    #[test]
    fn queue_wire_roundtrip_secured_unsecured_and_reject_equal_ids() {
        let (rpk, _) = kp(0x11);
        let (spk, _) = kp(0x22);
        for send_pubkey in [Some(spk), None] {
            let q = Queue {
                recv_id: [0x71; 32],
                send_id: [0x51; 32],
                recv_pubkey: rpk,
                send_pubkey,
                rotation_epoch: 1000,
                quota: 64,
            };
            let b = q.to_bytes();
            assert_eq!(b.len(), QUEUE_WIRE_SIZE);
            assert_eq!(Queue::decode(&b).unwrap(), q);
        }
        // equal recv_id/send_id — malformed (§423 independence)
        let bad = Queue {
            recv_id: [0x71; 32],
            send_id: [0x71; 32],
            recv_pubkey: rpk,
            send_pubkey: None,
            rotation_epoch: 1000,
            quota: 64,
        };
        assert!(Queue::decode(&bad.to_bytes()).is_err());
    }

    #[test]
    fn queue_ids_independent_random() {
        let (rpk, _) = kp(0x11);
        let q = Queue::generate(rpk, None, 100, 64).unwrap();
        assert_ne!(q.recv_id, q.send_id);
        assert_ne!(q.recv_id, [0u8; 32]);
    }

    #[test]
    fn hostdeposit_roundtrip_secured_and_unsecured() {
        for sig in [[0x03u8; SIGNATURE_SIZE], [0u8; SIGNATURE_SIZE]] {
            let d = HostDeposit {
                send_id: [0xAA; 32],
                msg_id: [0xBB; 16],
                ttl_windows: 240,
                shard_index: 1,
                shard_total: 4,
                nonce: [0x07; 16],
                ct: vec![0xCC; 256],
                sig,
            };
            assert_eq!(HostDeposit::decode(&d.to_bytes()).unwrap(), d);
        }
    }

    #[test]
    fn receiveproxy_roundtrip() {
        let rp = ReceiveProxy {
            host_addr: [0xEE; 32],
            sealed: vec![0x5A; 3357], // QueueSubscribe size (32+16+3309)
        };
        assert_eq!(ReceiveProxy::decode(&rp.to_bytes()).unwrap(), rp);
    }

    #[test]
    fn proxyforward_roundtrip() {
        let pf = ProxyForward {
            host_addr: [0xEE; 32],
            sealed: vec![0x5A; 500],
        };
        assert_eq!(ProxyForward::decode(&pf.to_bytes()).unwrap(), pf);
    }

    #[test]
    fn queuesubscribe_roundtrip_and_size() {
        let s = QueueSubscribe {
            recv_id: [0x01; 32],
            nonce: [0x02; 16],
            sig: [0x03; SIGNATURE_SIZE],
        };
        let b = s.to_bytes();
        assert_eq!(b.len(), 32 + 16 + 3309);
        assert_eq!(QueueSubscribe::decode(&b).unwrap(), s);
    }

    #[test]
    fn queueresp_roundtrip() {
        let r = QueueResp {
            items: vec![
                QueueItem {
                    msg_id: [1; 16],
                    shard_index: 0,
                    shard_total: 4,
                    ct: vec![9; 256],
                },
                QueueItem {
                    msg_id: [2; 16],
                    shard_index: 1,
                    shard_total: 4,
                    ct: vec![8; 1024],
                },
            ],
        };
        assert_eq!(QueueResp::decode(&r.to_bytes()).unwrap(), r);
    }

    #[test]
    fn subscribe_sig_verify_and_channel_binding() {
        let (rpk, rsk) = kp(0x11);
        let recv_id = [0x33; 32];
        let nonce = [0x07; 16];
        let ch = [0x0C; 32];
        let sig = sign_subscribe(&rsk, &recv_id, &nonce, &ch).unwrap();
        assert!(verify_subscribe(&rpk, &recv_id, &nonce, &ch, &sig));
        // another channel — the signature is not portable (F3)
        assert!(!verify_subscribe(&rpk, &recv_id, &nonce, &[0x0D; 32], &sig));
        // another recv_pubkey — will not match
        let (rpk2, _) = kp(0x12);
        assert!(!verify_subscribe(&rpk2, &recv_id, &nonce, &ch, &sig));
    }

    #[test]
    fn m1_queue_keys_ephemeral_deterministic_and_distinct() {
        // M-1: deterministic from routing_secret, recv≠send, different queue_index → different keys.
        let rs = [0x42u8; 32];
        let ((r0pk, _), (s0pk, _)) = derive_queue_keypairs(&rs, 0).unwrap();
        let ((r0pk_b, _), _) = derive_queue_keypairs(&rs, 0).unwrap();
        assert_eq!(
            r0pk.as_bytes(),
            r0pk_b.as_bytes(),
            "determinism by routing_secret+index"
        );
        assert_ne!(
            r0pk.as_bytes(),
            s0pk.as_bytes(),
            "recv_key != send_key (different domains)"
        );
        let ((r1pk, _), _) = derive_queue_keypairs(&rs, 1).unwrap();
        assert_ne!(
            r0pk.as_bytes(),
            r1pk.as_bytes(),
            "different queue_index → different keys"
        );
        // different routing_secret → different keys (unlinkability between sessions)
        let ((r0pk2, _), _) = derive_queue_keypairs(&[0x43u8; 32], 0).unwrap();
        assert_ne!(r0pk.as_bytes(), r0pk2.as_bytes());
    }

    #[test]
    fn deposit_sig_verify_send_key() {
        let (spk, ssk) = kp(0x22);
        let send_id = [0x44; 32];
        let msg_id = [0x55; 16];
        let nonce = [0x08; 16];
        let sig = sign_deposit(&ssk, &send_id, &msg_id, &nonce).unwrap();
        assert!(verify_deposit(&spk, &send_id, &msg_id, &nonce, &sig));
        assert!(!verify_deposit(&spk, &send_id, &msg_id, &[0x09; 16], &sig)); // another nonce
    }
}
