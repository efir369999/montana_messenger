// The runner of a window: the machine whose ticket cleared, and what it publishes to close the
// window. Consensus, "Closing a window": the runner assembles the proposal from what the slots
// carried, commits the roots of state, proves its ticket in the proposal itself, and publishes.
// Canon, "The proposal that closes a window": the ticket proof asserts the clearing of the ticket,
// the membership of the naming half in the tree of the electorate, and the digest of the key the
// proposal answers under, under the description of the ticket at the height of the presence.
//
// **A runner that did not clear has nothing here.** The trace of a ticket at or above the threshold
// is not written, so `of_the_window` answers nothing for such a machine: no proposal of a machine
// that did not draw the window can be assembled, let alone signed.

use crate::certificate::{Decided, Predecessor, Roots};
use crate::NodeError;
use mt_state::layout::Proposal;
use mt_state::Layout;
use zeroize::Zeroizing;

pub struct Runner {
    pub window: u64,
    pub key: mt_suite::sign::PublicKey,
    secret_of_the_key: mt_suite::sign::SecretKey,
    pub ticket_proof: Vec<u8>,
}

impl Runner {
    // What a machine that drew the window holds of it: the one-time key it publishes under, derived
    // from its secret and the window under the runner-key domain, and the proof that its ticket
    // cleared against the electorate root, the aggregate of the window two before and the threshold
    // of the draw read from state. Nothing where the ticket does not clear.
    pub fn of_the_window(
        machine_secret: &[u8; 32],
        window: u64,
        admitted_siblings: &[mt_proof::poseidon::Digest],
        admitted_position: u64,
        aggregate_two_before: &[u8; 32],
        draw_threshold: &mt_pulse::U256,
    ) -> Result<Option<Self>, NodeError> {
        let seed = mt_derive::pulse::runner_key_seed(machine_secret, window);
        let mut held = Zeroizing::new([0u8; mt_suite::sign::SEED_BYTES]);
        held.copy_from_slice(&seed[..mt_suite::sign::SEED_BYTES]);
        let (key, secret_of_the_key) = mt_suite::sign::keypair_from_seed(&held);
        let threshold = draw_threshold.to_be_bytes();
        let Some((trace, digests)) = mt_proof::circuit::ticket::trace_of(
            machine_secret,
            admitted_siblings,
            admitted_position,
            aggregate_two_before,
            &threshold,
            key.as_bytes(),
        ) else {
            return Ok(None);
        };
        let public =
            mt_proof::circuit::ticket::public_of(&digests, aggregate_two_before, &threshold);
        let description =
            mt_proof::circuit::ticket::description().ok_or(NodeError::Unprovable {
                what: "the description of a ticket",
            })?;
        let ticket_proof =
            mt_proof::scheme::prove(&description, &public, &trace).map_err(|_| {
                NodeError::Unprovable {
                    what: "a proof of this machine's ticket",
                }
            })?;
        Ok(Some(Self {
            window,
            key,
            secret_of_the_key,
            ticket_proof,
        }))
    }

    // The proposal that closes the window: its predecessor by identifier, the beacon the window closed
    // on and the cement that beacon carried, the roots and the count the verifier recomputes, the key
    // and the proof, signed under the key.
    pub fn propose(
        &self,
        protocol_version: u32,
        predecessor: Predecessor<'_>,
        roots: &Roots,
        decided: &Decided,
    ) -> Result<Proposal, NodeError> {
        let window = self.window;
        let follows = match predecessor {
            Predecessor::Genesis => true,
            Predecessor::Proposal(previous) => previous.window.checked_add(1) == Some(window),
        };
        if !follows || decided.window != window {
            return Err(NodeError::Refused {
                what: "a proposal of another window than the one this runner drew",
            });
        }
        let mut held = Proposal {
            window,
            protocol_version,
            previous: predecessor.id()?,
            final_beacon: decided.final_beacon,
            note_root: roots.note_root,
            nullifier_root: roots.nullifier_root,
            record_root: roots.record_root,
            machine_root: roots.machine_root,
            admitted_root: roots.admitted_root,
            operations_root: roots.operations_root,
            roll: roots.roll,
            admitted_count: roots.admitted_count,
            cement_aggregate: decided.cement_aggregate,
            cement_count: decided.cement_count,
            census: roots.census.clone(),
            suite_id: mt_net::SUITE,
            runner_pubkey: self.key.as_bytes().to_vec(),
            ticket_proof: self.ticket_proof.clone(),
            signature: vec![0u8; mt_codec::size::SIGNATURE],
        };
        let scope = held.signed_scope().map_err(NodeError::Object)?;
        let signature = mt_suite::sign::sign(&self.secret_of_the_key, &scope).map_err(|_| {
            NodeError::Unprovable {
                what: "the signature of a proposal",
            }
        })?;
        held.signature = signature.as_bytes().to_vec();
        held.bytes().map_err(NodeError::Object)?;
        Ok(held)
    }
}
