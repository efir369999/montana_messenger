// The worth of a window's right, against the vectors the set freezes beside the rule. They are read
// out of `docs/Montana Consensus.md`, "The right to a window's seconds", rather than copied here: a
// vector written twice is two vectors, and the day one of them moves the other would still pass.
//
// The named wrong implementations they refuse are the set's own: a fixed coin per window, a worth of
// a round rounded before it is multiplied, a count of chains left out, and a worth rounded up.

use montana_node::attest;

fn vectors() -> Vec<(u64, u64, u64)> {
    let at = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../../docs/Montana Consensus.md"
    );
    let md = std::fs::read_to_string(at).expect("the set stands beside the code");
    let from = md
        .find("## The right to a window's seconds")
        .expect("the set states the right");
    let body = &md[from..];
    let till = body[1..].find("\n## ").map_or(body.len(), |end| end + 1);
    let mut out = Vec::new();
    for line in body[..till].lines() {
        let cells: Vec<&str> = line
            .trim()
            .trim_matches('|')
            .split('|')
            .map(str::trim)
            .collect();
        if cells.len() != 3 {
            continue;
        }
        let numbers: Vec<u64> = cells.iter().filter_map(|cell| cell.parse().ok()).collect();
        if let [rounds, chains, worth] = numbers[..] {
            out.push((rounds, chains, worth));
        }
    }
    out
}

#[test]
fn every_frozen_vector_of_the_set_is_reproduced() {
    let held = vectors();
    assert!(
        held.len() >= 7,
        "the set freezes seven vectors and this read {}",
        held.len()
    );
    for (rounds, chains, worth) in held {
        assert_eq!(
            attest::window_value(rounds, chains).expect("a worth"),
            worth,
            "{rounds} rounds over {chains} chains"
        );
    }
}

#[test]
fn a_right_is_priced_by_the_chains_in_force_at_its_height() {
    let secret = [0x5Au8; 32];
    let rounds = mt_genesis::scalar("target_rounds").expect("the Decree names it");
    let step = mt_genesis::scalar("k_step").expect("the Decree names it");
    // At the first height one chain is in force, and a window of the target count of rounds is
    // worth the whole of its seconds; one step of height later two are, and the same rounds summed
    // over both chains are worth half of it.
    let seconds = mt_genesis::scalar("window_seconds").expect("the Decree names it");
    let one = attest::right_of(&secret, 0, rounds).expect("a right");
    assert_eq!(one.worth, seconds);
    let two = attest::right_of(&secret, step, rounds).expect("a right");
    assert_eq!(two.worth, seconds / 2);
}
