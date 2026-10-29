// The vectors of COIN-TX-V3 section 9 that the fold alone decides (V1, V3, V6, V8 to V15), the
// genesis cap of section 3, and the layout of section 1 read back field by field. Each test names
// the wrong implementation it refuses.

use mt_coin::*;
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, BTreeSet};

const ZERO: [u8; 32] = [0; 32];
const C: u64 = TX_SECOND_CUT;
const D: u64 = TX_TIME_CUT;
const E: u64 = TX_ONLINE_CUT;

fn sha(b: &[u8]) -> [u8; 32] {
    Sha256::digest(b).into()
}

fn hex(b: &[u8]) -> String {
    b.iter().map(|x| format!("{x:02x}")).collect()
}

fn seq(start: u8) -> [u8; 32] {
    core::array::from_fn(|i| start + i as u8)
}

#[derive(Clone, Copy)]
struct Draft {
    kind: u8,
    amount: u64,
    prev: [u8; 32],
    pair: [u8; 32],
    to: [u8; 32],
    reference: [u8; 32],
    t0: u64,
    t1: u64,
    key: u8,
    nonce: u8,
}

impl Draft {
    fn new(kind: u8, amount: u64) -> Draft {
        Draft {
            kind,
            amount,
            prev: ZERO,
            pair: ZERO,
            to: ZERO,
            reference: ZERO,
            t0: 0,
            t1: 0,
            key: 1,
            nonce: 0,
        }
    }

    fn bytes(&self) -> Vec<u8> {
        let mut r = vec![0xEE; TX3_LEN];
        r[..4].copy_from_slice(TX_MAGIC);
        r[4] = 3;
        r[5] = self.kind;
        r[6..14].copy_from_slice(&self.amount.to_le_bytes());
        r[14..22].copy_from_slice(&1_760_000_000_000u64.to_le_bytes());
        r[22..38].copy_from_slice(&[self.nonce; 16]);
        r[38..70].copy_from_slice(&self.prev);
        r[70..102].copy_from_slice(&self.pair);
        r[102..134].copy_from_slice(&self.to);
        r[134..166].copy_from_slice(&self.reference);
        r[166..174].copy_from_slice(&self.t0.to_le_bytes());
        r[174..182].copy_from_slice(&self.t1.to_le_bytes());
        r[182..2134].copy_from_slice(&[self.key; 1952]);
        r
    }
}

fn v2_bytes(amount: u64, prev: [u8; 32], key: u8, nonce: u8) -> Vec<u8> {
    let mut r = vec![0xEE; TX2_LEN];
    r[..4].copy_from_slice(TX_MAGIC);
    r[4] = 2;
    r[5..13].copy_from_slice(&amount.to_le_bytes());
    r[13..21].copy_from_slice(&1_760_000_000_000u64.to_le_bytes());
    r[21..37].copy_from_slice(&[nonce; 16]);
    r[37..69].copy_from_slice(&[0x77; 32]);
    r[69..101].copy_from_slice(&prev);
    r[101..2053].copy_from_slice(&[key; 1952]);
    r
}

#[derive(Default)]
struct Book {
    sends: BTreeMap<[u8; 32], SendFacts>,
    settled: BTreeSet<[u8; 32]>,
}

impl Ledger for Book {
    fn send(&self, id: &[u8; 32]) -> Option<SendFacts> {
        self.sends.get(id).copied()
    }
    fn settled(&self, id: &[u8; 32]) -> bool {
        self.settled.contains(id)
    }
}

// One key's chain as its node holds it: every record stands on the head, a refused record leaves
// the state as it stood, and the taken ones are kept in order for a whole fold.
struct Key {
    tag: u8,
    nonce: u8,
    state: KeyState,
    chain: Vec<(Record, u64)>,
}

impl Key {
    fn new(tag: u8) -> Key {
        Key {
            tag,
            nonce: 0,
            state: KeyState::default(),
            chain: Vec::new(),
        }
    }

    fn owner(&self) -> [u8; 32] {
        sha(&[self.tag; 1952])
    }

