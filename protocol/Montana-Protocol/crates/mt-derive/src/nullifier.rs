// Every nullifier of the set: a value that names nobody and can be produced once. The set states
// them in `docs/Montana Canon.md` — the one-time rights of a person, the nullifier of the rate of
// payment, of the rate of action, of a reach into the space of slots, of a machine's part, of a
// right to a share, of an attestation of a beacon — and the difference between them is exactly what
// enters the preimage:
//
//   nothing but the branch      -> a right issued once in a life
//   the branch and the window   -> a right issued once per window
//   the branch, window, index   -> a bound of several per window, the index proven and unpublished
//
// A window where the construction wants none would turn one right into many; an index where the
// construction wants none would turn a bound of one into a bound of many. Both mistakes are
// arithmetic on the preimage, and both are why these stand in one place.

use mt_codec::{domain, hash, Part};

// Issued once to a person and once only: nothing variable enters, so a second attempt presents the
// identical value and collides with the first.
//
// **Both are of the proof hash family, and that is what makes the bound a bound.** Each is
// published by an object whose proof must assert where it came from — an opening spends the
// one-time right to open a record, a candidacy the one-time right to raise a machine — and a
// circuit of this protocol works in that family alone. A value the proof cannot reach is a value a
// claimant draws afresh every time, and a ceiling counted over such values counts nobody.
pub fn open(open_secret: &[u8; 32]) -> [u8; 32] {
    mt_proof::poseidon::hash_bytes(domain::MT_OPEN_NF, open_secret).bytes()
}

pub fn operator(operator_secret: &[u8; 32]) -> [u8; 32] {
    mt_proof::poseidon::hash_bytes(domain::MT_OPERATOR_NF, operator_secret).bytes()
}

// Bounded at several per window: the index is proven below `spends_per_window` and never
// published. Of the proof hash family, since the circuit of a frame proves this derivation.
pub fn rate(rate_secret: &[u8; 32], window: u64, index: u8) -> [u8; 32] {
    let mut preimage = Vec::with_capacity(32 + 8 + 1);
    preimage.extend_from_slice(rate_secret);
    preimage.extend_from_slice(&window.to_le_bytes());
    preimage.push(index);
    mt_proof::poseidon::hash_bytes(domain::MT_RATE_NF, &preimage).bytes()
}

// Bounded at one per window: no index, so a second action of one window collides with the first.
pub fn act(act_secret: &[u8; 32], window: u64) -> [u8; 32] {
    hash(
        domain::MT_ACT_NF,
        &[Part::of(act_secret), Part::of(&window.to_le_bytes())],
    )
}

// The nullifier that spends one version of a record. It takes the blinding factor of that
// version's commitment and the commitment itself, and it takes no window: a version is spent once
// and forever, so a holder cannot act from a version they have already succeeded — which is what
// keeps a change of key from being undone by acting from the record that carried the old one.
//
// **Why the blinding factor and not a branch of the seed.** The factor is drawn afresh for every
// version and lives only in the preimage of that version's commitment; whoever holds the
// commitment cannot derive it, and whoever holds it holds that version. A branch would be one
// value for a life, and a nullifier of a life is a nullifier that spends every version at once.
// Of the proof hash family, since the circuit of an action proves this derivation.
pub fn record(blind: &[u8; 32], record_commit: &[u8; 32]) -> [u8; 32] {
    let mut preimage = Vec::with_capacity(64);
    preimage.extend_from_slice(blind);
    preimage.extend_from_slice(record_commit);
    mt_proof::poseidon::hash_bytes(domain::MT_RECORD_NF, &preimage).bytes()
}

pub fn lookup(lookup_secret: &[u8; 32], window: u64) -> [u8; 32] {
    hash(
        domain::MT_LOOKUP_NF,
        &[Part::of(lookup_secret), Part::of(&window.to_le_bytes())],
    )
}

