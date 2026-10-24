// The standing of an electorate and the committee it draws. The set states both in
// `docs/Montana Canon.md`, "The standing of an electorate, and the votes it draws": the census
// windows a standing is counted over, the list a proposal carries of them, the sum that list
// yields, and the threshold every unit of standing is drawn against.
//
// **A standing nobody publishes, and a sum everybody holds.** A unit of standing is a census window
// whose cement holds a machine's part; which units a machine holds is known to that machine alone,
// since a part names nobody. The sum over the electorate is the sum of the counts of the census
// cements, and a proposal carries them, so the size of the committee is read off state and never
// off anybody's word.
//
// **Below a committee's worth of standing, the electorate is counted whole.** A draw hides a weight
// only where the sample is smaller than the population; a standing smaller than the committee it
// would be sampled into is a sample of everything, and a sample of everything publishes every
// weight. There the threshold is nought, no unit votes, and the close is the count of machines
// alone — so a young network discloses no standing because it weighs none.

use crate::wide::U256;
use crate::PulseError;

fn parameter(name: &str) -> Result<u64, PulseError> {
    mt_genesis::scalar(name).ok_or(PulseError::DecreeIncomplete)
}

// The count of census windows a standing is counted over.
pub fn censuses() -> Result<usize, PulseError> {
    usize::try_from(parameter("standing_censuses")?).map_err(|_| PulseError::DecreeIncomplete)
}

fn interval() -> Result<u64, PulseError> {
    mt_genesis::divisor("census_interval").ok_or(PulseError::DecreeIncomplete)
}

// Whether a window is a census window: one the cement of which a standing counts.
pub fn is_census(window: u64) -> Result<bool, PulseError> {
    Ok(window.is_multiple_of(interval()?))
}

// The census windows of a window, newest first: the census windows at or before it, one per
// interval, as many as a standing counts. A census that would stand before window nought stands
// nowhere, and its place reads nought — the root a proposal carries there is the root of the empty
// cement, which no part walks to.
pub fn census_windows(window: u64) -> Result<Vec<u64>, PulseError> {
    let interval = interval()?;
    let newest = window / interval;
    Ok((0..censuses()? as u64)
        .map(|at| newest.checked_sub(at).map_or(0, |index| index * interval))
        .collect())
}

// The census a proposal of `window` carries, out of the census its predecessor carried: at a census
// window the window's own cement enters first and the oldest leaves; at any other window the list
// is carried whole.
pub fn carried<T: Clone>(previous: &[T], window: u64, own: T) -> Result<Vec<T>, PulseError> {
    let censuses = censuses()?;
    if previous.len() != censuses {
        return Err(PulseError::DecreeIncomplete);
    }
    if !is_census(window)? {
        return Ok(previous.to_vec());
    }
    let mut out = Vec::with_capacity(censuses);
    out.push(own);
    out.extend_from_slice(&previous[..censuses - 1]);
    Ok(out)
}

// The standing of an electorate: the sum of the counts of its census cements.
pub fn standing(counts: &[u64]) -> Result<u64, PulseError> {
    counts.iter().try_fold(0u64, |sum, count| {
        sum.checked_add(*count).ok_or(PulseError::CountBeyondWidth)
    })
}

// The committee a standing draws: the threshold a unit's coin clears, and the votes the whole
// standing casts in expectation. Below `standing_censuses x standing_committee` units the threshold
// is nought and so is the expectation — the electorate is counted whole — and from there the
// threshold is the width times the committee over the standing, so a machine of full standing
// expects at most one vote.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Committee {
    pub threshold: U256,
    pub expected: u64,
}

pub fn committee(standing: u64) -> Result<Committee, PulseError> {
    let seats = parameter("standing_committee")?;
    let floor = seats
        .checked_mul(censuses()? as u64)
        .ok_or(PulseError::CountBeyondWidth)?;
    if standing < floor {
        return Ok(Committee {
            threshold: U256::ZERO,
            expected: 0,
        });
    }
    let width = crate::retarget::draw_threshold()?;
    let threshold = width
        .mul_div(seats, standing)
        .ok_or(PulseError::CountBeyondWidth)?;
    Ok(Committee {
        threshold,
        expected: seats,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hex(v: U256) -> String {
        v.to_be_bytes().iter().map(|b| format!("{b:02x}")).collect()
    }

    // The census windows step back one interval at a time from the newest at or before the window,
    // and a census that would precede window nought reads nought. The named wrong implementation
    // counts from the window itself rather than from the census at or before it, and answers every
    // window that is not a census window with windows no cement was ever counted at.
    #[test]
    fn the_census_windows_step_back_from_the_newest_census() {
        let interval = mt_genesis::scalar("census_interval").expect("named");
        let censuses = censuses().expect("named");
        let held = census_windows(3 * interval + 5).expect("computes");
        assert_eq!(held.len(), censuses);
        assert_eq!(&held[..4], &[3 * interval, 2 * interval, interval, 0]);
        assert!(held[4..].iter().all(|w| *w == 0));
        let at = census_windows(3 * interval).expect("computes");
        assert_eq!(at[0], 3 * interval);
        assert!(is_census(3 * interval).expect("computes"));
        assert!(!is_census(3 * interval + 5).expect("computes"));
    }

    // At a census window the window's own cement enters first and the oldest leaves; elsewhere the
    // list is carried whole. The named wrong implementation appends rather than prepends, and the
    // root a ballot walks for its newest census would be the root of the oldest.
    #[test]
    fn a_census_window_shifts_its_cement_in_and_the_oldest_out() {
        let interval = mt_genesis::scalar("census_interval").expect("named");
        let censuses = censuses().expect("named");
        let previous: Vec<u64> = (1..=censuses as u64).collect();
        let shifted = carried(&previous, 4 * interval, 99).expect("computes");
        assert_eq!(shifted[0], 99);
        assert_eq!(&shifted[1..], &previous[..censuses - 1]);
        assert_eq!(
            carried(&previous, 4 * interval + 1, 99).expect("computes"),
            previous
        );
        assert!(carried(&previous[1..], 4 * interval, 99).is_err());
    }

    // Below the floor the electorate is counted whole; at it the threshold is the width over the
    // count of censuses, so a unit votes one time in that many; above it the threshold falls with
    // the standing and never reaches nought.
    #[test]
    fn the_committee_is_nought_below_its_floor_and_a_sample_above_it() {
        let seats = mt_genesis::scalar("standing_committee").expect("named");
        let censuses = censuses().expect("named") as u64;
        let floor = seats * censuses;
        assert_eq!(committee(0).expect("computes").expected, 0);
        assert_eq!(
            committee(floor - 1).expect("computes").threshold,
            U256::ZERO
        );
        let at = committee(floor).expect("computes");
        assert_eq!(at.expected, seats);
        let width = crate::retarget::draw_threshold().expect("computes");
        assert_eq!(at.threshold, width.mul_div(1, censuses).expect("divides"));
        let far = committee(1_000_000_000).expect("computes");
        assert!(far.threshold < at.threshold);
        assert!(!far.threshold.is_zero());
        assert_eq!(
            hex(committee(u64::MAX).expect("computes").threshold).len(),
            64
        );
    }

    #[test]
    fn a_standing_past_the_width_of_a_count_is_refused_rather_than_wrapped() {
        assert_eq!(standing(&[u64::MAX, 1]), Err(PulseError::CountBeyondWidth));
        assert_eq!(standing(&[3, 4, 5]), Ok(12));
    }
}
