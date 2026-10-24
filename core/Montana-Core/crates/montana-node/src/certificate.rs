// The closure of a window, verified as one entry point. Consensus, "The pulse and the close of a
// window": the close is a count every verifier makes — every heavy attestation verified natively as
// it arrives, a part that verified entering the cement once, and the predecessor final when the
// count multiplied by the denominator of the quorum reaches the count of the electorate multiplied
// by its numerator. Consensus, "The certificate of a window": a device that was not there verifies a
// window exactly as the living did — every presence proof against the electorate root it already
// holds, every signature, the distinctness of the parts, the count against the electorate, and the
// proposal's own ticket proof and signature.
//
// **One door for the living and for the device behind.** A machine of the window gathers the same
// attestations round by round through its pulse; a device walking the retained certificate hands
// them in whole. Both reach this door with the same bytes and leave with the same answer, which is
// what makes a certificate a certificate and not a second rule. What the two do not share is the
// state: the living recompute the roots of a proposal from what they hold, and a device behind takes
// them as the certificate that makes the proposal final attests them.

use crate::NodeError;
use mt_proof::poseidon::Digest;
use mt_pulse::standing::Committee;
use mt_state::layout::{Ballot, Beacon, Census, Confirmation, Pledge, Proposal};
use mt_state::Layout;
use std::collections::BTreeMap;

// The electorate of a window: the admitted set the proposal of the window two before carries, root
// and count, and the census its standing is counted over, with the committee that standing draws.
// For the first two windows of a network it is the opening cohort an operator handed the machine,
// standing on a census of nothing.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Electorate {
    pub root: Digest,
    pub count: u64,
    pub census: Vec<Census>,
    // The census window each entry of the census stands for, newest first.
    pub windows: Vec<u64>,
    pub committee: Committee,
}

fn of_the_standing(error: mt_pulse::PulseError) -> NodeError {
    match error {
        mt_pulse::PulseError::CountBeyondWidth => NodeError::Refused {
            what: "a standing past what a count carries",
        },
        _ => NodeError::Decree {
            row: "standing_censuses".to_string(),
        },
    }
}

impl Electorate {
    // The electorate the proposal of the window two before fixes: its admitted root and count, and
    // its census.
    pub fn of(proposal: &Proposal) -> Result<Self, NodeError> {
        let root = Digest::of_bytes(&proposal.admitted_root).ok_or(NodeError::Refused {
            what: "an admitted root that is no digest of the family",
        })?;
        Self::standing_on(
            root,
            proposal.admitted_count,
            proposal.census.clone(),
            proposal.window,
        )
    }

    // The opening cohort of a network, which stands on a census of nothing: every entry the root of
    // the empty cement and a count of nought, read against the census windows of the window two
    // before the one being opened, so a prover and a verifier name the same windows.
    pub fn opening(root: Digest, count: u64, window: u64) -> Result<Self, NodeError> {
        Self::standing_on(root, count, empty_census()?, window.saturating_sub(2))
    }

    fn standing_on(
        root: Digest,
        count: u64,
        census: Vec<Census>,
        of_the_census: u64,
    ) -> Result<Self, NodeError> {
        let windows = mt_pulse::standing::census_windows(of_the_census).map_err(of_the_standing)?;
        if windows.len() != census.len() {
            return Err(NodeError::Refused {
                what: "a census of another length than the Decree names",
            });
        }
        let counts: Vec<u64> = census.iter().map(|entry| entry.count).collect();
        let standing = mt_pulse::standing::standing(&counts).map_err(of_the_standing)?;
        let committee = mt_pulse::standing::committee(standing).map_err(of_the_standing)?;
        Ok(Self {
            root,
            count,
            census,
            windows,
            committee,
        })
    }

    // The census windows and the roots of their cements, as a ballot is proven and verified against.
    pub fn census_roots(&self) -> Result<Vec<(u64, Digest)>, NodeError> {
        self.windows
            .iter()
            .zip(&self.census)
            .map(|(window, entry)| {
                Digest::of_bytes(&entry.root)
                    .map(|root| (*window, root))
                    .ok_or(NodeError::Refused {
                        what: "a census root that is no digest of the family",
                    })
            })
            .collect()
    }
}

