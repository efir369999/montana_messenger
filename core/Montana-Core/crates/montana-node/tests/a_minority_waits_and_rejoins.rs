// A machine parted from the quorum moves nothing while it is parted, and once the parts meet it
// verifies the decisions it missed and is of the chain again. Consensus, "The TimeChain": "A network
// parted therefore does not become two chains: a part holding the quorum share carries the chain
// alone, and a part holding less carries nothing, publishes nothing and waits. When the parts meet,
// the machines that closed nothing verify the decisions they missed and are of the chain again";
// "Presence is witnessed and never self-declared": "The opening cohort and a resuming part of a split
// witness themselves by the same quorum"; "The join", 6: "It then follows the beacons of the open
// window as any machine does"; "The way back": "A loss of quorum halts the chain. Reconnection
// resumes the same open window against the same electorate and the same required share"; Registry,
// CNS-20: "halted partitions and rejoining under the fixed parent quorum".
//
// **The world outside the rules, arranged by this test.** Four machines open a network, a cohort of
// four at a quorum of three, and the transport of the test parts them three to one from the first
// window: the three reach one another, the fourth reaches nobody and nobody reaches it. The three
// live four windows. The fourth stands in the first alone, turning rounds that never close it, until
// the three have closed two windows and moved their head; then its disk fails under it — the directory
// its points are kept in becomes a file — which stops it as a crash does, and it stays down while the
// three close the rest. Then the parts meet: the third of the three lives no further, so that no
// window closes without the fourth, the fourth is started again on its store, the two and the fourth
// reach one another both ways, and the fourth walks from the anchor its operator hands it — the first
// two windows — to the head while the two stand in the window after the last the three closed, and
// lives that window and the next beside the two.
//
// **The test bounds its own waiting, and says what did not happen.** A machine short of the quorum
// waits without end, as it must: "Rounds go on, the cement accumulates and stops short of the share,
// and nothing else happens" (Consensus :72-73), and "Neither elapsed time nor an arbitrarily large
// number of rounds establishes that an absent machine has died" (:1215-1216). So `pulse::live` of a
// machine that cannot close returns never — its patience bounds the waiting at one round, and a
// machine short of the quorum still answers its own beacon and moves to the next. A test that waits on
// one without a bound of its own waits for ever: the first version of this test held the parted
// machine on a scoped thread whose end only the disk failing contrived, and waited for every thread of
// the scope, so a failed assertion inside it, or two machines waiting for a fourth that never came,
// left the test without a verdict (25.10.2026 11:55 UTC: 2695 rounds of the parted machine in window 0
// and no verdict, cut off when the agent running it stopped). Here every machine lives on a thread the
// test does not wait on, answers when it stops, and the test fails at the first machine that stops
// living with an error, and wherever no machine it watches closed a window for `STILL` askings.
//
// **The wrong implementations it refuses**, named before the assertions and once more at each: a
// machine that takes the count it can reach for the electorate — alone, it would cement the quorum of
// one and close the first window on a chain of its own; a minority that moves its head, its closed
// window, a proposal, its census or its window while it cannot reach the quorum; a way back that does
// not verify the decisions missed — the machine started again holding no proposal past the first
// window is refused the window the two stand in, where opening it on the cohort it was handed would
// stand on nothing the network decided; a way back that takes the head on the word of the anchor — an
// anchor a byte of which the test turned walks nowhere and keeps nothing; a walk that refuses the open
// window of a running network rather than stopping before it — there the fourth never comes back while
// the two wait for it; a way back that lives again the window the three closed — there the fourth
// closes it on a beacon of its own carrying a fuller cement, takes a proposal of its own, and pledges
// in the open window a name the two never took and cannot replay, and the agreement of that window
// does not decide (seen on this test, 25.10.2026 10:59 UTC: attempt eight, the two on one name and the
// fourth on another); a way back that keeps the proposals it walked and not the state they carry —
// there the fourth lives the window the two stand in over a plane that credited none of the windows it
// missed, its proposal of that window carries a root of credited rights nobody else recomputes, no
// roll replays to it, and the agreement of the window after parts two to one and never decides (seen
// on this test, 27.10.2026 14:25 UTC: window 5 in its ninth attempt, the two opening on one name and
// the fourth on another, cement 3 of 4); and a rejoined machine whose presence does not count — there
// the two never close a window without it, and the window lived together carries a cement of two.

