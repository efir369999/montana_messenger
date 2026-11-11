use montana_node::attest::{verify_heavy, Standing};
use montana_node::pulse::Cohort;
use mt_codec::domain;
use mt_proof::circuit::{lane, path, presence};
use mt_proof::field::F;
use mt_proof::params::Shape;
use mt_proof::poseidon::{self, Digest, CAPACITY};
use mt_proof::scheme::Proof;

// The observer of the session 37 reproduction, kept as it was written: it receives serialized
// evidence only and reads the lane cells of the opened rows as the spending half. Under the free
// block and the randomizer the rows a query opens are no longer a constant, and what it reads is
// what the oracle below compares against the true half.
fn lane_cells_of_the_opened_rows(bytes: &[u8]) -> Vec<[u8; 32]> {
    let shape = Shape::of_rows_log2(u32::from(presence::PRESENCE_ROWS_LOG2)).unwrap();
    let (proof, _) = Proof::decode(shape, bytes).unwrap();
    let places = lane::Places::after(path::TRACE_WIDTH);
    proof
        .queries
        .iter()
        .map(|query| {
            let mut read = [0u8; 32];
            for cell in 0..CAPACITY {
                let value = query.row[places.cell(cell)];
                read[cell * 8..cell * 8 + 8].copy_from_slice(&value.as_u64().to_le_bytes());
            }
            read
        })
        .collect()
}

fn predict_part(spending: &[u8; 32], window: u64) -> [u8; 32] {
    let digest = Digest::of_bytes(spending).unwrap();
    let mut preimage = digest.elements().to_vec();
    preimage.push(F::try_from_u64(window).unwrap());
    poseidon::hash_elements(domain::MT_PART_NF, &preimage).bytes()
}

fn predict_credit(spending: &[u8; 32], window: u64) -> [u8; 32] {
    let digest = Digest::of_bytes(spending).unwrap();
    let mut preimage = digest.elements().to_vec();
    preimage.push(F::try_from_u64(window).unwrap());
    poseidon::hash_elements_twice(domain::MT_CREDIT_NF, &preimage)
        .0
        .bytes()
}

// The disclosure of session 37, run again against the hiding construction: a verified presence
// opens rows that are uniform over the free block, so no opened row reads as the spending half,
// no two opened rows agree, and the nullifiers an observer predicts from any of them are not the
// machine's. Two proofs of one presence differ in every opened row as well.
#[test]
fn a_verified_presence_discloses_nothing_of_the_spending_half() {
    let secret = [0x73u8; 32];
    let window = 1_000;
    let cohort = Cohort::of(&[Cohort::half_of(&secret)]).unwrap();
    let branch = cohort.branch_of(&secret).unwrap();
    let standing =
        Standing::of_the_window(&secret, window, &branch.siblings, branch.position).unwrap();
    let confirmation = standing.heavy(&secret, [0x11; 32], [0x22; 32]).unwrap();
    verify_heavy(
        &confirmation,
        &cohort.root(),
        &[0x33; 32],
        0,
        0,
        &mt_pulse::U256::from_be_bytes(&[0xff; 32]),
    )
    .unwrap();

    let spending = mt_derive::nullifier::machine_halves(&secret).0;
    let read = lane_cells_of_the_opened_rows(&confirmation.proof);
    assert_eq!(read.len(), mt_proof::params::QUERIES);
    let mut distinct = read.clone();
    distinct.sort_unstable();
    distinct.dedup();
    assert_eq!(
        distinct.len(),
        read.len(),
        "two opened rows of a lane agree"
    );
    for row in &read {
        assert_ne!(*row, spending, "an opened row reads as the spending half");
        for height in [0, window - 1, window, window + 1, window + 10_000] {
            if let Some(digest) = Digest::of_bytes(row) {
                let _ = digest;
                assert_ne!(
                    predict_part(row, height),
                    mt_derive::nullifier::part(&secret, height).unwrap()
                );
                assert_ne!(
                    predict_credit(row, height),
                    mt_derive::nullifier::credit(&secret, height).unwrap()
                );
            }
        }
    }
    // And a second proof of the same presence opens other rows: nothing a verifier reads is a
    // function of the witness alone.
    let again =
        Standing::of_the_window(&secret, window, &branch.siblings, branch.position).unwrap();
    assert_ne!(again.presence, standing.presence);
    assert_ne!(lane_cells_of_the_opened_rows(&again.presence), read);
}