// The census before the first window of a network: the root of the empty cement and nought, at
// every entry.
pub fn empty_census() -> Result<Vec<Census>, NodeError> {
    let censuses = mt_pulse::standing::censuses().map_err(of_the_standing)?;
    Ok(vec![
        Census {
            root: mt_proof::cement::empty_root().bytes(),
            count: 0,
        };
        censuses
    ])
}

// What a window stands on: the proposal of the window before, or — for the first window of a
// network, which has none — the Genesis State Hash, which names the parameters the network opened
// on. Canon, "The proposal that closes a window": `previous`.
#[derive(Clone, Copy, Debug)]
pub enum Predecessor<'a> {
    Genesis,
    Proposal(&'a Proposal),
}

impl Predecessor<'_> {
    pub fn id(&self) -> Result<[u8; 32], NodeError> {
        match self {
            Predecessor::Genesis => {
                mt_state::tables::genesis_state_hash().ok_or(NodeError::Decree {
                    row: "genesis_state_hash".to_string(),
                })
            }
            Predecessor::Proposal(held) => held.id().map_err(NodeError::Object),
        }
    }

    // Whether `window` is the one this predecessor is followed by. The window a cohort opens at is
    // of the world outside, as the cohort itself is, so the Genesis State Hash stands under it.
    fn is_followed_by(&self, window: u64) -> bool {
        match self {
            Predecessor::Genesis => true,
            Predecessor::Proposal(held) => held.window.checked_add(1) == Some(window),
        }
    }

    // The rules a successor may not fall below.
    fn version(&self) -> u32 {
        match self {
            Predecessor::Genesis => 0,
            Predecessor::Proposal(held) => held.protocol_version,
        }
    }
}

// What a verified certificate establishes: the window, and the distinct parts its heavy attestations
// named, with their aggregate and count, and the votes the verified ballots of those parts cast —
// each part once, at the largest count a ballot of it carries.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Closure {
    pub window: u64,
    pub cement_aggregate: [u8; 32],
    pub cement_count: u64,
    pub parts: Vec<[u8; 32]>,
    pub votes: BTreeMap<[u8; 32], u64>,
}

impl Closure {
    // The votes the ballots of the certificate justify: the sum over its parts.
    pub fn justified(&self) -> Result<u64, NodeError> {
        sum_of_votes(self.votes.values())
    }
}

pub(crate) fn sum_of_votes<'a>(votes: impl Iterator<Item = &'a u64>) -> Result<u64, NodeError> {
    votes.into_iter().try_fold(0u64, |sum, cast| {
        sum.checked_add(*cast).ok_or(NodeError::Refused {
            what: "a tally of votes past what a count carries",
        })
    })
}

// A round of the certificate: the beacon a set of heavy attestations answered, those attestations,
// and the ballots standing beside them, as they stood at the points of the round.
pub struct Round<'a> {
    pub beacon: &'a Beacon,
    pub heavy: &'a [Confirmation],
    pub ballots: &'a [Ballot],
}

// The count of a cement against the quorum share of the electorate, by the integer rule of Canon.
fn reaches_the_quorum(count: u64, electorate: &Electorate) -> Result<(), NodeError> {
    let reached = mt_pulse::close::closes(u128::from(count), u128::from(electorate.count), 0)
        .map_err(|_| NodeError::Decree {
            row: "confirmation_quorum".to_string(),
        })?;
    if reached {
        Ok(())
    } else {
        Err(NodeError::Refused {
            what: "a cement below the quorum share of the electorate",
        })
    }
}

// The votes of a cement against the quorum share of the committee the electorate's standing draws,
// by the integer rule of Canon. A committee of nought — an electorate counted whole — asks none.
fn reaches_the_committee(votes: u64, electorate: &Electorate) -> Result<(), NodeError> {
    let reached = mt_pulse::close::votes_reached(
        u128::from(votes),
        u128::from(electorate.committee.expected),
    )
    .map_err(|_| NodeError::Decree {
        row: "confirmation_quorum".to_string(),
    })?;
    if reached {
        Ok(())
    } else {
        Err(NodeError::Refused {
            what: "votes below the quorum share of the committee",
        })
    }
}

