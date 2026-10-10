// The aggregation that feeds a consensus-critical seed, and the three calls consensus makes of
// it. The set states them in `docs/Montana Canon.md`, "R3 — aggregation for a seed" and "The
// draw, and the two canonical orders".
//
// What enters is signer identities and a temporal anchor, and never content, signatures or
// identifiers: the grinding surface of one participant is zero, because its commitment is fixed
// at registration and the composition of the set is emergent. An empty set takes a domain of
// its own, so a window that cemented nothing is not silently equal to one that cemented
// something.

use mt_codec::{domain, hash, Domain, Part, Preimage};

#[derive(Debug, PartialEq, Eq)]
pub struct RepeatedSigner;

// The identities are concatenated ascending, so two nodes holding one set reach one value
// whatever order they saw its members in.
// A repeated identity is refused here rather than folded twice or deduplicated, for the reason the
// fold of a window states where it refuses one: a set is what the members of a window are, and a
// run holding one of them twice is not a set. Deduplicating would let two verifiers holding the
// same members in two arrival orders carry one value while a third, handed the repeat, carried
// another; folding twice would let whoever assembles the run move the aggregate by handing in a
// member already in it — and the aggregate is what the draw, both canonical orders and the cascade
// stand on. The two aggregations over the members of one window now hold one defence.
pub fn for_seed(
    signer_ids: &[[u8; 32]],
    agg_domain: Domain,
    empty_domain: Domain,
    context: &[u8; 8],
) -> Result<[u8; 32], RepeatedSigner> {
    if signer_ids.is_empty() {
        return Ok(Preimage::under(empty_domain).fixed(context).finish());
    }
    let mut sorted: Vec<[u8; 32]> = signer_ids.to_vec();
    sorted.sort_unstable();
    if sorted.windows(2).any(|pair| pair[0] == pair[1]) {
        return Err(RepeatedSigner);
    }
    // The run of identities is of one width and the context of another, so the preimage reads one
    // way and the builder writes it: no body is assembled here, and no width can be erased on the
    // way in.
    Ok(Preimage::under(agg_domain)
        .run(&sorted)
        .fixed(context)
        .finish())
}

// The aggregate of a window: its context is the window, so one set of signers at two heights
// yields two values.
pub fn aggregate(signer_ids: &[[u8; 32]], window: u64) -> Result<[u8; 32], RepeatedSigner> {
    for_seed(
        signer_ids,
        domain::MT_BC_AGGREGATE,
        domain::MT_BC_AGGREGATE_EMPTY,
        &window.to_le_bytes(),
    )
}

// The ticket of a machine, never published: the window's proof asserts its clearing, and that
// assertion is the only judge it has. It is therefore of the proof hash family — a function the
// circuit cannot carry would put the draw beyond proving — while the three order keys below stay
// SHA-256, because every verifier computes those from state with no proof in hand.
pub fn ticket(machine_secret: &[u8; 32], aggregate: &[u8; 32]) -> [u8; 32] {
    let mut preimage = Vec::with_capacity(64);
    preimage.extend_from_slice(machine_secret);
    preimage.extend_from_slice(aggregate);
    mt_proof::poseidon::hash_bytes(domain::MT_TICKET, &preimage).bytes()
}

// The three canonical orders. Both stand on the same aggregate as the draw and for the same
// reason: it cannot be computed before the honest signatures that fix it exist, so no
// participant grinds a commitment toward a favourable position in either.
// The standby order a cascade walks: the ascending order of this key over the commitments of the
// active set, the first `cascade_width` of them entitled and senior first. It stands on the same
// cemented aggregate as the draw and the two orders beside it, so no participant grinds a
// commitment toward an earlier place, and it takes a domain of its own, since a value serving two
// orders would make one mechanism readable from the other.
pub fn cascade_key(aggregate: &[u8; 32], commitment: &[u8; 32]) -> [u8; 32] {
    hash(
        domain::MT_CASCADE,
        &[Part::of(aggregate), Part::of(commitment)],
    )
}

pub fn selection_key(aggregate: &[u8; 32], commitment: &[u8; 32]) -> [u8; 32] {
    hash(
        domain::MT_SELECTION,
        &[Part::of(aggregate), Part::of(commitment)],
    )
}

