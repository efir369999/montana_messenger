// The horizon of proving: the fold of the standing stride — the aligned run of
// `proving_horizon` windows the set names in `docs/Montana Canon.md`, "The horizon of proving".
// Leaf `i` of stride `E` is the note root of window `E × proving_horizon + i`, ascending; a
// stride is folded once, when its last root cements, and its fold stands as the one public
// input for a whole stride of landings — a value that moved with the window would enter the
// transcript afresh and pin every proof to one landing window. The walk is the append-only walk
// at the width of the reach, under doors of its own — a horizon folded under the note doors is
// a defect the frozen vector catches. Its paths are read by circuits alone; the fold itself is
// native, and carriage is not judgement.

use crate::poseidon::{self, Digest};
use mt_codec::domain;

pub fn leaf(root: &[u8; 32]) -> Option<Digest> {
    Some(poseidon::hash_elements(
        domain::MT_HORIZON_LEAF,
        Digest::of_bytes(root)?.elements(),
    ))
}

pub fn empty_leaf() -> Digest {
    poseidon::hash_elements(domain::MT_HORIZON_LEAF, &[])
}

pub fn node(left: &Digest, right: &Digest) -> Digest {
    poseidon::node(domain::MT_HORIZON_NODE, left, right)
}

// The reach, read from the Decree; the depth of the walk is its binary logarithm and no
// constant of its own. A reach that is not a power of two is no reach at all: the fold below
// is a full tree with no absent levels, and the set derives the width that way.
pub fn reach() -> Option<usize> {
    let width = mt_genesis::scalar("proving_horizon")? as usize;
    width.is_power_of_two().then_some(width)
}

// The root over the roots of a stride, ascending by window: leaf 0 is the stride's first. A
// closed stride fills every leaf; the padding below the reach is the empty leaf, the shape the
// frozen vector exercises and no standing fold takes. A list longer than the reach is no
// horizon and answers nothing, as do bytes that are not a digest of the family.
// The stride standing for a window, by the integer form of the set: the last root of stride E
// is the root of window (E + 1) x proving_horizon - 1, held by everyone proving_lag windows
// after it, and the stride then stands for exactly proving_horizon windows. Before the first
// stride closes no stride stands, the horizon is the fold of the empty reach, and a window
// carries frames of filler alone.
pub fn standing_stride(window: u64) -> Option<u64> {
    let reach = mt_genesis::scalar("proving_horizon")?;
    let lag = mt_genesis::scalar("proving_lag")?;
    let held = window.checked_sub(lag)? + 1;
    (held / reach).checked_sub(1)
}

// The windows whose roots a stride folds: its base and the one past its last.
pub fn stride_span(stride: u64) -> Option<(u64, u64)> {
    let reach = mt_genesis::scalar("proving_horizon")?;
    let base = stride.checked_mul(reach)?;
    Some((base, base.checked_add(reach)?))
}

pub fn root_of(roots: &[[u8; 32]]) -> Option<[u8; 32]> {
    let width = reach()?;
    if roots.len() > width {
        return None;
    }
    let mut level: Vec<Digest> = roots.iter().map(leaf).collect::<Option<Vec<Digest>>>()?;
    level.resize(width, empty_leaf());
    while level.len() > 1 {
        let mut above = Vec::with_capacity(level.len() / 2);
        for pair in level.chunks(2) {
            above.push(node(&pair[0], &pair[1]));
        }
        level = above;
    }
    level.first().map(|root| root.bytes())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn three() -> [[u8; 32]; 3] {
        let mut first = [0u8; 32];
        for (at, byte) in first.iter_mut().enumerate() {
            *byte = at as u8;
        }
        [first, [0x21; 32], [0x22; 32]]
    }

    #[test]
    fn the_reach_is_the_decree_and_a_longer_list_is_no_horizon() {
        let width = reach().expect("the Decree names the reach");
        assert_eq!(width, 128);
        assert!(root_of(&vec![[0x01; 32]; width + 1]).is_none());
        assert!(root_of(&[]).is_some());
    }

    #[test]
    fn the_order_reversed_answers_elsewhere() {
        let leaves = three();
        let straight = root_of(&leaves).expect("the vector folds");
        let reversed = root_of(&[leaves[2], leaves[1], leaves[0]]).expect("the vector folds");
        assert_ne!(straight, reversed);
    }

    #[test]
    fn absent_leaves_dropped_answer_elsewhere() {
        // The named wrong implementation: folding only the present leaves, padded to the next
        // power of two instead of to the reach, walks two levels where the horizon walks seven.
        let leaves = three();
        let straight = root_of(&leaves).expect("the vector folds");
        let mut level: Vec<Digest> = leaves.iter().map(|l| leaf(l).unwrap()).collect();
        level.resize(4, empty_leaf());
        while level.len() > 1 {
            let mut above = Vec::new();
            for pair in level.chunks(2) {
                above.push(node(&pair[0], &pair[1]));
            }
            level = above;
        }
        assert_ne!(straight, level[0].bytes());
    }

    #[test]
    fn the_note_doors_answer_elsewhere() {
        // The named wrong implementation: the same fold under the doors of the note tree.
        let leaves = three();
        let straight = root_of(&leaves).expect("the vector folds");
        let noted = |root: &[u8; 32]| -> Digest {
            poseidon::hash_elements(
                domain::MT_NOTE_LEAF,
                Digest::of_bytes(root).unwrap().elements(),
            )
        };
        let mut level: Vec<Digest> = leaves.iter().map(noted).collect();
        level.resize(128, poseidon::hash_elements(domain::MT_NOTE_LEAF, &[]));
        while level.len() > 1 {
            let mut above = Vec::new();
            for pair in level.chunks(2) {
                above.push(poseidon::node(domain::MT_NOTE_NODE, &pair[0], &pair[1]));
            }
            level = above;
        }
        assert_ne!(straight, level[0].bytes());
    }

    // The arithmetic of the standing stride against the set's own walls: the first window a
    // stride stands at, the last it stands at, and the window before the first stride closes,
    // which no stride stands for. The named wrong implementation: dividing before subtracting
    // the lag anchors a stride one window early, where half the network has not cemented its
    // last root, and the boundary vectors below refuse it.
    #[test]
    fn the_standing_stride_stands_when_the_set_says() {
        assert_eq!(standing_stride(128), None);
        assert_eq!(standing_stride(129), Some(0));
        assert_eq!(standing_stride(256), Some(0));
        assert_eq!(standing_stride(257), Some(1));
        assert_eq!(standing_stride(384), Some(1));
        assert_eq!(standing_stride(385), Some(2));
        assert_eq!(stride_span(0), Some((0, 128)));
        assert_eq!(stride_span(1), Some((128, 256)));
        let early = |window: u64| (window / 128).checked_sub(1);
        assert_eq!(early(128), Some(0), "the named wrong implementation");
        assert_eq!(standing_stride(128), None, "and the set refuses it");
    }

    #[test]
    fn the_frozen_vector_of_the_horizon() {
        let leaves = three();
        let hex =
            |bytes: [u8; 32]| -> String { bytes.iter().map(|b| format!("{b:02x}")).collect() };
        assert_eq!(
            hex(root_of(&leaves).unwrap()),
            "7b163740b7f98eb22eee50fb061f9787a0eb0efe58fe9debe2aff27a864c819c"
        );
        assert_eq!(
            hex(root_of(&[leaves[2], leaves[1], leaves[0]]).unwrap()),
            "32b0bc09f92f93ec8f110a9595c758d8952b34233708e196ff320f56f3060159"
        );
    }
}
