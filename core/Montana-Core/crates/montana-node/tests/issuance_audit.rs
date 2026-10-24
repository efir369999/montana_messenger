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
    let naming = mt_derive::nullifier::machine_halves(&secret).1;
    let mut root = mt_proof::admitted::leaf(&naming).unwrap();
    let siblings = mt_proof::admitted::empty_internals(mt_proof::tree_depth());
    for sibling in siblings.iter().take(mt_proof::tree_depth()) {
        root = mt_proof::admitted::node(&root, sibling);
    }
    let mut state = State::new().with_admitted(root);
    let right = attest::right_of(&secret, 1_000, 1).unwrap();
    let forged = u128::from(right.share) + 1;
    let (payee, spending_key) = payee_of(0xA1);
    let payment = wallet
        .redeem(
            &secret,
            right.window,
            forged,
            &siblings[..mt_proof::tree_depth()],
            0,
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
    assert!(forged > u128::from(attest::mint_of(right.window).unwrap()));

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
    eprintln!("OPEN FINDING: the verifier accepted issuance above the entire window budget and its onward spend");
}