// The certificate of the proposal of the window before: the heavy attestations of this window, each
// verified as the living verified it, counted once per part against the count of the electorate, and
// the pledges of the agreement run in it, which decide the proposal. `chains` is the count of chains
// in force at this height, which the round threshold is read from.
//
// Every refusal names what was refused and nothing of who sent it. A repeated part adds nothing and is
// lawful; a second answering key under one part is refused, because one machine attests one window
// under one key and a second key is a second claim of one place. A heavy attestation enters the cement
// whatever name it pledges beside its beacon (Consensus, "Closure, and the canonical cement"); what
// makes the predecessor final is the agreement deciding its name.
pub fn verify_certificate(
    window: u64,
    electorate: &Electorate,
    predecessor: Predecessor<'_>,
    aggregate_two_before: &[u8; 32],
    chains: u64,
    rounds: &[Round<'_>],
    pledges: &[Pledge],
) -> Result<Closure, NodeError> {
    if !predecessor.is_followed_by(window) {
        return Err(NodeError::Refused {
            what: "a certificate of a window other than the one after the proposal it finalizes",
        });
    }
    let previous_id = predecessor.id()?;
    let threshold =
        mt_pulse::retarget::round_threshold(electorate.count, chains).map_err(|_| {
            NodeError::Decree {
                row: "round_floor".to_string(),
            }
        })?;
    let mut cement = mt_pulse::cement::Cement::new();
    let mut keys: BTreeMap<[u8; 32], Vec<u8>> = BTreeMap::new();
    let mut book = crate::agreement::Book::of_the_window(window);
    for round in rounds {
        if round.beacon.window != window {
            return Err(NodeError::Refused {
                what: "a beacon of another window inside a certificate",
            });
        }
        let beacon_id = round.beacon.id().map_err(NodeError::Object)?;
        for held in round.heavy {
            if held.window != window {
                return Err(NodeError::Refused {
                    what: "an attestation of another window inside a certificate",
                });
            }
            let name = pledged_name(&held.attested, &beacon_id).ok_or(NodeError::Refused {
                what: "an attestation outside the beacon of its round",
            })?;
            if let Some(key) = keys.get(&held.part_nullifier) {
                if key != &held.answering_key {
                    return Err(NodeError::Refused {
                        what: "a second answering key under one part-nullifier",
                    });
                }
            }
            crate::attest::verify_heavy(
                held,
                &electorate.root,
                aggregate_two_before,
                round.beacon.chain,
                round.beacon.round,
                &threshold,
            )?;
            keys.entry(held.part_nullifier)
                .or_insert_with(|| held.answering_key.clone());
            cement.add(held.part_nullifier);
            book.heavy(held.part_nullifier, name);
        }
    }
    // The ballots, once the parts stand: a ballot counts for a part of the cement and for no other,
    // once, at the largest count a ballot of it carries. A ballot that does not verify casts nothing
    // and refuses nothing — the votes it claimed are simply not there — so whoever answered a walk
    // cannot stop it by handing in a forged one.
    let mut votes: BTreeMap<[u8; 32], u64> = BTreeMap::new();
    for round in rounds {
        for ballot in round.ballots {
            if !cement.holds(&ballot.part_nullifier) {
                continue;
            }
            let Ok(cast) =
                crate::attest::verify_ballot(ballot, window, electorate, aggregate_two_before)
            else {
                continue;
            };
            let held = votes.entry(ballot.part_nullifier).or_insert(0);
            *held = (*held).max(cast);
        }
    }
    reaches_the_quorum(cement.count(), electorate)?;
    reaches_the_committee(sum_of_votes(votes.values())?, electorate)?;
    // The pledges, once the keys stand: a pledge whose part has no heavy attestation here is in escrow
    // and one that does not verify under that key says nothing, and neither refuses the certificate —
    // as with a ballot, whoever answered a walk cannot stop it by handing in a forged one.
    for pledge in pledges {
        let Some(key) = keys.get(&pledge.part_nullifier) else {
            continue;
        };
        if crate::attest::verify_pledge(pledge, key).is_ok() {
            book.pledge(pledge.clone());
        }
    }
    let agreement = crate::agreement::Electorate {
        count: electorate.count,
        committee: electorate.committee.expected,
        votes: &votes,
    };
    if book.decided(&agreement).map(|(name, _)| name) != Some(previous_id) {
        return Err(NodeError::Refused {
            what: "a certificate whose agreement does not decide the proposal it finalizes",
        });
    }
    let cement_aggregate = cement.aggregate(window).map_err(|_| NodeError::Refused {
        what: "a cement the aggregation refuses",
    })?;
    Ok(Closure {
        window,
        cement_aggregate,
        cement_count: cement.count(),
        parts: cement.parts(),
        votes,
    })
}

// The name a heavy attestation pledges: the one of its two identifiers, ascending, that is not the
// beacon of its round. Consensus, "Invariants of the round".
fn pledged_name(attested: &[[u8; 32]], beacon: &[u8; 32]) -> Option<[u8; 32]> {
    match attested {
        [first, second] if first >= second => None,
        [first, second] if first == beacon => Some(*second),
        [first, second] if second == beacon => Some(*first),
        _ => None,
    }
}

// What a window decided of its cement: the beacon it closed on and the pair that beacon carried,
// with the votes the beacon carried as the evidence of the close. Consensus, "The beacon a window
// closes on": a proposal carries the pair, the share of every living machine divides the mint by
// its count, and the draw of the window two on reads its aggregate; the votes enter no proposal.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Decided {
    pub window: u64,
    pub final_beacon: [u8; 32],
    pub cement_aggregate: [u8; 32],
    pub cement_count: u64,
    pub cement_votes: u64,
}

