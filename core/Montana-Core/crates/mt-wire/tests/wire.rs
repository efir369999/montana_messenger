// The wire, end to end. The frozen vectors of a cell first, and then the property the stage closes:
// two machines exchange cells through a third that carries them and learns nothing.

use mt_wire::cell::{self, Delivery, Routing};
use mt_wire::{cell_bytes, chunk_bytes, path_max, LABEL_BYTES, SEAL_BYTES};
use sha2::{Digest, Sha256};
use std::sync::mpsc;
use std::thread;

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

fn digest(bytes: &[u8]) -> String {
    let out: [u8; 32] = Sha256::digest(bytes).into();
    hex(&out)
}

#[test]
fn the_frozen_cell_of_the_set_reproduces() {
    // Canon, "The vectors of the wire".
    let step_key = [0x11u8; 32];
    let pipe_key = [0x22u8; 32];
    let handshake_secret = [0x33u8; 32];
    let window = 1000u64;

    let step_label = mt_derive::tag::step_label(&handshake_secret, window);
    assert_eq!(hex(&step_label), "eef748b204b940f9ede20ee4b9894248");

    let width = chunk_bytes().expect("the Decree names the width");
    let chunk: Vec<u8> = (0..width).map(|i| (0x90 + i) as u8).collect();
    let delivery = Delivery {
        delivery_id: [0x88u8; SEAL_BYTES],
        block_index: 3,
        block_count: 276,
        chunk,
    };
    let inner =
        cell::seal_pipe_with_nonce(&pipe_key, &[0x55u8; 12], &delivery).expect("the pipe seals");
    assert_eq!(
        digest(&inner),
        "6390c2fc9bfb2a44a75a787d131c1fbe7a94bef8f9d6b9b499788cd7e85ece19"
    );

    let slots = path_max().expect("the Decree names the slots");
    let seals: Vec<[u8; SEAL_BYTES]> = (0..slots)
        .map(|slot| [(0x70 + slot) as u8; SEAL_BYTES])
        .collect();
    let routing = Routing {
        target_commit: [0x66u8; 32],
        seals,
        inner: inner.clone(),
    };
    let sealed =
        cell::seal_cell_with_nonce(&step_key, &step_label, &[0x44u8; 12], &routing).expect("seals");
    assert_eq!(sealed.as_bytes().len(), cell_bytes().expect("named"));
    assert_eq!(
        digest(sealed.as_bytes()),
        "d799dd8b3581c2989edcd542f158467ff96bf83853d60c29978e635159304b14"
    );

    // And what was sealed opens to what went in.
    let back = cell::open_cell(&step_key, &sealed).expect("opens");
    assert_eq!(back, routing);
    assert_eq!(cell::open_pipe(&pipe_key, &back.inner), Ok(delivery));
}

#[test]
fn a_cell_of_the_wrong_length_is_discarded_in_silence() {
    let whole = vec![0u8; cell_bytes().expect("named")];
    assert!(cell::Cell::parse(&whole).is_ok());
    assert!(cell::Cell::parse(&whole[..whole.len() - 1]).is_err());
    let mut longer = whole;
    longer.push(0);
    assert!(cell::Cell::parse(&longer).is_err());
}

// The three machines of the test, each holding what it is entitled to hold and nothing else.
struct Hop {
    step_key_in: [u8; 32],
    step_key_out: [u8; 32],
    label_out: [u8; LABEL_BYTES],
    owner_secret: [u8; 32],
}

