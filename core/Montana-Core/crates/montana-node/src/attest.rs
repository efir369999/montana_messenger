// What a machine does inside a window: draws its eligibility, answers a round, and gathers what
// answers arrive into the cement its successor closes on.
//
// **The first attestation of a window is heavy and every later one is light.** The heavy one
// carries the proof of presence — that the nullifier of this machine's part comes of the secret of
// a machine whose naming half stands in the tree of the electorate, and that the key signing the
// attestation is the one that proof was made for — and its part-nullifier is what enters the
// cement. A light one is the same object without the proof, valid because the key it signs under
// already stood proven in the heavy every verifier holds. Nothing an attestation carries weighs
// anything: a part counts once or not at all.
//
// **Nothing here decides anything a rule does not.** Eligibility is the draw of `mt-derive`, the
// proof is the description of `mt-proof`, the cement and the close are of `mt-pulse`, the objects
// are the layouts of `mt-state`. What this file holds is the order.

use crate::certificate::Electorate;
use crate::NodeError;
use mt_proof::circuit::ballot;
use mt_proof::poseidon::Digest;
use mt_state::layout::{Ballot, Confirmation, LightAttestation, Pledge};
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
}

impl Standing {
    // What a machine draws once per window. The proof is made here and not at every round: it binds
    // the window and not the round, so one presence serves the window it belongs to.
    pub fn of_the_window(
        machine_secret: &[u8; 32],
        window: u64,
        admitted_siblings: &[mt_proof::poseidon::Digest],
        admitted_position: u64,
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

        // The proof of presence: what the network verifies before it lets this machine's part enter
        // a cement.
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
        let public = mt_proof::circuit::presence::public_of(&digests, window);
        let description =
            mt_proof::circuit::presence::description().ok_or(NodeError::Unprovable {
                what: "the description of a presence",
            })?;
        let presence = mt_proof::scheme::prove(&description, &public, &trace).map_err(|_| {
            NodeError::Unprovable {
                what: "a proof of this machine's presence",
            }
        })?;

        Ok(Self {
            window,
            part_nullifier,
            key,
            secret_of_the_key,
            presence,
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

    // The heavy attestation of a window: the proof and the two identifiers it attests in the
    // canonical order the layout demands.
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
            // Record 309, beside the plan of #89: the line of the open slot of attempt zero at the
            // name attested, asserted by the proof of presence. Zeros until the presence asserts it.
            line_value: [0u8; 32],
            suite_id: mt_net::SUITE,
            answering_key: self.key.as_bytes().to_vec(),
            proof: self.presence.clone(),
            signature: vec![0u8; mt_codec::size::SIGNATURE],
        };
        self.signed(held)
    }

    // Every later attestation of the same window: the same object without the proof, valid because
    // its key already stood proven in the heavy.
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

    // A pledge of the agreement on the proposal of the window before, under the key this window's
    // heavy attestation proves. It carries the line of its slot at the abscissa of `name` and the
    // proof of the pledge, which binds that value to this machine's part and discloses neither half
    // (Canon, "The pledge of a part"; plan of #89, step 3).
    pub fn pledge(
        &self,
        machine_secret: &[u8; 32],
        attempt: u32,
        name: [u8; 32],
        since: u32,
    ) -> Result<Pledge, NodeError> {
        let unprovable = || NodeError::Unprovable {
            what: "the proof of a pledge",
        };
        let (trace, part, value) = mt_proof::circuit::pledge::trace_of(
            machine_secret,
            self.window,
            attempt,
            &name,
            since,
        )
        .ok_or_else(unprovable)?;
        // The part the proof names is the part this window stands on, or the secret is another's.
        if part.bytes() != self.part_nullifier {
            return Err(unprovable());
        }
        let public =
            mt_proof::circuit::pledge::public_of(self.window, attempt, &name, since, &part, value);
        let description = mt_proof::circuit::pledge::description().ok_or(NodeError::Unprovable {
            what: "the description of a pledge",
        })?;
        let proof =
            mt_proof::scheme::prove(&description, &public, &trace).map_err(|_| unprovable())?;
        let mut held = Pledge {
            window: self.window,
            attempt,
            name,
            since,
            part_nullifier: self.part_nullifier,
            line_value: value.to_bytes(),
            suite_id: mt_net::SUITE,
            answering_key: self.key.as_bytes().to_vec(),
            proof,
            signature: vec![0u8; mt_codec::size::SIGNATURE],
        };
        let scope = held.signed_scope().map_err(NodeError::Object)?;
        let signature = mt_suite::sign::sign(&self.secret_of_the_key, &scope).map_err(|_| {
            NodeError::Unprovable {
                what: "the signature of a pledge",
            }
        })?;
        held.signature = signature.as_bytes().to_vec();
        held.bytes().map_err(NodeError::Object)?;
        Ok(held)
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
    let scope = held.signed_scope().map_err(NodeError::Object)?;
    verify_signature(held.suite_id, &held.answering_key, &held.signature, &scope)?;
    let key: &[u8; mt_codec::size::SIGNING_PUBLIC_KEY] = held
        .answering_key
        .as_slice()
        .try_into()
        .map_err(|_| NodeError::Refused {
        what: "a key of another width",
    })?;

    // The public input a verifier computes for itself: the root it holds, the nullifier the
    // attestation carries, and the digest of the key that signed it. A proof lifted from another
    // attestation fails here, at the digest.
    let part =
        mt_proof::poseidon::Digest::of_bytes(&held.part_nullifier).ok_or(NodeError::Refused {
            what: "a part-nullifier that is no digest of the family",
        })?;
    let digest = mt_derive::pulse::key_digest(key);
    let key_digest = mt_proof::poseidon::Digest::of_bytes(&digest).ok_or(NodeError::Refused {
        what: "a digest that is no digest of the family",
    })?;
    let public =
        mt_proof::circuit::presence::public_of(&[*admitted_root, part, key_digest], held.window);
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

// A light answer inherits only a key already proven in this window. The pulse
// owns that cache; a signature under an arbitrary wire key is not a presence.
pub fn verify_light(
    held: &LightAttestation,
    proven_key: &[u8],
    aggregate: &[u8; 32],
    chain: u8,
    round: u32,
    threshold: &mt_pulse::U256,
) -> Result<(), NodeError> {
    if held.answering_key != proven_key {
        return Err(NodeError::Refused {
            what: "a light attestation without the same proven answering key",
        });
    }
    if !crate::round::eligible(&held.part_nullifier, aggregate, chain, round, threshold) {
        return Err(NodeError::Refused {
            what: "an attestation of a round this machine is not drawn for",
        });
    }
    let scope = held.signed_scope().map_err(NodeError::Object)?;
    verify_signature(held.suite_id, &held.answering_key, &held.signature, &scope)
}

// A pledge of the agreement counts only under the key its part's heavy attestation proved in this
// window. Consensus, "The agreement on what a window decided": until that heavy is seen the pledge
// stands in escrow, so the caller holds the proven key and this door judges the rest -- the
// signature, then the proof of the pledge against the public input this door computes from the
// pledge itself. A pledge whose proof does not verify enters no quorum and is no evidence (Canon,
// "Invariants of a pledge"; plan of #89, step 4).
pub fn verify_pledge(held: &Pledge, proven_key: &[u8]) -> Result<(), NodeError> {
    if held.answering_key != proven_key {
        return Err(NodeError::Refused {
            what: "a pledge without the same proven answering key",
        });
    }
    let scope = held.signed_scope().map_err(NodeError::Object)?;
    verify_signature(held.suite_id, &held.answering_key, &held.signature, &scope)?;
    let part =
        mt_proof::poseidon::Digest::of_bytes(&held.part_nullifier).ok_or(NodeError::Refused {
            what: "a part-nullifier that is no digest of the family",
        })?;
    let value = mt_proof::line::L::from_bytes(&held.line_value).ok_or(NodeError::Refused {
        what: "a line value that is no element of the field of the line",
    })?;
    let public = mt_proof::circuit::pledge::public_of(
        held.window,
        held.attempt,
        &held.name,
        held.since,
        &part,
        value,
    );
    let description = mt_proof::circuit::pledge::description().ok_or(NodeError::Unprovable {
        what: "the description of a pledge",
    })?;
    mt_proof::scheme::verify(&description, &public, &held.proof).map_err(|_| NodeError::Refused {
        what: "a pledge whose proof does not verify",
    })
}

fn verify_signature(
    suite: u16,
    key: &[u8],
    signature: &[u8],
    scope: &[u8],
) -> Result<(), NodeError> {
    if suite != mt_net::SUITE {
        return Err(NodeError::Refused {
            what: "an attestation under an unsupported suite",
        });
    }
    let key = key.try_into().map_err(|_| NodeError::Refused {
        what: "a key of another width",
    })?;
    let signature = signature.try_into().map_err(|_| NodeError::Refused {
        what: "a signature of another width",
    })?;
    mt_suite::sign::verify(
        &mt_suite::sign::PublicKey::from_bytes(key),
        scope,
        &mt_suite::sign::Signature::from_bytes(signature),
    )
    .map_err(|_| NodeError::Refused {
        what: "an attestation under a signature that does not verify",
    })
}

// A census window this machine lived: the root of its cement and the branch the machine's part walks
// in it. It is what a ballot is proven from, and it is the machine's own — no reader learns which
// census windows a machine lived, and the store keeps it closed to everyone but its owner.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct LivedCensus {
    pub window: u64,
    pub root: [u8; 32],
    pub siblings: Vec<Digest>,
    pub position: u64,
}

impl LivedCensus {
    // The census windows a machine lived, written one after another: the window, the root, the
    // position, and the siblings of the branch, every count of fixed width and every value whole.
    pub fn encode(held: &[LivedCensus]) -> Vec<u8> {
        let mut out = Vec::new();
        out.extend_from_slice(&(held.len() as u32).to_le_bytes());
        for one in held {
            out.extend_from_slice(&one.window.to_le_bytes());
            out.extend_from_slice(&one.root);
            out.extend_from_slice(&one.position.to_le_bytes());
            out.extend_from_slice(&(one.siblings.len() as u32).to_le_bytes());
            for sibling in &one.siblings {
                out.extend_from_slice(&sibling.bytes());
            }
        }
        out
    }

    // Read back whole or refused: a file of another shape is not this machine's standing.
    pub fn decode(bytes: &[u8]) -> Result<Vec<LivedCensus>, NodeError> {
        let short = || NodeError::Refused {
            what: "a standing shorter than what it declares",
        };
        if bytes.is_empty() {
            return Ok(Vec::new());
        }
        let mut at = 0usize;
        let mut take = |n: usize| -> Result<&[u8], NodeError> {
            let end = at.checked_add(n).ok_or_else(short)?;
            let held = bytes.get(at..end).ok_or_else(short)?;
            at = end;
            Ok(held)
        };
        let four = |b: &[u8]| u32::from_le_bytes([b[0], b[1], b[2], b[3]]) as usize;
        let eight = |b: &[u8]| {
            let mut w = [0u8; 8];
            w.copy_from_slice(b);
            u64::from_le_bytes(w)
        };
        let count = four(take(4)?);
        let mut out = Vec::new();
        for _ in 0..count {
            let window = eight(take(8)?);
            let mut root = [0u8; 32];
            root.copy_from_slice(take(32)?);
            let position = eight(take(8)?);
            let depth = four(take(4)?);
            if depth != mt_proof::tree_depth() {
                return Err(NodeError::Refused {
                    what: "a branch of another depth than the cement's",
                });
            }
            let mut siblings = Vec::with_capacity(depth);
            for _ in 0..depth {
                let mut held = [0u8; 32];
                held.copy_from_slice(take(32)?);
                siblings.push(Digest::of_bytes(&held).ok_or(NodeError::Refused {
                    what: "a sibling that is no digest of the family",
                })?);
            }
            out.push(LivedCensus {
                window,
                root,
                siblings,
                position,
            });
        }
        if at != bytes.len() {
            return Err(NodeError::Refused {
                what: "a standing longer than what it declares",
            });
        }
        Ok(out)
    }
}

// The units of standing a machine holds against an electorate: every census window of it, with the
// branch the machine walks where it lived that census under the root the electorate names. A census
// it lived under another root — a window it closed on another cement than the one that stood — casts
// nothing.
fn units_of(
    electorate: &Electorate,
    lived: &[LivedCensus],
) -> Result<Vec<ballot::Census>, NodeError> {
    electorate
        .census_roots()?
        .into_iter()
        .zip(&electorate.census)
        .map(|((window, root), entry)| {
            let branch = lived
                .iter()
                .find(|one| one.window == window && one.root == entry.root)
                .map(|one| (one.siblings.clone(), one.position));
            Ok(ballot::Census {
                window,
                root,
                branch,
            })
        })
        .collect()
}

fn spending_of(machine_secret: &[u8; 32]) -> Result<Digest, NodeError> {
    Digest::of_bytes(&mt_derive::nullifier::machine_halves(machine_secret).0).ok_or(
        NodeError::Unprovable {
            what: "the halves of this machine's secret",
        },
    )
}

// The ballot of this machine for a window: nothing where the electorate is counted whole or where its
// standing drew no vote, and otherwise the count of votes and the proof of it. The aggregate is the
// one of the window two before, which the draw of a runner reads as well.
pub fn ballot_of(
    machine_secret: &[u8; 32],
    window: u64,
    electorate: &Electorate,
    aggregate: &[u8; 32],
    lived: &[LivedCensus],
) -> Result<Option<Ballot>, NodeError> {
    if electorate.committee.expected == 0 {
        return Ok(None);
    }
    let spending = spending_of(machine_secret)?;
    let threshold = electorate.committee.threshold.to_be_bytes();
    let units = units_of(electorate, lived)?;
    let unprovable = || NodeError::Unprovable {
        what: "the ballot of this machine",
    };
    let votes =
        ballot::votes_of(&spending, &units, aggregate, &threshold).ok_or_else(unprovable)?;
    if votes == 0 {
        return Ok(None);
    }
    let (trace, part, votes) = ballot::trace_of(&spending, window, &units, aggregate, &threshold)
        .ok_or_else(unprovable)?;
    let pairs = electorate.census_roots()?;
    let public = ballot::public_of(&part, window, &pairs, aggregate, &threshold, votes);
    let description = ballot::description().ok_or_else(unprovable)?;
    let proof = mt_proof::scheme::prove(&description, &public, &trace).map_err(|_| unprovable())?;
    let held = Ballot {
        window,
        part_nullifier: part.bytes(),
        votes,
        proof,
    };
    held.bytes().map_err(NodeError::Object)?;
    Ok(Some(held))
}

// What a verifier does with a ballot that arrived: its rule, its window, and its proof against the
// census, the aggregate and the committee of the electorate it answers to. It answers with the count
// the ballot casts; whether the part it names entered the cement is the caller's question, since a
// ballot counts for a part of the cement and for no other.
pub fn verify_ballot(
    held: &Ballot,
    window: u64,
    electorate: &Electorate,
    aggregate: &[u8; 32],
) -> Result<u64, NodeError> {
    held.bytes().map_err(NodeError::Object)?;
    if held.window != window {
        return Err(NodeError::Refused {
            what: "a ballot of another window",
        });
    }
    if electorate.committee.expected == 0 {
        return Err(NodeError::Refused {
            what: "a ballot of an electorate counted whole",
        });
    }
    let part = Digest::of_bytes(&held.part_nullifier).ok_or(NodeError::Refused {
        what: "a part-nullifier that is no digest of the family",
    })?;
    let pairs = electorate.census_roots()?;
    let public = ballot::public_of(
        &part,
        window,
        &pairs,
        aggregate,
        &electorate.committee.threshold.to_be_bytes(),
        held.votes,
    );
    let description = ballot::description().ok_or(NodeError::Unprovable {
        what: "the description of a ballot",
    })?;
    mt_proof::scheme::verify(&description, &public, &held.proof).map_err(|_| {
        NodeError::Refused {
            what: "a ballot whose proof does not verify",
        }
    })?;
    Ok(held.votes)
}

// What a window credits, and to whom. Minting creates no note: a window credits **one coin for
// every second of it** — `window_credit` of the Decree, 86 400 / `segment_windows` = 60 — to every
// machine living in it, and issues to each a **right to its coins** of that window — one right per
// machine per window, extinguished by exactly one nullifier, so no machine takes its coins twice
// and none takes another's. Nothing is divided, so no remainder exists to carry: the count of the
// living is the count of part-nullifiers the cement holds, the credit times that count is the
// supply the window adds, in coins, and the count is never the price of a right. Consensus, "The
// right to a window's coin".
//
// A machine reads its own right out of its own secret and tells nobody: the nullifier names no one,
// and the window it is accepted in is drawn from the same absorption, so a person chooses nothing
// and nothing about the choice can be read.
pub struct Right {
    pub window: u64,
    pub nullifier: [u8; 32],
    // The window this right is accepted in — not early and not late.
    pub accepted_in: u64,
    // What the right brings into the balance of the frame that redeems it: the window's credit.
    pub worth: u64,
}

// The coins a window credits to every machine living in it, read off the Decree: one for every
// second of the window, 86 400 / `segment_windows` = 60, fixed by the constitutional layer whatever
// the height and whatever the count of the living. The seconds are counted by the Decree and never
// measured: no clock is read to issue it.
pub fn window_credit() -> Result<u64, NodeError> {
    mt_genesis::scalar("window_credit").ok_or(NodeError::Decree {
        row: "window_credit".to_string(),
    })
}

// What a window adds to the supply: the window's credit to every part its cement names, and
// nothing else. A cement of nobody adds nothing.
pub fn supply_added(living: usize) -> Result<u64, NodeError> {
    let living = u64::try_from(living).map_err(|_| NodeError::Refused {
        what: "a cement past counting",
    })?;
    window_credit()?
        .checked_mul(living)
        .ok_or(NodeError::Refused {
            what: "a cement past counting",
        })
}

// The right this machine holds to its coins of a window it lived in. What the right is worth does
// not read the count of the living: the window's credit, the same for every machine of every
// cement. Whether the
// machine lived the window is the caller's to know — its part among the parts the decided roll
// names — and nothing here can see it.
pub fn right_of(machine_secret: &[u8; 32], window: u64) -> Result<Right, NodeError> {
    let worth = window_credit()?;
    let nullifier =
        mt_derive::nullifier::credit(machine_secret, window).ok_or(NodeError::Unprovable {
            what: "the right of this machine to a window's coin",
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
        worth,
    })
}
