// The proof machinery of Montana: the field and its extension, the canonical description of a
// constraint set with its encoder and decoder, and — as the stage fills — the commitments, the
// transcript, the folding and the six checks of the verifier.
//
// Every quantity here is the set's. What this crate adds is arithmetic and bytes; what it decides
// is nothing.

#![forbid(unsafe_code)]
#![deny(clippy::all)]

// The depth every append-only construction of this protocol takes, read at one door and nowhere
// else. A row the Decree does not hold, or a depth of zero, is answered by refusal and never by a
// default: a tree of depth zero is its own empty leaf rather than a root over the levels the
// Decree names, and a circuit of depth zero carries no walk at all — so a silent zero would be a
// genesis root nobody computed and a membership nobody proved, both of them green.
//
// The three places of this crate that read the row, and the one place of the crate of the state,
// go through here. That the class was closed for the divisors of the Decree and not swept to the
// depths is what left the zero standing.
//
// PANIC-OK: the Decree is a static of this tree and the gate refuses a build in which the set and
// it disagree, so a missing or degenerate row is a tree that is not this protocol rather than an
// input a stranger can send.
pub fn tree_depth() -> usize {
    let depth = mt_genesis::scalar("note_tree_depth").expect("the Decree names note_tree_depth");
    assert!(
        depth > 0,
        "a construction of depth zero is no construction of this protocol"
    );
    usize::try_from(depth).expect("a depth beyond this machine")
}

pub mod admitted;
pub mod air;
pub mod circuit;
pub mod commit;
pub mod ext;
pub mod fabric;
pub mod field;
pub mod horizon;
pub mod notes;
pub mod params;
pub mod poly;
pub mod poseidon;
pub mod records;
pub mod scheme;
pub mod transcript;
