// Issue #15, Protocol-13 item 4: an admission comes of one admissible state. The proof of a
// candidacy walks the claimant's record to a root, and that root is a word of the public input the
// verifier lays from the proposal it holds (`State::apply_candidacy`, `admission::public_of`), never
// from the object: so every sibling of the walk is bound to that one root together with the record.
//
// `admission_audit.rs` refuses a foreign record with the claimant's secret and an unrelated path,
// and `a_record_raises_one_machine.rs` a whole candidacy proven against an earlier tree, of another
// window, or under a right already spent. These two hold the rest of the class the issue names:
//
// - the claimant's own record walked by the path of another record of the very tree the verifier
//   holds -- every sibling genuine, the walk of another position;
// - a path spliced of two states of the tree -- each sibling genuine in some state, the whole of it
//   the path of a tree no proposal ever carried.
//
// Each is refused before any table moves (the whole plane compared byte for byte), the right stays
// unspent, and the honest admission of the same record still applies. Each also shows where the
// refusal lives: the walk proves under the root it answers itself, and only the verifier's own root
// refuses it. The statement does not bind `node_commit` (the open finding F-1 in `admission_audit.rs`).

use montana_node::state::State;
use mt_proof::poseidon::Digest;

mod common;
use common::{a_candidacy_of, a_record_carrying, an_opening_of};

const WINDOW: u64 = 1_000;
// The segment window 1 000 stands in, floor(1 000 / 1 440) = 0: the machine derives it from the
// window (Canon, "The rules of continuity", rule 1; constitution records 297 and 300).
const SEGMENT: u32 = 0;
const MACHINE: [u8; 32] = [0x5A; 32];
const OWN_RIGHT: [u8; 32] = [0x22; 32];

fn opened(state: &mut State, open: u8, record: &[u8]) {
    state
        .apply_opening(&an_opening_of(&[open; 32], record, WINDOW, SEGMENT), WINDOW)
        .expect("a record opens");
}

fn key_of(record: &[u8]) -> [u8; 32] {
    mt_proof::records::leaf(record).bytes()
}

// The level of the claimant's walk whose sibling another record moves: the highest bit at which
// the two keys part. The tree splits on bit 255 at its root and on bit 0 above the leaves
// (`mt_proof::records::path_of_leaves`), so a record joins the claimant's sibling at the first
// split where their keys go apart, walking down from the root, and the walk's siblings are indexed
// by that height.
fn parting(a: &[u8; 32], b: &[u8; 32]) -> usize {
    (0..256usize)
        .rev()
        .find(|&level| (a[level >> 3] ^ b[level >> 3]) >> (level & 7) & 1 == 1)
        .expect("two records of distinct rights stand at distinct keys")
}

// A candidacy of the claimant's own record walked by `siblings`, proven the only way a prover can:
// under the root that walk answers. Against `held`, the root the verifier holds, the same trace
// satisfies nothing and proves nothing. What comes back is the candidacy and the root it answers.
fn walked(
    record: &[u8],
    siblings: &[Digest],
    held: &Digest,
) -> (mt_state::layout::Candidacy, Digest) {
    let (trace, digests) = mt_proof::circuit::admission::trace_of(
        record,
        &key_of(record),
        siblings,
        &MACHINE,
        &OWN_RIGHT,
    )
    .expect("an attacker writes it");
    assert_ne!(
        digests[0], *held,
        "the walk answers the root the verifier holds"
    );
    let statement = mt_proof::circuit::admission::description().expect("the description stands");
    let node_commit =
        mt_derive::node_commit(&[0xA1; mt_codec::size::SIGNING_PUBLIC_KEY], 1, &[0xB2; 32]);
    let public_at = |root: &Digest| {
        mt_proof::circuit::admission::public_of(
            WINDOW,
            root,
            &digests[1],
            &node_commit,
            &digests[2],
            1,
        )
    };
    let at_held = public_at(held);
    assert!(
        !statement.satisfied_by(&trace, &mt_proof::poseidon::limbs_of(&at_held)),
        "the statement accepts the walk under the root the verifier holds"
    );
    assert!(mt_proof::scheme::prove(&statement, &at_held, &trace).is_err());
    let at_own = public_at(&digests[0]);
    let proof = mt_proof::scheme::prove(&statement, &at_own, &trace)
        .expect("the walk proves under the root it answers");
    (
        mt_state::layout::Candidacy {
            window: WINDOW,
            naming_half: digests[1].bytes(),
            node_commit,
            operator_nullifier: digests[2].bytes(),
            suite_id: 1,
            proof,
        },
        digests[0],
    )
}

