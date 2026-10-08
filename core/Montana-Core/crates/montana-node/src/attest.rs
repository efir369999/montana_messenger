// What a machine does inside a window: draws its eligibility, answers a round, and gathers what
// answers arrive into the cement its successor closes on.
//
// **The first attestation of a window is heavy and every later one is light.** The heavy one
// carries the proof of presence — that the nullifier of this machine's part comes of the secret of
// a machine whose naming half stands in the tree of admitted machines, and that the key signing the
// attestation is the one that proof was made for — and the freshly blinded standing that enters the
// cement. A light one is the same object without the proof and without the standing, valid because
// the key it signs under already stood proven in the heavy every verifier holds.
//
// **Nothing here decides anything a rule does not.** Eligibility is the draw of `mt-derive`, the
// proof is the description of `mt-proof`, the cement and the close are of `mt-pulse`, the objects
// are the layouts of `mt-state`. What this file holds is the order.

use crate::NodeError;
use mt_state::layout::{Confirmation, LightAttestation};
use mt_state::Layout;
use zeroize::Zeroizing;

// What a machine holds of itself for one window: the nullifier of its part, the one-time key it
// answers under, and the proof of presence that binds the two. All three are functions of the
// secret and the window, so a machine that restarts inside a window rebuilds exactly what it had.
pub struct Standing {
    pub window: u64,
    pub part_nullifier: [u8; 32],
    pub key: mt_suite::sign::PublicKey,
    secret_of_the_key: mt_suite::sign::SecretKey,
    pub presence: Vec<u8>,
    pub commitment: Vec<u8>,
}

impl Standing {
    // What a machine draws once per window. The proof is made here and not at every round: it binds
    // the window and not the round, so one presence serves the window it belongs to.
    pub fn of_the_window(
        machine_secret: &[u8; 32],
        window: u64,
        admitted_siblings: &[mt_proof::poseidon::Digest],
        admitted_position: u64,
        standing: u64,
    ) -> Result<Self, NodeError> {
        let part_nullifier =
            mt_derive::nullifier::part(machine_secret, window).ok_or(NodeError::Unprovable {
                what: "the halves of this machine's secret",
            })?;

        // The one-time key of the part domain for this window, derived as the set states.
        let seed = mt_derive::pulse::part_key_seed(machine_secret, window);
        let mut held = Zeroizing::new([0u8; mt_suite::sign::SEED_BYTES]);
        held.copy_from_slice(&seed[..mt_suite::sign::SEED_BYTES]);
        let (key, secret_of_the_key) = mt_suite::sign::keypair_from_seed(&held);

        // The proof of presence: what the network verifies before it lets this machine's standing
        // enter a cement.
        let (trace, digests) = mt_proof::circuit::presence::trace_of(
            machine_secret,
            admitted_siblings,
            admitted_position,
            window,
            key.as_bytes(),
        )
        .ok_or(NodeError::Unprovable {
            what: "the presence of this machine in this window",
        })?;
        let public = mt_proof::circuit::presence::public_of(&digests);
        let description =
            mt_proof::circuit::presence::description().ok_or(NodeError::Unprovable {
                what: "the description of a presence",
            })?;
        let presence = mt_proof::scheme::prove(&description, &public, &trace).map_err(|_| {
            NodeError::Unprovable {
                what: "a proof of this machine's presence",
            }
        })?;

        // The standing this machine answers with, blinded afresh for this window: two machines of
        // equal standing present two commitments, and one machine presents two across two windows.
        let blind = mt_derive::nullifier::part(machine_secret, window.wrapping_add(1)).ok_or(
            NodeError::Unprovable {
                what: "the blinding factor of a window",
            },
        )?;
        let commitment = mt_suite::standing::weight_commit(
            standing,
            0,
            window,
            mt_suite::standing::Blind::of(blind, window),
        )
        .map_err(|_| NodeError::Unprovable {
            what: "the commitment of this machine's standing",
        })?
        .serialize();

        Ok(Self {
            window,
            part_nullifier,
            key,
            secret_of_the_key,
            presence,
            commitment,
        })
    }

    // Whether this machine may attest this round. Nothing of it is anyone's to choose: the
    // nullifier is fixed by the secret and the window, and the aggregate was cemented before the
    // window opened.
    pub fn eligible(
        &self,
        aggregate: &[u8; 32],
        chain: u8,
        round: u32,
        threshold: &mt_pulse::U256,
    ) -> bool {
        crate::round::eligible(&self.part_nullifier, aggregate, chain, round, threshold)
    }

