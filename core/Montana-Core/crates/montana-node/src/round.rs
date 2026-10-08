// The round of a chain, as a machine runs it. Every rule here is asked of the crate that owns it —
// the points of `mt-derive`, the eligibility of `mt-derive`, the beacon of `mt-state`, the cement of
// `mt-pulse`, the deposit and the collection of `mt-wire` — and what this file holds is the order
// they happen in.
//
// **A machine deposits at every replica and collects from every replica.** The points are a
// function of the window, the chain, the round and the index alone: nobody chooses them, and a
// machine computes the points of the round it is in without asking anybody. Withholding a round
// therefore takes holding every one of its points at once.
//
// **Eligibility is self-known and other-unknown.** A machine computes its own for every round the
// moment the aggregate cements, and nobody else can, because the one-time answering key of the
// window is unpublished until first used. It is grindless: nothing in the preimage is anyone's to
// choose.
//
// **What this file does not do, and why it is not a stub.** A machine's first attestation of a
// window is heavy and carries a proof binding its answering key to a living machine's secret. The
// set requires that proof and names no constraint set that produces it — the Decree binds three and
// none of them carries an answering key in its public input — so no machine can make one, and this
// tree writes no object whose contents the set does not define. The round therefore runs to the
// edge of the cement and stops there, and `AUDIT.md` carries the finding.

use mt_derive::{delivery, pulse};
use mt_state::layout::Beacon;
use mt_state::{Layout, ObjectError};

#[derive(Debug, PartialEq, Eq)]
pub enum RoundError {
    Decree,
    Object(ObjectError),
}

fn replicas() -> Result<u8, RoundError> {
    let held = mt_genesis::scalar("consensus_replicas").ok_or(RoundError::Decree)?;
    u8::try_from(held).map_err(|_| RoundError::Decree)
}

// Every point of one round, in the order of their indices. A machine deposits at all of them and
// collects from all of them, taking the union of what they hold.
pub fn points_of_round(window: u64, chain: u8, round: u32) -> Result<Vec<[u8; 16]>, RoundError> {
    Ok((0..replicas()?)
        .map(|index| delivery::round_point(window, chain, round, index))
        .collect())
}

// Every point a proposal of one window stands at.
pub fn points_of_window(window: u64) -> Result<Vec<[u8; 16]>, RoundError> {
    Ok((0..replicas()?)
        .map(|index| delivery::window_point(window, index))
        .collect())
}

// Whether this machine may attest this round. The comparison is unsigned and big-endian over the
// full width, and a value clears a threshold by standing **below** it — the same direction every
// draw of this protocol takes.
// What the draw reads is the nullifier of the machine's part in that window and never its one-time
// key: both are fixed by the secret and the window rather than chosen, but only the nullifier is a
// value the attestation of presence can assert, and a draw reading a value no proof binds would let
// a fabricator draw secrets until one of them clears.
pub fn eligible(
    part_nullifier: &[u8; 32],
    aggregate: &[u8; 32],
    chain: u8,
    round: u32,
    threshold: &mt_pulse::U256,
) -> bool {
    let drawn = pulse::round_eligibility(part_nullifier, aggregate, chain, round);
    mt_pulse::U256::from_be_bytes(&drawn) < *threshold
}

// The beacon that opens a round. Round zero links to the proposal of the window before — the very
// proposal whose cement these rounds accumulate — and every later round to the beacon before it.
pub fn beacon(
    window: u64,
    chain: u8,
    round: u32,
    previous: [u8; 32],
    cement_state: Vec<u8>,
) -> Result<Beacon, RoundError> {
    let held = Beacon {
        window,
        chain,
        round,
        previous,
        cement_state,
    };
    // The rule of the object is answered where it is written as well as where it is read, so a
    // beacon of the wrong width cannot be signed, cannot carry an identifier and cannot be
    // published by the machine that made it.
    held.bytes().map_err(RoundError::Object)?;
    Ok(held)
}

// The chain of beacons of one round, as a verifier walks it: each links to its predecessor by the
// identifier the beacon domain gives, and a link that does not hold is a chain that is not this
// one. A verifier recomputes every identifier rather than reading one that rode.
pub fn links_to(beacon: &Beacon, predecessor: &Beacon) -> Result<bool, RoundError> {
    let id = predecessor.id().map_err(RoundError::Object)?;
    // The round after the last one a count can carry is no round of this protocol: the addition is
    // checked rather than left to wrap, and a beacon carrying it links to nothing rather than
    // stopping the machine that reads it.
    let Some(after) = predecessor.round.checked_add(1) else {
        return Ok(false);
    };
    Ok(beacon.previous == id
        && beacon.round == after
        && beacon.chain == predecessor.chain
        && beacon.window == predecessor.window)
}

#[cfg(test)]
mod tests {
    use super::*;

    // The nullifier of a machine's part in a window, which is what the draw reads.
    // PANIC-OK: the secret is a literal of this test and the half it yields is of the family by
    // construction; a refusal here would mean the door of the halves has moved, which is what the
    // assertion exists to catch.
    fn part_of(machine: u8) -> [u8; 32] {
        mt_derive::nullifier::part(&[machine; 32], 1_000).expect("a half of the family")
    }

