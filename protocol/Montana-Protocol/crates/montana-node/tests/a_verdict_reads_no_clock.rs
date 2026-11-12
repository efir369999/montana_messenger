// The verdict of a window is one whatever the order its bytes arrive in, whatever budget a reader
// spends on them past their count, and whatever clock the machine counting its agreement runs on.
// Consensus, "Invariants of the TimeChain": "No quantity from outside the protocol — a clock, a date,
// a duration — enters any object of the chain, and none of its rules reads one"; "Invariants of the
// round": "no count, no measure and no clock closes it"; "How a machine pledges": the span of an
// attempt "is conduct, read by no rule of acceptance, and a machine that waited twice as long
// reaches the same decisions later". Constitution, I-15: no system clock and no monotonic clock
// inside protocol logic.
//
// **The world outside the rules, arranged by this test.** The bytes of two windows after an anchor,
// the second split — three of four attesting the proposal its agreement decides and the fourth
// another name, offered beside it — handed to the door in the order they were made, reversed, and
// turned by one, and read by a reader whose budget of rounds is the count of the rounds, one past
// it, a thousand times it, or short of it. Four machines counting one book of the agreement under a
// split of two and two, the clock of one of them running at the pace of the others, three times it
// and a thousand times it. And a machine whose own beacon never stands at the points of its round.
//
// **The wrong implementations it refuses**, named before the assertions: a door whose closure, head
// or decided name depends on the order the attestations, the pledges, the rolls, the proposals or
// the rounds arrive in — one arrival parts from the others; a walk that takes a head off the part of
// a window a short budget read — it stands elsewhere than at its anchor or a refusal; a count of the
// agreement that reads the clock of the machine counting it — the machine whose clock runs fast
// decides another name or in another attempt, or one of the four closes on a name the agreement
// does not decide; and a pulse that closes a round no beacon stood at once its budget runs out, or
// moves its head, its closed window or its record of the agreement on the way out.

use montana_node::agreement::{self, Book, Kind, Name, Part, Place};
use montana_node::attempt::{span_of, Action, Conduct, Record, Replayed, Seen};
use montana_node::certificate::{
    decided_of, verify_certificate, walk, Anchor, Closure, Decided, Electorate, Predecessor, Roots,
    Round, Step,
};
use montana_node::pulse::{self, Cohort};
use montana_node::runner::Runner;
use montana_node::{Configuration, Machine, NodeError};
use mt_state::layout::{Beacon, Confirmation, LightAttestation, Pledge, Proposal, Roll};
use std::collections::BTreeMap;

mod common;
use common::walk::{closing, handed, heavies, lights, opening};
use common::Scratch;

const ANCHOR: u64 = 2_000;

fn refused(what: &'static str) -> NodeError {
    NodeError::Refused { what }
}

// The three orders of arrival: as made, reversed, and turned by one.
#[derive(Clone, Copy, Debug)]
enum Arrival {
    AsMade,
    Reversed,
    Turned,
}

const ARRIVALS: [Arrival; 3] = [Arrival::AsMade, Arrival::Reversed, Arrival::Turned];

fn arrived<T: Clone>(made: &[T], arrival: Arrival) -> Vec<T> {
    let mut out = made.to_vec();
    match arrival {
        Arrival::AsMade => {}
        Arrival::Reversed => out.reverse(),
        Arrival::Turned => {
            if !out.is_empty() {
                out.rotate_left(1);
            }
        }
    }
    out
}

// A window as a reader hands it to the door: its rounds, each a beacon with the attestations that
// answered it, its pledges, its rolls and the proposals standing for it.
#[derive(Clone)]
struct Window {
    rounds: Vec<(Beacon, Vec<Confirmation>, Vec<LightAttestation>)>,
    pledges: Vec<Pledge>,
    rolls: Vec<Roll>,
    next: Vec<Proposal>,
}

impl Window {
    // The window as it arrived in `arrival`, read with a budget of `budget` rounds: the rounds from
    // zero up, as many as the budget reaches, then everything in the order of arrival.
    fn read(&self, arrival: Arrival, budget: usize) -> Self {
        let mut rounds = self.rounds.clone();
        rounds.sort_by_key(|(beacon, _, _)| beacon.round);
        rounds.truncate(budget);
        let rounds = arrived(&rounds, arrival)
            .into_iter()
            .map(|(beacon, heavy, light)| {
                (beacon, arrived(&heavy, arrival), arrived(&light, arrival))
            })
            .collect();
        Self {
            rounds,
            pledges: arrived(&self.pledges, arrival),
            rolls: arrived(&self.rolls, arrival),
            next: arrived(&self.next, arrival),
        }
    }

