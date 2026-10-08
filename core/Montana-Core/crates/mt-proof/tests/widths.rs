// The width a proof may carry is one number of the set, counted on the circuit that was written
// first. Every circuit written after it inherits that number as a ceiling, and a circuit that
// exceeds it does not merely cost more: the length of every proof is derived from it, so the number
// moves and every frozen value standing on that length moves with it.
//
// This test is the sentence that says so out loud, and it says it about **every** description the
// network accepts proofs under rather than about the first of them. A test naming "every" and
// reading one is a denominator of one wearing the name of the whole: the property would hold by the
// unit tests of each circuit, and the guard the plan credits with holding it would be empty. The
// enumeration is therefore the same one `identifiers.rs` binds into `air_hash` — the day a fourth
// description joins that binding, it joins this bound.

use mt_proof::circuit::{admission, frame, presence, window};

// Every description the network accepts a proof under, with the width it spends. The list is the
// one the Decree's `air_hash` binds, so a circuit that reaches the network reaches this test.
fn every_written_circuit() -> Vec<(&'static str, usize)> {
    let depth = mt_proof::tree_depth();
    let places = frame::Places::of(depth).expect("the Decree names the shape of a frame");
    let of_frame = frame::description(&places, mt_proof::params::ROWS_LOG2)
        .expect("the frame's description stands");
    let of_window = window::description();
    let of_admission = admission::description().expect("the admission's description stands");
    // PANIC-OK: as above — a description of this tree, built from its own constants.
    let of_presence = presence::description().expect("the presence's description stands");
    vec![
        ("frame", usize::from(of_frame.trace_width)),
        ("window", usize::from(of_window.trace_width)),
        ("admission", usize::from(of_admission.trace_width)),
        ("presence", usize::from(of_presence.trace_width)),
    ]
}

#[test]
fn every_written_circuit_stands_under_the_one_bound() {
    let bound = mt_proof::params::TRACE_WIDTH_BOUND;
    let written = every_written_circuit();
    assert_eq!(
        written.len(),
        4,
        "the circuits `air_hash` binds and the circuits this test reads are one list"
    );
    for (name, width) in written {
        println!("the circuit of the {name}: {width} of {bound}");
        assert!(
            width <= bound,
            "the circuit of the {name} is wider than the bound, which moves the length of every proof"
        );
    }
}

// The frame stands exactly at the bound, and the set says the number was counted on it. That is
// worth an assertion of its own, because it is the fact that makes the next circuit a question
// rather than a formality: there is no room left under the ceiling, only the same ceiling again.
#[test]
fn the_bound_was_counted_on_the_circuit_that_stands_at_it() {
    assert_eq!(
        mt_proof::circuit::frame::trace_width(),
        mt_proof::params::TRACE_WIDTH_BOUND,
        "the set says the bound was counted on the written circuit"
    );
}