impl Decided {
    // The beacon a machine of the window closed on: one it reconciled against the heavy attestations
    // and the ballots it held, whose count reaches the quorum of the electorate and whose votes reach
    // the quorum share of the committee.
    pub fn of_beacon(beacon: &Beacon, electorate: &Electorate) -> Result<Self, NodeError> {
        reaches_the_quorum(beacon.cement_count, electorate)?;
        reaches_the_committee(beacon.cement_votes, electorate)?;
        Ok(Self {
            window: beacon.window,
            final_beacon: beacon.id().map_err(NodeError::Object)?,
            cement_aggregate: beacon.cement_aggregate,
            cement_count: beacon.cement_count,
            cement_votes: beacon.cement_votes,
        })
    }

    // Whether another decision of the window is this one: the pair, whichever beacon of whichever
    // branch carried it and whatever tally beside it reached the committee.
    pub fn is_the_pair_of(&self, other: &Decided) -> bool {
        (self.window, self.cement_aggregate, self.cement_count)
            == (other.window, other.cement_aggregate, other.cement_count)
    }
}

// The final beacon a proposal names, read off a verified certificate by a device that was not there:
// a beacon among the rounds of the certificate, linked by hash round by round to round zero and from
// there to the proposal of the window two before — the one that fixed the electorate of the window
// (Canon, "The round of a chain, in integers": "round zero links to the proposal of the window two
// before") — whose count reaches the quorum and names no more parts than the certificate verified.
pub fn decided_of(
    final_beacon: &[u8; 32],
    stands_on: &[u8; 32],
    rounds: &[Round<'_>],
    closure: &Closure,
    electorate: &Electorate,
) -> Result<Decided, NodeError> {
    let mut by_id: BTreeMap<[u8; 32], &Beacon> = BTreeMap::new();
    for round in rounds {
        by_id.insert(round.beacon.id().map_err(NodeError::Object)?, round.beacon);
    }
    let held = *by_id.get(final_beacon).ok_or(NodeError::Refused {
        what: "a final beacon outside the certificate",
    })?;
    if held.window != closure.window {
        return Err(NodeError::Refused {
            what: "a final beacon of another window than its certificate",
        });
    }
    // Every step back lowers the round by one, so the walk ends at round zero or refuses.
    let mut at = held;
    while at.round > 0 {
        let before = *by_id.get(&at.previous).ok_or(NodeError::Refused {
            what: "a final beacon whose chain does not reach round zero inside the certificate",
        })?;
        if !crate::round::links_to(at, before).map_err(|_| NodeError::Refused {
            what: "a beacon of another width inside a certificate",
        })? {
            return Err(NodeError::Refused {
                what: "a beacon that does not link to the one before it",
            });
        }
        at = before;
    }
    if at.previous != *stands_on {
        return Err(NodeError::Refused {
            what: "a round zero standing on another proposal than the one two before",
        });
    }
    if held.cement_count > closure.cement_count {
        return Err(NodeError::Refused {
            what: "a final beacon naming more parts than its certificate verified",
        });
    }
    if held.cement_votes > closure.justified()? {
        return Err(NodeError::Refused {
            what: "a final beacon carrying more votes than its certificate's ballots cast",
        });
    }
    Decided::of_beacon(held, electorate)
}

// The roots a verifier recomputed from the canonical slots of the window, the count of the tree of
// admitted machines with them, and the census carried from the proposal before with the cement of
// this window: what a proposal must carry and is never trusted for.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Roots {
    pub note_root: [u8; 32],
    pub nullifier_root: [u8; 32],
    pub record_root: [u8; 32],
    pub machine_root: [u8; 32],
    pub admitted_root: [u8; 32],
    pub operations_root: [u8; 32],
    // The identifier of the roll: the frames applied, in their order, and the parts of the cement,
    // ascending. Canon, "The roll of a proposal".
    pub roll: [u8; 32],
    pub admitted_count: u64,
    pub census: Vec<Census>,
}

