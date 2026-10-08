// Three machines of one cohort, and the quorum that asks for all of them. The Decree names
// sixty-seven hundredths rather than two thirds, so a cement of two against three does not close a
// window: every machine must hold every attestation before any window closes.
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

const WINDOW: u64 = 2_000;
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
                    pulse::live(one, &cohort, WINDOW, 1, PATIENCE).expect("a machine lives it")
                })
            })
            .collect();
        held.into_iter()
            .map(|one| one.join().expect("the thread stands"))
            .collect()
    });

    let mint = montana_node::attest::mint_of(WINDOW).expect("the Decree names the schedule");
    for one in &lived {
        assert_eq!(one.len(), 1);
        assert_eq!(one[0].window, WINDOW);
        assert_eq!(
            one[0].living, 3,
            "a cement of fewer than three closed a window the quorum asks three for"
        );
        assert_eq!(one[0].right.share, mint / 3);
    }
    // Three machines, three rights, three nullifiers.
    let mut nullifiers: Vec<[u8; 32]> = lived.iter().map(|one| one[0].right.nullifier).collect();
    nullifiers.sort_unstable();
    nullifiers.dedup();
    assert_eq!(nullifiers.len(), 3, "two machines took one right");
}