    fn record(&mut self, mut d: Draft) -> Record {
        self.nonce += 1;
        d.prev = self.state.head;
        d.key = self.tag;
        d.nonce = self.nonce;
        parse(&d.bytes()).expect("a well-formed record")
    }

    fn v2(&mut self, amount: u64) -> Record {
        self.nonce += 1;
        parse(&v2_bytes(amount, self.state.head, self.tag, self.nonce)).expect("a v2 record")
    }

    fn lay(&mut self, r: Record, at: u64, book: &Book) -> Result<Folded, Refusal> {
        let f = step(&self.state, &r, at, book)?;
        self.state = f.state;
        self.chain.push((r, at));
        Ok(f)
    }

    fn genesis(&mut self, amount: u64, at: u64) -> Result<Folded, Refusal> {
        let r = self.record(Draft::new(5, amount));
        self.lay(r, at, &Book::default())
    }

    fn mint(&mut self, amount: u64, t0: u64, t1: u64, at: u64) -> Result<Folded, Refusal> {
        let r = self.record(Draft {
            t0,
            t1,
            ..Draft::new(3, amount)
        });
        self.lay(r, at, &Book::default())
    }

    fn send(&mut self, amount: u64, dec: u64, at: u64) -> Result<Folded, Refusal> {
        let r = self.record(Draft {
            pair: [0x77; 32],
            to: [0x99; 32],
            t0: dec,
            ..Draft::new(1, amount)
        });
        self.lay(r, at, &Book::default())
    }

    fn burn(&mut self, amount: u64, dec: u64, at: u64) -> Result<Folded, Refusal> {
        let r = self.record(Draft {
            t0: dec,
            ..Draft::new(6, amount)
        });
        self.lay(r, at, &Book::default())
    }
}

#[test]
fn v1_the_receivers_commitment() {
    let (from, blind) = (seq(0x00), seq(0x20));
    assert_eq!(
        hex(&commitment(&from, &blind)),
        "b08fb9c67b693f0cfe394de25474d2b79ae990a87a2f6a24bb7727560a8d88a4"
    );
    // The refused reading -- the blind before from -- is another hash, so the vector tells them apart.
    assert_eq!(
        hex(&commitment(&blind, &from)),
        "8d9016dfed6ea8b2c6c03daaf943afe73dfc25ed46a4bc9049bf5afe15de9c3f"
    );
}

#[test]
fn v3_the_doubling_rule_and_the_genesis_cap() {
    let table = [
        (0, 0),
        (1, 2),
        (2, 4),
        (3, 6),
        (4, 10),
        (7, 22),
        (8, 28),
        (15, 70),
        (16, 78),
        (8191, 180_230),
        (8192, 180_256),
        (8193, 180_282),
        (86_400, 2_213_664),
    ];
    for (x, want) in table {
        assert_eq!(a2(x), want, "A_2({x})");
    }
    assert_eq!(TX_GENESIS_CAP, 110_040_864);
    assert_eq!(TX_GENESIS_CAP, a2(TX_V2_CUT - TX_COIN_EPOCH));
}

#[test]
fn the_rule_of_a_mint_is_chosen_by_its_at() {
    assert_eq!(allowance(6800, C - 1), 146_846);
    assert_eq!(allowance(6800, C), 6800);
    assert_eq!(allowance(0, C), 0);
}

