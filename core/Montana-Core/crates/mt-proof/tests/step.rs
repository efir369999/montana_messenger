// What a step of the accumulation costs, measured on the gadgets that are written rather than
// estimated before they were. The set carries first-order counts; this is what the code says.
use mt_proof::circuit::{discharge, fold};
use mt_proof::params::TRACE_WIDTH_BOUND;

#[test]
fn what_a_step_of_the_accumulation_costs_by_the_written_gadgets() {
    let width = TRACE_WIDTH_BOUND;
    let coefficients = 1536usize;
    let randomness = 2816usize;
    let bits_of_a_folded_digit = 29usize;
    let height = 131072usize;

    let lanes = fold::lanes_in(width, 0);
    let fold_rows = fold::rows_of(coefficients, lanes);
    println!(
        "the fold: {lanes} lane a row, {} repetitions, {fold_rows} rows in all",
        fold::REPETITIONS
    );

    let widest = width - 1;
    let discharge_rows = discharge::rows_of(randomness * bits_of_a_folded_digit, widest);
    println!("the discharge: {widest} booleans a row, {discharge_rows} rows");

    let rest = 4601usize;
    let whole = fold_rows + discharge_rows + rest;
    println!(
        "the whole step: {whole} rows of {height} = {} parts in a hundred",
        100 * whole / height
    );
    assert!(
        whole < height,
        "a step must stand inside the height the memory admits"
    );
    assert!(discharge::Places::after(0, widest).width() <= width);
    assert!(fold::Places::after(0, lanes).width() <= width);
}
