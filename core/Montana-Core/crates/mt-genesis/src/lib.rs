// The numbers of Montana live here and nowhere else in this tree. The set states them in
// `docs/Montana Canon.md`, "Parameters of the Genesis Decree"; this is their one transcription,
// and every other crate reads them from `decree()` rather than writing one of its own.
//
// The encoding is the Decree's own rule: every parameter as an unsigned eight-byte little-endian
// integer in the order the table stands; a ratio as two such integers, numerator first; the
// emission schedule as its count of rows in two bytes followed by each row as two such integers,
// height then mint, ascending; a parameter written as a hash as its thirty-two bytes.

#![forbid(unsafe_code)]
#![deny(clippy::all)]

pub const TAU2: u64 = 20_160;

#[derive(Clone, PartialEq, Eq, Debug)]
pub enum Entry {
    Scalar(&'static str, u64),
    Ratio(&'static str, u64, u64),
    Schedule(&'static str, &'static [(u64, u64)]),
    Hash(&'static str, [u8; 32]),
    // A parameter the set names and has not published. It carries no value — not a zero, not a
    // stand-in, nothing — because a value written in place of one that does not exist is a value
    // some build somewhere will ship, and the whole of the Decree is what the Genesis State Hash
    // binds. What stands here is the name and the reason, and the encoding refuses while it does.
    Unpublished(&'static str, &'static str),
}

impl Entry {
    // The name, read in a constant: what the assertions below stand on cannot go through a
    // method a constant cannot call.
    pub const fn name_const(&self) -> &'static str {
        match self {
            Entry::Scalar(n, _)
            | Entry::Ratio(n, _, _)
            | Entry::Schedule(n, _)
            | Entry::Hash(n, _)
            | Entry::Unpublished(n, _) => n,
        }
    }

    pub fn name(&self) -> &'static str {
        match self {
            Entry::Scalar(n, _)
            | Entry::Ratio(n, _, _)
            | Entry::Schedule(n, _)
            | Entry::Hash(n, _)
            | Entry::Unpublished(n, _) => n,
        }
    }

    pub fn encoded_len(&self) -> Option<usize> {
        match self {
            Entry::Scalar(..) => Some(8),
            Entry::Ratio(..) => Some(16),
            Entry::Schedule(_, rows) => Some(2 + 16 * rows.len()),
            Entry::Hash(..) => Some(32),
            Entry::Unpublished(..) => None,
        }
    }

    fn encode_into(&self, out: &mut Vec<u8>) {
        match self {
            Entry::Unpublished(..) => {}
            Entry::Scalar(_, v) => out.extend_from_slice(&v.to_le_bytes()),
            Entry::Ratio(_, num, den) => {
                out.extend_from_slice(&num.to_le_bytes());
                out.extend_from_slice(&den.to_le_bytes());
            }
            Entry::Schedule(_, rows) => {
                out.extend_from_slice(&(rows.len() as u16).to_le_bytes());
                for (height, mint) in rows.iter() {
                    out.extend_from_slice(&height.to_le_bytes());
                    out.extend_from_slice(&mint.to_le_bytes());
                }
            }
            Entry::Hash(_, h) => out.extend_from_slice(h),
        }
    }
}

// The order is part of the value: it is what the Genesis State Hash binds.
// The two blocks of the Decree. A row stands in exactly one of them: the parameters, which the
// Genesis State Hash binds and no boundary between eras reaches, and the forms, which fix the
// shape of what crosses the wire and which a boundary may move.
pub const PARAMETERS: &[Entry] = &[
    Entry::Scalar("hash_bytes", 32),
    Entry::Scalar("tau2", TAU2),
    Entry::Schedule("emission_schedule", &[(0, 13_000_000_000)]),
    Entry::Scalar("slot_modulus", 64),
    Entry::Scalar("retarget_period", TAU2),
    Entry::Scalar("retarget_damping", 4),
    Entry::Scalar("retarget_step_bound", 4),
    Entry::Scalar("continuity_period", TAU2),
    Entry::Scalar("continuity_segments", 14),
    Entry::Scalar("segment_windows", TAU2 / 14),
    Entry::Ratio("continuity_required", 2, 3),
    Entry::Scalar("max_entry_segments", 56),
    Entry::Scalar("selection_interval", 336),
    Entry::Ratio("confirmation_quorum", 67, 100),
    Entry::Scalar("committee_divisor", 256),
    Entry::Scalar("admission_divisor", 130),
    Entry::Ratio("adaptive_entry_threshold", 1, 100),
    Entry::Scalar("adaptive_entry_multiplier", 100),
    Entry::Scalar("membership_term", 2 * TAU2),
    Entry::Scalar("candidate_expiry", 3 * TAU2),
    Entry::Scalar("record_bucket_base", 4),
    Entry::Scalar("frames_per_window", 273),
    Entry::Scalar("name_chain_length", 128),
    Entry::Scalar("name_renew_windows", 6 * TAU2),
    Entry::Scalar("name_reveal_windows", 2 * TAU2),
    Entry::Scalar("name_min_length", 4),
    Entry::Scalar("proving_lag", 2),
    Entry::Scalar("proving_horizon", 128),
    Entry::Scalar("spends_per_window", 4),
    Entry::Scalar("claim_spread", 1_440),
    Entry::Scalar("max_openings_per_window", 256),
    Entry::Scalar("hop_min", 3),
    Entry::Scalar("outbound_connections", 24),
    Entry::Scalar("inbound_slots", 96),
    Entry::Scalar("target_rounds", 284),
    Entry::Scalar("round_floor", 50),
    Entry::Scalar("unproven_depth", 8),
    Entry::Scalar("k_max", 8),
    Entry::Scalar("k_step", 96 * TAU2),
    Entry::Scalar("cascade_width", 3),
    Entry::Scalar("fold_arity", 2),
    Entry::Scalar("consensus_replicas", 3),
    Entry::Scalar("recovery_onset_multiple", 10),
    Entry::Hash(
        "air_hash",
        [
            0x2b, 0x78, 0x8d, 0xf1, 0xd2, 0xe2, 0x03, 0xad, 0x78, 0x60, 0x42, 0x28, 0x37, 0x10,
            0xff, 0xcc, 0xec, 0x07, 0x05, 0x6a, 0xfe, 0x67, 0x23, 0x5d, 0x73, 0x5a, 0x2d, 0xda,
            0xab, 0x83, 0x85, 0x2a,
        ],
    ),
];

pub const FORMS: &[Entry] = &[
    Entry::Scalar("spends_per_frame", 3),
    Entry::Scalar("spend_inputs", 2),
    Entry::Scalar("spend_outputs", 2),
    Entry::Scalar("items_per_spend", 5),
    Entry::Scalar("note_tree_depth", 40),
    Entry::Scalar("name_max_length", 32),
    Entry::Ratio("redundancy", 1, 4),
    Entry::Scalar("cell_bytes", 1_232),
    Entry::Scalar("erasure_group", 16),
    Entry::Scalar("path_max", 15),
];

// The parameters, encoded. There is no encoding of an incomplete Decree: what a chain opens on is
// every parameter the set names, and a table missing one of them opens nothing.
// The width of the block of parameters, read off the rows rather than off what an encoder
// produced: what binds the Genesis State Hash is offered at this width, and an encoding that
// disagrees with the rows is refused where it enters the preimage instead of being hashed.
pub fn encoded_len() -> Option<usize> {
    if !unpublished().is_empty() {
        return None;
    }
    Some(PARAMETERS.iter().filter_map(Entry::encoded_len).sum())
}

pub fn encode() -> Option<Vec<u8>> {
    if !unpublished().is_empty() {
        return None;
    }
    let mut out = Vec::with_capacity(PARAMETERS.iter().filter_map(Entry::encoded_len).sum());
    for entry in PARAMETERS {
        entry.encode_into(&mut out);
    }
    Some(out)
}

// The parameters the set names and has not published, and why. An empty answer is the day a chain
// can be opened at all.
pub fn unpublished() -> Vec<(&'static str, &'static str)> {
    PARAMETERS
        .iter()
        .chain(FORMS.iter())
        .filter_map(|e| match e {
            Entry::Unpublished(name, what) => Some((*name, *what)),
            _ => None,
        })
        .collect()
}

// The width of the parameters that are published, read off the rows rather than off what an
// encoder produced — the same rule the complete block stands under, so the door that hashes them
// refuses an encoding disagreeing with the rows rather than hashing it.
pub fn published_len() -> usize {
    PARAMETERS.iter().filter_map(Entry::encoded_len).sum()
}

// The parameters as they stand, whether or not the table is complete: what the gate of the set
// compares while a parameter is unpublished, and what says the encoding of the rest has not moved.
pub fn encode_published() -> Vec<u8> {
    let mut out = Vec::with_capacity(PARAMETERS.iter().filter_map(Entry::encoded_len).sum());
    for entry in PARAMETERS {
        entry.encode_into(&mut out);
    }
    out
}

// No name stands in both blocks, and no name stands twice in one. The reader below takes the
// parameters first and would answer with a parameter for a name a form also carried, so a repeat
// across the two blocks is a form nobody can read — and that is refused here, where the rows are
// written, rather than by a test that can be deleted.
const fn no_two_rows_carry_one_name() -> bool {
    let mut i = 0;
    while i < PARAMETERS.len() + FORMS.len() {
        let left = row_name(i);
        let mut j = i + 1;
        while j < PARAMETERS.len() + FORMS.len() {
            if same_name(left, row_name(j)) {
                return false;
            }
            j += 1;
        }
        i += 1;
    }
    true
}

const fn row_name(at: usize) -> &'static str {
    if at < PARAMETERS.len() {
        PARAMETERS[at].name_const()
    } else {
        FORMS[at - PARAMETERS.len()].name_const()
    }
}

