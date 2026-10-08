// The tags and the points of one window: sixteen bytes, derived from a secret and a window, and
// each under its own domain. The set states them in `docs/Montana Canon.md` — the integer form of a
// tag, the seal of a step and the placement of a sender, the point of a channel, the tag of first
// contact — and the family is one shape used four ways.
//
// The negative line of the set is normative and stands as a test below: an implementation that
// derives a tag from anything public produces the value frozen for that mistake instead of the
// value frozen for the secret, and fails the comparison.

use mt_codec::{domain, hash, hash_of_one, size, Domain, Part};

mt_codec::constants! {
    TAG_WIDTHS:
    pub const TAG_BYTES: usize = 16, writes "tag(shared_secret, W)        = SHA-256(\"mt-tag\"  || 0x00 || shared_secret || W_8B_LE)[0 .. 16]";
}

fn head16(full: [u8; 32]) -> [u8; TAG_BYTES] {
    let mut out = [0u8; TAG_BYTES];
    out.copy_from_slice(&full[..TAG_BYTES]);
    out
}

// The width of the secret travels with it: a slice would let a caller hand a value of any length
// into a preimage that also carries a window, and two such lengths would share one string.
fn of_secret_and_window<const N: usize>(
    space: Domain,
    secret: &[u8; N],
    window: u64,
) -> [u8; TAG_BYTES] {
    head16(hash(
        space,
        &[Part::of(secret), Part::of(&window.to_le_bytes())],
    ))
}

// The tag of a pipe: two correspondents hold the secret and nobody else does, so the point where
// their mail stands is computable by them alone and moves with every window.
pub fn tag(shared_secret: &[u8; 32], window: u64) -> [u8; TAG_BYTES] {
    of_secret_and_window(domain::MT_TAG, shared_secret, window)
}

// The label of one step, on the secret two neighbouring machines share.
pub fn step_label(handshake_secret: &[u8; 32], window: u64) -> [u8; TAG_BYTES] {
    of_secret_and_window(domain::MT_STEP, handshake_secret, window)
}

// The point of one window at which the publication of a channel stands: the slot names the channel
// for as long as it is held, while the point lives one window like every other point of this
// network.
pub fn channel_point(channel_slot: &[u8; 32], window: u64) -> [u8; TAG_BYTES] {
    of_secret_and_window(domain::MT_CHANNEL_POINT, channel_slot, window)
}

// The tag of first contact to a claimed name: it stands on a value anyone knowing the name can
// compute, which is why it takes a domain of its own and never collides with a tag standing on a
// secret two parties hold. It carries a request and never a letter.
pub fn first_contact(contact_root: &[u8; size::KEM_PUBLIC_KEY], window: u64) -> [u8; TAG_BYTES] {
    of_secret_and_window(domain::MT_NAME_TAG, contact_root, window)
}

// The identity of a path: the pipe layer of a cell is the one part of it that crosses unchanged,
// so what it hashes to is one value at every hop of one delivery and another value for every other
// delivery. A step label could not serve — it is chosen anew at every hop, and by the neighbour
// rather than by the hop itself, so one owner on two hops would leave two marks and a count of
// owners would be a count of machines.
pub fn path_id(inner: &[u8]) -> [u8; TAG_BYTES] {
    head16(hash_of_one(domain::MT_RELAY_PATH, inner))
}

// The seal a hop attaches to prove distinctness of owners within one delivery: one owner on two
// hops of one path yields one seal, which is what the bound on distinct owners is compared
// against, and two paths of one owner do not join because the pipe layer differs.
pub fn relay_seal(owner_secret: &[u8; 32], path_id: &[u8; TAG_BYTES]) -> [u8; TAG_BYTES] {
    head16(hash(
        domain::MT_RELAY_SEAL,
        &[Part::of(owner_secret), Part::of(path_id)],
    ))
}

// The slot a seal stands at, read from the seal and from nothing a neighbour chose. One owner
// yields one seal on one path and therefore one slot, so two machines of one owner write the same
// value at the same place and the array holds one entry per owner; two owners colliding undercount
// distinctness rather than overcounting it, and a floor of distinct owners fails closed.
pub fn seal_slot(seal: &[u8; TAG_BYTES]) -> Option<u64> {
    Some(int_le(&seal[..8]) % mt_genesis::divisor("path_max")?)
}

// The ephemeral identity a sender's placement is read from. It never leaves the device and appears
// in nothing published; only its reduction places the sender.
pub fn ephemeral_id(sender_secret: &[u8; 32], window: u64) -> [u8; 32] {
    hash(
        domain::MT_SLOT,
        &[Part::of(sender_secret), Part::of(&window.to_le_bytes())],
    )
}

fn int_le(bytes: &[u8]) -> u64 {
    let mut eight = [0u8; 8];
    eight.copy_from_slice(&bytes[..8]);
    u64::from_le_bytes(eight)
}

