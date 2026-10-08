// The parameters of the proof scheme, and the lengths that follow from them. Not one of these is
// chosen here: each is a row of the set, and what this module adds is the arithmetic the set
// writes beside them — the count of folding layers, the bytes of a query, and the length of a
// proof, which the set derives and this reproduces rather than restates.

use crate::ext::ELEMENT_BYTES;

mt_codec::constants! {
    PARAMETERS:
    /// The level SHA-256 leaves standing after Grover, and the level the whole stack is fixed at.
    pub const SECURITY_BITS: u32 = 128, writes "| `proof_security_bits` | 128 |";
    /// The rate at which the trace is extended.
    pub const BLOWUP: usize = 8, writes "| `proof_blowup` | 8 |";
    /// At this blowup each query rejects a false proof with probability seven in eight, and this
    /// many of them leave a forgery below the target.
    pub const QUERIES: usize = 48, writes "| `proof_queries` | 48 |";
    /// Folding divides the degree bound by this at every step.
    pub const FOLD: usize = 4, writes "| `proof_fold` | 4 |";
    /// Folding stops when the bound reaches this, and the tail travels nowhere.
    pub const TAIL_DEGREE: usize = 64, writes "| `proof_tail_degree` | 64 |";
    /// The slot beside the roots: every column at the out-of-domain point, every column at the
    /// point one row on, and the composition there — sized to the bound on the width rather than
    /// to a width, so the length of a proof says nothing about the circuit that wrote it.
    pub const OOD_VALUES: usize = 125, writes "| `proof_ood_values` | 125 |";
    /// What one permutation of the proof hash costs in rows of a trace. It is measured rather than
    /// assumed: the layout of the gadget that asserts the permutation stands beside it as the
    /// witness, and the count closes on a power of two of its own accord.
    pub const ROWS_PER_PERMUTATION: usize = 128, writes "| `rows_per_permutation` | 128 |";
    /// The bound on the width of a trace, which the memory of a telephone fixes and the slot of
    /// the out-of-domain evaluations covers. A query opens a row of this width whatever the
    /// circuit is, so a narrower trace pays the difference in padding and not in disclosure.
    pub const TRACE_WIDTH_BOUND: usize = 62, writes "| `proof_trace_width_bound` | 62 |";
    /// The degree a constraint may carry. The composition of a constraint of degree d carries
    /// degree about (d - 1) times the rows; the folding divides by the fold at every layer and the
    /// count of layers is what carries the rows down to the tail, so it carries the composition
    /// down to the tail times (d - 1). A tail of its own count of coefficients therefore admits
    /// two, at every height, since the rows cancel.
    pub const DEGREE_BOUND: u8 = 2, writes "admits `d ≤ 2`";
    /// A root of a tree of a proof, of the width of a hash output.
    pub const ROOT_BYTES: usize = 32, writes "| the commitment to the execution trace | 32 B |";
    /// The height every description the network accepts proofs under is built at. A proof is bytes
    /// of one length whatever is proven, and the length follows from the height — so a description
    /// built at another height yields a proof no object of this protocol has room for, and an
    /// identifier frozen over such a description binds a circuit the network never runs. The
    /// tallest circuit fixes it: the frame stands at this height by counting, and the rest stand
    /// here with it rather than each at the height its own blocks happen to fill.
    pub const ROWS_LOG2: u8 = 16, code "the height every description the network accepts proofs under is built at, which the length of a proof follows from";
}

#[derive(Debug, PartialEq, Eq)]
pub enum ShapeError {
    RowsDoNotReachTheTail { rows_log2: u32 },
}

// The shape of a proof over a trace of a stated height. Everything below follows from the
// parameters above and from this one number; nothing of it is a value of its own.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Shape {
    rows_log2: u32,
}

impl Shape {
    // The folding divides the degree bound at every step and stops at the tail, so a height the
    // steps cannot reach the tail from is refused rather than rounded to one they can. A height
    // that stands **at** the tail is refused with them and for a reason of the same kind: it folds
    // no layer at all, and every check of a proof past the first reads the layer the folding did
    // not make. A shape of no layers would carry a proof whose deep composition answers against
    // nothing, so it is refused where a shape becomes a shape.
    pub fn of_rows_log2(rows_log2: u32) -> Result<Shape, ShapeError> {
        let tail_log2 = TAIL_DEGREE.trailing_zeros();
        let fold_log2 = FOLD.trailing_zeros();
        if rows_log2 <= tail_log2 || !(rows_log2 - tail_log2).is_multiple_of(fold_log2) {
            return Err(ShapeError::RowsDoNotReachTheTail { rows_log2 });
        }
        Ok(Shape { rows_log2 })
    }