const fn same_name(a: &str, b: &str) -> bool {
    let (a, b) = (a.as_bytes(), b.as_bytes());
    if a.len() != b.len() {
        return false;
    }
    let mut i = 0;
    while i < a.len() {
        if a[i] != b[i] {
            return false;
        }
        i += 1;
    }
    true
}

// PANIC-OK, and of the kind that never runs: these three stand in constants, so what they refuse
// is refused where the rows are written and the build stops with the reason named. A panic of a
// constant is a compiler saying no, not a machine falling over.
const _: () = {
    assert!(
        no_two_rows_carry_one_name(),
        "two rows of the Decree carry one name"
    );
};

// No row of this Decree bounds the count of machines, and none may be added. What the seal array
// of a cell bounds is the reach of one delivery — `2^(path_max - hop_min)` — and that is a row of
// the forms, which a boundary between eras widens at the price the set writes beside it. A number
// frozen in the parameters would make the machine past it unlawful rather than slow, and the block
// a chain opens on is the one place a bound can never be moved from.

pub fn get(name: &str) -> Option<&'static Entry> {
    PARAMETERS
        .iter()
        .chain(FORMS.iter())
        .find(|e| e.name() == name)
}

pub fn scalar(name: &str) -> Option<u64> {
    match get(name) {
        Some(Entry::Scalar(_, v)) => Some(*v),
        _ => None,
    }
}