    fn rounds(&self) -> Vec<Round<'_>> {
        self.rounds
            .iter()
            .map(|(beacon, heavy, light)| Round {
                beacon,
                heavy,
                light,
                ballots: &[],
            })
            .collect()
    }
}

// The verdict of the door on the two windows after the anchor: the closure of each, what the first
// decided, and the head of the walk.
#[derive(Debug, PartialEq)]
struct Verdict {
    closures: Vec<Result<Closure, NodeError>>,
    decided: Result<Decided, NodeError>,
    head: Result<Anchor, NodeError>,
}

// The anchor, the two windows after it, the final beacon of the first and the name of the proposal
// the agreement of the second decides.
struct History {
    anchor: Anchor,
    windows: [Window; 2],
    final_beacon: [u8; 32],
    decided_next: [u8; 32],
}

impl History {
    fn verdict(&self, arrival: Arrival, budget: usize) -> Verdict {
        let first = self.windows[0].read(arrival, budget);
        let second = self.windows[1].read(arrival, budget);
        let (first_rounds, second_rounds) = (first.rounds(), second.rounds());
        let (earlier, later) = (&self.anchor.earlier, &self.anchor.later);
        let electorate = Electorate::of(earlier).expect("the electorate of the first window");
        let first_closure = verify_certificate(
            later.window + 1,
            &electorate,
            Predecessor::Proposal(later),
            &earlier.cement_aggregate,
            1,
            &first_rounds,
            &first.pledges,
        );
        let decided = match &first_closure {
            Ok(closure) => decided_of(
                &self.final_beacon,
                &earlier.id().expect("an identifier"),
                &first_rounds,
                closure,
                &electorate,
            ),
            Err(_) => Err(refused("no certificate of the first window stands")),
        };
        let decided_next = first
            .next
            .iter()
            .find(|one| one.id().ok() == Some(self.decided_next));
        let second_closure = match decided_next {
            Some(next) => verify_certificate(
                later.window + 2,
                &Electorate::of(later).expect("the electorate of the second window"),
                Predecessor::Proposal(next),
                &later.cement_aggregate,
                1,
                &second_rounds,
                &second.pledges,
            ),
            None => Err(refused("no proposal of the decision arrived")),
        };
        let draw = mt_pulse::retarget::draw_threshold().expect("the threshold of the draw");
        let steps = [
            Step {
                certificate: &first_rounds,
                pledges: &first.pledges,
                rolls: &first.rolls,
                next: &first.next,
            },
            Step {
                certificate: &second_rounds,
                pledges: &second.pledges,
                rolls: &second.rolls,
                next: &second.next,
            },
        ];
        Verdict {
            closures: vec![first_closure, second_closure],
            decided,
            head: walk(
                &self.anchor,
                &steps,
                1,
                &draw,
                mt_state::implemented_major(),
            ),
        }
    }
}

