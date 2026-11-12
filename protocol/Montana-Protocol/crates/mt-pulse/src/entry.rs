// The gate of entry: how many segments of lived continuity a candidacy proves, and how many of them
// it must have lived. Consensus states the count under "Presence and admission" as a ramp (decision
// 292, answer 4b; constitution records 297 and 300):
//
//   n = min(max_entry_segments, max(continuity_segments,
//           ceil(continuity_segments x pending x adaptive_entry_multiplier / active)))
//
// `pending` is the count of candidacies applied and neither admitted nor expired, and `active` is
// the `admitted_count`, both of the proposal a candidacy takes its `record_root` from. The ramp
// leaves `continuity_segments` exactly at the threshold the Decree gives, because the multiplier is
// that threshold turned over (the genesis gate holds the two to it), and it reaches
// `max_entry_segments` at four times the threshold.
//
// **Where nothing is active the formula divides by nought, and no count is given.** The decision
// does not say what stands there. The question is the Author's, so this answers nothing rather than
// choosing a count.

use crate::PulseError;

fn parameter(name: &str) -> Result<u64, PulseError> {
    mt_genesis::scalar(name).ok_or(PulseError::DecreeIncomplete)
}

// The count of segments in force at the gate of entry, or nothing where the active set is empty.
// The products are taken wide, so no count a proposal carries wraps them.
pub fn n_in_force(pending: u64, active: u64) -> Result<Option<u32>, PulseError> {
    let floor = parameter("continuity_segments")?;
    let ceiling = parameter("max_entry_segments")?;
    let slope = parameter("adaptive_entry_multiplier")?;
    if active == 0 {
        return Ok(None);
    }
    let pressed = u128::from(floor) * u128::from(pending) * u128::from(slope);
    let raised = pressed.div_ceil(u128::from(active));
    let n = raised.max(u128::from(floor)).min(u128::from(ceiling));
    u32::try_from(n)
        .map(Some)
        .map_err(|_| PulseError::CountBeyondWidth)
}

// The segments of `in_force` a record must have lived: the share of Identity, the multiplication
// before the division and the division rounding upward.
pub fn required_segments(in_force: u32) -> Result<u32, PulseError> {
    let (num, den) = mt_genesis::ratio("continuity_required")
        .filter(|&(_, den)| den != 0)
        .ok_or(PulseError::DecreeIncomplete)?;
    let share = (u64::from(in_force) * num).div_ceil(den);
    u32::try_from(share).map_err(|_| PulseError::CountBeyondWidth)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn at(pending: u64, active: u64) -> Option<u32> {
        n_in_force(pending, active).expect("the Decree names every row")
    }

    // At the threshold of one pending candidacy to a hundred active machines the ramp stands at its
    // floor, and at four times the threshold it reaches its ceiling. The named wrong implementation
    // is the literal step (a), which answers the ceiling the moment the threshold is crossed: it
    // answers fifty-six where the ramp answers twenty-eight at twice the threshold.
    #[test]
    fn the_ramp_stands_at_fourteen_at_the_threshold_and_at_fifty_six_at_four_times_it() {
        assert_eq!(at(1, 100), Some(14));
        assert_eq!(at(100, 10_000), Some(14));
        assert_eq!(at(2, 100), Some(28));
        assert_eq!(at(3, 100), Some(42));
        assert_eq!(at(4, 100), Some(56));
        assert_eq!(at(400, 10_000), Some(56));
        // Past four times the threshold the ceiling holds, and below the threshold the floor does.
        assert_eq!(at(5, 100), Some(56));
        assert_eq!(at(100, 100), Some(56));
        assert_eq!(at(u64::MAX, 1), Some(56));
        assert_eq!(at(0, 100), Some(14));
        assert_eq!(at(1, 1_000), Some(14));
        assert_eq!(at(0, u64::MAX), Some(14));
    }

    // Just past the threshold the division rounds upward: 14 x 101 x 100 / 10 000 is 14.14 and the
    // count is fifteen. The named wrong implementations round downward (fourteen here) and add one
    // to every quotient (twenty-two where 14 x 3 x 100 / 200 is exactly twenty-one).
    #[test]
    fn the_ramp_rounds_upward_and_only_where_the_division_leaves_a_remainder() {
        assert_eq!(at(101, 10_000), Some(15));
        assert_eq!(at(3, 200), Some(21));
        assert_eq!(at(7, 250), Some(40));
        assert_eq!(at(10_001, 1_000_000), Some(15));
    }

    // An empty active set gives no count: the formula divides by nought there and the decision does
    // not say what stands in its place. The named wrong implementations answer the floor or the
    // ceiling, and each would choose for the Author.
    #[test]
    fn an_empty_active_set_gives_no_count() {
        assert_eq!(at(0, 0), None);
        assert_eq!(at(5, 0), None);
    }

    // Two thirds of fourteen is ten, and of fifty-six is thirty-eight: the share rounds upward.
    #[test]
    fn the_share_of_a_count_rounds_upward() {
        assert_eq!(required_segments(14), Ok(10));
        assert_eq!(required_segments(15), Ok(10));
        assert_eq!(required_segments(28), Ok(19));
        assert_eq!(required_segments(56), Ok(38));
        assert_eq!(required_segments(0), Ok(0));
    }
}