// The count of chains in force at the height of a window, its division toward zero.
pub fn chains_at(window: u64) -> Option<u64> {
    let cap = mt_genesis::divisor("k_max")?;
    let step = mt_genesis::divisor("k_step")?;
    Some(cap.min(1 + window / step))
}

// A window holds `slot_modulus` residues on each of its chains, and a sender emits at the first
// round of its chain whose index matches its residue. The slot is a round of a chain and never a
// moment of a clock.
pub fn slot_of(sender_secret: &[u8; 32], window: u64) -> Option<u64> {
    let modulus = mt_genesis::divisor("slot_modulus")?;
    let id = ephemeral_id(sender_secret, window);
    Some(int_le(&id[..8]) % modulus)
}

pub fn chain_of(sender_secret: &[u8; 32], window: u64) -> Option<u64> {
    let id = ephemeral_id(sender_secret, window);
    Some(int_le(&id[8..16]) % chains_at(window)?)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hex(bytes: &[u8]) -> String {
        bytes.iter().map(|b| format!("{b:02x}")).collect()
    }

    const W: u64 = 1000;

    #[test]
    fn a_tag_and_the_labels_of_its_steps_are_the_frozen_values() {
        // Canon, "A tag and the labels of its steps".
        assert_eq!(
            hex(&tag(&[0x44u8; 32], W)),
            "1d99467017fe1d0cc7c7ba29df6fd1b6"
        );
        assert_eq!(
            hex(&tag(&[0x44u8; 32], W + 1)),
            "c146445f67c990e25256dd88dfb39a49"
        );
        assert_eq!(
            hex(&step_label(&[0x51u8; 32], W)),
            "4b8cb5c6442a52d0750bfb4fac0ba39d"
        );
        assert_eq!(
            hex(&step_label(&[0x52u8; 32], W)),
            "401d8ab71a2e2554ab30c11aab1ae97d"
        );
        assert_eq!(
            hex(&step_label(&[0x51u8; 32], W + 1)),
            "1cc3ac539a8b1d2701e489455a8b04d5"
        );
    }

    #[test]
    fn the_negative_vector_of_a_tag_is_what_a_public_value_produces() {
        // Canon: the negative line is normative. An implementation deriving a tag from anything
        // public produces this value instead of the one above, and fails the comparison — so the
        // test asserts both that the mistake yields the frozen mistake and that the two differ.
        let public = [0x55u8; 32];
        assert_eq!(hex(&tag(&public, W)), "783b2b17dffaab016d1aca852f60ea3e");
        assert_ne!(tag(&public, W), tag(&[0x44u8; 32], W));
    }

    #[test]
    fn the_point_of_a_channel_and_the_tag_of_first_contact_are_the_frozen_values() {
        // Canon, "A channel: its slot, and the head of a publication", and "The tag of first
        // contact to a claimed name".
        let slot = crate::name::channel_slot(b"alice");
        assert_eq!(
            hex(&channel_point(&slot, W)),
            "f76164012d5601ab75dc478181dd2a13"
        );
        assert_eq!(
            hex(&channel_point(&slot, W + 1)),
            "e4145e07ad3cd0a1bc747e7ae3222ebb"
        );
        assert_eq!(
            hex(&first_contact(&[0xCCu8; size::KEM_PUBLIC_KEY], W)),
            "45468cdd9bcdebe6f622c46257c27fe3"
        );
        assert_eq!(
            hex(&first_contact(&[0xCCu8; size::KEM_PUBLIC_KEY], W + 1)),
            "2751a149c51e219b73fadc85ca8b107b"
        );
    }

    #[test]
    fn the_seal_of_a_step_and_the_placement_of_a_sender_are_the_frozen_values() {
        // Canon, "The seal of a step, and the placement of a sender". The two pipe layers are of
        // the width the Decree derives for one, and a seal stands on the path they identify.
        let first = vec![0x5Au8; 916];
        let second = vec![0x6Bu8; 916];
        assert_eq!(hex(&path_id(&first)), "987275243eca62412618c55d69b2a1a6");
        assert_eq!(hex(&path_id(&second)), "fcdf2fc03faee3894c3238b9d6d21c93");
        assert_eq!(
            hex(&relay_seal(&[0x99u8; 32], &path_id(&first))),
            "1b847b1f5192a58d17722ab7191d58b7"
        );
        assert_eq!(
            hex(&relay_seal(&[0x99u8; 32], &path_id(&second))),
            "dbca283d657a22e135671435e71b36cf"
        );
        assert_eq!(
            seal_slot(&relay_seal(&[0x99u8; 32], &path_id(&first))),
            Some(6)
        );
        assert_eq!(
            seal_slot(&relay_seal(&[0x99u8; 32], &path_id(&second))),
            Some(14)
        );
        let sender = [0xBBu8; 32];
        assert_eq!(
            hex(&ephemeral_id(&sender, W)),
            "e0c80bc1e2aed9036f057863b56a09fd8cd90405ac1dbacd606008cf06b43cbf"
        );
        assert_eq!(slot_of(&sender, W), Some(32));
        assert_eq!(
            hex(&ephemeral_id(&sender, W + 1)),
            "62a174f307d8db5b3529fc9fb9a0216a32e04ca0b5f5eaaff0047cf77a4f7894"
        );
        assert_eq!(slot_of(&sender, W + 1), Some(34));
    }

    #[test]
    fn the_count_of_chains_climbs_by_the_step_and_stops_at_the_cap() {
        let cap = mt_genesis::scalar("k_max").expect("named");
        let step = mt_genesis::scalar("k_step").expect("named");
        assert_eq!(chains_at(0), Some(1));
        assert_eq!(chains_at(step), Some(2));
        assert_eq!(chains_at(7 * step), Some(cap));
        assert_eq!(chains_at(100 * step), Some(cap));
    }

    #[test]
    fn a_placement_is_a_function_of_the_window_and_of_nothing_else() {
        let sender = [0x0Fu8; 32];
        let mut seen = Vec::new();
        for window in 0..64u64 {
            let placed = (slot_of(&sender, window), chain_of(&sender, window));
            assert!(placed.0.is_some() && placed.1.is_some());
            seen.push(placed);
        }
        // Consecutive windows stand at unrelated positions: the run is not a walk of one residue.
        assert!(seen.windows(2).filter(|p| p[0] != p[1]).count() > 40);
    }

    #[test]
    fn every_tag_of_one_secret_and_one_window_stands_apart_by_its_domain() {
        let secret = [0x77u8; 32];
        let mut seen = vec![
            tag(&secret, W),
            step_label(&secret, W),
            channel_point(&secret, W),
            head16(hash(
                domain::MT_NAME_TAG,
                &[Part::of(&secret), Part::of(&W.to_le_bytes())],
            )),
        ];
        let before = seen.len();
        seen.sort_unstable();
        seen.dedup();
        assert_eq!(before, seen.len());
    }

    #[test]
    fn the_chain_of_a_placement_is_pinned_where_the_counts_part() {
        // Canon, "The seal of a step, and the placement of a sender": the first window of the
        // second chain and the first of the eighth. Below the first every count is one and
        // every implementation agrees by accident.
        let step = mt_genesis::scalar("k_step").expect("named");
        let sender = [0xBBu8; 32];
        assert_eq!(chains_at(step), Some(2));
        assert_eq!(chains_at(7 * step), Some(8));
        assert_eq!(
            hex(&ephemeral_id(&sender, step)),
            "354c059669790156d450f1304c1901e57b7dd1a47f8b2f8d5dc78c55e6faddfd"
        );
        assert_eq!(chain_of(&sender, step), Some(0));
        assert_eq!(
            hex(&ephemeral_id(&sender, 7 * step)),
            "d6ec8f75faf35bbfe194a9234301f0081f2563fa788798f04666c2eb395ffeba"
        );
        assert_eq!(chain_of(&sender, 7 * step), Some(1));
        // The named wrong implementations: the slot's bytes read for the chain, and the
        // chain's bytes read from the other end. Each fails both windows above.
        for window in [step, 7 * step] {
            let id = ephemeral_id(&sender, window);
            let k = chains_at(window).expect("named");
            let of_slot_bytes = int_le(&id[..8]) % k;
            let mut backwards = [0u8; 8];
            backwards.copy_from_slice(&id[8..16]);
            backwards.reverse();
            let other_end = u64::from_le_bytes(backwards) % k;
            let held = chain_of(&sender, window).expect("named");
            assert_ne!(of_slot_bytes, held, "W = {window}");
            assert_ne!(other_end, held, "W = {window}");
        }
    }
}

