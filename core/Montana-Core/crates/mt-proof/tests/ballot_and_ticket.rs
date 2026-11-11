// Obligation O-6 of WINDOW-THEOREM.md: the descriptions of the ballot and of the ticket read
// constraint by constraint, and the wrong witnesses that reading names, each built here and held
// against the description. The ballot is held to the bound from above: a count its holder lowers is
// an abstention and stands, and a count above what the standing drew is refused.

use mt_codec::domain;
use mt_proof::air::{Boundary, BoundaryValue, Description};
use mt_proof::circuit::compare::{self, Compared, BYTES_OF_A_WORD, COMPARED_BYTES};
use mt_proof::circuit::{ballot, lane, path, permutation, ticket};
use mt_proof::field::{F, P};
use mt_proof::poseidon::{self, Digest, CAPACITY};

const WINDOW: u64 = 50_000;

fn spending_of(secret: &[u8; 32]) -> Digest {
    poseidon::hash_elements_twice(domain::MT_KEY_HALVES, &poseidon::limbs_of(secret)).0
}

// The standing the tests of the ballot stand on: five strangers' parts in every census cement, and
// the machine's own in every census but one in three.
fn a_standing(spending: &Digest) -> Vec<ballot::Census> {
    let interval = mt_genesis::scalar("census_interval").expect("the Decree names it");
    let newest = (WINDOW - 2) / interval * interval;
    let depth = mt_proof::tree_depth();
    (0..ballot::censuses().expect("the Decree names it"))
        .map(|at| {
            let window = newest - at as u64 * interval;
            let mut parts: Vec<[u8; 32]> = (0..5u8)
                .map(|i| poseidon::hash_bytes(domain::MT_PART_NF, &[i, at as u8, 7, 7]).bytes())
                .collect();
            let mine = ballot::part_of(spending, window)
                .expect("a window of the field")
                .bytes();
            let lived = at % 3 != 1;
            if lived {
                parts.push(mine);
            }
            parts.sort_unstable();
            let root = mt_proof::cement::root_of(&parts, depth).expect("distinct ascending parts");
            let branch = if lived {
                mt_proof::cement::branch_of(&parts, &mine, depth)
            } else {
                None
            };
            ballot::Census {
                window,
                root,
                branch,
            }
        })
        .collect()
}

// The same census windows and roots, lived by nobody.
fn unlived(censuses: &[ballot::Census]) -> Vec<ballot::Census> {
    censuses
        .iter()
        .map(|census| ballot::Census {
            window: census.window,
            root: census.root,
            branch: None,
        })
        .collect()
}

fn pairs(censuses: &[ballot::Census]) -> Vec<(u64, Digest)> {
    censuses.iter().map(|c| (c.window, c.root)).collect()
}

// A threshold that halves the width: a coin clears when its first byte stands below 0x80.
fn half() -> [u8; 32] {
    let mut out = [0u8; 32];
    out[0] = 0x80;
    out
}

fn clears(spending: &Digest, census: u64, aggregate: &[u8; 32], threshold: &[u8; 32]) -> bool {
    ballot::coin_of(spending, census, aggregate)
        .expect("a window of the field")
        .bytes()
        < *threshold
}

// A machine holding a lived unit, not the last, whose coin does not clear half the width.
fn a_lived_unit_that_does_not_clear(aggregate: &[u8; 32]) -> (Digest, Vec<ballot::Census>, usize) {
    for seed in 0x50u8..=0xFF {
        let spending = spending_of(&[seed; 32]);
        let censuses = a_standing(&spending);
        let found = (0..censuses.len() - 1).find(|at| {
            censuses[*at].branch.is_some()
                && !clears(&spending, censuses[*at].window, aggregate, &half())
        });
        if let Some(at) = found {
            return (spending, censuses, at);
        }
    }
    panic!("no machine of the seeds tried holds a lived unit whose coin does not clear");
}

