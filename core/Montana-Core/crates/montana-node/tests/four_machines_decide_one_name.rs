// The acceptance of the agreement on what a window decided (AGREEMENT.md, section 6): four machines
// at a quorum of three, under a held part, a late frame and a partition that heals, decide one name
// for every window they close, and the roots they stand on are canonical.
//
// **The world outside the rules, arranged by this test.** Two halves of a cohort of four stand
// partitioned while the first window opens: the first half carries a frame published at the points
// of round zero, the second half never sees it before it leaves that round — the late frame, which
// parts the note roots and so the names of the window. The partition heals once every machine of
// the two halves has left round zero, so the heavy attestations cross and the cement reaches the
// quorum on both sides, each side under its own name. The fourth machine's part is held: it enters
// the window once the other three have left it — an event the test waits on, not a timer — so its
// heavy attestation is in no final beacon the others reconciled, and its own close carries a cement nobody else's beacon carried — the case of
// a machine holding more cement than the beacon at the quorum, which AGREEMENT.md names.
//
// **What is measured.** That the agreement of the window after decides one name of the split window
// — open pledges at the lowest place followed, closing pledges at the quorum — and that every
// machine whose name was not decided replays the decided roll and stands on the decided proposal:
// the proposal every machine keeps of each decided window has one identifier, the head of every
// machine stands on the newest decided window, and the right of a window is issued from its decided
// roll to the parts it names and to no other.
//
// **The wrong implementation it refuses**, named before the assertions: the pulse of f7f6eb5, which
// runs the agreement as far as attempt zero and refuses a heavy attestation naming another proposal
// than the one its machine took — on it the window after the split never reaches a cement of three
// at any machine, and every machine exhausts its waiting budget without a verified answer.

use montana_node::pulse::{self, Cohort};
use montana_node::{Configuration, Machine};
use montana_wallet::{Note, Wallet};
use std::time::Duration;

mod common;
use common::{of, payee_of, Scratch};

const FROM: u64 = 4_000;
const WINDOWS: u64 = 3;
const CHAIN: u8 = 0;
const PAID: u128 = 250_000_000;

// How many askings a machine spends at one round before giving it up: of the operator alone, sized
// for the far side's proofs on a machine of this size and for the spans of the agreement.
const PATIENCE: u32 = 24_000;

// A machine that answers the door for as many links as the test dials into it.
fn answering(machine: &Machine, links: usize) {
    for _ in 0..links {
        machine.answer_one().expect("a link is answered");
    }
}

fn id_of(held: &mt_state::layout::Proposal) -> [u8; 32] {
    held.id().expect("an identifier")
}

