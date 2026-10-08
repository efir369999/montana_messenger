// One wallet pays another, over the state a machine holds: the payer builds a frame against the
// tree of notes as it stands, proves it, the machine verifies and applies it, and the payee enters
// the note that came out of it.
//
// **The machine learns nothing of the payment.** What it is handed is nullifiers, commitments and
// the nullifier of a rate — values that name nobody and carry no amount — and what it does with
// them is check a proof and append. Who paid whom, and how much, is not in what it keeps, because
// it is not in what it is given.
//
// **A note spent twice is refused by the state and not by a rule of politeness.** The second frame
// carries a nullifier the state already holds, so it is refused before its proof is looked at.

use montana_node::state::State;
use montana_wallet::{Note, Wallet};
use mt_state::Layout;

mod common;
use common::{of, payee_of, Scratch};

const WINDOW: u64 = 1_000;

#[test]
fn a_wallet_pays_a_wallet_and_the_machine_learns_nothing_of_it() {
    let payer_at = Scratch::named("payment-payer");
    let payee_at = Scratch::named("payment-payee");
    let payer = Wallet::open(&payer_at.0).expect("a wallet opens");
    let payee = Wallet::open(&payee_at.0).expect("a wallet opens");
    let (of_payer, payer_key) = payee_of(0xA1);
    let (of_payee, payee_key) = payee_of(0xB2);

    // The state as it stands before the payment, and the notes the payer holds in it. What matters
    // here is that the tree the payer proves against is the tree the machine holds.
    let mut state = State::new();
    let inputs = mt_genesis::scalar("spend_inputs").expect("the Decree names it");
    let outputs = mt_genesis::scalar("spend_outputs").expect("the Decree names it");
    let count = mt_genesis::scalar("spends_per_frame").expect("the Decree names it");
    let taking = (inputs * count) as usize;
    let each = 1_000_000_000u128;
    for at in 0..taking {
        let note = Note::of(
            each,
            of_payer.note_pk,
            payer_key,
            of(0xC3, at as u8),
            at as u64,
        )
        .expect("a note of the family");
        state
            .witness(&note.commitment)
            .expect("the tree takes a commitment");
        payer.enter(note).expect("the ledger takes it");
    }
    assert_eq!(
        payer.balance().expect("a balance"),
        each * taking as u128,
        "the payer holds what was witnessed for it"
    );
    assert_eq!(payee.balance().expect("a balance"), 0);

    // The paths are the machine's answer, one per note: a payer proves its notes stand in the tree
    // the machine holds, and it is the machine that knows where.
    let paths: Vec<Vec<mt_proof::poseidon::Digest>> = (0..taking as u64)
        .map(|at| state.path_of(at).expect("a position that was written"))
        .collect();
    let root = state.notes_root();
    let admitted = mt_proof::admitted::empty_root();

    let amount = 250_000_000u128;
    let payment = payer
        .pay(
            &of_payee,
            amount,
            WINDOW,
            &of(0xD4, 0),
            &of_payer,
            &paths,
            &root,
            &admitted,
        )
        .expect("a payment of what the payer holds");

    // What crosses is a frame of the one width the Decree fixes, whatever it pays.
    assert_eq!(
        payment.frame.len(),
        State::width_of_a_frame(),
        "a frame of another width would be an object of another shape"
    );

    // The machine verifies it and applies it. Everything it holds afterwards is public: how many
    // commitments stand in its tree, and which nullifiers are spent.
    let object = mt_state::layout::Frame::parse(&payment.frame).expect("a frame reads back");
    let before = state.notes_held();
    let positions = state.apply(&object, WINDOW).expect("a true frame applies");
    assert_eq!(
        positions.len(),
        (count * outputs) as usize,
        "every commitment a frame creates took a position"
    );
    assert_eq!(state.notes_held(), before + positions.len() as u64);
    for spend in &object.spends {
        for nullifier in &spend.nullifiers {
            assert!(state.is_spent(nullifier), "a spent note was not recorded");
        }
    }

    // The payee enters the note it was paid. It holds the secrets of it — the key it is paid to and
    // the half its commitment binds — and the blinding factor reached it with the note itself; the
    // position is where the machine appended it.
    let created = payment.created.first().expect("a payment creates a note");
    assert_eq!(
        created.value, amount,
        "the first note created is the payment"
    );
    let taken = Note::of(
        created.value,
        created.note_pk,
        payee_key,
        created.rcm,
        positions[0],
    )
    .expect("a note of the family");
    assert_eq!(
        taken.commitment, object.spends[0].commitments[0],
        "the note the payee holds is not the commitment the frame published"
    );
    payee.enter(taken).expect("the ledger takes it");
    assert_eq!(
        payee.balance().expect("a balance"),
        amount,
        "the payee does not hold what it was paid"
    );

    // And what the payer holds is what it kept: every note it consumed leaves its ledger, and every
    // note the frame created for the payer enters it. A frame carries the value of what it spends
    // whether it pays it away or not — the first note of the first spend is the payment and every
    // other note of the frame is the payer's own — so a payer that only spent would have destroyed
    // the difference. This is the check that catches it: the balance afterwards is what was held
    // less what was paid, and an implementation that publishes the frame and enters nothing answers
    // zero here.
    for commitment in &payment.spent {
        payer.spend(commitment).expect("a note it held is spent");
    }
    payer
        .enter_what_it_left(&payment, &positions, &payer_key)
        .expect("the ledger takes what the payment left");
    assert_eq!(
        payer.balance().expect("a balance"),
        each * taking as u128 - amount,
        "the payer holds neither what it kept nor what it was left with"
    );

    // The named wrong implementation this refuses: the same frame applied twice. Its nullifiers
    // already stand in the state, so it is refused before its proof is looked at — which is what
    // keeps one note from being spent twice.
    assert!(
        state.apply(&object, WINDOW).is_err(),
        "a frame spending notes already spent was applied a second time"
    );
    assert_eq!(state.notes_held(), before + positions.len() as u64);
}
