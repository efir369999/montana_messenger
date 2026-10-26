// The credit of one coin for every second of a window to every machine living it (Registry,
// CNS-28): windows of one, two and four living machines, each crediting the window's credit to
// every part of its cement, and the supply growing by the credit times the count of the cement and
// by nothing else.
//
// **The level this stands at, named rather than implied.** The scenario the Registry names is a
// network living those windows, and it awaits stage 13. What runs here is the issuance the node
// performs once a window is final — a right read off its decided roll for every part the roll
// names — over rolls of one, two and four parts; the pulse that closes such windows is carried by
// the tests of two, three and four machines living a window, which hold each right they issue to
// the window's credit. No clock enters: nothing here reads one, and nothing the issuance takes could carry one.

use montana_node::attest;

#[test]
fn windows_of_one_two_and_four_living_machines_each_credit_every_second_to_every_part() {
    let credit = attest::window_credit().expect("the Decree names it");
    let mut supply = 0u64;
    for (window, living) in [(1_000u64, 1usize), (1_001, 2), (1_002, 4)] {
        let secrets: Vec<[u8; 32]> = (0..living).map(|at| [0x40 + at as u8; 32]).collect();
        // The roll of the window names the parts of its cement, ascending, each once.
        let mut parts: Vec<[u8; 32]> = secrets
            .iter()
            .map(|secret| mt_derive::nullifier::part(secret, window).expect("a part of the family"))
            .collect();
        parts.sort_unstable();
        parts.dedup();
        assert_eq!(
            parts.len(),
            living,
            "two machines of one cement under one part"
        );

        let mut rights = Vec::new();
        for secret in &secrets {
            let part = mt_derive::nullifier::part(secret, window).expect("a part of the family");
            assert!(parts.binary_search(&part).is_ok());
            let right = attest::right_of(secret, window).expect("a machine of the cement");
            assert_eq!(right.window, window);
            assert_eq!(
                right.worth, credit,
                "a machine of a cement of {living} was credited other than the window's credit"
            );
            rights.push(right);
        }

        // One right per part, each under a nullifier of its own: no machine takes its coin twice
        // and none takes another's.
        let mut nullifiers: Vec<[u8; 32]> = rights.iter().map(|right| right.nullifier).collect();
        nullifiers.sort_unstable();
        nullifiers.dedup();
        assert_eq!(nullifiers.len(), living);

        // What the window adds to the supply is its credit times the count of its cement, in coins.
        let added: u64 = rights.iter().map(|right| right.worth).sum();
        assert_eq!(added, parts.len() as u64 * credit);
        assert_eq!(attest::supply_added(parts.len()), Ok(added));
        supply += added;
    }
    // Three windows, of one, two and four living machines: seven credits, and nothing else.
    assert_eq!(supply, (1 + 2 + 4) * credit);
}