#[test]
fn two_machines_exchange_through_a_third_that_carries_and_learns_nothing() {
    let pipe_key = [0xC1u8; 32];
    let first_step = [0xA1u8; 32];
    let second_step = [0xB2u8; 32];
    let label_first = [0x01u8; LABEL_BYTES];
    let label_second = [0x02u8; LABEL_BYTES];
    let target_commit = [0x66u8; 32];
    let width = chunk_bytes().expect("named");
    let letter: Vec<u8> = (0..width).map(|i| (i % 251) as u8).collect();

    let (to_carrier, carrier_in) = mpsc::channel::<Vec<u8>>();
    let (to_receiver, receiver_in) = mpsc::channel::<Vec<u8>>();
    let (report, seen) = mpsc::channel::<(bool, bool, [u8; 32])>();
    let (drew, drawn) = mpsc::channel::<Vec<[u8; SEAL_BYTES]>>();
    let (read, was_read) = mpsc::channel::<Vec<[u8; SEAL_BYTES]>>();
    let (walked, path_walked) = mpsc::channel::<[u8; SEAL_BYTES]>();

    // The sender: it holds the pipe key it shares with the receiver and the key of its own step.
    let sender_letter = letter.clone();
    let sender = thread::spawn(move || {
        let delivery = Delivery {
            delivery_id: [0x99u8; SEAL_BYTES],
            block_index: 0,
            block_count: 1,
            chunk: sender_letter,
        };
        let inner = cell::seal_pipe(&pipe_key, &delivery).expect("seals");
        // The array is drawn by the one door that draws it: a sender filling it itself would be
        // free to fill it with zeros, and zeros are the count of steps crossed, published.
        let routing = Routing::new(target_commit, inner).expect("the array is drawn");
        drew.send(routing.seals.clone())
            .expect("the test is listening");
        let cell = cell::seal_cell(&first_step, &label_first, &routing).expect("seals");
        to_carrier
            .send(cell.as_bytes().to_vec())
            .expect("the carrier is listening");
    });

    // The carrier: it holds the keys of its two steps and its own secret, and no key of the pipe.
    let hop = Hop {
        step_key_in: first_step,
        step_key_out: second_step,
        label_out: label_second,
        owner_secret: [0xEEu8; 32],
    };
    let carrier = thread::spawn(move || {
        let bytes = carrier_in.recv().expect("a cell arrives");
        let cell = cell::Cell::parse(&bytes).expect("a cell of the one length");
        let routing = cell::open_cell(&hop.step_key_in, &cell).expect("its own step opens");
        // What it cannot do: open the pipe. It holds no key of it, and the two it does hold — the
        // keys of its own two steps — open nothing.
        let with_step_key = cell::open_pipe(&hop.step_key_in, &routing.inner).is_ok();
        let with_out_key = cell::open_pipe(&hop.step_key_out, &routing.inner).is_ok();
        report
            .send((with_step_key, with_out_key, routing.target_commit))
            .expect("the test is listening");
        let carried = cell::carry(
            &hop.step_key_in,
            &cell,
            &hop.owner_secret,
            &hop.step_key_out,
            &hop.label_out,
        )
        .expect("the hop carries");
        // No two points on a path carry one byte in common at the same place.
        assert_ne!(carried.as_bytes(), cell.as_bytes());
        to_receiver
            .send(carried.as_bytes().to_vec())
            .expect("the receiver is listening");
    });

    // The receiver: it holds the key of the last step and the pipe key.
    let expected = letter.clone();
    let receiver = thread::spawn(move || {
        let bytes = receiver_in.recv().expect("a cell arrives");
        let cell = cell::Cell::parse(&bytes).expect("a cell of the one length");
        let routing = cell::open_cell(&second_step, &cell).expect("the last step opens");
        let delivery = cell::open_pipe(&pipe_key, &routing.inner).expect("the pipe opens");
        assert_eq!(delivery.chunk, expected);
        // The commitment of the machine the cell is for crossed unchanged.
        assert_eq!(routing.target_commit, target_commit);
        // The hop wrote its seal at the slot its own seal selects, and the seal stands on the
        // path rather than on a label the hop before it chose.
        let path = mt_derive::tag::path_id(&routing.inner);
        let expected_seal = mt_derive::tag::relay_seal(&[0xEEu8; 32], &path);
        let slot = mt_derive::tag::seal_slot(&expected_seal).expect("named") as usize;
        assert_eq!(routing.seals[slot], expected_seal);
        // And no slot of the array stands at a value nobody drew: an untouched slot is the count
        // of steps a cell has crossed, readable by every hop that carries it.
        assert!(routing.seals.iter().all(|seal| *seal != [0u8; SEAL_BYTES]));
        read.send(routing.seals.clone())
            .expect("the test is listening");
        walked.send(path).expect("the test is listening");
    });

    sender.join().expect("the sender finishes");
    carrier.join().expect("the carrier finishes");
    receiver.join().expect("the receiver finishes");

    let (with_step_key, with_out_key, carried_commit) = seen.recv().expect("the carrier reports");
    assert!(
        !with_step_key,
        "the carrier opened the pipe with its own key"
    );
    assert!(
        !with_out_key,
        "the carrier opened the pipe with the next key"
    );
    assert_eq!(carried_commit, target_commit);

    // The array the sender drew and the array the receiver read agree everywhere but at the one
    // slot the hop rewrote: it rewrote its own and nothing else.
    let before = drawn.recv().expect("the sender reports what it drew");
    let after = was_read.recv().expect("the receiver reports what it read");
    assert_eq!(before.len(), path_max().expect("named"));
    let path = path_walked
        .recv()
        .expect("the receiver reports the path it read");
    let slot = mt_derive::tag::seal_slot(&mt_derive::tag::relay_seal(&[0xEEu8; 32], &path))
        .expect("named") as usize;
    for (position, (a, b)) in before.iter().zip(after.iter()).enumerate() {
        if position == slot {
            assert_ne!(a, b, "the hop wrote nothing at its own slot");
        } else {
            assert_eq!(a, b, "the hop rewrote a slot that is not its own");
        }
    }
}

