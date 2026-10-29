// The acceptance matrix of the relation of a window (WINDOW-RELATION.md, section 4), through the
// one entry point that judges a window's closure: a window of distinct admitted machines reaching
// the quorum with honest roots and an owned ticket is accepted, and every named deviation is refused
// where the relation says it is. Nothing here is a model of the rules: every attestation is the real
// node prover's, every proof is verified by the real verifier, every proposal is signed by the key
// its ticket names.

use montana_node::attest::Standing;
use montana_node::certificate::{
    decided_of, empty_census, verify_certificate, verify_proposal, Closure, Decided, Electorate,
    Held, Predecessor, Roots, Round,
};
use montana_node::pulse::Cohort;
use montana_node::runner::Runner;
use mt_state::layout::{Ballot, Beacon, Confirmation, LightAttestation, Pledge, Proposal};
use mt_state::Layout;

const WINDOW: u64 = 1_000;
const VERSION: u32 = 0x0001_0000;

// The world outside the rules: the machines of one electorate, the aggregate the window two before
// cemented, a threshold of the draw that every machine clears, and the proposal of the window before
// as the predecessor every attestation names. The roots are inputs of this test: what the entry
// point checks is that a proposal carries the ones the verifier holds.
struct World {
    secrets: Vec<[u8; 32]>,
    standings: Vec<Standing>,
    cohort: Cohort,
    aggregate: [u8; 32],
    draw: mt_pulse::U256,
    previous: Proposal,
    roots: Roots,
}

fn a_world(secrets: &[[u8; 32]], aggregate: [u8; 32]) -> World {
    let halves: Vec<[u8; 32]> = secrets.iter().map(Cohort::half_of).collect();
    let cohort = Cohort::of(&halves).expect("the cohort stands in the tree");
    let roots = Roots {
        note_root: [0x33; 32],
        nullifier_root: [0x44; 32],
        record_root: [0x55; 32],
        machine_root: [0x66; 32],
        admitted_root: cohort.root().bytes(),
        credited_root: mt_proof::credited::empty_root().bytes(),
        operations_root: [0x88; 32],
        roll: [0xBB; 32],
        admitted_count: cohort.count(),
        census: empty_census().expect("the Decree names the census"),
    };
    let previous = Proposal {
        window: WINDOW - 1,
        protocol_version: VERSION,
        previous: [0x11; 32],
        final_beacon: [0x22; 32],
        note_root: roots.note_root,
        nullifier_root: roots.nullifier_root,
        record_root: roots.record_root,
        machine_root: roots.machine_root,
        admitted_root: roots.admitted_root,
        credited_root: roots.credited_root,
        operations_root: roots.operations_root,
        roll: roots.roll,
        admitted_count: roots.admitted_count,
        cement_aggregate: [0x99; 32],
        cement_count: cohort.count(),
        census: roots.census.clone(),
        suite_id: mt_net::SUITE,
        runner_pubkey: vec![0xA1; mt_codec::size::SIGNING_PUBLIC_KEY],
        ticket_proof: vec![0x00; mt_state::PRESENCE_PROOF_LEN],
        signature: vec![0x5E; mt_codec::size::SIGNATURE],
    };
    let name = previous.id().expect("an identifier");
    let standings = secrets
        .iter()
        .map(|secret| {
            let branch = cohort.branch_of(secret).expect("its own leaf");
            Standing::of_the_window(secret, WINDOW, &name, &branch.siblings, branch.position)
                .expect("a machine of the cohort proves its presence")
        })
        .collect();
    World {
        secrets: secrets.to_vec(),
        standings,
        cohort,
        aggregate,
        draw: mt_pulse::U256::from_be_bytes(&[0xFFu8; 32]),
        previous,
        roots,
    }
}

impl World {
    // The electorate of a young network: the cohort, and a standing too narrow to be sampled, so
    // the close is the count of machines alone.
    fn electorate(&self) -> Electorate {
        Electorate::opening(self.cohort.root(), self.cohort.count(), WINDOW)
            .expect("an opening electorate stands")
    }