    // The heavy attestation of a window: the proof, the standing, and the two identifiers it
    // attests in the canonical order the layout demands.
    pub fn heavy(
        &self,
        machine_secret: &[u8; 32],
        beacon_id: [u8; 32],
        previous_proposal: [u8; 32],
    ) -> Result<Confirmation, NodeError> {
        let attested = ascending(beacon_id, previous_proposal);
        let held = Confirmation {
            window: self.window,
            attested,
            part_nullifier: self.part_nullifier,
            round_nullifier: mt_derive::nullifier::round(machine_secret, &beacon_id),
            weight_commit: self.commitment.clone(),
            suite_id: mt_net::SUITE,
            answering_key: self.key.as_bytes().to_vec(),
            proof: self.presence.clone(),
            signature: vec![0u8; mt_codec::size::SIGNATURE],
        };
        self.signed(held)
    }

    // Every later attestation of the same window: the same object without the proof and without the
    // standing, valid because its key already stood proven in the heavy.
    pub fn light(
        &self,
        machine_secret: &[u8; 32],
        beacon_id: [u8; 32],
        previous_proposal: [u8; 32],
    ) -> Result<LightAttestation, NodeError> {
        let attested = ascending(beacon_id, previous_proposal);
        let held = LightAttestation {
            window: self.window,
            attested,
            part_nullifier: self.part_nullifier,
            round_nullifier: mt_derive::nullifier::round(machine_secret, &beacon_id),
            suite_id: mt_net::SUITE,
            answering_key: self.key.as_bytes().to_vec(),
            signature: vec![0u8; mt_codec::size::SIGNATURE],
        };
        self.signed_light(held)
    }

    fn signed(&self, mut held: Confirmation) -> Result<Confirmation, NodeError> {
        let scope = held.signed_scope().map_err(NodeError::Object)?;
        let signature = mt_suite::sign::sign(&self.secret_of_the_key, &scope).map_err(|_| {
            NodeError::Unprovable {
                what: "the signature of an attestation",
            }
        })?;
        held.signature = signature.as_bytes().to_vec();
        held.bytes().map_err(NodeError::Object)?;
        Ok(held)
    }

    fn signed_light(&self, mut held: LightAttestation) -> Result<LightAttestation, NodeError> {
        let scope = held.signed_scope().map_err(NodeError::Object)?;
        let signature = mt_suite::sign::sign(&self.secret_of_the_key, &scope).map_err(|_| {
            NodeError::Unprovable {
                what: "the signature of an attestation",
            }
        })?;
        held.signature = signature.as_bytes().to_vec();
        held.bytes().map_err(NodeError::Object)?;
        Ok(held)
    }
}

// The two identifiers an attestation attests, ascending: the layout refuses any other order, so the
// order is taken here rather than left to a caller.
fn ascending(beacon_id: [u8; 32], previous_proposal: [u8; 32]) -> Vec<[u8; 32]> {
    if beacon_id < previous_proposal {
        vec![beacon_id, previous_proposal]
    } else {
        vec![previous_proposal, beacon_id]
    }
}

