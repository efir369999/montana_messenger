// The points and the rights of delivery. The set states them in `docs/Montana Canon.md`,
// "Depositing and collecting" and "The vectors of the messages": the right to take mail from a
// pipe, the points at which a round and a window stand, and the reference of an owner.
//
// A point lives one window and is computable by whoever holds what it stands on and by nobody
// else in advance; a right to collect is sealed to the collector by a value only the two
// correspondents derive, while the right to take a publication is public and presents nothing.

use mt_codec::wide::U256;
use mt_codec::{domain, hash, Part};

mt_codec::constants! {
    DELIVERY_WIDTHS:
    pub const POINT_BYTES: usize = 16, writes "point                            16 B         the tag of a pipe or the point of a channel";
}

fn head16(full: [u8; 32]) -> [u8; POINT_BYTES] {
    let mut out = [0u8; POINT_BYTES];
    out.copy_from_slice(&full[..POINT_BYTES]);
    out
}

pub fn collect_right(shared_secret: &[u8; 32], window: u64) -> [u8; 32] {
    hash(
        domain::MT_COLLECT,
        &[Part::of(shared_secret), Part::of(&window.to_le_bytes())],
    )
}

// The point of a round: the window, the chain, the round and the index, at the widths the set
// fixes — eight, one, four and one.
pub fn round_point(window: u64, chain: u8, round: u32, index: u8) -> [u8; POINT_BYTES] {
    head16(hash(
        domain::MT_ROUND_POINT,
        &[
            Part::of(&window.to_le_bytes()),
            Part::of(&[chain]),
            Part::of(&round.to_le_bytes()),
            Part::of(&[index]),
        ],
    ))
}

// The point a claim of a nullifier stands at: the nullifier, the window and the index. Two frames
// spending one nullifier therefore meet at one point wherever they were sent from, because the
// point follows from the note being spent and never from whoever spends it. The nullifier is
// already published by the frame and names nobody, so the point is a place and not a name.
pub fn notice_point(nullifier: &[u8; 32], window: u64, index: u8) -> [u8; POINT_BYTES] {
    head16(hash(
        domain::MT_NOTICE_POINT,
        &[
            Part::of(nullifier),
            Part::of(&window.to_le_bytes()),
            Part::of(&[index]),
        ],
    ))
}

pub fn window_point(window: u64, index: u8) -> [u8; POINT_BYTES] {
    head16(hash(
        domain::MT_WINDOW_POINT,
        &[Part::of(&window.to_le_bytes()), Part::of(&[index])],
    ))
}

// The key that seals the delivery layer of a cell: no hop holds it, so what a delivery needs of
// itself — which delivery, which block of it, how many blocks — lives where only the two
// correspondents read it. It moves with the window like every other value of this wire.
pub fn pipe_key(shared_secret: &[u8; 32], window: u64) -> [u8; 32] {
    hash(
        domain::MT_PIPE_KEY,
        &[Part::of(shared_secret), Part::of(&window.to_le_bytes())],
    )
}

// The two keys a cell that stands at a point takes. A cell carries one shape whatever it carries,
// so a publication carries both seals like every letter; what differs is only where the keys come
// of. A letter takes them of a secret two correspondents derive and nobody else holds; an object
// of consensus takes them of the point it stands at, which every machine computes for itself from
// the window, the chain, the round and the index. Nothing is thereby weakened: what stands at a
// point is for everyone by construction, and the seals are there so an observer of the wire tells
// a beacon from a letter by nothing at all.
pub fn point_step_key(point: &[u8; POINT_BYTES], window: u64) -> [u8; 32] {
    hash(
        domain::MT_STEP,
        &[Part::of(point), Part::of(&window.to_le_bytes())],
    )
}

pub fn point_pipe_key(point: &[u8; POINT_BYTES], window: u64) -> [u8; 32] {
    hash(
        domain::MT_PIPE_KEY,
        &[Part::of(point), Part::of(&window.to_le_bytes())],
    )
}

// The identifier a delivery carries inside its pipe layer: the tag of the pipe and the root of the
// body it carries, cut to sixteen bytes like every other value of that width.
pub fn delivery_id(tag: &[u8; POINT_BYTES], body_root: &[u8; 32]) -> [u8; POINT_BYTES] {
    head16(hash(
        domain::MT_DELIVERY,
        &[Part::of(tag), Part::of(body_root)],
    ))
}