    fn empty_state() -> Vec<u8> {
        vec![0u8; mt_state::WEIGHT_COMMIT_BYTES]
    }

    #[test]
    fn every_replica_of_a_round_stands_at_a_point_of_its_own() {
        let points = points_of_round(1_000, 0, 7).expect("the Decree names the replicas");
        assert_eq!(
            points.len(),
            mt_genesis::scalar("consensus_replicas").expect("named") as usize
        );
        let mut seen = points.clone();
        seen.sort_unstable();
        seen.dedup();
        assert_eq!(seen.len(), points.len(), "two replicas share a point");
        // A point is a function of the window, the chain, the round and the index alone: move any
        // one of the four and every point moves.
        assert_ne!(points, points_of_round(1_001, 0, 7).expect("named"));
        assert_ne!(points, points_of_round(1_000, 1, 7).expect("named"));
        assert_ne!(points, points_of_round(1_000, 0, 8).expect("named"));
        // And the points of a window are not the points of a round of it.
        let of_window = points_of_window(1_000).expect("named");
        assert!(of_window.iter().all(|p| !points.contains(p)));
    }

    #[test]
    fn eligibility_is_a_function_of_what_nobody_chooses() {
        let aggregate = [0x11u8; 32];
        let all = mt_pulse::U256::from_be_bytes(&[0xFFu8; 32]);
        let none = mt_pulse::U256::from_u64(0);
        // A threshold of everything admits, a threshold of nothing admits nobody: the comparison
        // is below, which is the direction every draw of this protocol takes.
        assert!(eligible(&part_of(1), &aggregate, 0, 7, &all));
        assert!(!eligible(&part_of(1), &aggregate, 0, 7, &none));
        // It moves with the round, the chain and the aggregate, and with nothing a machine holds.
        let drawn = |chain, round, aggregate: &[u8; 32]| {
            pulse::round_eligibility(&part_of(1), aggregate, chain, round)
        };
        assert_ne!(drawn(0, 7, &aggregate), drawn(1, 7, &aggregate));
        assert_ne!(drawn(0, 7, &aggregate), drawn(0, 8, &aggregate));
        assert_ne!(drawn(0, 7, &aggregate), drawn(0, 7, &[0x12u8; 32]));
        // Two machines draw two values for one round: the sample is keyed to each one's own key.
        assert_ne!(
            pulse::round_eligibility(&part_of(1), &aggregate, 0, 7),
            pulse::round_eligibility(&part_of(2), &aggregate, 0, 7)
        );
    }

    #[test]
    fn a_chain_of_beacons_links_by_the_identifier_a_verifier_recomputes() {
        let zero = beacon(1_000, 0, 0, [0xAAu8; 32], empty_state()).expect("a beacon stands");
        let one = beacon(
            1_000,
            0,
            1,
            zero.id().expect("an identifier"),
            empty_state(),
        )
        .expect("a beacon stands");
        assert!(links_to(&one, &zero).expect("the rule answers"));

        // The named wrong implementations, each refused: a beacon carrying an identifier nobody
        // computes, one of another round, one of another chain, one of another window.
        let forged = beacon(1_000, 0, 1, [0xBBu8; 32], empty_state()).expect("a beacon stands");
        assert!(!links_to(&forged, &zero).expect("the rule answers"));
        let skipped = beacon(
            1_000,
            0,
            2,
            zero.id().expect("an identifier"),
            empty_state(),
        )
        .expect("a beacon stands");
        assert!(!links_to(&skipped, &zero).expect("the rule answers"));
        let elsewhere = beacon(
            1_000,
            1,
            1,
            zero.id().expect("an identifier"),
            empty_state(),
        )
        .expect("a beacon stands");
        assert!(!links_to(&elsewhere, &zero).expect("the rule answers"));
        let later = beacon(
            1_001,
            0,
            1,
            zero.id().expect("an identifier"),
            empty_state(),
        )
        .expect("a beacon stands");
        assert!(!links_to(&later, &zero).expect("the rule answers"));

        // And the count that cannot go on: a predecessor at the last round a count carries links to
        // nothing, where an addition left to wrap would stop the machine reading it.
        let last =
            beacon(1_000, 0, u32::MAX, [0xAAu8; 32], empty_state()).expect("a beacon stands");
        let after = beacon(
            1_000,
            0,
            0,
            last.id().expect("an identifier"),
            empty_state(),
        )
        .expect("a beacon stands");
        assert!(!links_to(&after, &last).expect("the rule answers"));
    }

    #[test]
    fn a_beacon_of_the_wrong_width_is_refused_where_it_is_written() {
        // The cement state is of one width, and a beacon carrying another is not a beacon of this
        // protocol: it is refused before it can be signed or carry an identifier.
        assert!(matches!(
            beacon(1_000, 0, 0, [0u8; 32], vec![0u8; 7]),
            Err(RoundError::Object(ObjectError::Length { .. }))
        ));
    }
}
