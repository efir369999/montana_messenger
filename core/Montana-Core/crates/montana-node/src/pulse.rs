// The pulse of a window on a running machine: who runs it, what a round puts at its points, what a
// machine answers with, and when the window closes.
//
// **A round is made of waiting, and the waiting is the clock.** Nothing here measures time. A round
// closes when an answer arrives, and the machine that runs the chain publishes the next beacon; a
// machine that hears nothing publishes nothing and waits, which is what a pulse without a clock
// looks like from inside.
//
// **Everything crosses at points nobody chooses.** A beacon and the attestations answering it stand
// at the points of their round, a proposal at the points of its window, and every machine computes
// those sixteen bytes from the window, the chain, the round and the index alone. So a machine
// deposits without being told where and collects without asking anyone.

use crate::attest::{self, Standing};
use crate::certificate::{
    self, verify_proposal, Anchor, Decided, Electorate, Held, Predecessor, Roots,
};
use crate::runner::Runner;
use crate::{round, Machine, NodeError};
use mt_pulse::cement::Cement;
use mt_state::layout::{Ballot, Beacon, Census, Confirmation, LightAttestation, Proposal};
use mt_state::Layout;
use mt_wire::message::{self, Kind, POINT_BYTES};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, BTreeSet};

// Where a machine stands in the tree of admitted machines. The two travel together because they
// are one thing — what this machine is in that tree — and a door taking them apart would be a door
// a caller can hand two values that do not belong to one machine.
pub struct Branch {
    pub siblings: Vec<mt_proof::poseidon::Digest>,
    pub position: u64,
}

// The machines admitted to a window, and the tree they stand in. A cohort is built from the naming
// halves alone — the value a selection event writes into the tree of admitted machines — and every
// machine of it reaches the same root and its own branch without asking anybody, because the order
// is the ascending order of the halves and nothing else.
//
// **Where a cohort comes from is of the world and not of the set.** An opening cohort witnesses
// itself, which Consensus states, so the halves of it pass between operators exactly as an
// acquaintance does; a machine joining a running network takes them from the state a proposal
// carries. Neither is a value the Decree holds, and this is the one place either reaches the tree.
pub struct Cohort {
    // Ascending, which is the order the tree is built in and the order a position counts against.
    halves: Vec<[u8; 32]>,
    root: mt_proof::poseidon::Digest,
    leaves: Vec<mt_proof::poseidon::Digest>,
    empties: Vec<mt_proof::poseidon::Digest>,
}

impl Cohort {
    pub fn of(halves: &[[u8; 32]]) -> Result<Self, NodeError> {
        let depth = mt_proof::tree_depth();
        let mut held: Vec<[u8; 32]> = halves.to_vec();
        held.sort_unstable();
        held.dedup();
        let root = mt_proof::admitted::root_of(&held, depth).ok_or(NodeError::Refused {
            what: "a cohort the tree of admitted machines cannot hold",
        })?;
        let mut leaves = Vec::with_capacity(held.len());
        for half in &held {
            leaves.push(mt_proof::admitted::leaf(half).ok_or(NodeError::Refused {
                what: "a naming half that is not of the family",
            })?);
        }
        Ok(Self {
            halves: held,
            root,
            leaves,
            empties: mt_proof::admitted::empty_internals(depth),
        })
    }

    // The half a machine is named by in that tree, read off its own secret: it is derived and never
    // chosen, so a machine cannot stand anywhere but where its secret puts it.
    pub fn half_of(machine_secret: &[u8; 32]) -> [u8; 32] {
        mt_derive::nullifier::machine_halves(machine_secret).1
    }

    pub fn root(&self) -> mt_proof::poseidon::Digest {
        self.root
    }

    pub fn count(&self) -> u64 {
        self.halves.len() as u64
    }

    pub fn holds(&self, half: &[u8; 32]) -> bool {
        self.halves.binary_search(half).is_ok()
    }

    // The branch one machine walks. Every machine of the electorate weighs alike — the quorum is a
    // count of distinct parts against the count of the electorate — so a branch carries the place
    // and nothing about the machine but the place.
    pub fn branch_of(&self, machine_secret: &[u8; 32]) -> Option<Branch> {
        let half = Self::half_of(machine_secret);
        let position = self.halves.binary_search(&half).ok()?;
        // One sibling per level of the tree. The empties carry one more than that — the leaf's own
        // empty stands at the head of them — so the walk takes the depth and not the whole list.
        let depth = mt_proof::tree_depth();
        let mut siblings = Vec::with_capacity(depth);
        let mut level = self.leaves.clone();
        let mut index = position;
        for empty in self.empties.iter().take(depth) {
            siblings.push(level.get(index ^ 1).copied().unwrap_or(*empty));
            let mut next = Vec::with_capacity(level.len().div_ceil(2));
            for pair in level.chunks(2) {
                let right = pair.get(1).copied().unwrap_or(*empty);
                next.push(mt_proof::admitted::node(&pair[0], &right));
            }
            level = next;
            index >>= 1;
        }
        Some(Branch {
            siblings,
            position: position as u64,
        })
    }
}

// What one machine holds of the window it is in: what it answers with, the cement it has gathered,
// and the beacon it last saw.
pub struct Pulse {
    pub window: u64,
    pub chain: u8,
    pub standing: Standing,
    cement: Cement,
    pub round: u32,
    // What the beacon of this round links to by hash: the beacon of the round before, and at round
    // zero the identifier of the window before. It moves with every round.
    pub previous: [u8; 32],
    // What every attestation of this window attests beside the beacon of its round: the identifier
    // of the window before. It does not move — **one signature serves two duties**, the pulse of its
    // round and, once, the cement of the previous window, and the second duty is about the window.
    // The two stood in one field until a reading of the set put them apart, and in that one field
    // every attestation from the first round on attested the beacon it came from instead.
    of_the_window_before: [u8; 32],
    // Whether this machine already answered this window heavily. Its first attestation carries the
    // proof; every later one is light, and inherits the key already proven.
    answered_heavily: bool,
    // Only verified answers can authorize a round transition. These caches are
    // private so neither a count of cement nor an unverified caller can mint it.
    answered_beacons: BTreeSet<[u8; 32]>,
    // A cement checked before later heavy answers extend it remains a verified
    // version of this round. A signature alone never inserts an identifier here.
    reconciled_beacons: BTreeSet<[u8; 32]>,
    accepted_answers: BTreeSet<[u8; 32]>,
    proven_keys: BTreeMap<[u8; 32], Vec<u8>>,
    past_predecessors: BTreeMap<u32, [u8; 32]>,
    // The parts in the order they entered the cement. The cement only grows, so the set a beacon
    // was reconciled against is the first parts of this run — which is how a machine names the
    // exact set its final beacon carried, the tree of a census cement being folded over it.
    order: Vec<[u8; 32]>,
    // The count of the cement at the moment each beacon of the round was reconciled.
    reconciled_at: BTreeMap<[u8; 32], u64>,
    // The votes the verified ballots of the cement's parts cast, each part's at its largest, and the
    // ballots already judged, by the digest of their bytes: a proof is not cheaper the second time.
    ballots: BTreeMap<[u8; 32], u64>,
    judged: BTreeSet<[u8; 32]>,
    // This machine's own ballot of the window, and whether it has stood at the points yet.
    ballot: Option<Ballot>,
    ballot_stood: bool,
}