#[test]
fn a_v3_record_reads_every_field_at_its_offset() {
    let d = Draft {
        amount: 0x0807_0605_0403_0201,
        pair: seq(0x40),
        to: seq(0x60),
        t0: 0x0102,
        key: 9,
        nonce: 3,
        prev: seq(0x80),
        ..Draft::new(1, 0)
    };
    let b = d.bytes();
    let r = parse(&b).expect("a SEND");
    assert_eq!(r.version, 3);
    assert_eq!(r.kind, Kind::Send);
    // Little-endian: a big-endian reader gets 0x0102030405060708.
    assert_eq!(r.amount, 0x0807_0605_0403_0201);
    assert_eq!(r.prev, seq(0x80));
    assert_eq!(r.pair, seq(0x40));
    assert_eq!(r.to, seq(0x60));
    assert_eq!(r.reference, ZERO);
    assert_eq!((r.t0, r.t1, r.dec), (0x0102, 0, 0x0102));
    assert_eq!(r.id, sha(&b));
    assert_eq!(r.from, sha(&[9; 1952]));

    let m = parse(
        &Draft {
            t0: 0x1111,
            t1: 0x2222,
            ..Draft::new(3, 5)
        }
        .bytes(),
    )
    .expect("a MINT");
    assert_eq!((m.kind, m.t0, m.t1, m.dec), (Kind::Mint, 0x1111, 0x2222, 0));

    let recv = parse(
        &Draft {
            to: seq(0x20),
            reference: seq(0xA0),
            t0: 4,
            ..Draft::new(2, 10)
        }
        .bytes(),
    )
    .expect("a RECV");
    assert_eq!(
        (recv.kind, recv.to, recv.reference, recv.dec),
        (Kind::Recv, seq(0x20), seq(0xA0), 4)
    );
}

#[test]
fn a_v2_record_reads_every_field_at_its_offset() {
    let b = v2_bytes(0x0807_0605_0403_0201, seq(0x80), 4, 1);
    let r = parse(&b).expect("a v2 record");
    assert_eq!((r.version, r.kind), (2, Kind::Send));
    assert_eq!(r.amount, 0x0807_0605_0403_0201);
    assert_eq!(r.pair, [0x77; 32]);
    assert_eq!(r.prev, seq(0x80));
    assert_eq!((r.to, r.reference, r.dec), (ZERO, ZERO, 0));
    assert_eq!(r.id, sha(&b));
    assert_eq!(r.from, sha(&[4; 1952]));
}

#[test]
fn a_record_has_one_reading_only() {
    let good = Draft::new(5, 0).bytes();
    assert_eq!(parse(&good[..4]), Err(ParseError::Magic));
    let mut bad = good.clone();
    bad[0] = b'X';
    assert_eq!(parse(&bad), Err(ParseError::Magic));
    for v in [0, 1, 4] {
        let mut bad = good.clone();
        bad[4] = v;
        assert_eq!(parse(&bad), Err(ParseError::Version), "version {v}");
    }
    assert_eq!(parse(&good[..TX3_LEN - 1]), Err(ParseError::Length));
    assert_eq!(
        parse(&v2_bytes(1, ZERO, 1, 1)[..TX2_LEN - 1]),
        Err(ParseError::Length)
    );
    for k in [0, 7, 255] {
        assert_eq!(
            parse(&Draft::new(k, 1).bytes()),
            Err(ParseError::Kind),
            "kind {k}"
        );
    }
    let field = [
        Draft {
            pair: [1; 32],
            ..Draft::new(5, 0)
        },
        Draft {
            reference: [1; 32],
            t0: 1,
            t1: 61,
            ..Draft::new(3, 1)
        },
        Draft {
            reference: [1; 32],
            t0: 1,
            ..Draft::new(4, 1)
        },
        Draft {
            reference: [1; 32],
            pair: [1; 32],
            to: [1; 32],
            ..Draft::new(2, 1)
        },
        Draft {
            pair: [1; 32],
            ..Draft::new(1, 1)
        },
        Draft {
            to: [1; 32],
            ..Draft::new(2, 1)
        },
        Draft {
            t1: 1,
            pair: [1; 32],
            to: [1; 32],
            ..Draft::new(1, 1)
        },
    ];
    for (i, d) in field.iter().enumerate() {
        assert_eq!(parse(&d.bytes()), Err(ParseError::Field), "draft {i}");
    }
    let above = Draft {
        pair: [1; 32],
        to: [1; 32],
        t0: 6,
        ..Draft::new(1, 5)
    };
    assert_eq!(parse(&above.bytes()), Err(ParseError::Amount));
    assert_eq!(
        parse(
            &Draft {
                t0: 1,
                t1: 61,
                ..Draft::new(3, 0)
            }
            .bytes()
        ),
        Err(ParseError::Amount)
    );
    assert_eq!(parse(&v2_bytes(0, ZERO, 1, 1)), Err(ParseError::Amount));
    assert!(parse(&good).is_ok(), "a GENESIS of 0 is the birth of a key");
}

