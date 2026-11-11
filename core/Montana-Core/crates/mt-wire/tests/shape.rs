// PANIC-OK: a test reports by panicking; an unmet expectation here is the finding being raised.
//
// What an observer of the whole network sees of a cell is its shape, not its content, and shape is
// the surface this file stands over. Three questions are asked of it. Does any byte of a cell stand
// still between two sealings, which would be a mark an observer follows across the network. Does
// the array of seals look like anything but drawn bytes, which would publish how many steps a cell
// has crossed. And does the same body under two different contents leave a different shape, which
// would tell an observer what is being carried by the count of what carries it.

use mt_wire::cell::{Cell, Delivery, Routing};
use mt_wire::{cell, erasure};

const KEY: [u8; 32] = [0x11; 32];
const LABEL: [u8; mt_wire::LABEL_BYTES] = [0x22; mt_wire::LABEL_BYTES];

fn fill(seed: u64, into: &mut [u8]) {
    let mut x = seed | 1;
    for byte in into.iter_mut() {
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        *byte = (x >> 24) as u8;
    }
}

fn a_routing(seed: Option<u64>) -> Routing {
    let mut chunk = vec![0u8; mt_wire::chunk_bytes().expect("the set fixes a chunk")];
    if let Some(s) = seed {
        fill(s, &mut chunk);
    }
    let delivery = Delivery {
        delivery_id: [0x33; mt_wire::SEAL_BYTES],
        block_index: 0,
        block_count: 1,
        chunk,
    };
    let inner = cell::seal_pipe(&[0x44; 32], &delivery).expect("a delivery seals");
    Routing::new([0x55; 32], inner).expect("a routing layer is built")
}

// A byte that never moves is a mark. The label is the exception and is meant to be read: it is the
// point the cell stands at. Every byte after it — the nonce and the sealed body — must move,
// because a cell sealed twice under one key and one nonce would be two readings of one letter.
#[test]
fn beyond_the_label_no_byte_of_a_cell_stands_still_across_sealings() {
    let width = mt_wire::cell_bytes().expect("the set fixes the width of a cell");
    let rounds = 256;
    let mut seen: Vec<Option<u8>> = vec![None; width];
    let mut moved = vec![false; width];

    for _ in 0..rounds {
        let routing = a_routing(None);
        let sealed = cell::seal_cell(&KEY, &LABEL, &routing).expect("a cell seals");
        for (position, byte) in sealed.as_bytes().iter().enumerate() {
            match seen[position] {
                None => seen[position] = Some(*byte),
                Some(first) if first != *byte => moved[position] = true,
                _ => {}
            }
        }
    }

    let still: Vec<usize> = (mt_wire::LABEL_BYTES..width)
        .filter(|p| !moved[*p])
        .collect();
    assert!(
        still.is_empty(),
        "{} byte positions of a cell never moved across {rounds} sealings, the first at {:?}. \
         A position that never moves is a mark an observer follows.",
        still.len(),
        still.first()
    );
}

// The array of seals is what a hop writes its own mark into, and its unused slots must be
// indistinguishable from the used ones. Zeros in the free slots — the natural filling, and the one
// a caller would choose — would publish how many steps a cell has already crossed.
#[test]
fn the_array_of_seals_is_indistinguishable_from_drawn_bytes() {
    let slots = mt_wire::path_max().expect("the set fixes the slots");
    let rounds = 400;
    let mut counts = [0u64; 256];
    let mut ones = 0u64;
    let mut total_bits = 0u64;

    for _ in 0..rounds {
        let routing = a_routing(None);
        assert_eq!(routing.seals.len(), slots, "the array is full");
        for seal in &routing.seals {
            assert!(
                seal.iter().any(|b: &u8| *b != 0),
                "a slot of the array is all zero"
            );
            for byte in seal {
                counts[*byte as usize] += 1;
                ones += u64::from(byte.count_ones());
                total_bits += 8;
            }
        }
    }

    let total: u64 = counts.iter().sum();
    let expected = total as f64 / 256.0;
    let chi: f64 = counts
        .iter()
        .map(|c| {
            let d = *c as f64 - expected;
            d * d / expected
        })
        .sum();
    assert!(
        chi < 500.0,
        "the bytes of the seal array are not uniform: chi-square {chi:.1} over 255 degrees of \
         freedom, where a drawn array stands near 255."
    );

    let fraction = ones as f64 / total_bits as f64;
    assert!(
        (fraction - 0.5).abs() < 0.01,
        "the bits of the seal array are not balanced: {fraction:.4} of them are one."
    );
}

// Two bodies of one length must leave one shape: the same count of blocks, of groups and of cells,
// and every cell of one width. A shape that followed the content would tell an observer what is
// being carried by counting what carries it.
#[test]
fn two_bodies_of_one_length_leave_one_shape() {
    let length = 40_000;
    let zeros = vec![0u8; length];
    let mut drawn = vec![0u8; length];
    fill(0x0BEE_F00D_1234_5678, &mut drawn);

    let shape = |body: &[u8]| {
        let blocks = erasure::cut(body).expect("a body cuts");
        let groups = erasure::groups(&blocks).expect("blocks group");
        let widths: Vec<usize> = groups.iter().flat_map(|g| g.iter().map(Vec::len)).collect();
        (blocks.len(), groups.len(), widths)
    };

    let (zero_blocks, zero_groups, zero_widths) = shape(&zeros);
    let (drawn_blocks, drawn_groups, drawn_widths) = shape(&drawn);
    assert_eq!(
        zero_blocks, drawn_blocks,
        "the count of blocks follows the content"
    );
    assert_eq!(
        zero_groups, drawn_groups,
        "the count of groups follows the content"
    );
    assert_eq!(zero_widths, drawn_widths, "the widths follow the content");
    assert_eq!(
        zero_widths.len(),
        erasure::cells_of(length).expect("the set derives the count"),
        "the count of cells is not the one the set derives from the length alone"
    );
}

// One delivery sealed twice must share nothing after the label: were the sealing deterministic, an
// observer holding two cells would know they carry one letter without opening either.
#[test]
fn one_delivery_sealed_twice_shares_nothing_after_the_label() {
    let first = cell::seal_cell(&KEY, &LABEL, &a_routing(None)).expect("a cell seals");
    let second = cell::seal_cell(&KEY, &LABEL, &a_routing(None)).expect("a cell seals");
    let label = mt_wire::LABEL_BYTES;
    assert_eq!(first.as_bytes()[..label], second.as_bytes()[..label]);
    let shared = first.as_bytes()[label..]
        .iter()
        .zip(second.as_bytes()[label..].iter())
        .filter(|(a, b)| a == b)
        .count();
    let body = first.as_bytes().len() - label;
    assert!(
        (shared as f64) < body as f64 / 100.0,
        "two sealings of one delivery share {shared} of {body} bytes, far above what two \
         independent draws share."
    );
    assert!(Cell::parse(first.as_bytes()).is_ok());
}
