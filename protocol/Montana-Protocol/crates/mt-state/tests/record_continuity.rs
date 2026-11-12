use mt_state::layout::{Layout, Record};

fn record(bitmap: u64) -> Record {
    Record {
        segment_bitmap: bitmap,
        last_active_segment: 100,
        opened_window: 0,
        own_height: 0,
        operator_nf: [0; 32],
        fabric_root: [0; 32],
        suite_id: 1,
        current_pubkey: vec![0; mt_codec::size::SIGNING_PUBLIC_KEY],
        blind: [0; 32],
    }
}

fn limit() -> u32 {
    mt_genesis::scalar("max_entry_segments").unwrap() as u32
}

fn floor() -> u32 {
    mt_genesis::scalar("continuity_segments").unwrap() as u32
}

#[test]
fn reserved_segments_are_refused_when_read() {
    for bit in limit()..u64::BITS {
        assert!(
            Record::parse(&record(1u64 << bit).encode()).is_err(),
            "reserved bit {bit}"
        );
    }
}

#[test]
fn reserved_segments_cannot_be_published_as_record_bytes() {
    for bit in limit()..u64::BITS {
        assert!(record(1u64 << bit).bytes().is_err(), "reserved bit {bit}");
    }
}

#[test]
fn fabricated_future_segments_cannot_age_into_lived_continuity() {
    let forged = record(1u64 << limit());
    for distance in 0..=limit() {
        assert_eq!(
            forged.segments_lived(100 + distance, limit()),
            0,
            "distance {distance}"
        );
    }
}

// The newest segment is bit 0 and a reading keeps the low bits of the period in force (Canon, "The
// rules of continuity", rules 2 and 3; constitution records 297 and 300). A record that lived every
// segment of the width loses one segment of the period for every segment that passes. One that lived
// only its newest keeps it until the period leaves it behind, where a reader shifting right would
// lose it at the next segment.
#[test]
fn lawful_segments_survive_round_trip_and_leave_the_period_by_the_shift() {
    let width = limit();
    let floor = floor();
    let bits = u64::MAX.checked_shr(u64::BITS - width).unwrap();
    let held = record(bits);
    let bytes = held.bytes().unwrap();
    let replayed = Record::parse(&bytes).unwrap();
    assert_eq!(replayed.bytes().unwrap(), bytes);
    for distance in 0..=u64::BITS {
        for (in_force, expected) in [
            (width, width.saturating_sub(distance)),
            (floor, floor.saturating_sub(distance)),
        ] {
            assert_eq!(held.segments_lived(100 + distance, in_force), expected);
            assert_eq!(replayed.segments_lived(100 + distance, in_force), expected);
        }
    }
    assert_eq!(held.segments_lived(99, width), 0);
    let newest = record(1);
    for distance in 0..floor {
        assert_eq!(newest.segments_lived(100 + distance, floor), 1);
    }
    assert_eq!(newest.segments_lived(100 + floor, floor), 0);
}

// A record replayed after a partition carries the segment it was written against, and the period in
// force moves on without it: every bit leaves the period of fourteen once fourteen segments have
// passed, and replaying the bytes restores none of them.
#[test]
fn replaying_a_record_after_a_partition_does_not_restore_its_expired_bits() {
    let width = limit();
    let floor = floor();
    let held = record((1u64 << width) - 1);
    let bytes = held.bytes().unwrap();
    let current = held.last_active_segment + floor;
    for _ in 0..3 {
        let replayed = Record::parse(&bytes).unwrap();
        assert_eq!(replayed.segments_lived(current - 1, floor), 1);
        assert_eq!(replayed.segments_lived(current, floor), 0);
        assert_eq!(replayed.last_active_segment, held.last_active_segment);
        assert_eq!(replayed.segment_bitmap, held.segment_bitmap);
    }
}

// The successor an action writes is a record the layout accepts, whatever the distance, and a gate
// reads the segment acted in as lived in the period that ends with it (rule 2).
#[test]
fn an_action_leaves_a_lawful_record_that_counts_its_own_segment() {
    let width = limit();
    let full = record((1u64 << width) - 1);
    for distance in [0, 1, 13, 14, 55, 56, 63, 64, 1_000] {
        let (bitmap, last) = full.continuity_after_action(100 + distance).unwrap();
        let next = Record {
            segment_bitmap: bitmap,
            last_active_segment: last,
            ..full.clone()
        };
        assert!(next.bytes().is_ok(), "distance {distance}");
        assert_eq!(next.segments_lived(last, 1), 1, "distance {distance}");
        // The segments of the full record still inside the width, and the one acted in.
        let kept = if distance == 0 {
            width
        } else {
            width.saturating_sub(distance) + 1
        };
        assert_eq!(
            next.segments_lived(last, width),
            kept,
            "distance {distance}"
        );
    }
}