#[cfg(test)]
mod path_tests {
    use super::*;

    #[test]
    fn one_owner_reaches_one_seal_per_path_and_two_paths_do_not_join() {
        let owner = [0x99u8; 32];
        let inner = vec![0x5Au8; 916];
        // The same path read twice is the same seal at the same slot: two hops of one owner
        // leave one mark, which is what a count of owners rests on.
        let once = relay_seal(&owner, &path_id(&inner));
        let again = relay_seal(&owner, &path_id(&inner));
        assert_eq!(once, again);
        assert_eq!(seal_slot(&once), seal_slot(&again));
        // Another path of the same owner joins by nothing.
        let elsewhere = relay_seal(&owner, &path_id(&vec![0x6Bu8; 916]));
        assert_ne!(once, elsewhere);
        // The named wrong implementation: a seal over the label of a step. Every hop is handed a
        // different label, so one owner leaves as many marks as it holds machines.
        let labels = [[0x01u8; TAG_BYTES], [0x02u8; TAG_BYTES]];
        assert_ne!(
            relay_seal(&owner, &labels[0]),
            relay_seal(&owner, &labels[1])
        );
    }

    #[test]
    fn a_slot_stands_inside_the_array_whatever_the_seal_holds() {
        let slots = mt_genesis::scalar("path_max").expect("the Decree names it");
        for byte in 0..=255u8 {
            let slot = seal_slot(&[byte; TAG_BYTES]).expect("named");
            assert!(slot < slots);
        }
    }
}
