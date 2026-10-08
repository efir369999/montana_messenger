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
use mt_suite::{kem, sign};
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

// Flight one, from the initiator.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct Hello {
    pub suite_id: u16,
    pub kem_key: [u8; size::KEM_PUBLIC_KEY],
    pub answering_key: [u8; size::SIGNING_PUBLIC_KEY],
}

pub fn hello_len() -> usize {
    2 + size::KEM_PUBLIC_KEY + size::SIGNING_PUBLIC_KEY
}

impl Hello {
    pub fn encode(&self) -> Vec<u8> {
        let mut out = Vec::with_capacity(hello_len());
        out.extend_from_slice(&self.suite_id.to_le_bytes());
        out.extend_from_slice(&self.kem_key);
        out.extend_from_slice(&self.answering_key);
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
            answering_key: fixed(bytes, at),
        })
    }
}

// Flight two, from the responder.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct HelloAnswer {
    pub suite_id: u16,
    pub kem_key: [u8; size::KEM_PUBLIC_KEY],
    pub kem_ct: [u8; kem::CIPHERTEXT_BYTES],
    pub answering_key: [u8; size::SIGNING_PUBLIC_KEY],
}

pub fn hello_answer_len() -> usize {
    2 + size::KEM_PUBLIC_KEY + kem::CIPHERTEXT_BYTES + size::SIGNING_PUBLIC_KEY
}

impl HelloAnswer {
    pub fn encode(&self) -> Vec<u8> {
        let mut out = Vec::with_capacity(hello_answer_len());
        out.extend_from_slice(&self.suite_id.to_le_bytes());
        out.extend_from_slice(&self.kem_key);
        out.extend_from_slice(&self.kem_ct);
        out.extend_from_slice(&self.answering_key);
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
            answering_key: fixed(bytes, at),
        })
    }
}

// Flight three, from the initiator, who now holds all four values of the transcript.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct HelloFinish {
    pub kem_ct: [u8; kem::CIPHERTEXT_BYTES],
    pub signature: [u8; size::SIGNATURE],
}

pub fn hello_finish_len() -> usize {
    kem::CIPHERTEXT_BYTES + size::SIGNATURE
}

impl HelloFinish {
    pub fn encode(&self) -> Vec<u8> {
        let mut out = Vec::with_capacity(hello_finish_len());
        out.extend_from_slice(&self.kem_ct);
        out.extend_from_slice(&self.signature);
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
            signature: fixed(bytes, at),
        })
    }
}

// Flight four, from the responder.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct HelloConfirm {
    pub signature: [u8; size::SIGNATURE],
}

pub fn hello_confirm_len() -> usize {
    size::SIGNATURE
}

impl HelloConfirm {
    pub fn encode(&self) -> Vec<u8> {
        self.signature.to_vec()
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
            signature: fixed(bytes, at),
        })
    }
}

