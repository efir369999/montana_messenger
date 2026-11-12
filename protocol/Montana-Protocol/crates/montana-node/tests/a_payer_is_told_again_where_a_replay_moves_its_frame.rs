// A payer is told what its frame took as its round leaves, and told again where a replay of a
// decided roll moves it — or that it applies in no window. Consensus, "When the decision is not the
// name a machine took": "A payer learns what its frame took as the round carrying it leaves ... and
// where a replay moves it, the replay tells it again: the positions its commitments hold in the
// chain are those of the decided rolls"; the invariants of the agreement: "A payer is told what its
// frame took as its round leaves and told again where a replay moves it"; "Conformance set", item 19.
//
// **What is measured.** The payer's wallet, which is what the payer holds: after the round leaves,
// the notes the payment spent are gone and the note it left the payer stands at the position the
// round gave it; told again that the frame moved, that note stands at the position the decided roll
// gave it, and its nullifier with it; told that the frame applies in no window, the spent notes stand
// again and the note the payment left is forgotten. Once the window is final, nothing is told again.
//
// **The wrong implementations it refuses**, named before the assertions: a wallet keeping the
// positions of the round's leaving after a replay moved the frame — its note would spend by the
// nullifier of a position the decided chain never gave it, and the network would refuse the
// spending; and one leaving the spent notes spent where the frame applies in no window — value the
// payer holds, lost to a frame nobody applied.

use montana_node::{Configuration, Machine, Told};
use montana_wallet::{Note, Wallet};
use std::collections::BTreeMap;
use std::sync::mpsc;

mod common;
use common::{of, payee_of, Scratch};

const WINDOW: u64 = 1_100;
const CHAIN: u8 = 0;
const ROUND: u32 = 0;
const PAID: u128 = 250_000_000;

#[test]
fn a_payer_is_told_again_where_a_replay_moves_its_frame_and_when_it_applies_nowhere() {
    let machine_at = Scratch::named("told-again-machine");
    let ledger_at = Scratch::named("told-again-ledger");
    let wallet = Wallet::open(&ledger_at.0).expect("a wallet opens");
    let (of_payer, payer_key) = payee_of(0xA1);
    let (of_payee, _) = payee_of(0xB2);
    let (machine, _) = Machine::start(&Configuration::at(&machine_at.0, "127.0.0.1:0"))
        .expect("the machine starts");

    let inputs = mt_genesis::scalar("spend_inputs").expect("the Decree names it");
    let count = mt_genesis::scalar("spends_per_frame").expect("the Decree names it");
    let mut seeded: Vec<Note> = Vec::new();
    for at in 0..inputs * count {
        let note = Note::of(
            1_000_000_000,
            of_payer.note_pk,
            payer_key,
            of(0xC3, at as u8),
            at,
        )
        .expect("a note of the family");
        machine
            .value()
            .expect("the machine holds its state")
            .witness(&note.commitment)
            .expect("the tree takes it");
        wallet.enter(note.clone()).expect("the ledger takes it");
        seeded.push(note);
    }
    let held_before = wallet.balance().expect("a balance");
    machine
        .enter_round(WINDOW, CHAIN, ROUND)
        .expect("the machine stands in the round");
    // The wallet is dropped while the machine pays out of it: one store, one holder at a time.
    drop(wallet);

    // The payment stands at the points of the round, and applies as the machine leaves it.
    let (told, heard) = mpsc::channel();
    machine
        .pay_of_its_own(
            &ledger_at.0,
            &of_payee,
            PAID,
            WINDOW,
            CHAIN,
            ROUND,
            &of(0xD4, 0),
            Box::new(move |settled| {
                let _ = told.send(
                    settled
                        .map(|paid| paid.position)
                        .map_err(|e| format!("{e:?}")),
                );
            }),
        )
        .expect("the frame stands at the points of its round");
    assert_eq!(
        machine
            .apply_what_stands()
            .expect("the machine walks its points"),
        1
    );
    let paid_at = heard
        .try_recv()
        .expect("told as the round left")
        .expect("the frame applied");
    let frame = machine
        .value()
        .expect("the plane")
        .operations_of(WINDOW)
        .first()
        .copied()
        .expect("the one frame the round applied");

    // What the round left the payer: the spent notes gone, one note of change at a position after
    // the payee's.
    let wallet = Wallet::open(&ledger_at.0).expect("a wallet opens");
    let after = wallet.ledger().expect("a ledger");
    assert_eq!(wallet.balance().expect("a balance"), held_before - PAID);
    assert!(
        after
            .held
            .iter()
            .all(|note| !seeded.iter().any(|was| was.commitment == note.commitment)),
        "a spent note stands in the wallet"
    );
    let change: Vec<Note> = after.held.clone();
    assert!(
        !change.is_empty(),
        "the payment left the payer nothing to be told about"
    );
    assert!(change.iter().all(|note| note.position > paid_at));
    drop(wallet);

    // **Told again: the frame moved.** The decided roll put the frame's commitments a hundred
    // positions on; the change moves with them, and its nullifier with it.
    let moved: Vec<u64> = (0..32).map(|which| paid_at + which + 100).collect();
    let mut positions = BTreeMap::new();
    positions.insert(frame, moved.clone());
    assert_eq!(
        machine.retell(WINDOW, &positions).expect("told again"),
        1,
        "one settlement of the window was due to be told"
    );
    let wallet = Wallet::open(&ledger_at.0).expect("a wallet opens");
    let after_move = wallet.ledger().expect("a ledger");
    assert_eq!(wallet.balance().expect("a balance"), held_before - PAID);
    for note in &change {
        let now = after_move
            .held
            .iter()
            .find(|held| held.commitment == note.commitment)
            .expect("the change still stands");
        assert_eq!(now.position, note.position + 100, "the change did not move");
        assert_ne!(
            now.nullifier().expect("a nullifier"),
            note.nullifier().expect("a nullifier"),
            "the nullifier did not move with the position"
        );
    }
    // Told the same positions again, nothing is said.
    drop(wallet);
    assert_eq!(machine.retell(WINDOW, &positions).expect("told again"), 0);

    // **Told again: the frame applies in no window.** The spent notes stand again, and the change
    // never stood.
    assert_eq!(
        machine
            .retell(WINDOW, &BTreeMap::new())
            .expect("told again"),
        1
    );
    let wallet = Wallet::open(&ledger_at.0).expect("a wallet opens");
    let taken_back = wallet.ledger().expect("a ledger");
    assert_eq!(
        wallet.balance().expect("a balance"),
        held_before,
        "the notes a frame applied nowhere spent did not come back"
    );
    for was in &seeded {
        let note = taken_back
            .held
            .iter()
            .find(|held| held.commitment == was.commitment)
            .expect("a spent note stands again");
        assert_eq!(note.position, was.position);
    }
    assert!(
        taken_back
            .held
            .iter()
            .all(|held| !change.iter().any(|left| left.commitment == held.commitment)),
        "the change of a frame applied nowhere stands in the wallet"
    );
    assert!(
        taken_back.spent.is_empty(),
        "a nullifier stands written for a spending that happened in no window"
    );
    drop(wallet);

    // Told Applied again -- the decided roll holds the frame after all -- the notes are spent anew
    // and kept whole for a replay to move or give back.
    assert_eq!(machine.retell(WINDOW, &positions).expect("told again"), 1);
    let wallet = Wallet::open(&ledger_at.0).expect("a wallet opens");
    let spent_again = wallet.ledger().expect("a ledger");
    assert_eq!(wallet.balance().expect("a balance"), held_before - PAID);
    assert_eq!(
        spent_again.gone.len(),
        seeded.len(),
        "the spent notes are not kept whole"
    );
    assert_eq!(spent_again.spent.len(), seeded.len());
    drop(wallet);

    // **The window is final**: nothing of it is told again, and what the wallet kept whole of the
    // spent notes goes while the nullifiers written for them stay, so none of them enters again.
    machine
        .settled_through(WINDOW)
        .expect("the settlements of a final window go");
    assert_eq!(machine.retell(WINDOW, &positions).expect("told again"), 0);
    let wallet = Wallet::open(&ledger_at.0).expect("a wallet opens");
    let final_ledger = wallet.ledger().expect("a ledger");
    assert!(
        final_ledger.gone.is_empty(),
        "spent notes kept whole past the finality of their window"
    );
    assert_eq!(final_ledger.spent.len(), seeded.len());
    assert_eq!(
        wallet.enter(seeded[0].clone()).err(),
        Some(montana_wallet::WalletError::AlreadySpent)
    );
}