// The point of the ring an entry is taken from. Ring `j` stands at half the ring, a quarter, and
// so on, moved by an offset drawn from the sender's own secret inside the scale of that ring: the
// halving of distance is what carries a delivery in `log2` of the population, and the offset is
// what keeps the point out of everyone else's reach. Without it the point is a public function of
// the sender's own commitment, and a machine draws the blinding factor of its commitment — so an
// adversary would grind that factor until its machines stood immediately above every one of a
// victim's points.
//
// `period` is the height of the window divided by the period of adaptation. A ring beyond the
// count the Decree fixes is not a ring of this rule, and the answer is nothing rather than a
// shift nobody defined.
pub fn entry_point(
    own_commitment: &[u8; 32],
    sender_secret: &[u8; 32],
    period: u64,
    j: u8,
) -> Option<[u8; 32]> {
    let rings = mt_genesis::scalar("outbound_connections")?;
    if u64::from(j) >= rings {
        return None;
    }
    // The shift of a ring and the scale of its offset both stand below the width of the ring. A
    // ring at the very bottom leaves no scale for an offset at all, so it is refused by name here
    // rather than reached by a subtraction with nothing left to take.
    let shift = 255u32.checked_sub(u32::from(j))?;
    let scale = shift.checked_sub(1)?;
    let drawn = hash(
        domain::MT_ENTRY,
        &[
            Part::of(sender_secret),
            Part::of(&period.to_le_bytes()),
            Part::of(&[j]),
        ],
    );
    let offset = U256::from_be_bytes(&drawn).low_bits(scale)?;
    let own = U256::from_be_bytes(own_commitment);
    Some(
        own.wrapping_add(U256::bit(shift)?)
            .wrapping_add(offset)
            .to_be_bytes(),
    )
}

// The entries of a sender for one period: ring by ring, the machine standing above the point of
// that ring, wrapping at the top of the ring the way the holder of a tag wraps, and advancing to
// the next unused machine where a point lands on one already taken. The set holds one entry per
// ring or as many as the sender knows, whichever is fewer.
pub fn entries(
    own_commitment: &[u8; 32],
    sender_secret: &[u8; 32],
    period: u64,
    known: &[[u8; 32]],
) -> Option<Vec<[u8; 32]>> {
    let rings = mt_genesis::scalar("outbound_connections")?;
    let mut held: Vec<[u8; 32]> = Vec::new();
    for j in 0..rings.min(u64::from(u8::MAX)) {
        if held.len() == known.len() {
            break;
        }
        let Some(point) = entry_point(own_commitment, sender_secret, period, j as u8) else {
            break;
        };
        let free = || known.iter().filter(|c| !held.contains(c));
        let taken = match free().filter(|c| **c > point).min() {
            Some(above) => *above,
            None => match free().min() {
                Some(least) => *least,
                None => break,
            },
        };
        held.push(taken);
    }
    Some(held)
}

#[cfg(test)]
mod tests {
    use super::*;
    use sha2::Digest as _;

    fn hex(bytes: &[u8]) -> String {
        bytes.iter().map(|b| format!("{b:02x}")).collect()
    }

    // PANIC-OK: a test helper over the Decree of this tree, which holds every count it names.
    fn held_of(
        own: &[u8; 32],
        sender: &[u8; 32],
        period: u64,
        known: &[[u8; 32]],
    ) -> Vec<[u8; 32]> {
        entries(own, sender, period, known).expect("the Decree holds the count of rings")
    }

    fn decode(text: &str) -> [u8; 32] {
        let mut out = [0u8; 32];
        for (i, slot) in out.iter_mut().enumerate() {
            *slot = u8::from_str_radix(&text[i * 2..i * 2 + 2], 16).expect("hex of a test literal");
        }
        out
    }

    const W: u64 = 1000;

    #[test]
    fn the_right_and_the_two_points_are_the_frozen_values() {
        // Canon, "The vectors of the messages".
        assert_eq!(
            hex(&collect_right(&[0x22u8; 32], W)),
            "0bf7dd6548455ec0650828135980e7dc9b05180d459ca2bae0006def6159ae39"
        );
        assert_eq!(
            hex(&round_point(W, 0, 7, 0)),
            "534c4a72958d71edd7425654f881f341"
        );
        assert_eq!(hex(&window_point(W, 0)), "a2e9b61c437f761c4bb35fc87c98af79");
    }

    #[test]
    fn every_point_moves_with_every_input_it_names() {
        assert_ne!(round_point(W, 0, 7, 0), round_point(W + 1, 0, 7, 0));
        assert_ne!(round_point(W, 0, 7, 0), round_point(W, 1, 7, 0));
        assert_ne!(round_point(W, 0, 7, 0), round_point(W, 0, 8, 0));
        assert_ne!(round_point(W, 0, 7, 0), round_point(W, 0, 7, 1));
        assert_ne!(window_point(W, 0), window_point(W + 1, 0));
        assert_ne!(window_point(W, 0), window_point(W, 1));
        assert_ne!(
            collect_right(&[0x22u8; 32], W),
            collect_right(&[0x22u8; 32], W + 1)
        );
    }