#[test]
fn v6_a_v2_record_on_an_opened_chain() {
    let b = TX_GENESIS_GATE - 10_000;
    let mut s = Key::new(1);
    s.genesis(1000, b).unwrap();
    s.mint(500, b, b + 300, b + 300).unwrap();
    s.send(1200, 700, b + 400).unwrap();
    assert_eq!((s.state.proven, s.state.declared), (0, 300));
    let r = s.v2(50);
    let f = s.lay(r, b + 500, &Book::default()).unwrap();
    // A v2 record that moves nothing on an opened chain would leave 300 declared.
    assert_eq!((s.state.proven, s.state.declared), (0, 250));
    assert_eq!(f.v2_dec, Some(50));
    let over = s.v2(251);
    let mut chain = s.chain.clone();
    chain.push((over, b + 600));
    assert_eq!(
        s.lay(over, b + 600, &Book::default()),
        Err(Refusal::Overspend)
    );
    assert_eq!(fold(&chain, &Book::default()), Err((4, Refusal::Overspend)));
}

#[test]
fn v8_the_sum_of_time_before_the_second_cut() {
    let b = C - 100_000;
    let mut k = Key::new(2);
    k.genesis(0, b).unwrap();
    k.mint(120, b, b + 6800, b + 6800).unwrap();
    // A fold that weighs a MINT by its own interval alone refuses this 2000 (its interval allows 1680).
    k.mint(2000, b + 6800, b + 6870, b + 6870).unwrap();
    assert_eq!(
        (k.state.proven, k.state.minted, k.state.mint_end),
        (2120, 2120, b + 6870)
    );
    // A fold that forgets what the key minted takes it: A_2(6940) = 150206.
    assert_eq!(
        k.mint(148_087, b + 6870, b + 6940, b + 6940),
        Err(Refusal::Allowance)
    );
    k.mint(148_086, b + 6870, b + 6940, b + 6940).unwrap();
    assert_eq!(k.state.minted, a2(6940));
}

#[test]
fn a_mint_names_its_interval_on_a_born_chain() {
    let b = C - 100_000;
    let mut k = Key::new(3);
    assert_eq!(k.mint(1, b, b + 60, b + 60), Err(Refusal::NoBirth));
    k.genesis(0, b).unwrap();
    k.mint(1, b, b + 60, b + 60).unwrap();
    assert_eq!(
        k.mint(1, b + 59, b + 120, b + 120),
        Err(Refusal::Interval),
        "overlap"
    );
    assert_eq!(
        k.mint(1, b + 60, b + 119, b + 120),
        Err(Refusal::Interval),
        "59 seconds"
    );
    assert_eq!(
        k.mint(1, b + 60, b + 120, b + 119),
        Err(Refusal::Interval),
        "time not yet passed"
    );
    k.mint(1, b + 60, b + 120, b + 120).unwrap();
}

#[test]
fn v9_the_books_past() {
    let g = TX_GENESIS_GATE;
    let mut fresh = Key::new(4);
    assert_eq!(fresh.genesis(5, g + 1), Err(Refusal::GenesisPast));
    fresh.genesis(0, g + 1).unwrap();

    let p0 = g + 1000;
    let mut p = Key::new(5);
    let past = p.v2(10);
    p.lay(past, p0, &Book::default()).unwrap();
    assert_eq!(a2(360) + 1, 4759);
    assert_eq!(p.genesis(4759, p0 + 300), Err(Refusal::GenesisPast));
    assert_eq!(p.genesis(3799, p0 + 300), Err(Refusal::GenesisPast));
    p.genesis(3798, p0 + 300).unwrap();
    assert_eq!((p.state.declared, p.state.proven), (3798, 0));
    assert_eq!(p.genesis(0, p0 + 400), Err(Refusal::Genesis));

    let mut q = Key::new(6);
    q.genesis(777, g - 10).unwrap();
    assert_eq!(q.state.declared, 777);
    assert_eq!(fold(&q.chain, &Book::default()).unwrap(), q.state);
}