// The product and the count rewritten out of the carried bit and the borrows the trace holds, as
// the honest writer of the ballot writes them.
fn rewrite_votes(trace: &mut [Vec<F>], places: &ballot::Places, columns: &ballot::Columns) {
    let afters: Vec<usize> = (0..places.censuses).map(|at| places.after(at)).collect();
    let products: Vec<F> = trace[columns.votes.carried()]
        .iter()
        .zip(&trace[columns.compared.borrow()])
        .map(|(carried, borrow)| carried.times(*borrow))
        .collect();
    let mut count = F::ZERO;
    let counts: Vec<F> = products
        .iter()
        .zip(&trace[columns.votes.carried()])
        .enumerate()
        .map(|(row, (product, carried))| {
            let here = count;
            if afters.contains(&row) {
                count = count.plus(*carried).minus(*product);
            }
            here
        })
        .collect();
    trace[columns.votes.product()] = products;
    trace[columns.votes.count()] = counts;
}

// Every rule a trace breaks and every row it breaks it at, over the rows the scheme holds it at.
fn broken(held: &Description, trace: &[Vec<F>]) -> Vec<(usize, u64)> {
    let mut out = Vec::new();
    for rule in 0..held.constraints.len() {
        for row in 0..held.live_rows() - 1 {
            if !held.evaluate(trace, rule, row).is_zero() {
                out.push((rule, row));
            }
        }
    }
    out
}

// The rules of the votes stand last in the description of a ballot: the bit, the bit at the seam
// alone, one rule of the root per cell, the carried bit twice, the product and the count.
fn vote_rules() -> usize {
    2 + CAPACITY + 4
}

// The bound of O-6, both ways from one standing. Down: a lived unit whose coin clears, with its bit
// lowered at the seam its walk ends at and the carried bit, the product and the count rewritten to
// agree, is a ballot of one vote fewer, and the description accepts it and the scheme proves it — an
// abstention, which only the holder of the spending half can write and which the certificate never
// prefers, since it keeps the largest count among a part's verified ballots (F-539-1, closed by the
// statement of the bound from above). Up: the same standing rewritten to count one more than it
// drew is refused — published over the honest trace, by the boundary of the count; written as the
// bit of a unit not lived whose coin clears, by the rules of the root at that seam and by no other.
#[test]
fn a_ballot_counts_at_most_what_its_part_drew_and_its_holder_may_abstain() {
    let spending = spending_of(&[0x5Au8; 32]);
    let censuses = a_standing(&spending);
    let aggregate = [0x33u8; 32];
    let threshold = [0xFFu8; 32];
    let held = ballot::description().expect("the description stands");
    let (honest, part, votes) =
        ballot::trace_of(&spending, WINDOW, &censuses, &aggregate, &threshold)
            .expect("an honest ballot");
    let places = ballot::Places::of(censuses.len());
    let columns = ballot::Columns::of();
    let public_of = |count: u64| {
        ballot::public_of(
            &part,
            WINDOW,
            &pairs(&censuses),
            &aggregate,
            &threshold,
            count,
        )
    };
    let limbs_of = |count: u64| poseidon::limbs_of(&public_of(count));
    assert!(held.satisfied_by(&honest, &limbs_of(votes)));

    // Down: the holder leaves a lived clearing unit uncounted.
    let lived = censuses
        .iter()
        .position(|c| c.branch.is_some())
        .expect("a lived census");
    assert!(lived + 1 < censuses.len());
    assert!(clears(
        &spending,
        censuses[lived].window,
        &aggregate,
        &threshold
    ));
    let mut fewer = honest.clone();
    let seam = places.root_seam(lived);
    fewer[columns.votes.spike()][seam] = F::ZERO;
    fewer[columns.votes.carried()][seam + 1..=places.root_seam(lived + 1)].fill(F::ZERO);
    rewrite_votes(&mut fewer, &places, &columns);
    assert!(
        !held.satisfied_by(&fewer, &limbs_of(votes)),
        "the lowered trace counts one fewer and publishes nothing else"
    );
    assert!(held.satisfied_by(&fewer, &limbs_of(votes - 1)));
    let public = public_of(votes - 1);
    let bytes = mt_proof::scheme::prove(&held, &public, &fewer).expect("an abstention proves");
    assert_eq!(mt_proof::scheme::verify(&held, &public, &bytes), Ok(()));

    // Up: one more than the standing drew, published over the honest trace.
    assert!(broken(&held, &honest).is_empty());
    assert!(!held.satisfied_by(&honest, &limbs_of(votes + 1)));

    // Up: one more than the standing drew, written as the bit of a unit not lived whose coin clears.
    let unlived = censuses
        .iter()
        .position(|c| c.branch.is_none())
        .expect("a census not lived");
    assert!(unlived + 1 < censuses.len());
    assert!(clears(
        &spending,
        censuses[unlived].window,
        &aggregate,
        &threshold
    ));
    let mut more = honest.clone();
    let seam = places.root_seam(unlived);
    more[columns.votes.spike()][seam] = F::ONE;
    more[columns.votes.carried()][seam + 1..=places.root_seam(unlived + 1)].fill(F::ONE);
    rewrite_votes(&mut more, &places, &columns);
    assert_eq!(
        more[columns.votes.count()][places.counted()],
        F::from_u64_reduced(votes + 1)
    );
    assert!(!held.satisfied_by(&more, &limbs_of(votes + 1)));
    let bit = held.constraints.len() - vote_rules();
    let root_rules = bit + 2..bit + 2 + CAPACITY;
    let rules = broken(&held, &more);
    assert!(!rules.is_empty(), "a unit not lived votes");
    assert!(
        rules
            .iter()
            .all(|(rule, row)| root_rules.contains(rule) && *row == seam as u64),
        "the vote of a unit not lived breaks another rule than the root at its seam: {rules:?}"
    );
}

