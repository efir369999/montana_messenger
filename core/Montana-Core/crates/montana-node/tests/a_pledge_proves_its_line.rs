// A pledge carries the line of its slot at the abscissa of its name and a proof that binds that
// value to its machine's part, and the door counts it only where that proof verifies against the
// public input the door computes from the pledge itself. Canon, "The pledge of a part" and its
// invariants: "A pledge whose proof does not verify under the description of the pledge against its
// public input is refused: it enters no quorum and is no evidence"; `line_value` bytes "that are not
// one are refused before the proof is verified". Plan of #89, steps 3-5; and two pledges of one slot
// on two names give the lock-opening value.
//
// **The world outside the rules, arranged by this test.** Two machines and a cohort of both, in one
// window. Each signs under the one-time key of its own part; where the test moves a field of a
// pledge it signs the moved pledge again under that same key, so that the signature stands and only
// the proof is left to refuse it.
//
// **The wrong implementations it refuses**, named before the assertions: the door of d6ff61f, which
// checked the key and the signature and never the proof -- there a pledge carrying any line value,
// or the proof of another part, is counted; and the pledge of d6ff61f, which carried zeros for the
// value and the proof -- there an honest pledge fails the door this test asks it to pass.

use montana_node::attest::{verify_pledge, Standing};
use montana_node::pulse::Cohort;
use montana_node::NodeError;
use mt_proof::line::L;
use mt_state::layout::Pledge;
use mt_state::Layout;

const WINDOW: u64 = 5;
const ATTEMPT: u32 = 1;
const NAME: [u8; 32] = [0x31; 32];
const OTHER: [u8; 32] = [0x47; 32];
const FIRST: [u8; 32] = [0x11; 32];
const SECOND: [u8; 32] = [0x22; 32];

const PROOF: &str = "a pledge whose proof does not verify";

fn standing(cohort: &Cohort, secret: &[u8; 32]) -> Standing {
    let branch = cohort.branch_of(secret).expect("its own leaf");
    Standing::of_the_window(secret, WINDOW, &branch.siblings, branch.position)
        .expect("a machine of the tree proves its presence")
}

// The point a pledge publishes: the abscissa of its name and the value of its line there.
fn point(held: &Pledge) -> (L, L) {
    (
        mt_proof::line::abscissa(&held.name).expect("an abscissa"),
        L::from_bytes(&held.line_value).expect("a value of the field of the line"),
    )
}

// The pledge signed again under the one-time key of the part of `secret` in this window.
fn resigned(secret: &[u8; 32], mut held: Pledge) -> Pledge {
    let seed = mt_derive::pulse::part_key_seed(secret, WINDOW);
    let mut bytes = [0u8; mt_suite::sign::SEED_BYTES];
    bytes.copy_from_slice(&seed[..mt_suite::sign::SEED_BYTES]);
    let (_, key) = mt_suite::sign::keypair_from_seed(&bytes);
    let scope = held.signed_scope().expect("the scope of a pledge");
    held.signature = mt_suite::sign::sign(&key, &scope)
        .expect("a signature")
        .as_bytes()
        .to_vec();
    held
}

#[test]
fn a_pledge_counts_only_where_its_proof_binds_its_line_to_its_part() {
    let cohort =
        Cohort::of(&[Cohort::half_of(&FIRST), Cohort::half_of(&SECOND)]).expect("a cohort of two");
    let first = standing(&cohort, &FIRST);
    let second = standing(&cohort, &SECOND);
    let key = first.key.as_bytes().to_vec();

    // The honest pledge: its value, its proof and its signature, all of its own part.
    let honest = first
        .pledge(&FIRST, ATTEMPT, NAME, ATTEMPT)
        .expect("a pledge stands");
    assert_ne!(honest.line_value, [0u8; 32], "a pledge carries its line");
    assert_eq!(honest.proof.len(), mt_state::PRESENCE_PROOF_LEN);
    assert_eq!(verify_pledge(&honest, &key), Ok(()));

    // The value of another point of the same line, signed again: a canonical element, a good
    // signature, and a proof that does not hold it.
    let elsewhere = first
        .pledge(&FIRST, ATTEMPT, OTHER, ATTEMPT)
        .expect("a pledge stands");
    assert_ne!(elsewhere.line_value, honest.line_value);

    // The two pledges of one slot on two names are two points of one line, and the line at abscissa
    // zero is the machine's lock-opening value, which neither pledge discloses alone: the evidence
    // the forfeit of a node lock reads (Canon, "The forfeit of a node lock, and the evidence that
    // moves it"; the #61 relation).
    let spending = mt_proof::poseidon::hash_bytes_twice(mt_codec::domain::MT_KEY_HALVES, &FIRST).0;
    assert_eq!(
        mt_proof::line::opening_of(point(&honest), point(&elsewhere)),
        Some(mt_proof::line::opening(&spending))
    );
    let moved = resigned(
        &FIRST,
        Pledge {
            line_value: elsewhere.line_value,
            ..honest.clone()
        },
    );
    assert_eq!(
        verify_pledge(&moved, &key),
        Err(NodeError::Refused { what: PROOF })
    );

    // Another name under the honest value and proof, signed again: the abscissa moved.
    let renamed = resigned(
        &FIRST,
        Pledge {
            name: OTHER,
            ..honest.clone()
        },
    );
    assert_eq!(
        verify_pledge(&renamed, &key),
        Err(NodeError::Refused { what: PROOF })
    );

    // The proof and the value of the other machine's pledge of the same slot and name, carried
    // under this part and signed again: the nullifier of the part is no longer the proof's.
    let theirs = second
        .pledge(&SECOND, ATTEMPT, NAME, ATTEMPT)
        .expect("a pledge stands");
    let lifted = resigned(
        &FIRST,
        Pledge {
            line_value: theirs.line_value,
            proof: theirs.proof.clone(),
            ..honest.clone()
        },
    );
    assert_eq!(
        verify_pledge(&lifted, &key),
        Err(NodeError::Refused { what: PROOF })
    );

    // A value that is no element of the field of the line: refused before any proof is read.
    let spelled = Pledge {
        line_value: [0xFF; 32],
        ..honest.clone()
    };
    assert!(verify_pledge(&spelled, &key).is_err());

    // A pledge of another part's secret is not this window's standing to make.
    assert!(first.pledge(&SECOND, ATTEMPT, NAME, ATTEMPT).is_err());
}