// xorshift64*, seeded once: the same storm on every machine.
struct Rng(u64);

impl Rng {
    fn next(&mut self) -> u64 {
        let mut x = self.0;
        x ^= x >> 12;
        x ^= x << 25;
        x ^= x >> 27;
        self.0 = x;
        x.wrapping_mul(0x2545_F491_4F6C_DD1D)
    }
}

#[test]
fn every_decoder_of_this_wire_survives_a_storm_of_arbitrary_bytes() {
    // What crosses this wire comes from strangers. Every door that reads bytes is put to bytes
    // nobody meant: what it must never do is panic, and what it decodes it must encode back to the
    // bytes it was handed.
    use mt_wire::handshake::{Hello, HelloAnswer, HelloConfirm, HelloFinish};
    use mt_wire::message;

    let mut rng = Rng(0x4D54_2D57_4952_4531);
    let one = cell_bytes().expect("named");
    for _ in 0..2_000 {
        let len = (rng.next() % 80) as usize;
        let bytes: Vec<u8> = (0..len).map(|_| rng.next() as u8).collect();
        assert!(cell::Cell::parse(&bytes).is_err() || bytes.len() == one);
        let _ = message::parse_deposit(&bytes);
        let _ = message::parse_wake(&bytes);
        let _ = message::parse_state_query(&bytes);
        let _ = message::parse_slot_query(&bytes);
        let _ = message::parse_collect_answer(&bytes);
        if let Ok(proof) = message::parse_state_answer(&bytes) {
            assert_eq!(message::encode_state_answer(&proof), bytes);
        }
        if let Ok(published) = message::parse_slot_answer(&bytes) {
            assert_eq!(
                message::encode_slot_answer(&published).expect("encodes"),
                bytes
            );
        }
        let _ = Hello::parse(&bytes);
        let _ = HelloAnswer::parse(&bytes);
        let _ = HelloFinish::parse(&bytes);
        let _ = HelloConfirm::parse(&bytes);
    }

    // And at the widths that do decode: a cell of the one length parses whatever it holds, and a
    // unit of it opens under no key at all.
    for _ in 0..200 {
        let bytes: Vec<u8> = (0..one).map(|_| rng.next() as u8).collect();
        let parsed = cell::Cell::parse(&bytes).expect("a cell of the one length parses");
        assert_eq!(parsed.as_bytes(), &bytes[..]);
        assert!(cell::open_cell(&[0x11u8; 32], &parsed).is_err());
        assert!(mt_wire::link::open_unit(&[0x11u8; 32], &bytes).is_err());
        // Every slot a seal selects stands inside the array, whatever the seal holds.
        let slot = mt_derive::tag::seal_slot(&parsed.step_label()).expect("named");
        assert!((slot as usize) < path_max().expect("named"));
    }

    // The flights, at their own widths: what parses re-encodes to the bytes it came from.
    let mut hello = Hello {
        suite_id: 1,
        kem_key: [0u8; 1_184],
        answering_key: [0u8; 1_952],
    }
    .encode();
    for _ in 0..100 {
        for byte in hello[2..].iter_mut() {
            *byte = rng.next() as u8;
        }
        let parsed = Hello::parse(&hello).expect("a flight of the one length parses");
        assert_eq!(parsed.encode(), hello);
    }
}