impl Pulse {
    // A machine entering a window: it draws what the window turns on once, and stands at the points
    // of the round it opens in.
    pub fn open(
        machine: &Machine,
        machine_secret: &[u8; 32],
        at: crate::Round,
        branch: &Branch,
        previous_proposal: [u8; 32],
        electorate: &Electorate,
        aggregate: &[u8; 32],
    ) -> Result<Self, NodeError> {
        let (window, chain, _) = at;
        machine.lock_predecessor(window, &previous_proposal)?;
        // Receive public evidence while constructing the expensive presence
        // proof. This changes no closed head and grants no signing authority.
        machine.enter_round(window, chain, 0)?;
        let standing =
            Standing::of_the_window(machine_secret, window, &branch.siblings, branch.position)?;
        // The ballot, where the electorate weighs and this machine's standing drew a vote: drawn
        // once a window, as the presence is, and out of what the machine kept of the census windows
        // it lived.
        let ballot = attest::ballot_of(
            machine_secret,
            window,
            electorate,
            aggregate,
            &machine.lived_census()?,
        )?;
        Ok(Self {
            window,
            chain,
            standing,
            cement: Cement::new(),
            round: 0,
            previous: previous_proposal,
            of_the_window_before: previous_proposal,
            answered_heavily: false,
            answered_beacons: BTreeSet::new(),
            reconciled_beacons: BTreeSet::new(),
            accepted_answers: BTreeSet::new(),
            proven_keys: BTreeMap::new(),
            past_predecessors: BTreeMap::new(),
            order: Vec::new(),
            reconciled_at: BTreeMap::new(),
            ballots: BTreeMap::new(),
            judged: BTreeSet::new(),
            ballot,
            ballot_stood: false,
        })
    }

    // Whether this machine runs this chain of this window. The ticket takes the machine's secret
    // and the cemented aggregate and nothing else — nobody chooses it, and every machine computes
    // its own without asking.
    pub fn runs_the_chain(
        machine_secret: &[u8; 32],
        aggregate: &[u8; 32],
        threshold: &mt_pulse::U256,
    ) -> bool {
        match mt_derive::aggregate::ticket(machine_secret, aggregate) {
            Some(ticket) => mt_pulse::clears(&ticket, threshold),
            // A secret whose spending half is no digest of the family draws no ticket: it is not
            // a machine of this protocol, and nothing it holds clears anything.
            None => false,
        }
    }

    // The cement this machine has gathered, as a beacon carries it: the aggregate over the parts
    // with the window as context, their count, and the votes the ballots of those parts cast. A
    // window that cemented nothing carries the aggregate of the empty set, which is a value of its
    // own and of its window.
    fn cement_state(&self) -> Result<([u8; 32], u64, u64), NodeError> {
        let aggregate = self
            .cement
            .aggregate(self.window)
            .map_err(|_| NodeError::Refused {
                what: "a cement the aggregation refuses",
            })?;
        Ok((aggregate, self.cement.count(), self.votes()?))
    }

    // The votes the verified ballots of the cement's parts cast, each part's once at its largest. A
    // ballot is held only for a part the cement holds, so the sum runs over the cement and nothing
    // beside it.
    pub fn votes(&self) -> Result<u64, NodeError> {
        certificate::sum_of_votes(self.ballots.values())
    }

    // The beacon the runner publishes to open a round: the window, the chain, the round, the
    // identifier of its predecessor and the cement it has gathered.
    pub fn beacon_of_this_round(&self) -> Result<Beacon, NodeError> {
        let (aggregate, count, votes) = self.cement_state()?;
        round::beacon(
            self.window,
            self.chain,
            self.round,
            self.previous,
            aggregate,
            (count, votes),
        )
        .map_err(|e| match e {
            round::RoundError::Object(e) => NodeError::Object(e),
            round::RoundError::Decree => NodeError::Decree {
                row: "consensus_replicas".to_string(),
            },
        })
    }

    // What this machine answers a beacon with, if it is drawn for that round. The first answer of a
    // window is heavy and carries the proof; every later one is light.
    pub fn answer(
        &mut self,
        machine_secret: &[u8; 32],
        beacon: &Beacon,
        aggregate: &[u8; 32],
        threshold: &mt_pulse::U256,
    ) -> Result<Option<Vec<u8>>, NodeError> {
        self.check_beacon(beacon)?;
        self.reconcile_beacon(beacon)?;
        if !self
            .standing
            .eligible(aggregate, beacon.chain, beacon.round, threshold)
        {
            return Ok(None);
        }
        let id = beacon.id().map_err(NodeError::Object)?;
        let bytes = if self.answered_heavily {
            self.standing
                .light(machine_secret, id, self.of_the_window_before)?
                .bytes()
                .map_err(NodeError::Object)?
        } else {
            let heavy = self
                .standing
                .heavy(machine_secret, id, self.of_the_window_before)?;
            self.answered_heavily = true;
            heavy.bytes().map_err(NodeError::Object)?
        };
        Ok(Some(bytes))
    }

    // What a runner does with a heavy attestation that arrived: verifies it as any far side does,
    // and enters its part into the cement at its first appearance. A repetition adds nothing and is
    // lawful, which is what the answer of `false` says.
    pub fn gather(
        &mut self,
        held: &Confirmation,
        admitted_root: &mt_proof::poseidon::Digest,
        aggregate: &[u8; 32],
        beacon: &Beacon,
        threshold: &mt_pulse::U256,
    ) -> Result<bool, NodeError> {
        self.gather_saying(held, admitted_root, aggregate, beacon, threshold, None)
    }

    // The same gathering, writing to the account of a machine why an attestation did not enter. The
    // wire tells whoever published nothing at all; the operator of this machine is told all of it.
    pub fn gather_saying(
        &mut self,
        held: &Confirmation,
        admitted_root: &mt_proof::poseidon::Digest,
        aggregate: &[u8; 32],
        beacon: &Beacon,
        threshold: &mt_pulse::U256,
        counts: Option<&crate::say::Counts>,
    ) -> Result<bool, NodeError> {
        if held.window != self.window {
            if let Some(counts) = counts {
                counts.raise(&counts.attestations_of_another_window);
            }
            return Err(NodeError::Refused {
                what: "an attestation of another window",
            });
        }
        let id = self.check_answer(held.window, &held.attested, beacon, true)?;
        // Remember a cement verified before this answer extends it. Missing data
        // must not prevent collecting the authenticated parts needed to check
        // that cement, but an unreconciled beacon cannot authorize advancement.
        if beacon.round == self.round {
            let _ = self.reconcile_beacon(beacon);
        }
        // A historical duplicate authorizes nothing in the current round.
        if beacon.round < self.round && self.cement.holds(&held.part_nullifier) {
            return Ok(false);
        }
        let fingerprint: [u8; 32] = Sha256::digest(held.bytes().map_err(NodeError::Object)?).into();
        if self.accepted_answers.contains(&fingerprint) {
            if let Some(counts) = counts {
                counts.raise(&counts.attestations_repeated);
            }
            return Ok(false);
        }
        if self
            .proven_keys
            .get(&held.part_nullifier)
            .is_some_and(|key| key != &held.answering_key)
        {
            return Err(NodeError::Refused {
                what: "a second answering key under one part-nullifier",
            });
        }
        if let Err(why) = attest::verify_heavy(
            held,
            admitted_root,
            aggregate,
            self.chain,
            beacon.round,
            threshold,
        ) {
            if let Some(counts) = counts {
                match &why {
                    NodeError::Refused { what } if what.contains("not drawn") => {
                        counts.raise(&counts.attestations_undrawn)
                    }
                    NodeError::Refused { what } if what.contains("signature") => {
                        counts.raise(&counts.attestations_unsigned)
                    }
                    NodeError::Refused { what } if what.contains("proof of presence") => {
                        counts.raise(&counts.attestations_unproven)
                    }
                    _ => counts.raise(&counts.attestations_refused),
                }
            }
            return Err(why);
        }
        let entered = self.cement.add(held.part_nullifier);
        if entered {
            self.order.push(held.part_nullifier);
        }
        self.proven_keys
            .entry(held.part_nullifier)
            .or_insert_with(|| held.answering_key.clone());
        if beacon.round == self.round {
            self.accepted_answers.insert(fingerprint);
            self.answered_beacons.insert(id);
        }
        if let Some(counts) = counts {
            if entered {
                counts.raise(&counts.attestations_entered);
            } else {
                counts.raise(&counts.attestations_repeated);
            }
        }
        Ok(entered)
    }