use montana_node::certificate::Anchor;
use montana_node::pulse::{self, Cohort, Lived};
use montana_node::{Configuration, Machine, NodeError};
use std::collections::BTreeMap;
use std::path::Path;
use std::sync::mpsc::{self, Receiver, RecvTimeoutError, Sender};
use std::sync::Arc;
use std::time::Duration;

mod common;
use common::Scratch;

// The windows the three live while the fourth is parted, and the two windows lived together after.
const PARTED: u64 = 4;
const TOGETHER: u64 = 2;

// The window the three close before the parted machine is stopped: the second, whose close moves
// their head onto the first while the parted machine's stands nowhere.
const BEFORE_THE_STOP: u64 = 1;

// How many askings a machine spends at one round before giving it up: of the operator alone, sized
// for the far side's proofs on a machine of this size and for the spans of the agreement.
const PATIENCE: u32 = 40_000;

// How often the test looks at the machines it waits on, and how many of its looks in a row may pass
// with no window closed at any of them before it stops and fails. Conduct of the test and no number
// of the protocol: the bound of a test that would otherwise wait as long as a minority does. It covers
// the window lived together once the parts meet: the two waited alone into a late attempt of its
// agreement, whose spans double, and the fourth proves its presence and the runner its proposal on a
// loaded host — at 1 800 the bound ran out with all three decided on one name in attempt eight and the
// proposal not yet proven (27.10.2026 17:38 UTC, Lauterbourg-3). A split is no such wait: two names
// are held for ever and the attempts go on, so it fails at this bound all the same.
const ASKING: Duration = Duration::from_secs(1);
const STILL: u32 = 3_600;

const NO_PROPOSAL_TWO_BEFORE: &str =
    "a window past the first two of a network standing on no proposal two before";
const NOT_DECIDED: &str = "a certificate whose agreement does not decide the proposal it finalizes";

fn id_of(held: &mt_state::layout::Proposal) -> [u8; 32] {
    held.id().expect("an identifier")
}

fn kept(machine: &Machine, window: u64) -> Option<[u8; 32]> {
    machine
        .proposal_of(window)
        .expect("the store answers")
        .map(|held| id_of(&held))
}

// What a machine living on a thread of its own answers when it stops: which machine, and what it
// lived.
type Answer = (usize, Result<Vec<Lived>, NodeError>);

// What the machines that answered lived, by machine.
type Lives = BTreeMap<usize, Vec<Lived>>;

// A machine living `windows` windows from `from` on a thread the test does not wait on, answering
// when it stops. A test that fails while the machine still turns rounds is not held by it.
fn living(
    machine: &Arc<Machine>,
    halves: &[[u8; 32]],
    from: u64,
    windows: u64,
    at: usize,
    answers: &Sender<Answer>,
) {
    let machine = Arc::clone(machine);
    let halves = halves.to_vec();
    let answers = answers.clone();
    std::thread::spawn(move || {
        let lived = Cohort::of(&halves)
            .and_then(|cohort| pulse::live(&machine, &cohort, from, windows, PATIENCE));
        let _ = answers.send((at, lived));
    });
}

// A machine answering the door for as many links as the test dials into it, on a thread the test
// joins once every link it dials stands.
fn answering(machine: &Arc<Machine>, links: usize) -> std::thread::JoinHandle<()> {
    let machine = Arc::clone(machine);
    std::thread::spawn(move || {
        for _ in 0..links {
            machine.answer_one().expect("a link is answered");
        }
    })
}

// Where the machines watched stand: the last window each closed and the window and round it is in.
type Standing = Vec<(usize, Option<u64>, Option<(u64, u32)>)>;

fn standing(watched: &[(usize, &Machine)]) -> Standing {
    watched
        .iter()
        .map(|(at, one)| {
            (
                *at,
                one.closed_window().expect("the store answers"),
                one.round_of_the_machine()
                    .map(|(window, _, round)| (window, round)),
            )
        })
        .collect()
}