// A lived unit cannot cast two votes by a bit of two at its seam: the rule of the root holds (the
// walk does reach the root), the carried bit takes the two, and the product and the count agree;
// the rule that the bit is a bit refuses it, and nothing else does.
#[test]
fn a_lived_unit_cannot_cast_two_votes_by_a_bit_of_two() {
    let spending = spending_of(&[0x5Au8; 32]);
    let censuses = a_standing(&spending);
    let aggregate = [0x33u8; 32];
    let threshold = [0xFFu8; 32];
    let held = ballot::description().expect("the description stands");
    let (mut trace, part, votes) =
        ballot::trace_of(&spending, WINDOW, &censuses, &aggregate, &threshold)
            .expect("an honest ballot");
    let places = ballot::Places::of(censuses.len());
    let columns = ballot::Columns::of();
    let lived = censuses
        .iter()
        .position(|c| c.branch.is_some())
        .expect("a lived census");
    let two = F::ONE.plus(F::ONE);
    let seam = places.root_seam(lived);
    trace[columns.votes.spike()][seam] = two;
    trace[columns.votes.carried()][seam + 1..=places.root_seam(lived + 1)].fill(two);
    rewrite_votes(&mut trace, &places, &columns);
    let public = ballot::public_of(
        &part,
        WINDOW,
        &pairs(&censuses),
        &aggregate,
        &threshold,
        votes + 1,
    );
    assert!(!held.satisfied_by(&trace, &poseidon::limbs_of(&public)));
    let bit = held.constraints.len() - vote_rules();
    let rules = broken(&held, &trace);
    assert!(!rules.is_empty(), "the second vote stands");
    assert!(
        rules
            .iter()
            .all(|(rule, row)| *rule == bit && *row == seam as u64),
        "the forgery breaks another rule than the bit at its seam: {rules:?}"
    );
}