// What a verifier holds when it judges a proposal, and nothing of it comes from the proposal: its
// predecessor, the cement its window decided, the electorate its ticket is drawn from, the aggregate
// of the window two before, the threshold of the draw read from state, and the major version this
// machine implements.
#[derive(Clone, Copy)]
pub struct Held<'a> {
    pub predecessor: Predecessor<'a>,
    pub decided: &'a Decided,
    pub electorate: &'a Electorate,
    pub aggregate_two_before: &'a [u8; 32],
    pub draw_threshold: &'a mt_pulse::U256,
    pub implemented_major: u16,
}

// The identifier of what a machine's window decided: the fields from the height through the suite,
// which the rules of this tree, the predecessor, the decided cement and the recomputed roots fix and
// which no runner's key, proof or signature enters. Canon, "The proposal that closes a window".
pub fn decided_identifier(held: &Held<'_>, roots: &Roots) -> Result<[u8; 32], NodeError> {
    Proposal {
        window: held.decided.window,
        protocol_version: mt_state::PROTOCOL_VERSION,
        previous: held.predecessor.id()?,
        final_beacon: held.decided.final_beacon,
        note_root: roots.note_root,
        nullifier_root: roots.nullifier_root,
        record_root: roots.record_root,
        machine_root: roots.machine_root,
        admitted_root: roots.admitted_root,
        operations_root: roots.operations_root,
        roll: roots.roll,
        admitted_count: roots.admitted_count,
        cement_aggregate: held.decided.cement_aggregate,
        cement_count: held.decided.cement_count,
        census: roots.census.clone(),
        suite_id: mt_net::SUITE,
        runner_pubkey: vec![0u8; mt_codec::size::SIGNING_PUBLIC_KEY],
        ticket_proof: vec![0u8; mt_state::PRESENCE_PROOF_LEN],
        signature: vec![0u8; mt_codec::size::SIGNATURE],
    }
    .id()
    .map_err(NodeError::Object)
}

// The proposal that closes the window, judged by a machine of the window: everything a device behind
// judges, and beside it the roots and the count recomputed from the state it holds.
pub fn verify_proposal(
    proposal: &Proposal,
    held: &Held<'_>,
    roots: &Roots,
) -> Result<(), NodeError> {
    judge(proposal, held, Some(roots))
}

// The proposal judged by a device that holds no state to recompute its roots from. Its roots are
// attested by the certificate that makes it final — every machine of that quorum recomputed them
// before it attested — so what this door checks is the rest of it, whole.
pub fn verify_successor(proposal: &Proposal, held: &Held<'_>) -> Result<(), NodeError> {
    judge(proposal, held, None)
}