    // Light answers move the pulse, never the cement, and inherit a presence
    // verified in this window. A replay from another beacon cannot move this one.
    pub fn gather_light(
        &mut self,
        held: &LightAttestation,
        aggregate: &[u8; 32],
        beacon: &Beacon,
        threshold: &mt_pulse::U256,
    ) -> Result<bool, NodeError> {
        let id = self.check_answer(held.window, &held.attested, beacon, false)?;
        let _ = self.reconcile_beacon(beacon);
        let fingerprint: [u8; 32] = Sha256::digest(held.bytes().map_err(NodeError::Object)?).into();
        if self.accepted_answers.contains(&fingerprint) {
            return Ok(false);
        }
        let key = self
            .proven_keys
            .get(&held.part_nullifier)
            .ok_or(NodeError::Refused {
                what: "a light attestation before its proven heavy",
            })?;
        attest::verify_light(held, key, aggregate, self.chain, self.round, threshold)?;
        self.accepted_answers.insert(fingerprint);
        self.answered_beacons.insert(id);
        Ok(true)
    }

    fn check_beacon(&self, beacon: &Beacon) -> Result<[u8; 32], NodeError> {
        if (beacon.window, beacon.chain, beacon.round, beacon.previous)
            != (self.window, self.chain, self.round, self.previous)
        {
            return Err(NodeError::Refused {
                what: "a beacon outside this round's predecessor chain",
            });
        }
        beacon.id().map_err(NodeError::Object)
    }

    // Whether a beacon carries the cement this machine recomputed from what it holds: the pair of
    // the aggregate and the count, and not one of them alone — and votes no more than the ballots it
    // verified of those parts cast. A beacon carrying fewer is taken; it only delays its own close.
    fn matches_cement(&self, beacon: &Beacon) -> bool {
        match self.cement_state() {
            Ok((aggregate, count, votes)) => {
                beacon.cement_aggregate == aggregate
                    && beacon.cement_count == count
                    && beacon.cement_votes <= votes
            }
            Err(_) => false,
        }
    }

    fn reconcile_beacon(&mut self, beacon: &Beacon) -> Result<(), NodeError> {
        let id = self.check_beacon(beacon)?;
        if self.reconciled_beacons.contains(&id) || self.matches_cement(beacon) {
            self.reconciled_beacons.insert(id);
            let count = self.cement.count();
            self.reconciled_at.entry(id).or_insert(count);
            Ok(())
        } else {
            Err(NodeError::UnreconciledCement)
        }
    }

    // The exact set of parts a reconciled beacon carried, ascending: the first parts to enter this
    // machine's cement, as many as the cement held when the beacon was reconciled. Nothing for a
    // beacon this machine never reconciled.
    pub fn parts_of(&self, beacon: &Beacon) -> Option<Vec<[u8; 32]>> {
        let id = beacon.id().ok()?;
        let count = match self.reconciled_at.get(&id) {
            Some(count) => *count,
            None if self.matches_cement(beacon) => self.cement.count(),
            None => return None,
        };
        let count = usize::try_from(count).ok()?;
        let mut parts = self.order.get(..count)?.to_vec();
        parts.sort_unstable();
        Some(parts)
    }

    // A ballot that arrived: judged once against the electorate and the aggregate of the window, and
    // counted for its part at the largest count a ballot of that part casts. A ballot whose part is
    // not yet in the cement is passed over and judged when it is, since a ballot counts for a part of
    // the cement and for no other.
    pub fn gather_ballot(
        &mut self,
        held: &Ballot,
        electorate: &Electorate,
        aggregate: &[u8; 32],
    ) -> Result<bool, NodeError> {
        if held.window != self.window || !self.cement.holds(&held.part_nullifier) {
            return Ok(false);
        }
        let fingerprint: [u8; 32] = Sha256::digest(held.bytes().map_err(NodeError::Object)?).into();
        if !self.judged.insert(fingerprint) {
            return Ok(false);
        }
        let cast = attest::verify_ballot(held, self.window, electorate, aggregate)?;
        let standing = self.ballots.entry(held.part_nullifier).or_insert(0);
        let moved = cast > *standing;
        *standing = (*standing).max(cast);
        Ok(moved)
    }

    // This machine's own ballot, handed out once, after its heavy attestation: it stands at the points
    // of the round that heavy stood at.
    pub fn ballot_to_stand(&mut self) -> Result<Option<Vec<u8>>, NodeError> {
        if self.ballot_stood || !self.answered_heavily {
            return Ok(None);
        }
        let Some(ballot) = &self.ballot else {
            return Ok(None);
        };
        self.ballot_stood = true;
        Ok(Some(ballot.bytes().map_err(NodeError::Object)?))
    }

    fn check_answer(
        &self,
        window: u64,
        attested: &[[u8; 32]],
        beacon: &Beacon,
        historical: bool,
    ) -> Result<[u8; 32], NodeError> {
        let id = if historical && beacon.round < self.round {
            if beacon.window != self.window
                || beacon.chain != self.chain
                || self.past_predecessors.get(&beacon.round) != Some(&beacon.previous)
            {
                return Err(NodeError::Refused {
                    what: "a historical beacon outside the verified predecessor chain",
                });
            }
            beacon.id().map_err(NodeError::Object)?
        } else {
            self.check_beacon(beacon)?
        };
        let mut expected = [id, self.of_the_window_before];
        expected.sort_unstable();
        if window != self.window || attested != expected || id == self.of_the_window_before {
            return Err(NodeError::Refused {
                what: "an attestation outside this beacon and previous proposal",
            });
        }
        Ok(id)
    }

    pub fn can_advance(&self, beacon: &Beacon) -> bool {
        self.check_beacon(beacon).is_ok_and(|id| {
            self.answered_beacons.contains(&id)
                && (self.reconciled_beacons.contains(&id) || self.matches_cement(beacon))
        })
    }

    // Whether this window closes on what this machine holds: the count of distinct parts of the
    // electorate in its cement against the count of the electorate, by the integer rule of the set.
    // Every machine of the window makes this count from what it holds, and a runner is one of them:
    // it assembles the proposal when the count stands and not before, and a proposal assembled
    // below it is refused by every machine that counts. Both counts are public and name nobody.
    pub fn attempts_the_close(&self, admitted: u64) -> Result<bool, NodeError> {
        let held = u128::try_from(self.living()).map_err(|_| NodeError::Refused {
            what: "a count of attestations past what a number carries",
        })?;
        mt_pulse::close::closes(held, u128::from(admitted), u64::from(self.round)).map_err(|_| {
            NodeError::Decree {
                row: "confirmation_quorum".to_string(),
            }
        })
    }

    // The same rule over counts handed in, so a verifier of a certificate and a runner of a window
    // read the close out of one place.
    pub fn closes(&self, cemented: u128, electorate: u128) -> Result<bool, NodeError> {
        mt_pulse::close::closes(cemented, electorate, u64::from(self.round)).map_err(|_| {
            NodeError::Decree {
                row: "confirmation_quorum".to_string(),
            }
        })
    }

    // How many machines the cement names: the count of the living, which the issuance of the
    // window multiplies the worth of its right by, and a count of distinct part-nullifiers and of
    // nothing else.
    pub fn living(&self) -> usize {
        self.cement.count() as usize
    }

    // Moving to the next round: the beacon of this one becomes the predecessor of the next, and the
    // machine stands at the points of the round it moves into.
    // **Only the link of the beacon moves.** What an attestation attests beside the beacon of its
    // round is the identifier of the window before, and that is a fact about the window rather than
    // about the round — a machine that advanced it with the rounds would attest the beacon it came
    // from instead, and every attestation after the first round would confirm nothing of the window
    // whose cement it is entering.
    pub fn advance(&mut self, machine: &Machine, beacon: &Beacon) -> Result<(), NodeError> {
        let previous = self.check_beacon(beacon)?;
        self.reconcile_beacon(beacon)?;
        if !self.answered_beacons.contains(&previous) {
            return Err(NodeError::Refused {
                what: "a round without a verified answer cannot advance",
            });
        }
        let next = self.round.checked_add(1).ok_or(NodeError::Refused {
            what: "a round past the last one a count carries",
        })?;
        machine.enter_round(self.window, self.chain, next)?;
        self.past_predecessors.insert(self.round, self.previous);
        self.previous = previous;
        self.round = next;
        self.answered_beacons.clear();
        self.reconciled_beacons.clear();
        self.reconciled_at.clear();
        self.accepted_answers.clear();
        Ok(())
    }
}

