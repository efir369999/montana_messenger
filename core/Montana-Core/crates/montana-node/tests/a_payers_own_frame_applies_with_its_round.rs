// A payer's own frame applies with the frames of its round and not before. Canon, "The roots of
// state": "A frame applies once, when a machine leaves the round whose points carry it, among the
// frames of that round in ascending order of identifier."
//
// **The wrong implementation it refuses**, named before the assertions: a payer that applies its own
// frame as it publishes it. The tree of notes would grow at the publication, the wallet would spend
// before the round applied anything, and a round carrying two payers' frames would apply them in an
// order of the payer's own at the payer and in the order of the names everywhere else — two roots
// for one window. Here the tree holds still until the machine leaves the round, the wallet holds its
// notes until then, and what the frame took is told only as the round applies it; a frame the round
// left without applying is told nothing and spends nothing.

use montana_node::{Configuration, Machine, Told};
use montana_wallet::{Note, Wallet};
use std::sync::mpsc;

mod common;
use common::{of, payee_of, Scratch};

const WINDOW: u64 = 1_000;
const CHAIN: u8 = 0;
const ROUND: u32 = 0;
const PAID: u128 = 250_000_000;

#[test]
fn a_payers_own_frame_applies_as_it_leaves_the_round() {
    let machine_at = Scratch::named("own-frame-machine");
    let ledger_at = Scratch::named("own-frame-ledger");
    let wallet = Wallet::open(&ledger_at.0).expect("a wallet opens");
    let (of_payer, payer_key) = payee_of(0xA1);
    let (of_payee, _) = payee_of(0xB2);
    let (machine, _) = Machine::start(&Configuration::at(&machine_at.0, "127.0.0.1:0"))
        .expect("the machine starts");

    // The notes the payer holds stand in the tree of the machine it lives on.
    let inputs = mt_genesis::scalar("spend_inputs").expect("the Decree names it");
    let count = mt_genesis::scalar("spends_per_frame").expect("the Decree names it");
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
        wallet.enter(note).expect("the ledger takes it");
    }
    let held = wallet.balance().expect("a balance");
    // One store, one holder at a time: the wallet is dropped while the machine pays out of it, and
    // opened again to read what the payment left.
    drop(wallet);
    let notes_held = || {
        machine
            .value()
            .expect("the machine holds its state")
            .notes_held()
    };
    machine
        .enter_round(WINDOW, CHAIN, ROUND)
        .expect("the machine stands in the round");

    // A settlement whose frame never stood at the points of its round is told nothing as the round
    // leaves.
    let (told, heard) = mpsc::channel();
    machine
        .settle_when_applied(
            (WINDOW, CHAIN, ROUND),
            [0x5Au8; 32],
            Box::new(move |what| {
                let _ = told.send(match what {
                    Told::Applied(positions) => Some(positions),
                    _ => None,
                });
            }),
        )
        .expect("the settlement waits");
    assert_eq!(
        machine
            .apply_what_stands()
            .expect("the machine walks its points"),
        0
    );
    assert_eq!(heard.try_recv(), Ok(None));

    // The payment: published at the points of the round, and applied nowhere yet.
    let before = notes_held();
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
                        .map(|paid| (paid.value, paid.position))
                        .map_err(|e| format!("{e:?}")),
                );
            }),
        )
        .expect("the frame stands at the points of its round");
    assert_eq!(
        notes_held(),
        before,
        "the payer applied its own frame as it published it"
    );
    let wallet = Wallet::open(&ledger_at.0).expect("a wallet opens again");
    assert_eq!(
        wallet.balance().expect("a balance"),
        held,
        "the wallet spent before the round applied the frame"
    );
    drop(wallet);
    assert!(
        heard.try_recv().is_err(),
        "the payment was settled before its round left"
    );

    // The machine leaves the round: the frame applies among the round's frames, and only now is the
    // payer told where the payee's note stands.
    assert_eq!(
        machine
            .apply_what_stands()
            .expect("the machine walks its points"),
        1
    );
    let (value, position) = heard
        .try_recv()
        .expect("told as the round left")
        .expect("the frame applied");
    assert_eq!(value, PAID);
    assert_eq!(
        position, before,
        "the payee's note took the first free position"
    );
    assert!(notes_held() > before);
    let wallet = Wallet::open(&ledger_at.0).expect("a wallet opens again");
    assert_eq!(
        wallet.balance().expect("a balance"),
        held - PAID,
        "the notes it spent left and what the payment did not pay away came back"
    );
}