// The two halves of a machine's secret, from the one absorption of it: the half that spends its
// rights and the half that names it in the tree of admitted machines, in that order. One door
// serves this and the key of a note alike — the halves of a secret that spends are one thing.
pub fn machine_halves(machine_secret: &[u8; 32]) -> ([u8; 32], [u8; 32]) {
    let (spending, naming) =
        mt_proof::poseidon::hash_bytes_twice(domain::MT_KEY_HALVES, machine_secret);
    (spending.bytes(), naming.bytes())
}

// The leaf a machine stands at once it is admitted: the half that names it and nothing else. The
// fold itself stands where the tree that holds it is written and is called from here rather than
// written a second time — a second place for one fold is a second place to move.
pub fn admitted_leaf(machine_secret: &[u8; 32]) -> Option<[u8; 32]> {
    let naming = machine_halves(machine_secret).1;
    Some(mt_proof::admitted::leaf(&naming)?.bytes())
}

// The nullifier of a right and the moment it is extinguished at, of one absorption: a second one
// would be a second reading of the same secret, and a circuit reading a secret twice is a circuit
// where the two readings may differ. Of the proof hash family, for the reason the envelope of a
// note is: a right is redeemed by a frame and by nothing else.
fn credit_and_delay(machine_secret: &[u8; 32], window: u64) -> Option<([u8; 32], [u8; 32])> {
    let spending = machine_halves(machine_secret).0;
    let cells = mt_proof::poseidon::Digest::of_bytes(&spending)?;
    let mut elements = Vec::with_capacity(4 + 1);
    elements.extend_from_slice(cells.elements());
    // The window as one element, for the reason an amount is one: one encoding, one nullifier.
    elements.push(mt_proof::field::F::try_from_u64(window)?);
    let (nullifier, delay) =
        mt_proof::poseidon::hash_elements_twice(domain::MT_CREDIT_NF, &elements);
    Some((nullifier.bytes(), delay.bytes()))
}

pub fn credit(machine_secret: &[u8; 32], window: u64) -> Option<[u8; 32]> {
    Some(credit_and_delay(machine_secret, window)?.0)
}

// Of the proof hash family, because the attestation of presence proves this derivation inside its
// circuit — and the draw of a round reads this value rather than the one-time key for exactly that
// reason: a key comes of a lattice key generation no circuit can assert. It takes the half that
// spends, while the half that names is the leaf of the tree of admitted machines, both of the one
// absorption of the secret.
pub fn part(machine_secret: &[u8; 32], window: u64) -> Option<[u8; 32]> {
    let spending = machine_halves(machine_secret).0;
    let cells = mt_proof::poseidon::Digest::of_bytes(&spending)?;
    let mut elements = Vec::with_capacity(4 + 1);
    elements.extend_from_slice(cells.elements());
    // The window as one element, for the reason an amount is one: one encoding, one nullifier.
    elements.push(mt_proof::field::F::try_from_u64(window)?);
    Some(mt_proof::poseidon::hash_elements(domain::MT_PART_NF, &elements).bytes())
}

// One attestation per machine per beacon: versions of one round yield distinct values, so
// attesting them all is duty and a repeat under one beacon is refused.
pub fn round(machine_secret: &[u8; 32], beacon_id: &[u8; 32]) -> [u8; 32] {
    hash(
        domain::MT_ROUND_NF,
        &[Part::of(machine_secret), Part::of(beacon_id)],
    )
}