fn judge(proposal: &Proposal, held: &Held<'_>, roots: Option<&Roots>) -> Result<(), NodeError> {
    let Held {
        predecessor,
        decided,
        electorate,
        aggregate_two_before,
        draw_threshold,
        implemented_major,
    } = *held;
    proposal.bytes().map_err(NodeError::Object)?;
    if !predecessor.is_followed_by(proposal.window) || decided.window != proposal.window {
        return Err(NodeError::Refused {
            what: "a proposal of another window than the one its certificate closes",
        });
    }
    if proposal.previous != predecessor.id()? {
        return Err(NodeError::Refused {
            what: "a proposal whose predecessor is not the final proposal of the window before",
        });
    }
    if proposal.major() > implemented_major {
        return Err(NodeError::Refused {
            what: "a proposal under rules this machine does not implement",
        });
    }
    if proposal.protocol_version < predecessor.version() {
        return Err(NodeError::Refused {
            what: "a proposal whose rules roll back inside one chain",
        });
    }
    if proposal.final_beacon != decided.final_beacon
        || proposal.cement_aggregate != decided.cement_aggregate
        || proposal.cement_count != decided.cement_count
    {
        return Err(NodeError::Refused {
            what: "a proposal whose cement is not the one its certificate established",
        });
    }
    if let Some(roots) = roots {
        if (
            proposal.note_root,
            proposal.nullifier_root,
            proposal.record_root,
            proposal.machine_root,
            proposal.admitted_root,
            proposal.operations_root,
            proposal.roll,
            proposal.admitted_count,
            &proposal.census,
        ) != (
            roots.note_root,
            roots.nullifier_root,
            roots.record_root,
            roots.machine_root,
            roots.admitted_root,
            roots.operations_root,
            roots.roll,
            roots.admitted_count,
            &roots.census,
        ) {
            return Err(NodeError::Refused {
                what: "a proposal whose roots differ from the recomputed ones",
            });
        }
    }
    if proposal.suite_id != mt_net::SUITE {
        return Err(NodeError::Refused {
            what: "a proposal under an unsupported suite",
        });
    }
    let key: &[u8; mt_codec::size::SIGNING_PUBLIC_KEY] = proposal
        .runner_pubkey
        .as_slice()
        .try_into()
        .map_err(|_| NodeError::Refused {
            what: "a runner key of another width",
        })?;
    let signature: &[u8; mt_codec::size::SIGNATURE] = proposal
        .signature
        .as_slice()
        .try_into()
        .map_err(|_| NodeError::Refused {
            what: "a signature of another width",
        })?;
    let scope = proposal.signed_scope().map_err(NodeError::Object)?;
    mt_suite::sign::verify(
        &mt_suite::sign::PublicKey::from_bytes(*key),
        &scope,
        &mt_suite::sign::Signature::from_bytes(*signature),
    )
    .map_err(|_| NodeError::Refused {
        what: "a proposal under a signature that does not verify",
    })?;
    // The ticket: the electorate root, the digest of the key this proposal answers under, the
    // aggregate of the window two before and the threshold of the draw, in the order Canon states;
    // a proof lifted from another runner's proposal fails at the digest.
    let digest =
        Digest::of_bytes(&mt_derive::pulse::runner_digest(key)).ok_or(NodeError::Refused {
            what: "a digest that is no digest of the family",
        })?;
    let public = mt_proof::circuit::ticket::public_of(
        &[electorate.root, digest],
        aggregate_two_before,
        &draw_threshold.to_be_bytes(),
    );
    let description = mt_proof::circuit::ticket::description().ok_or(NodeError::Unprovable {
        what: "the description of a ticket",
    })?;
    mt_proof::scheme::verify(&description, &public, &proposal.ticket_proof).map_err(|_| {
        NodeError::Refused {
            what: "a proposal whose ticket proof does not verify",
        }
    })?;
    Ok(())
}

// Two consecutive final proposals: what an operator hands a joining device, and what a device that
// lived the network holds of its own past. Consensus, "The join".
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Anchor {
    pub earlier: Proposal,
    pub later: Proposal,
}

// One step of the walk: the certificate of the later proposal of the pair the walk stands on — the
// beacons and heavy attestations of the window after it — and the proposals found standing for that
// window. Several runners publish one decision under one name, and any one of them may hand bytes
// the door refuses under it — a final beacon outside the certificate, a signature that does not
// verify — so the walk judges each in turn and takes the first that stands: a runner publishing a
// refused copy of an honest decision stops no device.
pub struct Step<'a> {
    pub certificate: &'a [Round<'a>],
    pub pledges: &'a [Pledge],
    pub next: &'a [Proposal],
}