    fn previous_id(&self) -> [u8; 32] {
        self.previous.id().expect("an identifier")
    }

    fn beacon(&self) -> Beacon {
        Beacon {
            window: WINDOW,
            chain: 0,
            round: 0,
            // Round zero stands on the proposal of the window two before: the one `previous` names.
            previous: self.previous.previous,
            cement_aggregate: mt_derive::aggregate::aggregate(&[], WINDOW).expect("the empty set"),
            cement_count: 0,
            cement_votes: 0,
        }
    }

    fn beacon_id(&self) -> [u8; 32] {
        self.beacon().id().expect("an identifier")
    }

    // The beacon of the next round, whose cement is the one the heavies answering round zero name:
    // the beacon the window closes on.
    fn final_beacon(&self, heavies: &[Confirmation]) -> Beacon {
        let mut parts: Vec<[u8; 32]> = heavies.iter().map(|h| h.part_nullifier).collect();
        parts.sort_unstable();
        parts.dedup();
        Beacon {
            window: WINDOW,
            chain: 0,
            round: 1,
            previous: self.beacon_id(),
            cement_aggregate: mt_derive::aggregate::aggregate(&parts, WINDOW)
                .expect("distinct parts"),
            cement_count: parts.len() as u64,
            cement_votes: 0,
        }
    }

    // The heavy attestation of one machine of the electorate, answering the opening beacon and
    // attesting the proposal of the window before.
    fn heavy(&self, at: usize) -> Confirmation {
        self.heavy_on(at, self.previous_id())
    }

    // The heavy attestation of one machine pledging `name` beside the opening beacon. A presence
    // binds the name it attests (record 309), so a name other than the one the world's standing was
    // made for is proven afresh.
    fn heavy_on(&self, at: usize, name: [u8; 32]) -> Confirmation {
        let fresh;
        let standing = if self.standings[at].name == name {
            &self.standings[at]
        } else {
            let branch = self
                .cohort
                .branch_of(&self.secrets[at])
                .expect("its own leaf");
            fresh = Standing::of_the_window(
                &self.secrets[at],
                WINDOW,
                &name,
                &branch.siblings,
                branch.position,
            )
            .expect("a machine of the cohort proves its presence");
            &fresh
        };
        standing
            .heavy(&self.secrets[at], self.beacon_id(), name)
            .expect("a heavy attestation stands")
    }

    fn pledge(&self, at: usize, attempt: u32, name: [u8; 32], since: u32) -> Pledge {
        self.standings[at]
            .pledge(&self.secrets[at], attempt, name, since)
            .expect("a pledge stands")
    }

    // The closing pledges of attempt zero on the proposal of the window before, one per machine: the
    // agreement of a window whose heavy attestations all took one name.
    fn closings(&self) -> Vec<Pledge> {
        (0..self.secrets.len())
            .map(|at| self.pledge(at, 0, self.previous_id(), 0))
            .collect()
    }

    fn runner(&self, at: usize) -> Runner {
        let secret = &self.secrets[at];
        let branch = self.cohort.branch_of(secret).expect("its own leaf");
        Runner::of_the_window(
            secret,
            WINDOW,
            &branch.siblings,
            branch.position,
            &self.aggregate,
            &self.draw,
        )
        .expect("the ticket proves")
        .expect("a threshold of everything draws every machine")
    }

    fn closure_of(&self, heavies: &[Confirmation]) -> Result<Closure, montana_node::NodeError> {
        let beacon = self.beacon();
        let rounds = [Round {
            beacon: &beacon,
            heavy: heavies,
            light: &[],
            ballots: &[],
        }];
        verify_certificate(
            WINDOW,
            &self.electorate(),
            Predecessor::Proposal(&self.previous),
            &self.aggregate,
            1,
            &rounds,
            &self.closings(),
        )
    }