// What a machine lived of one window: the rounds it stood, the machines the window's cement named,
// the right that window minted to it — none where its own part is not among the parts the window
// decided, since a machine whose attestation did not enter the cement did not live the window —
// and the identifier of the proposal the window closed under, the one value of the window the next
// one stands on.
pub struct Lived {
    pub window: u64,
    pub rounds: u32,
    pub living: usize,
    pub right: Option<attest::Right>,
    pub proposal: [u8; 32],
}

// How long a machine holds still before asking its acquaintances again what stands at a point.
//
// **It measures nothing of the protocol.** A round closes when an answer arrives and not when a
// clock says so; this is only how often a machine asks. Nothing of consensus turns on its length,
// and a machine that asked twice as often or half as often would cement the same windows.
const ASKS_AGAIN_AFTER: std::time::Duration = std::time::Duration::from_millis(25);

pub use mt_pulse::WAITS_UP_TO;

// The chain a machine of an opening cohort runs: the first of the ones the cascade entitles. It is
// declared where the pulse's numbers are declared.
use mt_pulse::{CARRIES_WITHIN, OPENING_CHAIN, REACHES_AGAIN_EVERY, SAYS_EVERY};

// **An acquaintance that did not answer at the start is dialled again until it does.** Two machines
// of one cohort cannot both find the other listening when each starts, so the one started first
// dials into nothing; a machine that never dials again holds no link of its own, can be written into
// and never ask, and the first window it falls one behind in is a window it never leaves — which is
// how one host stood in window 1 while the other waited in window 2 (06.10.2026). It dials on a
// thread of its own and says when the link stands; a link held is used by every asking after it,
// since what a machine asks over is read from what it holds at the moment it asks.
pub fn reach_again(machine: std::sync::Arc<Machine>, line: String) {
    std::thread::spawn(move || loop {
        std::thread::sleep(ASKS_AGAIN_AFTER * REACHES_AGAIN_EVERY);
        if machine.reach_and_hold(&line).is_ok() {
            println!("connection restored");
            return;
        }
    });
}

// The chain a cohort that witnesses itself opens on, for a caller that must stand at its points
// before the pulse begins.
pub fn opening_chain() -> u8 {
    OPENING_CHAIN
}

// The bodies standing at every point of one round, taken as the two kinds a round carries. What
// tells them apart is the width a body comes back at, which differs between the two objects and is
// derived from the Decree rather than declared here.
#[derive(Default)]
struct RoundObjects {
    beacons: Vec<Beacon>,
    heavy: Vec<Confirmation>,
    light: Vec<LightAttestation>,
    ballots: Vec<Ballot>,
}

fn of_the_round(
    machine: &Machine,
    window: u64,
    chain: u8,
    round: u32,
) -> Result<RoundObjects, NodeError> {
    read_the_round(machine, window, chain, round, false)
}

// The same reading by a device walking the past: what the acquaintances hold, held nowhere.
fn walked_round(
    machine: &Machine,
    window: u64,
    chain: u8,
    round: u32,
) -> Result<RoundObjects, NodeError> {
    read_the_round(machine, window, chain, round, true)
}

fn read_the_round(
    machine: &Machine,
    window: u64,
    chain: u8,
    round: u32,
    walking: bool,
) -> Result<RoundObjects, NodeError> {
    let points = round::points_of_round(window, chain, round).map_err(|_| NodeError::Decree {
        row: "consensus_replicas".to_string(),
    })?;
    let of_beacon =
        mt_wire::message::body_len(Beacon::expected_len()).map_err(|_| NodeError::Decree {
            row: "chunk_bytes".to_string(),
        })?;
    let of_answer = mt_wire::message::body_len(Confirmation::expected_len()).map_err(|_| {
        NodeError::Decree {
            row: "chunk_bytes".to_string(),
        }
    })?;
    let of_light = mt_wire::message::body_len(LightAttestation::expected_len()).map_err(|_| {
        NodeError::Decree {
            row: "chunk_bytes".to_string(),
        }
    })?;
    let of_ballot =
        mt_wire::message::body_len(Ballot::expected_len()).map_err(|_| NodeError::Decree {
            row: "chunk_bytes".to_string(),
        })?;
    let mut objects = RoundObjects::default();
    for point in &points {
        let bodies = if walking {
            machine.collect_public(point, window)?
        } else {
            machine.objects_at_the_point(point, window)?
        };
        for body in bodies {
            // Padding can put several object types in one wire length. Parse
            // each candidate independently; its context and signature decide.
            if body.len() == of_beacon {
                if let Ok(held) = Beacon::parse(&body[..Beacon::expected_len()]) {
                    if (held.window, held.chain, held.round) == (window, chain, round)
                        && !objects
                            .beacons
                            .iter()
                            .any(|one| one.id().ok() == held.id().ok())
                    {
                        objects.beacons.push(held);
                    }
                }
            }
            if body.len() == of_answer {
                if let Ok(held) = Confirmation::parse(&body[..Confirmation::expected_len()]) {
                    if held.window == window {
                        objects.heavy.push(held);
                    }
                }
            }
            if body.len() == of_light {
                if let Ok(held) = LightAttestation::parse(&body[..LightAttestation::expected_len()])
                {
                    if held.window == window {
                        objects.light.push(held);
                    }
                }
            }
            if body.len() == of_ballot {
                if let Ok(held) = Ballot::parse(&body[..Ballot::expected_len()]) {
                    if held.window == window && !objects.ballots.contains(&held) {
                        objects.ballots.push(held);
                    }
                }
            }
        }
    }
    Ok(objects)
}

// An object of a round put at every point of it. The set carries one object three times so that no
// round depends on one holder being willing.
fn stand_at_the_round(
    machine: &Machine,
    window: u64,
    chain: u8,
    round: u32,
    object: &[u8],
) -> Result<(), NodeError> {
    let points = round::points_of_round(window, chain, round).map_err(|_| NodeError::Decree {
        row: "consensus_replicas".to_string(),
    })?;
    for point in &points {
        machine.publish_at_the_point(point, window, object)?;
    }
    Ok(())
}

// The pulse of a running machine, from the terminal an operator started it at. It enters a window,
// stands at the points of its rounds, publishes a beacon of every round it runs the chain of and
// answers every beacon it sees, gathers what verifies into its cement, and closes the window when
// the cement reaches the share — taking the right that window mints. Then the next window.
//
// A verified answer advances a round. The polling delay only schedules reads.
// `patience` bounds this invocation: exhausting it returns an operator error,
// preserving the round and its cement. It cannot manufacture a successor.
// The window closes through the one door of `certificate.rs`: what it decided and the proposal
// carrying it are judged there, and the head moves only onto a proposal the next cement finalized.
// **What a machine does of its own inside a window, and why it cannot be done after one.** A frame
// stands at the points of the round its slot names, and a machine holds those points only while it
// stands in that round: the moment its window closes it releases them. So an errand run after the
// window — a right redeemed, a payment made — publishes into points nobody holds any more, and the
// only machine that takes it is one still lagging in the window the payer already left. It is run
// here instead: the machine has entered the round and has not yet attested, so every other machine
// is still standing where the frame lands and applies it before the cement it is waiting on
// completes.
pub type Errand<'a> = &'a dyn Fn(&Machine, u64) -> Result<(), NodeError>;

// Freeze the end of each historical sweep. Taking the cursor modulo the live
// round starves old points when that round grows at least once per read: the
// cursor chases the tip forever and never sees a late first-round proof.
// This schedules reads only. It grants no authority to advance or close.
#[derive(Default)]
struct HistoricalRounds {
    next: u32,
    end: u32,
}

impl HistoricalRounds {
    fn next(&mut self, current: u32) -> Option<u32> {
        if current == 0 {
            return None;
        }
        if self.next >= self.end || self.end > current {
            self.next = 0;
            self.end = current;
        }
        let at = self.next;
        // at < end <= current <= u32::MAX, including the last possible round.
        self.next += 1;
        Some(at)
    }
}