// Two windows after an anchor, as `a_walk_from_an_anchor` makes them: the first closed by the two
// machines its electorate holds and answered lightly in its final round, the second split, three of
// four attesting the proposal of the first and the fourth another proposal of the same decision
// offered beside it.
fn a_history() -> History {
    let (one, two, three, four) = ([0x11u8; 32], [0x22u8; 32], [0x33u8; 32], [0x44u8; 32]);
    let pair = Cohort::of(&[Cohort::half_of(&one), Cohort::half_of(&two)]).expect("a tree of two");
    let all = Cohort::of(&[
        Cohort::half_of(&one),
        Cohort::half_of(&two),
        Cohort::half_of(&three),
        Cohort::half_of(&four),
    ])
    .expect("a tree of four");
    let draw = mt_pulse::retarget::draw_threshold().expect("the threshold of the draw");
    let earlier = handed(ANCHOR, [0x10; 32], &pair, [0x0Au8; 32]);
    let later = handed(
        ANCHOR + 1,
        earlier.id().expect("an identifier"),
        &all,
        [0x0Bu8; 32],
    );
    let (earlier_id, later_id) = (
        earlier.id().expect("an identifier"),
        later.id().expect("an identifier"),
    );

    let window = ANCHOR + 2;
    let first = opening(window, earlier_id);
    let (answered, closed, standing) = heavies(&[one, two], &pair, window, &first, later_id);
    let last = closing(window, &first, &answered);
    let answering = lights(&standing, &[one, two], &last, later_id);
    let mut parts: Vec<[u8; 32]> = answered.iter().map(|h| h.part_nullifier).collect();
    parts.sort_unstable();
    let roll = Roll {
        window,
        frames: Vec::new(),
        parts,
    };
    let rounds = [
        Round {
            beacon: &first,
            heavy: &answered,
            light: &[],
            ballots: &[],
        },
        Round {
            beacon: &last,
            heavy: &[],
            light: &answering,
            ballots: &[],
        },
    ];
    let electorate = Electorate::of(&earlier).expect("the electorate of the window");
    let closure = verify_certificate(
        window,
        &electorate,
        Predecessor::Proposal(&later),
        &earlier.cement_aggregate,
        1,
        &rounds,
        &closed,
    )
    .expect("the certificate of the first window");
    let decided = decided_of(
        &last.id().expect("an identifier"),
        &earlier_id,
        &rounds,
        &closure,
        &electorate,
    )
    .expect("the final beacon of the window");
    let branch = pair.branch_of(&one).expect("its own leaf");
    let runner = Runner::of_the_window(
        &one,
        window,
        &branch.siblings,
        branch.position,
        &earlier.cement_aggregate,
        &draw,
    )
    .expect("the ticket proves")
    .expect("the threshold of the draw clears every machine");
    let roots = Roots {
        note_root: [0x31; 32],
        nullifier_root: [0x41; 32],
        record_root: [0x51; 32],
        machine_root: [0x61; 32],
        admitted_root: all.root().bytes(),
        credited_root: [0x8A; 32],
        operations_root: [0x81; 32],
        roll: roll.id().expect("an identifier"),
        admitted_count: all.count(),
        census: later.census.clone(),
    };
    let next = runner
        .propose(
            mt_state::PROTOCOL_VERSION,
            Predecessor::Proposal(&later),
            &roots,
            &decided,
        )
        .expect("the proposal stands");
    let mut other_roots = roots.clone();
    other_roots.note_root[0] ^= 1;
    let other = runner
        .propose(
            mt_state::PROTOCOL_VERSION,
            Predecessor::Proposal(&later),
            &other_roots,
            &decided,
        )
        .expect("the other proposal stands");

    let after = ANCHOR + 3;
    let first_after = opening(after, later_id);
    let (mut split, mut split_closed, _) = heavies(
        &[one, two, three],
        &all,
        after,
        &first_after,
        next.id().expect("an identifier"),
    );
    let (astray, astray_closed, _) = heavies(
        &[four],
        &all,
        after,
        &first_after,
        other.id().expect("an identifier"),
    );
    split.extend(astray);
    split_closed.extend(astray_closed);
    let decided_next = next.id().expect("an identifier");

    History {
        anchor: Anchor { earlier, later },
        windows: [
            Window {
                rounds: vec![
                    (first, answered, Vec::new()),
                    (last.clone(), Vec::new(), answering),
                ],
                pledges: closed,
                rolls: vec![roll],
                next: vec![other, next],
            },
            Window {
                rounds: vec![(first_after, split, Vec::new())],
                pledges: split_closed,
                rolls: Vec::new(),
                next: Vec::new(),
            },
        ],
        final_beacon: last.id().expect("an identifier"),
        decided_next,
    }
}

#[test]
fn the_door_answers_one_verdict_whatever_the_order_of_arrival_and_the_budget_of_reading() {
    let history = a_history();
    let count = history
        .windows
        .iter()
        .map(|window| window.rounds.len())
        .max()
        .expect("two windows");
    let honest = history.verdict(Arrival::AsMade, count);
    let closure = honest.closures[0]
        .as_ref()
        .expect("the first window closes");
    assert_eq!(closure.cement_count, 2);
    assert!(honest.closures[1].is_ok(), "{:?}", honest.closures[1]);
    let head = honest.head.as_ref().expect("the walk reaches the head");
    assert_eq!(head.later.window, ANCHOR + 2);
    assert_eq!(
        head.later.id(),
        history.windows[0].next[1].id(),
        "the walk took the proposal the window after does not decide"
    );

    // One verdict at every order of arrival and at every budget at or past the count of the rounds.
    for arrival in ARRIVALS {
        for budget in [count, count + 1, count * 1_000] {
            assert_eq!(
                history.verdict(arrival, budget),
                honest,
                "the verdict moved under the arrival {arrival:?} read with a budget of {budget}"
            );
        }
    }
    // A budget short of the rounds reads part of a window: the walk refuses it or stands at its
    // anchor, and never takes a head off it.
    for arrival in ARRIVALS {
        let short = history.verdict(arrival, count - 1);
        assert!(
            match &short.head {
                Ok(head) => *head == history.anchor,
                Err(_) => true,
            },
            "a walk read short of the rounds took a head: {:?}",
            short.head
        );
    }
}

