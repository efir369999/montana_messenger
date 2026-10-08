// How the wire reaches another machine. Everything crossing between two machines is already one
// object of one length — `mt-wire` holds the cell, the four flights and the sealing of a unit —
// and what this crate adds is the socket underneath and the order of reading above: nothing here
// invents a byte of format, and every length it reads is asked of the crate that owns it.
//
// **There is one size on this wire and no second.** Everything crossing it is a unit of
// `cell_bytes` — the four flights of a handshake among them, which the set states travel the same
// way as everything after them: each occupies whole units, padded to the one width, sealed by
// nothing because the channel they open does not yet exist, and the label position of such a unit
// carries a value drawn like any secret. A side that wrote a flight as its own length would put two
// distinguishable sizes on the wire, which is the one thing a wire of one shape exists to remove.
//
// **Where a message ends is read from the message and never from the wire.** A reader assembles the
// pieces and takes the boundary from the bytes it has — every message of this wire either has one
// length its layout fixes or carries its own count — and discards the padding of the last piece. A
// length in the open would be a marker of size.
//
// **A machine is reached by an acquaintance handed over out of band.** There is no directory and
// none can be assembled: what one operator passes another is one address and the key that machine
// answers with, and a handshake reaching a machine that answers with another key ends in silence.
// An address is held by whoever holds it; the key is what an acquaintance is.

#![forbid(unsafe_code)]
#![deny(clippy::all)]

use mt_codec::size;
use mt_suite::{kem, sign};
use mt_wire::handshake::{
    self, Channel, HandshakeError, Hello, HelloAnswer, HelloConfirm, HelloFinish,
};
use mt_wire::link;
use mt_wire::message::Kind;
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream, ToSocketAddrs};
use std::time::Duration;
use zeroize::Zeroizing;

mt_codec::constants! {
    NET:
    /// The row of the suite table a machine of this era opens a handshake under. A flight naming a
    /// row nobody wrote is refused by `mt-wire`, which is where that table is read.
    pub const SUITE: u16 = 1, code "the row of the suite table this era opens a handshake under, which mt-wire refuses if no row answers it";
    /// How long this machine waits on a far side that has begun and stopped. It decides nothing of
    /// the protocol — no state moves, no round advances, no window closes on it — and it is of this
    /// tree because the set names no clock anywhere: what it decides is when this machine stops
    /// holding a thread for a stranger who opened a message and never finished it. The number is
    /// the largest message this wire carries — an answer of `collect_answer_max` cells, 433 666
    /// bytes — crossing at sixty-four kilobits a second, which is the slowest link a telephone of
    /// this network sustains: fifty-four seconds, taken up to sixty.
    pub const PATIENCE_SECONDS: u64 = 60, code "how long this machine waits on a far side that has begun a message and stopped, which is the largest message of this wire crossing at the slowest rate a telephone sustains";
}

#[derive(Debug, PartialEq, Eq)]
pub enum NetError {
    // What the socket answered. It reaches an operator and never a stranger: every refusal this
    // crate makes of a far side is silence, and what carries a reason is the local end alone.
    Socket { said: String },
    // A far side that stopped speaking, or spoke fewer bytes than the length its flight has.
    Truncated { expected: usize, found: usize },
    // The handshake refused. The far side is told nothing of it — the connection is dropped.
    Handshake(HandshakeError),
    // A machine answering with a key other than the one the acquaintance names.
    NotTheMachineNamed,
    // A value the wire could not draw, or a unit it could not seal or open.
    Wire(mt_wire::WireError),
    // A piece naming a kind the set does not write. The link ends rather than the bytes being read
    // as something they are not.
    UnknownKind { carried: u8 },
}

// A far side that has begun a message and stopped holds nothing of this machine but the thread
// reading it, and only for this long. Silence between messages is ordinary and is never bounded:
// what is bounded is silence **inside** one message, where the far side has already said how many
// units it is sending.
fn patience() -> Duration {
    Duration::from_secs(PATIENCE_SECONDS)
}

fn wait_without_end(stream: &TcpStream) -> Result<(), NetError> {
    stream.set_read_timeout(None).map_err(socket)
}

fn wait_with_patience(stream: &TcpStream) -> Result<(), NetError> {
    stream.set_read_timeout(Some(patience())).map_err(socket)
}

fn socket(e: std::io::Error) -> NetError {
    NetError::Socket {
        said: e.to_string(),
    }
}

fn wire(e: mt_wire::WireError) -> NetError {
    NetError::Wire(e)
}

