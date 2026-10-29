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

use crate::agreement::{self, Book, Name, Part};
use crate::attempt::{self, Action, Conduct, Replayed, Seen};
use crate::attest::{self, Standing};
use crate::certificate::{
    self, verify_proposal, Anchor, Decided, Electorate, Held, Predecessor, Roots,
};
use crate::runner::Runner;
use crate::state::State;
use crate::{round, Machine, NodeError};
use mt_pulse::cement::Cement;
use mt_state::layout::{
    Ballot, Beacon, Census, Confirmation, Frame, LightAttestation, Pledge, Proposal, Roll,
};
use mt_state::Layout;
use mt_wire::message::{self, Kind, POINT_BYTES};
use sha2::{Digest, Sha256};
use crate::collections::{BTreeMap, BTreeSet};

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
    // zero the proposal of the window two before — the proposal that fixed the electorate of this
    // window, final when it opens. **Not the proposal of the window before**: that is what this
    // window's agreement decides, and two machines may have taken two names for it; a pulse standing
    // on it would part with the names, two pulses each gathering the living of its half, and the
    // cement would part with them (Consensus, "Why round zero stands on the proposal two before").
    // It moves with every round.
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
    // What this machine holds of the agreement on the proposal of the window before: kept in the
    // store before anything it governs is published, and let go at the close.
    pub record: attempt::Record,
    // The book of the agreement: every heavy attestation's name as the open pledge of attempt zero
    // of its part, and every pledge that verified under the key its part's heavy proved.
    pub book: Book,
    // The name each part's heavy attestation pledged: what a light attestation of that part must
    // carry, and what a second heavy of that part under another name contradicts.
    names: BTreeMap<Part, Name>,
    // The pledges already judged, by the digest of their bytes: booked or refused under a proven
    // key. One whose key is not yet proven stands in escrow and is judged again.
    pledges_judged: BTreeSet<[u8; 32]>,
    // The timing of this machine's current attempt, which is conduct and is kept nowhere.
    conduct: Conduct,
    // What this machine learnt of the names it was asked to replay, and what the replay produced.
    replayed: BTreeMap<Name, Replayed>,
    adopted: BTreeMap<Name, Adopted>,
    // The asking a replay of each name was last tried at, where the proposal or its roll was not at
    // the points yet.
    replay_tried: BTreeMap<Name, u32>,
}

// How many askings a machine has stood since `since`: its waiting in units of `ASKS_AGAIN_AFTER`.
fn askings_since(since: std::time::Instant) -> u32 {
    let unit = ASKS_AGAIN_AFTER.as_millis().max(1);
    u32::try_from(since.elapsed().as_millis() / unit).unwrap_or(u32::MAX)
}

// Eight hexadecimal characters of an identifier, for the account of a machine.
fn shown(id: &[u8; 32]) -> String {
    id.iter().take(4).map(|b| format!("{b:02x}")).collect()
}

// A proposal of the window before whose roll this machine replayed and found to carry its roots,
// its cement and its census: the proposal, its roll, and the state the replay produced — the
// decided state of that window, should the agreement decide this name.
#[derive(Clone)]
pub struct Adopted {
    pub proposal: Proposal,
    pub roll: Roll,
    pub state: State,
    // The positions every frame of the roll took as the replay applied it: what a payer of this
    // machine is told again where they moved.
    pub positions: Positions,
}

impl Pulse {
    // A machine entering a window: it draws what the window turns on once, and stands at the points
    // of the round it opens in.
    // `previous_proposal` is the name this machine took of the proposal of the window before, which
    // its heavy attestation pledges; `stands_on` is the proposal of the window two before, which
    // round zero links to. The two are two values of two windows and travel apart.
    #[allow(clippy::too_many_arguments)]
    pub fn open(
        machine: &Machine,
        machine_secret: &[u8; 32],
        at: crate::Round,
        branch: &Branch,
        previous_proposal: [u8; 32],
        stands_on: [u8; 32],
        electorate: &Electorate,
        aggregate: &[u8; 32],
    ) -> Result<Self, NodeError> {
        let (window, chain, _) = at;
        // **The record of the agreement stands before anything it governs is published.** A machine
        // that restarts inside a window reads the name it pledged back from its own record, and one
        // asked to open the window on another name is refused rather than let equivocate; a record
        // of a window never opened is written here, at attempt zero with nothing made.
        if machine
            .closed_window()?
            .is_some_and(|closed| window <= closed)
        {
            return Err(NodeError::Refused {
                what: "a window this machine already closed",
            });
        }
        let record = match machine.agreement_of(window)? {
            Some(held) => held,
            None => machine.open_agreement(&attempt::Record::opened(window, previous_proposal))?,
        };
        if record.taken != previous_proposal {
            return Err(NodeError::Refused {
                what: "a window this machine already pledged under another name",
            });
        }
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
            previous: stands_on,
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
            record,
            book: Book::of_the_window(window),
            names: BTreeMap::new(),
            pledges_judged: BTreeSet::new(),
            conduct: Conduct::default(),
            replayed: BTreeMap::new(),
            adopted: BTreeMap::new(),
            replay_tried: BTreeMap::new(),
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
        let (id, name) = self.check_answer(held.window, &held.attested, beacon, true)?;
        // Remember a cement verified before this answer extends it. Missing data
        // must not prevent collecting the authenticated parts needed to check
        // that cement, but an unreconciled beacon cannot authorize advancement.
        if beacon.round == self.round {
            let _ = self.reconcile_beacon(beacon);
        }
        // **One part attests one name.** Two heavy attestations of one window under one part naming
        // two names are the first of the contradicting pairs the sanction reads; the first appearance
        // stands and the second is refused (Consensus, "The sanction of a double answer").
        if self
            .names
            .get(&held.part_nullifier)
            .is_some_and(|first| *first != name)
        {
            return Err(NodeError::Refused {
                what: "a second heavy attestation of one part naming another name",
            });
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
        // A part enters the cement once, whatever name it pledges; its name is the open pledge of
        // attempt zero the agreement counts (Consensus, "The close is a count every verifier makes").
        let entered = self.cement.add(held.part_nullifier);
        if entered {
            self.order.push(held.part_nullifier);
        }
        self.names.entry(held.part_nullifier).or_insert(name);
        self.book.heavy(
            crate::agreement::Place::of(self.chain, beacon.round, held),
            held.part_nullifier,
            name,
        );
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
        let (id, name) = self.check_answer(held.window, &held.attested, beacon, false)?;
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
        // A light attestation carries the name its heavy pledged and pledges nothing; one carrying
        // another name is refused (Canon, "The light attestation of a part").
        if self.names.get(&held.part_nullifier) != Some(&name) {
            return Err(NodeError::Refused {
                what: "a light attestation naming another name than its heavy",
            });
        }
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

    // What an attestation answers, and what it pledges: the beacon of its round, which must be one
    // of this chain, and beside it the name its machine took of the proposal of the window before —
    // any name, since the cement gathers the living whatever they pledge and the agreement counts
    // the names. The layout holds the two ascending and distinct, so the one that is not the beacon
    // is the name.
    // A pledge that arrived: counted under the key its part's heavy attestation proved, once. One
    // whose part has no proven key yet stands in escrow and is judged again when it has; one that
    // does not verify under the proven key is refused and not judged again. Consensus, "The pledge".
    pub fn gather_pledge(&mut self, held: &Pledge) -> Result<bool, NodeError> {
        if held.window != self.window {
            return Ok(false);
        }
        let fingerprint: [u8; 32] = Sha256::digest(held.bytes().map_err(NodeError::Object)?).into();
        if self.pledges_judged.contains(&fingerprint) {
            return Ok(false);
        }
        let Some(key) = self.proven_keys.get(&held.part_nullifier) else {
            return Ok(false);
        };
        self.pledges_judged.insert(fingerprint);
        attest::verify_pledge(held, key)?;
        self.book.pledge(held.clone());
        Ok(true)
    }

    // The electorate as the agreement counts it: the count, the committee and the votes the
    // verified ballots of the parts cast.
    fn counting<'a>(&'a self, electorate: &Electorate) -> agreement::Electorate<'a> {
        agreement::Electorate {
            count: electorate.count,
            committee: electorate.committee.expected,
            votes: &self.ballots,
        }
    }

    // The decision of the agreement this machine holds: the name and the attempt, or none.
    pub fn decided(&self, electorate: &Electorate) -> Option<(Name, u32)> {
        self.book.decided(&self.counting(electorate))
    }

    // One asking of the conduct of the agreement: what this machine does now, read off the book,
    // its record and the count of its askings.
    pub fn tick(&mut self, now: u32, electorate: &Electorate, aggregate: &[u8; 32]) -> Vec<Action> {
        let mut conduct = std::mem::take(&mut self.conduct);
        let actions = conduct.tick(
            now,
            &Seen {
                book: &self.book,
                electorate: &self.counting(electorate),
                record: &self.record,
                part: &self.standing.part_nullifier,
                aggregate,
                replayed: &self.replayed,
            },
        );
        self.conduct = conduct;
        actions
    }

    // Entering an attempt: the record first, then the count of askings the spans run from.
    pub fn enter_attempt(
        &mut self,
        machine: &Machine,
        attempt: u32,
        now: u32,
        electorate: &Electorate,
    ) -> Result<(), NodeError> {
        if attempt <= self.record.attempt {
            return Ok(());
        }
        self.record.attempt = attempt;
        self.record.valid = self.book.valid_name(&self.counting(electorate));
        machine.keep_agreement(&self.record)?;
        self.conduct.entering(now);
        Ok(())
    }

    // A pledge of this machine in its current attempt, signed under the key of the window, kept
    // in the record before it is handed out, and handed out as bytes for the points. A pledge
    // already made of that kind in that attempt is handed out again rather than signed anew: a
    // part pledges once per kind and attempt, and a machine never signs two.
    pub fn make_pledge(
        &mut self,
        machine: &Machine,
        name: Name,
        since: u32,
        electorate: &Electorate,
    ) -> Result<Vec<u8>, NodeError> {
        let attempt = self.record.attempt;
        let kind = if since == attempt {
            agreement::Kind::Closing
        } else {
            agreement::Kind::Open
        };
        if let Some(made) = self.record.made_in(kind, attempt) {
            return made.bytes().map_err(NodeError::Object);
        }
        let pledge = self.standing.pledge(attempt, name, since)?;
        let bytes = pledge.bytes().map_err(NodeError::Object)?;
        if kind == agreement::Kind::Closing {
            self.record.lock = Some((name, attempt));
        }
        self.record.valid = self.book.valid_name(&self.counting(electorate));
        self.record.made.push(pledge);
        machine.keep_agreement(&self.record)?;
        Ok(bytes)
    }

