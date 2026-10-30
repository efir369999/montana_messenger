// The post-quantum handshake, in four flights. Roles are fixed by the connection: the side that
// opened it is the initiator. Both encapsulations enter the master, so a channel is secure if
// either of them was; the two directional keys come from it under distinct domains, so a key
// protecting one direction never protects the other; and each signature covers the transcript
// under a domain of its own, so neither can be replayed as the other.
//
// The key that signs is the answering key of the device, derived from the machine's own secret.
// A device that signed a handshake with a branch of a person's seed would bind a handshake to a
// person, which is the edge this protocol does not create.

use crate::WireError;
use mt_codec::{domain, hash, size, Part};
use mt_suite::{aead, kem, sign};
use zeroize::Zeroize;

#[derive(Debug, PartialEq, Eq)]
pub enum HandshakeError {
    WrongLength { expected: usize, found: usize },
    Signing,
    Unverified,
    // A future suite enters through a protocol version upgrade and an explicit row of the table.
    // A flight naming a row nobody wrote is refused rather than carried under a scheme this tree
    // does not hold.
    UnknownSuite { suite_id: u16 },
    // Two flights naming two suites are two sides of two protocols. The transcript covers the
    // suite, so a mismatch would fail verification anyway; it is named here rather than left to
    // read as a broken signature, because the two are different faults.
    SuiteMismatch { hello: u16, answer: u16 },
    // A sealed part of a flight that does not open: a stranger's first flight, or a signature
    // sealed under another master. The far side is told nothing of it.
    Unopened,
}

fn known(suite_id: u16) -> Result<(), HandshakeError> {
    match mt_suite::suite::scheme(suite_id) {
        Some(_) => Ok(()),
        None => Err(HandshakeError::UnknownSuite { suite_id }),
    }
}

fn fixed<const N: usize>(bytes: &[u8], at: &mut usize) -> [u8; N] {
    let mut out = [0u8; N];
    out.copy_from_slice(&bytes[*at..*at + N]);
    *at += N;
    out
}

// A part of a flight that names a key crosses sealed, under a key that seals that part and nothing
// else, so the nonce of the one seal it makes is fixed rather than drawn: a nonce exists to keep two
// seals under one key apart, and these keys make one each (Canon, "The post-quantum handshake").
const ONE_SEAL: [u8; size::AEAD_NONCE] = [0u8; size::AEAD_NONCE];
pub const SEALED_KEY: usize = size::SIGNING_PUBLIC_KEY + size::AEAD_TAG;
pub const SEALED_SIGNATURE: usize = size::SIGNATURE + size::AEAD_TAG;

fn seal_with(key: [u8; 32], part: &[u8]) -> Result<Vec<u8>, HandshakeError> {
    aead::seal(&aead::SealingKey::new(key), &ONE_SEAL, &[], part)
        .map_err(|_| HandshakeError::Signing)
}

fn open_with<const N: usize>(key: [u8; 32], sealed: &[u8]) -> Result<[u8; N], HandshakeError> {
    let opened = aead::open(&aead::SealingKey::new(key), &ONE_SEAL, &[], sealed)
        .map_err(|_| HandshakeError::Unopened)?;
    let mut out = [0u8; N];
    out.copy_from_slice(&opened);
    Ok(out)
}

// Flight one, from the initiator. It names the initiator's answering key only sealed, under a key
// that comes of an encapsulation to the responder's static key, which the acquaintance line carries:
// a side that was not handed the line produces a flight the responder opens to nothing, and gets
// silence (#22, G-1 (b); Network, "Where a shared secret comes from").
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct Hello {
    pub suite_id: u16,
    pub kem_key: [u8; size::KEM_PUBLIC_KEY],
    pub static_ct: [u8; kem::CIPHERTEXT_BYTES],
    pub sealed_key: [u8; SEALED_KEY],
}

pub fn hello_len() -> usize {
    2 + size::KEM_PUBLIC_KEY + kem::CIPHERTEXT_BYTES + SEALED_KEY
}

impl Hello {
    pub fn encode(&self) -> Vec<u8> {
        let mut out = Vec::with_capacity(hello_len());
        out.extend_from_slice(&self.suite_id.to_le_bytes());
        out.extend_from_slice(&self.kem_key);
        out.extend_from_slice(&self.static_ct);
        out.extend_from_slice(&self.sealed_key);
        out
    }

    pub fn parse(bytes: &[u8]) -> Result<Self, HandshakeError> {
        if bytes.len() != hello_len() {
            return Err(HandshakeError::WrongLength {
                expected: hello_len(),
                found: bytes.len(),
            });
        }
        let suite_id = u16::from_le_bytes([bytes[0], bytes[1]]);
        known(suite_id)?;
        let at = &mut 2usize;
        Ok(Self {
            suite_id,
            kem_key: fixed(bytes, at),
            static_ct: fixed(bytes, at),
            sealed_key: fixed(bytes, at),
        })
    }
}

// The key the initiator's answering key is sealed under: the secret of the encapsulation to the
// static key, and everything of the flight that stands beside it.
pub fn hello_key(
    ss_s: &[u8; 32],
    suite_id: u16,
    pk_s: &[u8; size::KEM_PUBLIC_KEY],
    pk_i: &[u8; size::KEM_PUBLIC_KEY],
    ct_s: &[u8; kem::CIPHERTEXT_BYTES],
) -> [u8; 32] {
    hash(
        domain::MT_NOISE_PQ_V2_HELLO,
        &[
            Part::of(ss_s),
            Part::of(&suite_id.to_le_bytes()),
            Part::of(pk_s),
            Part::of(pk_i),
            Part::of(ct_s),
        ],
    )
}