// The property the seal of a step exists for, and the one the set says the bound on distinct
// owners protects nothing without: a path crossing two machines of one owner leaves **one** mark.
#[test]
fn one_owner_on_two_hops_of_one_path_leaves_one_seal_at_one_slot() {
    let pipe_key = [0x22u8; 32];
    let owner = [0xEEu8; 32];
    let keys = [[0x41u8; 32], [0x42u8; 32], [0x43u8; 32]];
    let labels = [
        [0x01u8; LABEL_BYTES],
        [0x02u8; LABEL_BYTES],
        [0x03u8; LABEL_BYTES],
    ];

    let delivery = Delivery {
        delivery_id: [0x99u8; SEAL_BYTES],
        block_index: 0,
        block_count: 1,
        chunk: vec![7u8; chunk_bytes().expect("named")],
    };
    let inner = cell::seal_pipe(&pipe_key, &delivery).expect("seals");
    let routing = Routing::new([0xCCu8; 32], inner).expect("draws its array");
    let drawn = routing.seals.clone();
    let mut cell =
        cell::seal_cell_with_nonce(&keys[0], &labels[0], &crate_nonce(), &routing).expect("seals");

    // Two hops in a row, both of one owner, each handed a label the hop before it chose.
    for step in 0..2 {
        cell = cell::carry(
            &keys[step],
            &cell,
            &owner,
            &keys[step + 1],
            &labels[step + 1],
        )
        .expect("the hop carries");
    }
    let carried = cell::open_cell(&keys[2], &cell).expect("the last step opens");

    let path = mt_derive::tag::path_id(&carried.inner);
    let seal = mt_derive::tag::relay_seal(&owner, &path);
    let slot = mt_derive::tag::seal_slot(&seal).expect("named") as usize;
    let marks: Vec<usize> = (0..drawn.len())
        .filter(|position| carried.seals[*position] != drawn[*position])
        .collect();
    assert_eq!(
        marks,
        vec![slot],
        "one owner on two hops left more than one mark"
    );
    assert_eq!(carried.seals[slot], seal);

    // The named wrong implementation: a seal taken over the label of the step. Each hop is handed
    // a different label, so that rule leaves two marks at two slots and a count of owners becomes
    // a count of machines — which is the bound protecting nothing.
    let first = mt_derive::tag::relay_seal(&owner, &labels[0]);
    let second = mt_derive::tag::relay_seal(&owner, &labels[1]);
    assert_ne!(first, second);
    assert_ne!(
        mt_derive::tag::seal_slot(&first).expect("named"),
        mt_derive::tag::seal_slot(&second).expect("named")
    );
}

// A nonce for a cell a test seals by hand: the door that draws one is of the crate, and what a
// test needs is any value of the width, since nothing here reads it back.
fn crate_nonce() -> [u8; 12] {
    [0x5Au8; 12]
}