#[test]
fn a_genesis_is_bounded_by_the_cap_and_the_cut() {
    let early = TX_GENESIS_GATE - 1;
    let cap = TX_GENESIS_CAP as u64;
    let mut over = Key::new(7);
    assert_eq!(over.genesis(cap + 1, early), Err(Refusal::GenesisAmount));
    over.genesis(cap, early).unwrap();
    let mut late = Key::new(8);
    assert_eq!(late.genesis(1, TX_V2_CUT), Err(Refusal::GenesisLate));
    late.genesis(0, TX_V2_CUT).unwrap();
}

#[test]
fn v10_a_v2_record_that_spent_comes_back() {
    let b = TX_GENESIS_GATE - 100_000;
    let mut v = Key::new(10);
    let past = v.v2(1);
    let past_id = past.id;
    v.lay(past, b, &Book::default()).unwrap();
    v.genesis(1000, b + 10).unwrap();
    v.mint(500, b, b + 300, b + 300).unwrap();
    let spent = v.v2(1200);
    let spent_id = spent.id;
    let f = v.lay(spent, b + 400, &Book::default()).unwrap();
    assert_eq!((v.state.proven, v.state.declared), (0, 300));
    assert_eq!(f.v2_dec, Some(700));

    let mut book = Book::default();
    book.sends.insert(
        spent_id,
        SendFacts {
            from: v.owner(),
            amount: 1200,
            at: b + 400,
            to: ZERO,
            dec: 700,
        },
    );
    let refund = |key: &mut Key, amount: u64, reference: [u8; 32]| {
        key.record(Draft {
            reference,
            ..Draft::new(4, amount)
        })
    };

    let mut r = Key::new(11);
    r.genesis(0, b).unwrap();
    let recv = r.record(Draft {
        to: [0x55; 32],
        reference: spent_id,
        t0: 700,
        ..Draft::new(2, 1200)
    });
    assert_eq!(
        step(&r.state, &recv, b + 500, &book),
        Err(Refusal::NotYours)
    );

    let day = b + 400 + TX_DAY;
    let of_the_past = refund(&mut v, 1, past_id);
    assert_eq!(
        step(&v.state, &of_the_past, day, &book),
        Err(Refusal::NoSend)
    );
    let other = refund(&mut v, 1199, spent_id);
    assert_eq!(step(&v.state, &other, day, &book), Err(Refusal::Amount));
    let mut w = Key::new(12);
    w.genesis(0, b).unwrap();
    let by_another = refund(&mut w, 1200, spent_id);
    assert_eq!(
        step(&w.state, &by_another, day, &book),
        Err(Refusal::NotYours)
    );
    let early = refund(&mut v, 1200, spent_id);
    assert_eq!(step(&v.state, &early, day - 1, &book), Err(Refusal::Early));

    let back = refund(&mut v, 1200, spent_id);
    v.lay(back, day, &book).unwrap();
    // Given back as proven it would read 1200 proven and 300 declared.
    assert_eq!((v.state.proven, v.state.declared), (500, 1000));
    assert_eq!(fold(&v.chain, &book).unwrap(), v.state);
    book.settled.insert(spent_id);
    let again = refund(&mut v, 1200, spent_id);
    assert_eq!(
        step(&v.state, &again, day + 1, &book),
        Err(Refusal::Settled)
    );
}

#[test]
fn v11_one_second_one_coin() {
    let b = C - 100;
    let mut l = Key::new(13);
    l.genesis(0, b).unwrap();
    l.mint(100, b, b + 300, C + 200).unwrap();
    // Its interval alone allows 60; the key's 360 seconds less its 100 allow 260.
    l.mint(250, b + 300, b + 360, C + 500).unwrap();
    // A_2(420) - 350 = 5368 under the doubling rule; A(420) - 350 = 70 under the second's.
    assert_eq!(
        l.mint(71, b + 360, b + 420, C + 500),
        Err(Refusal::Allowance)
    );
    l.mint(70, b + 360, b + 420, C + 500).unwrap();
    assert_eq!((l.state.proven, l.state.minted), (420, 420));

    let k = v11_key_k();
    assert_eq!((k.state.proven, k.state.minted), (140_000, 140_000));
}