pub fn seal_key(
    key: [u8; 32],
    answering_key: &[u8; size::SIGNING_PUBLIC_KEY],
) -> Result<[u8; SEALED_KEY], HandshakeError> {
    let sealed = seal_with(key, answering_key)?;
    let mut out = [0u8; SEALED_KEY];
    out.copy_from_slice(&sealed);
    Ok(out)
}

// What a responder reads of a first flight. ML-KEM answers every ciphertext with some secret, so a
// stranger's flight decapsulates; what it never does is open, and a flight that does not open is
// answered by no byte at all.
pub fn open_key(
    key: [u8; 32],
    sealed: &[u8; SEALED_KEY],
) -> Result<[u8; size::SIGNING_PUBLIC_KEY], HandshakeError> {
    open_with(key, sealed)
}

// Flight two, from the responder. It carries no answering key: the initiator holds it from the line,
// and the signature of flight four is what proves the responder holds its secret.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct HelloAnswer {
    pub suite_id: u16,
    pub kem_key: [u8; size::KEM_PUBLIC_KEY],
    pub kem_ct: [u8; kem::CIPHERTEXT_BYTES],
}

pub fn hello_answer_len() -> usize {
    2 + size::KEM_PUBLIC_KEY + kem::CIPHERTEXT_BYTES
}

impl HelloAnswer {
    pub fn encode(&self) -> Vec<u8> {
        let mut out = Vec::with_capacity(hello_answer_len());
        out.extend_from_slice(&self.suite_id.to_le_bytes());
        out.extend_from_slice(&self.kem_key);
        out.extend_from_slice(&self.kem_ct);
        out
    }

    pub fn parse(bytes: &[u8]) -> Result<Self, HandshakeError> {
        if bytes.len() != hello_answer_len() {
            return Err(HandshakeError::WrongLength {
                expected: hello_answer_len(),
                found: bytes.len(),
            });
        }
        let suite_id = u16::from_le_bytes([bytes[0], bytes[1]]);
        known(suite_id)?;
        let at = &mut 2usize;
        Ok(Self {
            suite_id,
            kem_key: fixed(bytes, at),
            kem_ct: fixed(bytes, at),
        })
    }
}

// Flight three, from the initiator, who now holds every value of the transcript. Its signature
// crosses sealed: one in the open would let whoever holds a candidate key test it.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct HelloFinish {
    pub kem_ct: [u8; kem::CIPHERTEXT_BYTES],
    pub sealed_signature: [u8; SEALED_SIGNATURE],
}

pub fn hello_finish_len() -> usize {
    kem::CIPHERTEXT_BYTES + SEALED_SIGNATURE
}

impl HelloFinish {
    pub fn encode(&self) -> Vec<u8> {
        let mut out = Vec::with_capacity(hello_finish_len());
        out.extend_from_slice(&self.kem_ct);
        out.extend_from_slice(&self.sealed_signature);
        out
    }

    pub fn parse(bytes: &[u8]) -> Result<Self, HandshakeError> {
        if bytes.len() != hello_finish_len() {
            return Err(HandshakeError::WrongLength {
                expected: hello_finish_len(),
                found: bytes.len(),
            });
        }
        let at = &mut 0usize;
        Ok(Self {
            kem_ct: fixed(bytes, at),
            sealed_signature: fixed(bytes, at),
        })
    }
}

// Flight four, from the responder, its signature sealed for the same reason.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct HelloConfirm {
    pub sealed_signature: [u8; SEALED_SIGNATURE],
}

pub fn hello_confirm_len() -> usize {
    SEALED_SIGNATURE
}

impl HelloConfirm {
    pub fn encode(&self) -> Vec<u8> {
        self.sealed_signature.to_vec()
    }

    pub fn parse(bytes: &[u8]) -> Result<Self, HandshakeError> {
        if bytes.len() != hello_confirm_len() {
            return Err(HandshakeError::WrongLength {
                expected: hello_confirm_len(),
                found: bytes.len(),
            });
        }
        let at = &mut 0usize;
        Ok(Self {
            sealed_signature: fixed(bytes, at),
        })
    }
}

