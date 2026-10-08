// The closing condition of the eleventh stage, run at the shape the Decree names rather than at a
// shape a test chose: a real frame — three spends, six redemptions against one root, at the depth
// of the tree of notes — proven, verified, and measured.
//
// It stands apart from the tests of the crate because it costs minutes rather than seconds, and
// because what it answers is not a rule of a gadget but the one question the stage closes on:
// whether the machine that writes a frame fits the device the parameters were derived for.

use mt_codec::domain;
use mt_proof::circuit::frame::{self, Consumed, Created, Frame, Places, Rate, Spend};
use mt_proof::circuit::redemption::{Held, HeldRight};
use mt_proof::notes;
use mt_proof::params::{Shape, BLOWUP, TRACE_WIDTH_BOUND};
use mt_proof::poseidon::{self, Digest};

const ROWS_LOG2: u8 = 16;

fn depth() -> usize {
    mt_genesis::scalar("note_tree_depth").expect("the Decree names the depth of the tree") as usize
}

fn tree(commitments: &[Digest], depth: usize) -> (Digest, Vec<Vec<Digest>>) {
    let empties = notes::empty_internals(depth);
    let mut level: Vec<Digest> = commitments.iter().map(notes::leaf_of).collect();
    let mut paths: Vec<Vec<Digest>> = vec![Vec::new(); commitments.len()];
    let mut index: Vec<usize> = (0..commitments.len()).collect();
    for empty in empties.iter().take(depth) {
        for (which, path) in paths.iter_mut().enumerate() {
            let sibling = index[which] ^ 1;
            path.push(level.get(sibling).copied().unwrap_or(*empty));
        }
        let mut above = Vec::new();
        let mut which = 0;
        while which < level.len() {
            let left = level[which];
            let right = level.get(which + 1).copied().unwrap_or(*empty);
            above.push(notes::node(&left, &right));
            which += 2;
        }
        level = above;
        for at in index.iter_mut() {
            *at >>= 1;
        }
    }
    (level[0], paths)
}

fn commitment_of(held: &Held) -> Digest {
    let half = poseidon::hash_bytes_twice(domain::MT_KEY_HALVES, &held.nf_key).1;
    let mut elements = Vec::new();
    elements.extend_from_slice(half.elements());
    elements.extend_from_slice(&poseidon::limbs_of(&held.value.to_le_bytes()));
    elements.extend_from_slice(&poseidon::limbs_of(&held.note_pk));
    elements.extend_from_slice(&poseidon::limbs_of(&held.rcm));
    poseidon::hash_elements(domain::MT_NOTE_CM, &elements)
}

fn admitted_of_one(machine_secret: &[u8; 32]) -> (Digest, Vec<Digest>) {
    let naming = poseidon::hash_bytes_twice(domain::MT_KEY_HALVES, machine_secret).1;
    let leaf = mt_proof::admitted::leaf_of(&naming);
    let empties = mt_proof::admitted::empty_internals(depth());
    let mut current = leaf;
    let mut siblings = Vec::new();
    for empty in empties.iter().take(depth()) {
        siblings.push(*empty);
        current = mt_proof::admitted::node(&current, empty);
    }
    (current, siblings)
}

