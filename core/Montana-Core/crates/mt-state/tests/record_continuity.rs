use mt_state::layout::{Layout, Record};

fn record(bitmap: u64) -> Record {
    Record {
        segment_bitmap: bitmap,
        last_active_segment: 100,
        opened_window: 0,
        own_height: 0,
        fabric_root: [0; 32],
        suite_id: 1,
        current_pubkey: vec![0; mt_codec::size::SIGNING_PUBLIC_KEY],
        blind: [0; 32],
    }
}

fn limit() -> u32 {
    mt_genesis::scalar("max_entry_segments").unwrap() as u32
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
            forged.segments_lived(100 + distance),
            0,
            "distance {distance}"
        );
    }
}

#[test]
fn lawful_segments_survive_round_trip_and_expire_only_by_the_shift() {
    let width = limit();
    let bits = u64::MAX.checked_shr(u64::BITS - width).unwrap();
    let held = record(bits);
    let bytes = held.bytes().unwrap();
    let replayed = Record::parse(&bytes).unwrap();
    assert_eq!(replayed.bytes().unwrap(), bytes);
    for distance in 0..=u64::BITS {
        let expected = width.saturating_sub(distance);
        assert_eq!(held.segments_lived(100 + distance), expected);
        assert_eq!(replayed.segments_lived(100 + distance), expected);
    }
    assert_eq!(held.segments_lived(99), 0);
}

#[test]
fn replaying_a_record_after_a_partition_does_not_restore_its_expired_bits() {
    let width = limit();
    let held = record((1u64 << width) - 1);
    let bytes = held.bytes().unwrap();
    let current = held.last_active_segment + width;
    for _ in 0..3 {
        let replayed = Record::parse(&bytes).unwrap();
        assert_eq!(replayed.segments_lived(current), 0);
        assert_eq!(replayed.last_active_segment, held.last_active_segment);
        assert_eq!(replayed.segment_bitmap, held.segment_bitmap);
    }
}
