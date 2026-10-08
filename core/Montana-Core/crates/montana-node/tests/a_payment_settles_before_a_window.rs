// A payment settles when it stands, and it waits for no window.
//
// **What is measured.** A note reaches its owner inside a frame, and the question this vector
// answers is when that owner may spend it: at the moment the frame stands in the tree, or only once
// the window carrying it has closed on a cement. The two answers are a whole protocol apart — the
// first is one echo, the second is `target_rounds` of them — and neither the set nor this tree held
// a measurement of which one is built.
//
// **The wrong implementation this vector refuses.** One that settles at the close of a window. The
// second payment below is built against the tree as the first left it, in the same window, with
// nothing cemented, no beacon anywhere and no proposal assembled. An implementation that made a
// note spendable only at a close would leave the payee holding nothing to spend here, and the
// second frame would have no note to prove a path for.
//
// **Why no window appears in it at all.** Applying a frame reads the window only as one value of
// the public input its proof binds; nothing of the pulse is constructed in this file, and that
// absence is the whole of the assertion.

use montana_node::state::State;
use montana_wallet::{Note, Wallet};
use mt_state::Layout;

mod common;
use common::{of, payee_of, Scratch};

const WINDOW: u64 = 1_000;

#[test]
fn a_note_is_spendable_the_moment_it_stands_and_no_window_closes_between() {
    let payer_at = Scratch::named("settlement-payer");
    let payee_at = Scratch::named("settlement-payee");
    let third_at = Scratch::named("settlement-third");
    let payer = Wallet::open(&payer_at.0).expect("a wallet opens");
    let payee = Wallet::open(&payee_at.0).expect("a wallet opens");
    let third = Wallet::open(&third_at.0).expect("a wallet opens");
    let (of_payer, payer_key) = payee_of(0xA1);
    let (of_payee, payee_key) = payee_of(0xB2);
    let (of_third, third_key) = payee_of(0xC3);

    let mut state = State::new();
    let inputs = mt_genesis::scalar("spend_inputs").expect("the Decree names it");
    let count = mt_genesis::scalar("spends_per_frame").expect("the Decree names it");
    let taking = (inputs * count) as usize;
    let each = 1_000_000_000u128;
    for at in 0..taking {
        let note = Note::of(
            each,
            of_payer.note_pk,
            payer_key,
            of(0xD4, at as u8),
            at as u64,
        )
        .expect("a note of the family");
        state
            .witness(&note.commitment)
            .expect("the tree takes a commitment");
        payer.enter(note).expect("the ledger takes it");
    }
    let admitted = mt_proof::admitted::empty_root();

    // The first payment. Everything of it is ordinary; what matters is the tree it leaves behind.
    let paths: Vec<Vec<mt_proof::poseidon::Digest>> = (0..taking as u64)
        .map(|at| state.path_of(at).expect("a position that was written"))
        .collect();
    let before = state.notes_root();
    let amount = 400_000_000u128;
    let first = payer
        .pay(
            &of_payee,
            amount,
            WINDOW,
            &of(0xE5, 0),
            &of_payer,
            &paths,
            &before,
            &admitted,
        )
        .expect("a payment of what the payer holds");
    let object = mt_state::layout::Frame::parse(&first.frame).expect("a frame reads back");
    let positions = state.apply(&object, WINDOW).expect("a true frame applies");
    let created = first.created.first().expect("a payment creates a note");
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
        amount,
        "the payee does not hold what it was paid"
    );

    // **Nothing happens here.** No beacon is built, no attestation is folded, no cement moves, no
    // proposal is assembled and the window does not change. If settlement were the close of a
    // window, this is where the payee would wait, and everything below would be unreachable.
    let after = state.notes_root();
    assert_ne!(
        before.bytes(),
        after.bytes(),
        "the tree did not move, so the note the payee holds stands nowhere"
    );

    // The payee spends what it was paid, against the tree as the first payment left it.
    let onward = 250_000_000u128;
    let of_the_payee = vec![state
        .path_of(positions[0])
        .expect("the position the first payment wrote")];
    let second = payee
        .pay(
            &of_third,
            onward,
            WINDOW,
            &of(0xF6, 0),
            &of_payee,
            &of_the_payee,
            &after,
            &admitted,
        )
        .expect("a payment of a note that stands in the tree");
    let onward_object = mt_state::layout::Frame::parse(&second.frame).expect("a frame reads back");
    let onward_positions = state
        .apply(&onward_object, WINDOW)
        .expect("a frame against the tree as it stands applies, with no window closed between");

    let paid = second.created.first().expect("a payment creates a note");
    assert_eq!(paid.value, onward, "the note created is not the payment");
    let held = Note::of(
        paid.value,
        paid.note_pk,
        third_key,
        paid.rcm,
        onward_positions[0],
    )
    .expect("a note of the family");
    third.enter(held).expect("the ledger takes it");
    assert_eq!(
        third.balance().expect("a balance"),
        onward,
        "value did not reach a third owner inside one window"
    );

    // And the payee holds what the onward payment left it. Value crossed two owners between one
    // beacon and the next, which is what settling in an echo means.
    for commitment in &second.spent {
        payee.spend(commitment).expect("a note it held is spent");
    }
    payee
        .enter_what_it_left(&second, &onward_positions, &payee_key)
        .expect("the ledger takes what the payment left");
    assert_eq!(
        payee.balance().expect("a balance"),
        amount - onward,
        "the payee holds neither what it kept nor what it was left with"
    );
}