    pub fn rows_log2(self) -> u32 {
        self.rows_log2
    }

    pub fn rows(self) -> usize {
        1usize << self.rows_log2
    }

    pub fn domain_log2(self) -> u32 {
        self.rows_log2 + BLOWUP.trailing_zeros()
    }

    pub fn domain(self) -> usize {
        1usize << self.domain_log2()
    }

    // The count of folding layers, which follows from the tail and is not chosen.
    pub fn layers(self) -> usize {
        ((self.rows_log2 - TAIL_DEGREE.trailing_zeros()) / FOLD.trailing_zeros()) as usize
    }

    // The levels the folding layers open: a layer commits the values it folds as one leaf, so it
    // has a quarter of the leaves it has values, and the levels fall by two from one layer to the
    // next.
    pub fn levels_of_a_query(self) -> usize {
        (0..self.layers())
            .map(|i| (self.domain_log2() as usize) - 2 - 2 * i)
            .sum()
    }

    // The bytes of one query: the path of the trace and the row it opens, the path of the
    // composition and the value it opens, and for every folding layer its path and the values it
    // folds. The row is of the bound on the width whatever the circuit is.
    pub fn query_bytes(self) -> usize {
        ROOT_BYTES * (self.domain_log2() as usize)
            + TRACE_WIDTH_BOUND * 8
            + ROOT_BYTES * (self.domain_log2() as usize)
            + ELEMENT_BYTES
            + ROOT_BYTES * self.levels_of_a_query()
            + self.layers() * FOLD * ELEMENT_BYTES
    }