// The test's wait on one stretch of the machines' lives: until `done` holds, taking every answer as
// it comes. It fails at the first machine that stops living with an error, and where no machine
// watched closed a window for `STILL` askings in a row, naming what it waited for and where every
// machine stood.
fn awaiting(
    what: &str,
    watched: &[(usize, &Machine)],
    answers: &Receiver<Answer>,
    lived: &mut Lives,
    done: &dyn Fn(&Lives) -> bool,
) {
    let closed = || -> Vec<Option<u64>> {
        watched
            .iter()
            .map(|(_, one)| one.closed_window().expect("the store answers"))
            .collect()
    };
    let mut last = closed();
    let mut still = 0;
    while !done(lived) {
        match answers.recv_timeout(ASKING) {
            Ok((at, Ok(windows))) => {
                lived.insert(at, windows);
            }
            Ok((at, Err(why))) => panic!(
                "{what}: machine {at} stopped living: {why:?}; closed and standing: {:?}",
                standing(watched)
            ),
            Err(RecvTimeoutError::Timeout) => {}
            Err(RecvTimeoutError::Disconnected) => {
                panic!("{what}: no machine is left to answer")
            }
        }
        let now = closed();
        if now == last {
            still += 1;
        } else {
            last = now;
            still = 0;
        }
        assert!(
            still < STILL,
            "{what}: no machine closed a window in {STILL} askings; closed and standing: {:?}",
            standing(watched)
        );
    }
}

// A disk failing under a machine, which stops it as a crash does: the directory its points are kept
// in becomes a file, so the next cell it keeps fails. And the disk mended.
fn fail_the_disk(at: &Path) {
    std::fs::rename(at.join("points"), at.join("points-aside")).expect("the directory is taken");
    std::fs::write(at.join("points"), b"").expect("a file in its place");
}

fn mend_the_disk(at: &Path) {
    std::fs::remove_file(at.join("points")).expect("the file goes");
    std::fs::rename(at.join("points-aside"), at.join("points")).expect("the directory is put back");
}