pub fn live(
    machine: &Machine,
    cohort: &Cohort,
    from: u64,
    windows: u64,
    patience: u32,
) -> Result<Vec<Lived>, NodeError> {
    live_doing(machine, cohort, from, windows, patience, None)
}

pub fn live_doing(
    machine: &Machine,
    cohort: &Cohort,
    from: u64,
    windows: u64,
    patience: u32,
    errand: Option<Errand<'_>>,
) -> Result<Vec<Lived>, NodeError> {
    let counts = machine.counts();
    let secret = machine.machine_secret()?;
    let mut of_the_machine = [0u8; 32];
    of_the_machine.copy_from_slice(&secret[..32]);
    machine.admits(cohort.count())?;
    // And the value plane of this machine stands against the same tree its pulse does, so a frame
    // proving a machine is among the admitted is verified against the tree that admitted it.
    machine.admits_the_tree(cohort.root())?;
    // **Two thresholds, because they are two questions.** The draw asks who may run a window, and
    // its threshold is the width at every window, so every machine of the electorate may and the
    // ticket only orders them; a round asks who answers it and is computed from the count of the
    // electorate, so that the crowd of a round never falls below the floor the Decree names and no
    // round is ever one nobody was drawn for.
    let of_the_draw = mt_pulse::retarget::draw_threshold().map_err(|_| NodeError::Decree {
        row: "hash_bytes".to_string(),
    })?;
    let branch = cohort
        .branch_of(&of_the_machine)
        .ok_or(NodeError::Refused {
            what: "a machine that stands in no cohort of this window",
        })?;
    // **What a window stands on is two proposals and nothing else.** The proposal of the window
    // before is what the open window cements and what its round zero links to; the proposal of the
    // window two before fixed the electorate and the aggregate the open window draws from. A machine
    // holds those two and lets the older go, and what it keeps of them beyond is the store's.
    let mut stands_on: BTreeMap<u64, Proposal> = BTreeMap::new();
    let mut out = Vec::new();
    for step in 0..windows {
        let window = from.checked_add(step).ok_or(NodeError::Refused {
            what: "a window past the last one a count carries",
        })?;
        // The electorate of a window is the admitted set of the proposal two before it, and the
        // aggregate it draws from is that proposal's cement. An opening cohort stands for the first
        // two windows a machine lives, and the aggregate of no signers is what the set freezes for a
        // window with nothing cemented two before it.
        let two_before = window.checked_sub(2).and_then(|at| stands_on.get(&at));
        let (electorate, aggregate) = match two_before {
            Some(proposal) => (Electorate::of(proposal)?, proposal.cement_aggregate),
            None => (
                Electorate::opening(cohort.root(), cohort.count(), window)?,
                mt_derive::aggregate::aggregate(&[], window).map_err(|_| NodeError::Refused {
                    what: "an aggregate over a repeated identity",
                })?,
            ),
        };
        if electorate.root != cohort.root() {
            return Err(NodeError::Refused {
                what: "an electorate whose tree this machine holds no branch of",
            });
        }
        let of_a_round =
            mt_pulse::retarget::round_threshold(electorate.count, 1).map_err(|_| {
                NodeError::Decree {
                    row: "round_floor".to_string(),
                }
            })?;
        let predecessor = match window.checked_sub(1).and_then(|at| stands_on.get(&at)) {
            Some(proposal) => Predecessor::Proposal(proposal),
            None => Predecessor::Genesis,
        };
        let mut pulse = Pulse::open(
            machine,
            &of_the_machine,
            (window, OPENING_CHAIN, 0),
            &branch,
            predecessor.id()?,
            &electorate,
            &aggregate,
        )?;
        // The errand of this machine, done in the first window it lives and before it attests
        // anything of that window.
        if step == 0 {
            if let Some(errand) = errand {
                errand(machine, window)?;
            }
        }
        let runs = Pulse::runs_the_chain(&of_the_machine, &aggregate, &of_the_draw);
        let mut history = HistoricalRounds::default();
        let last: Beacon = loop {
            if runs {
                let beacon = pulse.beacon_of_this_round()?;
                let bytes = beacon.bytes().map_err(NodeError::Object)?;
                stand_at_the_round(machine, window, OPENING_CHAIN, pulse.round, &bytes)?;
            }
            let mut waited = 0;
            let beacons = loop {
                let mut arrived = of_the_round(machine, window, OPENING_CHAIN, pulse.round)?;
                arrived
                    .beacons
                    .retain(|beacon| pulse.check_beacon(beacon).is_ok());
                if !arrived.beacons.is_empty() {
                    break arrived.beacons;
                }
                waited += 1;
                if waited >= patience {
                    return Err(NodeError::Refused {
                        what: "a round no beacon ever stood at",
                    });
                }
                std::thread::sleep(ASKS_AGAIN_AFTER);
            };
            // **Every machine gathers, and not the runner alone.** A window is finalized on
            // confirmations reaching the quorum, and a machine that waited to be told would be
            // taking somebody's word for a cement it can verify itself. What arrives is verified as
            // any far side verifies it, and folded at its first appearance; a repetition adds
            // nothing and is lawful.
            let mut waited = 0;
            let mut seen: Vec<[u8; 32]> = Vec::new();
            let mut answers_seen;
            // What this machine last said it held, so that a change is what makes it speak.
            let mut said = (usize::MAX, usize::MAX, usize::MAX, usize::MAX);
            let mut ordered = beacons;
            let closed = loop {
                let mut unreconciled = 0;
                // **A version that arrives after this machine answered still gets an answer.** A
                // machine answers every valid version of a round it sees, and the versions of a
                // round do not all arrive at once; a machine that read the beacons once and then
                // only gathered would leave the slower runner unanswered for the whole round.
                for beacon in &ordered {
                    let id = beacon.id().map_err(NodeError::Object)?;
                    if seen.contains(&id) {
                        continue;
                    }
                    match pulse.answer(&of_the_machine, beacon, &aggregate, &of_a_round) {
                        Ok(answer) => {
                            seen.push(id);
                            if let Some(bytes) = answer {
                                stand_at_the_round(
                                    machine,
                                    window,
                                    OPENING_CHAIN,
                                    pulse.round,
                                    &bytes,
                                )?;
                            }
                            // The ballot stands beside the heavy attestation, at the points of
                            // the same round, once.
                            if let Some(bytes) = pulse.ballot_to_stand()? {
                                stand_at_the_round(
                                    machine,
                                    window,
                                    OPENING_CHAIN,
                                    pulse.round,
                                    &bytes,
                                )?;
                            }
                        }
                        // Retry after gathering. A version with missing leaves
                        // has not been answered and must not enter `seen`.
                        Err(NodeError::UnreconciledCement) => unreconciled += 1,
                        Err(error) => return Err(error),
                    }
                }
                let mut arrived = of_the_round(machine, window, OPENING_CHAIN, pulse.round)?;
                arrived
                    .beacons
                    .retain(|beacon| pulse.check_beacon(beacon).is_ok());
                ordered = arrived.beacons;
                answers_seen = arrived.heavy.len() + arrived.light.len();
                for beacon in &ordered {
                    for held in &arrived.heavy {
                        let _ = pulse.gather_saying(
                            held,
                            &electorate.root,
                            &aggregate,
                            beacon,
                            &of_a_round,
                            Some(&counts),
                        );
                    }
                    for held in &arrived.light {
                        let _ = pulse.gather_light(held, &aggregate, beacon, &of_a_round);
                    }
                }
                // The ballots of the parts the cement holds: each judged once, and counted for its
                // part at the largest count a ballot of that part casts.
                for held in &arrived.ballots {
                    let _ = pulse.gather_ballot(held, &electorate, &aggregate);
                }
                // Round completion does not end the window's cement collection.
                // Revisit one historical round per read so a late heavy answer
                // can establish the key used by current light answers.
                if let Some(at) = history.next(pulse.round) {
                    let past = of_the_round(machine, window, OPENING_CHAIN, at)?;
                    for beacon in &past.beacons {
                        for held in &past.heavy {
                            let _ = pulse.gather_saying(
                                held,
                                &electorate.root,
                                &aggregate,
                                beacon,
                                &of_a_round,
                                Some(&counts),
                            );
                        }
                    }
                    for held in &past.ballots {
                        let _ = pulse.gather_ballot(held, &electorate, &aggregate);
                    }
                }
                // **A window closes on a beacon that carries the quorum.** The count every machine
                // closes on is the one a beacon carries, so that every machine closing a window
                // closes it on one value: a beacon of this round whose carried count reaches the
                // quorum share of the electorate, which this machine reconciled against what it
                // holds and which a verified attestation answered. Consensus, "The beacon a window
                // closes on".
                if ordered.iter().any(|beacon| {
                    pulse.can_advance(beacon) && carries_the_quorum(beacon, &electorate)
                }) {
                    break true;
                }
                if ordered.iter().any(|beacon| pulse.can_advance(beacon)) {
                    break false;
                }
                waited += 1;
                if waited >= patience {
                    return Err(NodeError::Refused {
                        what: "waiting budget exhausted without a verified answer; round unchanged",
                    });
                }
                // **The account is written while the machine waits, and not only when it moves.** A
                // round is made of waiting, so a machine that spoke once a round would be silent for
                // as long as the waiting lasts — which is exactly the stretch an operator needs to
                // see into. It speaks when what it holds changes, and again while nothing does: the
                // **sequence of arrivals** — every time the cement grows or a new attestation
                // stands — and, while nothing arrives, a heartbeat that says so.
                let held = (pulse.living(), answers_seen, ordered.len(), unreconciled);
                if held != said || waited % SAYS_EVERY == 0 {
                    said = held;
                    println!(
                        "window {} round {} waiting: cement {} of {}, beacons {}, standing {}, unreconciled cement {} | {}",
                        window,
                        pulse.round,
                        held.0,
                        electorate.count,
                        held.2,
                        held.1,
                        held.3,
                        counts.line()
                    );
                }
                std::thread::sleep(ASKS_AGAIN_AFTER);
            };
            // Two versions of one round are resolved by the smaller identifier, which is the rule
            // the set states for two clearings of one height; a closing round chooses among the
            // versions carrying the quorum.
            ordered.retain(|one| {
                pulse.can_advance(one) && (!closed || carries_the_quorum(one, &electorate))
            });
            ordered.sort_by_key(|one| one.id().unwrap_or([0xFFu8; 32]));
            let taken = ordered.first().cloned().ok_or(NodeError::Refused {
                what: "a round whose beacons vanished between two readings",
            })?;
            // **The frames of a round apply as the machine leaves it**, in ascending order of their
            // identifiers: Canon, "The roots of state". A machine that applied each as it arrived
            // would order one round's frames by the order of its own deliveries, and two machines
            // would carry two roots for one window. What arrived in the same breath as the close is
            // applied before the machine leaves for the same reason: a frame published inside a
            // window stands at the very points the attestation completing the cement stands at.
            let _ = machine.apply_what_stands();
            if closed {
                break taken;
            }
            // **A machine that stands at a round says everything it did in it.** The count it is
            // waiting on, and beside it the whole account of this machine's own doings — what it
            // took and what it refused and for which reason, what it published and pushed, what it
            // asked for and pulled, what it read back and what it read of its own memory, and what
            // entered its cement and what did not and why. Every one of them names nobody.
            println!(
                "window {} round {}: cement {} of {}, beacons {}, standing {} | {}",
                window,
                pulse.round,
                pulse.living(),
                electorate.count,
                ordered.len(),
                answers_seen,
                counts.line()
            );
            pulse.advance(machine, &taken)?;
        };
        // **What the window decided, and the proposal that carries it.** The final beacon's pair is
        // the cement of the window; the roots are recomputed from the plane as the window left it;
        // and the proposal this machine takes is the one under the identifier it computed itself,
        // judged at the one door whoever proved it.
        let decided = Decided::of_beacon(&last, &electorate)?;
        // The parts the window decided, exactly: those the final beacon carried when this machine
        // reconciled it. They are what a census window folds the tree of its cement over, and what
        // says whether this machine lived the window at all.
        let decided_parts = pulse.parts_of(&last).ok_or(NodeError::Refused {
            what: "a final beacon this machine never reconciled",
        })?;
        let own_part = pulse.standing.part_nullifier;
        let lived_it = decided_parts.binary_search(&own_part).is_ok();
        let depth = mt_proof::tree_depth();
        let mut own_census = Census {
            root: mt_proof::cement::empty_root().bytes(),
            count: decided.cement_count,
        };
        let censused = mt_pulse::standing::is_census(window).map_err(|_| NodeError::Decree {
            row: "census_interval".to_string(),
        })?;
        if censused {
            let root =
                mt_proof::cement::root_of(&decided_parts, depth).ok_or(NodeError::Refused {
                    what: "a cement the tree of a cement cannot hold",
                })?;
            own_census.root = root.bytes();
            if lived_it {
                if let Some((siblings, position)) =
                    mt_proof::cement::branch_of(&decided_parts, &own_part, depth)
                {
                    machine.record_census(attest::LivedCensus {
                        window,
                        root: root.bytes(),
                        siblings,
                        position,
                    })?;
                }
            }
        }
        // The census this window's proposal carries: the one before it, with this window's own
        // cement entering first where this is a census window.
        let previous_census = match predecessor {
            Predecessor::Proposal(before) => before.census.clone(),
            Predecessor::Genesis => certificate::empty_census()?,
        };
        let mut roots = machine.value()?.roots(cohort, window)?;
        roots.census =
            mt_pulse::standing::carried(&previous_census, window, own_census).map_err(|_| {
                NodeError::Decree {
                    row: "standing_censuses".to_string(),
                }
            })?;
        let held = Held {
            predecessor,
            decided: &decided,
            electorate: &electorate,
            aggregate_two_before: &aggregate,
            draw_threshold: &of_the_draw,
            implemented_major: mt_state::implemented_major(),
        };
        let proposal = take_the_proposal(
            machine,
            &of_the_machine,
            &branch,
            runs,
            &held,
            &roots,
            patience,
        )?;
        // **The cement of this window made the proposal before it final**, and the head moves onto
        // it now. The proposal of this window is kept before anything points at it, and is final
        // when the cement of the next window reaches the quorum on it.
        if let Predecessor::Proposal(before) = predecessor {
            machine.finalize(before.window)?;
        }
        machine.keep_proposal(&proposal)?;
        let id = proposal.id().map_err(NodeError::Object)?;
        let living = usize::try_from(decided.cement_count).map_err(|_| NodeError::Refused {
            what: "a count of the living past what a number carries",
        })?;
        // How many rounds this window ran, the one it closed at among them: rounds are counted
        // from zero, and a window that closed in its round zero has run one. It is the one count
        // the worth of the window's right reads, and this machine ran one chain of it; a window
        // of more chains is worth the rounds of every one of them, which this machine does not
        // hold, so it refuses rather than pricing the whole window by its own part of it.
        let rounds = pulse.round.checked_add(1).ok_or(NodeError::Refused {
            what: "a round past the last one a count carries",
        })?;
        let right = if lived_it {
            let chains = mt_derive::tag::chains_at(window).ok_or(NodeError::Decree {
                row: "k_step".to_string(),
            })?;
            if chains != 1 {
                return Err(NodeError::Refused {
                    what: "a window of more chains than the one this machine ran",
                });
            }
            Some(attest::right_of(
                &of_the_machine,
                window,
                u64::from(rounds),
            )?)
        } else {
            None
        };
        let lived = Lived {
            window,
            rounds,
            living,
            right,
            proposal: id,
        };
        // **A window closed is said when it closes.** A machine living until it is stopped returns
        // nothing, so what it lived written only at the return is written never, and an operator
        // watching a chain that moves sees a machine that says nothing. The identifier the next
        // window carries back is said with it: it is the one value of this window the next one
        // stands on.
        let link: String = id.iter().map(|b| format!("{b:02x}")).collect();
        match &lived.right {
            Some(right) => println!(
                "window {} closed after {} rounds on a cement naming {} machines and casting {} votes; the next links to the proposal {} | it mints {} to this machine, accepted in window {}",
                lived.window, lived.rounds, lived.living, decided.cement_votes, link, right.worth, right.accepted_in
            ),
            None => println!(
                "window {} closed after {} rounds on a cement naming {} machines and casting {} votes; the next links to the proposal {} | this machine's part is not in that cement, so it took no right of it",
                lived.window, lived.rounds, lived.living, decided.cement_votes, link
            ),
        }
        out.push(lived);
        stands_on.insert(window, proposal);
        stands_on.retain(|at, _| at.saturating_add(1) >= window);
    }
    Ok(out)
}