#[test]
fn four_machines_decide_one_name_under_a_held_part_a_late_frame_and_a_healed_partition() {
    let at: Vec<Scratch> = ["four-a", "four-b", "four-c", "four-d"]
        .into_iter()
        .map(Scratch::named)
        .collect();
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
    let cohort = Cohort::of(&halves).expect("four machines stand in the tree");
    assert_eq!(cohort.count(), 4);
    let lines: Vec<String> = machines
        .iter()
        .map(|one| one.acquaintance().expect("a line"))
        .collect();

    // The notes a payer holds stand in the tree of every machine alike, so a frame spending them
    // verifies on every plane; the payer's wallet holds them too.
    let ledger_at = Scratch::named("four-ledger");
    let wallet = Wallet::open(&ledger_at.0).expect("a wallet opens");
    let (of_payer, payer_key) = payee_of(0xA1);
    let (of_payee, _) = payee_of(0xB2);
    let inputs = mt_genesis::scalar("spend_inputs").expect("the Decree names it");
    let count = mt_genesis::scalar("spends_per_frame").expect("the Decree names it");
    for position in 0..inputs * count {
        let note = Note::of(
            1_000_000_000,
            of_payer.note_pk,
            payer_key,
            of(0xC3, position as u8),
            position,
        )
        .expect("a note of the family");
        for machine in &machines {
            machine
                .value()
                .expect("the machine holds its state")
                .witness(&note.commitment)
                .expect("the tree takes it");
        }
        wallet.enter(note).expect("the ledger takes it");
    }
    // The frame, built once against the roots every plane holds as the first window opens: the
    // tree of notes as seeded, and the tree of admitted machines of the cohort.
    let frame = {
        let plane = machines[0].value().expect("the plane");
        let paths: Vec<_> = (0..inputs * count)
            .map(|position| plane.path_of(position).unwrap_or_default())
            .collect();
        wallet
            .pay(
                &of_payee,
                PAID,
                FROM,
                &of(0xD4, 0),
                &of_payer,
                &paths,
                &plane.notes_root(),
                &cohort.root(),
            )
            .expect("the payment is built")
            .frame
    };

    let stands_the_frame =
        |machine: &Machine, window: u64| -> Result<(), montana_node::NodeError> {
            machine.stand_the_frame(&frame, window, CHAIN, 0)
        };
    let errand: &(dyn Fn(&Machine, u64) -> Result<(), montana_node::NodeError> + Sync) =
        &stands_the_frame;

    // The partition: the first half reaches itself, the second half reaches itself, and nothing
    // crosses. Each machine answers the door for the three links the test dials into it in all.
    std::thread::scope(|scope| {
        for machine in &machines {
            scope.spawn(move || answering(machine, 3));
        }
        let reach = |from: usize, to: usize| {
            machines[from]
                .reach_and_hold(&lines[to])
                .expect("the acquaintance answers");
        };
        reach(0, 1);
        reach(1, 0);
        reach(2, 3);
        reach(3, 2);

        // The first half stands the late frame at the points of round zero of the first window,
        // before it attests anything of it; the second half never holds it before it leaves that
        // round, and applies it in no window of its own.
        let living: Vec<_> = (0..3)
            .map(|index| {
                let machine = &machines[index];
                let cohort = Cohort::of(&halves).expect("the same cohort");
                scope.spawn(move || {
                    let errand: Option<pulse::Errand<'_>> =
                        if index < 2 { Some(errand) } else { None };
                    pulse::live_doing(machine, &cohort, FROM, WINDOWS, PATIENCE, errand)
                })
            })
            .collect();

        // The partition heals once every machine of the two halves left round zero: the halves
        // reach each other both ways, and from here every machine reaches every other.
        loop {
            let past_round_zero = machines[..3].iter().all(|one| {
                one.round_of_the_machine()
                    .is_some_and(|(window, _, round)| window > FROM || round > 0)
            });
            if past_round_zero {
                break;
            }
            std::thread::sleep(Duration::from_millis(100));
        }
        for (from, to) in [
            (0, 2),
            (0, 3),
            (1, 2),
            (1, 3),
            (2, 0),
            (2, 1),
            (3, 0),
            (3, 1),
        ] {
            reach(from, to);
        }

        // The held part: the fourth machine enters the first window only once the other three have
        // left it — an event, not a timer — so its heavy attestation of that window reaches them
        // after their final beacons and no decided cement of the window names it.
        loop {
            let left_the_first = machines[..3].iter().all(|one| {
                one.round_of_the_machine()
                    .is_some_and(|(window, _, _)| window > FROM)
            });
            if left_the_first {
                break;
            }
            std::thread::sleep(Duration::from_millis(100));
        }
        let fourth = {
            let machine = &machines[3];
            let cohort = Cohort::of(&halves).expect("the same cohort");
            scope.spawn(move || pulse::live(machine, &cohort, FROM, WINDOWS, PATIENCE))
        };

        let mut lived: Vec<Vec<pulse::Lived>> = living
            .into_iter()
            .map(|one| {
                one.join()
                    .expect("the thread stands")
                    .expect("a machine lives it")
            })
            .collect();
        lived.push(
            fourth
                .join()
                .expect("the thread stands")
                .expect("the held machine lives it"),
        );

        // Every machine lived every window.
        for one in &lived {
            assert_eq!(one.len(), WINDOWS as usize);
            for (at, window) in one.iter().enumerate() {
                assert_eq!(window.window, FROM + at as u64);
            }
        }
        // **One name per decided window**, at every machine: the first two windows are decided, by
        // the agreements of the second and the third, and every machine keeps the decided proposal
        // of each under one identifier — the one it reports as final — whichever name it took.
        for at in 0..(WINDOWS - 1) {
            let window = FROM + at;
            let kept: Vec<[u8; 32]> = machines
                .iter()
                .map(|one| {
                    id_of(
                        &one.proposal_of(window)
                            .expect("the store answers")
                            .expect("a proposal kept for every window lived"),
                    )
                })
                .collect();
            assert!(
                kept.iter().all(|id| *id == kept[0]),
                "window {window} stands under more than one name across the machines: {kept:x?}"
            );
            for one in &lived {
                assert_eq!(
                    one[at as usize].proposal, kept[0],
                    "a machine reports window {window} final under another name than it keeps"
                );
            }
        }
        // The split was real: the names the first three took of the first window differ between
        // the halves, since one half applied the late frame and the other did not, and the held
        // machine took a name of its own cement.
        for one in &machines {
            assert_eq!(
                one.head().expect("the store answers"),
                Some(FROM + WINDOWS - 2),
                "the head stands elsewhere than on the newest decided window"
            );
        }
        // **The right of a window is issued from its decided roll**: one equal share to every part
        // the decided proposal's cement names, none to a machine whose part it does not name, and
        // the shares with the remainder are the mint of the window exactly.
        for at in 0..(WINDOWS - 1) {
            let window = FROM + at;
            let decided = machines[0]
                .proposal_of(window)
                .expect("the store answers")
                .expect("the decided proposal");
            let mint = montana_node::attest::mint_of(window).expect("the Decree names it");
            let rights: Vec<&montana_node::attest::Right> = lived
                .iter()
                .filter_map(|one| one[at as usize].right.as_ref())
                .collect();
            assert_eq!(
                rights.len() as u64,
                decided.cement_count,
                "window {window} minted to another count of machines than its decided cement names"
            );
            for right in &rights {
                assert_eq!(right.share, mint / decided.cement_count);
                assert_eq!(right.carried_forward, mint % decided.cement_count);
            }
            let mut nullifiers: Vec<[u8; 32]> = rights.iter().map(|r| r.nullifier).collect();
            nullifiers.sort_unstable();
            nullifiers.dedup();
            assert_eq!(
                nullifiers.len(),
                rights.len(),
                "two machines took one right"
            );
        }
        // The last window awaits the decision of a window nobody lived: no right stands for it.
        for one in &lived {
            assert!(one[(WINDOWS - 1) as usize].right.is_none());
        }
        // The held part took no share of the first window: it entered the window once the others had
        // left it, so its heavy attestation reached them after their final beacons and no decided
        // cement of that window names it.
        assert!(
            lived[3][0].right.is_none(),
            "the held part took a share of a window whose decided cement cannot name it"
        );
    });
}