#[test]
fn a_machine_parted_from_the_quorum_moves_nothing_and_rejoins_by_verifying() {
    let at: Vec<Scratch> = ["minority-a", "minority-b", "minority-c", "minority-d"]
        .into_iter()
        .map(Scratch::named)
        .collect();
    let mut machines: Vec<Arc<Machine>> = at
        .iter()
        .map(|one| {
            Arc::new(
                Machine::start(&Configuration::at(&one.0, "127.0.0.1:0"))
                    .expect("a machine starts")
                    .0,
            )
        })
        .collect();
    let halves: Vec<[u8; 32]> = machines
        .iter()
        .map(|one| one.naming_half().expect("a half"))
        .collect();
    let cohort = Cohort::of(&halves).expect("four machines stand in the tree");
    let lines: Vec<String> = machines
        .iter()
        .map(|one| one.acquaintance().expect("a line"))
        .collect();
    let parted = machines.pop().expect("the fourth");
    let (answers, answered) = mpsc::channel::<Answer>();

    // The partition: the three reach one another, and the fourth nobody.
    let doors: Vec<_> = machines
        .iter()
        .map(|machine| answering(machine, 2))
        .collect();
    for (from, machine) in machines.iter().enumerate() {
        for (to, line) in lines[..3].iter().enumerate() {
            if from != to {
                machine
                    .reach_and_hold(line)
                    .expect("the acquaintance answers");
            }
        }
    }
    for door in doors {
        door.join().expect("the thread stands");
    }
    for (index, machine) in machines.iter().enumerate() {
        living(machine, &halves, 0, PARTED, index, &answers);
    }
    let alone = {
        let parted = Arc::clone(&parted);
        let halves = halves.clone();
        std::thread::spawn(move || {
            Cohort::of(&halves).and_then(|cohort| pulse::live(&parted, &cohort, 0, 1, PATIENCE))
        })
    };
    let three: Vec<(usize, &Machine)> = machines
        .iter()
        .enumerate()
        .map(|(index, one)| (index, one.as_ref()))
        .collect();
    let mut lived = Lives::new();
    awaiting(
        "the three close their second window while the fourth stands alone",
        &three,
        &answered,
        &mut lived,
        &|_| {
            three.iter().all(|(_, one)| {
                one.closed_window()
                    .expect("the store answers")
                    .is_some_and(|closed| closed >= BEFORE_THE_STOP)
            })
        },
    );

    // The parted machine stops: its disk fails, where it has not stopped already.
    let failed = !alone.is_finished();
    if failed {
        fail_the_disk(&at[3].0);
    }
    let mut still = 0;
    while !alone.is_finished() {
        still += 1;
        assert!(
            still < STILL,
            "the parted machine went on living on a failed disk: {:?}",
            parted.round_of_the_machine()
        );
        std::thread::sleep(ASKING);
    }
    // A minority that closes its window alone, by taking the count it reaches for the electorate.
    assert!(
        alone.join().expect("the thread stands").is_err(),
        "the parted machine lived its window"
    );
    if failed {
        mend_the_disk(&at[3].0);
    }

    // **The part holding less carries nothing**, while the three moved their head. The stretch was
    // real: a minority standing beside a network that moved nothing proves nothing.
    for (_, one) in &three {
        assert!(
            one.head().expect("the store answers").is_some(),
            "the three moved no head while the fourth stood alone"
        );
    }
    // A minority that moves its head onto a proposal of its own.
    assert_eq!(parted.head().expect("the store answers"), None);
    // A minority that closes a window short of the quorum.
    assert_eq!(parted.closed_window().expect("the store answers"), None);
    // A minority that keeps a proposal, the beginning of a chain of its own.
    for window in 0..PARTED {
        assert_eq!(
            kept(&parted, window),
            None,
            "the parted machine kept a proposal of window {window}"
        );
    }
    // A minority that books its part in a census, a vote it would carry into a later window.
    assert!(parted.lived_census().expect("the store answers").is_empty());
    // A minority that leaves the window it cannot close for the next one.
    assert!(parted
        .round_of_the_machine()
        .is_some_and(|(window, _, _)| window == 0));
    drop(parted);

    // The three live on to the end of their windows without the fourth.
    awaiting(
        "the three close their windows without the fourth",
        &three,
        &answered,
        &mut lived,
        &|lived| lived.len() == 3,
    );
    for (index, one) in &lived {
        // A network that counts a machine it cannot reach, or a machine short of the windows asked.
        assert_eq!(one.len(), PARTED as usize, "machine {index}");
        for window in one {
            assert_eq!(
                window.living, 3,
                "machine {index}, window {}",
                window.window
            );
        }
    }
    for (_, one) in &three {
        assert_eq!(one.head().expect("the store answers"), Some(PARTED - 2));
    }

    // The parts meet. The third of the three lives no further, so no window closes without the
    // fourth; the fourth is started again and reaches the first two, and they reach it.
    let (back, born) = Machine::start(&Configuration::at(&at[3].0, "127.0.0.1:0"))
        .expect("the parted machine starts again");
    assert!(!born, "a restart drew a second secret");
    let back = Arc::new(back);
    let line = back.acquaintance().expect("a line");
    let doors: Vec<_> = machines[..2]
        .iter()
        .map(|machine| answering(machine, 1))
        .chain([answering(&back, 2)])
        .collect();
    for (index, machine) in machines[..2].iter().enumerate() {
        back.reach_and_hold(&lines[index])
            .expect("the acquaintance answers");
        machine
            .reach_and_hold(&line)
            .expect("the parted machine answers");
    }
    for door in doors {
        door.join().expect("the thread stands");
    }

    // The two live on, waiting for the fourth, and stand in the window after the last the three
    // closed, short of the quorum.
    for (index, machine) in machines[..2].iter().enumerate() {
        living(machine, &halves, PARTED, TOGETHER, index, &answers);
    }
    let together: Vec<(usize, &Machine)> = vec![
        (0, machines[0].as_ref()),
        (1, machines[1].as_ref()),
        (3, back.as_ref()),
    ];
    let mut lived = Lives::new();
    awaiting(
        "the two enter the window after the last the three closed",
        &together[..2],
        &answered,
        &mut lived,
        &|_| {
            machines[..2].iter().all(|one| {
                one.round_of_the_machine()
                    .is_some_and(|(window, _, _)| window == PARTED)
            })
        },
    );

    // Refused: the window the two stand in, opened by the fourth on what it holds — nothing past the
    // first window — and the cohort its operator handed it. A way back that does not verify the
    // decisions missed would open it there, standing on nothing the network decided.
    assert_eq!(
        pulse::live(&back, &cohort, PARTED, TOGETHER, PATIENCE).map(|_| ()),
        Err(NodeError::Refused {
            what: NO_PROPOSAL_TWO_BEFORE
        })
    );
    assert!(back
        .agreement_of(PARTED)
        .expect("the store answers")
        .is_none());

    // The anchor its operator hands it: the proposals of the first two windows.
    let anchor = Anchor {
        earlier: machines[0]
            .proposal_of(0)
            .expect("the store answers")
            .expect("the first proposal"),
        later: machines[0]
            .proposal_of(1)
            .expect("the store answers")
            .expect("the second proposal"),
    };

    // Refused: the anchor with one byte of its later proposal turned by the test. The certificate of
    // the window after it decides the network's proposal and not the turned one; a way back taking
    // the head on the word of the anchor would walk from it all the same. Nothing is kept.
    let mut turned = anchor.clone();
    turned.later.note_root[0] ^= 1;
    assert_eq!(
        pulse::join(&back, &turned, PATIENCE).map(|_| ()),
        Err(NodeError::Refused { what: NOT_DECIDED })
    );
    assert_eq!(back.head().expect("the store answers"), None);
    assert_eq!(back.closed_window().expect("the store answers"), None);

    // The walk: from the anchor to the head the three made final, verifying every certificate since.
    let head = pulse::join(&back, &anchor, PATIENCE).expect("the walk reaches the head");
    // A walk that stops at its anchor, or one refused by the open window of the two.
    assert_eq!(head.later.window, PARTED - 2);
    assert_eq!(
        Some(id_of(&head.later)),
        kept(&machines[0], PARTED - 2),
        "the walk reached another head than the network's"
    );
    assert_eq!(back.head().expect("the store answers"), Some(PARTED - 2));
    // A way back that leaves the window the three closed open to be lived again: the walk keeps the
    // proposal the three closed it on, awaiting its certificate, and that window stands closed.
    assert_eq!(
        back.closed_window().expect("the store answers"),
        Some(PARTED - 1)
    );
    assert_eq!(
        kept(&back, PARTED - 1),
        kept(&machines[0], PARTED - 1),
        "the walk kept another proposal of the window the three closed last"
    );
    let from = back
        .closed_window()
        .expect("the store answers")
        .expect("the walk closed what it verified")
        + 1;
    assert_eq!(from, PARTED);
    // A way back that keeps the proposals it walked and not the state they carry: the fourth would
    // live the window the two stand in over a plane that credited none of the windows it missed, and
    // close it on roots nobody else recomputes.
    let last_closed = machines[0]
        .proposal_of(PARTED - 1)
        .expect("the store answers")
        .expect("the window the three closed last");
    assert_eq!(
        back.value()
            .expect("the plane")
            .tables_of(PARTED - 1)
            .expect("the tables"),
        [
            last_closed.note_root,
            last_closed.nullifier_root,
            last_closed.record_root,
            last_closed.machine_root,
            last_closed.admitted_root,
            last_closed.credited_root,
            last_closed.operations_root,
        ],
        "the walk left the fourth on a plane that is not the decided state of the window it closed"
    );

    // The fourth lives from the window the two stand in, beside them.
    living(&back, &halves, from, TOGETHER, 3, &answers);
    awaiting(
        "the fourth and the two live their windows together",
        &together,
        &answered,
        &mut lived,
        &|lived| lived.len() == 3,
    );
    let mine = &lived[&3];

    // **One chain, and the fourth of it.** Every window from the second to the first lived together
    // stands under one proposal at every machine that holds it — the last the three closed under the
    // proposal they closed it on — and the first window lived together carries a cement of three, the
    // two and the fourth, and the right of it is the fourth's as it is theirs.
    assert_eq!(
        mine.iter().map(|one| one.window).collect::<Vec<_>>(),
        (PARTED..PARTED + TOGETHER).collect::<Vec<_>>()
    );
    for window in 1..PARTED + TOGETHER - 1 {
        // The third of the three holds the windows it lived and none after.
        let mut holders: Vec<&Machine> = machines.iter().map(|one| one.as_ref()).collect();
        if window >= PARTED {
            holders.pop();
        }
        holders.push(back.as_ref());
        let ids: Vec<Option<[u8; 32]>> = holders.iter().map(|one| kept(one, window)).collect();
        // A way back that leaves the fourth on a chain of its own: two names for one window.
        assert!(
            ids.iter().all(|id| id.is_some() && *id == ids[0]),
            "window {window} stands under more than one name: {ids:x?}"
        );
    }
    let first_together = machines[0]
        .proposal_of(PARTED)
        .expect("the store answers")
        .expect("the first window lived together");
    // A rejoined machine whose presence does not count.
    assert_eq!(
        first_together.cement_count, 3,
        "the window lived together does not carry the fourth"
    );
    // A rejoined machine the decided roll of the window it lived does not name.
    assert!(
        mine[0].right.is_some(),
        "the fourth took no share of the window it lived beside the two"
    );
    for index in [0, 1] {
        let theirs = &lived[&index];
        assert_eq!(theirs.len(), TOGETHER as usize);
        // An agreement on the window lived together that decides two names.
        assert_eq!(theirs[0].proposal, mine[0].proposal);
        assert!(theirs[0].right.is_some());
    }
    // A head of the fourth standing elsewhere than the network's.
    for (_, one) in &together {
        assert_eq!(
            one.head().expect("the store answers"),
            Some(PARTED + TOGETHER - 2)
        );
    }
}