    // The light attestations of every machine of the electorate answering `beacon` on `name`: what
    // answers a final round, every machine having answered the window heavily before.
    fn lights_on(&self, beacon: &Beacon, name: [u8; 32]) -> Vec<LightAttestation> {
        let id = beacon.id().expect("an identifier");
        self.standings
            .iter()
            .zip(&self.secrets)
            .map(|(standing, secret)| {
                standing
                    .light(secret, id, name)
                    .expect("a light attestation stands")
            })
            .collect()
    }

    // What the window decided, read off the certificate as a device behind reads it: the heavies
    // answering round zero, and the beacon of round one carrying their cement, answered by the light
    // attestations of the machines.
    fn decided_by(
        &self,
        heavies: &[Confirmation],
        last: &Beacon,
    ) -> Result<Decided, montana_node::NodeError> {
        self.decided_answered(heavies, last, &self.lights_on(last, self.previous_id()))
    }

    // The same reading, with the light attestations of the final round handed in by the caller.
    fn decided_answered(
        &self,
        heavies: &[Confirmation],
        last: &Beacon,
        light: &[LightAttestation],
    ) -> Result<Decided, montana_node::NodeError> {
        let first = self.beacon();
        let rounds = [
            Round {
                beacon: &first,
                heavy: heavies,
                light: &[],
                ballots: &[],
            },
            Round {
                beacon: last,
                heavy: &[],
                light,
                ballots: &[],
            },
        ];
        let closure = verify_certificate(
            WINDOW,
            &self.electorate(),
            Predecessor::Proposal(&self.previous),
            &self.aggregate,
            1,
            &rounds,
            &self.closings(),
        )?;
        decided_of(
            &last.id().expect("an identifier"),
            &self.previous.previous,
            &rounds,
            &closure,
            &self.electorate(),
        )
    }

    fn judge(&self, proposal: &Proposal, decided: &Decided) -> Result<(), montana_node::NodeError> {
        let electorate = self.electorate();
        verify_proposal(
            proposal,
            &Held {
                predecessor: Predecessor::Proposal(&self.previous),
                decided,
                electorate: &electorate,
                aggregate_two_before: &self.aggregate,
                draw_threshold: &self.draw,
                implemented_major: 1,
            },
            &self.roots,
        )
    }

    fn propose(&self, runner: &Runner, roots: &Roots, decided: &Decided) -> Proposal {
        runner
            .propose(
                VERSION,
                Predecessor::Proposal(&self.previous),
                roots,
                decided,
            )
            .expect("the proposal stands")
    }
}

fn refused(what: &'static str) -> montana_node::NodeError {
    montana_node::NodeError::Refused { what }
}

// The one-time signing key of a machine for a window under a given domain door, for the deviations
// that re-sign an object under a key the proof does not name.
fn signing_key(seed: [u8; 32]) -> (mt_suite::sign::PublicKey, mt_suite::sign::SecretKey) {
    let mut held = [0u8; mt_suite::sign::SEED_BYTES];
    held.copy_from_slice(&seed[..mt_suite::sign::SEED_BYTES]);
    mt_suite::sign::keypair_from_seed(&held)
}

