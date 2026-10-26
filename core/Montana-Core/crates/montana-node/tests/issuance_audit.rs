// THE FINDING, TURNED (Protocol-13 item 3, issue #14 A2 and T4). This test once reproduced an open
// finding: a right redeemed one coin above its window's credit became a spendable note and was paid
// onward. The frame now holds a right's worth to the credit, so the same redemption is refused
// before any balance moves, and the right it tried to inflate is still redeemable at its credit.
use montana_node::{attest, state::State};
use montana_wallet::{Note, Wallet};

mod common;
use common::{of, payee_of, Scratch};

#[test]
fn an_oversized_right_is_refused_and_the_right_stays_redeemable_at_its_credit() {
    let location = Scratch::named("issuance-audit");
    let wallet = Wallet::open(&location.0).unwrap();
    let secret = of(0x77, 0);
    // The machine lived window 1 000, and the proposal of the window after it credited its part.
    let part = mt_derive::nullifier::part(&secret, 1_000).unwrap();
    let mut state = State::new();
    state.credit(&[part]).unwrap();
    let (siblings, position) = state.credited_branch(&part).unwrap();
    let root = state.credited();
    let right = attest::right_of(&secret, 1_000).unwrap();
    let credit = u128::from(attest::window_credit().unwrap());
    assert_eq!(u128::from(right.worth), credit, "a right is worth its window's credit");
    let (payee, spending_key) = payee_of(0xA1);
    let notes = state.notes_root();
    let redeem = |worth: u128, seed: u8| {
        wallet.redeem(
            &secret,
            right.window,
            worth,
            &siblings,
            position,
            &payee,
            right.accepted_in,
            &of(seed, 0),
            &notes,
            &root,
        )
    };

    // One coin above the credit: no proof the verifier takes, so nothing is applied.
    match redeem(credit + 1, 0xD4) {
        Err(_) => {}
        Ok(payment) => {
            let frame = mt_state::layout::Frame::parse(&payment.frame).unwrap();
            assert!(
                state.apply(&frame, right.accepted_in).is_err(),
                "the verifier accepted a right redeemed above its window's credit"
            );
        }
    }
    assert_eq!(state.notes_root(), notes, "a refused frame moved the tree of notes");
    assert_eq!(wallet.balance().unwrap(), 0, "a refused frame moved a balance");

    // At the credit the same right redeems: the refusal spent nothing of it.
    let payment = redeem(credit, 0xD5).unwrap();
    let frame = mt_state::layout::Frame::parse(&payment.frame).unwrap();
    let positions = state.apply(&frame, right.accepted_in).unwrap();
    let created = &payment.created[0];
    let note = Note::of(
        created.value,
        created.note_pk,
        spending_key,
        created.rcm,
        positions[0],
    )
    .unwrap();
    assert_eq!(note.commitment, frame.spends[0].commitments[0]);
    wallet.enter(note).unwrap();
    assert_eq!(wallet.balance().unwrap(), credit);
}
