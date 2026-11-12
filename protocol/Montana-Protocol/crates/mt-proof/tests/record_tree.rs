use mt_proof::poseidon::Digest;
use mt_proof::records;
use std::collections::BTreeMap;

fn reference(entries: &[([u8; 32], Digest)], height: usize, empty: &[Digest]) -> Digest {
    if entries.is_empty() {
        return empty[height];
    }
    if height == 0 {
        assert_eq!(entries.len(), 1);
        return entries[0].1;
    }
    let bit = height - 1;
    let (left, right): (Vec<_>, Vec<_>) = entries
        .iter()
        .copied()
        .partition(|(key, _)| (key[bit / 8] >> (bit % 8)) & 1 == 0);
    records::node(
        &reference(&left, bit, empty),
        &reference(&right, bit, empty),
    )
}

fn interleaved() -> BTreeMap<[u8; 32], Digest> {
    let mut out = BTreeMap::new();
    for (at, bytes) in [[1, 0], [1, 1], [2, 0]].into_iter().enumerate() {
        let mut key = [0u8; 32];
        key[..2].copy_from_slice(&bytes);
        out.insert(key, records::leaf(&[at as u8 + 1]));
    }
    out
}

#[test]
fn byte_order_cannot_change_the_sparse_merkle_root() {
    let leaves = interleaved();
    let entries: Vec<_> = leaves.iter().map(|(key, value)| (*key, *value)).collect();
    let expected = reference(
        &entries,
        records::key_bits(),
        &records::empty_internals(records::key_bits()),
    );
    assert_eq!(records::root_of_leaves(&leaves), expected);
}

#[test]
fn every_record_path_reaches_the_root_with_interleaved_keys() {
    let leaves = interleaved();
    let root = records::root_of_leaves(&leaves);
    for (key, leaf) in &leaves {
        let mut held = *leaf;
        for (bit, sibling) in records::path_of_leaves(&leaves, key)
            .expect("a held record has a path")
            .iter()
            .enumerate()
        {
            held = if (key[bit / 8] >> (bit % 8)) & 1 == 0 {
                records::node(&held, sibling)
            } else {
                records::node(sibling, &held)
            };
        }
        assert_eq!(held, root);
    }
}

#[test]
fn paths_span_every_key_byte_and_share_one_root() {
    let mut leaves = BTreeMap::new();
    leaves.insert([0u8; 32], records::leaf(&[0]));
    for (at, bit) in [0usize, 7, 8, 15, 63, 127, 254, 255]
        .into_iter()
        .enumerate()
    {
        let mut key = [0u8; 32];
        key[bit / 8] = 1 << (bit % 8);
        leaves.insert(key, records::leaf(&[at as u8 + 1]));
    }
    leaves.insert([0xff; 32], records::leaf(&[0xfe]));
    let empty = records::empty_internals(records::key_bits());
    let entries: Vec<_> = leaves.iter().map(|(key, value)| (*key, *value)).collect();
    let root = records::root_of_leaves(&leaves);
    assert_eq!(root, reference(&entries, records::key_bits(), &empty));
    for (key, leaf) in &leaves {
        let path = records::path_of_leaves(&leaves, key).expect("a held key");
        assert_eq!(path.len(), records::key_bits());
        let mut held = *leaf;
        for (bit, sibling) in path.iter().enumerate() {
            held = if (key[bit / 8] >> (bit % 8)) & 1 == 0 {
                records::node(&held, sibling)
            } else {
                records::node(sibling, &held)
            };
        }
        assert_eq!(held, root);
    }
    assert!(records::path_of_leaves(&leaves, &[0x55; 32]).is_none());
    assert_eq!(
        records::root_of_leaves(&BTreeMap::new()),
        empty[records::key_bits()]
    );
}