fn v11_key_k() -> Key {
    let b = C - 7000;
    let mut k = Key::new(14);
    k.genesis(0, b).unwrap();
    // Taken before the cut by A_2(6800) = 146846; a fold applying A at a re-fold refuses it.
    k.mint(140_000, b, b + 6800, C - 150).unwrap();
    // Its t1 lies before the cut: a rule chosen by t1 would take it (A_2(6870) - 140000 = 8526).
    assert_eq!(
        k.mint(1, b + 6800, b + 6870, C + 10),
        Err(Refusal::Allowance)
    );
    k
}

#[test]
fn v12_the_chain_mints_the_keys_time() {
    let b = D - 1000;
    let mut t = Key::new(15);
    t.genesis(0, b).unwrap();
    // A step applied before D would refuse this MINT «allowance».
    t.mint(300, b, b + 400, D - 500).unwrap();
    assert_eq!((t.state.proven, t.state.minted), (300, 300));
    // The time folds first: on 300 alone the SEND would be an overspend.
    t.send(1000, 0, D + 100).unwrap();
    assert_eq!((t.state.proven, t.state.minted), (100, 1100));
    let head = t.state.head;
    assert_eq!(
        t.mint(1, b + 400, b + 1060, D + 200),
        Err(Refusal::Allowance)
    );
    assert_eq!(t.state.head, head, "a refused record leaves the state");
    let now = at_now(&t.state, D + 300);
    // The head's state alone would answer proven 100, minted 1100.
    assert_eq!(
        (now.proven, now.minted, now.declared, now.head),
        (300, 1300, 0, head)
    );
    assert_eq!(at_now(&t.state, D), t.state, "never below the head's at");

    let mut k = v11_key_k();
    k.send(1, 0, D).unwrap();
    // Seconds credited without the key's MINTs would leave 406199.
    assert_eq!(k.state.proven, 266_199);
    assert_eq!(k.state.minted, 266_200);
}

#[test]
fn v13_a_mint_counts_the_present_seconds() {
    let b = E - 1000;
    let mut k = Key::new(19);
    k.genesis(0, b).unwrap();
    // The life credits up to the cut and no further: fold-6 would credit 1500 here and take 1001.
    assert_eq!(k.send(1001, 0, E + 500), Err(Refusal::Overspend));
    k.send(1000, 0, E + 500).unwrap();
    assert_eq!((k.state.proven, k.state.minted), (0, 1000));
    assert_eq!(
        at_now(&k.state, E + 5000).proven,
        0,
        "the life mints nothing after the cut"
    );
    // Away from E to E + 500: a MINT over all of it counts its last 120 seconds alone. A fold without
    // the present seconds takes 600 (1600 lived less 1000 minted).
    assert_eq!(k.mint(101, b, E + 600, E + 620), Err(Refusal::Stale));
    k.mint(100, b, E + 600, E + 620).unwrap();
    // Present a minute later: every second of the interval counts.
    assert_eq!(k.mint(61, E + 600, E + 660, E + 670), Err(Refusal::Stale));
    k.mint(60, E + 600, E + 660, E + 670).unwrap();
    assert_eq!(
        (k.state.proven, k.state.minted, k.state.mint_end),
        (160, 1160, E + 660)
    );
    // Present is measured back from the node's second, never from t1: a fold that measures from t1
    // takes this one coin of an interval that ended three minutes before.
    assert_eq!(k.mint(1, E + 660, E + 720, E + 900), Err(Refusal::Stale));
    assert_eq!(fold(&k.chain, &Book::default()).unwrap(), k.state);
}