// The window a right to a share is accepted in: not early and not late, and a person chooses
// nothing, so nothing about the choice can be read. The spread is the Decree's.
pub fn claim_window(machine_secret: &[u8; 32], window: u64) -> Option<u64> {
    let spread = mt_genesis::divisor("claim_spread")?;
    let delay = credit_and_delay(machine_secret, window)?.1;
    let drawn = u32::from_le_bytes([delay[0], delay[1], delay[2], delay[3]]);
    Some(window + u64::from(drawn) % spread)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hex(bytes: &[u8]) -> String {
        bytes.iter().map(|b| format!("{b:02x}")).collect()
    }

    const W: u64 = 1000;

    #[test]
    fn the_nullifiers_of_the_two_rates_and_of_a_share_are_the_frozen_values() {
        // Canon, "The nullifiers of the two rates, and the nullifier of a share".
        assert_eq!(
            hex(&rate(&[0x55u8; 32], W, 2)),
            "a8a93575275a22c234290aa51717ced537e24014719decd6b3f97268d00ce15e"
        );
        assert_eq!(
            hex(&rate(&[0x55u8; 32], W, 3)),
            "920a6cf0c84798d7eab5b7e6a3e6a3b530163e54a029c0f080488d59bba37518"
        );
        assert_eq!(
            hex(&act(&[0x66u8; 32], W)),
            "8816f366666263bf7a12076ef05815b037a60abe66ff21999daaf246df11129a"
        );
        assert_eq!(
            hex(&act(&[0x66u8; 32], W + 1)),
            "6e08f0c78060ee27fb284376f48451b61db76318a87196e5035c81bc58f70110"
        );
        assert_eq!(
            hex(&credit(&[0x77u8; 32], W).expect("a half of the family")),
            "5b2123e556ede6e1fdf0c2f99baa381a11df3d96b8f1928567c8490e39cb9108"
        );
    }

    #[test]
    fn the_nullifier_of_a_part_and_of_a_reach_are_the_frozen_values() {
        // Canon, "The nullifier of a part, and the identifier of an application", and
        // "The nullifier of a reach into the space of slots".
        assert_eq!(
            hex(&part(&[0x77u8; 32], W).expect("a half of the family")),
            "90e8ec8b288c98ade06b92a0160ab271ab82032e45a283d8ce15f971c711531d"
        );
        assert_eq!(
            hex(&lookup(&[0x88u8; 32], W)),
            "1bc58d1f29771ebde0d6591d6a771158f2aeeec154f0c8f8448ab8ad1dc5541f"
        );
        assert_eq!(
            hex(&lookup(&[0x88u8; 32], W + 1)),
            "54f816fad3496caab8665459e9a2282bef606f8528849fd95434a4d7eaf704b0"
        );
    }

    #[test]
    fn the_moment_of_extinguishing_is_the_frozen_one() {
        // Canon, "The computed moment of extinguishing".
        let secret = [0x77u8; 32];
        assert_eq!(claim_window(&secret, 1000), Some(2284));
        assert_eq!(claim_window(&secret, 1001), Some(1369));
    }

    #[test]
    fn the_moment_stands_inside_the_spread_the_decree_fixes() {
        let spread = mt_genesis::scalar("claim_spread").expect("the Decree names it");
        for window in [0u64, 1, 1000, 20_160, 1_000_000] {
            let claimed = claim_window(&[0x77u8; 32], window).expect("the Decree names the spread");
            assert!(claimed >= window && claimed < window + spread);
        }
    }

    #[test]
    fn a_right_of_a_life_admits_nothing_variable_and_a_right_of_a_window_admits_the_window() {
        // The two shapes the set separates: adding a window to the first would turn a right
        // issued once into a right issued per window, and dropping it from the second the reverse.
        let secret = [0x11u8; 32];
        assert_eq!(open(&secret), open(&secret));
        assert_ne!(open(&secret), operator(&secret));
        assert_ne!(credit(&secret, 1), credit(&secret, 2));
        assert_ne!(act(&secret, 1), act(&secret, 2));
        assert_ne!(rate(&secret, 1, 0), rate(&secret, 1, 1));
    }

    #[test]
    fn every_nullifier_stands_under_its_own_domain_and_none_collides() {
        // One secret and one window through every derivation of this module: eight values, all
        // distinct, because each takes a domain of its own.
        let secret = [0x5Au8; 32];
        let beacon = [0x5Au8; 32];
        let mut seen = vec![
            open(&secret),
            operator(&secret),
            rate(&secret, W, 0),
            act(&secret, W),
            lookup(&secret, W),
            credit(&secret, W).expect("a half of the family"),
            part(&secret, W).expect("a half of the family"),
            round(&secret, &beacon),
        ];
        let before = seen.len();
        seen.sort_unstable();
        seen.dedup();
        assert_eq!(before, seen.len());
    }
}