// Whether a beacon carries a cement at the quorum share of the electorate and votes at the quorum
// share of its committee, by the integer rules of Canon. A count the rules cannot compare carries
// nothing.
fn carries_the_quorum(beacon: &Beacon, electorate: &Electorate) -> bool {
    mt_pulse::close::closes_window(
        u128::from(beacon.cement_count),
        u128::from(electorate.count),
        u128::from(beacon.cement_votes),
        u128::from(electorate.committee.expected),
    )
    .unwrap_or(false)
}

// The proposal of this window under the identifier this machine recomputed. A runner of the window
// proves its own unless a proposal of that identifier already stands verified at the window's
// points — two runners of one decision publish one identifier, so one proof serves the window — and
// a machine whose ticket does not clear takes a runner's. Whatever it takes it judges at the one
// door, its own proof included.
//
// **The ticket orders the runners, and nobody is told the order.** Canon, "The threshold of the
// draw": every machine of the electorate clears the width, so before it proves its own a machine
// waits the share of `CARRIES_WITHIN` its ticket stands at, taking whatever proposal of its decision
// stands verified meanwhile. The lowest ticket usually carries the decision first and alone.
fn take_the_proposal(
    machine: &Machine,
    machine_secret: &[u8; 32],
    branch: &Branch,
    runs: bool,
    held: &Held<'_>,
    roots: &Roots,
    patience: u32,
) -> Result<Proposal, NodeError> {
    let window = held.decided.window;
    let expected = certificate::decided_identifier(held, roots)?;
    let mut refused: BTreeSet<[u8; 32]> = BTreeSet::new();
    if let Some(found) = standing_proposal(machine, window, &expected, held, roots, &mut refused)? {
        return Ok(found);
    }
    for _ in 0..carries_after(machine_secret, held.aggregate_two_before) {
        std::thread::sleep(ASKS_AGAIN_AFTER);
        if let Some(found) =
            standing_proposal(machine, window, &expected, held, roots, &mut refused)?
        {
            return Ok(found);
        }
    }
    if runs {
        if let Some(runner) = Runner::of_the_window(
            machine_secret,
            window,
            &branch.siblings,
            branch.position,
            held.aggregate_two_before,
            held.draw_threshold,
        )? {
            let own = runner.propose(
                mt_state::PROTOCOL_VERSION,
                held.predecessor,
                roots,
                held.decided,
            )?;
            verify_proposal(&own, held, roots)?;
            let bytes = own.bytes().map_err(NodeError::Object)?;
            stand_at_the_window(machine, window, &bytes)?;
            return Ok(own);
        }
    }
    let mut waited = 0;
    loop {
        if let Some(found) =
            standing_proposal(machine, window, &expected, held, roots, &mut refused)?
        {
            return Ok(found);
        }
        waited += 1;
        if waited >= patience {
            return Err(NodeError::Refused {
                what: "a window no proposal of its decision ever stood at",
            });
        }
        std::thread::sleep(ASKS_AGAIN_AFTER);
    }
}