#[test]
fn the_acceptance_matrix_of_the_relation_through_the_one_entry_point() {
    let world = a_world(&[[0x11u8; 32], [0x22u8; 32], [0x33u8; 32]], [0x33u8; 32]);
    let heavies: Vec<Confirmation> = (0..3).map(|at| world.heavy(at)).collect();

    // Accepted: three distinct admitted machines, every presence against the electorate root, the
    // count at the quorum, the aggregate the parts fold to.
    let closure = world
        .closure_of(&heavies)
        .expect("a window of the whole electorate closes");
    assert_eq!(closure.cement_count, 3);
    let parts: Vec<[u8; 32]> = heavies.iter().map(|h| h.part_nullifier).collect();
    assert_eq!(
        closure.cement_aggregate,
        mt_derive::aggregate::aggregate(&parts, WINDOW).expect("distinct parts")
    );

    // A repeated part is counted once: four attestations, three parts, one closure.
    let mut doubled = heavies.clone();
    doubled.push(heavies[1].clone());
    assert_eq!(
        world.closure_of(&doubled).expect("a repeat adds nothing"),
        closure
    );

    // Refused: a count strictly below the quorum of the electorate — two of three.
    assert_eq!(
        world.closure_of(&heavies[..2]),
        Err(refused("a cement below the quorum share of the electorate"))
    );

    // Refused: an electorate whose standing is sampled closes on the votes of its committee beside
    // the count, and a certificate of the whole count without the votes closes nothing. The named
    // wrong implementation closes on the count alone once the standing outgrows the committee.
    let beacon = world.beacon();
    let closes_under = |electorate: &Electorate, ballots: &[Ballot]| {
        verify_certificate(
            WINDOW,
            electorate,
            Predecessor::Proposal(&world.previous),
            &world.aggregate,
            1,
            &[Round {
                beacon: &beacon,
                heavy: &heavies,
                light: &[],
                ballots,
            }],
            &world.closings(),
        )
    };
    let seats = mt_genesis::scalar("standing_committee").expect("the Decree names it");
    let mut weighed = world.electorate();
    for entry in &mut weighed.census {
        entry.count = seats;
    }
    weighed.committee = mt_pulse::standing::committee(seats * weighed.census.len() as u64)
        .expect("the committee of a standing at its floor");
    assert_eq!(weighed.committee.expected, seats);
    assert_eq!(
        closes_under(&weighed, &[]),
        Err(refused("votes below the quorum share of the committee"))
    );
    // Refused: votes a ballot claims and its proof does not carry. A committee of three asks three
    // votes, every part's ballot claims a unit of every census under a proof of nothing, and the
    // certificate stays without a vote. The named wrong implementation reads the count a ballot
    // carries off the wire, and closes here on thirty claimed votes.
    let censuses = weighed.census.len() as u64;
    let forged: Vec<Ballot> = heavies
        .iter()
        .map(|held| Ballot {
            window: WINDOW,
            part_nullifier: held.part_nullifier,
            votes: censuses,
            proof: vec![0u8; mt_state::PROOF_LEN],
        })
        .collect();
    let mut small = world.electorate();
    small.committee.expected = 3;
    assert_eq!(
        closes_under(&small, &forged),
        Err(refused("votes below the quorum share of the committee"))
    );
    assert!(closes_under(&world.electorate(), &forged).is_ok());

    // Refused: an attestation whose presence proof stands against another electorate root. The
    // stranger attests the same beacon and the same predecessor, and is refused at the proof.
    let strangers = a_world(&[[0x44u8; 32], [0x55u8; 32], [0x66u8; 32]], world.aggregate);
    let stranger_secret = strangers.secrets[0];
    let branch = strangers
        .cohort
        .branch_of(&stranger_secret)
        .expect("its own leaf");
    let foreign = Standing::of_the_window(
        &stranger_secret,
        WINDOW,
        &world.previous_id(),
        &branch.siblings,
        branch.position,
    )
    .expect("a stranger proves its presence in its own tree")
    .heavy(&stranger_secret, world.beacon_id(), world.previous_id())
    .expect("a heavy attestation stands");
    let mut mixed = heavies.clone();
    mixed[2] = foreign;
    assert_eq!(
        world.closure_of(&mixed),
        Err(refused(
            "an attestation whose proof of presence does not verify"
        ))
    );

    // Refused: an attestation signed by a key the presence proof does not name.
    let (other_key, other_secret) =
        signing_key(mt_derive::pulse::part_key_seed(&world.secrets[1], WINDOW));
    let mut lifted = heavies[0].clone();
    lifted.answering_key = other_key.as_bytes().to_vec();
    lifted.signature = mt_suite::sign::sign(&other_secret, &lifted.signed_scope().expect("scope"))
        .expect("the other machine owns its key")
        .as_bytes()
        .to_vec();
    let mut with_lifted = heavies.clone();
    with_lifted[0] = lifted;
    assert_eq!(
        world.closure_of(&with_lifted),
        Err(refused(
            "an attestation whose proof of presence does not verify"
        ))
    );

    // What the window decided: the beacon of round one, carrying the cement the heavies of round zero
    // name, read off the certificate and linked back to the proposal of the window before.
    let last = world.final_beacon(&heavies);
    let decided = world
        .decided_by(&heavies, &last)
        .expect("a final beacon at the quorum, linked to its predecessor");
    assert_eq!(
        (decided.cement_aggregate, decided.cement_count),
        (closure.cement_aggregate, closure.cement_count)
    );

    // Refused: a final beacon whose count stands below the quorum, though every attestation behind
    // it verifies — the beacon of round zero, which carries the empty cement.
    let opening = world.beacon();
    assert_eq!(
        world.decided_by(&heavies, &opening),
        Err(refused("a cement below the quorum share of the electorate"))
    );
    // Refused: a final beacon that claims more parts than its certificate verified.
    let inflated = Beacon {
        cement_count: 4,
        ..last.clone()
    };
    assert_eq!(
        world.decided_by(&heavies, &inflated),
        Err(refused(
            "a final beacon naming more parts than its certificate verified"
        ))
    );
    // Refused: a final beacon standing on another predecessor than the proposal it finalizes.
    let unlinked = Beacon {
        previous: [0x5Au8; 32],
        ..last.clone()
    };
    assert_eq!(
        world.decided_by(&heavies, &unlinked),
        Err(refused(
            "a final beacon whose chain does not reach round zero inside the certificate"
        ))
    );

    // Accepted: the proposal of the runner who drew the window, with honest roots and its own ticket.
    let runner = world.runner(0);
    let proposal = world.propose(&runner, &world.roots, &decided);
    assert_eq!(
        proposal.bytes().expect("its own width").len(),
        Proposal::expected_len()
    );
    world
        .judge(&proposal, &decided)
        .expect("an honest proposal is accepted");

    // A second runner of the same decision writes the same name: the identifier is what the window
    // decided, so two clearings carry one identifier and either one's bytes are the proposal.
    let second = world.propose(&world.runner(1), &world.roots, &decided);
    assert_ne!(second.runner_pubkey, proposal.runner_pubkey);
    assert_eq!(second.id(), proposal.id());
    world
        .judge(&second, &decided)
        .expect("the second runner's proposal of one decision is accepted");

    // Refused: a proposal whose roots differ from the recomputed ones.
    let mut moved = world.roots.clone();
    moved.note_root[0] ^= 1;
    assert_eq!(
        world.judge(&world.propose(&runner, &moved, &decided), &decided),
        Err(refused(
            "a proposal whose roots differ from the recomputed ones"
        ))
    );
    let mut recounted = world.roots.clone();
    recounted.admitted_count += 1;
    assert_eq!(
        world.judge(&world.propose(&runner, &recounted, &decided), &decided),
        Err(refused(
            "a proposal whose roots differ from the recomputed ones"
        ))
    );
    // Refused: a proposal whose census is not the one carried from the proposal before — a count of
    // the standing moved, which the name of the proposal stands over like the roots.
    let mut recensused = world.roots.clone();
    recensused.census[0].count += 1;
    assert_eq!(
        world.judge(&world.propose(&runner, &recensused, &decided), &decided),
        Err(refused(
            "a proposal whose roots differ from the recomputed ones"
        ))
    );
    // Refused: a final beacon carrying votes no ballot of its certificate cast. The certificate here
    // holds no ballot, so any vote at all is one too many.
    let voted = Beacon {
        cement_votes: 1,
        ..last.clone()
    };
    assert_eq!(
        world.decided_by(&heavies, &voted),
        Err(refused(
            "a final beacon carrying more votes than its certificate's ballots cast"
        ))
    );

    // Refused: a proposal whose cement is not the one the certificate established — a forged count
    // under the true beacon, and a forged aggregate.
    let overcounted = Decided {
        cement_count: decided.cement_count + 1,
        ..decided
    };
    assert_eq!(
        world.judge(
            &world.propose(&runner, &world.roots, &overcounted),
            &decided
        ),
        Err(refused(
            "a proposal whose cement is not the one its certificate established"
        ))
    );
    let reweighed = Decided {
        cement_aggregate: [0x99u8; 32],
        ..decided
    };
    assert_eq!(
        world.judge(&world.propose(&runner, &world.roots, &reweighed), &decided),
        Err(refused(
            "a proposal whose cement is not the one its certificate established"
        ))
    );

    // Refused: a proposal whose predecessor is not the final proposal of the window before.
    let mut detached = proposal.clone();
    detached.previous[0] ^= 1;
    let (_, runner_secret) =
        signing_key(mt_derive::pulse::runner_key_seed(&world.secrets[0], WINDOW));
    detached.signature =
        mt_suite::sign::sign(&runner_secret, &detached.signed_scope().expect("scope"))
            .expect("the runner owns its key")
            .as_bytes()
            .to_vec();
    assert_eq!(
        world.judge(&detached, &decided),
        Err(refused(
            "a proposal whose predecessor is not the final proposal of the window before"
        ))
    );

    // Refused: a proposal signed by a key another machine's ticket proof names — the first runner's
    // ticket proof under the second machine's key, signed by the second machine, which owns that key.
    let (second_key, second_secret) =
        signing_key(mt_derive::pulse::runner_key_seed(&world.secrets[1], WINDOW));
    let mut usurped = proposal.clone();
    usurped.runner_pubkey = second_key.as_bytes().to_vec();
    usurped.signature =
        mt_suite::sign::sign(&second_secret, &usurped.signed_scope().expect("scope"))
            .expect("the second machine owns its key")
            .as_bytes()
            .to_vec();
    assert_eq!(
        world.judge(&usurped, &decided),
        Err(refused("a proposal whose ticket proof does not verify"))
    );

    // Refused: a ticket drawn against another aggregate is a draw of another window.
    let elsewhere = a_world(&[[0x11u8; 32], [0x22u8; 32], [0x33u8; 32]], [0x34u8; 32]);
    assert_eq!(
        elsewhere.judge(&proposal, &decided),
        Err(refused("a proposal whose ticket proof does not verify"))
    );

    // Two proofs of one ticket differ byte for byte and both stand: an observer holding both learns
    // nothing of the ticket from their bytes.
    let again = world.runner(0);
    assert_ne!(again.ticket_proof, runner.ticket_proof);
    world
        .judge(&world.propose(&again, &world.roots, &decided), &decided)
        .expect("a second proof of the same ticket is accepted");
}

