// THE FINDING, TURNED (Protocol-13 item 3, issue #14 A2 and T4). This test once reproduced an open
// finding: a right redeemed one coin above its window's credit became a spendable note and was paid
// onward. The frame now holds a right's worth to the credit, so the same redemption is refused
// before any balance moves, and the right it tried to inflate is still redeemable at its credit.
// The tests after it hold the rest of item 3: a right no window credited, a right redeemed to a
// recipient other than the one its proof names, and a right redeemed twice -- also across a
// restart -- are each refused by the verifier before any table moves.
use montana_node::{attest, state::State};
use montana_wallet::pay::Payment;
use montana_wallet::{Note, Wallet};
use mt_proof::poseidon::Digest;
use mt_state::Layout;

mod common;
use common::{of, payee_of, Scratch};

// One machine that lived window 1 000, its part credited by the proposal of the window after, and
// the wallet that redeems its right.
struct Lived {
    wallet: Wallet,
    secret: [u8; 32],
    state: State,
    siblings: Vec<Digest>,
    position: u64,
    right: attest::Right,
    credit: u128,
    _location: Scratch,
}

fn lived(name: &str) -> Lived {
    let location = Scratch::named(name);
    let wallet = Wallet::open(&location.0).unwrap();
    let secret = of(0x77, 0);
    let part = mt_derive::nullifier::part(&secret, 1_000).unwrap();
    let mut state = State::new();
    state.credit(&[part]).unwrap();
    let (siblings, position) = state.credited_branch(&part).unwrap();
    let right = attest::right_of(&secret, 1_000).unwrap();
    let credit = u128::from(attest::window_credit().unwrap());
    Lived {
        wallet,
        secret,
        state,
        siblings,
        position,
        right,
        credit,
        _location: location,
    }
}

impl Lived {
    // The redemption of this machine's right by `secret` (its own, or one that is not), to the
    // payee of `payee_seed`, proved against the state as it stands now.
    fn redeem_as(&self, secret: &[u8; 32], payee_seed: u8, rate_seed: u8) -> Option<Payment> {
        let (payee, _) = payee_of(payee_seed);
        self.wallet
            .redeem(
                secret,
                self.right.window,
                self.credit,
                &self.siblings,
                self.position,
                &payee,
                self.right.accepted_in,
                &of(rate_seed, 0),
                &self.state.notes_root(),
                &self.state.credited(),
            )
            .ok()
    }

    // A refusal moves nothing: the tree of notes and the wallet's balance stand as before.
    fn refused(&mut self, payment: Option<Payment>, what: &str) {
        let notes = self.state.notes_root();
        if let Some(payment) = payment {
            let frame = mt_state::layout::Frame::parse(&payment.frame).unwrap();
            assert!(
                self.state.apply(&frame, self.right.accepted_in).is_err(),
                "the verifier accepted {what}"
            );
        }
        assert_eq!(
            self.state.notes_root(),
            notes,
            "{what} moved the tree of notes"
        );
        assert_eq!(self.wallet.balance().unwrap(), 0, "{what} moved a balance");
    }
}

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
    assert_eq!(
        u128::from(right.worth),
        credit,
        "a right is worth its window's credit"
    );
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
    assert_eq!(
        state.notes_root(),
        notes,
        "a refused frame moved the tree of notes"
    );
    assert_eq!(
        wallet.balance().unwrap(),
        0,
        "a refused frame moved a balance"
    );

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

#[test]
fn a_right_no_window_credited_is_refused() {
    let mut lived = lived("issuance-audit-invented");
    // Another machine's secret walking the one credited part: its own part of window 1 000 stands
    // in no cement, so it holds a right no window issued.
    let stranger = of(0x78, 0);
    let payment = lived.redeem_as(&stranger, 0xA1, 0xD7);
    lived.refused(payment, "a right no window credited");
    assert!(
        lived.redeem_as(&lived.secret, 0xA1, 0xD8).is_some(),
        "the machine that lived the window lost its own right"
    );
}

#[test]
fn a_right_redeemed_to_another_recipient_than_its_proof_names_is_refused() {
    let mut lived = lived("issuance-audit-recipient");
    let to_a = lived.redeem_as(&lived.secret, 0xA1, 0xD9).unwrap();
    let to_b = lived.redeem_as(&lived.secret, 0xB2, 0xDA).unwrap();
    let theirs = mt_state::layout::Frame::parse(&to_b.frame).unwrap();
    let mut frame = mt_state::layout::Frame::parse(&to_a.frame).unwrap();
    assert_ne!(
        frame.spends[0].commitments[0],
        theirs.spends[0].commitments[0]
    );
    // The frame proved a coin to A, relayed with B's note in its place.
    frame.spends[0].commitments[0] = theirs.spends[0].commitments[0];
    let notes = lived.state.notes_root();
    assert!(
        lived.state.apply(&frame, lived.right.accepted_in).is_err(),
        "the verifier accepted a right paid to a recipient its proof does not name"
    );
    assert_eq!(
        lived.state.notes_root(),
        notes,
        "a refused frame moved the tree of notes"
    );
}

#[test]
fn a_right_redeemed_twice_is_refused_and_so_after_a_restart() {
    let mut lived = lived("issuance-audit-twice");
    let first = lived.redeem_as(&lived.secret, 0xA1, 0xDB).unwrap();
    let frame = mt_state::layout::Frame::parse(&first.frame).unwrap();
    lived.state.apply(&frame, lived.right.accepted_in).unwrap();
    // The second redemption is a fresh frame over the state as it now stands, so only the right's
    // own nullifier can stop it.
    let second = lived.redeem_as(&lived.secret, 0xA1, 0xDC);
    lived.refused(second, "a right redeemed a second time");
    // The node stops and reads its plane back: the right stays spent.
    lived.state = State::decode(&lived.state.encode().unwrap()).unwrap();
    let again = lived.redeem_as(&lived.secret, 0xA1, 0xDD);
    lived.refused(again, "a right redeemed a second time after a restart");
}
