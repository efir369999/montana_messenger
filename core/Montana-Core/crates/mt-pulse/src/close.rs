// The close of a window and the slots a selection event offers. The set states both in
// `docs/Montana Canon.md`, "The close of a window, and the slots an event offers": two comparisons
// written without a division, so that no rounding is left for two implementations to disagree
// about.

use crate::PulseError;

// A window closes when the count of distinct machines of the electorate that entered the cement
// reaches the share of the electorate's count the Decree names. The comparison multiplies rather
// than divides: at an electorate of three, a cement of two is not sixty-seven hundredths, and a rule
// that divided would call it one.
pub fn quorum_reached(cemented: u128, total: u128) -> Result<bool, PulseError> {
    let (num, den) =
        mt_genesis::ratio("confirmation_quorum").ok_or(PulseError::DecreeIncomplete)?;
    reaches_share(cemented, total, num, den)
}

// Both closing paths compare a subset with a nonempty electorate. Multiplying alone admits 0/0 and
// even a cement larger than the electorate it claims to be a part of.
fn reaches_share(cemented: u128, total: u128, num: u64, den: u64) -> Result<bool, PulseError> {
    if total == 0 || cemented > total {
        return Ok(false);
    }
    let left = cemented
        .checked_mul(u128::from(den))
        .ok_or(PulseError::CountBeyondWidth)?;
    let right = total
        .checked_mul(u128::from(num))
        .ok_or(PulseError::CountBeyondWidth)?;
    Ok(left >= right)
}

// The votes of a window against the committee its electorate's standing draws: the share of the
// expected votes the Decree names, compared without a division. A committee of nought — an
// electorate counted whole — asks no vote at all.
pub fn votes_reached(votes: u128, expected: u128) -> Result<bool, PulseError> {
    let (num, den) =
        mt_genesis::ratio("confirmation_quorum").ok_or(PulseError::DecreeIncomplete)?;
    let left = votes
        .checked_mul(u128::from(den))
        .ok_or(PulseError::CountBeyondWidth)?;
    let right = expected
        .checked_mul(u128::from(num))
        .ok_or(PulseError::CountBeyondWidth)?;
    Ok(left >= right)
}

// The close of a window as a whole: the count of distinct machines against the electorate, and the
// votes their standing drew against the committee. Both halves at the one share the Decree names.
pub fn closes_window(
    cemented: u128,
    total: u128,
    votes: u128,
    expected: u128,
) -> Result<bool, PulseError> {
    Ok(closes(cemented, total, 0)? && votes_reached(votes, expected)?)
}

// The count of candidates one selection event admits. The floor of one is what lets a young
// network grow: below the divisor the quotient is zero, an event that offers no slot admits
// nobody, and a network that admits nobody never reaches the count at which the quotient rises.
pub fn offered(active: u64) -> Result<u64, PulseError> {
    let divisor = mt_genesis::divisor("admission_divisor").ok_or(PulseError::DecreeIncomplete)?;
    Ok((active / divisor).max(1))
}

// Recovery keeps the quorum authenticated by the parent. A round count supplies no evidence that an
// absent machine died: an equivocating machine can be present in both competing certificates. The
// argument remains in the API so conformance can exercise the retired bypass boundaries.
pub fn resume_share_num(_rounds: u64) -> Result<u64, PulseError> {
    fixed_parent_rule()?;
    mt_genesis::ratio("confirmation_quorum")
        .map(|(num, _)| num)
        .ok_or(PulseError::DecreeIncomplete)
}

fn fixed_parent_rule() -> Result<(), PulseError> {
    match mt_genesis::scalar("finality_rule") {
        Some(1) => Ok(()),
        Some(_) => Err(PulseError::UnsupportedFinalityRule),
        None => Err(PulseError::DecreeIncomplete),
    }
}

// This is only the arithmetic predicate. The caller must authenticate the electorate, the distinct
// parts, the parent, the proposal and the complete transition before treating it as finality.
pub fn closes(cemented: u128, total: u128, _rounds: u64) -> Result<bool, PulseError> {
    fixed_parent_rule()?;
    quorum_reached(cemented, total)
}

// Re-basing the electorate on respondents forks under a partition, even with no Byzantine machine.
// A distinct network needs an explicit different Genesis; it is not this transition.
pub fn restart_admitted(_rounds: u64) -> Result<bool, PulseError> {
    fixed_parent_rule()?;
    Ok(false)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_empty_electorate_or_a_cement_larger_than_it_never_closes() {
        for (cemented, total) in [(0, 0), (1, 0), (2, 1), (101, 100)] {
            assert_eq!(quorum_reached(cemented, total), Ok(false));
            for rounds in [0, 1, u64::MAX] {
                assert_eq!(closes(cemented, total, rounds), Ok(false));
            }
        }
    }

    #[test]
    fn the_frozen_vectors_of_the_close_and_the_offering_reproduce() {
        // Canon, "The close of a window, and the slots an event offers".
        assert_eq!(quorum_reached(67, 100), Ok(true));
        assert_eq!(quorum_reached(66, 100), Ok(false));
        assert_eq!(quorum_reached(2, 3), Ok(false));
        assert_eq!(quorum_reached(100, 100), Ok(true));
        assert_eq!(offered(0), Ok(1));
        assert_eq!(offered(129), Ok(1));
        assert_eq!(offered(130), Ok(1));
        assert_eq!(offered(260), Ok(2));
        assert_eq!(offered(4_096), Ok(31));
    }

    #[test]
    fn the_named_wrong_implementations_answer_otherwise() {
        // A close computed by division: two thirds truncates to sixty-six hundredths and then to
        // zero, and a rule comparing quotients would close a window the Decree does not.
        let (num, den) = mt_genesis::ratio("confirmation_quorum").expect("named");
        assert_eq!(2 * 100 / 3, 66);
        assert!((2u128 * 100 / 3) * u128::from(den) < 100 * u128::from(num));
        // An offering that divides and stops: a network below the divisor never grows.
        let divisor = mt_genesis::scalar("admission_divisor").expect("named");
        assert_eq!(divisor - 1, 129);
        assert_eq!((divisor - 1) / divisor, 0);
        assert_eq!(offered(divisor - 1), Ok(1));
    }

    #[test]
    fn the_offering_rises_with_the_population_and_never_falls() {
        let mut last = 0;
        for active in (0..5_000).step_by(37) {
            let held = offered(active).expect("computes");
            assert!(held >= last);
            assert!(held >= 1);
            last = held;
        }
    }

    #[test]
    fn recovery_keeps_the_quorum_at_every_retired_boundary() {
        for rounds in [
            0,
            1,
            2_840,
            2_841,
            2_858,
            2_982,
            3_123,
            3_124,
            3_408,
            u64::MAX,
        ] {
            assert_eq!(resume_share_num(rounds), Ok(67));
            assert_eq!(closes(51, 100, rounds), Ok(false));
            assert_eq!(closes(67, 100, rounds), Ok(true));
            assert_eq!(restart_admitted(rounds), Ok(false));
        }
    }

    #[test]
    fn waiting_never_changes_the_parent_quorum() {
        for rounds in 0..4_000 {
            for (cemented, total) in [(67, 100), (66, 100), (2, 3), (100, 100)] {
                assert_eq!(
                    closes(cemented, total, rounds),
                    quorum_reached(cemented, total)
                );
            }
        }
    }

    #[test]
    fn a_count_at_the_width_of_the_type_is_refused_rather_than_wrapped() {
        assert_eq!(
            quorum_reached(u128::MAX, u128::MAX),
            Err(PulseError::CountBeyondWidth)
        );
    }
}
