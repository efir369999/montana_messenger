// Three machines of one cohort, and the quorum that asks for all of them. The Decree names
// sixty-seven hundredths rather than two thirds, so a cement of two against three does not close a
// window: every machine must hold every attestation before any window closes.
//
// **Two windows, because a right is issued when a window is final.** The proposal of a window is
// decided by the agreement of the window after it, and the right to its coin is issued from the
// decided roll and from no count (Consensus, "The right to a window's coin"; the item 2 of
// Protocol-13): so the first window's right stands once the second window closed, and the second
// window's right stands at no close this test lives. The wrong implementation refused: one minting
// a right at a machine's own close, before the name of the window was decided.
//
// **The links are one per pair and no more.** The first machine reaches the second and the third,
// and the third reaches the second; nothing else is dialled. A link a machine opened is its way of
// asking and a link it answered is its way of being asked, so what each machine holds comes either
// of what it pulled or of what whoever dialled it wrote into it — and the three converge without a
// full mesh of dialling.

use montana_node::pulse::{self, Cohort};
use montana_node::{Configuration, Machine};

mod common;
use common::Scratch;

// The window the network opens at: zero, the one window the Genesis State Hash stands under
// (Consensus, "Invariants of the TimeChain").
const WINDOW: u64 = 0;
const PATIENCE: u32 = 40_000;

#[test]
fn three_machines_close_a_window_and_each_takes_one_share() {
    let at = [
        Scratch::named("three-one"),
        Scratch::named("three-two"),
        Scratch::named("three-three"),
    ];
    let machines: Vec<Machine> = at
        .iter()
        .map(|one| {
            Machine::start(&Configuration::at(&one.0, "127.0.0.1:0"))
                .expect("a machine starts")
                .0
        })
        .collect();
    let halves: Vec<[u8; 32]> = machines
        .iter()
        .map(|one| one.naming_half().expect("a half"))
        .collect();
    let cohort = Cohort::of(&halves).expect("three machines stand in the tree");
    assert_eq!(cohort.count(), 3);

    // One link per pair: the first reaches the second and the third, the third reaches the second.
    let lines: Vec<String> = machines
        .iter()
        .map(|one| one.acquaintance().expect("a line"))
        .collect();
    std::thread::scope(|scope| {
        let second = &machines[1];
        let third = &machines[2];
        let waiting = scope.spawn(move || {
            second.answer_one().expect("the second answers the first");
            second.answer_one().expect("the second answers the third");
        });
        let also = scope.spawn(move || {
            third.answer_one().expect("the third answers the first");
        });
        machines[0]
            .reach_and_hold(&lines[1])
            .expect("the second answers");
        machines[0]
            .reach_and_hold(&lines[2])
            .expect("the third answers");
        machines[2]
            .reach_and_hold(&lines[1])
            .expect("the second answers");
        waiting.join().expect("the thread stands");
        also.join().expect("the thread stands");
    });

    // And all three live the window.
    let lived: Vec<Vec<pulse::Lived>> = std::thread::scope(|scope| {
        let held: Vec<_> = machines
            .iter()
            .map(|one| {
                let cohort = Cohort::of(&halves).expect("the same cohort");
                scope.spawn(move || {
                    pulse::live(one, &cohort, WINDOW, 2, PATIENCE).expect("a machine lives it")
                })
            })
            .collect();
        held.into_iter()
            .map(|one| one.join().expect("the thread stands"))
            .collect()
    });

    for one in &lived {
        assert_eq!(one.len(), 2);
        assert_eq!(one[0].window, WINDOW);
        assert_eq!(one[1].window, WINDOW + 1);
        for window in one {
            assert_eq!(
                window.living, 3,
                "a cement of fewer than three closed a window the quorum asks three for"
            );
        }
        // The first window is final, decided by the second: its right is issued from the decided
        // roll, which names all three parts, and it is the window's credit whatever the count of the three.
        // The second awaits the decision of a window nobody lived, and credits nothing yet.
        assert_eq!(
            one[0]
                .right
                .as_ref()
                .expect("the first window is final and its roll names every part")
                .worth,
            montana_node::attest::window_credit().expect("the Decree names it")
        );
        assert!(
            one[1].right.is_none(),
            "a right was issued before the window's name was decided"
        );
    }
    // One decision, one name: every machine closed each window under the identifier of one
    // proposal, whichever runner's bytes it took, and the first window is final under it.
    for at in 0..2 {
        assert!(
            lived
                .iter()
                .all(|one| one[at].proposal == lived[0][at].proposal),
            "three machines closing one window on one beacon took more than one proposal"
        );
    }
    for one in &machines {
        assert_eq!(
            one.head().expect("the store answers"),
            Some(WINDOW),
            "the head stands elsewhere than on the one final window"
        );
    }
    // Three machines, three rights, three nullifiers.
    let mut nullifiers: Vec<[u8; 32]> = lived
        .iter()
        .filter_map(|one| one[0].right.as_ref().map(|right| right.nullifier))
        .collect();
    nullifiers.sort_unstable();
    nullifiers.dedup();
    assert_eq!(nullifiers.len(), 3, "two machines took one right");
}