    // The length of a proof: the two roots, one root per folding layer, the evaluations out of the
    // domain, the coefficients of the tail, and one block per query.
    pub fn proof_bytes(self) -> usize {
        ROOT_BYTES * 2
            + ROOT_BYTES * self.layers()
            + OOD_VALUES * ELEMENT_BYTES
            + TAIL_DEGREE * ELEMENT_BYTES
            + QUERIES * self.query_bytes()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Canon derives the shape of a frame's proof from these parameters and from the count of
    // compressions its circuit holds. Reproducing that arithmetic is what says the parameters are
    // read rather than remembered — and every number below is the set's own.
    #[test]
    fn the_shape_of_a_frame_is_the_one_the_set_derives() {
        let depth = mt_genesis::scalar("note_tree_depth").expect("the Decree names it") as usize;
        // Every hash of the circuit is of the proof hash family. A redemption walks its path —
        // one node per level and the two permutations of its leaf — opens its commitment and the
        // public half of its nullifier key, and derives its nullifier; the counts of the openings
        // are the sponge's own: limbs of the preimage, the pad element, blocks of the rate.
        // An absorption counts in elements: four-byte limbs for a byte field, the four words
        // of a digest where a derivation consumes another, one pad element, blocks of the rate.
        let blocks = |elements: usize| (elements + 1).div_ceil(8);
        let limbs = |bytes: usize| bytes.div_ceil(4);
        let leaf_permutations = blocks(4);
        let cm_permutations = blocks(limbs(16) + limbs(32) + 4 + limbs(32));
        let nf_permutations = blocks(4 + 4 + 1);
        // The key is absorbed once and squeezed twice: the blocks of the absorption, and one more
        // whose state is the state they left. That block is what makes the two halves two values
        // of one reading of the key rather than two readings of it.
        let key_permutations = blocks(limbs(32)) + 1;
        let rate_permutations = blocks(limbs(32) + limbs(8) + limbs(1));
        // What the walk answers with costs no permutation: the value a redemption's accumulator
        // ends at stands at a boundary of the trace, against the root or against the right.
        let redemption_permutations =
            depth + leaf_permutations + cm_permutations + nf_permutations + key_permutations;
        assert_eq!(redemption_permutations, 50);
        let spend_permutations =
            2 * redemption_permutations + 2 * cm_permutations + rate_permutations;
        assert_eq!(spend_permutations, 110);
        let frame_permutations = 3 * spend_permutations;
        assert_eq!(frame_permutations, 330);

        let rows = frame_permutations * ROWS_PER_PERMUTATION;
        assert_eq!(rows, 42_240);
        // The least lawful height above that count: 2^15 does not reach the tail by whole folds,
        // so the height is 2^16 — and every length that carries a proof stands where it stood.
        assert!(Shape::of_rows_log2(15).is_err());
        let rows_log2 = 16;
        assert!(rows <= 1usize << rows_log2);
        // The margin the frame keeps at that cost, named rather than discovered: a permutation of
        // one row more than this would carry the trace past its height and move every length that
        // carries a proof.
        let ceiling = (1usize << rows_log2) / frame_permutations;
        assert_eq!(ceiling, 198);
        assert!(ROWS_PER_PERMUTATION <= ceiling);

        let shape = Shape::of_rows_log2(rows_log2).expect("the height reaches the tail");
        assert_eq!(shape.domain_log2(), 19);
        assert_eq!(shape.layers(), 5);
        assert_eq!(shape.levels_of_a_query(), 65);
        assert_eq!(shape.query_bytes(), 4_296);
        assert_eq!(shape.proof_bytes(), 210_968);
        // And the length the state layer carries for a proof is that number, held in one place.
        assert_eq!(shape.proof_bytes(), mt_state::PROOF_LEN);
    }

    // The length of a proof follows from the height its description stands at, and the lengths the
    // state layer carries are those numbers — two heights, two lengths, no third. A description
    // built at any other height is a proof no object has room for, which is what this holds.
    #[test]
    fn the_lengths_of_a_proof_follow_from_the_two_heights() {
        let shape = Shape::of_rows_log2(u32::from(ROWS_LOG2)).expect("the height reaches the tail");
        assert_eq!(shape.proof_bytes(), mt_state::PROOF_LEN);
        // The presence stands at its own height, and the arithmetic of the set lands on its
        // length: four layers, a domain of 2^17, forty-eight levels of folding paths a query
        // opens, and the bytes the derivation writes.
        let presence = Shape::of_rows_log2(u32::from(crate::circuit::presence::PRESENCE_ROWS_LOG2))
            .expect("the presence's height reaches the tail");
        assert_eq!(presence.layers(), 4);
        assert_eq!(presence.domain_log2(), 17);
        assert_eq!(presence.levels_of_a_query(), 48);
        assert_eq!(presence.query_bytes(), 3_528);
        assert_eq!(presence.proof_bytes(), mt_state::PRESENCE_PROOF_LEN);
        // The named wrong implementation: a description built at a height of its own choosing.
        // Every height is a length, and the objects of this protocol have room for exactly two.
        let lower = Shape::of_rows_log2(u32::from(ROWS_LOG2) - 4).expect("a lawful height");
        assert_ne!(lower.proof_bytes(), mt_state::PROOF_LEN);
        assert_ne!(lower.proof_bytes(), mt_state::PRESENCE_PROOF_LEN);
    }

    // The last layer stands over a domain of five hundred and twelve elements, which is room for
    // the sixty-four coefficients the tail carries — the check that the two parameters agree.
    #[test]
    fn the_domain_under_the_last_layer_holds_the_tail() {
        let shape = Shape::of_rows_log2(16).expect("the height reaches the tail");
        let under_the_last = 1usize << (shape.domain_log2() as usize - 2 * shape.layers());
        assert_eq!(under_the_last, 512);
        assert!(under_the_last >= TAIL_DEGREE);
        // What stops the folding is the degree and not the room: a further layer would carry the
        // bound to two to the fourth, below the tail, and a tail of sixty-four coefficients would
        // then claim more degree than the folding leaves it.
        let bound_a_layer_further =
            1usize << (shape.rows_log2() as usize - 2 * (shape.layers() + 1));
        assert_eq!(bound_a_layer_further, 16);
        assert!(bound_a_layer_further < TAIL_DEGREE);
        // Five steps take a bound of 2^16 to 2^6 exactly.
        assert_eq!(shape.rows_log2() - 2 * shape.layers() as u32, 6);
    }

    #[test]
    fn a_height_the_folding_cannot_reach_the_tail_from_is_refused() {
        assert_eq!(
            Shape::of_rows_log2(5),
            Err(ShapeError::RowsDoNotReachTheTail { rows_log2: 5 })
        );
        assert_eq!(
            Shape::of_rows_log2(21),
            Err(ShapeError::RowsDoNotReachTheTail { rows_log2: 21 })
        );
        // A height standing at the tail folds no layer at all, and every check of a proof past the
        // first reads the layer the folding did not make: it is refused with the rest rather than
        // admitted into a proof whose deep composition answers against nothing.
        assert_eq!(
            Shape::of_rows_log2(TAIL_DEGREE.trailing_zeros()),
            Err(ShapeError::RowsDoNotReachTheTail {
                rows_log2: TAIL_DEGREE.trailing_zeros()
            })
        );
        assert!(Shape::of_rows_log2(8).is_ok());
        assert_eq!(
            Shape::of_rows_log2(8).map(|shape| shape.layers()),
            Ok(1),
            "the least height this scheme folds at folds once"
        );
        assert!(Shape::of_rows_log2(12).is_ok());
    }
}