// The order of folding is fixed by role and not by arrival, so both sides compute one master from
// one exchange. What enters is everything the two sides named: the suite, the answering key of
// each, the static key the line carries, and the values of the three encapsulations.
//
// The two answering keys enter for a reason that is not decoration. A signature proves possession
// of the key that made it; if the key itself stands outside what is signed, a third party may
// relay the encapsulation untouched, put **its own** answering key in the first flight and sign
// with it, and the responder finishes a channel it attributes to that third party while the bytes
// belong to the initiator. Nothing is decrypted by anyone new — and the machine credited for the
// path is the wrong one. The suite enters for the same reason in the other direction: a value
// negotiated outside the transcript is a value an intermediary may lower.
//
// Every part is of a width the set fixes, so the concatenation is self-delimiting by its types
// and no two different inputs share a preimage.
#[allow(clippy::too_many_arguments)]
pub fn transcript(
    suite_id: u16,
    id_pk_i: &[u8; size::SIGNING_PUBLIC_KEY],
    id_pk_r: &[u8; size::SIGNING_PUBLIC_KEY],
    pk_s: &[u8; size::KEM_PUBLIC_KEY],
    pk_i: &[u8; size::KEM_PUBLIC_KEY],
    pk_r: &[u8; size::KEM_PUBLIC_KEY],
    ct_s: &[u8; kem::CIPHERTEXT_BYTES],
    ct_r: &[u8; kem::CIPHERTEXT_BYTES],
    ct_i: &[u8; kem::CIPHERTEXT_BYTES],
) -> [u8; 32] {
    hash(
        domain::MT_NOISE_PQ_V2_TRANSCRIPT,
        &[
            Part::of(&suite_id.to_le_bytes()),
            Part::of(id_pk_i),
            Part::of(id_pk_r),
            Part::of(pk_s),
            Part::of(pk_i),
            Part::of(pk_r),
            Part::of(ct_s),
            Part::of(ct_r),
            Part::of(ct_i),
        ],
    )
}

// The one suite the two flights name: both of them state it, and a pair naming two is refused
// before a key is derived from either.
fn agreed(hello: &Hello, answer: &HelloAnswer) -> Result<u16, HandshakeError> {
    if hello.suite_id != answer.suite_id {
        return Err(HandshakeError::SuiteMismatch {
            hello: hello.suite_id,
            answer: answer.suite_id,
        });
    }
    Ok(hello.suite_id)
}

// All three shared secrets enter, in the order of the flights that carried them, so a channel is
// secure if any one of the three encapsulations was.
pub fn master(
    ss_s: &[u8; 32],
    ss_r: &[u8; 32],
    ss_i: &[u8; 32],
    transcript: &[u8; 32],
) -> [u8; 32] {
    hash(
        domain::MT_NOISE_PQ_V2_MASTER,
        &[
            Part::of(ss_s),
            Part::of(ss_r),
            Part::of(ss_i),
            Part::of(transcript),
        ],
    )
}

// The keys the two signatures cross under. They come of the master as the directional keys do,
// under domains of their own, so a key that seals a signature never seals a message.
pub fn initiator_seal(master: &[u8; 32]) -> [u8; 32] {
    hash(domain::MT_NOISE_PQ_V2_SEAL_I, &[Part::of(master)])
}

pub fn responder_seal(master: &[u8; 32]) -> [u8; 32] {
    hash(domain::MT_NOISE_PQ_V2_SEAL_R, &[Part::of(master)])
}

pub fn initiator_to_responder(master: &[u8; 32]) -> [u8; 32] {
    hash(domain::MT_NOISE_PQ_V1_I2R, &[Part::of(master)])
}

pub fn responder_to_initiator(master: &[u8; 32]) -> [u8; 32] {
    hash(domain::MT_NOISE_PQ_V1_R2I, &[Part::of(master)])
}

// **The secret of a link after a renewal of its keys** (Network, "How a link renews its keys";
// issue #75). The secret of a link begins as the master of its handshake, and the two directional
// keys are derived from every secret of the link exactly as from the master, by the two functions
// above, so a link that never renewed carries the keys of its handshake and nothing here moves the
// handshake, its transcript or its vectors. A renewal folds the previous secret, both shared secrets
// and the four public values it exchanged, in the order of the roles of the handshake — the values
// of the side that opened the link first — and never in the order of the renewal, so both sides
// compute one value whichever of them offered. `pk_i` and `pk_r` are the encapsulation keys the
// initiator and the responder drew for this renewal alone, `ct_i` the encapsulation the initiator
// made to `pk_r` and `ct_r` the one the responder made to `pk_i`; `ss_i` and `ss_r` are what those
// open to. Both encapsulations enter, as both enter a master, so the new secret is beyond whoever
// holds neither fresh decapsulation key. Every part has a width the set fixes, so the concatenation
// is self-delimiting as the transcript's is.
pub fn renewed(
    previous: &[u8; 32],
    ss_i: &[u8; 32],
    ss_r: &[u8; 32],
    pk_i: &[u8; size::KEM_PUBLIC_KEY],
    pk_r: &[u8; size::KEM_PUBLIC_KEY],
    ct_i: &[u8; kem::CIPHERTEXT_BYTES],
    ct_r: &[u8; kem::CIPHERTEXT_BYTES],
) -> [u8; 32] {
    hash(
        domain::MT_LINK_RENEW,
        &[
            Part::of(previous),
            Part::of(ss_i),
            Part::of(ss_r),
            Part::of(pk_i),
            Part::of(pk_r),
            Part::of(ct_i),
            Part::of(ct_r),
        ],
    )
}

// What each side signs: its own domain, the NUL of the primitive, and the transcript. The two take
// distinct domains, so neither signature can be replayed as the other.
fn signed_message(space: mt_codec::Domain, transcript: &[u8; 32]) -> Vec<u8> {
    let mut out = Vec::with_capacity(space.as_str().len() + 1 + 32);
    out.extend_from_slice(space.as_str().as_bytes());
    out.push(0x00);
    out.extend_from_slice(transcript);
    out
}

