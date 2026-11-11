// A machine that was away walks back to the head from its own anchor and lives on from there.
// Consensus, "The join": "A device that lived the network holds its own anchor — the last two
// proposals it verified — and needs nobody's"; "a device away for `k` windows catches up in `k`
// windows of that duty. Machines retain the attestations of a window for `retained_windows` windows
// after it closes; a device away longer than that finds no certificate to walk and takes a fresh
// anchor from its operator, which is a change of trust and not a verification, and the set says so".
// Consensus, "The TimeChain": "When the parts meet, the machines that closed nothing verify the
// decisions they missed and are of the chain again".
//
// **The world outside the rules, arranged by this test.** One machine and a cohort of itself lives the
// first three windows of a network, and what its disk holds then is kept aside twice: that is the disk
// of a machine away from that moment on. The machine lives two windows more and stops living, and
// answers its door from then on: it is the network that went on. The machine on the disk kept aside
// is started — the machine come back, under the secret it always had — reaches the network, and is
// asked to live the window the network stands at. The second copy of the disk comes back once the
// network has let the windows it missed go, which is what the end of the retention does to them: the
// points of the first window it missed, and of every window before it, are gone from every holder.
//
// **The wrong implementations it refuses**, named before the assertions: a machine that opens the
// window it is told on what it holds — there it opens the network's window on proposals two windows
// old, and the pulse of this tree before the walk back refused it outright, a machine away being one
// that never comes back; a way back that takes the head on the word of whoever answered — there an
// anchor one byte of which turned on its disk walks to the head as well; a way back that leaves the
// machine the window the network already closed to live again, rather than the window the network
// stands at — there it is answered the window after the head and stands on nothing the network
// pledged in the open window; a walk that, finding no
// certificate of the windows missed, leaves the machine standing at its anchor as though it were the
// head — there the machine away longer than the retention is told nothing and lives a window on
// proposals the network left behind; and a join that answers a device holding a handed anchor nothing
// stands after with its anchor, rather than saying no certificate stands.

use montana_node::certificate::Anchor;
use montana_node::pulse::{self, Cohort};
use montana_node::{Configuration, Machine, NodeError};
use std::path::Path;

mod common;
use common::Scratch;

// The windows lived before the disk is kept aside, and those the network lives after it.
const BEFORE: u64 = 3;
const AWAY: u64 = 2;

// How many askings a machine spends at one round before giving it up: of the operator alone, sized
// for the proofs of a machine of this size.
const PATIENCE: u32 = 40_000;

const NO_CERTIFICATE: &str = "no certificate to walk; a fresh anchor is a change of trust";

fn refused(what: &'static str) -> NodeError {
    NodeError::Refused { what }
}

fn id_of(held: &mt_state::layout::Proposal) -> [u8; 32] {
    held.id().expect("an identifier")
}

// A directory copied whole, files and directories, as a disk is copied.
fn copied(from: &Path, to: &Path) {
    std::fs::create_dir_all(to).expect("a directory to copy into");
    for entry in std::fs::read_dir(from).expect("a directory to copy") {
        let entry = entry.expect("an entry");
        let at = to.join(entry.file_name());
        if entry.file_type().expect("a type").is_dir() {
            copied(&entry.path(), &at);
        } else {
            std::fs::copy(entry.path(), &at).expect("a file copied");
        }
    }
}

// The machine `near` reaching `far`, which answers the one link.
fn reached(near: &Machine, far: Machine) -> Machine {
    let line = far.acquaintance().expect("an acquaintance is written");
    let answering = std::thread::spawn(move || {
        far.answer_one().expect("a link is answered");
        far
    });
    near.reach_and_hold(&line).expect("the far side answers");
    answering.join().expect("the thread stands")
}