// A coin that does not clear cannot vote by a borrow out written as nought: the subtraction of the
// last byte of its comparison reads that borrow one row on, and refuses it there and nowhere else.
#[test]
fn a_borrow_out_written_as_nought_does_not_make_a_coin_clear() {
    let aggregate = [0x33u8; 32];
    let threshold = half();
    let (spending, censuses, at) = a_lived_unit_that_does_not_clear(&aggregate);
    let held = ballot::description().expect("the description stands");
    let (mut trace, part, votes) =
        ballot::trace_of(&spending, WINDOW, &censuses, &aggregate, &threshold)
            .expect("an honest ballot");
    let places = ballot::Places::of(censuses.len());
    let columns = ballot::Columns::of();
    let after = places.after(at);
    assert_eq!(trace[columns.compared.borrow()][after], F::ONE);
    trace[columns.compared.borrow()][after] = F::ZERO;
    rewrite_votes(&mut trace, &places, &columns);
    let public = ballot::public_of(
        &part,
        WINDOW,
        &pairs(&censuses),
        &aggregate,
        &threshold,
        votes + 1,
    );
    assert!(!held.satisfied_by(&trace, &poseidon::limbs_of(&public)));
    let rules = broken(&held, &trace);
    assert!(!rules.is_empty(), "the forged vote stands");
    assert!(
        rules.iter().all(|(_, row)| *row == (after - 1) as u64),
        "the forgery breaks a rule off the last byte of its comparison: {rules:?}"
    );
}

// A machine whose coin does not clear cannot borrow the coin another spending half draws for the
// same census: the chain of the coin, its lane and its comparison grafted whole from a trace of the
// other half are refused at the one seam the spending half is wired into the coin, and nowhere else.
#[test]
fn a_coin_drawn_from_another_spending_half_is_refused() {
    let aggregate = [0x33u8; 32];
    let threshold = half();
    let (spending, censuses, at) = a_lived_unit_that_does_not_clear(&aggregate);
    let window = censuses[at].window;
    let other = (0u8..=0xFF)
        .map(|seed| spending_of(&[seed; 32]))
        .find(|half_of| *half_of != spending && clears(half_of, window, &aggregate, &threshold))
        .expect("a spending half whose coin clears");
    let held = ballot::description().expect("the description stands");
    let (mut trace, part, votes) =
        ballot::trace_of(&spending, WINDOW, &censuses, &aggregate, &threshold)
            .expect("an honest ballot");
    let (grafted, _, _) =
        ballot::trace_of(&other, WINDOW, &unlived(&censuses), &aggregate, &threshold)
            .expect("a ballot of nothing lived");
    let places = ballot::Places::of(censuses.len());
    let columns = ballot::Columns::of();
    let period = permutation::period();
    let coin = places.coin(at) * period..places.start(at);
    for (into, from) in trace.iter_mut().zip(&grafted).take(path::ACCUMULATOR) {
        into[coin.clone()].copy_from_slice(&from[coin.clone()]);
    }
    let lane_rows = places.start(at)..places.start(at + 1);
    for cell in 0..CAPACITY {
        let column = columns.coin.cell(cell);
        trace[column][lane_rows.clone()].copy_from_slice(&grafted[column][lane_rows.clone()]);
    }
    let compared_rows = places.start(at)..places.after(at) + 1;
    let compared_columns = columns.compared.width() - columns.compared.first;
    for (into, from) in trace
        .iter_mut()
        .zip(&grafted)
        .skip(columns.compared.first)
        .take(compared_columns)
    {
        into[compared_rows.clone()].copy_from_slice(&from[compared_rows.clone()]);
    }
    rewrite_votes(&mut trace, &places, &columns);
    let public = ballot::public_of(
        &part,
        WINDOW,
        &pairs(&censuses),
        &aggregate,
        &threshold,
        votes + 1,
    );
    assert!(!held.satisfied_by(&trace, &poseidon::limbs_of(&public)));
    let rules = broken(&held, &trace);
    let wire = places.root_seam(at) as u64;
    assert!(!rules.is_empty(), "the borrowed coin votes");
    assert!(
        rules.iter().all(|(_, row)| *row == wire),
        "the graft breaks a rule off the seam of the spending wire: {rules:?}"
    );
}

