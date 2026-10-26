// Where value enters the network at all: a window closes, its cement names the machines that lived
// it, each takes a right to its coin, and a right becomes a note by being extinguished inside an
// ordinary payment. Only then can one wallet pay another — and that is the whole of the chain this
// stage is measured by.
//
// **The named wrong implementation this refuses**: a circuit knowing only a note and a right. A
// machine that has just closed the first window of the network holds one right and nothing else,
// and five of its six redemption positions have nothing to put in them. Without filler it cannot
// compose a frame at all, so nothing minted ever becomes spendable and the network never holds its
// first note.

use montana_node::attest;
use montana_node::state::State;
use montana_wallet::{Note, Wallet};
use mt_state::Layout;

mod common;
use common::{of, payee_of, Scratch};

const WINDOW: u64 = 1_000;

#[test]
fn a_window_mints_a_right_the_right_becomes_a_note_and_the_note_is_paid_away() {
    let miner_at = Scratch::named("value-miner");
    let payee_at = Scratch::named("value-payee");
    let miner = Wallet::open(&miner_at.0).expect("a wallet opens");
    let payee = Wallet::open(&payee_at.0).expect("a wallet opens");
    let (of_miner, miner_key) = payee_of(0xA1);
    let (of_payee, payee_key) = payee_of(0xB2);

    let machine_secret = of(0x77, 0);
    // The window closed on a cement naming one machine, and the proposal of the window after it
    // credited that machine's part: the leaf its right walks to.
    let part = mt_derive::nullifier::part(&machine_secret, WINDOW).expect("a secret of the family");
    let mut state = State::new();
    state.credit(&[part]).expect("a cement the tree holds");
    let (credited_siblings, credited_position) = state
        .credited_branch(&part)
        .expect("the part the window credited");
    let credited_root = state.credited();

    // The window closed on a cement naming one machine, so that machine takes one coin, as every
    // machine of every cement does.
    let right = attest::right_of(&machine_secret, WINDOW).expect("a window that named a machine");
    assert_eq!(right.window, WINDOW);
    assert_eq!(right.worth, 1, "a right is worth one coin");

    // The right becomes a note: five positions of filler, the sixth the right itself, and the coin
    // leaves as one note the machine pays to itself. Nothing else could have been built — this
    // wallet holds not one note yet.
    assert_eq!(miner.balance().expect("a balance"), 0);
    let minted = miner
        .redeem(
            &machine_secret,
            WINDOW,
            u128::from(right.worth),
            &credited_siblings,
            credited_position,
            &of_miner,
            right.accepted_in,
            &of(0xD4, 0),
            &state.notes_root(),
            &credited_root,
        )
        .expect("a machine holding one right writes a frame");

    let object = mt_state::layout::Frame::parse(&minted.frame).expect("a frame reads back");
    let positions = state
        .apply(&object, right.accepted_in)
        .expect("a true frame applies");
    let created = minted.created.first().expect("a redemption creates a note");
    assert_eq!(
        u128::from(right.worth),
        created.value,
        "the note created is not the coin the window credited"
    );
    let note = Note::of(
        created.value,
        created.note_pk,
        miner_key,
        created.rcm,
        positions[0],
    )
    .expect("a note of the family");
    assert_eq!(
        note.commitment, object.spends[0].commitments[0],
        "the note the machine holds is not the commitment its frame published"
    );
    miner.enter(note).expect("the ledger takes it");
    assert_eq!(
        miner.balance().expect("a balance"),
        u128::from(right.worth),
        "the first value of the network did not reach the wallet that mined it"
    );

    // And now it pays like anybody: the whole coin, since nothing smaller than a coin exists. The
    // wallet holds one note where a frame consumes six, so the rest of its positions take filler
    // too — the same branch, used for what it was written for.
    let paid = u128::from(right.worth);
    let taking = (mt_genesis::scalar("spend_inputs").expect("named")
        * mt_genesis::scalar("spends_per_frame").expect("named")) as usize;
    let mut paths = Vec::with_capacity(taking);
    for at in 0..taking as u64 {
        paths.push(state.path_of(at).unwrap_or_default());
    }
    let payment = miner
        .pay(
            &of_payee,
            paid,
            WINDOW,
            &of(0xD5, 0),
            &of_miner,
            &paths,
            &state.notes_root(),
            &credited_root,
        )
        .expect("a wallet holding a note pays");
    let object = mt_state::layout::Frame::parse(&payment.frame).expect("a frame reads back");
    let positions = state.apply(&object, WINDOW).expect("a true frame applies");
    let created = payment.created.first().expect("a payment creates a note");
    let taken = Note::of(
        created.value,
        created.note_pk,
        payee_key,
        created.rcm,
        positions[0],
    )
    .expect("a note of the family");
    payee.enter(taken).expect("the ledger takes it");
    assert_eq!(
        payee.balance().expect("a balance"),
        paid,
        "the payee does not hold what it was paid"
    );
}