    // What this machine learnt of a name it replayed.
    pub fn learnt(&mut self, name: Name, outcome: Replayed, adopted: Option<Adopted>) {
        self.replayed.insert(name, outcome);
        if let Some(held) = adopted {
            self.adopted.insert(name, held);
        }
    }

    pub fn adopted(&self, name: &Name) -> Option<&Adopted> {
        self.adopted.get(name)
    }

    // Whether a replay of `name` is due at this asking: not tried yet, or tried long enough ago.
    pub fn replay_due(&mut self, name: &Name, now: u32) -> bool {
        match self.replay_tried.get(name) {
            Some(last) if now.saturating_sub(*last) < ASKS_FOR_A_ROLL_AGAIN_AFTER => false,
            _ => {
                self.replay_tried.insert(*name, now);
                true
            }
        }
    }

    // The parts of every heavy attestation this machine verified in this window, ascending: the
    // cement and the late ones beside it, against which the roll of a proposal of this window is
    // replayed by a machine that took another name.
    pub fn parts_held(&self) -> Vec<Part> {
        self.cement.parts()
    }

    fn check_answer(
        &self,
        window: u64,
        attested: &[[u8; 32]],
        beacon: &Beacon,
        historical: bool,
    ) -> Result<([u8; 32], Name), NodeError> {
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
        let name = match attested {
            [first, second] if *first == id && *second != id => *second,
            [first, second] if *second == id && *first != id => *first,
            _ => {
                return Err(NodeError::Refused {
                    what: "an attestation outside the beacon of its round",
                })
            }
        };
        if window != self.window {
            return Err(NodeError::Refused {
                what: "an attestation of another window",
            });
        }
        Ok((id, name))
    }

    // A beacon of this round this machine can close on: answered by a verified attestation and
    // carrying the pair this machine recomputed. Consensus, "The beacon a window closes on".
    pub fn can_advance(&self, beacon: &Beacon) -> bool {
        self.check_beacon(beacon).is_ok_and(|id| {
            self.answered_beacons.contains(&id)
                && (self.reconciled_beacons.contains(&id) || self.matches_cement(beacon))
        })
    }