pub fn initiator_message(transcript: &[u8; 32]) -> Vec<u8> {
    signed_message(domain::MT_NOISE_PQ_V1_SIG_I, transcript)
}

pub fn responder_message(transcript: &[u8; 32]) -> Vec<u8> {
    signed_message(domain::MT_NOISE_PQ_V1_SIG_R, transcript)
}

// What a side holds once the four flights have run: the transcript both computed and the two
// directional keys. Its fields are its own, and the only ways to make one are the two doors below,
// each of which verifies the signature of the other side over the transcript it computed itself
// before it answers. **A side that cannot verify carries nothing**, and the type is what holds it
// to that: there is no arrangement of legal calls that yields the keys of an unverified channel.
pub struct Channel {
    transcript: [u8; 32],
    initiator_to_responder: [u8; 32],
    responder_to_initiator: [u8; 32],
}

// What this holds are the two keys of a session, so it shows nothing, compares nothing and wipes
// itself. A derived `Debug` would print both keys into whatever a test, a log or the message of a
// panic goes to; a derived `PartialEq` would compare key material in a time that depends on where
// the first difference stands; and a derived `Clone` would put a second copy where nothing wipes
// it. The transcript is public and stands beside them, and it is what a caller compares when it
// asks whether two sides reached one channel.
impl core::fmt::Debug for Channel {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        f.write_str("Channel(<wiped on drop, never shown>)")
    }
}

impl Drop for Channel {
    fn drop(&mut self) {
        self.transcript.zeroize();
        self.initiator_to_responder.zeroize();
        self.responder_to_initiator.zeroize();
    }
}

impl Channel {
    pub fn transcript(&self) -> &[u8; 32] {
        &self.transcript
    }

    pub fn initiator_to_responder(&self) -> &[u8; 32] {
        &self.initiator_to_responder
    }

    pub fn responder_to_initiator(&self) -> &[u8; 32] {
        &self.responder_to_initiator
    }
}

// What both sides derive once every value of the transcript is held, before either signature is
// read: the transcript, and the master the channel and the two seals come of. It wipes itself, and
// it becomes a channel only through the verification of the other side's signature.
pub struct Keys {
    transcript: [u8; 32],
    master: [u8; 32],
}

impl Drop for Keys {
    fn drop(&mut self) {
        self.transcript.zeroize();
        self.master.zeroize();
    }
}

impl Keys {
    #[allow(clippy::too_many_arguments)]
    pub fn of(
        hello: &Hello,
        answer: &HelloAnswer,
        id_pk_i: &[u8; size::SIGNING_PUBLIC_KEY],
        id_pk_r: &[u8; size::SIGNING_PUBLIC_KEY],
        pk_s: &[u8; size::KEM_PUBLIC_KEY],
        ct_i: &[u8; kem::CIPHERTEXT_BYTES],
        secrets: [&[u8; 32]; 3],
    ) -> Result<Self, HandshakeError> {
        let suite_id = agreed(hello, answer)?;
        let transcript = transcript(
            suite_id,
            id_pk_i,
            id_pk_r,
            pk_s,
            &hello.kem_key,
            &answer.kem_key,
            &hello.static_ct,
            &answer.kem_ct,
            ct_i,
        );
        let [ss_s, ss_r, ss_i] = secrets;
        let master = master(ss_s, ss_r, ss_i, &transcript);
        Ok(Self { transcript, master })
    }

    pub fn transcript(&self) -> &[u8; 32] {
        &self.transcript
    }

    pub fn seal_initiator(
        &self,
        signature: &[u8; size::SIGNATURE],
    ) -> Result<[u8; SEALED_SIGNATURE], HandshakeError> {
        sealed_signature(initiator_seal(&self.master), signature)
    }

    pub fn seal_responder(
        &self,
        signature: &[u8; size::SIGNATURE],
    ) -> Result<[u8; SEALED_SIGNATURE], HandshakeError> {
        sealed_signature(responder_seal(&self.master), signature)
    }

    // The initiator carries a channel once the fourth flight opens and verifies under the key the
    // line named.
    pub fn initiator_channel(
        self,
        id_pk_r: &[u8; size::SIGNING_PUBLIC_KEY],
        confirm: &HelloConfirm,
    ) -> Result<Channel, HandshakeError> {
        let signature = open_with(responder_seal(&self.master), &confirm.sealed_signature)?;
        verify_responder(id_pk_r, &self.transcript, &signature)?;
        Ok(self.channel())
    }

    // The responder carries a channel once the third flight opens and verifies under the key the
    // first flight sealed.
    pub fn responder_channel(
        self,
        id_pk_i: &[u8; size::SIGNING_PUBLIC_KEY],
        finish: &HelloFinish,
    ) -> Result<Channel, HandshakeError> {
        let signature = open_with(initiator_seal(&self.master), &finish.sealed_signature)?;
        verify_initiator(id_pk_i, &self.transcript, &signature)?;
        Ok(self.channel())
    }

    fn channel(&self) -> Channel {
        Channel {
            transcript: self.transcript,
            initiator_to_responder: initiator_to_responder(&self.master),
            responder_to_initiator: responder_to_initiator(&self.master),
        }
    }
}

fn sealed_signature(
    key: [u8; 32],
    signature: &[u8; size::SIGNATURE],
) -> Result<[u8; SEALED_SIGNATURE], HandshakeError> {
    let sealed = seal_with(key, signature)?;
    let mut out = [0u8; SEALED_SIGNATURE];
    out.copy_from_slice(&sealed);
    Ok(out)
}