// The askings a machine waits before it proves its own proposal: the share of `CARRIES_WITHIN` its
// ticket stands at, read off the ticket's leading bytes. A secret that draws no ticket waits nothing.
fn carries_after(machine_secret: &[u8; 32], aggregate: &[u8; 32]) -> u32 {
    let Some(ticket) = mt_derive::aggregate::ticket(machine_secret, aggregate) else {
        return 0;
    };
    let lead = u64::from(u16::from_be_bytes([ticket[0], ticket[1]]));
    u32::try_from((lead * u64::from(CARRIES_WITHIN)) >> u16::BITS).unwrap_or(CARRIES_WITHIN)
}

// A proposal standing at the points of the window under the expected identifier, verified whole. A
// proposal refused once is not judged again: its bytes are remembered, and a proof is not cheaper to
// refuse the second time.
fn standing_proposal(
    machine: &Machine,
    window: u64,
    expected: &[u8; 32],
    held: &Held<'_>,
    roots: &Roots,
    refused: &mut BTreeSet<[u8; 32]>,
) -> Result<Option<Proposal>, NodeError> {
    for candidate in proposals_at_the_window(machine, window, false)? {
        if candidate.id().ok() != Some(*expected) {
            continue;
        }
        let bytes = candidate.bytes().map_err(NodeError::Object)?;
        let fingerprint: [u8; 32] = Sha256::digest(&bytes).into();
        if refused.contains(&fingerprint) {
            continue;
        }
        if verify_proposal(&candidate, held, roots).is_ok() {
            return Ok(Some(candidate));
        }
        refused.insert(fingerprint);
    }
    Ok(None)
}

// The proposals standing at the points of a window, distinct by their bytes. A machine of the window
// reads its own points and every acquaintance's; a device walking the past reads the acquaintances'
// alone and holds nothing.
fn proposals_at_the_window(
    machine: &Machine,
    window: u64,
    walking: bool,
) -> Result<Vec<Proposal>, NodeError> {
    let points = round::points_of_window(window).map_err(|_| NodeError::Decree {
        row: "consensus_replicas".to_string(),
    })?;
    let width = Proposal::expected_len();
    let of_proposal = mt_wire::message::body_len(width).map_err(|_| NodeError::Decree {
        row: "chunk_bytes".to_string(),
    })?;
    let mut out: Vec<Proposal> = Vec::new();
    for point in &points {
        let bodies = if walking {
            machine.collect_public(point, window)?
        } else {
            machine.objects_at_the_point(point, window)?
        };
        for body in bodies {
            if body.len() != of_proposal {
                continue;
            }
            let Ok(held) = Proposal::parse(&body[..width]) else {
                continue;
            };
            if held.window == window && !out.iter().any(|one| one.signature == held.signature) {
                out.push(held);
            }
        }
    }
    Ok(out)
}

// A proposal put at every point of its window.
fn stand_at_the_window(machine: &Machine, window: u64, object: &[u8]) -> Result<(), NodeError> {
    let points = round::points_of_window(window).map_err(|_| NodeError::Decree {
        row: "consensus_replicas".to_string(),
    })?;
    for point in &points {
        machine.publish_at_the_point(point, window, object)?;
    }
    Ok(())
}

// **A device that holds nothing walks to the head from the anchor its operator handed it.**
// Consensus, "The join": it asks every acquaintance it reached what stands at the points of every
// window after the anchor — the beacons and heavy attestations of the rounds, and the proposals of
// the window — judges every answer at the one door and trusts none, and takes as the head the newest
// proposal whose certificate verified. What it reads it does not hold: a device walking the past
// deposits nothing and stands at no point. It reads no further than the retention, past which no
// certificate stands; a device further behind takes a fresh anchor, and the set says that is a
// change of trust. The head and the proposal before it are kept, and the head moves onto it.
pub fn join(machine: &Machine, anchor: &Anchor, patience: u32) -> Result<Anchor, NodeError> {
    let retained = mt_genesis::scalar("retained_windows").ok_or(NodeError::Decree {
        row: "retained_windows".to_string(),
    })?;
    type Rounds = Vec<(Beacon, Vec<Confirmation>, Vec<Ballot>)>;
    let mut collected: Vec<(Rounds, Vec<Proposal>)> = Vec::new();
    let mut window = anchor.later.window;
    for _ in 0..=retained {
        window = window.checked_add(1).ok_or(NodeError::Refused {
            what: "a window past the last one a count carries",
        })?;
        let rounds = rounds_standing(machine, window, patience)?;
        if rounds.is_empty() {
            break;
        }
        let proposals = proposals_at_the_window(machine, window, true)?;
        collected.push((rounds, proposals));
    }
    // Every proposal standing for a window is handed to the walk, which takes the one the window after
    // it attests and whose bytes stand at the door; a window no later window attests holds a proposal
    // awaiting its certificate, and the walk takes nothing against it.
    let rounds: Vec<Vec<certificate::Round<'_>>> = collected
        .iter()
        .map(|(rounds, _)| {
            rounds
                .iter()
                .map(|(beacon, heavy, ballots)| certificate::Round {
                    beacon,
                    heavy,
                    ballots,
                })
                .collect()
        })
        .collect();
    let steps: Vec<certificate::Step<'_>> = rounds
        .iter()
        .zip(collected.iter())
        .map(|(certificate, (_, next))| certificate::Step { certificate, next })
        .collect();
    let threshold = mt_pulse::retarget::draw_threshold().map_err(|_| NodeError::Decree {
        row: "hash_bytes".to_string(),
    })?;
    let head = certificate::walk(anchor, &steps, 1, &threshold, mt_state::implemented_major())?;
    machine.keep_proposal(&head.earlier)?;
    machine.keep_proposal(&head.later)?;
    machine.finalize(head.later.window)?;
    Ok(head)
}