    #[test]
    fn the_points_of_the_rings_are_the_frozen_values() {
        // Canon, "The point of a ring of entries".
        let own = decode("08e640011db3702bb5ea5f1a3ea6aa62d7aa274b4acfcada27346e093d60fdc5");
        let mut reversed = own;
        reversed.reverse();
        let sender = [0xBBu8; 32];
        assert_eq!(
            hex(&entry_point(&own, &sender, 3, 0).unwrap()),
            "991c058327cbe19ac1b39ee1b4b9b0a1f0b8510fcdf662e9810a8084d9ac83be"
        );
        assert_eq!(
            hex(&entry_point(&own, &sender, 3, 1).unwrap()),
            "6672a6c3c858e84be4dc720ae1bec56580b8fda84efa73c13f9d236e2d21a943"
        );
        assert_eq!(
            hex(&entry_point(&own, &sender, 3, 23).unwrap()),
            "08e641690b245dc1d89caf7793c94d4110fb4f1eb2c324186ed6f5953d7dd8b8"
        );
        assert_eq!(
            hex(&entry_point(&reversed, &sender, 3, 0).unwrap()),
            "563325bf1386a596e6940f11c13ab1167bb8d0029d8682c48546c5989d8c6c01"
        );
        assert_eq!(
            hex(&entry_point(&own, &sender, 4, 0).unwrap()),
            "ae1ff71e8e7cdba1c960a2eb52c4df5c978b65c646220957a0ba5713f6143836"
        );
    }

    #[test]
    fn the_named_wrong_implementations_of_a_point_answer_elsewhere() {
        let own = decode("08e640011db3702bb5ea5f1a3ea6aa62d7aa274b4acfcada27346e093d60fdc5");
        let sender = [0xBBu8; 32];
        let point = entry_point(&own, &sender, 3, 0).unwrap();
        // The offset dropped: the bare point of the ring.
        let bare = U256::from_be_bytes(&own)
            .wrapping_add(U256::bit(255).unwrap())
            .to_be_bytes();
        assert_ne!(point, bare);
        // The shift taken as `j` where the rule takes `j + 1`.
        assert_ne!(entry_point(&own, &sender, 3, 1).unwrap(), {
            let drawn = hash(
                domain::MT_ENTRY,
                &[
                    Part::of(&sender),
                    Part::of(&3u64.to_le_bytes()),
                    Part::of(&[1u8]),
                ],
            );
            U256::from_be_bytes(&own)
                .wrapping_add(U256::bit(255).unwrap())
                .wrapping_add(U256::from_be_bytes(&drawn).low_bits(253).unwrap())
                .to_be_bytes()
        });
        // The commitment read from the low end.
        let mut reversed = own;
        reversed.reverse();
        assert_ne!(point, entry_point(&reversed, &sender, 3, 0).unwrap());
        // A ring the Decree does not hold is not a ring of this rule.
        assert_eq!(entry_point(&own, &sender, 3, 24), None);
        assert_eq!(entry_point(&own, &sender, 3, u8::MAX), None);
    }

    #[test]
    fn a_high_commitment_wraps_at_the_top_of_the_ring() {
        // The reversal stands in the upper half, so the point of its first ring passes the top.
        let own = decode("c5fd603d096e3427dacacf4a4b27aad762aaa63e1a5feab52b70b31d0140e608");
        let sender = [0xBBu8; 32];
        let point = entry_point(&own, &sender, 3, 0).unwrap();
        assert!(
            point < own,
            "the sum passed the top and continued from the bottom"
        );
    }

    #[test]
    fn the_entries_are_distinct_and_bounded_by_what_the_sender_knows() {
        let own = decode("08e640011db3702bb5ea5f1a3ea6aa62d7aa274b4acfcada27346e093d60fdc5");
        let sender = [0xBBu8; 32];
        // The population is spread over the whole ring rather than packed at its bottom: a set of
        // consecutive small values would leave every point above every commitment, the search
        // would wrap every time, and two senders would hold one set — the test would pass while
        // measuring nothing.
        let known: Vec<[u8; 32]> = (0u16..300)
            .map(|i| {
                let mut hasher = sha2::Sha256::new();
                sha2::Digest::update(&mut hasher, b"a machine of the ring");
                sha2::Digest::update(&mut hasher, i.to_be_bytes());
                let mut c = [0u8; 32];
                c.copy_from_slice(&sha2::Digest::finalize(hasher));
                c
            })
            .collect();
        let held = held_of(&own, &sender, 3, &known);
        assert_eq!(held.len(), 24);
        let mut sorted = held.clone();
        sorted.sort_unstable();
        sorted.dedup();
        assert_eq!(
            sorted.len(),
            held.len(),
            "a machine is held at one ring only"
        );
        // Fewer machines than rings: the set holds what the sender knows and no repetition.
        let few = &known[..5];
        let held = held_of(&own, &sender, 3, few);
        assert_eq!(held.len(), 5);
        // Another sender standing at the same commitment holds another set.
        let other = held_of(&own, &[0xCCu8; 32], 3, &known);
        assert_ne!(other, held_of(&own, &sender, 3, &known));
        // The set rotates with the period and with nothing else.
        assert_ne!(
            held_of(&own, &sender, 4, &known),
            held_of(&own, &sender, 3, &known)
        );
    }

    #[test]
    fn a_point_of_a_round_is_not_a_point_of_a_window_under_one_input() {
        // The two domains are what keep the families apart; without them the round of index
        // zero and the window of the same index would collide.
        assert_ne!(round_point(W, 0, 0, 0), window_point(W, 0));
    }
}