// A row read as a divisor: a value of zero answers nothing rather than dividing. The guard stands
// here and not at the uses, because a guard written at some of them is what tells a reader that
// the others were thought about — and every one of these rows is a row the gate holds, so what
// this closes is the shape of the code rather than a reachable state.
pub fn divisor(name: &str) -> Option<u64> {
    match scalar(name) {
        Some(0) | None => None,
        Some(value) => Some(value),
    }
}

pub fn ratio(name: &str) -> Option<(u64, u64)> {
    match get(name) {
        Some(Entry::Ratio(_, num, den)) => Some((*num, *den)),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn s(name: &str) -> u64 {
        super::scalar(name).expect("the Decree names it")
    }

    #[test]
    fn the_block_is_the_length_the_rule_gives_and_the_complete_table_encodes() {
        let expected: usize = PARAMETERS.iter().filter_map(Entry::encoded_len).sum();
        assert_eq!(encode_published().len(), expected);
        // The Decree is complete — the last row to land was the hash binding the constraint sets —
        // so the whole table encodes, and the published block is the whole block.
        assert_eq!(encode().map(|b| b.len()), Some(expected));
        assert_eq!(unpublished().len(), 0);
    }

    #[test]
    fn the_derived_parameters_agree_with_what_they_derive_from() {
        assert_eq!(
            s("segment_windows") * s("continuity_segments"),
            s("continuity_period")
        );
        assert_eq!(
            s("items_per_spend"),
            s("spend_inputs") + s("spend_outputs") + 1
        );
        assert_eq!(s("claim_spread"), s("segment_windows"));
        assert_eq!(s("retarget_period"), TAU2);
    }

    #[test]
    fn the_encoding_is_little_endian_and_in_order() {
        let bytes = encode_published();
        // The block opens with its first row and the rows follow in the order the Decree writes
        // them: what is checked is that order, read off the table rather than pinned by a place a
        // new row would move.
        let mut at = 0usize;
        for entry in PARAMETERS.iter().take(2) {
            let width = entry.encoded_len().expect("a published row");
            if let Entry::Scalar(_, value) = entry {
                assert_eq!(&bytes[at..at + 8], &value.to_le_bytes());
            }
            if let Entry::Schedule(_, rows) = entry {
                assert_eq!(
                    &bytes[at..at + 2],
                    &(rows.len() as u16).to_le_bytes(),
                    "a schedule opens with its count of rows"
                );
            }
            at += width;
        }
        // The block ends at the last published row and nothing stands after it: an unpublished
        // parameter writes no bytes, rather than writing bytes nobody agreed to. Which row that
        // is, is read off the table — a test naming one would fail the day a row joined the block
        // rather than the day the encoding moved, which is the whole difference between a check
        // and a place.
        let last = PARAMETERS
            .iter()
            .rev()
            .find(|e| e.encoded_len().is_some())
            .expect("the block holds a published row");
        let width = last.encoded_len().expect("a published row");
        let mut tail = Vec::new();
        last.encode_into(&mut tail);
        assert_eq!(&bytes[bytes.len() - width..], &tail[..]);
    }

    #[test]
    fn a_name_the_decree_does_not_hold_yields_nothing() {
        assert!(super::scalar("committee_size").is_none());
        assert!(ratio("tau2").is_none());
    }

    #[test]
    fn the_quorum_leaves_a_third_of_standing_to_convict_itself() {
        // Two quorums of one height intersect in 2q - 1 of standing, and the sanction needs that
        // to exceed a third: 2*num/den - 1 > 1/3, which in integers is 3*num > 2*den. Written with
        // a division it would pass by truncation rather than by the property.
        let (num, den) = ratio("confirmation_quorum").expect("the Decree names it");
        assert!(3 * num > 2 * den);
    }

    #[test]
    fn an_unpublished_parameter_carries_no_value_of_any_kind() {
        // Not a zero, not a stand-in: the rule survives the day the table no longer holds such a
        // row, so it is held against a row of its own rather than against the published Decree.
        let held = Entry::Unpublished("a_parameter_of_a_test", "why it waits");
        assert_eq!(held.encoded_len(), None);
        // And the published table holds the hash that ended the waiting, as thirty-two bytes.
        let Some(Entry::Hash(name, value)) = get("air_hash") else {
            panic!("the Decree publishes it");
        };
        assert_eq!(*name, "air_hash");
        assert_eq!(value.len(), 32);
        assert_eq!(scalar("air_hash"), None);
        assert_eq!(ratio("air_hash"), None);
    }
}