// The comparison alone, as both circuits use it: a lane holding the four words of a digest, the
// thirty-two rows opening at `start`, the threshold one public limb per row, the borrow in at one
// and the borrow out at nought — what "the digest clears" is in the ticket.
fn a_comparison_alone(start: usize) -> (Description, lane::Places, Compared) {
    let rows_log2 = (2 * mt_proof::params::FREE_ROWS).trailing_zeros() as u8;
    let digest = lane::Places::after(0);
    let compared = Compared::after(digest.width());
    let width = compared.width();
    let mut boundaries = compare::threshold_boundaries(&compared, start, |at| at as u16);
    boundaries.push(compare::borrow_in(&compared, start));
    boundaries.push(Boundary {
        column: compared.borrow() as u16,
        row: compare::after_of(start) as u64,
        value: BoundaryValue::Literal(0),
    });
    boundaries.extend(compare::accumulators_open(&compared, start));
    let held = Description {
        trace_width: width as u16,
        rows_log2,
        periodic: compare::periodic_columns(rows_log2, &[start]),
        constraints: compare::constraints(width, &compared, &digest),
        boundaries,
    };
    (held, digest, compared)
}

fn trace_of_a_comparison(
    held: &Description,
    digest: &lane::Places,
    compared: &Compared,
    start: usize,
    words: &[u64; CAPACITY],
    bytes: &[u8; 32],
    threshold: &[u8; 32],
) -> Vec<Vec<F>> {
    let rows = held.rows() as usize;
    let mut trace = vec![vec![F::ZERO; rows]; usize::from(held.trace_width)];
    for (cell, word) in words.iter().enumerate() {
        trace[digest.cell(cell)].fill(F::from_u64_reduced(*word));
    }
    compare::write(&mut trace, compared, start, bytes, threshold);
    trace
}

// A word written in bytes above the modulus is another spelling of the same field element: the
// word 0xFF written as the eight bytes of 0xFF + p puts nought in the most significant byte of the
// comparison, where its canonical bytes put 0xFF. Against a threshold of 0x80 the canonical digest
// does not clear and the second spelling would; the canonical check refuses the second spelling,
// and nothing but that check does.
#[test]
fn a_word_written_in_bytes_above_the_modulus_does_not_clear() {
    let start = 8usize;
    let (held, digest, compared) = a_comparison_alone(start);
    held.check().expect("the comparison alone is a description");
    let mut threshold = [0u8; 32];
    threshold[0] = 0x80;
    let public: Vec<F> = (0..COMPARED_BYTES)
        .map(|at| {
            let word = CAPACITY - 1 - at / BYTES_OF_A_WORD;
            let byte = BYTES_OF_A_WORD - 1 - at % BYTES_OF_A_WORD;
            F::from_u64_reduced(u64::from(threshold[word * BYTES_OF_A_WORD + byte]))
        })
        .collect();
    let words = [0xFFu64, 0, 0, 0];
    let mut canonical = [0u8; 32];
    canonical[..BYTES_OF_A_WORD].copy_from_slice(&words[0].to_le_bytes());
    let mut above = canonical;
    above[..BYTES_OF_A_WORD].copy_from_slice(&(words[0] + P).to_le_bytes());
    assert_eq!(above[0], 0);

    // The canonical spelling breaks no rule and does not clear: the borrow out is one, and the
    // boundary that holds it at nought is what refuses it.
    let honest = trace_of_a_comparison(
        &held, &digest, &compared, start, &words, &canonical, &threshold,
    );
    assert!(broken(&held, &honest).is_empty());
    assert_eq!(honest[compared.borrow()][compare::after_of(start)], F::ONE);
    assert!(!held.satisfied_by(&honest, &public));

    // The spelling above the modulus clears the subtraction and rebuilds the word the lane holds,
    // and is refused by the canonical check at the last byte of that word alone.
    let forged =
        trace_of_a_comparison(&held, &digest, &compared, start, &words, &above, &threshold);
    assert_eq!(forged[compared.borrow()][compare::after_of(start)], F::ZERO);
    assert!(!held.satisfied_by(&forged, &public));
    let canonical_rules = held.constraints.len() - (4 + CAPACITY)..held.constraints.len();
    let end_of_the_word = compare::row_of(start, 0, 0) as u64;
    let rules = broken(&held, &forged);
    assert!(!rules.is_empty(), "a word above the modulus clears");
    assert!(
        rules
            .iter()
            .all(|(rule, row)| canonical_rules.contains(rule) && *row == end_of_the_word),
        "the second spelling breaks another rule than the canonical check: {rules:?}"
    );
}