// Refused against `root`, and nothing of the plane moved: the right unspent, every table the same.
fn refused(state: &mut State, candidacy: &mt_state::layout::Candidacy, root: &Digest, what: &str) {
    let before = state.encode().expect("the plane is written");
    assert!(
        state.apply_candidacy(candidacy, WINDOW, root).is_err(),
        "the node applied {what}"
    );
    assert!(
        !state.is_spent_right(&candidacy.operator_nullifier),
        "a refused candidacy spent the claimant's right: {what}"
    );
    assert_eq!(
        state.encode().expect("the plane is written"),
        before,
        "a refused candidacy moved the plane: {what}"
    );
}

#[test]
fn an_own_record_walked_by_the_path_of_another_record_of_the_tree_is_refused() {
    let mut state = State::new();
    let own = a_record_carrying(&OWN_RIGHT, WINDOW, SEGMENT);
    let other = a_record_carrying(&[0x23; 32], WINDOW, SEGMENT);
    opened(&mut state, 0x44, &own);
    opened(&mut state, 0x45, &other);
    let root = state.records_root();
    let own_path = state
        .path_of_a_record(&key_of(&own))
        .expect("the claimant's record stands in the tree");
    let other_path = state
        .path_of_a_record(&key_of(&other))
        .expect("the other record stands in the tree");
    assert_ne!(own_path, other_path, "two records walk one path");

    let (mixed, _) = walked(&own, &other_path, &root);
    refused(
        &mut state,
        &mixed,
        &root,
        "the claimant's record walked by the path of another record",
    );

    let honest = a_candidacy_of(&state, &own, &MACHINE, &OWN_RIGHT, WINDOW);
    assert_eq!(honest.operator_nullifier, mixed.operator_nullifier);
    state
        .apply_candidacy(&honest, WINDOW, &root)
        .expect("the honest admission of the same record verifies");
    assert!(state.is_spent_right(&honest.operator_nullifier));
}

#[test]
fn a_path_spliced_of_two_states_of_the_tree_is_refused() {
    let own = a_record_carrying(&OWN_RIGHT, WINDOW, SEGMENT);
    let first = a_record_carrying(&[0x23; 32], WINDOW, SEGMENT);
    let at_first = parting(&key_of(&own), &key_of(&first));
    // A second record parting from the claimant's at another level than the first, so the two
    // entries move two different siblings of the claimant's walk.
    let second = (0x24u8..=0xFF)
        .map(|right| a_record_carrying(&[right; 32], WINDOW, SEGMENT))
        .find(|record| parting(&key_of(&own), &key_of(record)) != at_first)
        .expect("a record parting at another level");
    let at_second = parting(&key_of(&own), &key_of(&second));

    let mut state = State::new();
    opened(&mut state, 0x44, &own);
    let early = state.clone();
    opened(&mut state, 0x45, &first);
    let middle = state.clone();
    opened(&mut state, 0x46, &second);
    let roots = [
        early.records_root(),
        middle.records_root(),
        state.records_root(),
    ];
    let key = key_of(&own);
    let path = |held: &State| held.path_of_a_record(&key).expect("the record stands");
    let (before, between, now) = (path(&early), path(&middle), path(&state));
    let moved = |a: &[Digest], b: &[Digest]| -> Vec<usize> {
        (0..a.len())
            .filter(|level| a[*level] != b[*level])
            .collect()
    };
    assert_eq!(moved(&before[..], &between[..]), vec![at_first]);
    assert_eq!(moved(&between[..], &now[..]), vec![at_second]);

    // The sibling the first record put there taken back from the earliest tree, the one the second
    // record put there kept from the tree held now: the path of a tree holding the claimant's record
    // and the second record alone, which no state of this machine ever was.
    let mut spliced = now.clone();
    spliced[at_first] = before[at_first];
    let held = state.records_root();
    let (mixed, answered) = walked(&own, &spliced, &held);
    for root in &roots {
        assert_ne!(
            answered, *root,
            "the spliced path answers a root a state held"
        );
    }
    for root in &roots {
        refused(
            &mut state,
            &mixed,
            root,
            "a path spliced of two states of the tree of records",
        );
    }

    let honest = a_candidacy_of(&state, &own, &MACHINE, &OWN_RIGHT, WINDOW);
    state
        .apply_candidacy(&honest, WINDOW, &held)
        .expect("the honest admission under the tree held now verifies");
    assert!(state.is_spent_right(&honest.operator_nullifier));
}
