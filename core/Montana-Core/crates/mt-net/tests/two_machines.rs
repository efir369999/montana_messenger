// Two machines on one host meet by an acquaintance handed over out of band, run the four flights
// over a real socket and carry messages inside the channel they opened. What this holds is what the
// thirteenth stage stands on and what the set demands of the wire:
//
// a handshake reaches the machine an operator named, and a machine answering with another key is
// not that machine however well it holds the address; a side that was not handed the line is
// answered by no byte at all; and **there is one size on the wire and no
// second** — the flights of a handshake cross as units of the same width as everything after them,
// so an observer counting bytes learns the same nothing from a handshake as from a letter.

use mt_net::{dial, Acquaintance, Answering, Door, NetError};
use mt_wire::handshake::HandshakeError;
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
    let far_kem = *answering_side.kem_public().as_bytes();
    let (address, waiting) = door_answering(answering_side);
    let opened = dial(
        &Acquaintance {
            address,
            answering_key: far_key,
            kem_key: far_kem,
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
    let far_kem = *far.kem_public().as_bytes();
    let (address, answering) = door_answering(far);
    // The acquaintance names a key this machine does not answer with — whoever holds the address,
    // it is not the machine the operator meant. That key is inside the transcript the initiator
    // computes, so the two sides hold two masters: the third flight opens to nothing at the far
    // side, which ends the connection without a fourth, and the initiator carries no link.
    assert!(dial(
        &Acquaintance {
            address,
            answering_key: *machine(0xEE).public().as_bytes(),
            kem_key: far_kem,
        },
        &machine(0xD4),
    )
    .is_err());
    // And the far side carries nothing: it never verified anybody.
    assert_eq!(
        answering.join().expect("the thread stands").err(),
        Some(NetError::Handshake(HandshakeError::Unopened))
    );
}

// **A door says nothing to a side that was not handed the line** (#22). Its first flight is made to
// a static key that is not this machine's; it opens to nothing, and the door writes not one byte —
// nor does it end the connection on that flight, since ending it at the last unit would tell a probe
// by its own length that a machine read it. A relay between the two watches the door: after the
// whole first flight it is silent and still open, and it lets go only once the far side does.
#[test]
fn a_side_without_the_line_is_answered_by_no_byte() {
    use std::io::{Read, Write};
    let far = machine(0xC5);
    let far_key = *far.public().as_bytes();
    let (door_address, answering) = door_answering(far);
    let width = mt_wire::cell_bytes().expect("named");
    let flight =
        width * mt_wire::handshake::units_of(mt_wire::handshake::hello_len()).expect("named");

    let relay = std::net::TcpListener::bind("127.0.0.1:0").expect("a relay opens");
    let address = relay.local_addr().expect("it stands").to_string();
    let watching = std::thread::spawn(move || {
        let (mut near, _) = relay.accept().expect("the stranger arrives");
        let mut door = std::net::TcpStream::connect(&door_address).expect("the door is reached");
        let mut first = vec![0u8; flight];
        near.read_exact(&mut first)
            .expect("the first flight arrives whole");
        door.write_all(&first).expect("it crosses");
        door.set_read_timeout(Some(std::time::Duration::from_secs(1)))
            .expect("a bound");
        let mut one = [0u8; 1];
        let heard = door.read(&mut one).map_err(|e| e.kind());
        // The stranger gives up, and the relay ends both sides as it would.
        let _ = door.shutdown(std::net::Shutdown::Both);
        let _ = near.shutdown(std::net::Shutdown::Both);
        heard
    });

    assert_eq!(
        dial(
            &Acquaintance {
                address,
                answering_key: far_key,
                kem_key: *machine(0xEF).kem_public().as_bytes(),
            },
            &machine(0xD6),
        )
        .err(),
        Some(NetError::Truncated {
            expected: width,
            found: 0
        })
    );
    let heard = watching.join().expect("the relay stands");
    assert!(
        matches!(
            heard,
            Err(std::io::ErrorKind::WouldBlock | std::io::ErrorKind::TimedOut)
        ),
        "after a whole first flight it could not open the door gave {heard:?} rather than silence"
    );
    assert_eq!(
        answering.join().expect("the thread stands").err(),
        Some(NetError::Handshake(HandshakeError::Unopened))
    );
}

// **A probe of the whole length of a first flight is held as one a byte short is** (#22). Bytes of
// that length which are no flight do not assemble, parse or open; the door neither answers nor
// closes on them, and lets go only when the probe ends the connection — and even then says nothing.
#[test]
fn a_probe_of_the_whole_length_of_a_first_flight_is_neither_answered_nor_closed() {
    use std::io::{Read, Write};
    let (address, answering) = door_answering(machine(0xC7));
    let flight = mt_wire::cell_bytes().expect("named")
        * mt_wire::handshake::units_of(mt_wire::handshake::hello_len()).expect("named");
    let mut probe = std::net::TcpStream::connect(&address).expect("the door is reached");
    probe.write_all(&vec![0xA5u8; flight]).expect("it crosses");
    probe
        .set_read_timeout(Some(std::time::Duration::from_secs(1)))
        .expect("a bound");
    let mut one = [0u8; 1];
    let heard = probe.read(&mut one).map_err(|e| e.kind());
    assert!(
        matches!(
            heard,
            Err(std::io::ErrorKind::WouldBlock | std::io::ErrorKind::TimedOut)
        ),
        "a probe of the length of a first flight was given {heard:?} rather than silence"
    );
    probe
        .shutdown(std::net::Shutdown::Write)
        .expect("the probe gives up");
    assert!(answering.join().expect("the thread stands").is_err());
    // The door has returned, so its end is already closed and the end is read at once, under the
    // bound already set: a socket whose far side closed may refuse a new bound on some systems.
    assert_eq!(probe.read(&mut one).map_err(|e| e.kind()), Ok(0));
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
            kem_key: *machine(0x77).kem_public().as_bytes(),
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

// The Author's decision G-4 (a) of #22: a machine is named by an IP literal and a port, and a name is
// refused before any lookup. The door below is reachable as "localhost", so a tree that handed names
// to the resolver would reach it; this one opens no socket and the door sees nobody.
#[test]
fn a_name_is_refused_before_any_lookup_and_reaches_nobody() {
    let door = std::net::TcpListener::bind("127.0.0.1:0").expect("a door opens");
    let port = door.local_addr().expect("it stands").port();
    door.set_nonblocking(true).expect("it waits for nobody");
    assert_eq!(
        dial(
            &Acquaintance {
                address: format!("localhost:{port}"),
                answering_key: *machine(0x31).public().as_bytes(),
                kem_key: *machine(0x31).kem_public().as_bytes(),
            },
            &machine(0x32),
        )
        .err(),
        Some(NetError::NotALiteral)
    );
    assert_eq!(
        door.accept().map(|_| ()).map_err(|e| e.kind()),
        Err(std::io::ErrorKind::WouldBlock),
        "nothing reached the door"
    );
    // And a door is opened at a literal alone.
    assert_eq!(Door::open("localhost:0").err(), Some(NetError::NotALiteral));
}
