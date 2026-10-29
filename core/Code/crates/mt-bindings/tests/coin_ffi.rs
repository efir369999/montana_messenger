// The coin doors a node outside Rust folds by (mt_coin_step, mt_coin_at_now, mt_coin_refusal,
// mt_coin_fold): the state and the SEND's facts cross as bytes, so each case reads the answer back
// through the bytes and checks it against the spec's numbers, not against the library alone.

use mt_bindings::ffi_c::*;
use mt_bindings::{MT_ERR_BUFFER_TOO_SMALL, MT_ERR_DECODE, MT_ERR_NULL_PTR, MT_OK};
use mt_coin::*;
use sha2::{Digest, Sha256};
use std::ptr;

const C: u64 = TX_SECOND_CUT;
const D: u64 = TX_TIME_CUT;

fn v3(
    kind: u8,
    amount: u64,
    prev: [u8; 32],
    to: [u8; 32],
    reference: [u8; 32],
    t0: u64,
    t1: u64,
) -> Vec<u8> {
    let mut r = vec![0xEE; TX3_LEN];
    r[..4].copy_from_slice(TX_MAGIC);
    r[4] = 3;
    r[5] = kind;
    r[6..14].copy_from_slice(&amount.to_le_bytes());
    r[38..70].copy_from_slice(&prev);
    r[70..102].copy_from_slice(&if kind == 1 { [0x55; 32] } else { [0; 32] });
    r[102..134].copy_from_slice(&to);
    r[134..166].copy_from_slice(&reference);
    r[166..174].copy_from_slice(&t0.to_le_bytes());
    r[174..182].copy_from_slice(&t1.to_le_bytes());
    r[182..2134].copy_from_slice(&[0x42; 1952]);
    r
}

fn v2(amount: u64, prev: [u8; 32]) -> Vec<u8> {
    let mut r = vec![0xEE; TX2_LEN];
    r[..4].copy_from_slice(TX_MAGIC);
    r[4] = 2;
    r[5..13].copy_from_slice(&amount.to_le_bytes());
    r[37..69].copy_from_slice(&[0x77; 32]);
    r[69..101].copy_from_slice(&prev);
    r[101..2053].copy_from_slice(&[0x42; 1952]);
    r
}

struct Out {
    code: i32,
    state: Option<KeyState>,
    v2_dec: Option<u64>,
}

fn door(s: &KeyState, rec: &[u8], at: u64, sent: Option<SendFacts>, settled: bool) -> Out {
    let input = s.encode();
    let facts = sent.map(|f| f.encode());
    let (mut out, mut dec, mut set) = ([0u8; MT_COIN_STATE_LEN], 0u64, 0u8);
    let code = unsafe {
        mt_coin_step(
            input.as_ptr(),
            rec.as_ptr(),
            rec.len(),
            at,
            facts.as_ref().map_or(ptr::null(), |b| b.as_ptr()),
            i32::from(settled),
            out.as_mut_ptr(),
            &mut dec,
            &mut set,
        )
    };
    Out {
        code,
        state: (code == MT_OK)
            .then(|| KeyState::decode(&out).expect("the core writes a readable state")),
        v2_dec: (set == 1).then_some(dec),
    }
}

fn word(code: i32) -> String {
    let mut b = [0u8; 32];
    let n = unsafe { mt_coin_refusal(code, b.as_mut_ptr(), b.len()) };
    assert!(n > 0, "code {code} has no word");
    String::from_utf8(b[..n as usize].to_vec()).expect("an ASCII word")
}

fn born(at: u64) -> KeyState {
    let rec = v3(5, 0, [0; 32], [0; 32], [0; 32], 0, 0);
    door(&KeyState::default(), &rec, at, None, false)
        .state
        .expect("a GENESIS of 0 opens a key")
}

// Refuses a door that weighs a MINT by anything but one coin a second of the key's life from the
// second's cut: 300 seconds mint 300, never 301.
#[test]
fn a_mint_through_the_door_is_one_coin_a_second() {
    let b = C - 100;
    let s = born(b);
    assert_eq!((s.height, s.birth, s.mint_end), (1, b, b));
    let over = door(
        &s,
        &v3(3, 301, s.head, [0; 32], [0; 32], b, b + 300),
        C + 200,
        None,
        false,
    );
    assert_eq!(over.code, i32::from(Refusal::Allowance.code()));
    assert_eq!(word(over.code), "allowance");
    let ok = door(
        &s,
        &v3(3, 300, s.head, [0; 32], [0; 32], b, b + 300),
        C + 200,
        None,
        false,
    );
    assert_eq!(ok.code, MT_OK);
    let n = ok.state.expect("taken");
    assert_eq!(
        (n.proven, n.minted, n.mint_end, n.height, n.last_at),
        (300, 300, b + 300, 2, C + 200)
    );
    assert_eq!(ok.v2_dec, None);
}