#[test]
fn v14_a_burn_spends_and_names_no_one() {
    let b = E - 1000;
    let mut k = Key::new(20);
    k.genesis(0, b).unwrap();
    assert_eq!(k.burn(10, 0, E - 1), Err(Refusal::NotYet));
    assert_eq!(k.burn(1001, 1, E + 10), Err(Refusal::Overspend));
    assert_eq!(k.burn(400, 1, E + 10), Err(Refusal::Split));
    k.burn(400, 0, E + 10).unwrap();
    // A BURN folded as a MINT, or as nothing, leaves 1400 or 1000.
    assert_eq!(
        (k.state.proven, k.state.declared, k.state.minted),
        (600, 0, 1000)
    );
    let burned = k.state.head;
    let refund = k.record(Draft {
        reference: burned,
        ..Draft::new(4, 400)
    });
    assert_eq!(
        step(&k.state, &refund, E + 10 + TX_DAY, &Book::default()),
        Err(Refusal::NoSend)
    );
    assert_eq!(fold(&k.chain, &Book::default()).unwrap(), k.state);

    let r = parse(
        &Draft {
            t0: 3,
            ..Draft::new(6, 5)
        }
        .bytes(),
    )
    .expect("a BURN");
    assert_eq!((r.kind, r.amount, r.dec, r.t1), (Kind::Burn, 5, 3, 0));
    let stray = [
        Draft {
            pair: [1; 32],
            ..Draft::new(6, 5)
        },
        Draft {
            to: [1; 32],
            ..Draft::new(6, 5)
        },
        Draft {
            reference: [1; 32],
            ..Draft::new(6, 5)
        },
        Draft {
            t1: 1,
            ..Draft::new(6, 5)
        },
    ];
    for (i, d) in stray.iter().enumerate() {
        assert_eq!(parse(&d.bytes()), Err(ParseError::Field), "burn draft {i}");
    }
    assert_eq!(parse(&Draft::new(6, 0).bytes()), Err(ParseError::Amount));
    assert_eq!(
        parse(
            &Draft {
                t0: 6,
                ..Draft::new(6, 5)
            }
            .bytes()
        ),
        Err(ParseError::Amount)
    );
}

#[test]
fn v15_the_past_never_eats_the_present() {
    // Key O minted by the doubling rule before the second's cut: 2567238 coins for 99999 seconds,
    // above every second it lives until after TX_ONLINE_CUT.
    let b = C - 100_000;
    let mut o = Key::new(21);
    o.genesis(0, b).unwrap();
    let m = a2(99_999);
    assert_eq!(m, 2_567_238);
    o.mint(2_567_238, b, C - 1, C - 1).unwrap();
    assert_eq!((o.state.proven, o.state.minted), (m, m));
    // fold-7 answers m, m: its 359500 seconds of life lie below what it minted, so it credits none.
    let now = at_now(&o.state, D + 300);
    assert_eq!((now.proven, now.minted), (m + 300, m + 300));
    o.send(1, 0, D + 300).unwrap();
    assert_eq!((o.state.proven, o.state.minted), (m + 299, m + 300));
    // From the last record, never again from the cut: a step that ignores last_at answers m + 799.
    let now = at_now(&o.state, D + 500);
    assert_eq!((now.proven, now.minted), (m + 499, m + 500));
    // The life stops at TX_ONLINE_CUT, and a MINT counts its present seconds from it alone: fold-7
    // refuses it «allowance», and a MINT without the cut's floor takes the 120 seconds of its interval.
    assert_eq!(o.mint(61, E - 60, E + 60, E + 60), Err(Refusal::Stale));
    o.mint(60, E - 60, E + 60, E + 60).unwrap();
    let away = u128::from(E - D - 300);
    assert_eq!(
        (o.state.proven, o.state.minted, o.state.mint_end),
        (m + 299 + away + 60, m + 300 + away + 60, E + 60)
    );
    assert_eq!(fold(&o.chain, &Book::default()).unwrap(), o.state);
}