// A side that cannot verify the signature of the other over the transcript it computed carries
// nothing.
pub fn verify_initiator(
    answering_key: &[u8; size::SIGNING_PUBLIC_KEY],
    transcript: &[u8; 32],
    signature: &[u8; size::SIGNATURE],
) -> Result<(), HandshakeError> {
    sign::verify(
        &sign::PublicKey::from_bytes(*answering_key),
        &initiator_message(transcript),
        &sign::Signature::from_bytes(*signature),
    )
    .map_err(|_| HandshakeError::Unverified)
}

pub fn verify_responder(
    answering_key: &[u8; size::SIGNING_PUBLIC_KEY],
    transcript: &[u8; 32],
    signature: &[u8; size::SIGNATURE],
) -> Result<(), HandshakeError> {
    sign::verify(
        &sign::PublicKey::from_bytes(*answering_key),
        &responder_message(transcript),
        &sign::Signature::from_bytes(*signature),
    )
    .map_err(|_| HandshakeError::Unverified)
}

pub fn sign_initiator(
    secret: &sign::SecretKey,
    transcript: &[u8; 32],
) -> Result<[u8; size::SIGNATURE], HandshakeError> {
    sign::sign(secret, &initiator_message(transcript))
        .map(|s| *s.as_bytes())
        .map_err(|_| HandshakeError::Signing)
}

pub fn sign_responder(
    secret: &sign::SecretKey,
    transcript: &[u8; 32],
) -> Result<[u8; size::SIGNATURE], HandshakeError> {
    sign::sign(secret, &responder_message(transcript))
        .map(|s| *s.as_bytes())
        .map_err(|_| HandshakeError::Signing)
}