// A machine whose ticket does not clear draws no proposal: the trace of a false statement is not
// written, so there is nothing to sign.
#[test]
fn a_machine_whose_ticket_does_not_clear_assembles_no_proposal() {
    let world = a_world(&[[0x11u8; 32], [0x22u8; 32]], [0x33u8; 32]);
    let secret = &world.secrets[0];
    let branch = world.cohort.branch_of(secret).expect("its own leaf");
    let none = Runner::of_the_window(
        secret,
        WINDOW,
        &branch.siblings,
        branch.position,
        &world.aggregate,
        &mt_pulse::U256::ZERO,
    )
    .expect("the question is answered");
    assert!(
        none.is_none(),
        "a ticket above a threshold of nothing drew the window"
    );
}

const UNDECIDED: &str = "a certificate whose agreement does not decide the proposal it finalizes";

// What a certificate makes final is what its agreement decides. Accepted: one name taken by every
// heavy and closed in attempt zero, and a split of the heavies at attempt zero decided by a later
// attempt, every heavy in the cement whatever name it pledged. Refused: no pledges, closing pledges
// below the quorum, a closing pledge under a key no heavy of the certificate proves, and a heavy that
// does not stand beside the beacon of its round. The wrong implementations refused: one finalizing
// the predecessor on the heavy attestations alone, one counting a pledge under any key, and one
// refusing a heavy that pledged another name beside its beacon.
#[test]
fn the_agreement_decides_what_a_certificate_makes_final() {
    let world = a_world(&[[0x11u8; 32], [0x22u8; 32], [0x33u8; 32]], [0x33u8; 32]);
    let x = world.previous_id();
    let y = [0x77u8; 32];
    let beacon = world.beacon();
    let under = |heavies: &[Confirmation], pledges: &[Pledge]| {
        verify_certificate(
            WINDOW,
            &world.electorate(),
            Predecessor::Proposal(&world.previous),
            &world.aggregate,
            1,
            &[Round {
                beacon: &beacon,
                heavy: heavies,
                light: &[],
                ballots: &[],
            }],
            pledges,
        )
    };
    let heavies: Vec<Confirmation> = (0..3).map(|at| world.heavy(at)).collect();
    let closings = world.closings();
    assert!(under(&heavies, &closings).is_ok());
    assert_eq!(under(&heavies, &[]), Err(refused(UNDECIDED)));
    assert_eq!(under(&heavies, &closings[..2]), Err(refused(UNDECIDED)));

    let (other_key, other_secret) =
        signing_key(mt_derive::pulse::part_key_seed(&world.secrets[0], WINDOW));
    let mut lifted = closings[2].clone();
    lifted.answering_key = other_key.as_bytes().to_vec();
    lifted.signature = mt_suite::sign::sign(&other_secret, &lifted.signed_scope().expect("scope"))
        .expect("the other machine owns its key")
        .as_bytes()
        .to_vec();
    assert_eq!(
        under(
            &heavies,
            &[closings[0].clone(), closings[1].clone(), lifted]
        ),
        Err(refused(UNDECIDED))
    );

    let split = vec![
        world.heavy_on(0, x),
        world.heavy_on(1, x),
        world.heavy_on(2, y),
    ];
    assert_eq!(under(&split, &closings), Err(refused(UNDECIDED)));
    let mut later: Vec<Pledge> = (0..3)
        .map(|at| world.pledge(at, 1, x, mt_state::STANDS_ON_NONE))
        .collect();
    later.extend((0..3).map(|at| world.pledge(at, 1, x, 1)));
    let closure = under(&split, &later).expect("a split decided by a later attempt closes");
    assert_eq!(closure.cement_count, 3);

    let astray = world.standings[0]
        .heavy(&world.secrets[0], [0x01u8; 32], x)
        .expect("a heavy attestation stands");
    assert_eq!(
        under(&[astray, heavies[1].clone(), heavies[2].clone()], &closings),
        Err(refused("an attestation outside the beacon of its round"))
    );
}