// Exactly this many bytes, or the far side stopped mid-unit. A short read is not a shorter object
// of this protocol — there are no shorter objects.
fn read_exactly(stream: &mut TcpStream, count: usize) -> Result<Vec<u8>, NetError> {
    let mut held = vec![0u8; count];
    let mut filled = 0usize;
    while filled < count {
        match stream.read(&mut held[filled..]) {
            Ok(0) => {
                return Err(NetError::Truncated {
                    expected: count,
                    found: filled,
                })
            }
            Ok(n) => filled += n,
            Err(e) if e.kind() == std::io::ErrorKind::Interrupted => {}
            Err(e) => return Err(socket(e)),
        }
    }
    Ok(held)
}

fn write_whole(stream: &mut TcpStream, bytes: &[u8]) -> Result<(), NetError> {
    stream.write_all(bytes).map_err(socket)?;
    stream.flush().map_err(socket)
}

// A flight crosses as whole units of the one width, sealed by nothing: its pieces carry the framing
// every unit of this wire carries, and the label position of each carries a drawn value. What an
// observer sees is units of `cell_bytes`, exactly as it sees of everything after the handshake.
fn write_flight(stream: &mut TcpStream, flight: &[u8]) -> Result<(), NetError> {
    let width = mt_wire::cell_bytes().map_err(wire)?;
    // A flight is no message of the set and carries no kind: the position of the kind holds a drawn
    // byte, like the padding beside it, since a side reads the flight it awaits by the length that
    // flight has and nothing of the framing decides it.
    let kind = mt_wire::draw::filling(1).map_err(wire)?[0];
    for piece in link::pieces(kind, flight).map_err(wire)? {
        let label = mt_wire::draw::label().map_err(wire)?;
        let mut unit = Vec::with_capacity(width);
        unit.extend_from_slice(&label);
        unit.extend_from_slice(&piece);
        // The padding is drawn and never left at a value nobody drew: a tail of zeros where every
        // unit after the handshake carries a seal and a tag separates the two by one comparison,
        // and a middlebox matching that comparison matches this protocol.
        let filling = mt_wire::draw::filling(width - unit.len()).map_err(wire)?;
        unit.extend_from_slice(&filling);
        write_whole(stream, &unit)?;
    }
    Ok(())
}

// The units of one flight, of the count its own length gives — a reader knows the flight it is
// waiting for, so the count is read from the set rather than from the wire. What comes back is the
// flight at the length its layout fixes, the padding of the last piece discarded.
fn read_flight(stream: &mut TcpStream, length: usize) -> Result<Vec<u8>, NetError> {
    let width = mt_wire::cell_bytes().map_err(wire)?;
    let units = handshake::units_of(length).map_err(wire)?;
    // A piece is of the width the framing of this wire gives it; what stands after it inside the
    // unit is the padding that makes every unit one size, and handing that to the reassembly would
    // offer it a piece of a width it does not admit.
    let piece = link::FRAMING_BYTES + mt_wire::piece_bytes().map_err(wire)?;
    let mut pieces = Vec::with_capacity(units);
    for _ in 0..units {
        let unit = read_exactly(stream, width)?;
        pieces.push(unit[mt_wire::LABEL_BYTES..mt_wire::LABEL_BYTES + piece].to_vec());
    }
    let (_, assembled) = link::reassemble(&pieces)
        .map_err(wire)?
        .ok_or(NetError::Truncated {
            expected: length,
            found: 0,
        })?;
    if assembled.len() < length {
        return Err(NetError::Truncated {
            expected: length,
            found: assembled.len(),
        });
    }
    Ok(assembled[..length].to_vec())
}

// What one operator hands another: one address and the key that machine answers with. Nothing else
// is needed and nothing else exists — a first connection comes from the world, and what it yields
// is one handshake and never a map.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct Acquaintance {
    pub address: String,
    pub answering_key: [u8; size::SIGNING_PUBLIC_KEY],
}

// The pair a machine answers the wire with, drawn from its own secret and from nothing else, so
// the same machine on another start answers with the same key. The seed it is drawn from is held
// in a wiping wrapper and never leaves this function.
pub struct Answering {
    public: sign::PublicKey,
    secret: sign::SecretKey,
}

impl Answering {
    pub fn of_machine(machine_secret: &[u8; sign::SEED_BYTES]) -> Self {
        let expanded = mt_seed::answering_key(machine_secret);
        let mut seed = Zeroizing::new([0u8; sign::SEED_BYTES]);
        seed.copy_from_slice(&expanded[..sign::SEED_BYTES]);
        let (public, secret) = sign::keypair_from_seed(&seed);
        Self { public, secret }
    }

    pub fn public(&self) -> &sign::PublicKey {
        &self.public
    }
}

// A link that stands: the channel the four flights opened, the socket under it, and which of the
// two directional keys this side sends with.
pub struct Link {
    stream: TcpStream,
    channel: Channel,
    opened_it: bool,
}

