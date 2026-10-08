// The close of a window and the slots a selection event offers. The set states both in
// `docs/Montana Canon.md`, "The close of a window, and the slots an event offers": two comparisons
// written without a division, so that no rounding is left for two implementations to disagree
// about.

use crate::PulseError;

// A window closes when the standing that entered the cement reaches the share of the whole active
// set the Decree names. The comparison multiplies rather than divides: at a total of three, a
// cemented standing of two is not sixty-seven hundredths, and a rule that divided would call it
// one.
pub fn quorum_reached(cemented: u128, total: u128) -> Result<bool, PulseError> {
    let (num, den) =
        mt_genesis::ratio("confirmation_quorum").ok_or(PulseError::DecreeIncomplete)?;
    let left = cemented
        .checked_mul(u128::from(den))
        .ok_or(PulseError::CountBeyondWidth)?;
    let right = total
        .checked_mul(u128::from(num))
        .ok_or(PulseError::CountBeyondWidth)?;
    Ok(left >= right)
}

// The count of candidates one selection event admits. The floor of one is what lets a young
// network grow: below the divisor the quotient is zero, an event that offers no slot admits
// nobody, and a network that admits nobody never reaches the count at which the quotient rises.
pub fn offered(active: u64) -> Result<u64, PulseError> {
    let divisor = mt_genesis::divisor("admission_divisor").ok_or(PulseError::DecreeIncomplete)?;
    Ok((active / divisor).max(1))
}

// The way back. Consensus states it whole; this is its one transcription. After the open window
// has run `recovery_onset_multiple` times the derived count of rounds, the share a cement must
// reach falls by equal steps over one further count of that size, from the quorum the Decree names
// to one more part than half — and never below, because two disjoint parts cannot each hold more
// than half of one total, and that floor is the whole of what keeps a halt from becoming a fork.
//
// Nothing here is a sanction: no standing falls, no membership is revoked and no silence is judged.
// What moves is the bar, and it moves on a count of rounds — which advances on a valid attestation
// and on no clock — rather than on a timeout, which this protocol admits nowhere.
pub fn resume_share_num(rounds: u64) -> Result<u64, PulseError> {
    let (num, den) =
        mt_genesis::ratio("confirmation_quorum").ok_or(PulseError::DecreeIncomplete)?;
    let target = mt_genesis::divisor("target_rounds").ok_or(PulseError::DecreeIncomplete)?;
    let multiple =
        mt_genesis::scalar("recovery_onset_multiple").ok_or(PulseError::DecreeIncomplete)?;
    let onset = multiple
        .checked_mul(target)
        .ok_or(PulseError::CountBeyondWidth)?;
    // One more part than half, applied by name: at exactly half two parts of an even split would
    // both qualify, and the halt would have become the fork this floor exists to refuse.
    let floor = den / 2 + 1;
    if rounds <= onset {
        return Ok(num);
    }
    let completed = onset
        .checked_add(target)
        .ok_or(PulseError::CountBeyondWidth)?;
    if rounds >= completed {
        return Ok(floor);
    }
    // Unsigned, the multiplication before the division, the division toward zero.
    let fallen = num
        .checked_sub(floor)
        .and_then(|span| span.checked_mul(rounds - onset))
        .ok_or(PulseError::CountBeyondWidth)?
        / target;
    Ok(num - fallen)
}

// A window closes when the standing that entered the cement reaches the share the rule above gives
// at the count of rounds the window has run. At and below the onset that share is the quorum, so
// this is the close of the set with the way back folded into it rather than a second rule beside
// it — a second rule is where two implementations come to disagree about which one applies.
pub fn closes(cemented: u128, total: u128, rounds: u64) -> Result<bool, PulseError> {
    let (_, den) = mt_genesis::ratio("confirmation_quorum").ok_or(PulseError::DecreeIncomplete)?;
    let share = resume_share_num(rounds)?;
    let left = cemented
        .checked_mul(u128::from(den))
        .ok_or(PulseError::CountBeyondWidth)?;
    let right = total
        .checked_mul(u128::from(share))
        .ok_or(PulseError::CountBeyondWidth)?;
    Ok(left >= right)
}