// The order of folding is fixed by role and not by arrival, so both sides compute one master from
// one exchange. What enters is everything the two sides named: the suite, the answering key of
// each and the four values of the encapsulation.
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
    pk_i: &[u8; size::KEM_PUBLIC_KEY],
    pk_r: &[u8; size::KEM_PUBLIC_KEY],
    ct_i: &[u8; kem::CIPHERTEXT_BYTES],
    ct_r: &[u8; kem::CIPHERTEXT_BYTES],
) -> [u8; 32] {
    hash(
        domain::MT_NOISE_PQ_V1_TRANSCRIPT,
        &[
            Part::of(&suite_id.to_le_bytes()),
            Part::of(id_pk_i),
            Part::of(id_pk_r),
            Part::of(pk_i),
            Part::of(pk_r),
            Part::of(ct_i),
            Part::of(ct_r),
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

pub fn master(ss_i: &[u8; 32], ss_r: &[u8; 32], transcript: &[u8; 32]) -> [u8; 32] {
    hash(
        domain::MT_NOISE_PQ_V1_MASTER,
        &[Part::of(ss_i), Part::of(ss_r), Part::of(transcript)],
    )
}

pub fn initiator_to_responder(master: &[u8; 32]) -> [u8; 32] {
    hash(domain::MT_NOISE_PQ_V1_I2R, &[Part::of(master)])
}

pub fn responder_to_initiator(master: &[u8; 32]) -> [u8; 32] {
    hash(domain::MT_NOISE_PQ_V1_R2I, &[Part::of(master)])
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

fn of_transcript(transcript: [u8; 32], ss_i: &[u8; 32], ss_r: &[u8; 32]) -> Channel {
    let master = master(ss_i, ss_r, &transcript);
    Channel {
        transcript,
        initiator_to_responder: initiator_to_responder(&master),
        responder_to_initiator: responder_to_initiator(&master),
    }
}

// The initiator carries a channel once the fourth flight has verified: it computes the transcript
// from the four values it holds and reads the responder's signature over it.
pub fn initiator_channel(
    hello: &Hello,
    answer: &HelloAnswer,
    ct_i: &[u8; kem::CIPHERTEXT_BYTES],
    ss_i: &[u8; 32],
    ss_r: &[u8; 32],
    confirm: &HelloConfirm,
) -> Result<Channel, HandshakeError> {
    let suite_id = agreed(hello, answer)?;
    let transcript = transcript(
        suite_id,
        &hello.answering_key,
        &answer.answering_key,
        &hello.kem_key,
        &answer.kem_key,
        ct_i,
        &answer.kem_ct,
    );
    verify_responder(&answer.answering_key, &transcript, &confirm.signature)?;
    Ok(of_transcript(transcript, ss_i, ss_r))
}

// The responder carries a channel once the third flight has verified.
pub fn responder_channel(
    hello: &Hello,
    answer: &HelloAnswer,
    finish: &HelloFinish,
    ss_i: &[u8; 32],
    ss_r: &[u8; 32],
) -> Result<Channel, HandshakeError> {
    let suite_id = agreed(hello, answer)?;
    let transcript = transcript(
        suite_id,
        &hello.answering_key,
        &answer.answering_key,
        &hello.kem_key,
        &answer.kem_key,
        &finish.kem_ct,
        &answer.kem_ct,
    );
    verify_initiator(&hello.answering_key, &transcript, &finish.signature)?;
    Ok(of_transcript(transcript, ss_i, ss_r))
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
        assert_eq!(hello_len(), 3_138);
        assert_eq!(hello_answer_len(), 4_226);
        assert_eq!(hello_finish_len(), 4_397);
        assert_eq!(hello_confirm_len(), 3_309);
    }

    fn vector_transcript() -> [u8; 32] {
        transcript(
            1,
            &[0x0Au8; size::SIGNING_PUBLIC_KEY],
            &[0x0Bu8; size::SIGNING_PUBLIC_KEY],
            &[0x01u8; size::KEM_PUBLIC_KEY],
            &[0x02u8; size::KEM_PUBLIC_KEY],
            &[0x03u8; kem::CIPHERTEXT_BYTES],
            &[0x04u8; kem::CIPHERTEXT_BYTES],
        )
    }

    #[test]
    fn the_handshake_of_the_set_reproduces() {
        // Canon, "The post-quantum handshake".
        let ss_i = [0x05u8; 32];
        let ss_r = [0x06u8; 32];
        let held = vector_transcript();
        assert_eq!(
            hex(&held),
            "ed9ca2f7898c073ed4d62159b3219c9b3e1bdb9f4527c7564ee77d611338bbf2"
        );
        let master = master(&ss_i, &ss_r, &held);
        assert_eq!(
            hex(&master),
            "0e0518c8ad43bd274b49c8c98d2c8321dad8adde9bb7a065f5f6c10bd2ca50ef"
        );
        assert_eq!(
            hex(&initiator_to_responder(&master)),
            "271ff1e9b997151f5925fa83e8b846c0c503ae8222d07b8d3b31acc62a5296c2"
        );
        assert_eq!(
            hex(&responder_to_initiator(&master)),
            "08a031d18e42a5793274dcf0943bfe9df730d7c8acf118f7d77ae8e1ea9845aa"
        );
        // The named wrong implementations, each reproducing none of the four: the order of folding
        // taken from arrival rather than from role; the suite left outside; and either answering
        // key left outside, which is the value that decides whom a channel belongs to.
        assert_ne!(
            transcript(
                1,
                &[0x0Bu8; size::SIGNING_PUBLIC_KEY],
                &[0x0Au8; size::SIGNING_PUBLIC_KEY],
                &[0x02u8; size::KEM_PUBLIC_KEY],
                &[0x01u8; size::KEM_PUBLIC_KEY],
                &[0x04u8; kem::CIPHERTEXT_BYTES],
                &[0x03u8; kem::CIPHERTEXT_BYTES],
            ),
            held
        );
        assert_ne!(
            transcript(
                2,
                &[0x0Au8; size::SIGNING_PUBLIC_KEY],
                &[0x0Bu8; size::SIGNING_PUBLIC_KEY],
                &[0x01u8; size::KEM_PUBLIC_KEY],
                &[0x02u8; size::KEM_PUBLIC_KEY],
                &[0x03u8; kem::CIPHERTEXT_BYTES],
                &[0x04u8; kem::CIPHERTEXT_BYTES],
            ),
            held
        );
        assert_ne!(
            transcript(
                1,
                &[0x0Cu8; size::SIGNING_PUBLIC_KEY],
                &[0x0Bu8; size::SIGNING_PUBLIC_KEY],
                &[0x01u8; size::KEM_PUBLIC_KEY],
                &[0x02u8; size::KEM_PUBLIC_KEY],
                &[0x03u8; kem::CIPHERTEXT_BYTES],
                &[0x04u8; kem::CIPHERTEXT_BYTES],
            ),
            held
        );
    }

    #[test]
    fn each_flight_round_trips_and_a_flight_of_another_length_is_refused() {
        let hello = Hello {
            suite_id: 1,
            kem_key: [0x01; size::KEM_PUBLIC_KEY],
            answering_key: [0xA1; size::SIGNING_PUBLIC_KEY],
        };
        let bytes = hello.encode();
        assert_eq!(bytes.len(), hello_len());
        assert_eq!(Hello::parse(&bytes), Ok(hello));
        assert!(Hello::parse(&bytes[..bytes.len() - 1]).is_err());

        let answer = HelloAnswer {
            suite_id: 1,
            kem_key: [0x02; size::KEM_PUBLIC_KEY],
            kem_ct: [0x03; kem::CIPHERTEXT_BYTES],
            answering_key: [0xA2; size::SIGNING_PUBLIC_KEY],
        };
        let bytes = answer.encode();
        assert_eq!(bytes.len(), hello_answer_len());
        assert_eq!(HelloAnswer::parse(&bytes), Ok(answer));

        let finish = HelloFinish {
            kem_ct: [0x04; kem::CIPHERTEXT_BYTES],
            signature: [0x5E; size::SIGNATURE],
        };
        let bytes = finish.encode();
        assert_eq!(bytes.len(), hello_finish_len());
        assert_eq!(HelloFinish::parse(&bytes), Ok(finish));

        let confirm = HelloConfirm {
            signature: [0x5F; size::SIGNATURE],
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

    #[test]
    fn a_channel_exists_only_on_the_far_side_of_a_verification() {
        // The four flights, run as the set orders them, with two devices answering under their own
        // keys. What the doors below refuse is the whole point: a side that cannot verify the other
        // carries nothing, and there is no other way to reach the keys of a channel.
        let (pk_of_i, sk_of_i) = sign::keypair_from_seed(&[0x31u8; sign::SEED_BYTES]);
        let (pk_of_r, sk_of_r) = sign::keypair_from_seed(&[0x32u8; sign::SEED_BYTES]);
        let hello = Hello {
            suite_id: 1,
            kem_key: [0x01; size::KEM_PUBLIC_KEY],
            answering_key: *pk_of_i.as_bytes(),
        };
        let answer = HelloAnswer {
            suite_id: 1,
            kem_key: [0x02; size::KEM_PUBLIC_KEY],
            kem_ct: [0x04; kem::CIPHERTEXT_BYTES],
            answering_key: *pk_of_r.as_bytes(),
        };
        let ct_i = [0x03u8; kem::CIPHERTEXT_BYTES];
        let ss_i = [0x05u8; 32];
        let ss_r = [0x06u8; 32];
        let shared = transcript(
            hello.suite_id,
            &hello.answering_key,
            &answer.answering_key,
            &hello.kem_key,
            &answer.kem_key,
            &ct_i,
            &answer.kem_ct,
        );
        let finish = HelloFinish {
            kem_ct: ct_i,
            signature: sign_initiator(&sk_of_i, &shared).expect("signs"),
        };
        let confirm = HelloConfirm {
            signature: sign_responder(&sk_of_r, &shared).expect("signs"),
        };

        let of_initiator =
            initiator_channel(&hello, &answer, &ct_i, &ss_i, &ss_r, &confirm).expect("verified");
        let of_responder =
            responder_channel(&hello, &answer, &finish, &ss_i, &ss_r).expect("verified");
        // Two sides reached one channel: what is compared is the transcript and both keys read
        // through their own doors, since a channel compares nothing of itself — a comparison of
        // key material would run in a time that depends on where the first difference stands.
        assert_eq!(of_initiator.transcript(), of_responder.transcript());
        assert_eq!(
            of_initiator.initiator_to_responder(),
            of_responder.initiator_to_responder()
        );
        assert_eq!(
            of_initiator.responder_to_initiator(),
            of_responder.responder_to_initiator()
        );
        assert_eq!(of_initiator.transcript(), &shared);

        // A confirm signed over another transcript leaves the initiator with nothing.
        let elsewhere = [0x77u8; 32];
        let wrong = HelloConfirm {
            signature: sign_responder(&sk_of_r, &elsewhere).expect("signs"),
        };
        assert_eq!(
            initiator_channel(&hello, &answer, &ct_i, &ss_i, &ss_r, &wrong).err(),
            Some(HandshakeError::Unverified)
        );
        // And a finish signed by a key that is not the one the hello named leaves the responder
        // with nothing.
        let impostor = HelloFinish {
            kem_ct: ct_i,
            signature: sign_initiator(&sk_of_r, &shared).expect("signs"),
        };
        assert_eq!(
            responder_channel(&hello, &answer, &impostor, &ss_i, &ss_r).err(),
            Some(HandshakeError::Unverified)
        );
        // A third party that relays the encapsulation untouched and puts its own answering key in
        // the first flight reaches nothing: the transcript covers that key, so the signature the
        // initiator made over its own transcript verifies under no other name.
        let (pk_of_e, sk_of_e) = sign::keypair_from_seed(&[0x33u8; sign::SEED_BYTES]);
        let relayed = Hello {
            answering_key: *pk_of_e.as_bytes(),
            ..hello.clone()
        };
        let by_e = HelloFinish {
            kem_ct: ct_i,
            signature: sign_initiator(&sk_of_e, &shared).expect("signs"),
        };
        assert_eq!(
            responder_channel(&relayed, &answer, &by_e, &ss_i, &ss_r).err(),
            Some(HandshakeError::Unverified)
        );
        // And two flights naming two suites are refused before a key is derived from either.
        let elsewhere = HelloAnswer {
            suite_id: 1,
            ..answer.clone()
        };
        let mismatched = Hello {
            suite_id: 2,
            ..hello.clone()
        };
        assert!(matches!(
            responder_channel(&mismatched, &elsewhere, &finish, &ss_i, &ss_r),
            Err(HandshakeError::SuiteMismatch { .. })
        ));
    }

    #[test]
    fn a_flight_naming_a_suite_the_table_does_not_hold_is_refused() {
        let mut bytes = Hello {
            suite_id: 1,
            kem_key: [0x01; size::KEM_PUBLIC_KEY],
            answering_key: [0xA1; size::SIGNING_PUBLIC_KEY],
        }
        .encode();
        bytes[..2].copy_from_slice(&7u16.to_le_bytes());
        assert_eq!(
            Hello::parse(&bytes),
            Err(HandshakeError::UnknownSuite { suite_id: 7 })
        );
    }
}
