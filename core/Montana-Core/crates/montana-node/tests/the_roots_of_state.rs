// The seven roots and the count a proposal carries, recomputed from the plane as a real frame left
// it. Canon, "The roots of state".
//
// **The wrong implementations it refuses**, named before the assertions: a set of nullifiers taking
// the rate nullifier of a spend as an entry — the rate stands in the rate set of the horizon, which is
// no tree; one leaving the spent positions out; a tree of operations carried from one window into the
// next; a plane forgetting its rates or its operations across a stop; and a plane answering for a tree
// of admitted machines other than the cohort it stands against.

use montana_node::pulse::Cohort;
use montana_node::state::State;
use montana_wallet::{Note, Wallet};
use mt_state::tables::{self, Table};
use mt_state::Layout;

mod common;
use common::{of, payee_of, Scratch};

const WINDOW: u64 = 1_000;

#[test]
fn the_roots_of_state_are_the_tables_the_window_left() {
    let cohort = Cohort::of(&[
        Cohort::half_of(&[0x11u8; 32]),
        Cohort::half_of(&[0x22u8; 32]),
    ])
    .expect("a tree of two");
    let mut state = State::new().with_admitted(cohort.root());

    // The empty plane: every root is the root of its empty table, and the count is the cohort's.
    let empty = state
        .roots(&cohort, WINDOW, &[])
        .expect("the roots of an empty plane");
    assert_eq!(empty.note_root, Table::Notes.empty_root());
    assert_eq!(empty.nullifier_root, Table::Nullifiers.empty_root());
    assert_eq!(empty.record_root, Table::Records.empty_root());
    assert_eq!(empty.machine_root, Table::Machines.empty_root());
    assert_eq!(empty.operations_root, Table::Operations.empty_root());
    assert_eq!(empty.admitted_root, cohort.root().bytes());
    assert_eq!(empty.credited_root, Table::Credited.empty_root());
    assert_eq!(empty.admitted_count, 2);
    let elsewhere = Cohort::of(&[Cohort::half_of(&[0x33u8; 32])]).expect("a tree of one");
    assert!(
        state.roots(&elsewhere, WINDOW, &[]).is_err(),
        "a plane answered for a tree it does not stand against"
    );

    // A real frame: the payer's notes stand in the tree, and it pays against the tree as it stands.
    let payer_at = Scratch::named("roots-payer");
    let payer = Wallet::open(&payer_at.0).expect("a wallet opens");
    let (of_payer, payer_key) = payee_of(0xA1);
    let (of_payee, _) = payee_of(0xB2);
    let inputs = mt_genesis::scalar("spend_inputs").expect("the Decree names it");
    let count = mt_genesis::scalar("spends_per_frame").expect("the Decree names it");
    let taking = (inputs * count) as usize;
    for at in 0..taking {
        let note = Note::of(
            1_000_000_000u128,
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
    let paths: Vec<Vec<mt_proof::poseidon::Digest>> = (0..taking as u64)
        .map(|at| state.path_of(at).expect("a position that was written"))
        .collect();
    let before = state.notes_root();
    let paid = payer
        .pay(
            &of_payee,
            400_000_000u128,
            WINDOW,
            &of(0xE5, 0),
            &of_payer,
            &paths,
            &before,
            &state.credited(),
        )
        .expect("a payment of what the payer holds");
    let frame = mt_state::layout::Frame::parse(&paid.frame).expect("a frame reads back");
    state.apply(&frame, WINDOW).expect("a true frame applies");

    let roots = state
        .roots(&cohort, WINDOW, &[])
        .expect("the roots after the frame");
    assert_eq!(roots.note_root, state.notes_root().bytes());
    assert_ne!(roots.note_root, empty.note_root);
    let spent: Vec<[u8; 32]> = frame
        .spends
        .iter()
        .flat_map(|spend| spend.nullifiers.iter().copied())
        .collect();
    let rates: Vec<[u8; 32]> = frame
        .spends
        .iter()
        .map(|spend| spend.rate_nullifier)
        .collect();
    assert_eq!(
        Some(roots.nullifier_root),
        tables::root_of_set(Table::Nullifiers, &spent),
        "the set of nullifiers is not the positions the frame spent"
    );
    assert_ne!(
        Some(roots.nullifier_root),
        tables::root_of_set(Table::Nullifiers, spent.iter().chain(&rates)),
        "the rate nullifiers entered the set of nullifiers"
    );
    let id = frame.id().expect("the name of the frame");
    assert_eq!(
        Some(roots.operations_root),
        tables::root_of_sequence(Table::Operations, [&id]),
        "the tree of operations is not the frame the window applied"
    );
    assert_eq!(roots.machine_root, Table::Machines.empty_root());
    assert_eq!(roots.record_root, empty.record_root);

    // The tree of operations holds one window: the window after holds nothing yet.
    assert_eq!(
        state
            .roots(&cohort, WINDOW + 1, &[])
            .expect("the roots of the next window")
            .operations_root,
        Table::Operations.empty_root()
    );

    // A plane written and read back answers the same roots, its rates and operations included, and
    // still refuses the rate it already holds.
    let back = State::decode(&state.encode().expect("the plane encodes")).expect("it reads back");
    assert_eq!(
        back.roots(&cohort, WINDOW, &[])
            .expect("the roots read back"),
        roots
    );
    assert!(rates.iter().all(|rate| back.is_spent(rate)));
    assert!(spent.iter().all(|one| back.is_spent(one)));

    // The credit of a window moves no frame's root and moves the root of credited rights by the
    // parts of its cement, in their order; it survives a stop, and a part it took has a branch that
    // walks to that root while a part of no credited cement has none.
    let mut parts = vec![
        mt_derive::nullifier::part(&[0x11u8; 32], WINDOW).expect("a part of the family"),
        mt_derive::nullifier::part(&[0x22u8; 32], WINDOW).expect("a part of the family"),
    ];
    parts.sort_unstable();
    let mut credited = back;
    credited.credit(&parts).expect("a cement the tree holds");
    let after = credited
        .roots(&cohort, WINDOW, &[])
        .expect("the roots after the credit");
    assert_eq!(
        Some(after.credited_root),
        mt_proof::credited::root_of(&parts, mt_proof::tree_depth()).map(|root| root.bytes()),
        "the tree of credited rights is not the parts of the cement in their order"
    );
    assert_eq!(
        (after.note_root, after.nullifier_root, after.operations_root),
        (roots.note_root, roots.nullifier_root, roots.operations_root)
    );
    let (siblings, position) = credited
        .credited_branch(&parts[1])
        .expect("a part the credit took");
    assert_eq!(position, 1);
    let mut walked = mt_proof::credited::leaf(&parts[1]).expect("a part of the family");
    for (level, sibling) in siblings.iter().enumerate() {
        walked = if (position >> level) & 1 == 1 {
            mt_proof::credited::node(sibling, &walked)
        } else {
            mt_proof::credited::node(&walked, sibling)
        };
    }
    assert_eq!(walked.bytes(), after.credited_root);
    let outside = mt_derive::nullifier::part(&[0x11u8; 32], WINDOW + 1).expect("a part");
    assert!(credited.credited_branch(&outside).is_none());
    let kept =
        State::decode(&credited.encode().expect("the plane encodes")).expect("it reads back");
    assert_eq!(kept.credited(), credited.credited());
}
