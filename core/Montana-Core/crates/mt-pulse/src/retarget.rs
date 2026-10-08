// The two recomputations. The set states both in `docs/Montana Canon.md` — "The recomputation of
// the draw threshold" and "The recomputation of the round threshold" — and this is their one
// transcription: the multiplication before the division, the division toward zero, the clamp after
// the division and the floor last and by name.
//
// The direction of each ratio is the property, not the arithmetic. A rule that reproduces the
// shape and inverts the direction is a network that stalls once and then stalls forever, so both
// directions stand as assertions of this module and not only as vectors.

use crate::wide::U256;
use crate::PulseError;

fn parameter(name: &str) -> Result<u64, PulseError> {
    mt_genesis::scalar(name).ok_or(PulseError::DecreeIncomplete)
}

// The threshold both retargets begin from: the largest value the width of the comparison carries.
// Canon states it and states why it is forced — a threshold is walked by observations that exist
// only once windows have closed, so a starting value too low for the population that stands is a
// deadlock the arithmetic cannot leave, while the largest value opens the network and lets the
// first observation move it.
//
// It reads `hash_bytes` and nothing else, which is why it stands in no row of the Decree.
pub fn opening_threshold() -> Result<U256, PulseError> {
    let width = parameter("hash_bytes")?;
    if usize::try_from(width) != Ok(32) {
        return Err(PulseError::DecreeIncomplete);
    }
    Ok(U256::from_be_bytes(&[0xFFu8; 32]))
}

// The clamp and the floor, shared by both rules because the set states them once for both.
//
// **A quotient past the width is not an error but a value above the clamp.** The product of the
// rule is exact and its quotient can exceed the width — from a threshold standing at the width, a
// ratio of five does — and such a quotient stands above every upper bound the clamp can hold, so it
// takes that bound. An implementation that wrapped would turn the largest threshold into a small
// one; one that refused would stop a network whose threshold stands at the width, which is where
// every network begins.
fn clamp_and_floor(new: Option<U256>, old: U256, step_bound: u64) -> Result<U256, PulseError> {
    let low = old
        .div_u64(step_bound)
        .ok_or(PulseError::DecreeIncomplete)?;
    let high = old.saturating_mul_u64(step_bound);
    let held = match new {
        None => high,
        Some(new) if new < low => low,
        Some(new) if new > high => high,
        Some(new) => new,
    };
    Ok(if held.is_zero() { U256::ONE } else { held })
}

// The draw: `cleared` is the count of windows of the period in which at least one machine cleared
// the threshold. A higher threshold is an easier one, so the quotient rises when fewer windows
// cleared — written the other way a network that stalled once would make its next window harder,
// and harder again, with no bottom.
pub fn recompute_draw(target_old: U256, cleared: u64) -> Result<U256, PulseError> {
    let period = parameter("retarget_period")?;
    let damping = parameter("retarget_damping")?;
    let step_bound = parameter("retarget_step_bound")?;
    let numer = damping
        .checked_mul(period)
        .and_then(|v| v.checked_add(period))
        .ok_or(PulseError::DecreeIncomplete)?;
    let denom = damping
        .checked_mul(cleared)
        .and_then(|v| v.checked_add(period))
        .ok_or(PulseError::CountBeyondWidth)?;
    clamp_and_floor(target_old.mul_div(numer, denom), target_old, step_bound)
}