// Where no part qualifies, the restart is admitted — after one further count of that size with no
// cement, so that the fall has run its whole course before anybody may open a chain that binds the
// head this one closed.
pub fn restart_admitted(rounds: u64) -> Result<bool, PulseError> {
    let target = mt_genesis::divisor("target_rounds").ok_or(PulseError::DecreeIncomplete)?;
    let multiple =
        mt_genesis::scalar("recovery_onset_multiple").ok_or(PulseError::DecreeIncomplete)?;
    let at = multiple
        .checked_add(2)
        .and_then(|m| m.checked_mul(target))
        .ok_or(PulseError::CountBeyondWidth)?;
    Ok(rounds >= at)
}

#[cfg(test)]
mod tests {
    use super::*;

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
    fn the_share_holds_at_the_quorum_until_the_onset_and_falls_to_the_floor() {
        // Canon, "Vectors of the way back".
        let target = mt_genesis::scalar("target_rounds").expect("named");
        let multiple = mt_genesis::scalar("recovery_onset_multiple").expect("named");
        let onset = multiple * target;
        assert_eq!(resume_share_num(0), Ok(67));
        assert_eq!(resume_share_num(onset), Ok(67));
        assert_eq!(resume_share_num(onset + 1), Ok(67));
        assert_eq!(resume_share_num(onset + 18), Ok(66));
        assert_eq!(resume_share_num(onset + 142), Ok(59));
        assert_eq!(resume_share_num(onset + 283), Ok(52));
        assert_eq!(resume_share_num(onset + target), Ok(51));
        assert_eq!(resume_share_num(u64::MAX), Ok(51));
    }

    #[test]
    fn the_share_never_falls_below_one_more_part_than_half() {
        // The whole of the anti-fork guarantee: two disjoint parts cannot each hold more than half
        // of one total, so at most one part of a split ever closes — whatever order they are
        // driven in, and whether or not they can see each other.
        let (_, den) = mt_genesis::ratio("confirmation_quorum").expect("named");
        let floor = den / 2 + 1;
        for rounds in [0u64, 1, 2_840, 3_000, 3_124, 100_000, u64::MAX] {
            assert!(
                resume_share_num(rounds).expect("computes") >= floor,
                "{rounds}"
            );
        }
        assert!(2 * floor > den, "two parts of a split would both close");
        // At the floor, half of a total does not close and one more part does.
        assert_eq!(closes(50, 100, u64::MAX), Ok(false));
        assert_eq!(closes(51, 100, u64::MAX), Ok(true));
        // And the named wrong implementation — a floor of exactly half — would let both.
        assert!(50 * u128::from(den) >= 100 * u128::from(den / 2));
    }

    #[test]
    fn the_fall_never_moves_upward_and_the_close_only_loosens() {
        let mut last = resume_share_num(0).expect("computes");
        for rounds in (0..4_000).step_by(7) {
            let held = resume_share_num(rounds).expect("computes");
            assert!(held <= last, "the share rose at {rounds}");
            last = held;
        }
    }

    #[test]
    fn the_close_at_and_below_the_onset_is_the_quorum_of_the_set() {
        // The way back folds into the close rather than standing beside it: below the onset the
        // two answer identically, so no implementation has to decide which rule applies.
        for (cemented, total) in [(67u128, 100u128), (66, 100), (2, 3), (100, 100)] {
            assert_eq!(
                closes(cemented, total, 0),
                quorum_reached(cemented, total),
                "{cemented}/{total}"
            );
        }
    }

    #[test]
    fn a_restart_is_admitted_only_after_the_fall_has_run_its_course() {
        let target = mt_genesis::scalar("target_rounds").expect("named");
        let multiple = mt_genesis::scalar("recovery_onset_multiple").expect("named");
        let at = (multiple + 2) * target;
        assert_eq!(restart_admitted(at - 1), Ok(false));
        assert_eq!(restart_admitted(at), Ok(true));
        // The fall has completed before a restart is admitted, and by a whole count of rounds.
        assert_eq!(
            resume_share_num(at),
            resume_share_num(multiple * target + target)
        );
    }

    #[test]
    fn a_standing_at_the_width_of_the_type_is_refused_rather_than_wrapped() {
        assert_eq!(
            quorum_reached(u128::MAX, 1),
            Err(PulseError::CountBeyondWidth)
        );
    }
}