// The walk from an anchor to the head. Each step verifies the certificate of the later proposal of
// the pair against the electorate and the aggregate the earlier one carries, and judges the next
// proposal against them whole but for its roots; the next proposal is final when its own certificate
// verifies in the step after, and the head is the newest proposal whose certificate verified. What
// comes back is the pair the head forms with the proposal before it — the anchor of the next walk.
pub fn walk(
    anchor: &Anchor,
    steps: &[Step<'_>],
    chains: u64,
    draw_threshold: &mt_pulse::U256,
    implemented_major: u16,
) -> Result<Anchor, NodeError> {
    let mut earlier = anchor.earlier.clone();
    let mut later = anchor.later.clone();
    if earlier.window.checked_add(1) != Some(later.window)
        || later.previous != earlier.id().map_err(NodeError::Object)?
    {
        return Err(NodeError::Refused {
            what: "an anchor of two proposals that are not consecutive",
        });
    }
    let mut head = anchor.clone();
    let mut ahead: Option<Closure> = None;
    for (at, step) in steps.iter().enumerate() {
        let window = later.window.checked_add(1).ok_or(NodeError::Refused {
            what: "a window past the last one a count carries",
        })?;
        let electorate = Electorate::of(&earlier)?;
        let closure = match ahead.take() {
            Some(closure) => closure,
            None => verify_certificate(
                window,
                &electorate,
                Predecessor::Proposal(&later),
                &earlier.cement_aggregate,
                chains,
                step.certificate,
                step.pledges,
            )?,
        };
        head = Anchor {
            earlier: earlier.clone(),
            later: later.clone(),
        };
        // Where the certificate of the window after was handed in, the names its attestations attest:
        // a proposal under another name decided something else, and that certificate would refuse it
        // one step on.
        let after = steps.get(at + 1);
        let attested: Option<std::collections::BTreeSet<[u8; 32]>> = after.map(|after| {
            after
                .certificate
                .iter()
                .flat_map(|round| {
                    round
                        .heavy
                        .iter()
                        .flat_map(|held| held.attested.iter().copied())
                })
                .collect()
        });
        let mut taken: Option<&Proposal> = None;
        let mut refusal: Option<NodeError> = None;
        for candidate in step.next {
            if let Some(names) = &attested {
                if !candidate.id().is_ok_and(|id| names.contains(&id)) {
                    continue;
                }
            }
            // An attested name is not yet a decided one: a minority of the window after may attest a
            // name its agreement never decides, so the candidate taken is the one whose certificate
            // verifies in the step after (Consensus, "The join", 3), and that certificate is carried
            // into the step rather than verified twice.
            let judged = earlier
                .id()
                .map_err(NodeError::Object)
                .and_then(|two_before| {
                    decided_of(
                        &candidate.final_beacon,
                        &two_before,
                        step.certificate,
                        &closure,
                        &electorate,
                    )
                })
                .and_then(|decided| {
                    verify_successor(
                        candidate,
                        &Held {
                            predecessor: Predecessor::Proposal(&later),
                            decided: &decided,
                            electorate: &electorate,
                            aggregate_two_before: &earlier.cement_aggregate,
                            draw_threshold,
                            implemented_major,
                        },
                    )
                })
                .and_then(|()| match after {
                    Some(after) => verify_certificate(
                        window.checked_add(1).ok_or(NodeError::Refused {
                            what: "a window past the last one a count carries",
                        })?,
                        &Electorate::of(&later)?,
                        Predecessor::Proposal(candidate),
                        &later.cement_aggregate,
                        chains,
                        after.certificate,
                        after.pledges,
                    )
                    .map(Some),
                    None => Ok(None),
                });
            match judged {
                Ok(closure_after) => {
                    taken = Some(candidate);
                    ahead = closure_after;
                    break;
                }
                Err(why) => {
                    refusal.get_or_insert(why);
                }
            }
        }
        let Some(next) = taken else {
            // Nothing offered stands: a refusal is said, and where nothing was offered under the
            // attested name the head is where the walk stands.
            return match refusal {
                Some(why) => Err(why),
                None => Ok(head),
            };
        };
        earlier = later;
        later = next.clone();
    }
    Ok(head)
}