impl Link {
    // What a caller compares out of band to know it reached the machine it meant. The transcript
    // is public by design and both signatures cover it.
    pub fn transcript(&self) -> &[u8; 32] {
        self.channel.transcript()
    }

    fn sending_key(&self) -> &[u8; 32] {
        if self.opened_it {
            self.channel.initiator_to_responder()
        } else {
            self.channel.responder_to_initiator()
        }
    }

    fn receiving_key(&self) -> &[u8; 32] {
        if self.opened_it {
            self.channel.responder_to_initiator()
        } else {
            self.channel.initiator_to_responder()
        }
    }

    // A message crosses as the pieces its own count names, each sealed into a unit of the one
    // width. The label of every unit is drawn, so a unit carrying a message and a cell carrying a
    // delivery are one shape to anybody watching.
    pub fn send(&mut self, kind: Kind, message: &[u8]) -> Result<(), NetError> {
        let pieces = link::pieces(kind.byte(), message).map_err(wire)?;
        let key = *self.sending_key();
        for piece in &pieces {
            let label = mt_wire::draw::label().map_err(wire)?;
            let unit = link::seal_unit(&key, &label, piece).map_err(wire)?;
            write_whole(&mut self.stream, &unit)?;
        }
        Ok(())
    }

    // The units of one message, read at the count its first piece declares. What comes back is what
    // the pieces assemble to, with the padding of the last piece still on it: **where a message ends
    // is read from the message and never from the wire**, so a caller takes the boundary from the
    // shape it is waiting for — every message of this wire either has one length its layout fixes or
    // carries its own count. A unit that does not open ends this link rather than being answered: a
    // reply saying so is information.
    //
    // **A message is its own count of units and no more.** A reader that kept reading until the
    // pieces happened to assemble would hold whatever a far side kept sending — one index repeated
    // for as long as it liked — and would sort them again at every unit, which is a machine's memory
    // and a machine's time spent by a stranger who has passed a handshake and nothing else. The
    // count is read once, held against the largest message this wire carries, and the link ends if
    // the units it names do not assemble.
    pub fn receive(&mut self) -> Result<(Kind, Vec<u8>), NetError> {
        let width = mt_wire::cell_bytes().map_err(wire)?;
        let key = *self.receiving_key();
        // Silence between two messages is ordinary and is never bounded; silence inside one is
        // bounded, because the far side has already said how many units it is sending.
        wait_without_end(&self.stream)?;
        let opening = read_exactly(&mut self.stream, width)?;
        wait_with_patience(&self.stream)?;
        let mut held: Vec<Zeroizing<Vec<u8>>> = Vec::new();
        held.push(link::open_unit(&key, &opening).map_err(wire)?);
        let (_, count, carried) = link::declared(&held[0]).map_err(wire)?;
        // A kind outside the vocabulary the set writes ends the link: a machine that guessed would
        // answer a stranger's bytes as something they are not.
        let kind = Kind::of(carried).ok_or(NetError::UnknownKind { carried })?;
        let bound = link::pieces_max().map_err(wire)?;
        if count == 0 || count > bound {
            return Err(NetError::Wire(mt_wire::WireError::WrongLength {
                expected: bound,
                found: count,
            }));
        }
        held.reserve(count.saturating_sub(1));
        for _ in 1..count {
            let unit = read_exactly(&mut self.stream, width)?;
            held.push(link::open_unit(&key, &unit).map_err(wire)?);
        }
        let view: Vec<&[u8]> = held.iter().map(|piece| piece.as_slice()).collect();
        let (_, message) = link::reassemble(&view)
            .map_err(wire)?
            .ok_or(NetError::Truncated {
                expected: count,
                found: held.len(),
            })?;
        Ok((kind, message))
    }
}

// One handshake's encapsulation keypair, drawn afresh through the one door this tree draws at. A
// machine reusing one across handshakes would let an observer join two connections it holds no
// key of.
fn ephemeral_kem() -> Result<(kem::PublicKey, kem::SecretKey), NetError> {
    let seed = mt_wire::draw::block::<{ kem::SEED_BYTES }>().map_err(wire)?;
    Ok(kem::keypair_from_seed(&seed))
}

