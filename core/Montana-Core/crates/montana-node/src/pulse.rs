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
use crate::{round, Machine, NodeError};
use mt_pulse::fold::Cement;
use mt_state::layout::{Beacon, Confirmation};
use mt_state::Layout;
use mt_wire::message::{self, Kind, POINT_BYTES};

// Where a machine stands in the tree of admitted machines, and what standing it answers with. The
// three travel together because they are one thing — what this machine is in that tree — and a
// door taking them apart would be a door a caller can hand three values that do not belong to one
// machine.
pub struct Branch {
    pub siblings: Vec<mt_proof::poseidon::Digest>,
    pub position: u64,
    pub standing: u64,
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

    // The branch one machine walks, and the standing it answers with. **A machine of an opening
    // cohort answers with one standing**, because the set fixes no standing for an admitted machine
    // and what it does fix is that the share of a window is equal — which is also what the door of
    // the close already reads, since it compares a count of attestations against a count of
    // machines. A cohort of unequal standing is not of this stage, and the day the set gives
    // standing a source it is read from there and not from here.
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
            standing: 1,
        })
    }
}

// What one machine holds of the window it is in: what it answers with, the cement it has gathered,
// and the beacon it last saw.
pub struct Pulse {
    pub window: u64,
    pub chain: u8,
    pub standing: Standing,
    pub cement: Cement,
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
    // proof and the standing; every later one is light, and inherits the key already proven.
    answered_heavily: bool,
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
    ) -> Result<Self, NodeError> {
        let (window, chain, _) = at;
        let standing = Standing::of_the_window(
            machine_secret,
            window,
            &branch.siblings,
            branch.position,
            branch.standing,
        )?;
        machine.enter_round(window, chain, 0)?;
        Ok(Self {
            window,
            chain,
            standing,
            cement: Cement::new(),
            round: 0,
            previous: previous_proposal,
            of_the_window_before: previous_proposal,
            answered_heavily: false,
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
        let ticket = mt_derive::aggregate::ticket(machine_secret, aggregate);
        mt_pulse::clears(&ticket, threshold)
    }

    // The beacon the runner publishes to open a round: the window, the chain, the round, the
    // identifier of its predecessor and the cement state it has gathered.
    pub fn beacon_of_this_round(&self) -> Result<Beacon, NodeError> {
        let state = match self.cement.state() {
            Some(held) => held.serialize(),
            // A window that cemented nothing carries no state, and a beacon of such a window is a
            // beacon before the first attestation of its chain.
            None => vec![0u8; mt_state::WEIGHT_COMMIT_BYTES],
        };
        round::beacon(self.window, self.chain, self.round, self.previous, state).map_err(
            |e| match e {
                round::RoundError::Object(e) => NodeError::Object(e),
                round::RoundError::Decree => NodeError::Decree {
                    row: "consensus_replicas".to_string(),
                },
            },
        )
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
    // and folds it into the cement at its first appearance. A repetition adds nothing and is
    // lawful, which is what the answer of `false` says.
    pub fn gather(
        &mut self,
        held: &Confirmation,
        admitted_root: &mt_proof::poseidon::Digest,
        aggregate: &[u8; 32],
        round_of_it: u32,
        threshold: &mt_pulse::U256,
    ) -> Result<bool, NodeError> {
        self.gather_saying(held, admitted_root, aggregate, round_of_it, threshold, None)
    }

    // The same fold, writing to the account of a machine why an attestation did not enter. The wire
    // tells whoever published nothing at all; the operator of this machine is told all of it.
    pub fn gather_saying(
        &mut self,
        held: &Confirmation,
        admitted_root: &mt_proof::poseidon::Digest,
        aggregate: &[u8; 32],
        round_of_it: u32,
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
        // A part-nullifier already in the cement is answered before its proof is looked at. The
        // fold takes one part-nullifier at most once, so verifying a second appearance decides
        // nothing — and a machine standing at a round reads what stands there over and over, so a
        // verification before this test is a core spent on an answer already known.
        if self.cement.holds(&held.part_nullifier) {
            if let Some(counts) = counts {
                counts.raise(&counts.attestations_repeated);
            }
            return Ok(false);
        }
        if let Err(why) = attest::verify_heavy(
            held,
            admitted_root,
            aggregate,
            self.chain,
            round_of_it,
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
        let leaf = attest::leaf_of(held)?;
        let entered = self.cement.add(&leaf).map_err(|_| NodeError::Refused {
            what: "an attestation the cement could not take",
        })?;
        if let Some(counts) = counts {
            if entered {
                counts.raise(&counts.attestations_entered);
            } else {
                counts.raise(&counts.attestations_repeated);
            }
        }
        Ok(entered)
    }

    // Whether a runner attempts to close this window. A runner never reads the cement — the cement
    // is a sum of commitments and only the owners of what entered can open it — so it does not
    // decide the close and cannot. What it decides is whether to attempt: it builds the proof of
    // the window, and the circuit asserts the cement against the quorum share of the committed
    // total. A window below the share yields no proof, because the assertion is false and a false
    // statement does not prove; a window at or above it yields one, and that proof is the close.
    //
    // What a runner reads to know when to attempt is public and names nobody: how many
    // part-nullifiers its cement holds, and how many machines the tree of the admitted carries. An
    // attempt below the share is certain to fail, so it is not made; at or above it the attempt is
    // made and the circuit decides. Counting is never the rule — the standing the circuit opens is
    // — and this door is only what keeps a runner from attempting what it knows cannot stand.
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

    // Whether the standing the circuit opens reaches the share. It is the same rule the attempt
    // above is drawn from, over the quantities only a circuit holds, and it exists so the assertion
    // a window's proof carries and the attempt a runner makes are read out of one place.
    pub fn closes(&self, cemented_standing: u128, total_standing: u128) -> Result<bool, NodeError> {
        mt_pulse::close::closes(cemented_standing, total_standing, u64::from(self.round)).map_err(
            |_| NodeError::Decree {
                row: "confirmation_quorum".to_string(),
            },
        )
    }

    // How many machines the cement names. It is what the count of the living is read off, and it is
    // a count of part-nullifiers rather than of standing.
    pub fn living(&self) -> usize {
        self.cement.count()
    }

    // Moving to the next round: the beacon of this one becomes the predecessor of the next, and the
    // machine stands at the points of the round it moves into.
    // **Only the link of the beacon moves.** What an attestation attests beside the beacon of its
    // round is the identifier of the window before, and that is a fact about the window rather than
    // about the round — a machine that advanced it with the rounds would attest the beacon it came
    // from instead, and every attestation after the first round would confirm nothing of the window
    // whose cement it is entering.
    pub fn advance(&mut self, machine: &Machine, beacon: &Beacon) -> Result<(), NodeError> {
        self.previous = beacon.id().map_err(NodeError::Object)?;
        self.round = self.round.checked_add(1).ok_or(NodeError::Refused {
            what: "a round past the last one a count carries",
        })?;
        machine.enter_round(self.window, self.chain, self.round)
    }

    // The right this machine takes of the window it lived in, once that window closed.
    pub fn right(&self, machine_secret: &[u8; 32]) -> Result<attest::Right, NodeError> {
        attest::right_of(machine_secret, self.window, self.cement.count())
    }
}

// What a machine lived of one window: the rounds it stood, the machines its cement named, and the
// right that window minted to it.
pub struct Lived {
    pub window: u64,
    pub rounds: u32,
    pub living: usize,
    pub right: attest::Right,
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
use mt_pulse::{OPENING_CHAIN, REACHES_AGAIN_EVERY, SAYS_EVERY};

// **An acquaintance that did not answer at the start is dialled again until it does.** Two machines
// of one cohort cannot both find the other listening when each starts, so the one started first
// dials into nothing; a machine that never dials again holds no link of its own, can be written into
// and never ask, and the first window it falls one behind in is a window it never leaves — which is
// how Lauterbourg stood in window 1 while Moscow waited in window 2 (06.10.2026). It dials on a
// thread of its own and says when the link stands; a link held is used by every asking after it,
// since what a machine asks over is read from what it holds at the moment it asks.
pub fn reach_again(machine: std::sync::Arc<Machine>, line: String) {
    std::thread::spawn(move || loop {
        std::thread::sleep(ASKS_AGAIN_AFTER * REACHES_AGAIN_EVERY);
        if let Ok(transcript) = machine.reach_and_hold(&line) {
            let shown: String = transcript.iter().map(|b| format!("{b:02x}")).collect();
            println!("reached on dialling again {line}\n  transcript {shown}");
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
fn of_the_round(
    machine: &Machine,
    window: u64,
    chain: u8,
    round: u32,
) -> Result<(Vec<Beacon>, Vec<Confirmation>), NodeError> {
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
    let mut beacons: Vec<Beacon> = Vec::new();
    let mut answers: Vec<Confirmation> = Vec::new();
    for point in &points {
        for body in machine.objects_at_the_point(point, window)? {
            if body.len() == of_beacon {
                let Ok(held) = Beacon::parse(&body[..Beacon::expected_len()]) else {
                    continue;
                };
                // **A body of one length is not an object of one kind.** What stands at a point is
                // padded to the group of the erasure code, so a beacon of six thousand bytes and a
                // light attestation of five thousand four hundred arrive as bodies of the identical
                // length — and a reader that classified by that length alone would read every
                // answer it published as a new question. It did: the machine answered its own
                // attestation, published another, read that one back as a beacon too, and filled
                // the point with its own echo until the point refused the one heavy attestation
                // that would have closed the window. So the object is asked what it says of itself:
                // a beacon of this round names this window, this chain and this round, and bytes
                // that name anything else are of another kind however long they are.
                if held.window != window || held.chain != chain || held.round != round {
                    continue;
                }
                // One object carried three times is one object: a point of the same round holding
                // the same beacon adds nothing.
                if !beacons.iter().any(|one| one.id().ok() == held.id().ok()) {
                    beacons.push(held);
                }
            } else if body.len() == of_answer {
                let Ok(held) = Confirmation::parse(&body[..Confirmation::expected_len()]) else {
                    continue;
                };
                // The same question asked of an attestation: it carries the window it attests, and
                // an object of another window standing at this point is not of this round.
                if held.window != window {
                    continue;
                }
                // Attestations are not thinned here. One machine answers every version of a
                // round it sees, so two attestations of one part-nullifier stand at a point — the
                // heavy one carrying the proof and the light ones inheriting the key it proved —
                // and a reader that kept one per part-nullifier could keep a light one and lose the
                // heavy. What thins them is the cement, which takes a part-nullifier once.
                answers.push(held);
            }
        }
    }
    Ok((beacons, answers))
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
// **Nothing here measures time.** What moves a round is a beacon arriving, and what closes a window
// is its cement. The one duration in this file is how often a machine asks, and a machine that
// asked at another rate would cement the same windows.
//
// `patience` is how many askings a machine spends at one round before giving that round up, and it
// is of the operator: a machine whose acquaintances have gone silent stops waiting on them rather
// than standing at one round for ever.
// **What a machine does of its own inside a window, and why it cannot be done after one.** A frame
// stands at the points of the round its slot names, and a machine holds those points only while it
// stands in that round: the moment its window closes it releases them. So an errand run after the
// window — a right redeemed, a payment made — publishes into points nobody holds any more, and the
// only machine that takes it is one still lagging in the window the payer already left. It is run
// here instead: the machine has entered the round and has not yet attested, so every other machine
// is still standing where the frame lands and applies it before the cement it is waiting on
// completes.
pub type Errand<'a> = &'a dyn Fn(&Machine, u64) -> Result<(), NodeError>;

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
    // **Two thresholds, because they are two questions.** The draw asks who runs a window and is
    // walked by the retarget from the opening value; a round asks who answers it and is computed
    // from the count of admitted machines, so that the crowd of a round never falls below the floor
    // the Decree names and no round is ever one nobody was drawn for.
    let of_the_draw = mt_pulse::retarget::opening_threshold().map_err(|_| NodeError::Decree {
        row: "hash_bytes".to_string(),
    })?;
    let of_a_round =
        mt_pulse::retarget::round_threshold(cohort.count(), 1).map_err(|_| NodeError::Decree {
            row: "round_floor".to_string(),
        })?;
    let mut previous = [0u8; 32];
    let mut out = Vec::new();
    for step in 0..windows {
        let window = from.checked_add(step).ok_or(NodeError::Refused {
            what: "a window past the last one a count carries",
        })?;
        // The aggregate of a window is the cemented set of the window two before it. An opening
        // network has none, and the aggregate of no signers is what the set freezes for exactly
        // that.
        let aggregate =
            mt_derive::aggregate::aggregate(&[], window).map_err(|_| NodeError::Refused {
                what: "an aggregate over a repeated identity",
            })?;
        let branch = cohort
            .branch_of(&of_the_machine)
            .ok_or(NodeError::Refused {
                what: "a machine that stands in no cohort of this window",
            })?;
        let mut pulse = Pulse::open(
            machine,
            &of_the_machine,
            (window, OPENING_CHAIN, 0),
            &branch,
            previous,
        )?;
        // The errand of this machine, done in the first window it lives and before it attests
        // anything of that window.
        if step == 0 {
            if let Some(errand) = errand {
                errand(machine, window)?;
            }
        }
        let runs = Pulse::runs_the_chain(&of_the_machine, &aggregate, &of_the_draw);
        let answered: Beacon = loop {
            if runs {
                let beacon = pulse.beacon_of_this_round()?;
                let bytes = beacon.bytes().map_err(NodeError::Object)?;
                stand_at_the_round(machine, window, OPENING_CHAIN, pulse.round, &bytes)?;
            }
            let mut waited = 0;
            let beacons = loop {
                let (beacons, _) = of_the_round(machine, window, OPENING_CHAIN, pulse.round)?;
                if !beacons.is_empty() {
                    break beacons;
                }
                waited += 1;
                if waited >= patience {
                    return Err(NodeError::Refused {
                        what: "a round no beacon ever stood at",
                    });
                }
                std::thread::sleep(ASKS_AGAIN_AFTER);
            };
            // And what else stands at this round enters the state. A frame stands at the round
            // points of the round its canonical slot names, so a machine standing at a round is
            // already holding what was published there: it verifies each against the tree as it
            // stands and appends, and a frame it has already applied is refused by its own
            // nullifiers rather than by a memory of having seen it.
            let _ = machine.apply_what_stands();
            // **Every machine gathers, and not the runner alone.** A window is finalized on
            // confirmations reaching the quorum, and a machine that waited to be told would be
            // taking somebody's word for a cement it can verify itself. What arrives is verified as
            // any far side verifies it, and folded at its first appearance; a repetition adds
            // nothing and is lawful.
            let mut waited = 0;
            let mut seen: Vec<[u8; 32]> = Vec::new();
            let mut answers_seen;
            // What this machine last said it held, so that a change is what makes it speak.
            let mut said = (usize::MAX, usize::MAX, usize::MAX);
            let mut ordered = beacons;
            let closed = loop {
                // **A version that arrives after this machine answered still gets an answer.** A
                // machine answers every valid version of a round it sees, and the versions of a
                // round do not all arrive at once; a machine that read the beacons once and then
                // only gathered would leave the slower runner unanswered for the whole round.
                for beacon in &ordered {
                    let id = beacon.id().map_err(NodeError::Object)?;
                    if seen.contains(&id) {
                        continue;
                    }
                    seen.push(id);
                    if let Some(bytes) =
                        pulse.answer(&of_the_machine, beacon, &aggregate, &of_a_round)?
                    {
                        stand_at_the_round(machine, window, OPENING_CHAIN, pulse.round, &bytes)?;
                    }
                }
                let (again, standing) = of_the_round(machine, window, OPENING_CHAIN, pulse.round)?;
                ordered = again;
                answers_seen = standing.len();
                for held in &standing {
                    let _ = pulse.gather_saying(
                        held,
                        &cohort.root(),
                        &aggregate,
                        pulse.round,
                        &of_a_round,
                        Some(&counts),
                    );
                }
                if pulse.attempts_the_close(cohort.count())? {
                    // **What arrived in the same breath as the close is applied before the machine
                    // leaves.** A frame published inside a window stands at the very points the
                    // attestation that completes the cement stands at, so both are pulled in one
                    // asking — and a machine that saw the cement and walked out would drop the
                    // frame it had already taken over the wire. The payee then holds a note whose
                    // position exists in the payer's tree and in nobody else's, which is a payment
                    // that never happened for everyone but the one who made it.
                    let _ = machine.apply_what_stands();
                    break true;
                }
                waited += 1;
                if waited >= patience {
                    break false;
                }
                // **The account is written while the machine waits, and not only when it moves.** A
                // round is made of waiting, so a machine that spoke once a round would be silent for
                // as long as the waiting lasts — which is exactly the stretch an operator needs to
                // see into. It writes what it is holding and what it has done, every so many
                // askings, and nothing of it names anybody.
                // **A machine speaks when what it holds changes, and again while nothing does.**
                // Counting askings alone measures the wrong thing: an asking that pulls a round
                // over the wire and opens every cell of it costs a hundred times one that finds
                // nothing new, so a machine bound to speak every so many askings can close a whole
                // window without a word. What an operator needs to see is the **sequence of
                // arrivals** — every time the cement grows or a new attestation stands — and, while
                // nothing arrives, a heartbeat that says so.
                let held = (pulse.living(), answers_seen, ordered.len());
                if held != said || waited % SAYS_EVERY == 0 {
                    said = held;
                    println!(
                        "window {} round {} waiting: cement {} of {}, beacons {}, standing {} | {}",
                        window,
                        pulse.round,
                        held.0,
                        cohort.count(),
                        held.2,
                        held.1,
                        counts.line()
                    );
                }
                std::thread::sleep(ASKS_AGAIN_AFTER);
            };
            // Two versions of one round are resolved by the smaller identifier, which is the rule
            // the set states for two clearings of one height.
            ordered.sort_by_key(|one| one.id().unwrap_or([0xFFu8; 32]));
            let taken = ordered.first().cloned().ok_or(NodeError::Refused {
                what: "a round whose beacons vanished between two readings",
            })?;
            if closed {
                break taken;
            }
            // **A machine that stands at a round says why.** A window closes on its cement, and a
            // cement fills as the attestations of the others arrive; an operator watching a machine
            // stand at one round for minutes is owed the count it is waiting on rather than
            // silence. What this names is public and names nobody: the round, how many machines the
            // cement holds, and how many the window admits.
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
                cohort.count(),
                ordered.len(),
                answers_seen,
                counts.line()
            );
            pulse.advance(machine, &taken)?;
        };
        // What the next window links back to. The set links a window to the **proposal** that closed
        // the one before it; a proposal stands on the proof of a window, which this tree carries and
        // does not yet build inside a running machine, so what a machine carries forward here is the
        // identifier of the beacon its window closed on. `AUDIT.md` holds the proof of a window with
        // what it blocks, and this is the one place that stands in for it.
        previous = answered.id().map_err(NodeError::Object)?;
        let lived = Lived {
            window,
            rounds: pulse.round,
            living: pulse.living(),
            right: pulse.right(&of_the_machine)?,
        };
        // **A window closed is said when it closes.** A machine living until it is stopped returns
        // nothing, so what it lived written only at the return is written never, and an operator
        // watching a chain that moves sees a machine that says nothing. The link the next window
        // carries back is said with it: it is the one value of this window the next one stands on.
        let link: String = previous.iter().map(|b| format!("{b:02x}")).collect();
        println!(
            "window {} closed after {} rounds on a cement naming {} machines; the next links to {} | it mints {} to this machine, accepted in window {}",
            lived.window, lived.rounds, lived.living, link, lived.right.share, lived.right.accepted_in
        );
        out.push(lived);
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