// A frame the round passed over that the decided roll holds applies for the first time at the
// replay, and its payer is told Applied — not Moved: it never entered anything it could move, and
// what it is told now is what it would have been told as the round left. The wrong implementation
// refused: a retelling that turns none-then-some into Moved, under which the payer's wallet would
// move a note it never held (NotHeld) and keep the spent notes it took back.
#[test]
fn a_frame_the_round_passed_over_is_told_applied_when_the_decided_roll_holds_it() {
    let at = Scratch::named("told-applied-late");
    let (machine, _) =
        Machine::start(&Configuration::at(&at.0, "127.0.0.1:0")).expect("the machine starts");
    machine
        .enter_round(WINDOW, CHAIN, ROUND)
        .expect("the machine stands in the round");
    let frame = [0x7Eu8; 32];
    let (told, heard) = mpsc::channel();
    machine
        .settle_when_applied(
            (WINDOW, CHAIN, ROUND),
            frame,
            Box::new(move |what| {
                let _ = told.send(what);
            }),
        )
        .expect("the settlement waits");
    // The round leaves without the frame: told Left.
    assert_eq!(
        machine
            .apply_what_stands()
            .expect("the machine walks its points"),
        0
    );
    assert_eq!(heard.try_recv(), Ok(Told::Left));
    // The decided roll holds the frame at positions of its own: told Applied, then Moved where a
    // later replay moves it, then Left where one leaves it out.
    let mut positions = BTreeMap::new();
    positions.insert(frame, vec![40, 41]);
    assert_eq!(machine.retell(WINDOW, &positions).expect("told again"), 1);
    assert_eq!(heard.try_recv(), Ok(Told::Applied(vec![40, 41])));
    positions.insert(frame, vec![50, 51]);
    assert_eq!(machine.retell(WINDOW, &positions).expect("told again"), 1);
    assert_eq!(heard.try_recv(), Ok(Told::Moved(vec![50, 51])));
    assert_eq!(
        machine
            .retell(WINDOW, &BTreeMap::new())
            .expect("told again"),
        1
    );
    assert_eq!(heard.try_recv(), Ok(Told::Left));
    assert!(heard.try_recv().is_err(), "told what was not due");
}