// The side that opens a connection is the initiator. It runs the first and third flights, and it
// carries a channel only once the fourth has verified.
pub fn dial(to: &Acquaintance, answering: &Answering) -> Result<Link, NetError> {
    let address = to
        .address
        .to_socket_addrs()
        .map_err(socket)?
        .next()
        .ok_or_else(|| NetError::Socket {
            said: "the address names no socket".to_string(),
        })?;
    let mut stream = TcpStream::connect(address).map_err(socket)?;
    stream.set_nodelay(true).map_err(socket)?;
    stream.set_write_timeout(Some(patience())).map_err(socket)?;
    wait_with_patience(&stream)?;

    let (kem_public, kem_secret) = ephemeral_kem()?;
    let hello = Hello {
        suite_id: SUITE,
        kem_key: *kem_public.as_bytes(),
        answering_key: *answering.public.as_bytes(),
    };
    write_flight(&mut stream, &hello.encode())?;

    let answer = HelloAnswer::parse(&read_flight(&mut stream, handshake::hello_answer_len())?)
        .map_err(NetError::Handshake)?;
    if answer.answering_key != to.answering_key {
        return Err(NetError::NotTheMachineNamed);
    }

    let ss_r = kem::decapsulate(&kem_secret, &kem::Ciphertext::from_bytes(answer.kem_ct));
    let their_kem = kem::PublicKey::from_bytes(answer.kem_key);
    let (ct_i, ss_i) =
        kem::encapsulate(&their_kem).map_err(|_| wire(mt_wire::WireError::Undrawn))?;

    let transcript = handshake::transcript(
        SUITE,
        &hello.answering_key,
        &answer.answering_key,
        &hello.kem_key,
        &answer.kem_key,
        ct_i.as_bytes(),
        &answer.kem_ct,
    );
    let finish = HelloFinish {
        kem_ct: *ct_i.as_bytes(),
        signature: handshake::sign_initiator(&answering.secret, &transcript)
            .map_err(NetError::Handshake)?,
    };
    write_flight(&mut stream, &finish.encode())?;

    let confirm = HelloConfirm::parse(&read_flight(&mut stream, handshake::hello_confirm_len())?)
        .map_err(NetError::Handshake)?;
    let channel = handshake::initiator_channel(
        &hello,
        &answer,
        ct_i.as_bytes(),
        ss_i.as_bytes(),
        ss_r.as_bytes(),
        &confirm,
    )
    .map_err(NetError::Handshake)?;
    Ok(Link {
        stream,
        channel,
        opened_it: true,
    })
}

// A machine reachable from outside answers links it did not choose. What it answers with is the
// second and fourth flights, and it carries a channel only once the third has verified.
pub struct Door(TcpListener);

impl Door {
    pub fn open(address: &str) -> Result<Self, NetError> {
        Ok(Self(TcpListener::bind(address).map_err(socket)?))
    }

    // Where this door actually stands. An operator asking for port zero is told which one the
    // system gave, so the acquaintance it hands over names the door that exists.
    pub fn address(&self) -> Result<String, NetError> {
        Ok(self.0.local_addr().map_err(socket)?.to_string())
    }

    pub fn answer(&self, answering: &Answering) -> Result<Link, NetError> {
        let (mut stream, _) = self.0.accept().map_err(socket)?;
        stream.set_nodelay(true).map_err(socket)?;
        stream.set_write_timeout(Some(patience())).map_err(socket)?;
        // The four flights stand under the same patience as a message: a far side that opens a
        // connection and says nothing holds a thread of this machine and nothing else, and only for
        // as long as this.
        wait_with_patience(&stream)?;

        let hello = Hello::parse(&read_flight(&mut stream, handshake::hello_len())?)
            .map_err(NetError::Handshake)?;
        let (kem_public, kem_secret) = ephemeral_kem()?;
        let their_kem = kem::PublicKey::from_bytes(hello.kem_key);
        let (ct_r, ss_r) =
            kem::encapsulate(&their_kem).map_err(|_| wire(mt_wire::WireError::Undrawn))?;
        let answer = HelloAnswer {
            suite_id: hello.suite_id,
            kem_key: *kem_public.as_bytes(),
            kem_ct: *ct_r.as_bytes(),
            answering_key: *answering.public.as_bytes(),
        };
        write_flight(&mut stream, &answer.encode())?;

        let finish = HelloFinish::parse(&read_flight(&mut stream, handshake::hello_finish_len())?)
            .map_err(NetError::Handshake)?;
        let ss_i = kem::decapsulate(&kem_secret, &kem::Ciphertext::from_bytes(finish.kem_ct));
        let channel = handshake::responder_channel(
            &hello,
            &answer,
            &finish,
            ss_i.as_bytes(),
            ss_r.as_bytes(),
        )
        .map_err(NetError::Handshake)?;

        let transcript = *channel.transcript();
        let confirm = HelloConfirm {
            signature: handshake::sign_responder(&answering.secret, &transcript)
                .map_err(NetError::Handshake)?,
        };
        write_flight(&mut stream, &confirm.encode())?;
        Ok(Link {
            stream,
            channel,
            opened_it: false,
        })
    }
}