fn a_real_frame() -> (Frame, Places, Digest, Digest) {
    let places = Places::of(depth()).expect("the Decree names the shape of a frame");
    let amounts: [[u128; 4]; 3] = [
        [5_000_000_000, 3_000_000_000, 6_000_000_000, 2_000_000_000],
        [13_000_000_000, 1, 1, 13_000_000_000],
        [1 << 40, 1 << 20, 1 << 20, 1 << 40],
    ];
    let mut consumed = Vec::new();
    for (spend, values) in amounts.iter().enumerate() {
        for (at, value) in values.iter().take(2).enumerate() {
            let which = spend * 2 + at;
            consumed.push(Held {
                nf_key: [0x30 + which as u8; 32],
                value: *value,
                note_pk: [0x20 + which as u8; 32],
                rcm: [0x80 + which as u8; 32],
                siblings: Vec::new(),
                // Positions with bits at both ends, so a walk that reads them from the wrong end
                // reaches another root: the leaves stand where the tree puts them.
                position: (which as u64) * 3 + 1,
            });
        }
    }
    let commitments: Vec<Digest> = consumed.iter().map(commitment_of).collect();
    // The tree holds the notes at the positions they were given, and the paths follow.
    let mut leaves: Vec<Digest> = Vec::new();
    let highest = consumed.iter().map(|h| h.position).max().unwrap_or(0) as usize;
    for at in 0..=highest {
        match consumed.iter().position(|h| h.position as usize == at) {
            Some(which) => leaves.push(commitments[which]),
            None => leaves.push(poseidon::hash_bytes(domain::MT_NOTE_CM, &[0xEE; 32])),
        }
    }
    let (root, paths) = tree(&leaves, depth());
    for held in consumed.iter_mut() {
        held.siblings = paths[held.position as usize].clone();
    }
    // The first redemption of the frame consumes a right: the machine's membership in the tree
    // of admitted machines, its share riding the cells an amount rides in, its moment computed.
    let machine_secret = [0x77u8; 32];
    let (admitted_root, admitted_siblings) = admitted_of_one(&machine_secret);
    let due = 1000u64;
    let window = mt_derive::nullifier::claim_window(&machine_secret, due)
        .expect("the Decree names the spread");
    let spends: Vec<Spend> = (0..3)
        .map(|spend| Spend {
            consumed: consumed[spend * 2..spend * 2 + 2]
                .iter()
                .cloned()
                .map(Consumed::Note)
                .collect(),
            created: (0..2)
                .map(|at| {
                    let which = spend * 2 + at;
                    Created {
                        half: poseidon::hash_bytes_twice(
                            domain::MT_KEY_HALVES,
                            &[0x50 + which as u8; 32],
                        )
                        .1
                        .bytes(),
                        value: amounts[spend][2 + at],
                        note_pk: [0x60 + which as u8; 32],
                        rcm: [0x90 + which as u8; 32],
                    }
                })
                .collect(),
            rate: Rate {
                secret: [0x55; 32],
                index: spend as u8,
            },
        })
        .collect();
    let mut spends = spends;
    spends[0].consumed[0] = Consumed::Right(HeldRight {
        machine_secret,
        window: due,
        value: amounts[0][0],
        siblings: admitted_siblings,
        position: 0,
    });
    (Frame { spends, window }, places, root, admitted_root)
}

// A machine that holds one right and nothing else. Five of its six positions have nothing to put
// in them, and the set says what goes there: filler, drawn by its emitter from its own randomness.
// This is the first value in the network — before it, no note exists to be redeemed — and it is
// what the named wrong implementation cannot build: a circuit knowing only a note and a right
// leaves that machine unable to compose a frame at all, so nothing minted ever becomes spendable.
fn a_first_frame() -> (Frame, Places, Digest, Digest) {
    let places = Places::of(depth()).expect("the Decree names the shape of a frame");
    let machine_secret = [0x77u8; 32];
    let (admitted_root, admitted_siblings) = admitted_of_one(&machine_secret);
    let due = 1000u64;
    let window = mt_derive::nullifier::claim_window(&machine_secret, due)
        .expect("the Decree names the spread");
    let share = 13_000_000_000u128;
    let mut spends: Vec<Spend> = (0..3)
        .map(|spend| Spend {
            consumed: (0..2)
                .map(|at| Consumed::filler(&[0xC1u8; 32], spend * 2 + at, depth()))
                .collect(),
            created: (0..2)
                .map(|at| Created {
                    half: poseidon::hash_bytes_twice(
                        domain::MT_KEY_HALVES,
                        &[0x50 + (spend * 2 + at) as u8; 32],
                    )
                    .1
                    .bytes(),
                    // Only the first spend pays out: it carries the whole share, the rest create
                    // nothing, and the shape says nothing about which did which.
                    value: if spend == 0 && at == 0 { share } else { 0 },
                    note_pk: [0x60 + (spend * 2 + at) as u8; 32],
                    rcm: [0x90 + (spend * 2 + at) as u8; 32],
                })
                .collect(),
            rate: Rate {
                secret: [0x55; 32],
                index: spend as u8,
            },
        })
        .collect();
    spends[0].consumed[0] = Consumed::Right(HeldRight {
        machine_secret,
        window: due,
        value: share,
        siblings: admitted_siblings,
        position: 0,
    });
    // The root of the tree of notes as it stands when nothing has been witnessed yet: the first
    // frame of the network proves against the empty tree, and its filler answers to no root at all.
    (
        Frame { spends, window },
        places,
        notes::empty_root(),
        admitted_root,
    )
}

