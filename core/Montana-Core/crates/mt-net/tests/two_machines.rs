// Two machines on one host meet by an acquaintance handed over out of band, run the four flights
// over a real socket and carry messages inside the channel they opened. What this holds is what the
// thirteenth stage stands on and what the set demands of the wire:
//
// a handshake reaches the machine an operator named, and a machine answering with another key is
// not that machine however well it holds the address; and **there is one size on the wire and no
// second** — the flights of a handshake cross as units of the same width as everything after them,
// so an observer counting bytes learns the same nothing from a handshake as from a letter.

use mt_net::{dial, Acquaintance, Answering, Door, NetError};
use mt_wire::message;

fn machine(secret: u8) -> Answering {
    Answering::of_machine(&[secret; 32])
}

// A door on a port the system chooses, answered on a thread of its own: the test is two machines
// and needs both of them running at once.
fn door_answering(
    answering: Answering,
) -> (
    String,
    std::thread::JoinHandle<Result<mt_net::Link, NetError>>,
) {
    let door = Door::open("127.0.0.1:0").expect("a door opens");
    let address = door.address().expect("a door knows where it stands");
    let handle = std::thread::spawn(move || door.answer(&answering));
    (address, handle)
}

fn met(near: u8, far: u8) -> (mt_net::Link, mt_net::Link) {
    let answering_side = machine(far);
    let far_key = *answering_side.public().as_bytes();
    let (address, waiting) = door_answering(answering_side);
    let opened = dial(
        &Acquaintance {
            address,
            answering_key: far_key,
        },
        &machine(near),
    )
    .expect("the handshake stands");
    let answered = waiting
        .join()
        .expect("the thread stands")
        .expect("answered");
    (opened, answered)
}

#[test]
fn two_machines_meet_by_an_acquaintance_and_carry_a_message_each_way() {
    let (mut opened, mut answered) = met(0xB2, 0xA1);
    // Both sides computed one transcript, which is what says the handshake is theirs.
    assert_eq!(opened.transcript(), answered.transcript());

    // A message of a fixed length its layout gives: the far side takes the boundary from the shape
    // it waits for and discards the padding of the last piece, as the set states.
    let query = message::encode_state_query(1_000, message::RootIndex::Machines, &[0x33; 32]);
    opened
        .send(message::Kind::StateQuery, &query)
        .expect("it crosses");
    let (kind, arrived) = answered.receive().expect("it arrives");
    // What arrived is read as what it is rather than guessed from its bytes: the kind rides in the
    // framing of every piece, under the seal, and it is what a machine dispatches on.
    assert_eq!(kind, message::Kind::StateQuery);
    assert_eq!(
        message::parse_state_query(&arrived[..message::state_query_len()]),
        Ok((1_000, message::RootIndex::Machines, [0x33; 32]))
    );

    // And a message carrying its own count, which needs no length from the wire at all.
    let answer = message::encode_slot_answer(b"what a slot publishes").expect("encodes");
    answered
        .send(message::Kind::SlotAnswer, &answer)
        .expect("it crosses");
    let (kind, back) = opened.receive().expect("it arrives");
    assert_eq!(kind, message::Kind::SlotAnswer);
    let declared = 2 + usize::from(u16::from_le_bytes([back[0], back[1]]));
    assert_eq!(
        message::parse_slot_answer(&back[..declared]),
        Ok(b"what a slot publishes".to_vec())
    );
}

#[test]
fn a_message_of_many_pieces_arrives_whole() {
    let (mut opened, mut answered) = met(0x11, 0x22);
    // An answer of several cells stands well past one piece, so the cutting and the reassembly are
    // exercised rather than skipped.
    let cell = vec![0x5Au8; mt_wire::cell_bytes().expect("named")];
    let many =
        message::encode_collect_answer(&[cell.clone(), cell.clone(), cell]).expect("encodes");
    opened
        .send(message::Kind::CollectAnswer, &many)
        .expect("it crosses");
    let (kind, arrived) = answered.receive().expect("it arrives");
    assert_eq!(kind, message::Kind::CollectAnswer);
    let declared = usize::from(u16::from_le_bytes([arrived[0], arrived[1]]));
    let width = 2 + declared * mt_wire::cell_bytes().expect("named");
    assert_eq!(declared, 3);
    assert_eq!(
        message::parse_collect_answer(&arrived[..width]).map(|c| c.len()),
        Ok(3)
    );
}

#[test]
fn a_machine_answering_with_another_key_is_not_the_one_the_acquaintance_names() {
    let far = machine(0xC3);
    let (address, answering) = door_answering(far);
    // The acquaintance names a key this machine does not answer with — whoever holds the address,
    // it is not the machine the operator meant.
    assert_eq!(
        dial(
            &Acquaintance {
                address,
                answering_key: *machine(0xEE).public().as_bytes(),
            },
            &machine(0xD4),
        )
        .err(),
        Some(NetError::NotTheMachineNamed)
    );
    // And the far side carries nothing: the initiator left before the third flight, so the
    // responder never verified anybody.
    assert!(answering.join().expect("the thread stands").is_err());
}

// The property the set states in as many words: there is one size on this wire and no second. A
// handshake is counted in bytes on the socket and every one of them stands in a whole unit.
#[test]
fn every_byte_of_a_handshake_crosses_in_units_of_the_one_width() {
    use std::io::Read;
    let width = mt_wire::cell_bytes().expect("named");
    let door = std::net::TcpListener::bind("127.0.0.1:0").expect("a door opens");
    let address = door.local_addr().expect("it stands").to_string();

    // A counter that speaks to nobody: it accepts one connection and reads until the initiator
    // gives up, so what it measures is what an observer of the line would measure.
    let counting = std::thread::spawn(move || {
        let (mut stream, _) = door.accept().expect("a connection arrives");
        let mut held = Vec::new();
        let mut chunk = [0u8; 4096];
        while let Ok(n) = stream.read(&mut chunk) {
            if n == 0 {
                break;
            }
            held.extend_from_slice(&chunk[..n]);
            // The first flight is whole once its units stand; reading further would wait for a
            // machine that will never answer.
            if held.len()
                >= width
                    * mt_wire::handshake::units_of(mt_wire::handshake::hello_len()).expect("named")
            {
                break;
            }
        }
        held.len()
    });

    let _ = dial(
        &Acquaintance {
            address,
            answering_key: *machine(0x77).public().as_bytes(),
        },
        &machine(0x88),
    );
    let seen = counting.join().expect("the counter stands");
    assert_eq!(
        seen % width,
        0,
        "a handshake put {seen} bytes on the wire, which is not whole units of {width}"
    );
    assert_eq!(
        seen,
        width * mt_wire::handshake::units_of(mt_wire::handshake::hello_len()).expect("named"),
        "the first flight occupies the units its own length gives"
    );
}