// A beacon of a round as a walk reads it off the points: the beacon, the heavy attestations that
// answered it, and the ballots standing beside it.
type StandingRound = (Beacon, Vec<Confirmation>, Vec<Ballot>);

// The beacons of every round of a window standing at its points, each beside the heavy attestations
// that answered it, read until a round holds no beacon or the budget of reads runs out. The ballots of
// a round stand beside the first of its beacons alone: a ballot answers a part and no beacon, and
// handing it to every version of the round would judge one proof as many times.
fn rounds_standing(
    machine: &Machine,
    window: u64,
    patience: u32,
) -> Result<Vec<StandingRound>, NodeError> {
    let mut out = Vec::new();
    for round in 0..patience {
        let objects = walked_round(machine, window, OPENING_CHAIN, round)?;
        if objects.beacons.is_empty() {
            break;
        }
        let mut ballots = Some(objects.ballots);
        for beacon in objects.beacons {
            let id = beacon.id().map_err(NodeError::Object)?;
            let heavy: Vec<Confirmation> = objects
                .heavy
                .iter()
                .filter(|one| one.attested.contains(&id))
                .cloned()
                .collect();
            out.push((beacon, heavy, ballots.take().unwrap_or_default()));
        }
    }
    Ok(out)
}

// What a machine puts at a point, and what it takes from one. A deposit is one cell of the one
// width; an object is cut into cells by the delivery the wire carries and every cell is deposited
// at the same point, so a beacon of six thousand bytes and an attestation of a quarter of a
// megabyte reach a point by the same door a single cell does.
pub fn deposit_at(
    link: &mut mt_net::Link,
    point: &[u8; POINT_BYTES],
    cell: &[u8],
) -> Result<(), NodeError> {
    let message = message::encode_deposit(point, cell).map_err(|_| NodeError::Refused {
        what: "a cell of another width",
    })?;
    link.send(Kind::Deposit, &message).map_err(NodeError::Net)
}

// Every cell standing at a point, read in as many answers as it takes. One answer carries at most
// the cells of the largest single object, and a round stands at a point as a beacon and every
// attestation answering it, so an asker that stopped after one answer would read the beacon and
// never the answers to it. The asking ends when an answer comes back shorter than the bound.
pub fn collect_from(
    link: &mut mt_net::Link,
    point: &[u8; POINT_BYTES],
    already: u16,
) -> Result<Vec<Vec<u8>>, NodeError> {
    let bound = message::collect_answer_max().map_err(|_| NodeError::Decree {
        row: "cell_bytes".to_string(),
    })?;
    let mut held: Vec<Vec<u8>> = Vec::new();
    loop {
        let read = u16::try_from(held.len()).map_err(|_| NodeError::Refused {
            what: "a point holding more cells than a count carries",
        })?;
        let after = already.checked_add(read).ok_or(NodeError::Refused {
            what: "a point holding more cells than a count carries",
        })?;
        let arrived = collect_once(link, point, after)?;
        let taken = arrived.len();
        held.extend(arrived);
        if taken < bound {
            return Ok(held);
        }
    }
}

fn collect_once(
    link: &mut mt_net::Link,
    point: &[u8; POINT_BYTES],
    after: u16,
) -> Result<Vec<Vec<u8>>, NodeError> {
    link.send(
        Kind::CollectPublic,
        &message::encode_collect_public(point, after),
    )
    .map_err(NodeError::Net)?;
    let (kind, arrived) = link.receive().map_err(NodeError::Net)?;
    if kind != Kind::CollectAnswer {
        return Err(NodeError::Refused {
            what: "an answer of another kind than a collection's",
        });
    }
    if arrived.len() < 2 {
        return Ok(Vec::new());
    }
    let declared = usize::from(u16::from_le_bytes([arrived[0], arrived[1]]));
    let one = mt_wire::cell_bytes().map_err(|_| NodeError::Decree {
        row: "cell_bytes".to_string(),
    })?;
    let width = 2 + declared * one;
    if arrived.len() < width {
        return Ok(Vec::new());
    }
    message::parse_collect_answer(&arrived[..width]).map_err(|_| NodeError::Refused {
        what: "an answer of a collection that does not parse",
    })
}

// An object of consensus put at a point: cut into cells under the keys of that point, and every
// cell deposited there. The count of cells is what the erasure code gives — no caller chooses it —
// and a delivery of one object never exceeds `collect_answer_max`, so what is deposited is what one
// collection answers with.
pub fn publish_at(
    link: &mut mt_net::Link,
    point: &[u8; POINT_BYTES],
    window: u64,
    object: &[u8],
) -> Result<usize, NodeError> {
    let cells =
        mt_wire::publish::cells_of(point, window, object).map_err(|_| NodeError::Refused {
            what: "an object no delivery of this wire carries",
        })?;
    for cell in &cells {
        deposit_at(link, point, cell)?;
    }
    Ok(cells.len())
}

// The object standing at a point, or nothing. A collection answers with what the holder has; the
// blocks of one delivery are placed by the index each carries, and a delivery short of a block is
// nothing rather than a body with a hole in it.
pub fn take_from(
    link: &mut mt_net::Link,
    point: &[u8; POINT_BYTES],
    window: u64,
    length: usize,
) -> Result<Option<Vec<u8>>, NodeError> {
    let cells = collect_from(link, point, 0)?;
    mt_wire::publish::object_of(point, window, &cells, length).map_err(|_| NodeError::Refused {
        what: "cells of a point that do not read back as one delivery",
    })
}

#[cfg(test)]
mod historical_reads {
    use super::HistoricalRounds;
    use std::collections::BTreeSet;

    #[test]
    fn late_first_round_data_is_read_even_while_every_read_advances_the_tip() {
        let mut history = HistoricalRounds::default();
        let mut late_data_seen = false;
        for current in 1..=32 {
            let at = history.next(current).unwrap();
            assert!(at < current);
            // The first-round proof becomes available only after round four.
            late_data_seen |= current > 4 && at == 0;
        }
        assert!(late_data_seen, "a growing tip starved the late proof");
    }

    #[test]
    fn a_stalled_tip_revisits_every_historical_round() {
        let mut history = HistoricalRounds::default();
        for _ in 0..3 {
            let visited: BTreeSet<_> = (0..5).map(|_| history.next(5).unwrap()).collect();
            assert_eq!(visited, (0..5).collect());
        }
    }

    #[test]
    fn the_first_and_last_round_do_not_query_the_future_or_overflow() {
        let mut history = HistoricalRounds::default();
        assert_eq!(history.next(0), None);
        assert_eq!(history.next(1), Some(0));
        history.next = u32::MAX - 1;
        history.end = u32::MAX;
        assert_eq!(history.next(u32::MAX), Some(u32::MAX - 1));
        assert_eq!(history.next(u32::MAX), Some(0));
    }
}