pub fn registration_key(aggregate: &[u8; 32], commitment: &[u8; 32]) -> [u8; 32] {
    hash(
        domain::MT_NODEREG_SORT,
        &[Part::of(aggregate), Part::of(commitment)],
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    // The door of one body stands here to write the wrong implementations these vectors refuse:
    // a body laid beside another is exactly what the builder no longer lets the tree write.
    use mt_codec::hash_of_one;

    fn hex(bytes: &[u8]) -> String {
        bytes.iter().map(|b| format!("{b:02x}")).collect()
    }

    const W: u64 = 1000;

    fn cemented() -> [[u8; 32]; 2] {
        [[0x10u8; 32], [0x40u8; 32]]
    }

    #[test]
    fn the_aggregate_the_ticket_and_the_two_orders_are_the_frozen_values() {
        // Canon, "The aggregate, the ticket and the two orders".
        let agg = aggregate(&cemented(), W).expect("no repeat");
        assert_eq!(
            hex(&agg),
            "673a9549b24ae601ebf3e3aa8d5215883518cbcf9fcbaeea3e4e7fb67a3d98de"
        );
        assert_eq!(
            hex(&aggregate(&[], W).expect("no repeat")),
            "5d25d6189f62e347d8075dc3485e31e66e4c67492f1b25c1131a57d9e1af62f7"
        );
        assert_eq!(
            hex(&ticket(&[0x77u8; 32], &agg)),
            "c156cf92ed5da581dd5691330f53058666e15133777d84bea48e066c830ab95b"
        );
        assert_eq!(
            hex(&selection_key(&agg, &[0x10u8; 32])),
            "8878a966c5c9952f92d873170044c4d25a2e8c3c398eab4626979591e2321512"
        );
        assert_eq!(
            hex(&registration_key(&agg, &[0x40u8; 32])),
            "801171079fc782bdd6d28cef81dd3c1ec30db517b59d6e7fbc78a67c936ff9f2"
        );
        assert_eq!(
            hex(&cascade_key(&agg, &[0x10u8; 32])),
            "74b5211962f44431a2b6fa74d4bb42bb404971fae3b51dba197fca38afaea9f6"
        );
        assert_eq!(
            hex(&cascade_key(&agg, &[0x40u8; 32])),
            "0ddc936f7eb21d388796f3bd15eee224f4bee71d3eecfd61eb4159759ce5b465"
        );
        // The two keys of the cascade order the two commitments of this set, and the smaller is
        // the senior: an implementation reproducing the values reproduces the order with them.
        assert!(cascade_key(&agg, &[0x40u8; 32]) < cascade_key(&agg, &[0x10u8; 32]));
    }

    #[test]
    fn the_order_the_set_was_seen_in_carries_nothing() {
        let straight = aggregate(&[[0x10u8; 32], [0x40u8; 32]], W).expect("no repeat");
        let reversed = aggregate(&[[0x40u8; 32], [0x10u8; 32]], W).expect("no repeat");
        assert_eq!(straight, reversed);
        // The named wrong implementation: concatenating in the order seen. It reproduces the
        // frozen value for one order of arrival and another for the other.
        let unsorted = {
            let mut concatenated = Vec::new();
            concatenated.extend_from_slice(&[0x40u8; 32]);
            concatenated.extend_from_slice(&[0x10u8; 32]);
            concatenated.extend_from_slice(&W.to_le_bytes());
            hash_of_one(domain::MT_BC_AGGREGATE, &concatenated)
        };
        assert_ne!(unsorted, straight);
    }

    // The members of one window are a set, and a run holding one of them twice is refused rather
    // than folded twice or quietly deduplicated. The named wrong implementation this catches is
    // the one that folds the repeat: it moves the aggregate the draw and both canonical orders
    // stand on, and whoever assembles the run moves it by handing in a member already there.
    // A run of one width followed by a part of another is one concatenation: the count of the run
    // is what the length of the preimage gives, since what follows it is of a width of its own.
    // That holds here because the context is eight bytes and an identity is thirty-two — and this
    // is what says so. The named wrong implementation it refuses is the one that puts a part of
    // thirty-two bytes after the run: a run of k identities and a tail would then share a preimage
    // with a run of k + 1, and two different sets of members would carry one aggregate.
    #[test]
    fn the_tail_of_the_preimage_is_of_another_width_than_the_run() {
        assert_eq!(core::mem::size_of::<u64>(), 8);
        assert_ne!(core::mem::size_of::<u64>(), 32);
        // And the two shapes the widths keep apart are told apart in bytes.
        let one = aggregate(&[[0x10u8; 32], [0x40u8; 32]], W).expect("no repeat");
        let other = aggregate(&[[0x10u8; 32], [0x40u8; 32], [0x00u8; 32]], W).expect("no repeat");
        assert_ne!(one, other);
    }

    #[test]
    fn a_run_holding_one_identity_twice_is_refused() {
        assert_eq!(
            aggregate(&[[0x10u8; 32], [0x10u8; 32]], W),
            Err(RepeatedSigner)
        );
        assert_eq!(
            aggregate(&[[0x40u8; 32], [0x10u8; 32], [0x40u8; 32]], W),
            Err(RepeatedSigner)
        );
        // And the set of two distinct members stands, so what is refused is the repeat and not
        // the shape of the call.
        assert!(aggregate(&cemented(), W).is_ok());
    }

    #[test]
    fn a_window_that_cemented_nothing_is_not_one_that_cemented_something() {
        assert_ne!(
            aggregate(&[], W).expect("no repeat"),
            aggregate(&cemented(), W).expect("no repeat")
        );
        // And the empty aggregate moves with its window, so two empty windows do not agree.
        assert_ne!(
            aggregate(&[], W).expect("no repeat"),
            aggregate(&[], W + 1).expect("no repeat")
        );
    }

    #[test]
    fn the_temporal_anchor_enters_and_two_heights_never_agree() {
        assert_ne!(
            aggregate(&cemented(), W).expect("no repeat"),
            aggregate(&cemented(), W + 1).expect("no repeat")
        );
        // The named wrong implementation: the anchor dropped. It yields a value the set does
        // not hold and makes two heights of one set agree.
        let mut concatenated = Vec::new();
        for id in [[0x10u8; 32], [0x40u8; 32]] {
            concatenated.extend_from_slice(&id);
        }
        let without = hash_of_one(domain::MT_BC_AGGREGATE, &concatenated);
        assert_ne!(without, aggregate(&cemented(), W).expect("no repeat"));
    }

    #[test]
    fn each_of_the_three_calls_stands_under_its_own_domain() {
        let agg = aggregate(&cemented(), W).expect("no repeat");
        let mut seen = vec![
            ticket(&[0x77u8; 32], &agg),
            selection_key(&agg, &[0x10u8; 32]),
            registration_key(&agg, &[0x10u8; 32]),
        ];
        let before = seen.len();
        seen.sort_unstable();
        seen.dedup();
        assert_eq!(before, seen.len());
    }
}
