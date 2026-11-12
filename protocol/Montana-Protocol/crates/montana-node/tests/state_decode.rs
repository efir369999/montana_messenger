use montana_node::state::State;
use mt_proof::{admitted, records};

fn encoded(
    records_in: &[([u8; 32], [u8; 32])],
    spent: &[[u8; 32]],
    rights: &[[u8; 32]],
) -> Vec<u8> {
    let mut bytes = 0u32.to_le_bytes().to_vec();
    bytes.extend_from_slice(&(spent.len() as u32).to_le_bytes());
    for value in spent {
        bytes.extend_from_slice(value);
    }
    bytes.extend_from_slice(&admitted::empty_root().bytes());
    bytes.extend_from_slice(&(records_in.len() as u32).to_le_bytes());
    for (key, leaf) in records_in {
        bytes.extend_from_slice(key);
        bytes.extend_from_slice(leaf);
    }
    bytes.extend_from_slice(&(rights.len() as u32).to_le_bytes());
    for value in rights {
        bytes.extend_from_slice(value);
    }
    bytes.extend_from_slice(&0u64.to_le_bytes());
    bytes.extend_from_slice(&0u64.to_le_bytes());
    // No rate nullifier, no frame applied in window zero, and no window credited.
    bytes.extend_from_slice(&0u32.to_le_bytes());
    bytes.extend_from_slice(&0u64.to_le_bytes());
    bytes.extend_from_slice(&0u32.to_le_bytes());
    bytes.extend_from_slice(&0u32.to_le_bytes());
    bytes
}

#[test]
fn duplicate_record_keys_cannot_silently_replace_a_committed_leaf() {
    let bytes = encoded(
        &[
            ([1; 32], records::leaf(b"first").bytes()),
            ([1; 32], records::leaf(b"second").bytes()),
        ],
        &[],
        &[],
    );
    assert!(State::decode(&bytes).is_err());
}

#[test]
fn record_keys_must_have_the_canonical_stored_order() {
    let leaf = records::leaf(b"held").bytes();
    let bytes = encoded(&[([2; 32], leaf), ([1; 32], leaf)], &[], &[]);
    assert!(State::decode(&bytes).is_err());
}

#[test]
fn spent_sets_cannot_contain_the_same_nullifier_twice() {
    for (spent, rights) in [
        (vec![[3; 32], [3; 32]], vec![]),
        (vec![], vec![[4; 32], [4; 32]]),
    ] {
        let bytes = encoded(&[], &spent, &rights);
        assert!(State::decode(&bytes).is_err());
    }
}

#[test]
fn corrupt_counts_are_refused_before_reserving_their_declared_size() {
    let empty = State::new().encode().unwrap();
    for at in [0, 4, 40, 44, 64, 76, 80] {
        let mut bytes = empty.clone();
        bytes[at..at + 4].copy_from_slice(&u32::MAX.to_le_bytes());
        assert!(State::decode(&bytes).is_err());
    }
}

#[test]
fn canonical_state_keeps_its_exact_encoding_and_rejects_every_truncation() {
    let first = records::leaf(b"first").bytes();
    let second = records::leaf(b"second").bytes();
    let bytes = encoded(
        &[([1; 32], first), ([2; 32], second)],
        &[[3; 32], [4; 32]],
        &[[5; 32], [6; 32]],
    );
    assert_eq!(
        State::decode(&bytes)
            .expect("canonical state")
            .encode()
            .unwrap(),
        bytes
    );
    for end in 0..bytes.len() {
        assert!(State::decode(&bytes[..end]).is_err(), "truncated at {end}");
    }
    let mut extra = bytes;
    extra.push(0);
    assert!(State::decode(&extra).is_err());
}
