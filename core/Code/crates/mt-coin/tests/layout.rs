// What crosses the C door: a key's state, the facts of a SEND, and a refusal's code. The bytes are
// frozen from an independent packing (Python struct, little-endian), every field a different value,
// so a swapped pair of fields, a big-endian word or a u128 cut to its low u64 reads back wrong.

use mt_coin::*;

fn hex(b: &[u8]) -> String {
    b.iter().map(|x| format!("{x:02x}")).collect()
}

fn state() -> KeyState {
    KeyState {
        head: core::array::from_fn(|i| i as u8 + 1),
        height: 0x0102_0304_0506_0708,
        birth: 0x1112_1314_1516_1718,
        mint_end: 0x2122_2324_2526_2728,
        proven: 0x3132_3334_3536_3738_393a_3b3c_3d3e_3f40,
        declared: 0x4142_4344_4546_4748_494a_4b4c_4d4e_4f50,
        last_at: 0x5152_5354_5556_5758,
        v3: true,
        minted: 0x6162_6364_6566_6768_696a_6b6c_6d6e_6f70,
    }
}

const STATE_HEX: &str = "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20\
                         0807060504030201\
                         1817161514131211\
                         2827262524232221\
                         403f3e3d3c3b3a393837363534333231\
                         504f4e4d4c4b4a494847464544434241\
                         5857565554535251\
                         01\
                         706f6e6d6c6b6a696867666564636261";

// Refuses an encoder that writes big-endian, swaps two fields, or keeps only the low half of a u128.
#[test]
fn state_layout_is_frozen() {
    assert_eq!(STATE_LEN, 113);
    assert_eq!(hex(&state().encode()), STATE_HEX);
    assert_eq!(KeyState::decode(&state().encode()), Some(state()));
}

// Refuses a decoder that reads any non-zero v3 byte as true: one state, one reading.
#[test]
fn state_v3_flag_is_zero_or_one() {
    let mut b = state().encode();
    b[96] = 0;
    assert_eq!(KeyState::decode(&b).map(|s| s.v3), Some(false));
    b[96] = 2;
    assert_eq!(KeyState::decode(&b), None);
}

fn sent() -> SendFacts {
    SendFacts {
        from: core::array::from_fn(|i| 0xa0 + i as u8),
        amount: 0x7172_7374_7576_7778,
        at: 0x8182_8384_8586_8788,
        to: core::array::from_fn(|i| 0xc0 + i as u8),
        dec: 0x9192_9394_9596_9798,
    }
}

const SENT_HEX: &str = "a0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebf\
                        78777675747372718887868584838281\
                        c0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedf\
                        9897969594939291";

// Refuses an encoder that swaps amount and at, or from and to.
#[test]
fn sent_layout_is_frozen() {
    assert_eq!(SENT_LEN, 88);
    assert_eq!(hex(&sent().encode()), SENT_HEX);
    assert_eq!(SendFacts::decode(&sent().encode()), sent());
}

// Refuses a code table out of the declaration's order, a code 0 that reads as a refusal, and two
// refusals sharing a word.
#[test]
fn refusal_codes_count_from_one_in_order() {
    for (i, r) in Refusal::ALL.iter().enumerate() {
        assert_eq!(usize::from(r.code()), i + 1);
        assert_eq!(Refusal::from_code(r.code()), Some(*r));
    }
    assert_eq!(Refusal::from_code(0), None);
    assert_eq!(Refusal::from_code(19), None);
    assert_eq!(Refusal::NotOnTheHead.code(), 1);
    assert_eq!(Refusal::Allowance.code(), 10);
    assert_eq!(Refusal::Settled.code(), 15);
    assert_eq!(Refusal::NotYet.code(), 17);
    assert_eq!(Refusal::Stopped.code(), 18);
    let mut words: Vec<&str> = Refusal::ALL.iter().map(|r| r.word()).collect();
    words.sort_unstable();
    words.dedup();
    assert_eq!(words.len(), 18);
}

// Refuses a one-reference ledger that answers for any id, or reports settled for another SEND.
#[test]
fn named_ledger_answers_its_reference_alone() {
    let reference = [7u8; 32];
    let other = [8u8; 32];
    let book = Named {
        reference,
        sent: Some(sent()),
        settled: true,
    };
    assert_eq!(book.send(&reference), Some(sent()));
    assert_eq!(book.send(&other), None);
    assert!(book.settled(&reference));
    assert!(!book.settled(&other));
}