const X: Name = [0x58; 32];
const Y: Name = [0x59; 32];
const OF_THE_BOOK: u64 = 7;
// How many askings of the slowest clock the four are given to decide: far past the spans of the
// attempts a split of two and two takes, which is what the assertion of a decision measures.
const ASKINGS: u32 = 100_000;

// A machine of the agreement: its part, the record it keeps, its conduct and what it replayed, and
// the pace of its clock against the others'.
struct Counting {
    part: Part,
    record: Record,
    conduct: Conduct,
    replayed: BTreeMap<Name, Replayed>,
    pace: u32,
}

fn pledge_of(part: &Part, attempt: u32, name: Name, since: u32) -> Pledge {
    Pledge {
        window: OF_THE_BOOK,
        attempt,
        name,
        since,
        part_nullifier: *part,
        suite_id: 1,
        answering_key: vec![0xA1; mt_codec::size::SIGNING_PUBLIC_KEY],
        signature: vec![0xF0; mt_codec::size::SIGNATURE],
    }
}

// A pledge of `one` in its current attempt, booked at once in the one book every machine reads: what
// the pulse signs, keeps and publishes, the wire carrying it at once.
fn pledged(
    book: &mut Book,
    one: &mut Counting,
    name: Name,
    since: u32,
    electorate: &agreement::Electorate<'_>,
) {
    let attempt = one.record.attempt;
    let kind = if since == attempt {
        Kind::Closing
    } else {
        Kind::Open
    };
    if one.record.made_in(kind, attempt).is_some() {
        return;
    }
    let pledge = pledge_of(&one.part, attempt, name, since);
    book.pledge(pledge.clone());
    if kind == Kind::Closing {
        one.record.lock = Some((name, attempt));
    }
    one.record.made.push(pledge);
    one.record.valid = book.valid_name(electorate);
}

// What the agreement of one book comes to when the machine at `fast` counts `pace` askings for every
// one the other three count: the decision, every pledge each machine made, and the contradictions the
// book met. Both names are valid to every machine that replays them, as two proposals of one window
// whose rolls replay are.
fn agreed(fast: usize, pace: u32) -> (Option<(Name, u32)>, Vec<Vec<Pledge>>, usize) {
    let votes = BTreeMap::new();
    let electorate = agreement::Electorate {
        count: 4,
        committee: 0,
        votes: &votes,
    };
    let aggregate = [0x33u8; 32];
    let mut book = Book::of_the_window(OF_THE_BOOK);
    let mut machines: Vec<Counting> = (0..4usize)
        .map(|at| {
            let part = [at as u8 + 1; 32];
            let taken = if at < 2 { X } else { Y };
            book.heavy(Place::default(), part, taken);
            let mut conduct = Conduct::default();
            conduct.entering(0);
            Counting {
                part,
                record: Record::opened(OF_THE_BOOK, taken),
                conduct,
                replayed: BTreeMap::new(),
                pace: if at == fast { pace } else { 1 },
            }
        })
        .collect();
    for asking in 0..ASKINGS {
        if book.decided(&electorate).is_some() {
            break;
        }
        for one in &mut machines {
            let now = asking.saturating_mul(one.pace);
            let actions = one.conduct.tick(
                now,
                &Seen {
                    book: &book,
                    electorate: &electorate,
                    record: &one.record,
                    part: &one.part,
                    aggregate: &aggregate,
                    replayed: &one.replayed,
                },
            );
            for action in actions {
                match action {
                    Action::Close(name) => {
                        let attempt = one.record.attempt;
                        pledged(&mut book, one, name, attempt, &electorate);
                    }
                    Action::Open(name, since) => pledged(&mut book, one, name, since, &electorate),
                    Action::Replay(name) => {
                        one.replayed.insert(name, Replayed::Valid);
                    }
                    Action::Enter(attempt) => {
                        if attempt > one.record.attempt {
                            one.record.attempt = attempt;
                            one.record.valid = book.valid_name(&electorate);
                            one.conduct.entering(now);
                        }
                    }
                }
            }
        }
    }
    (
        book.decided(&electorate),
        machines.into_iter().map(|one| one.record.made).collect(),
        book.contradictions.len(),
    )
}