// Refuses a door that drops the SEND's facts, reads them at the wrong offsets, or ignores settled.
#[test]
fn a_recv_through_the_door_takes_the_named_send_once() {
    let s = born(C - 1000);
    let blind = [0x33; 32];
    let rid = [0x99; 32];
    let rec = v3(2, 700, s.head, blind, rid, 200, 0);
    let from = Sha256::digest([0x42u8; 1952]).into();
    let sent = SendFacts {
        from: [0x11; 32],
        amount: 700,
        at: C - 900,
        to: commitment(&from, &blind),
        dec: 200,
    };
    let ok = door(&s, &rec, C - 800, Some(sent), false);
    assert_eq!(ok.code, MT_OK);
    let n = ok.state.expect("taken");
    assert_eq!((n.proven, n.declared), (500, 200));
    assert_eq!(
        word(door(&s, &rec, C - 800, Some(sent), true).code),
        "settled"
    );
    assert_eq!(word(door(&s, &rec, C - 800, None, false).code), "no send");
    let other = SendFacts {
        amount: 701,
        ..sent
    };
    assert_eq!(
        word(door(&s, &rec, C - 800, Some(other), false).code),
        "amount"
    );
}

// Refuses a door that loses the declared part a v2 record took on an opened chain (fold-4).
#[test]
fn a_v2_spend_through_the_door_names_its_declared_part() {
    let s = KeyState {
        head: [0x21; 32],
        height: 4,
        birth: C - 5000,
        mint_end: C - 5000,
        proven: 50,
        declared: 100,
        last_at: C - 10,
        v3: true,
        minted: 50,
    };
    let out = door(&s, &v2(120, s.head), C - 5, None, false);
    assert_eq!(out.code, MT_OK);
    assert_eq!(out.v2_dec, Some(70));
    let n = out.state.expect("taken");
    assert_eq!((n.proven, n.declared, n.height), (0, 30, 5));
    let past = door(
        &KeyState { v3: false, ..s },
        &v2(120, s.head),
        C - 5,
        None,
        false,
    );
    assert_eq!(past.v2_dec, None);
}

// Refuses an at_now that answers the head's state alone, or folds the time before its cut.
#[test]
fn at_now_folds_the_key_s_seconds() {
    let s = KeyState {
        head: [0x31; 32],
        height: 1,
        birth: D - 1000,
        mint_end: D - 1000,
        last_at: D - 1000,
        v3: true,
        ..KeyState::default()
    };
    let at = |now: u64| {
        let mut out = [0u8; MT_COIN_STATE_LEN];
        assert_eq!(
            unsafe { mt_coin_at_now(s.encode().as_ptr(), now, out.as_mut_ptr()) },
            MT_OK
        );
        KeyState::decode(&out).expect("readable")
    };
    let n = at(D + 5);
    assert_eq!((n.proven, n.minted), (1005, 1005));
    assert_eq!(at(D - 1).proven, 0);
}

// Refuses a door that folds an unreadable record or state, or writes through a null pointer.
#[test]
fn the_door_refuses_what_it_cannot_read() {
    let s = born(C - 100);
    let rec = v3(3, 1, s.head, [0; 32], [0; 32], C - 100, C - 30);
    assert_eq!(
        door(&s, &rec[..TX3_LEN - 1], C, None, false).code,
        MT_ERR_DECODE
    );
    let mut bad = s.encode();
    bad[96] = 2;
    let (mut out, mut dec, mut set) = ([0u8; MT_COIN_STATE_LEN], 0u64, 0u8);
    let code = unsafe {
        mt_coin_step(
            bad.as_ptr(),
            rec.as_ptr(),
            rec.len(),
            C,
            ptr::null(),
            0,
            out.as_mut_ptr(),
            &mut dec,
            &mut set,
        )
    };
    assert_eq!(code, MT_ERR_DECODE);
    let code = unsafe {
        mt_coin_step(
            s.encode().as_ptr(),
            rec.as_ptr(),
            rec.len(),
            C,
            ptr::null(),
            0,
            ptr::null_mut(),
            &mut dec,
            &mut set,
        )
    };
    assert_eq!(code, MT_ERR_NULL_PTR);
}

// Refuses a word for a code no refusal has, a word written past its buffer, and a fold name the
// core does not fold by.
#[test]
fn words_and_the_fold_s_name() {
    let mut b = [0u8; 32];
    assert_eq!(
        unsafe { mt_coin_refusal(0, b.as_mut_ptr(), b.len()) },
        MT_ERR_DECODE
    );
    assert_eq!(
        unsafe { mt_coin_refusal(19, b.as_mut_ptr(), b.len()) },
        MT_ERR_DECODE
    );
    assert_eq!(
        unsafe { mt_coin_refusal(10, b.as_mut_ptr(), 3) },
        MT_ERR_BUFFER_TOO_SMALL
    );
    assert_eq!(word(1), "not on the head");
    assert_eq!(word(18), "minting stopped");
    let n = unsafe { mt_coin_fold(b.as_mut_ptr(), b.len()) };
    assert_eq!(&b[..n as usize], TX_FOLD.as_bytes());
    assert_eq!(TX_FOLD, "fold-9");
}