#[test]
fn a_record_stands_on_the_head_and_splits_as_named() {
    let b = TX_GENESIS_GATE - 10_000;
    let mut s = Key::new(16);
    s.genesis(1000, b).unwrap();
    s.mint(500, b, b + 300, b + 300).unwrap();
    assert_eq!(s.send(600, 0, b + 400), Err(Refusal::Split));
    assert_eq!(s.send(600, 101, b + 400), Err(Refusal::Split));
    assert_eq!(s.send(1501, 1001, b + 400), Err(Refusal::Overspend));
    let stale = Record {
        prev: [0x33; 32],
        ..s.record(Draft {
            pair: [1; 32],
            to: [1; 32],
            t0: 100,
            ..Draft::new(1, 600)
        })
    };
    assert_eq!(
        step(&s.state, &stale, b + 400, &Book::default()),
        Err(Refusal::NotOnTheHead)
    );
    s.send(600, 100, b + 400).unwrap();
    assert_eq!((s.state.proven, s.state.declared), (0, 900));
    assert_eq!(s.state.height, 3);
}

#[test]
fn a_recv_opens_its_send_once() {
    let b = TX_GENESIS_GATE - 10_000;
    let mut r = Key::new(17);
    r.genesis(0, b).unwrap();
    let blind = [0x42; 32];
    let send_id = [0x24; 32];
    let mut book = Book::default();
    book.sends.insert(
        send_id,
        SendFacts {
            from: [0x18; 32],
            amount: 50,
            at: b,
            to: commitment(&r.owner(), &blind),
            dec: 20,
        },
    );
    let recv = |key: &mut Key, dec: u64| {
        key.record(Draft {
            to: blind,
            reference: send_id,
            t0: dec,
            ..Draft::new(2, 50)
        })
    };
    let wrong_split = recv(&mut r, 19);
    assert_eq!(
        step(&r.state, &wrong_split, b + 1, &book),
        Err(Refusal::Split)
    );
    let mut stranger = Key::new(18);
    stranger.genesis(0, b).unwrap();
    let theirs = recv(&mut stranger, 20);
    assert_eq!(
        step(&stranger.state, &theirs, b + 1, &book),
        Err(Refusal::NotYours)
    );
    let good = recv(&mut r, 20);
    r.lay(good, b + 1, &book).unwrap();
    assert_eq!((r.state.proven, r.state.declared), (30, 20));
    book.settled.insert(send_id);
    let twice = recv(&mut r, 20);
    assert_eq!(step(&r.state, &twice, b + 2, &book), Err(Refusal::Settled));
}

#[test]
fn every_refusal_has_the_nodes_word() {
    let words = [
        (Refusal::NotOnTheHead, "not on the head"),
        (Refusal::Overspend, "overspend"),
        (Refusal::Allowance, "allowance"),
        (Refusal::GenesisPast, "genesis past"),
        (Refusal::Settled, "settled"),
        (Refusal::Stale, "stale"),
        (Refusal::NotYet, "not yet"),
        (Refusal::Stopped, "minting stopped"),
    ];
    for (r, w) in words {
        assert_eq!(r.word(), w);
    }
    assert_eq!(TX_FOLD, "fold-9");
}

// fold-9 (decision 362 a): from TX_MINT_STOP no MINT is taken, whatever its interval, and the life
// credits nothing, so a key's coins only move. A MINT taken the second before keeps its fate at a
// re-fold, and a GENESIS 0 still opens a key. Refuses a fold that still mints from the stop, or one
// that refuses a MINT taken before it.
#[test]
fn v16_minting_stops_and_only_the_core_mints() {
    let s = TX_MINT_STOP;
    let mut k = Key::new(23);
    k.genesis(0, s - 1000).unwrap();
    k.mint(60, s - 200, s - 140, s - 130).unwrap();
    let before = k.state;
    assert_eq!(k.mint(60, s - 60, s, s), Err(Refusal::Stopped));
    assert_eq!(k.mint(1, s + 60, s + 120, s + 125), Err(Refusal::Stopped));
    assert_eq!(k.state, before);
    assert_eq!(
        at_now(&k.state, s + 86_400),
        before,
        "the life mints nothing after the stop"
    );
    assert_eq!(fold(&k.chain, &Book::default()).unwrap(), before);
    let mut n = Key::new(24);
    n.genesis(0, s + 10).unwrap();
    assert_eq!(n.state.proven + n.state.declared, 0);
    assert_eq!(n.genesis(1, s + 20), Err(Refusal::Genesis));
    assert_eq!(n.mint(60, s + 10, s + 70, s + 75), Err(Refusal::Stopped));
}