// The ticket of a machine as the derivation computes it: the spending half and the eight limbs of
// the aggregate under the ticket domain.
fn ticket_of(secret: &[u8; 32], aggregate: &[u8; 32]) -> Digest {
    let mut preimage = spending_of(secret).elements().to_vec();
    preimage.extend(poseidon::limbs_of(aggregate));
    poseidon::hash_elements(domain::MT_TICKET, &preimage)
}

fn one_above(value: &[u8; 32]) -> [u8; 32] {
    let mut out = *value;
    for byte in out.iter_mut().rev() {
        let (sum, carried) = byte.overflowing_add(1);
        *byte = sum;
        if !carried {
            break;
        }
    }
    out
}

// An admitted machine whose ticket does not clear cannot borrow a stranger's ticket that does: the
// chain of the ticket, the lane of the digest and the comparison grafted whole from the stranger's
// trace are refused at the one seam the spending half — the first squeeze of the halves the walked
// leaf is the second squeeze of — is wired into the ticket, and nowhere else. The reverse graft,
// the stranger's ticket over an admitted machine's membership, is
// `a_ticket_cannot_graft_another_machines_membership` in ticket.rs.
#[test]
fn a_ticket_drawn_from_another_spending_half_is_refused() {
    let admitted = [0x5Au8; 32];
    let depth = mt_proof::tree_depth();
    let siblings = mt_proof::admitted::empty_internals(depth)[..depth].to_vec();
    let aggregate = [0x33u8; 32];
    let key = vec![0xA1u8; mt_codec::size::SIGNING_PUBLIC_KEY];
    let own = ticket_of(&admitted, &aggregate).bytes();
    let stranger = (0u8..=0xFF)
        .map(|seed| [seed; 32])
        .find(|secret| *secret != admitted && ticket_of(secret, &aggregate).bytes() < own)
        .expect("a stranger whose ticket stands below the admitted machine's");
    let threshold = one_above(&ticket_of(&stranger, &aggregate).bytes());
    assert!(
        ticket::trace_of(&admitted, &siblings, 0, &aggregate, &threshold, &key).is_none(),
        "the admitted machine's own ticket does not clear"
    );
    let (mut trace, digests) =
        ticket::trace_of(&admitted, &siblings, 0, &aggregate, &[0xFFu8; 32], &key)
            .expect("the admitted machine's trace below a threshold of everything");
    let (grafted, _) = ticket::trace_of(&stranger, &siblings, 0, &aggregate, &threshold, &key)
        .expect("the stranger's ticket clears");
    let places = ticket::Places;
    let period = permutation::period();
    let chain = places.ticket() * period..places.key() * period;
    for (into, from) in trace.iter_mut().zip(&grafted).take(path::ACCUMULATOR) {
        into[chain.clone()].copy_from_slice(&from[chain.clone()]);
    }
    let digest_lane = lane::Places::after(lane::Places::after(path::TRACE_WIDTH).width());
    let compared = Compared::after(digest_lane.width());
    for (into, from) in trace
        .iter_mut()
        .zip(&grafted)
        .skip(digest_lane.first)
        .take(compared.width() - digest_lane.first)
    {
        into.copy_from_slice(from);
    }
    let held = ticket::description().expect("the description stands");
    let public = ticket::public_of(&digests, &aggregate, &threshold);
    assert!(!held.satisfied_by(&trace, &poseidon::limbs_of(&public)));
    let rules = broken(&held, &trace);
    let wire = (places.ticket() * period - 1) as u64;
    assert!(!rules.is_empty(), "the borrowed ticket clears");
    assert!(
        rules.iter().all(|(_, row)| *row == wire),
        "the graft breaks a rule off the seam of the spending wire: {rules:?}"
    );
}