    // A beacon of this round a verified attestation answered, whatever pair it carries: what a
    // round advances on. Consensus, "The round": "A round advances only on a valid attestation".
    pub fn is_answered(&self, beacon: &Beacon) -> bool {
        self.check_beacon(beacon)
            .is_ok_and(|id| self.answered_beacons.contains(&id))
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

    // How many machines the cement names: the count of the living, which is the coins the window
    // credits, one to each, and a count of distinct part-nullifiers and of nothing else.
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
    // **A round advances on a valid attestation, and on nothing else.** The beacon it advances on
    // need not carry the pair this machine recomputed: a machine holding one heavy attestation more
    // than the runner held cannot reconcile that beacon, answers it with nothing and closes on it
    // never, but it follows the pulse past it and closes on a later beacon carrying its pair —
    // Consensus, "Why one vote does not suffice" ("cannot reconcile that beacon and closes on a
    // later one"). A machine that stood still before an unreconciled beacon stood in its round for
    // ever, as two of six did on 2026-10-16.
    pub fn advance(&mut self, machine: &Machine, beacon: &Beacon) -> Result<(), NodeError> {
        let previous = self.check_beacon(beacon)?;
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
// the right that window minted to it, and the identifier of its proposal. The right and the
// identifier are of the decided proposal, and stand once the window is final — decided by the
// agreement of the window after, at that window's close; until then the identifier is the name
// this machine took and the right is none, since a right is issued from the decided roll and from
// no count, and a machine whose part that roll does not name took no coin of the window.
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
use mt_pulse::{
    ASKS_FOR_A_ROLL_AGAIN_AFTER, CARRIES_WITHIN, OPENING_CHAIN, REACHES_AGAIN_EVERY, SAYS_EVERY,
};

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

// **The window a machine handed a cohort begins at, and whether it begins at all.** Consensus, "The
// cold start": opening is an explicit act of the operator on an empty store, and a machine that
// holds nothing and is not asked to open opens no window. So `open` on a store holding nothing is
// window zero; `open` on a store holding a chain is refused, since it would be a second window zero
// of a network this machine already stands in; a store holding nothing and not asked to open is
// refused, since it holds no anchor; and a store holding a chain begins after the last window it
// closed, from its own anchor. A store that holds a chain and closed no window was stopped inside
// the first one and holds no anchor either. Every refusal comes before anything is written.
pub fn first_window(machine: &Machine, open: bool) -> Result<u64, NodeError> {
    match (open, machine.holds_a_chain()?) {
        (true, false) => Ok(0),
        (true, true) => Err(NodeError::Refused {
            what: OPENED_OVER_A_CHAIN,
        }),
        (false, false) => Err(NodeError::Refused { what: NO_ANCHOR }),
        (false, true) => match machine.closed_window()? {
            Some(closed) => closed.checked_add(1).ok_or(NodeError::Refused {
                what: "a window past the last one a count carries",
            }),
            None => Err(NodeError::Refused { what: NO_ANCHOR }),
        },
    }
}

const OPENED_OVER_A_CHAIN: &str = "a network opened on a store that holds a chain";
const NO_ANCHOR: &str = "a machine with no anchor opens no window";

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

// What one asking of a round ends in: the window closes on the decision it holds and its final
// beacon, or the machine moves to the round after.
enum Step {
    Close((Name, u32)),
    Advance,
}

// What a machine keeps of a window it closed, for the agreement of the window after: the electorate,
// the aggregate and the threshold its heavy attestations were verified against, the parts of every
// heavy attestation it verified, and the roll of the proposal it took. A machine of the window after
// that took another name replays the decided roll against these, and the right of the window is
// issued from the decided roll once the window is final.
struct Facts {
    electorate: Electorate,
    aggregate: [u8; 32],
    threshold: mt_pulse::U256,
    parts: Vec<Part>,
    roll: Roll,
}

// The decided states and the facts of the last two windows this machine closed: what a replay of a
// decided roll starts from (the decided state of the window two before) and what it is checked
// against. Two windows deep and never a history. A state is held by the window it is the base of,
// so the base of window zero — the plane a machine opens the network on, of no window before it —
// is held as every other.
#[derive(Default)]
struct Memory {
    bases: BTreeMap<u64, State>,
    facts: BTreeMap<u64, Facts>,
}

impl Memory {
    // What a machine that closed `window` keeps: the base of the window after it and its own, which
    // a replay of this window in the next one starts from, and the facts of this window and the one
    // before.
    fn let_go_on_closing(&mut self, window: u64) {
        self.bases.retain(|at, _| *at >= window);
        self.facts.retain(|at, _| at.saturating_add(1) >= window);
    }
}

// **What a machine stands on is what it kept, and nothing it is handed.** The proposals of the last
// two windows it closed, read back from its own store: the one of the last window closed is the name
// the next window pledges, and the one before it is final and fixed the electorate of the next
// window. "A device that lived the network holds its own anchor — the last two proposals it verified
// — and needs nobody's" (Consensus, "The join"); "Reconnection resumes the same open window against
// the same electorate and the same required share" (Consensus, "The way back"). A machine that
// closed a window opens the one after it and no other: a window further on stands on proposals it
// does not hold, and one at or below it stands closed. What it reads back is judged before anything
// stands on it — each proposal of its window, the later naming the earlier (the first window of a
// network, the Genesis State Hash), each under the signature of its runner — so a store a byte of
// which turned opens no window, where it would have opened a chain of its own. A machine that closed
// nothing stands on nothing, and the opening cohort and the Genesis State Hash are for the first
// windows of a network alone.
fn held_of_the_store(machine: &Machine, from: u64) -> Result<BTreeMap<u64, Proposal>, NodeError> {
    let mut held = BTreeMap::new();
    let Some(closed) = machine.closed_window()? else {
        return Ok(held);
    };
    if closed.checked_add(1) != Some(from) {
        return Err(NodeError::Refused {
            what: "a window other than the one after the last this machine closed",
        });
    }
    let kept = |window: u64| {
        machine.proposal_of(window)?.ok_or(NodeError::Refused {
            what: "a closed window whose proposal this machine does not hold",
        })
    };
    let later = kept(closed)?;
    let earlier = closed.checked_sub(1).map(kept).transpose()?;
    let before = match &earlier {
        Some(proposal) => Predecessor::Proposal(proposal),
        None => Predecessor::Genesis,
    };
    if later.window != closed || !before.is_followed_by(closed) || later.previous != before.id()? {
        return Err(NodeError::Refused {
            what: "a kept proposal that does not stand on the one kept before it",
        });
    }
    for proposal in earlier.iter().chain([&later]) {
        certificate::signed_by_its_runner(proposal)?;
    }
    if let Some(proposal) = earlier {
        held.insert(proposal.window, proposal);
    }
    held.insert(closed, later);
    Ok(held)
}

pub fn live_doing(
    machine: &Machine,
    cohort: &Cohort,
    from: u64,
    windows: u64,
    patience: u32,
    errand: Option<Errand<'_>>,
) -> Result<Vec<Lived>, NodeError> {
    // Window zero is opened on an empty store and on no other (Consensus, "The cold start"), whoever
    // calls the pulse: before anything of the window is written.
    if from == 0 && machine.holds_a_chain()? {
        return Err(NodeError::Refused {
            what: OPENED_OVER_A_CHAIN,
        });
    }
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
    // holds those two and lets the older go, and what it keeps of them beyond is the store's — which
    // is where a machine started again reads them back from.
    let mut stands_on = held_of_the_store(machine, from)?;
    let mut memory = Memory::default();
    // The plane as this machine holds it entering its first window: the base that window's decided
    // roll replays over.
    memory.bases.insert(from, machine.value()?.clone());
    let mut out: Vec<Lived> = Vec::new();
    // A reading of an earlier run is not this run's. Inside the run the last reading stands until
    // the next replaces it: a window that opens after a close still reads that close.
    counts.clear_status();
    for step in 0..windows {
        let window = from.checked_add(step).ok_or(NodeError::Refused {
            what: "a window past the last one a count carries",
        })?;
        // The electorate of a window is the admitted set of the proposal two before it, and the
        // aggregate it draws from is that proposal's cement. An opening cohort stands for the first
        // two windows of a network and for no other: "For the first two windows of a network it is
        // the opening cohort an operator handed the machine, which the proposal of window zero must
        // carry" (Consensus, "The pulse and the close of a window"), and the aggregate of no signers
        // is what the set freezes for a window with nothing cemented two before it. A later window
        // this machine holds no proposal two before of is one it does not open: the cohort it was
        // handed is no electorate of it.
        let two_before = window.checked_sub(2).and_then(|at| stands_on.get(&at));
        let (electorate, aggregate) = match two_before {
            Some(proposal) => (Electorate::of(proposal)?, proposal.cement_aggregate),
            None if window >= 2 => return Err(NodeError::Refused {
                what: "a window past the first two of a network standing on no proposal two before",
            }),
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
        // The proposal of the window before as this machine took it: the name its heavy attestation
        // pledges in attempt zero. The agreement of this window decides it, and where it decides
        // another name the machine takes that one below, before anything of this window stands on it.
        let mut predecessor_held: Option<Proposal> = window
            .checked_sub(1)
            .and_then(|at| stands_on.get(&at))
            .cloned();
        // The Genesis State Hash is that name for window zero alone (Consensus, "Invariants of the
        // TimeChain").
        let taken = match &predecessor_held {
            Some(proposal) => Predecessor::Proposal(proposal).id()?,
            None if window == 0 => Predecessor::Genesis.id()?,
            None => {
                return Err(NodeError::Refused {
                    what: "a window past the first of a network standing on no proposal before it",
                })
            }
        };
        // Round zero stands on the proposal two before, final when this window opens; for the
        // first two windows of a network, on the Genesis State Hash.
        let stands_on_two_before = match two_before {
            Some(proposal) => Predecessor::Proposal(proposal).id()?,
            None => Predecessor::Genesis.id()?,
        };
        let mut pulse = Pulse::open(
            machine,
            &of_the_machine,
            (window, OPENING_CHAIN, 0),
            &branch,
            taken,
            stands_on_two_before,
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
        // The count of this machine's askings in this window: the clock the spans of the agreement
        // run on, which is conduct and enters no rule of acceptance. An asking is the unit of this
        // machine's waiting, `ASKS_AGAIN_AFTER`, and the count is read off how long the machine has
        // stood in the window in those units rather than off the turns of its loop: a machine
        // turning rounds or reading a whole window at every turn would count a span in minutes
        // while its neighbour standing still counted it in seconds, and the honest machines would
        // never enter an attempt together (seen on four machines, 23.10.2026).
        let opened_at = std::time::Instant::now();
        let mut asked: u32;
        // The beacon this machine closes the window on, once it holds one: the first beacon of its
        // chain at the quorum of the electorate and of the committee that it reconciled and that a
        // verified attestation answered. The rounds stop turning for this machine once it holds one,
        // and the window closes once the agreement has decided (Consensus, "The beacon a window
        // closes on").
        let mut final_beacon: Option<Beacon> = None;
        let decided: (Name, u32) = loop {
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
                let on = counts.observe(true, askings_since(opened_at), waited, patience);
                waited += 1;
                if waited >= patience {
                    return Err(counts.exhausted(on, "a round no beacon ever stood at"));
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
            let mut said = (usize::MAX, usize::MAX, usize::MAX, usize::MAX, u32::MAX);
            let mut ordered = beacons;
            let step = loop {
                asked = askings_since(opened_at);
                let mut unreconciled = 0;
                let mut missing_light_key = false;
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
                        // Another version's answer is not a failed proof of this version.
                        if !held
                            .attested
                            .contains(&beacon.id().map_err(NodeError::Object)?)
                        {
                            continue;
                        }
                        match pulse.gather_light(held, &aggregate, beacon, &of_a_round) {
                            Err(NodeError::Refused {
                                what: "a light attestation before its proven heavy",
                            }) => missing_light_key = true,
                            Err(_) => counts.raise(&counts.light_refused),
                            Ok(_) => {}
                        }
                    }
                }
                // The ballots of the parts the cement holds: each judged once, and counted for its
                // part at the largest count a ballot of that part casts.
                for held in &arrived.ballots {
                    if pulse.gather_ballot(held, &electorate, &aggregate).is_err() {
                        counts.raise(&counts.ballots_refused);
                    }
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
                        if pulse.gather_ballot(held, &electorate, &aggregate).is_err() {
                            counts.raise(&counts.ballots_refused);
                        }
                    }
                }
                // **The pledges of the agreement stand at the points of the window**, and every
                // machine of the window reads them as it reads the rounds: each counted under the
                // key its part's heavy attestation proved, and in escrow until that heavy is seen.
                for held in pledges_at_the_window(machine, window)? {
                    match pulse.gather_pledge(&held) {
                        Ok(true) => counts.raise(&counts.pledges_booked),
                        Ok(false) => {}
                        Err(_) => counts.raise(&counts.pledges_refused),
                    }
                }
                // **The conduct of the agreement, one asking of it.** What the steps of "How a
                // machine pledges" ask for now is signed and kept before it is published, and an
                // attempt is entered by writing the record first.
                for action in pulse.tick(asked, &electorate, &aggregate) {
                    match action {
                        // **What a machine does in the agreement, it says**: every pledge it makes,
                        // every roll it replays and every attempt it enters, with the name it
                        // concerns — eight hexadecimal characters of it — so an operator reads the
                        // agreement of a window off the account rather than guessing at it.
                        Action::Close(name) => {
                            let attempt = pulse.record.attempt;
                            let bytes = pulse.make_pledge(machine, name, attempt, &electorate)?;
                            stand_at_the_window(machine, window, &bytes)?;
                            counts.raise(&counts.pledges_made);
                            let line = format!(
                                "window {} attempt {}: this machine closes on {} at asking {}",
                                window,
                                attempt,
                                shown(&name),
                                asked
                            );
                            crate::private::say(&line, || {
                                format!("{line} -- part {}", shown(&pulse.standing.part_nullifier))
                            });
                        }
                        Action::Open(name, since) => {
                            let bytes = pulse.make_pledge(machine, name, since, &electorate)?;
                            stand_at_the_window(machine, window, &bytes)?;
                            counts.raise(&counts.pledges_made);
                            let line = format!(
                                "window {} attempt {}: this machine opens on {} standing on {} at asking {}",
                                window,
                                pulse.record.attempt,
                                shown(&name),
                                if since == mt_state::STANDS_ON_NONE {
                                    "none".to_string()
                                } else {
                                    since.to_string()
                                },
                                asked
                            );
                            crate::private::say(&line, || {
                                format!("{line} -- part {}", shown(&pulse.standing.part_nullifier))
                            });
                        }
                        Action::Replay(name) => {
                            // A roll that is not at the points yet is asked for again after a few
                            // askings, not at every one: reading a past window asks every
                            // acquaintance for every point of every round of it.
                            if pulse.replay_due(&name, asked) {
                                if let Some(before) = window.checked_sub(1) {
                                    match replay(
                                        machine,
                                        cohort,
                                        before,
                                        &name,
                                        &memory,
                                        &stands_on,
                                        &of_the_draw,
                                        patience,
                                    )? {
                                        Some((outcome, adopted, why)) => {
                                            let line = format!(
                                                "window {} attempt {}: the roll of {} replayed at asking {}: {why}",
                                                window,
                                                pulse.record.attempt,
                                                shown(&name),
                                                asked
                                            );
                                            crate::private::say(&line, || {
                                                format!(
                                                    "{line} -- part {}",
                                                    shown(&pulse.standing.part_nullifier)
                                                )
                                            });
                                            pulse.learnt(name, outcome, adopted);
                                        }
                                        None => {
                                            let line = format!(
                                                "window {} attempt {}: the proposal {} or its roll does not stand at the points of the window before yet (asking {})",
                                                window,
                                                pulse.record.attempt,
                                                shown(&name),
                                                asked
                                            );
                                            crate::private::say(&line, || {
                                                format!(
                                                    "{line} -- part {}",
                                                    shown(&pulse.standing.part_nullifier)
                                                )
                                            });
                                        }
                                    }
                                }
                            }
                        }
                        Action::Enter(attempt) => {
                            pulse.enter_attempt(machine, attempt, asked, &electorate)?;
                            let line = format!(
                                "window {} enters attempt {} at asking {} holding {} pledges of the agreement",
                                window,
                                pulse.record.attempt,
                                asked,
                                pulse.book.held()
                            );
                            crate::private::say(&line, || {
                                format!("{line} -- part {}", shown(&pulse.standing.part_nullifier))
                            });
                        }
                    }
                }
                // **A window closes on a beacon that carries the quorum.** The count every machine
                // closes on is the one a beacon carries, so that every machine closing a window
                // closes it on one value: a beacon of this round whose carried count reaches the
                // quorum share of the electorate, which this machine reconciled against what it
                // holds and which a verified attestation answered. Consensus, "The beacon a window
                // closes on". The first such beacon is the final beacon of the window for this
                // machine, the smallest identifier among the versions of its round, and the rounds
                // stop turning for this machine once it holds one; the window closes once the
                // agreement has decided.
                if final_beacon.is_none() {
                    let mut at_the_quorum: Vec<&Beacon> = ordered
                        .iter()
                        .filter(|beacon| {
                            pulse.can_advance(beacon) && carries_the_quorum(beacon, &electorate)
                        })
                        .collect();
                    at_the_quorum.sort_by_key(|one| one.id().unwrap_or([0xFFu8; 32]));
                    final_beacon = at_the_quorum.first().map(|one| (*one).clone());
                }
                let on = counts.observe(
                    final_beacon.is_none()
                        && (ordered.is_empty() || unreconciled > 0 || missing_light_key),
                    asked,
                    waited,
                    patience,
                );
                if final_beacon.is_some() {
                    if let Some(decision) = pulse.decided(&electorate) {
                        let line = format!(
                            "window {} decided {} in attempt {} at asking {}",
                            window,
                            shown(&decision.0),
                            decision.1,
                            asked
                        );
                        crate::private::say(&line, || {
                            format!("{line} -- part {}", shown(&pulse.standing.part_nullifier))
                        });
                        break Step::Close(decision);
                    }
                } else if ordered.iter().any(|beacon| pulse.is_answered(beacon)) {
                    break Step::Advance;
                }
                waited += 1;
                if waited >= patience {
                    return Err(counts.exhausted(
                        on,
                        if final_beacon.is_some() {
                            "waiting budget exhausted: agreement undecided; window unchanged"
                        } else {
                            "waiting budget exhausted without a verified answer; round unchanged"
                        },
                    ));
                }
                // **The account is written while the machine waits, and not only when it moves.** A
                // round is made of waiting, so a machine that spoke once a round would be silent for
                // as long as the waiting lasts — which is exactly the stretch an operator needs to
                // see into. It speaks when what it holds changes, and again while nothing does: the
                // **sequence of arrivals** — every time the cement grows or a new attestation
                // stands — and, while nothing arrives, a heartbeat that says so.
                let held = (
                    pulse.living(),
                    answers_seen,
                    ordered.len(),
                    unreconciled,
                    pulse.record.attempt,
                );
                if held != said || waited % SAYS_EVERY == 0 {
                    said = held;
                    println!(
                        "{on}: window {} round {} waiting: cement {} of {}, beacons {}, standing {}, unreconciled cement {}, attempt {}{} | {}",
                        window,
                        pulse.round,
                        held.0,
                        electorate.count,
                        held.2,
                        held.1,
                        held.3,
                        held.4,
                        if final_beacon.is_some() {
                            ", final beacon held, awaiting the decision"
                        } else {
                            ""
                        },
                        counts.line()
                    );
                }
                std::thread::sleep(ASKS_AGAIN_AFTER);
            };
            // Two versions of one round are resolved by the smaller identifier, which is the rule
            // the set states for two clearings of one height: among the versions this machine
            // reconciled where it holds one, among the versions a verified attestation answered
            // where it holds none it reconciled.
            let reconciled: Vec<Beacon> = ordered
                .iter()
                .filter(|one| pulse.can_advance(one))
                .cloned()
                .collect();
            if reconciled.is_empty() {
                ordered.retain(|one| pulse.is_answered(one));
            } else {
                ordered = reconciled;
            }
            ordered.sort_by_key(|one| one.id().unwrap_or([0xFFu8; 32]));
            // **The frames of a round apply as the machine leaves it**, in ascending order of their
            // identifiers: Canon, "The roots of state". A machine that applied each as it arrived
            // would order one round's frames by the order of its own deliveries, and two machines
            // would carry two roots for one window. What arrived in the same breath as the close is
            // applied before the machine leaves for the same reason: a frame published inside a
            // window stands at the very points the attestation completing the cement stands at.
            machine.apply_what_stands()?;
            match step {
                Step::Close(decision) => break decision,
                Step::Advance => {}
            }
            let taken = ordered.first().cloned().ok_or(NodeError::Refused {
                what: "a round whose beacons vanished between two readings",
            })?;
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
        let last = final_beacon.ok_or(NodeError::Refused {
            what: "a window decided before this machine held its final beacon",
        })?;
        // **When the decision is not the name this machine took.** It takes the decided proposal
        // and its roll, replays the roll over the decided state of the window two before, holds
        // what results as the decided state of the window before, and applies again, over that
        // state and in their order, the frames of this window it had applied. Consensus, "When the
        // decision is not the name a machine took". The roll usually replayed while the agreement
        // ran; a machine that never followed that name replays it here. Nothing of it is held until
        // the close stands: the plane it applies again is the plane the window closes on, written in
        // the one record of the close below, and the payers are told once that record stands.
        let (decided_name, decided_in) = decided;
        let mut replayed: Option<(Adopted, State, Positions)> = None;
        if decided_name != taken {
            let before = window.checked_sub(1).ok_or(NodeError::Refused {
                what: "a decision on a window before the first",
            })?;
            let mut waited = 0;
            let adopted = loop {
                if let Some(held) = pulse.adopted(&decided_name).cloned() {
                    break held;
                }
                match replay(
                    machine,
                    cohort,
                    before,
                    &decided_name,
                    &memory,
                    &stands_on,
                    &of_the_draw,
                    patience,
                )? {
                    Some((Replayed::Valid, Some(held), _)) => {
                        pulse.learnt(decided_name, Replayed::Valid, Some(held.clone()));
                        break held;
                    }
                    Some((_, _, why)) => {
                        println!(
                            "window {} refuses the decided proposal of the window before: {why}",
                            window
                        );
                        return Err(NodeError::Refused {
                            what: "a decided proposal whose roll does not replay to it",
                        });
                    }
                    None => {}
                }
                let on = counts.observe(true, askings_since(opened_at), waited, patience);
                waited += 1;
                if waited >= patience {
                    return Err(counts.exhausted(
                        on,
                        "a decided proposal that never stood at the points with its roll",
                    ));
                }
                std::thread::sleep(ASKS_AGAIN_AFTER);
            };
            let (plane, positions) = applied_again(machine, window, &adopted.state, patience)?;
            let link: String = decided_name.iter().map(|b| format!("{b:02x}")).collect();
            println!(
                "window {} decided the proposal {} of the window before in attempt {}, not the one this machine took; its roll replayed and this window applied again",
                window, link, decided_in
            );
            stands_on.insert(before, adopted.proposal.clone());
            predecessor_held = Some(adopted.proposal.clone());
            replayed = Some((adopted, plane, positions));
        }
        // The plane the window closes on: the one applied again over the decided state, or the one
        // this machine applied round by round.
        let mut plane = match &replayed {
            Some((_, plane, _)) => plane.clone(),
            None => machine.value()?.clone(),
        };
        let predecessor = match &predecessor_held {
            Some(proposal) => Predecessor::Proposal(proposal),
            None => Predecessor::Genesis,
        };
        // **What the window decided, and the proposal that carries it.** The final beacon's pair is
        // the cement of the window; the roots are recomputed from the plane as the window left it;
        // and the proposal this machine takes is the one under the identifier it computed itself,
        // judged at the one door whoever proved it.
        let decided = Decided::of_beacon(&last, &electorate)?;
        // The parts the window decided, exactly: those the final beacon carried when this machine
        // reconciled it. They are what a census window folds the tree of its cement over.
        let decided_parts = pulse.parts_of(&last).ok_or(NodeError::Refused {
            what: "a final beacon this machine never reconciled",
        })?;
        let own_part = pulse.standing.part_nullifier;
        let depth = mt_proof::tree_depth();
        let mut own_census = Census {
            root: mt_proof::cement::empty_root().bytes(),
            count: decided.cement_count,
        };
        let censused = mt_pulse::standing::is_census(window).map_err(|_| NodeError::Decree {
            row: "census_interval".to_string(),
        })?;
        // The census window this machine lived, kept by the close.
        let mut lived_census: Option<attest::LivedCensus> = None;
        if censused {
            let root =
                mt_proof::cement::root_of(&decided_parts, depth).ok_or(NodeError::Refused {
                    what: "a cement the tree of a cement cannot hold",
                })?;
            own_census.root = root.bytes();
            if decided_parts.binary_search(&own_part).is_ok() {
                if let Some((siblings, position)) =
                    mt_proof::cement::branch_of(&decided_parts, &own_part, depth)
                {
                    lived_census = Some(attest::LivedCensus {
                        window,
                        root: root.bytes(),
                        siblings,
                        position,
                    });
                }
            }
        }
        // The census this window's proposal carries: the one before it, with this window's own
        // cement entering first where this is a census window.
        let previous_census = match predecessor {
            Predecessor::Proposal(before) => before.census.clone(),
            Predecessor::Genesis => certificate::empty_census()?,
        };
        // **The challenge of the window before closed with this window's decision**, so the proposal
        // of this window credits its cement: the parts of its decided roll enter the tree of credited
        // rights of the candidate plane before the roots are taken, and the root this proposal carries
        // stands after them. The credit is the close's and no one else's: it becomes durable only in the
        // one record of this close, so a refused proposal leaves the plane and its record on the close
        // before (F-562-1).
        let credited = credited_by(machine, &memory, &predecessor)?.ok_or(NodeError::Refused {
            what: "a window before whose decided roll this machine does not hold",
        })?;
        plane.credit(&credited)?;
        let mut roots = plane.roots(cohort, window, &decided_parts)?;
        let roll = plane.roll(window, &decided_parts);
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
            &roll,
            patience,
        )?;
        // **The window closes in one writing.** The decision of this window made the proposal before
        // it final, and the head moves onto it in the record of this close, which carries the number
        // of the window closed, the plane it closed on, the decided state of the window before and
        // the standing; the proposal of this window is kept before it, and is final when the
        // agreement of the next window decides it. Nothing of the close is held, told or let go
        // before that record stands: a refusal before it leaves this machine on the close before.
        let decided_before = match &replayed {
            Some((adopted, _, _)) => Some(adopted.state.clone()),
            None => memory.bases.get(&window).cloned(),
        };
        machine.close(crate::Closing {
            head: predecessor_held.clone(),
            taken: proposal.clone(),
            plane: plane.clone(),
            before: decided_before,
            census: lived_census,
        })?;
        // **The payers of this machine are told again** where the replay moved their frames —
        // those of the window before, by the decided roll, and those of this window, applied
        // again — or that a frame of theirs applies in no window.
        if let Some((adopted, _, positions)) = replayed {
            let before = adopted.proposal.window;
            machine.retell(before, &adopted.positions)?;
            machine.retell(window, &positions)?;
            memory.bases.insert(window, adopted.state);
            if let Some(facts) = memory.facts.get_mut(&before) {
                facts.roll = adopted.roll;
            }
        }
        // The right of the window made final is issued from its decided roll: the window's credit to
        // every part the roll names, and none to a machine whose part it does not name.
        if let Some(before) = &predecessor_held {
            // The window is final: no replay moves its frames again, and what its payers were told
            // stands.
            machine.settled_through(before.window)?;
            let final_id = before.id().map_err(NodeError::Object)?;
            let link: String = final_id.iter().map(|b| format!("{b:02x}")).collect();
            let decided_roll = decided_roll(machine, &memory, before)?;
            let right = match decided_roll {
                Some(roll) => {
                    let part_before = mt_derive::nullifier::part(&of_the_machine, before.window)
                        .ok_or(NodeError::Unprovable {
                            what: "the halves of this machine's secret",
                        })?;
                    if roll.parts.binary_search(&part_before).is_ok() {
                        Some(attest::right_of(&of_the_machine, before.window)?)
                    } else {
                        None
                    }
                }
                None => None,
            };
            let line = format!(
                "window {} is final under the proposal {} decided in attempt {}",
                before.window, link, decided_in
            );
            crate::private::say(&line, || match &right {
                Some(right) => format!(
                    "{line} | it credits {} coin to this machine, accepted in window {}",
                    right.worth, right.accepted_in
                ),
                None => format!(
                    "{line} | this machine's part is not in its cement, so it took no coin of it"
                ),
            });
            if let Some(lived) = out.iter_mut().find(|one| one.window == before.window) {
                lived.right = right;
                lived.proposal = final_id;
            }
        }
        let id = proposal.id().map_err(NodeError::Object)?;
        let living = usize::try_from(decided.cement_count).map_err(|_| NodeError::Refused {
            what: "a count of the living past what a number carries",
        })?;
        let lived = Lived {
            window,
            rounds: pulse.round,
            living,
            right: None,
            proposal: id,
        };
        // **A window closed is said when it closes.** A machine living until it is stopped returns
        // nothing, so what it lived written only at the return is written never, and an operator
        // watching a chain that moves sees a machine that says nothing. The identifier the next
        // window carries back is said with it: it is the one value of this window the next one
        // stands on, and the one the agreement of the next window decides.
        let link: String = id.iter().map(|b| format!("{b:02x}")).collect();
        println!(
            "window {} closed after {} rounds on a cement naming {} machines and casting {} votes; the next links to the proposal {} and decides it",
            lived.window, lived.rounds, lived.living, decided.cement_votes, link
        );
        counts.closed(lived.window);
        out.push(lived);
        memory.facts.insert(
            window,
            Facts {
                electorate: electorate.clone(),
                aggregate,
                threshold: of_a_round,
                parts: pulse.parts_held(),
                roll,
            },
        );
        if let Some(next) = window.checked_add(1) {
            memory.bases.insert(next, plane);
        }
        memory.let_go_on_closing(window);
        stands_on.insert(window, proposal);
        stands_on.retain(|at, _| at.saturating_add(1) >= window);
    }
    Ok(out)
}

// The decided roll of a window this machine closed: the one this run held of a window it lived, and
// of the window an earlier run of this machine closed before it stopped, the roll standing at the
// points of that window under the identifier its final proposal carries -- so a machine started
// again credits and issues what it would have had it never stopped (Consensus, "The way back"). A
// roll whose identifier is not the one the proposal carries is no decided roll of it.
fn decided_roll(
    machine: &Machine,
    memory: &Memory,
    before: &Proposal,
) -> Result<Option<Roll>, NodeError> {
    if let Some(facts) = memory.facts.get(&before.window) {
        if facts.roll.id().ok() == Some(before.roll) {
            return Ok(Some(facts.roll.clone()));
        }
    }
    Ok(rolls_of(
        &bodies_at_a_past_window(machine, before.window)?,
        before.window,
    )
    .into_iter()
    .find(|one| one.id().ok() == Some(before.roll)))
}

// The parts the proposal of a window credits: those of the decided roll of the window before it,
// which this machine closed, and none for the first window of a network; none at all where this
// machine holds no decided roll of that window. Canon, "The right of a machine to its coin of a
// window, and what redeems it". The set leaves out a part a contradicting pair of that window's
// challenge convicted; the sanction itself is not built (Registry, CNS-10), so the whole cement is
// credited until it is.
fn credited_by(
    machine: &Machine,
    memory: &Memory,
    predecessor: &Predecessor<'_>,
) -> Result<Option<Vec<[u8; 32]>>, NodeError> {
    match predecessor {
        Predecessor::Genesis => Ok(Some(Vec::new())),
        Predecessor::Proposal(before) => {
            Ok(decided_roll(machine, memory, before)?.map(|roll| roll.parts))
        }
    }
}

// The positions the frames of a window took as a replay applied them, by the frame: what a payer is
// told again.
type Positions = BTreeMap<[u8; 32], Vec<u64>>;

// What a replay answers: whether the name is valid to this machine, what it adopted where it is, and
// the reason in a word for the account of the machine.
type Replay = (Replayed, Option<Adopted>, &'static str);

// The replay of the roll of a proposal of `window` under `name`, by a machine that took another
// name: the proposal and its roll are read off the points of that window, the frames the roll names
// are applied in their order over the decided state of the window before it, the parts are checked
// against the heavy attestations of that window, and the roots, the cement and the census that
// result are the proposal's — or the roll is not that proposal's and the name is not valid to this
// machine. Consensus, "The roll of a proposal"; Canon, "The roll of a proposal". Nothing, where the
// proposal or its roll does not stand at the points yet.
#[allow(clippy::too_many_arguments)]
fn replay(
    machine: &Machine,
    cohort: &Cohort,
    window: u64,
    name: &Name,
    memory: &Memory,
    stands_on: &BTreeMap<u64, Proposal>,
    draw_threshold: &mt_pulse::U256,
    patience: u32,
) -> Result<Option<Replay>, NodeError> {
    let invalid = |why: &'static str| Ok(Some((Replayed::Invalid, None, why)));
    let Some(facts) = memory.facts.get(&window) else {
        return invalid("a window this machine did not live");
    };
    let Some(base) = memory.bases.get(&window) else {
        return invalid("no decided state of the window before to replay over");
    };
    let bodies = bodies_at_a_past_window(machine, window)?;
    let Some(proposal) = proposals_of(&bodies, window)?
        .into_iter()
        .find(|one| one.id().ok().as_ref() == Some(name))
    else {
        return Ok(None);
    };
    let Some(roll) = rolls_of(&bodies, window)
        .into_iter()
        .find(|one| one.id().ok() == Some(proposal.roll))
    else {
        return Ok(None);
    };
    // The parts: the cement_count of the proposal, aggregating to its pair, reaching the quorum,
    // and each the part of a heavy attestation of the window this machine verified — the late ones
    // read off the rounds of the window where its cement lacks one.
    if proposal.window != window || roll.parts.len() as u64 != proposal.cement_count {
        return invalid("a roll whose count of parts is not the proposal's");
    }
    let pair = mt_derive::aggregate::aggregate(&roll.parts, window);
    if pair.as_ref().ok() != Some(&proposal.cement_aggregate) {
        return invalid("a roll whose parts do not aggregate to the proposal's cement");
    }
    if !mt_pulse::close::closes(
        roll.parts.len() as u128,
        u128::from(facts.electorate.count),
        0,
    )
    .unwrap_or(false)
    {
        return invalid("a roll whose parts do not reach the quorum");
    }
    let mut parts = facts.parts.clone();
    if roll
        .parts
        .iter()
        .any(|part| parts.binary_search(part).is_err())
    {
        parts.extend(late_parts_of_a_past_window(
            machine, window, facts, patience,
        )?);
        parts.sort_unstable();
        parts.dedup();
        if roll
            .parts
            .iter()
            .any(|part| parts.binary_search(part).is_err())
        {
            return invalid("a roll naming a part no heavy attestation of the window carries");
        }
    }
    let previous = match window.checked_sub(1).and_then(|at| stands_on.get(&at)) {
        Some(before) => Predecessor::Proposal(before),
        None => Predecessor::Genesis,
    };
    if proposal.previous != previous.id()? {
        return invalid("a proposal whose predecessor is not the one this machine decided");
    }
    // The frames, in the order of the roll, over the decided state of the window before.
    let frames = frames_of_a_past_window(machine, window, patience)?;
    let mut state = base.clone();
    let mut positions: Positions = BTreeMap::new();
    for id in &roll.frames {
        let Some(frame) = frames.get(id) else {
            return invalid("a frame of the roll that stands at no round of the window");
        };
        match state.apply(frame, window) {
            Ok(took) => {
                positions.insert(*id, took);
            }
            Err(_) => return invalid("a frame of the roll the decided state refuses"),
        }
    }
    // The credit the proposal of this window writes: the decided cement of the window before it.
    let Some(credited) = credited_by(machine, memory, &previous)? else {
        return invalid("a window before whose decided roll this machine does not hold");
    };
    if state.credit(&credited).is_err() {
        return invalid("a cement the tree of credited rights cannot hold");
    }
    let mut roots = state.roots(cohort, window, &roll.parts)?;
    let censused = mt_pulse::standing::is_census(window).map_err(|_| NodeError::Decree {
        row: "census_interval".to_string(),
    })?;
    let own_census = Census {
        root: if censused {
            mt_proof::cement::root_of(&roll.parts, mt_proof::tree_depth())
                .ok_or(NodeError::Refused {
                    what: "a cement the tree of a cement cannot hold",
                })?
                .bytes()
        } else {
            mt_proof::cement::empty_root().bytes()
        },
        count: proposal.cement_count,
    };
    let previous_census = match previous {
        Predecessor::Proposal(before) => before.census.clone(),
        Predecessor::Genesis => certificate::empty_census()?,
    };
    roots.census =
        mt_pulse::standing::carried(&previous_census, window, own_census).map_err(|_| {
            NodeError::Decree {
                row: "standing_censuses".to_string(),
            }
        })?;
    let decided = Decided {
        window,
        final_beacon: proposal.final_beacon,
        cement_aggregate: proposal.cement_aggregate,
        cement_count: proposal.cement_count,
        cement_votes: 0,
    };
    let held = Held {
        predecessor: previous,
        decided: &decided,
        electorate: &facts.electorate,
        aggregate_two_before: &facts.aggregate,
        draw_threshold,
        implemented_major: mt_state::implemented_major(),
    };
    // The roots recomputed, the rules, the link, the signature and the ticket: the whole door, as
    // a machine of the window judged it.
    if verify_proposal(&proposal, &held, &roots).is_err() {
        return invalid(
            "a proposal whose roots, census, signature or ticket the replay does not reproduce",
        );
    }
    Ok(Some((
        Replayed::Valid,
        Some(Adopted {
            proposal,
            roll,
            state,
            positions,
        }),
        "the roll replays to the proposal",
    )))
}

// The frames of the open window this machine applied, applied again in their order over the
// decided state of the window before: what results is the plane of this machine. A frame the
// decided state refuses applies in no window, which is what its sender is told.
fn applied_again(
    machine: &Machine,
    window: u64,
    decided_before: &State,
    patience: u32,
) -> Result<(State, Positions), NodeError> {
    let applied = machine.value()?.operations_of(window);
    let frames = frames_of_a_past_window(machine, window, patience)?;
    let mut state = decided_before.clone();
    let mut positions = BTreeMap::new();
    for id in &applied {
        if let Some(frame) = frames.get(id) {
            if let Ok(took) = state.apply(frame, window) {
                positions.insert(*id, took);
            }
        }
    }
    Ok((state, positions))
}

// The bodies standing at the points of a window this machine lived and left: what it holds at its
// own points and what its acquaintances hold at theirs, each body once. A point of a past window
// takes no deposit, so what the acquaintances answer is read and held nowhere.
fn bodies_at_a_past_window(machine: &Machine, window: u64) -> Result<Vec<Vec<u8>>, NodeError> {
    let points = round::points_of_window(window).map_err(|_| NodeError::Decree {
        row: "consensus_replicas".to_string(),
    })?;
    bodies_at_past_points(machine, &points, window)
}

fn bodies_at_past_points(
    machine: &Machine,
    points: &[[u8; POINT_BYTES]],
    window: u64,
) -> Result<Vec<Vec<u8>>, NodeError> {
    let mut out: Vec<Vec<u8>> = Vec::new();
    let mut seen: BTreeSet<[u8; 32]> = BTreeSet::new();
    for point in points {
        let mut bodies = machine.objects_at_the_point(point, window)?;
        bodies.extend(machine.collect_public(point, window)?);
        for body in bodies {
            if seen.insert(Sha256::digest(&body).into()) {
                out.push(body);
            }
        }
    }
    Ok(out)
}

// The frames standing at the round points of a window this machine lived, by their identifiers:
// read round by round until a round holds nothing, since a round that stood holds its beacon.
fn frames_of_a_past_window(
    machine: &Machine,
    window: u64,
    patience: u32,
) -> Result<BTreeMap<[u8; 32], Frame>, NodeError> {
    let width = State::width_of_a_frame();
    let of_frame = mt_wire::message::body_len(width).map_err(|_| NodeError::Decree {
        row: "chunk_bytes".to_string(),
    })?;
    let mut out = BTreeMap::new();
    for round in 0..patience {
        let points = round::points_of_round(window, OPENING_CHAIN, round).map_err(|_| {
            NodeError::Decree {
                row: "consensus_replicas".to_string(),
            }
        })?;
        let bodies = bodies_at_past_points(machine, &points, window)?;
        if bodies.is_empty() {
            break;
        }
        for body in bodies {
            if body.len() != of_frame {
                continue;
            }
            let Ok(frame) = Frame::parse(&body[..width]) else {
                continue;
            };
            if let Ok(id) = frame.id() {
                out.entry(id).or_insert(frame);
            }
        }
    }
    Ok(out)
}

// The parts of the heavy attestations standing at the rounds of a window this machine lived that
// verify against the electorate, the aggregate and the threshold of that window: what a roll's
// parts are checked against where this machine's cement lacks one — a heavy that reached the
// points after this machine left the window.
fn late_parts_of_a_past_window(
    machine: &Machine,
    window: u64,
    facts: &Facts,
    patience: u32,
) -> Result<Vec<Part>, NodeError> {
    let width = Confirmation::expected_len();
    let of_answer = mt_wire::message::body_len(width).map_err(|_| NodeError::Decree {
        row: "chunk_bytes".to_string(),
    })?;
    let mut out = Vec::new();
    for round in 0..patience {
        let points = round::points_of_round(window, OPENING_CHAIN, round).map_err(|_| {
            NodeError::Decree {
                row: "consensus_replicas".to_string(),
            }
        })?;
        let bodies = bodies_at_past_points(machine, &points, window)?;
        if bodies.is_empty() {
            break;
        }
        for body in bodies {
            if body.len() != of_answer {
                continue;
            }
            let Ok(held) = Confirmation::parse(&body[..width]) else {
                continue;
            };
            if held.window != window {
                continue;
            }
            if attest::verify_heavy(
                &held,
                &facts.electorate.root,
                &facts.aggregate,
                OPENING_CHAIN,
                round,
                &facts.threshold,
            )
            .is_ok()
            {
                out.push(held.part_nullifier);
            }
        }
    }
    Ok(out)
}

// The pledges standing at the points of the open window.
fn pledges_at_the_window(machine: &Machine, window: u64) -> Result<Vec<Pledge>, NodeError> {
    pledges_of(&bodies_at_the_window(machine, window, false)?, window)
}

// The rolls among the bodies of a window, distinct. A roll's length is a function of its own two
// counts, read off its head before an entry is read; a body shorter than that length is not a roll.
fn rolls_of(bodies: &[Vec<u8>], window: u64) -> Vec<Roll> {
    let head = size_of::<u64>() + size_of::<u32>() + size_of::<u64>();
    let mut out: Vec<Roll> = Vec::new();
    for body in bodies {
        if body.len() < head {
            continue;
        }
        let frames = u64::from(u32::from_le_bytes([body[8], body[9], body[10], body[11]]));
        let mut eight = [0u8; 8];
        eight.copy_from_slice(&body[12..20]);
        let parts = u64::from_le_bytes(eight);
        let Some(length) = Roll::len_of(frames, parts) else {
            continue;
        };
        if body.len() < length {
            continue;
        }
        let Ok(roll) = Roll::parse(&body[..length]) else {
            continue;
        };
        if roll.window == window && !out.contains(&roll) {
            out.push(roll);
        }
    }
    out
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

// **What a test of a close without a proposal reaches, and nothing else does.** Every machine of
// the electorate clears the draw, so a machine holding a final beacon and a decision always proves
// a proposal of its own, and no world a test arranges leaves it at the quorum with no proposal it
// verified. A test of that close holds back, on the thread living the window, the proposal this
// machine proved: it is handed it first — to read, and to forge from — and where it answers true,
// the proposal is neither published nor taken, and the machine waits for one standing at the points
// as a machine whose proof never came. The door every proposal is judged at is not reached from
// here. It is compiled into tests alone and is no parameter of anything this protocol runs.
#[cfg(feature = "withhold")]
pub mod withhold {
    use crate::Machine;
    use mt_state::layout::Proposal;
    use std::cell::RefCell;

    pub type Hook = Box<dyn FnMut(&Machine, &Proposal) -> bool>;

    thread_local! {
        static HOOK: RefCell<Option<Hook>> = const { RefCell::new(None) };
    }

    // From now on, on this thread, every proposal a machine proves of its own is handed to `hook`,
    // and one it answers true for is withheld. `None` disarms.
    pub fn own_proposals(hook: Option<Hook>) {
        HOOK.set(hook);
    }

    pub(crate) fn withholds(machine: &Machine, own: &Proposal) -> bool {
        HOOK.with_borrow_mut(|hook| hook.as_mut().is_some_and(|hook| hook(machine, own)))
    }
}

#[cfg(not(feature = "withhold"))]
mod withhold {
    #[inline(always)]
    pub(crate) fn withholds(_: &crate::Machine, _: &mt_state::layout::Proposal) -> bool {
        false
    }
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
#[allow(clippy::too_many_arguments)]
fn take_the_proposal(
    machine: &Machine,
    machine_secret: &[u8; 32],
    branch: &Branch,
    runs: bool,
    held: &Held<'_>,
    roots: &Roots,
    roll: &Roll,
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
            if !withhold::withholds(machine, &own) {
                let bytes = own.bytes().map_err(NodeError::Object)?;
                stand_at_the_window(machine, window, &bytes)?;
                // **The roll stands beside the proposal**, at the points of the window it closes,
                // for as long as the frames it names: what a machine that took another name
                // replays. Canon, "The roll of a proposal".
                let body = roll.bytes().map_err(NodeError::Object)?;
                stand_at_the_window(machine, window, &body)?;
                return Ok(own);
            }
        }
    }
    let mut waited = 0;
    loop {
        if let Some(found) =
            standing_proposal(machine, window, &expected, held, roots, &mut refused)?
        {
            return Ok(found);
        }
        let counts = machine.counts();
        let asking = counts
            .status()
            .map_or(0, |status| status.asking())
            .saturating_add(1);
        let on = counts.observe(true, asking, waited, patience);
        waited += 1;
        if waited >= patience {
            return Err(counts.exhausted(on, "a window no proposal of its decision ever stood at"));
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
        machine.counts().raise(&machine.counts().proposals_refused);
        refused.insert(fingerprint);
    }
    Ok(None)
}

// The bodies standing at the points of a window. A machine of the window reads its own points and
// every acquaintance's; a device walking the past reads the acquaintances' alone and holds nothing.
fn bodies_at_the_window(
    machine: &Machine,
    window: u64,
    walking: bool,
) -> Result<Vec<Vec<u8>>, NodeError> {
    let points = round::points_of_window(window).map_err(|_| NodeError::Decree {
        row: "consensus_replicas".to_string(),
    })?;
    let mut out = Vec::new();
    for point in &points {
        out.extend(if walking {
            machine.collect_public(point, window)?
        } else {
            machine.objects_at_the_point(point, window)?
        });
    }
    Ok(out)
}

// The proposals among the bodies of a window, distinct by their bytes.
fn proposals_of(bodies: &[Vec<u8>], window: u64) -> Result<Vec<Proposal>, NodeError> {
    let width = Proposal::expected_len();
    let of_proposal = mt_wire::message::body_len(width).map_err(|_| NodeError::Decree {
        row: "chunk_bytes".to_string(),
    })?;
    let mut out: Vec<Proposal> = Vec::new();
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
    Ok(out)
}

// The pledges among the bodies of a window, distinct by their bytes. They are judged where they are
// counted, against the keys the certificate of the window proves; here they are only read.
fn pledges_of(bodies: &[Vec<u8>], window: u64) -> Result<Vec<Pledge>, NodeError> {
    let width = Pledge::expected_len();
    let of_pledge = mt_wire::message::body_len(width).map_err(|_| NodeError::Decree {
        row: "chunk_bytes".to_string(),
    })?;
    let mut out: Vec<Pledge> = Vec::new();
    for body in bodies {
        if body.len() != of_pledge {
            continue;
        }
        let Ok(held) = Pledge::parse(&body[..width]) else {
            continue;
        };
        if held.window == window && !out.iter().any(|one| one.signature == held.signature) {
            out.push(held);
        }
    }
    Ok(out)
}

fn proposals_at_the_window(
    machine: &Machine,
    window: u64,
    walking: bool,
) -> Result<Vec<Proposal>, NodeError> {
    proposals_of(&bodies_at_the_window(machine, window, walking)?, window)
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
// window after the anchor — the beacons and the heavy and light attestations of the rounds, and the pledges, the
// proposals and the rolls of the proposals of the window — judges every answer at the one door and trusts none, and takes as the head the newest
// proposal whose certificate verified. What it reads it does not hold: a device walking the past
// deposits nothing and stands at no point. It reads no further than the retention, past which no
// certificate stands; a device further behind takes a fresh anchor, and the set says that is a
// change of trust. The head and the proposal before it are kept, and the head moves onto it.
pub fn join(machine: &Machine, anchor: &Anchor, patience: u32) -> Result<Anchor, NodeError> {
    joined(machine, anchor, None, patience)
}

// **A device handed a cohort as well takes the state of the head from the network** where it holds
// none to replay from (Consensus, "The join", 5): a device given a fresh anchor past the first window,
// or one that was away past the retention. The plane of the head comes table by table from the
// machines it reached and is judged against the roots of the head the walk verified; the walk replays
// over it what stands after the head and keeps it in the one writing of a close, as a replayed walk
// keeps its state. A device none of whose offers passes is refused the walk and lives no window on it.
pub fn join_under(
    machine: &Machine,
    anchor: &Anchor,
    cohort: &Cohort,
    patience: u32,
) -> Result<Anchor, NodeError> {
    joined(machine, anchor, Some(cohort), patience)
}

fn joined(
    machine: &Machine,
    anchor: &Anchor,
    cohort: Option<&Cohort>,
    patience: u32,
) -> Result<Anchor, NodeError> {
    let (head, pending) = walked(machine, anchor, patience)?;
    kept_as_walked(machine, anchor, &head, pending.as_ref(), cohort, patience)?;
    Ok(head)
}

// The walk of a join, read and judged, with nothing of it kept yet: the head, and the proposal after
// it awaiting its certificate, where the walk took one.
fn walked(
    machine: &Machine,
    anchor: &Anchor,
    patience: u32,
) -> Result<(Anchor, Option<Proposal>), NodeError> {
    let retained = mt_genesis::scalar("retained_windows").ok_or(NodeError::Decree {
        row: "retained_windows".to_string(),
    })?;
    let mut collected: Vec<StandingWindow> = Vec::new();
    let mut window = anchor.later.window;
    for _ in 0..=retained {
        window = window.checked_add(1).ok_or(NodeError::Refused {
            what: "a window past the last one a count carries",
        })?;
        let rounds = rounds_standing(machine, window, patience)?;
        if rounds.is_empty() {
            break;
        }
        let bodies = bodies_at_the_window(machine, window, true)?;
        collected.push((
            rounds,
            pledges_of(&bodies, window)?,
            proposals_of(&bodies, window)?,
            rolls_of(&bodies, window),
        ));
    }
    // Every proposal standing for a window is handed to the walk, which takes the one the window after
    // it attests and whose bytes stand at the door; a window no later window attests holds a proposal
    // awaiting its certificate, and the walk takes nothing against it.
    let rounds: Vec<Vec<certificate::Round<'_>>> = collected
        .iter()
        .map(|(rounds, _, _, _)| {
            rounds
                .iter()
                .map(|(beacon, heavy, light, ballots)| certificate::Round {
                    beacon,
                    heavy,
                    light,
                    ballots,
                })
                .collect()
        })
        .collect();
    let steps: Vec<certificate::Step<'_>> = rounds
        .iter()
        .zip(collected.iter())
        .map(
            |(certificate, (_, pledges, next, rolls))| certificate::Step {
                certificate,
                pledges,
                rolls,
                next,
            },
        )
        .collect();
    let threshold = mt_pulse::retarget::draw_threshold().map_err(|_| NodeError::Decree {
        row: "hash_bytes".to_string(),
    })?;
    // **No certificate standing is no walk**, and the device is told so rather than left at its anchor
    // as though it were the head: "a device away longer than that finds no certificate to walk and
    // takes a fresh anchor from its operator, which is a change of trust and not a verification, and
    // the set says so" (Consensus, "The join").
    if steps.is_empty() {
        return Err(NodeError::Refused {
            what: NO_CERTIFICATE_TO_WALK,
        });
    }
    certificate::walk_to_the_open(anchor, &steps, 1, &threshold, mt_state::implemented_major())
}

// What a walk leaves a machine: the head and the proposal before it kept, the head moved onto it,
// and the proposal after the head awaiting its certificate kept as the name of the window it closes
// — the window the network closed and whose agreement the next window holds. **A machine that walked
// lives the window the network stands at and not one it closed:** "It then follows the beacons of the
// open window as any machine does" (Consensus, "The join", 6). A machine that lived again a window
// the network closed would close it on a beacon of its own, a fuller cement than the network's, and
// pledge in the open window a name of its own that nobody beside it took (seen on four machines,
// 25.10.2026 10:59 UTC: the agreement of the open window in its eighth attempt, undecided).
//
// **And what it walked to, it holds the state of.** "It takes the state it needs against the roots of
// the head ... and it recomputes every root it takes rather than accepting one" (Consensus, "The
// join", 5). A machine that lives the open window needs the whole of it: the decided state of the
// window it closed by the walk is what the proposal of the open window credits and applies over, and
// a machine standing on another state takes a proposal under roots nobody else recomputes, which no
// roll replays to — the agreement of the window after parts on two names and never decides (seen on
// four machines, 27.10.2026 14:25 UTC: window 5 in its ninth attempt, the two on one name and the one
// come back on another). Where the machine holds a state to replay from, the walk keeps the state it
// replayed with the proposals in the one record of a close, and so does a device that holds none but
// was handed a cohort, from the plane of the head the network offered; where it holds none and was
// handed no cohort, it keeps the proposals alone, and lives no window on them that anybody else
// verifies.
fn kept_as_walked(
    machine: &Machine,
    anchor: &Anchor,
    head: &Anchor,
    pending: Option<&Proposal>,
    cohort: Option<&Cohort>,
    patience: u32,
) -> Result<(), NodeError> {
    machine.keep_proposal(&head.earlier)?;
    // A device that walked to this head stands in no window at or below it, nor in the window of the
    // proposal awaiting its certificate: those are closed, and a machine pledges nothing of a closed
    // window. The number that refuses them is the one the close writes, so a joiner asked to live a
    // closed window is refused at the opening rather than at the close, where its head would have to
    // leave the decision.
    let taken = pending.unwrap_or(&head.later);
    let beyond = machine
        .closed_window()?
        .is_none_or(|closed| taken.window > closed);
    if beyond {
        if let Some((plane, before)) =
            state_of_the_walk(machine, anchor, head, taken, cohort, patience)?
        {
            return machine.close(crate::Closing {
                head: Some(head.later.clone()),
                taken: taken.clone(),
                plane,
                before,
                census: None,
            });
        }
    }
    machine.keep_proposal(&head.later)?;
    machine.finalize(head.later.window)?;
    if pending.is_some() {
        machine.keep_proposal(taken)?;
    }
    machine.let_go_of(taken.window)
}

// **The state a walk reaches, replayed and not received.** From the state this machine holds — the
// decided state of its own head, kept in the record of the last window it closed, or, for a machine
// that holds no chain and walked from the first window of a network, the plane before any window —
// the decided roll of every window walked is replayed in its order, as a machine that took another
// name replays one (Consensus, "The roll of a proposal"): its frames over the decided state of the
// window before, then the parts of the decided roll before it credited, and the tables recomputed
// are the proposal's or the walk is refused. What it answers is the state of the proposal taken and
// the state of the window before it, where the replay passed that window. A machine that holds no
// state to replay from, or one from before the anchor only, and was handed a cohort starts from the
// plane of the walked head the network offers, judged against the head's roots (`plane_of_the_network`), with the rate set the walk
// rebuilds beside it (`remember_the_walked_rates`): with no proposal after the head it answers that
// plane and no state before it, which it never held. Nothing, where it holds no state and was handed
// no cohort.
fn state_of_the_walk(
    machine: &Machine,
    anchor: &Anchor,
    head: &Anchor,
    taken: &Proposal,
    cohort: Option<&Cohort>,
    patience: u32,
) -> Result<Option<(State, Option<State>)>, NodeError> {
    let known = [
        &anchor.earlier,
        &anchor.later,
        &head.earlier,
        &head.later,
        taken,
    ];
    let known = &known[..];
    let genesis = Predecessor::Genesis.id()?;
    let first = known
        .iter()
        .find(|one| one.window == 0 && one.previous == genesis);
    let empty = machine.head()?.is_none() && machine.closed_window()?.is_none();
    let since = anchor.later.window;
    // The window the replay starts from beside the proposal its state answers for, and that state.
    // A state of its own from before the anchor stands on windows the walk did not pass, which the
    // retention may have let go of; handed a cohort, the machine takes the plane of the head instead.
    let (from, mut state) = match (machine.decided_state_of_the_head()?, first) {
        (Some((window, state)), _) if window >= since || cohort.is_none() => {
            (Some((window, machine.proposal_of(window)?)), state)
        }
        (None, Some(first)) if empty => {
            let admitted = mt_proof::poseidon::Digest::of_bytes(&first.admitted_root).ok_or(
                NodeError::Refused {
                    what: "an admitted root outside the field",
                },
            )?;
            (None, State::new().with_admitted(admitted))
        }
        _ => match cohort {
            Some(cohort) => {
                let head = &head.later;
                let mut plane = plane_of_the_network(machine, head, cohort)?;
                remember_the_walked_rates(machine, known, head, since, &mut plane, patience)?;
                (Some((head.window, Some(head.clone()))), plane)
            }
            None => return Ok(None),
        },
    };
    let start = from.as_ref().map_or(0, |(window, _)| *window);
    // The proposals from the window of that state to the one taken, each the one the next names.
    let mut chain: Vec<Proposal> = vec![taken.clone()];
    while let Some(last) = chain.last() {
        if last.window <= start {
            break;
        }
        let at = last.window - 1;
        let named =
            proposal_named(machine, known, at, &last.previous)?.ok_or(NodeError::Refused {
                what: "a walked window whose proposal stands at none of its points",
            })?;
        chain.push(named);
    }
    chain.reverse();
    let mut credited: Vec<[u8; 32]> = Vec::new();
    let replayed = match &from {
        // The state answers for the proposal the walk passed at its window, or for another chain's.
        Some((window, answered)) => {
            let base = &chain[0];
            let own = answered.as_ref().and_then(|one| one.id().ok());
            if base.window != *window
                || own != base.id().ok()
                || state.tables_of(*window)? != tables_carried(base)
            {
                return Err(NodeError::Refused {
                    what: "a decided state of the head that is not the head the walk passed",
                });
            }
            credited = roll_named(machine, base)?
                .ok_or(NodeError::Refused {
                    what: "a walked window whose decided roll stands at none of its points",
                })?
                .parts;
            &chain[1..]
        }
        None => &chain[..],
    };
    let mut before = None;
    for proposal in replayed {
        let window = proposal.window;
        let roll = roll_named(machine, proposal)?.ok_or(NodeError::Refused {
            what: "a walked window whose decided roll stands at none of its points",
        })?;
        before = Some(state.clone());
        if !roll.frames.is_empty() {
            let frames = frames_of_a_past_window(machine, window, patience)?;
            for id in &roll.frames {
                let frame = frames.get(id).ok_or(NodeError::Refused {
                    what: "a frame of a walked roll that stands at no round of its window",
                })?;
                state.apply(frame, window).map_err(|_| NodeError::Refused {
                    what: "a frame of a walked roll the decided state refuses",
                })?;
            }
        }
        state.credit(&credited)?;
        if state.tables_of(window)? != tables_carried(proposal) {
            return Err(NodeError::Refused {
                what: "a walked proposal whose roots the replay of its roll does not reproduce",
            });
        }
        credited = roll.parts;
    }
    Ok(Some((state, before)))
}

// **The rate set the walk rebuilds** (decision of the author 298, B = b): no root covers it (Canon,
// "The roots of state"), so a plane offered carries none and none is taken from an offer. Every frame
// the decided roll of a walked window names — each window after the anchor up to the head, each
// proposal the one the next names — is read from the frames standing at its window, matched to the
// identifier the roll carries, and its rate nullifiers enter the plane; the frames after the head
// enter by the replay that applies them. A walk reaches back `retained_windows` and a stride of the
// horizon `proving_horizon`: the rate nullifiers of a stride's windows before the anchor stand at no
// point the walk reads, and the plane holds those of the windows walked alone.
fn remember_the_walked_rates(
    machine: &Machine,
    known: &[&Proposal],
    head: &Proposal,
    since: u64,
    plane: &mut State,
    patience: u32,
) -> Result<(), NodeError> {
    let mut at = head.clone();
    while at.window > since {
        let roll = roll_named(machine, &at)?.ok_or(NodeError::Refused {
            what: "a walked window whose decided roll stands at none of its points",
        })?;
        if !roll.frames.is_empty() {
            let frames = frames_of_a_past_window(machine, at.window, patience)?;
            for id in &roll.frames {
                let frame = frames.get(id).ok_or(NodeError::Refused {
                    what: "a frame of a walked roll that stands at no round of its window",
                })?;
                plane.remember_the_rates_of(frame);
            }
        }
        let window = at.window - 1;
        at = proposal_named(machine, known, window, &at.previous)?.ok_or(NodeError::Refused {
            what: "a walked window whose proposal stands at none of its points",
        })?;
    }
    Ok(())
}

// The proposal of `window` under the identifier `named`: one the walk handed over, one this machine
// keeps, or one standing at the points of that window.
fn proposal_named(
    machine: &Machine,
    known: &[&Proposal],
    window: u64,
    named: &[u8; 32],
) -> Result<Option<Proposal>, NodeError> {
    let is_it = |one: &Proposal| one.window == window && one.id().ok().as_ref() == Some(named);
    if let Some(one) = known.iter().find(|one| is_it(one)) {
        return Ok(Some((*one).clone()));
    }
    if let Some(one) = machine.proposal_of(window)?.filter(is_it) {
        return Ok(Some(one));
    }
    Ok(
        proposals_of(&bodies_at_a_past_window(machine, window)?, window)?
            .into_iter()
            .find(is_it),
    )
}

// The roll a proposal names, standing at the points of its window.
fn roll_named(machine: &Machine, proposal: &Proposal) -> Result<Option<Roll>, NodeError> {
    Ok(rolls_of(
        &bodies_at_a_past_window(machine, proposal.window)?,
        proposal.window,
    )
    .into_iter()
    .find(|one| one.id().ok() == Some(proposal.roll)))
}

// The seven tables a proposal carries, in the order a plane recomputes them.
fn tables_carried(proposal: &Proposal) -> [[u8; 32]; 7] {
    [
        proposal.note_root,
        proposal.nullifier_root,
        proposal.record_root,
        proposal.machine_root,
        proposal.admitted_root,
        proposal.credited_root,
        proposal.operations_root,
    ]
}

// What a walk that finds nothing to verify answers, whether the device holds nothing or lived the
// network: past the retention no certificate stands, and the anchor it would need is a trust only an
// operator can hand it.
const NO_CERTIFICATE_TO_WALK: &str = "no certificate to walk; a fresh anchor is a change of trust";

// **A machine that was away walks back from its own anchor.** "A device that lived the network holds
// its own anchor — the last two proposals it verified — and needs nobody's" (Consensus, "The join"),
// and "the machines that closed nothing verify the decisions they missed and are of the chain again"
// (Consensus, "The TimeChain"). A machine asked to live a window further on than the one after the
// last it closed walks from the two final proposals it kept — its head and the proposal before it —
// to the head the certificates standing since make final, as a joining device walks, and lives on
// from the window after the last it closed now: the window it answers. A walk that moves the head
// nowhere is no way back — the certificates of the windows it missed stand nowhere, or the chain
// stands where the machine left it — and is refused as a walk with nothing to verify, before anything
// of it is kept; a machine holding no two final proposals of its own has no anchor to walk from. A
// machine asked to live the window after the last it closed, or holding nothing, is answered that
// window, and the opening of it judges the rest.
pub fn come_back(machine: &Machine, to: u64, patience: u32) -> Result<u64, NodeError> {
    let Some(closed) = machine.closed_window()? else {
        return Ok(to);
    };
    if to <= closed.saturating_add(1) {
        return Ok(to);
    }
    let held = |window: u64| machine.proposal_of(window);
    let anchor = match machine.head()? {
        Some(head) => match (head.checked_sub(1).map(held).transpose()?, held(head)?) {
            (Some(Some(earlier)), Some(later)) => Some(Anchor { earlier, later }),
            _ => None,
        },
        None => None,
    }
    .ok_or(NodeError::Refused {
        what: "a machine away from the chain holding no two final proposals of its own",
    })?;
    let (head, pending) = walked(machine, &anchor, patience)?;
    if head.later.window <= anchor.later.window {
        return Err(NodeError::Refused {
            what: NO_CERTIFICATE_TO_WALK,
        });
    }
    kept_as_walked(machine, &anchor, &head, pending.as_ref(), None, patience)?;
    machine
        .closed_window()?
        .and_then(|closed| closed.checked_add(1))
        .ok_or(NodeError::Refused {
            what: "a window past the last one a count carries",
        })
}

// **A device that walked to a head takes the plane of that head against its roots.** Consensus, "The
// join", step 5: "It takes the state it needs against the roots of the head ... and it recomputes
// every root it takes rather than accepting one." The head is the proposal the walk kept and the store
// names, never one handed beside the plane, so a server cannot pair its tables with a root of its own;
// the cohort is the tree of admitted machines the root of the head stands over, handed as an opening
// cohort is. The plane passes the one door of its encoding, every root is folded again from the leaves
// offered and compared with the head's (State::taken_under), and only then is it held. A plane refused
// leaves the device as it was.
pub fn take_the_plane(machine: &Machine, cohort: &Cohort, offered: &[u8]) -> Result<(), NodeError> {
    let window = machine.head()?.ok_or(NodeError::Refused {
        what: "a plane offered to a device that holds no head",
    })?;
    let head = machine.proposal_of(window)?.ok_or(NodeError::Refused {
        what: "a head whose proposal this device does not hold",
    })?;
    let plane = State::decode(offered)?.taken_under(&head, cohort)?;
    machine.hold_the_plane(&head, plane)
}

// **And it asks the network for it.** Consensus, "The join", step 5, over the wire the Canon lays
// out for it (`table_query`, `table_answer`): every machine this device reached offers the plane of
// the head table by table, and each offer is judged alone by `take_the_plane` — the first whose every
// root is the head's is held, and the rest are not asked about. A device none of whose offers passes
// holds what it held, and says so.
pub fn take_the_plane_of_the_network(machine: &Machine, cohort: &Cohort) -> Result<(), NodeError> {
    let window = machine.head()?.ok_or(NodeError::Refused {
        what: "a plane asked for by a device that holds no head",
    })?;
    let head = machine.proposal_of(window)?.ok_or(NodeError::Refused {
        what: "a head whose proposal this device does not hold",
    })?;
    let plane = plane_of_the_network(machine, &head, cohort)?;
    machine.hold_the_plane(&head, plane)
}

// The plane of `head` as the machines this one reached offer it, each offer passing the one door of
// its encoding and judged alone against the roots of that head (State::taken_under): the first that
// passes, and nothing held by it — the caller keeps it, in a close or beside the head — or the
// refusal of the last offer where none passes.
fn plane_of_the_network(
    machine: &Machine,
    head: &Proposal,
    cohort: &Cohort,
) -> Result<State, NodeError> {
    let mut refused = NodeError::Refused {
        what: "no machine reached offered the plane of the head",
    };
    for offered in machine.planes_offered(head.window, cohort.root())? {
        match State::decode(&offered).and_then(|plane| plane.taken_under(head, cohort)) {
            Ok(plane) => return Ok(plane),
            Err(why) => refused = why,
        }
    }
    Err(refused)
}

// A beacon of a round as a walk reads it off the points: the beacon, the heavy and the light
// attestations that answered it, and the ballots standing beside it.
type StandingRound = (
    Beacon,
    Vec<Confirmation>,
    Vec<LightAttestation>,
    Vec<Ballot>,
);

// A window as a walk reads it off the points: the rounds standing at them, and the pledges, the
// proposals and the rolls of the proposals of the window.
type StandingWindow = (Vec<StandingRound>, Vec<Pledge>, Vec<Proposal>, Vec<Roll>);

// The beacons of every round of a window standing at its points, each beside the heavy and the light
// attestations that answered it — the light ones because a final round answered by them alone is the
// ordinary close, and a final beacon nobody answered closes nothing (Consensus, "The certificate of a
// window") — read until a round holds no beacon or the budget of reads runs out. The ballots of
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
            let light: Vec<LightAttestation> = objects
                .light
                .iter()
                .filter(|one| one.attested.contains(&id))
                .cloned()
                .collect();
            out.push((beacon, heavy, light, ballots.take().unwrap_or_default()));
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