// What a verifier does with a heavy attestation that arrived: the eligibility natively, the
// signature under the key it carries, and the proof of presence against the root of admitted
// machines it answers to. A verifier that skipped the proof would take the word of whoever sent it.
pub fn verify_heavy(
    held: &Confirmation,
    admitted_root: &mt_proof::poseidon::Digest,
    aggregate: &[u8; 32],
    chain: u8,
    round: u32,
    threshold: &mt_pulse::U256,
) -> Result<(), NodeError> {
    if !crate::round::eligible(&held.part_nullifier, aggregate, chain, round, threshold) {
        return Err(NodeError::Refused {
            what: "an attestation of a round this machine is not drawn for",
        });
    }
    let key: [u8; mt_codec::size::SIGNING_PUBLIC_KEY] = held
        .answering_key
        .clone()
        .try_into()
        .map_err(|_| NodeError::Refused {
            what: "a key of another width",
        })?;
    let scope = held.signed_scope().map_err(NodeError::Object)?;
    let signature: [u8; mt_codec::size::SIGNATURE] =
        held.signature
            .clone()
            .try_into()
            .map_err(|_| NodeError::Refused {
                what: "a signature of another width",
            })?;
    mt_suite::sign::verify(
        &mt_suite::sign::PublicKey::from_bytes(key),
        &scope,
        &mt_suite::sign::Signature::from_bytes(signature),
    )
    .map_err(|_| NodeError::Refused {
        what: "an attestation under a signature that does not verify",
    })?;

    // The public input a verifier computes for itself: the root it holds, the nullifier the
    // attestation carries, and the digest of the key that signed it. A proof lifted from another
    // attestation fails here, at the digest.
    let part =
        mt_proof::poseidon::Digest::of_bytes(&held.part_nullifier).ok_or(NodeError::Refused {
            what: "a part-nullifier that is no digest of the family",
        })?;
    let digest = mt_derive::pulse::key_digest(&key);
    let key_digest = mt_proof::poseidon::Digest::of_bytes(&digest).ok_or(NodeError::Refused {
        what: "a digest that is no digest of the family",
    })?;
    let public = mt_proof::circuit::presence::public_of(&[*admitted_root, part, key_digest]);
    let description = mt_proof::circuit::presence::description().ok_or(NodeError::Unprovable {
        what: "the description of a presence",
    })?;
    mt_proof::scheme::verify(&description, &public, &held.proof).map_err(|_| {
        NodeError::Refused {
            what: "an attestation whose proof of presence does not verify",
        }
    })?;
    Ok(())
}

// What a window mints, and to whom. Minting creates no note: a window mints a fixed quantity and
// issues, to each living machine, a **right to a share** of it — one right per machine per window,
// extinguished by exactly one nullifier, so no machine takes its share twice and none takes
// another's. The count of the living is the count of part-nullifiers the cement holds, and the
// share is the mint of that window divided by it, the remainder that does not divide carried
// forward rather than appropriated.
//
// A machine reads its own right out of its own secret and tells nobody: the nullifier names no one,
// and the window it is accepted in is drawn from the same absorption, so a person chooses nothing
// and nothing about the choice can be read.
pub struct Right {
    pub window: u64,
    pub nullifier: [u8; 32],
    // The window this right is accepted in — not early and not late.
    pub accepted_in: u64,
    pub share: u64,
    pub carried_forward: u64,
}

// The mint of a window, read off the schedule of the Decree by the height of that window.
pub fn mint_of(window: u64) -> Result<u64, NodeError> {
    let schedule = mt_genesis::get("emission_schedule").ok_or(NodeError::Decree {
        row: "emission_schedule".to_string(),
    })?;
    let rows = match schedule {
        mt_genesis::Entry::Schedule(_, rows) => rows,
        _ => {
            return Err(NodeError::Decree {
                row: "emission_schedule".to_string(),
            })
        }
    };
    // The row a height reads: the last one whose height does not exceed it, the rows ascending.
    let mut held = None;
    for (height, mint) in rows.iter() {
        if *height <= window {
            held = Some(*mint);
        }
    }
    held.ok_or(NodeError::Decree {
        row: "emission_schedule".to_string(),
    })
}

// The right this machine holds to the share of a window it lived in. The count of the living is
// what the cement names, and the division is exact: the share each takes and the remainder the
// window carries forward.
pub fn right_of(machine_secret: &[u8; 32], window: u64, living: usize) -> Result<Right, NodeError> {
    if living == 0 {
        return Err(NodeError::Refused {
            what: "a window whose cement names no machine mints no share",
        });
    }
    let mint = mint_of(window)?;
    let living = living as u64;
    let nullifier =
        mt_derive::nullifier::credit(machine_secret, window).ok_or(NodeError::Unprovable {
            what: "the right of this machine to a window's share",
        })?;
    let accepted_in = mt_derive::nullifier::claim_window(machine_secret, window).ok_or(
        NodeError::Unprovable {
            what: "the window this machine's right is accepted in",
        },
    )?;
    Ok(Right {
        window,
        nullifier,
        accepted_in,
        share: mint / living,
        carried_forward: mint % living,
    })
}

// The leaf a verified heavy attestation contributes to the cement of its window.
pub fn leaf_of(held: &Confirmation) -> Result<mt_pulse::fold::Leaf, NodeError> {
    let commitment = mt_suite::standing::Commitment::deserialize(&held.weight_commit).ok_or(
        NodeError::Refused {
            what: "a commitment of another width",
        },
    )?;
    Ok(mt_pulse::fold::Leaf {
        part_nullifier: held.part_nullifier,
        commitment,
    })
}
