// Reproduces an OPEN finding. A passing test here is evidence of the defect,
// not conformance. Replace the acceptance assertion with refusal when the
// issued entitlement is authenticated by the frame relation.
use montana_node::{attest, state::State};
use montana_wallet::{Note, Wallet};
use mt_state::Layout;

mod common;
use common::{of, payee_of, Scratch};

#[test]
fn audit_reproduces_an_oversized_right_becoming_a_spendable_note() {
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
    let forged = u128::from(right.worth) + 1;
    let (payee, spending_key) = payee_of(0xA1);
    let payment = wallet
        .redeem(
            &secret,
            right.window,
            forged,
            &siblings,
            position,
            &payee,
            right.accepted_in,
            &of(0xD4, 0),
            &state.notes_root(),
            &root,
        )
        .unwrap();
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
    assert_eq!(wallet.balance().unwrap(), forged);
    // A right is worth its window's credit (Consensus, "The right to a window's coin"); the frame
    // took one coin more.
    assert!(forged > u128::from(attest::window_credit().unwrap()));

    let (recipient, _) = payee_of(0xB2);
    let positions = (mt_genesis::scalar("spend_inputs").unwrap()
        * mt_genesis::scalar("spends_per_frame").unwrap()) as usize;
    let paths: Vec<_> = (0..positions)
        .map(|at| state.path_of(at as u64).unwrap_or_default())
        .collect();
    let paid = wallet
        .pay(
            &recipient,
            forged,
            right.accepted_in,
            &of(0xD5, 0),
            &payee,
            &paths,
            &state.notes_root(),
            &root,
        )
        .unwrap();
    let forwarded = mt_state::layout::Frame::parse(&paid.frame).unwrap();
    state.apply(&forwarded, right.accepted_in).unwrap();
    assert_eq!(paid.created[0].value, forged);
    eprintln!("OPEN FINDING: the verifier accepted a right redeemed above its window's credit and its onward spend");
}