#[test]
fn the_first_value_of_the_network_is_a_right_redeemed_beside_filler() {
    let (frame, places, root, admitted_root) = a_first_frame();
    let held = frame::description(&places, ROWS_LOG2).expect("a lawful height");
    let (trace, _) = frame::trace_of(&places, &frame, &admitted_root, ROWS_LOG2)
        .expect("a machine holding one right writes a frame");
    let public = frame::public_of(&frame, &places, &root, &admitted_root).expect("a public input");
    assert!(
        held.satisfied_by(&trace, &poseidon::limbs_of(&public)),
        "a frame of one right and filler does not satisfy its own description"
    );
    let bytes = mt_proof::scheme::prove(&held, &public, &trace).expect("a true frame proves");
    assert_eq!(mt_proof::scheme::verify(&held, &public, &bytes), Ok(()));
}

#[test]
fn a_real_frame_is_proven_verified_and_measured() {
    let (frame, places, root, admitted_root) = a_real_frame();
    assert_eq!(places.blocks(), 330, "the blocks the set counts");
    let rows = 1usize << ROWS_LOG2;
    assert!(
        places.blocks() * mt_proof::circuit::permutation::period() <= rows,
        "the frame stands inside the height the set derives"
    );

    let held = frame::description(&places, ROWS_LOG2).expect("a lawful height");
    held.check()
        .expect("the description stands inside the shape");
    assert!(
        usize::from(held.trace_width) <= TRACE_WIDTH_BOUND,
        "the width stands inside the bound the memory of a telephone fixes"
    );

    let (trace, reached) =
        frame::trace_of(&places, &frame, &admitted_root, ROWS_LOG2).expect("a written frame");
    assert_eq!(
        reached, root,
        "every note proves against one root, and the right against the tree of machines"
    );
    let public = frame::public_of(&frame, &places, &root, &admitted_root).expect("a public input");
    let bytes = mt_proof::scheme::prove(&held, &public, &trace).expect("a true frame proves");
    assert_eq!(mt_proof::scheme::verify(&held, &public, &bytes), Ok(()));

    // The length of a proof is the one the set derives, and it is the one the state layer carries.
    let shape = Shape::of_rows_log2(u32::from(ROWS_LOG2)).expect("a lawful height");
    assert_eq!(bytes.len(), shape.proof_bytes());
    assert_eq!(bytes.len(), mt_state::PROOF_LEN);

    // A frame published with one nullifier moved is not this proof's frame.
    let mut other = public.clone();
    other[0] ^= 1;
    assert!(mt_proof::scheme::verify(&held, &other, &bytes).is_err());

    // What the proving of it costs, held at once, at the height and width it actually occupies.
    let element = 8usize;
    let domain = rows * BLOWUP;
    let extended = usize::from(held.trace_width) * domain * element;
    let composition = domain * 3 * element;
    let trees = domain * 32 * 2;
    let folding: usize = (1..=shape.layers())
        .map(|layer| (domain >> (2 * layer)) * 3 * element)
        .sum();
    let whole = extended + composition + trees + folding;
    println!(
        "the frame at 2^{ROWS_LOG2}: width {}, blocks {}, proof {} B",
        held.trace_width,
        places.blocks(),
        bytes.len()
    );
    println!(
        "proving it holds {} MiB at once — extended trace {} MiB, composition {} MiB, trees {} MiB, folding {} MiB",
        whole / (1024 * 1024),
        extended / (1024 * 1024),
        composition / (1024 * 1024),
        trees / (1024 * 1024),
        folding / (1024 * 1024)
    );
    // The budget the parameters were derived from: under half a gigabyte held whole.
    assert!(
        whole < 512 * 1024 * 1024,
        "the proving of a frame stands inside the budget its parameters were derived from"
    );
}