// A certificate's verdict is a function of the set of its pledges. Four machines, every heavy on the
// predecessor; machines 0 and 1 close attempt zero on it, and machine 3, faulty, closes it on the
// predecessor and on another name. Handed in either order, the certificate is accepted where the
// other name is above the predecessor and refused where it is below: the part counts under the
// lesser of its two names (Consensus, "The sanction of a double answer"). The wrong implementation
// refused: one keeping the pledge handed in first, which accepts one order and refuses the other.
#[test]
fn the_order_the_pledges_are_handed_in_changes_no_verdict() {
    let world = a_world(
        &[[0x11u8; 32], [0x22u8; 32], [0x33u8; 32], [0x44u8; 32]],
        [0x33u8; 32],
    );
    let x = world.previous_id();
    let beacon = world.beacon();
    let heavies: Vec<Confirmation> = (0..4).map(|at| world.heavy(at)).collect();
    let under = |pledges: &[Pledge]| {
        verify_certificate(
            WINDOW,
            &world.electorate(),
            Predecessor::Proposal(&world.previous),
            &world.aggregate,
            1,
            &[Round {
                beacon: &beacon,
                heavy: &heavies,
                light: &[],
                ballots: &[],
            }],
            pledges,
        )
    };
    let honest = [world.pledge(0, 0, x, 0), world.pledge(1, 0, x, 0)];
    for (other, accepted) in [([0xFFu8; 32], true), ([0x00u8; 32], false)] {
        assert_eq!(x < other, accepted);
        let on_x = world.pledge(3, 0, x, 0);
        let on_other = world.pledge(3, 0, other, 0);
        let forward = [on_x.clone(), on_other.clone()];
        let backward = [on_other, on_x];
        let one = under(&[&forward[..], &honest[..]].concat());
        let two = under(&[&backward[..], &honest[..]].concat());
        assert_eq!(one, two);
        if accepted {
            assert_eq!(one.expect("the lesser name decides").cement_count, 4);
        } else {
            assert_eq!(one, Err(refused(UNDECIDED)));
        }
    }
}