#[test]
fn a_machine_away_walks_back_from_its_own_anchor_and_lives_on() {
    let at = Scratch::named("away-network");
    let aside = Scratch::named("away-disk");
    let aside_again = Scratch::named("away-disk-again");
    let device_at = Scratch::named("away-device");
    let (network, _) =
        Machine::start(&Configuration::at(&at.0, "127.0.0.1:0")).expect("the machine starts");
    let cohort = Cohort::of(&[network.naming_half().expect("a half")]).expect("a cohort of itself");
    pulse::live(&network, &cohort, 0, BEFORE, PATIENCE).expect("the first windows");
    copied(&at.0, &aside.0.join("disk"));
    copied(&at.0, &aside_again.0.join("disk"));
    let lived =
        pulse::live(&network, &cohort, BEFORE, AWAY, PATIENCE).expect("the network goes on");
    assert_eq!(lived.len(), AWAY as usize);
    let head = BEFORE + AWAY - 2;
    assert_eq!(network.head().expect("the store answers"), Some(head));

    // The machine come back holds the head of three windows ago, and reaches the network.
    let (back, born) = Machine::start(&Configuration::at(aside.0.join("disk"), "127.0.0.1:0"))
        .expect("the machine away starts");
    assert!(!born, "the disk kept aside drew a second secret");
    assert_eq!(back.head().expect("the store answers"), Some(BEFORE - 2));
    assert_eq!(
        back.closed_window().expect("the store answers"),
        Some(BEFORE - 1)
    );
    let network = reached(&back, network);

    // Refused: an anchor a byte of which turned on its own disk. The certificate of the window after
    // it decides the proposal the network holds and not the turned one, and the machine keeps nothing
    // over what it held and lives nothing.
    let own_head = back
        .proposal_of(BEFORE - 2)
        .expect("the store answers")
        .expect("its head");
    let mut turned = own_head.clone();
    turned.note_root[0] ^= 1;
    back.keep_proposal(&turned).expect("the store takes it");
    assert_eq!(
        pulse::come_back(&back, BEFORE + AWAY, PATIENCE),
        Err(refused(
            "a certificate whose agreement does not decide the proposal it finalizes"
        ))
    );
    assert_eq!(back.head().expect("the store answers"), Some(BEFORE - 2));
    assert_eq!(
        back.closed_window().expect("the store answers"),
        Some(BEFORE - 1)
    );
    back.keep_proposal(&own_head)
        .expect("the store takes it back");

    // The way back: the walk from its own anchor reaches the network's head, keeps the proposal the
    // network closed its last window on, awaiting its certificate, and the machine is answered the
    // window the network stands at. It lives that window and the next.
    let from = pulse::come_back(&back, BEFORE + AWAY, PATIENCE).expect("the walk back");
    assert_eq!(from, head + 2);
    assert_eq!(back.head().expect("the store answers"), Some(head));
    assert_eq!(
        back.closed_window().expect("the store answers"),
        Some(head + 1)
    );
    for window in [head - 1, head, head + 1] {
        assert_eq!(
            back.proposal_of(window)
                .expect("the store answers")
                .map(|held| id_of(&held)),
            network
                .proposal_of(window)
                .expect("the store answers")
                .map(|held| id_of(&held)),
            "the walk back kept another proposal of window {window} than the network's"
        );
    }
    let again = pulse::live(&back, &cohort, from, 2, PATIENCE).expect("the machine lives on");
    assert_eq!(
        again.iter().map(|one| one.window).collect::<Vec<_>>(),
        vec![head + 2, head + 3]
    );
    let missed = network
        .proposal_of(head + 1)
        .expect("the store answers")
        .expect("the network's last proposal");
    let own = back
        .proposal_of(head + 2)
        .expect("the store answers")
        .expect("the window it lived on");
    assert_eq!(
        own.previous,
        id_of(&missed),
        "the machine come back stands on another proposal than the one the network closed on"
    );
    assert_eq!(
        own.cement_count, 1,
        "its part is not in the cement it lived"
    );
    assert_eq!(again[0].proposal, id_of(&own));
    // The proposal the network closed its last window on is final now, by the decision of the
    // window the machine come back lived.
    assert_eq!(back.head().expect("the store answers"), Some(head + 2));
    assert_eq!(
        back.proposal_of(head + 1)
            .expect("the store answers")
            .map(|held| id_of(&held)),
        Some(id_of(&missed))
    );
    drop(back);

    // A device handed an anchor nothing stands after — the network's own head — is told no
    // certificate stands, and keeps nothing.
    let (device, _) =
        Machine::start(&Configuration::at(&device_at.0, "127.0.0.1:0")).expect("the device starts");
    let network = reached(&device, network);
    let anchor = Anchor {
        earlier: network
            .proposal_of(head)
            .expect("the store answers")
            .expect("kept"),
        later: missed.clone(),
    };
    assert_eq!(
        pulse::join(&device, &anchor, PATIENCE).map(|_| ()),
        Err(refused(NO_CERTIFICATE))
    );
    assert_eq!(device.head().expect("the store answers"), None);
    assert_eq!(device.closed_window().expect("the store answers"), None);
    drop(device);

    // The end of the retention, by the holders' own rule rather than by hand: a holder keeping a cell
    // of window `w` lets go of the points of every window below `w - retained_windows`
    // (`montana-node/src/lib.rs`, `keep_the_cell`, calling `mt-store/src/lib.rs`,
    // `drop_points_before`). The network is not lived on to window `BEFORE + 1 + retained_windows`
    // here; the same rule is applied to its disk as it stands at that window, which lets go of the
    // first window the machine missed and of every window before it. The second copy of the disk
    // comes back and is told no certificate stands; its head, its closed window and its kept
    // proposals stand as they were.
    drop(network);
    mt_store::Store::open(&at.0)
        .expect("the network's store opens")
        .drop_points_before(BEFORE + 1)
        .expect("the points of the windows past the retention go");
    assert!(!at.0.join("points").join(format!("{BEFORE:020}")).exists());
    let (network, _) = Machine::start(&Configuration::at(&at.0, "127.0.0.1:0"))
        .expect("the network answers again");
    let (late, _) = Machine::start(&Configuration::at(
        aside_again.0.join("disk"),
        "127.0.0.1:0",
    ))
    .expect("the machine away longer starts");
    let _network = reached(&late, network);
    assert_eq!(
        pulse::come_back(&late, BEFORE + AWAY, PATIENCE),
        Err(refused(NO_CERTIFICATE))
    );
    assert_eq!(late.head().expect("the store answers"), Some(BEFORE - 2));
    assert_eq!(
        late.closed_window().expect("the store answers"),
        Some(BEFORE - 1)
    );
    assert!(late
        .proposal_of(BEFORE)
        .expect("the store answers")
        .is_none());
}