// The count of units a flight occupies on a link, by the framing of this wire.
pub fn units_of(flight: usize) -> Result<usize, WireError> {
    Ok(flight.div_ceil(crate::piece_bytes()?).max(1))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hex(bytes: &[u8]) -> String {
        bytes.iter().map(|b| format!("{b:02x}")).collect()
    }

    #[test]
    fn the_lengths_of_the_four_flights_are_the_ones_the_set_states() {
        assert_eq!(hello_len(), 4_242);
        assert_eq!(hello_answer_len(), 2_274);
        assert_eq!(hello_finish_len(), 4_413);
        assert_eq!(hello_confirm_len(), 3_325);
    }

    fn vector_transcript(suite_id: u16, id_i: u8, id_r: u8, swapped: bool) -> [u8; 32] {
        let (pk_i, pk_r, ct_r, ct_i) = if swapped { (3, 2, 6, 5) } else { (2, 3, 5, 6) };
        transcript(
            suite_id,
            &[id_i; size::SIGNING_PUBLIC_KEY],
            &[id_r; size::SIGNING_PUBLIC_KEY],
            &[0x01u8; size::KEM_PUBLIC_KEY],
            &[pk_i; size::KEM_PUBLIC_KEY],
            &[pk_r; size::KEM_PUBLIC_KEY],
            &[0x04u8; kem::CIPHERTEXT_BYTES],
            &[ct_r; kem::CIPHERTEXT_BYTES],
            &[ct_i; kem::CIPHERTEXT_BYTES],
        )
    }

    #[test]
    fn the_handshake_of_the_set_reproduces() {
        // Canon, "The post-quantum handshake, in integers": every value below is SHA-256 of the
        // domain, the NUL and the parts, recomputed outside this tree.
        let (ss_s, ss_r, ss_i) = ([0x07u8; 32], [0x08u8; 32], [0x09u8; 32]);
        assert_eq!(
            hex(&hello_key(
                &ss_s,
                1,
                &[0x01u8; size::KEM_PUBLIC_KEY],
                &[0x02u8; size::KEM_PUBLIC_KEY],
                &[0x04u8; kem::CIPHERTEXT_BYTES],
            )),
            "620860cfc1f2858310ce01592016abd8b5bac93e1ee2a3e351d8d2714b9b0f50"
        );
        let held = vector_transcript(1, 0x0A, 0x0B, false);
        assert_eq!(
            hex(&held),
            "c6a11287143bc6df3efe7183ee92eff918f303662dbac804cf415771bdd05970"
        );
        let master = master(&ss_s, &ss_r, &ss_i, &held);
        assert_eq!(
            hex(&master),
            "23a67d016c5565287e67f7a0889780a1528bdd52cb9c861fa8d9cefe12939217"
        );
        assert_eq!(
            hex(&initiator_to_responder(&master)),
            "96099cfb93a13dd963f8685913cb700342c5c9a9d651f84f61215ed71d026c44"
        );
        assert_eq!(
            hex(&responder_to_initiator(&master)),
            "429df34deb7edf6ad11a68858bfdaabc90779f6d349de2b44db0aeccfefbe352"
        );
        assert_eq!(
            hex(&initiator_seal(&master)),
            "17df587c80fd72b2c7dacc4f952d12361834e8e493d17b7bdd5eccb1358e54fc"
        );
        assert_eq!(
            hex(&responder_seal(&master)),
            "d0136b9d143e3918fd5ee26a69fb00da4eb358ee508981bfbdd904ec5f1852f4"
        );
        // The named wrong implementations, each reproducing none of them: the order of folding
        // taken from arrival rather than from role; the suite left outside; either answering key
        // left outside, which is the value that decides whom a channel belongs to; and the secret
        // of the static encapsulation left out of the master.
        assert_ne!(vector_transcript(1, 0x0B, 0x0A, true), held);
        assert_ne!(vector_transcript(2, 0x0A, 0x0B, false), held);
        assert_ne!(vector_transcript(1, 0x0C, 0x0B, false), held);
        assert_ne!(vector_transcript(1, 0x0A, 0x0C, false), held);
        assert_ne!(super::master(&[0u8; 32], &ss_r, &ss_i, &held), master);
    }

    #[test]
    fn each_flight_round_trips_and_a_flight_of_another_length_is_refused() {
        let hello = Hello {
            suite_id: 1,
            kem_key: [0x01; size::KEM_PUBLIC_KEY],
            static_ct: [0x02; kem::CIPHERTEXT_BYTES],
            sealed_key: [0xA1; SEALED_KEY],
        };
        let bytes = hello.encode();
        assert_eq!(bytes.len(), hello_len());
        assert_eq!(Hello::parse(&bytes), Ok(hello));
        assert!(Hello::parse(&bytes[..bytes.len() - 1]).is_err());

        let answer = HelloAnswer {
            suite_id: 1,
            kem_key: [0x02; size::KEM_PUBLIC_KEY],
            kem_ct: [0x03; kem::CIPHERTEXT_BYTES],
        };
        let bytes = answer.encode();
        assert_eq!(bytes.len(), hello_answer_len());
        assert_eq!(HelloAnswer::parse(&bytes), Ok(answer));

        let finish = HelloFinish {
            kem_ct: [0x04; kem::CIPHERTEXT_BYTES],
            sealed_signature: [0x5E; SEALED_SIGNATURE],
        };
        let bytes = finish.encode();
        assert_eq!(bytes.len(), hello_finish_len());
        assert_eq!(HelloFinish::parse(&bytes), Ok(finish));

        let confirm = HelloConfirm {
            sealed_signature: [0x5F; SEALED_SIGNATURE],
        };
        let bytes = confirm.encode();
        assert_eq!(bytes.len(), hello_confirm_len());
        assert_eq!(HelloConfirm::parse(&bytes), Ok(confirm));
    }

    #[test]
    fn the_two_signatures_take_two_domains_and_neither_replays_as_the_other() {
        let (public, secret) = sign::keypair_from_seed(&[0x11u8; sign::SEED_BYTES]);
        let transcript = [0x22u8; 32];
        let by_initiator = sign_initiator(&secret, &transcript).expect("signs");
        let by_responder = sign_responder(&secret, &transcript).expect("signs");
        assert_ne!(by_initiator, by_responder);
        assert_eq!(
            verify_initiator(public.as_bytes(), &transcript, &by_initiator),
            Ok(())
        );
        assert_eq!(
            verify_responder(public.as_bytes(), &transcript, &by_responder),
            Ok(())
        );
        assert_eq!(
            verify_initiator(public.as_bytes(), &transcript, &by_responder),
            Err(HandshakeError::Unverified)
        );
        assert_eq!(
            verify_responder(public.as_bytes(), &transcript, &by_initiator),
            Err(HandshakeError::Unverified)
        );
        let moved = [0x23u8; 32];
        assert_eq!(
            verify_initiator(public.as_bytes(), &moved, &by_initiator),
            Err(HandshakeError::Unverified)
        );
    }

    // Two machines, each answering under its own key; the responder's static encapsulation pair is
    // what the line hands the initiator beside that key.
    struct Side {
        id: sign::PublicKey,
        secret: sign::SecretKey,
    }

    fn side(seed: u8) -> Side {
        let (id, secret) = sign::keypair_from_seed(&[seed; sign::SEED_BYTES]);
        Side { id, secret }
    }

    struct Run {
        hello: Hello,
        answer: HelloAnswer,
        ct_i: [u8; kem::CIPHERTEXT_BYTES],
        of_initiator: Keys,
        of_responder: Keys,
    }

    // The four flights as the set orders them, up to the two signatures, for an initiator holding
    // `line` as the responder's static key.
    fn run(
        i: &Side,
        r: &Side,
        statics: &kem::SecretKey,
        line: &kem::PublicKey,
    ) -> Result<Run, HandshakeError> {
        let (pk_i, sk_i) = kem::keypair_from_seed(&[0x41u8; kem::SEED_BYTES]);
        let (ct_s, ss_s) = kem::encapsulate(line).expect("draws");
        let k_hello = hello_key(
            ss_s.as_bytes(),
            1,
            line.as_bytes(),
            pk_i.as_bytes(),
            ct_s.as_bytes(),
        );
        let hello = Hello {
            suite_id: 1,
            kem_key: *pk_i.as_bytes(),
            static_ct: *ct_s.as_bytes(),
            sealed_key: seal_key(k_hello, i.id.as_bytes())?,
        };

        // The responder: the first flight opens, or nothing is answered.
        let held_s = kem::decapsulate(statics, &kem::Ciphertext::from_bytes(hello.static_ct));
        let own_line = kem::keypair_from_seed(&[0x40u8; kem::SEED_BYTES]).0;
        let opened = open_key(
            hello_key(
                held_s.as_bytes(),
                hello.suite_id,
                own_line.as_bytes(),
                &hello.kem_key,
                &hello.static_ct,
            ),
            &hello.sealed_key,
        )?;
        let (pk_r, sk_r) = kem::keypair_from_seed(&[0x42u8; kem::SEED_BYTES]);
        let (ct_r, ss_r) =
            kem::encapsulate(&kem::PublicKey::from_bytes(hello.kem_key)).expect("draws");
        let answer = HelloAnswer {
            suite_id: 1,
            kem_key: *pk_r.as_bytes(),
            kem_ct: *ct_r.as_bytes(),
        };

        // The initiator.
        let held_r = kem::decapsulate(&sk_i, &kem::Ciphertext::from_bytes(answer.kem_ct));
        let (ct_i, ss_i) = kem::encapsulate(&pk_r).expect("draws");
        let of_initiator = Keys::of(
            &hello,
            &answer,
            i.id.as_bytes(),
            r.id.as_bytes(),
            line.as_bytes(),
            ct_i.as_bytes(),
            [ss_s.as_bytes(), held_r.as_bytes(), ss_i.as_bytes()],
        )?;

        // The responder again, once the third flight's encapsulation is held.
        let held_i = kem::decapsulate(&sk_r, &ct_i);
        let of_responder = Keys::of(
            &hello,
            &answer,
            &opened,
            r.id.as_bytes(),
            own_line.as_bytes(),
            ct_i.as_bytes(),
            [held_s.as_bytes(), ss_r.as_bytes(), held_i.as_bytes()],
        )?;
        Ok(Run {
            hello,
            answer,
            ct_i: *ct_i.as_bytes(),
            of_initiator,
            of_responder,
        })
    }

    #[test]
    fn a_channel_exists_only_on_the_far_side_of_a_verification() {
        let (i, r) = (side(0x31), side(0x32));
        let (line, statics) = kem::keypair_from_seed(&[0x40u8; kem::SEED_BYTES]);
        let again = || run(&i, &r, &statics, &line).expect("opens");
        let Run {
            ct_i,
            of_initiator,
            of_responder,
            ..
        } = again();
        assert_eq!(of_initiator.transcript(), of_responder.transcript());

        let by_i = sign_initiator(&i.secret, of_initiator.transcript()).expect("signs");
        let finish = HelloFinish {
            kem_ct: ct_i,
            sealed_signature: of_initiator.seal_initiator(&by_i).expect("seals"),
        };
        let by_r = sign_responder(&r.secret, of_responder.transcript()).expect("signs");
        let confirm = HelloConfirm {
            sealed_signature: of_responder.seal_responder(&by_r).expect("seals"),
        };
        // Neither signature crosses in the open: the bytes on the wire are not the signature.
        assert_ne!(&finish.sealed_signature[..size::SIGNATURE], &by_i[..]);
        assert_ne!(&confirm.sealed_signature[..size::SIGNATURE], &by_r[..]);

        let of_responder = of_responder
            .responder_channel(i.id.as_bytes(), &finish)
            .expect("verified");
        let of_initiator = of_initiator
            .initiator_channel(r.id.as_bytes(), &confirm)
            .expect("verified");
        // Two sides reached one channel: what is compared is the transcript and both keys read
        // through their own doors, since a channel compares nothing of itself.
        assert_eq!(of_initiator.transcript(), of_responder.transcript());
        assert_eq!(
            of_initiator.initiator_to_responder(),
            of_responder.initiator_to_responder()
        );
        assert_eq!(
            of_initiator.responder_to_initiator(),
            of_responder.responder_to_initiator()
        );

        // A confirm signed over another transcript leaves the initiator with nothing.
        let Run {
            of_initiator,
            of_responder,
            ..
        } = again();
        let wrong = HelloConfirm {
            sealed_signature: of_responder
                .seal_responder(&sign_responder(&r.secret, &[0x77u8; 32]).expect("signs"))
                .expect("seals"),
        };
        assert_eq!(
            of_initiator
                .initiator_channel(r.id.as_bytes(), &wrong)
                .err(),
            Some(HandshakeError::Unverified)
        );
        // A signature sealed under the other direction's key does not open.
        let Run {
            of_initiator,
            of_responder,
            ..
        } = again();
        let crossed = HelloConfirm {
            sealed_signature: of_responder
                .seal_initiator(
                    &sign_responder(&r.secret, of_responder.transcript()).expect("signs"),
                )
                .expect("seals"),
        };
        assert_eq!(
            of_initiator
                .initiator_channel(r.id.as_bytes(), &crossed)
                .err(),
            Some(HandshakeError::Unopened)
        );
        // A finish signed by a key that is not the one the first flight sealed leaves the responder
        // with nothing.
        let Run {
            ct_i,
            of_initiator,
            of_responder,
            ..
        } = again();
        let impostor = HelloFinish {
            kem_ct: ct_i,
            sealed_signature: of_initiator
                .seal_initiator(
                    &sign_initiator(&r.secret, of_initiator.transcript()).expect("signs"),
                )
                .expect("seals"),
        };
        assert_eq!(
            of_responder
                .responder_channel(i.id.as_bytes(), &impostor)
                .err(),
            Some(HandshakeError::Unverified)
        );
        // A responder that reads another answering key out of the first flight computes another
        // transcript and so another master, and the finish sealed under the initiator's opens to
        // nothing under it: the key that decides whom a channel belongs to is inside every secret.
        let e = side(0x33);
        let Run {
            hello,
            answer,
            ct_i,
            of_initiator,
            ..
        } = again();
        let finish = HelloFinish {
            kem_ct: ct_i,
            sealed_signature: of_initiator
                .seal_initiator(
                    &sign_initiator(&i.secret, of_initiator.transcript()).expect("signs"),
                )
                .expect("seals"),
        };
        let fixed = [[0x07u8; 32], [0x08u8; 32], [0x09u8; 32]];
        let secrets = [&fixed[0], &fixed[1], &fixed[2]];
        let as_e = Keys::of(
            &hello,
            &answer,
            e.id.as_bytes(),
            r.id.as_bytes(),
            line.as_bytes(),
            &ct_i,
            secrets,
        )
        .expect("derives");
        assert_eq!(
            as_e.responder_channel(e.id.as_bytes(), &finish).err(),
            Some(HandshakeError::Unopened)
        );
        // And two flights naming two suites are refused before a key is derived from either.
        let mismatched = Hello {
            suite_id: 2,
            ..hello.clone()
        };
        assert!(matches!(
            Keys::of(
                &mismatched,
                &answer,
                i.id.as_bytes(),
                r.id.as_bytes(),
                line.as_bytes(),
                &ct_i,
                secrets
            ),
            Err(HandshakeError::SuiteMismatch { .. })
        ));
    }

    // **The door says nothing to a stranger.** A side that was not handed the line encapsulates to a
    // static key that is not the responder's; ML-KEM still hands the responder a secret, and the
    // sealed key opens to nothing under it, which is where the responder stops without a byte.
    #[test]
    fn a_first_flight_from_a_side_without_the_line_does_not_open() {
        let (i, r) = (side(0x31), side(0x32));
        let (_, statics) = kem::keypair_from_seed(&[0x40u8; kem::SEED_BYTES]);
        let (elsewhere, _) = kem::keypair_from_seed(&[0x4Fu8; kem::SEED_BYTES]);
        assert_eq!(
            run(&i, &r, &statics, &elsewhere).err(),
            Some(HandshakeError::Unopened)
        );
    }

    // The fold of a renewal, recomputed here from its definition (Network, "How a link renews its
    // keys"): the domain, the NUL, the previous secret, both shared secrets and the four public
    // values in the order of the roles. The named wrong folds answer elsewhere: the order of the
    // renewal (the responder offered and its values went first), one side's material alone, and the
    // previous secret left out.
    #[test]
    fn a_renewal_folds_both_encapsulations_in_the_order_of_the_roles() {
        use sha2::Digest as _;
        let previous = [0x51u8; 32];
        let (ss_i, ss_r) = ([0x52u8; 32], [0x53u8; 32]);
        let (pk_i, pk_r) = (
            [0x54u8; size::KEM_PUBLIC_KEY],
            [0x55u8; size::KEM_PUBLIC_KEY],
        );
        let (ct_i, ct_r) = (
            [0x56u8; kem::CIPHERTEXT_BYTES],
            [0x57u8; kem::CIPHERTEXT_BYTES],
        );
        let next = renewed(&previous, &ss_i, &ss_r, &pk_i, &pk_r, &ct_i, &ct_r);
        let mut by_hand = sha2::Sha256::new();
        by_hand.update(b"mt-link-renew");
        by_hand.update([0x00]);
        for part in [&previous[..], &ss_i, &ss_r, &pk_i, &pk_r, &ct_i, &ct_r] {
            by_hand.update(part);
        }
        assert_eq!(next, <[u8; 32]>::from(by_hand.finalize()));
        let of_the_renewal = renewed(&previous, &ss_r, &ss_i, &pk_r, &pk_i, &ct_r, &ct_i);
        assert_ne!(next, of_the_renewal);
        let one_side = renewed(&previous, &ss_i, &ss_i, &pk_i, &pk_i, &ct_i, &ct_i);
        assert_ne!(next, one_side);
        let without_the_past = renewed(&[0u8; 32], &ss_i, &ss_r, &pk_i, &pk_r, &ct_i, &ct_r);
        assert_ne!(next, without_the_past);
        // The keys walk with the secret, and a link that never renewed keeps those of its master.
        assert_ne!(
            initiator_to_responder(&next),
            initiator_to_responder(&previous)
        );
        assert_ne!(
            responder_to_initiator(&next),
            responder_to_initiator(&previous)
        );
        assert_ne!(initiator_to_responder(&next), responder_to_initiator(&next));
    }

    #[test]
    fn a_flight_naming_a_suite_the_table_does_not_hold_is_refused() {
        let mut bytes = Hello {
            suite_id: 1,
            kem_key: [0x01; size::KEM_PUBLIC_KEY],
            static_ct: [0x02; kem::CIPHERTEXT_BYTES],
            sealed_key: [0xA1; SEALED_KEY],
        }
        .encode();
        bytes[..2].copy_from_slice(&7u16.to_le_bytes());
        assert_eq!(
            Hello::parse(&bytes),
            Err(HandshakeError::UnknownSuite { suite_id: 7 })
        );
    }
}