// The close counts a beacon "which a verified attestation answered" (Consensus, "The beacon a window
// closes on"), and a device verifies a certificate as the living did, so the final beacon a device
// reads off a certificate is one a verified attestation of it answered. A final round is answered by
// light attestations alone in the ordinary close — every machine drawn in it already answered the
// window heavily — so the certificate carries them. Accepted: the final beacon answered by the light
// attestations of the machines. Refused, each with the same beacon, at the quorum and linked to its
// predecessor: no light attestation at all, which a decider reading the pair and not the answer
// takes; light attestations on another name than their parts' heavies pledged, which one checking
// the key and the signature and not the name takes; light attestations answering another beacon,
// which one counting whatever stands in the round takes; and light attestations re-signed under a
// key no heavy attestation of the certificate proved, which one verifying a light attestation under
// the key it carries takes.
#[test]
fn a_final_beacon_no_verified_attestation_answered_closes_nothing() {
    const UNANSWERED: &str = "a final beacon no verified attestation of the certificate answered";
    let world = a_world(&[[0x11u8; 32], [0x22u8; 32], [0x33u8; 32]], [0x33u8; 32]);
    let heavies: Vec<Confirmation> = (0..3).map(|at| world.heavy(at)).collect();
    let last = world.final_beacon(&heavies);
    let x = world.previous_id();

    let answering = world.lights_on(&last, x);
    let decided = world
        .decided_answered(&heavies, &last, &answering)
        .expect("a final beacon the light attestations of its round answered");
    assert_eq!(decided.final_beacon, last.id().expect("an identifier"));
    // One light attestation answers a beacon as well as all of them.
    assert!(world
        .decided_answered(&heavies, &last, &answering[..1])
        .is_ok());

    assert_eq!(
        world.decided_answered(&heavies, &last, &[]),
        Err(refused(UNANSWERED))
    );
    assert_eq!(
        world.decided_answered(&heavies, &last, &world.lights_on(&last, [0x77u8; 32])),
        Err(refused(UNANSWERED))
    );
    assert_eq!(
        world.decided_answered(&heavies, &last, &world.lights_on(&world.beacon(), x)),
        Err(refused(UNANSWERED))
    );
    let (other_key, other_secret) = signing_key(mt_derive::pulse::part_key_seed(
        &world.secrets[0],
        WINDOW + 1,
    ));
    let lifted: Vec<LightAttestation> = answering
        .iter()
        .map(|held| {
            let mut lifted = held.clone();
            lifted.answering_key = other_key.as_bytes().to_vec();
            lifted.signature =
                mt_suite::sign::sign(&other_secret, &lifted.signed_scope().expect("scope"))
                    .expect("the other key signs")
                    .as_bytes()
                    .to_vec();
            lifted
        })
        .collect();
    assert_eq!(
        world.decided_answered(&heavies, &last, &lifted),
        Err(refused(UNANSWERED))
    );
}