// The threshold of a round is not walked to by observation; it is read out of the state a window
// already holds. **A round advances on an attestation and on nothing else**, so a round no machine
// is drawn for is not a slow round but a chain that stands, and without a clock nothing tells that
// apart from an answer still in flight — the crowd of a round therefore carries a floor, and the
// floor holds at every population, down to the one machine a cold start begins with.
//
// `admitted` is the count of machines the tree of admitted machines carries; `chains` is the count
// in force. The crowd is per chain and per round, exactly as the strikes of a machine are spread
// across the chains, so the count of rounds a window takes and the crowd move together and their
// product — the strikes of a machine per window — is the constant the volume of the Decree is
// checked against.
pub fn round_threshold(admitted: u64, chains: u64) -> Result<U256, PulseError> {
    let width = opening_threshold()?;
    if admitted == 0 || chains == 0 {
        return Ok(width);
    }
    let floor = parameter("round_floor")?;
    let divisor = parameter("committee_divisor")?;
    let spread = divisor
        .checked_mul(chains)
        .ok_or(PulseError::CountBeyondWidth)?;
    let crowd = (admitted / spread).max(floor).min(admitted);
    let held = width
        .mul_div(crowd, admitted)
        .ok_or(PulseError::CountBeyondWidth)?;
    // The floor of one is applied last and by name: a threshold of nought is a chain whose rounds
    // no machine is ever eligible for, and the quotient reaches nought wherever the crowd does.
    Ok(if held == U256::ZERO { U256::ONE } else { held })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hex(v: U256) -> String {
        v.to_be_bytes().iter().map(|b| format!("{b:02x}")).collect()
    }

    fn two_pow_248() -> U256 {
        let mut bytes = [0u8; 32];
        bytes[0] = 1;
        U256::from_be_bytes(&bytes)
    }

    #[test]
    fn the_frozen_vectors_of_the_draw_reproduce() {
        // Canon, "Vectors of the recomputation".
        let period = mt_genesis::scalar("retarget_period").expect("named");
        assert_eq!(
            hex(recompute_draw(two_pow_248(), period).expect("computes")),
            "0100000000000000000000000000000000000000000000000000000000000000"
        );
        assert_eq!(
            hex(recompute_draw(two_pow_248(), 0).expect("computes")),
            "0400000000000000000000000000000000000000000000000000000000000000"
        );
        assert_eq!(
            hex(recompute_draw(two_pow_248(), period / 2).expect("computes")),
            "01aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        );
        assert_eq!(
            hex(recompute_draw(U256::from_u64(3), 0).expect("computes")),
            "000000000000000000000000000000000000000000000000000000000000000c"
        );
        assert_eq!(
            hex(recompute_draw(U256::from_u64(1), 0).expect("computes")),
            "0000000000000000000000000000000000000000000000000000000000000004"
        );
    }

    #[test]
    fn the_frozen_vectors_of_the_threshold_of_a_round_reproduce() {
        // Canon, "Vectors of the threshold of a round".
        for (admitted, chains, expected) in [
            (
                1u64,
                1u64,
                "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
            ),
            (
                3,
                1,
                "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
            ),
            (
                50,
                1,
                "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
            ),
            (
                100,
                1,
                "7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
            ),
            (
                12_800,
                1,
                "00ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
            ),
            (
                1_000_000,
                1,
                "00fffbce4217d2849cb252ce032db1e9f2778140dd3fe1975f2cb641700cd855",
            ),
            (
                1_000_000,
                4,
                "003ff69014b599aa60913a4f8726d04e618ce2d1f1cfbb9496249a133c1ce6c0",
            ),
        ] {
            assert_eq!(
                hex(round_threshold(admitted, chains).expect("computes")),
                expected,
                "admitted {admitted}, chains {chains}"
            );
        }
    }

    #[test]
    fn the_implementation_that_divides_without_the_floor_answers_otherwise() {
        // The named wrong one. It agrees at and above `round_floor x committee_divisor x chains`
        // admitted machines — which is why a vector of this rule may not stand on a large
        // population alone — and below it the crowd is nought, so the whole width collapses to the
        // floor of one: a chain no machine is ever eligible for.
        let floor = mt_genesis::scalar("round_floor").expect("named");
        let divisor = mt_genesis::scalar("committee_divisor").expect("named");
        let width = opening_threshold().expect("computes");
        let without_the_floor = |admitted: u64, chains: u64| {
            let crowd = (admitted / (divisor * chains)).min(admitted);
            let held = width.mul_div(crowd, admitted).expect("divides");
            if held == U256::ZERO {
                U256::ONE
            } else {
                held
            }
        };
        let boundary = floor * divisor;
        assert_eq!(
            without_the_floor(boundary, 1),
            round_threshold(boundary, 1).expect("computes"),
            "the two must agree where the divisor is what binds"
        );
        // Below the divisor its crowd is nought, so the whole width collapses to the floor of one:
        // a chain no machine is ever eligible for.
        for admitted in [1u64, 3, 100, divisor - 1] {
            assert_eq!(without_the_floor(admitted, 1), U256::ONE, "{admitted}");
            assert!(
                round_threshold(admitted, 1).expect("computes") > U256::ONE,
                "admitted {admitted}"
            );
        }
        // Between the divisor and the boundary its crowd is short of the floor, so its threshold is
        // narrower than the rule's at every one of them.
        for admitted in [divisor, divisor * 4, boundary - 1] {
            assert!(
                without_the_floor(admitted, 1) < round_threshold(admitted, 1).expect("computes"),
                "admitted {admitted}"
            );
        }
    }

    #[test]
    fn the_threshold_holds_the_width_below_the_floor_and_falls_with_the_population_above_it() {
        // Properties rather than the formula restated: what is asserted here is what the rule is
        // for, and an implementation that reproduced the arithmetic while losing any of these
        // would be a different rule wearing the same shape.
        let floor = mt_genesis::scalar("round_floor").expect("named");
        let divisor = mt_genesis::scalar("committee_divisor").expect("named");
        let width = opening_threshold().expect("computes");

        // At and below the floor every machine of the population is drawn, so the threshold is the
        // whole width — the network of one machine a cold start begins with among them.
        for admitted in 1..=floor {
            assert_eq!(
                round_threshold(admitted, 1).expect("computes"),
                width,
                "admitted {admitted}"
            );
        }

        // Between the floor and the boundary the crowd is the floor while the population grows
        // under it, so the threshold falls at every step and never reaches nought.
        let boundary = floor * divisor;
        let mut last = width;
        for admitted in [floor + 1, 100, 1_000, boundary] {
            let held = round_threshold(admitted, 1).expect("computes");
            assert!(held <= last, "the threshold rose at {admitted}");
            assert!(!held.is_zero(), "admitted {admitted}");
            last = held;
        }

        // At the boundary the crowd is the admitted through the divisor exactly, so the threshold
        // is the width through the divisor.
        let designed = width.mul_div(1, divisor).expect("divides");
        assert_eq!(round_threshold(boundary, 1).expect("computes"), designed);

        // Above it the share is the designed one and **stops falling**: it never exceeds it, and
        // never drops to half of it however far the population grows. A rule that kept falling
        // would be walking toward the very wall this one exists to remove.
        let half = width.mul_div(1, divisor * 2).expect("divides");
        for admitted in [boundary + 1, 100_000, 1_000_000, 10_000_000, 1_000_000_000] {
            let held = round_threshold(admitted, 1).expect("computes");
            assert!(held <= designed, "admitted {admitted}");
            assert!(held > half, "admitted {admitted}");
        }

        // A chain added spreads the strikes, so the crowd of one chain's round falls with it while
        // the floor still holds it up wherever it binds.
        for chains in 1..=8u64 {
            let wide = round_threshold(10_000_000, chains).expect("computes");
            let narrow = round_threshold(10_000_000, chains + 1).expect("computes");
            assert!(wide > narrow, "chains {chains}");
            assert_eq!(round_threshold(floor, chains).expect("computes"), width);
        }
    }

    #[test]
    fn the_direction_of_the_draw_is_the_one_the_set_states() {
        // The named wrong implementation of the draw: the quotient falling when nothing cleared.
        // A network that stalled once would then make its next window harder, and harder again.
        let period = mt_genesis::scalar("retarget_period").expect("named");
        let held = two_pow_248();
        let none = recompute_draw(held, 0).expect("computes");
        let all = recompute_draw(held, period).expect("computes");
        let half = recompute_draw(held, period / 2).expect("computes");
        assert!(none > half, "fewer cleared must be the easier threshold");
        assert!(half > all, "fewer cleared must be the easier threshold");
        assert_eq!(all, held, "every window cleared holds the threshold");
    }

    #[test]
    fn no_threshold_of_the_draw_reaches_zero_however_it_is_driven() {
        let mut target = U256::from_u64(1);
        for _ in 0..64 {
            let period = mt_genesis::scalar("retarget_period").expect("named");
            target = recompute_draw(target, period).expect("computes");
            assert!(!target.is_zero());
        }
    }

    #[test]
    fn a_step_of_the_draw_never_exceeds_the_bound() {
        let bound = mt_genesis::scalar("retarget_step_bound").expect("named");
        let held = two_pow_248();
        for cleared in [0u64, 1, 5_000, 20_160] {
            let new = recompute_draw(held, cleared).expect("computes");
            assert!(new <= held.saturating_mul_u64(bound));
            assert!(new >= held.div_u64(bound).expect("divides"));
        }
    }
}

#[cfg(test)]
mod opening {
    use super::*;

    // Canon, "The threshold the draw begins from".
    #[test]
    fn the_opening_threshold_is_the_width_and_every_draw_clears_it() {
        let held = opening_threshold().expect("the Decree names the width");
        assert_eq!(held.to_be_bytes(), [0xFFu8; 32]);
        // Every value the width carries stands below it but the one value equal to it, which is
        // what "drawn by everybody" means at the largest threshold there is.
        assert!(crate::clears(&[0x00u8; 32], &held));
        assert!(crate::clears(&[0xFEu8; 32], &held));
        let mut one_below = [0xFFu8; 32];
        one_below[31] = 0xFE;
        assert!(crate::clears(&one_below, &held));
        assert!(
            !crate::clears(&[0xFFu8; 32], &held),
            "a draw clears by standing below, so the largest value is not below itself"
        );
    }

    // The named wrong implementation this refuses: a starting value below the population that
    // stands. Its own retarget cannot repair it — the rise happens once per period of windows, and
    // a window ends only by closing, so a threshold nobody clears never gets its period.
    //
    // What the vector shows is the arithmetic of that: from the smallest thresholds the rule can
    // only walk while something clears, and the clamp of the first step from the largest value
    // saturates rather than wrapping.
    #[test]
    fn the_first_recomputation_from_the_opening_threshold_saturates_rather_than_wrapping() {
        let opening = opening_threshold().expect("named");
        let period = parameter("retarget_period").expect("named");
        // Every window of the period cleared, which is what an opening cohort does: the ratio is
        // one and the threshold holds.
        let held = recompute_draw(opening, period).expect("the rule computes");
        assert_eq!(
            held, opening,
            "a period that cleared every window moved the threshold"
        );
        // And where none cleared, the clamp bounds the rise to one step, which at the width is the
        // width itself rather than a value that wrapped to something small.
        let risen = recompute_draw(opening, 0).expect("the rule computes");
        assert_eq!(
            risen, opening,
            "the upper clamp wrapped instead of saturating"
        );
    }
}