// The clock of one machine moves when the machines pledge and not what the agreement decides: at
// every pace, whichever machine runs it, the same name is decided in the same attempt, no part
// pledges a contradiction, and no machine closes on a name the agreement does not decide. When a
// machine pledges is conduct and does move: with the clock of machine 0 at three times the pace,
// machine 1 opens on the decided name before it closes on it, where at one pace it only closes.
#[test]
fn a_machine_whose_clock_runs_otherwise_reaches_the_same_decision() {
    let (decided, _, contradictions) = agreed(0, 1);
    let (name, _) = decided.expect("four machines decide a split of two and two");
    assert_eq!(contradictions, 0);
    for fast in 0..4 {
        for pace in [1u32, 3, 1_000] {
            let (theirs, their_made, their_contradictions) = agreed(fast, pace);
            assert_eq!(
                theirs, decided,
                "machine {fast} at {pace} times the pace moved the decision"
            );
            assert_eq!(
                their_contradictions, 0,
                "machine {fast} at {pace} times the pace"
            );
            for (at, made) in their_made.iter().enumerate() {
                assert!(
                    made.iter()
                        .filter(|pledge| pledge.is_closing())
                        .all(|pledge| pledge.name == name),
                    "machine {at} closed on another name with machine {fast} at {pace} times the pace"
                );
            }
        }
    }
}

// On one book, the step of the conduct that pledges a decision — the closing pledge on the open quorum
// of its attempt — is taken at the first asking whatever the clock reads, and a decided book asks for
// nothing at any asking.
#[test]
fn the_closing_step_and_a_decided_book_read_no_clock() {
    let votes = BTreeMap::new();
    let electorate = agreement::Electorate {
        count: 4,
        committee: 0,
        votes: &votes,
    };
    let aggregate = [0x33u8; 32];
    let parts: Vec<Part> = (1..=4u8).map(|at| [at; 32]).collect();
    let mut book = Book::of_the_window(OF_THE_BOOK);
    for (at, part) in parts.iter().enumerate() {
        book.heavy(Place::default(), *part, if at < 2 { X } else { Y });
    }
    for part in &parts[..3] {
        book.pledge(pledge_of(part, 1, X, mt_state::STANDS_ON_NONE));
    }
    let mut record = Record::opened(OF_THE_BOOK, Y);
    record.attempt = 1;
    let replayed = BTreeMap::new();
    let tick = |book: &Book, entered: u32, now: u32| {
        let mut conduct = Conduct::default();
        conduct.entering(entered);
        conduct.tick(
            now,
            &Seen {
                book,
                electorate: &electorate,
                record: &record,
                part: &parts[3],
                aggregate: &aggregate,
                replayed: &replayed,
            },
        )
    };
    let instants = [0u32, 1, span_of(1), 4 * span_of(1), 1_000_000];
    for pace in [1u32, 3, 1_000] {
        for at in instants {
            assert_eq!(
                tick(&book, 0, at.saturating_mul(pace)),
                vec![Action::Close(X)],
                "the closing step moved with the clock at {at} times {pace}"
            );
        }
    }
    let mut decided = book;
    for part in &parts[..3] {
        decided.pledge(pledge_of(part, 1, X, 1));
    }
    assert_eq!(decided.decided(&electorate), Some((X, 1)));
    for pace in [1u32, 3, 1_000] {
        for at in instants {
            assert!(tick(&decided, 0, at.saturating_mul(pace)).is_empty());
        }
    }
}

// A round no beacon ever stood at closes nothing: the machine stands one round ahead of the round it
// opens, so its own beacon falls at points it does not hold and silently; its budget of readings runs
// out on the stall `no data` -- the beacon is the data that never came (issue #21) -- and its head,
// its closed window, its kept proposals and its record of the agreement stand as they stood when the
// window opened.
#[test]
fn a_round_no_beacon_stood_at_closes_nothing_and_moves_nothing() {
    let at = Scratch::named("no-beacon");
    let (machine, _) =
        Machine::start(&Configuration::at(&at.0, "127.0.0.1:0")).expect("the machine starts");
    let cohort = Cohort::of(&[machine.naming_half().expect("a half")]).expect("a cohort of itself");
    let genesis = mt_state::tables::genesis_state_hash().expect("the hash of the network");
    let ahead =
        |machine: &Machine, window: u64| machine.enter_round(window, pulse::opening_chain(), 1);
    let errand: pulse::Errand<'_> = &ahead;
    assert_eq!(
        pulse::live_doing(&machine, &cohort, 0, 1, 4, Some(errand)).map(|_| ()),
        Err(NodeError::Stalled {
            on: montana_node::say::Verdict::NoData,
            what: "a round no beacon ever stood at",
        })
    );
    assert_eq!(machine.head().expect("the store answers"), None);
    assert_eq!(machine.closed_window().expect("the store answers"), None);
    assert!(machine.proposal_of(0).expect("the store answers").is_none());
    assert_eq!(
        machine.agreement_of(0).expect("the store answers"),
        Some(Record::opened(0, genesis))
    );
}
