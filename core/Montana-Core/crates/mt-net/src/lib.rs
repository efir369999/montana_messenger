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
// none can be assembled: what one operator passes another is one address, the key that machine
// answers with and the static key a first flight is encapsulated to. A first flight not made to that
// static key opens to nothing and is answered by no byte, so whoever was not handed the line cannot
// tell a machine from a closed device; a handshake reaching a machine that answers with another key
// ends in silence. An address is held by whoever holds it; the two keys are what an acquaintance is.

#![forbid(unsafe_code)]
#![deny(clippy::all)]

use mt_codec::size;
use mt_suite::{kem, sign};
use mt_wire::handshake::{
    self, Channel, HandshakeError, Hello, HelloAnswer, HelloConfirm, HelloFinish, Keys,
};
use mt_wire::link;
use mt_wire::message::{self, Kind};
use std::io::{Read, Write};
use std::net::{SocketAddr, TcpListener, TcpStream};
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
    /// the largest message this wire carries — an answer of `collect_answer_max` cells, 768 770
    /// bytes — crossing at sixty-four kilobits a second, which is the slowest link a telephone of
    /// this network sustains: ninety-six seconds, taken up to one hundred and twenty.
    pub const PATIENCE_SECONDS: u64 = 120, code "how long this machine waits on a far side that has begun a message and stopped, which is the largest message of this wire crossing at the slowest rate a telephone sustains";
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
    // A machine whose fourth flight does not open or does not verify under the key the acquaintance
    // names: another machine at that address, or none.
    NotTheMachineNamed,
    // A value the wire could not draw, or a unit it could not seal or open.
    Wire(mt_wire::WireError),
    // A piece naming a kind the set does not write. The link ends rather than the bytes being read
    // as something they are not.
    UnknownKind { carried: u8 },
    // A message of a renewal no renewal of this link awaits, or one a caller asked to send. The link
    // ends rather than taking a key from it: the three messages travel inside the link, in their one
    // order, and nowhere else.
    RenewalOutOfTurn,
    // An address that is not an IP literal and a port. It carries nothing of what was given, so the
    // refusal names no address on a line an operator's terminal keeps.
    NotALiteral,
    // A sending key that has sealed twice its ceiling: this side offered at `rekey_units` and the
    // far side has not completed a renewal in as many units again. The link ends rather than one
    // key covering a volume without bound (Network, "And when the chain does not advance").
    KeyExhausted,
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

// An address as an IP literal and a port, read without the resolver. A name handed to the system's
// resolver is a question put to a server of names on the open network -- which machine this one is
// about to reach, or to stand as -- asked before the first flight and outside every seal of this
// wire. So a name is refused here, before any lookup and before a socket opens (the Author's
// decision G-4 (a) of #22, 29.10.2026).
fn literal(address: &str) -> Result<SocketAddr, NetError> {
    address
        .parse::<SocketAddr>()
        .map_err(|_| NetError::NotALiteral)
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
// waiting for, so the count is read from the set rather than from the wire. What this reads is the
// units and nothing of what they hold: a socket that ends or stops inside them is told apart here
// from units that arrived whole and say nothing, which `assemble_flight` decides.
fn read_flight_units(stream: &mut TcpStream, length: usize) -> Result<Vec<Vec<u8>>, NetError> {
    let width = mt_wire::cell_bytes().map_err(wire)?;
    let units = handshake::units_of(length).map_err(wire)?;
    let mut held = Vec::with_capacity(units);
    for _ in 0..units {
        held.push(read_exactly(stream, width)?);
    }
    Ok(held)
}

// What units read whole assemble to: the flight at the length its layout fixes, the padding of the
// last piece discarded.
fn assemble_flight(units: &[Vec<u8>], length: usize) -> Result<Vec<u8>, NetError> {
    // A piece is of the width the framing of this wire gives it; what stands after it inside the
    // unit is the padding that makes every unit one size, and handing that to the reassembly would
    // offer it a piece of a width it does not admit.
    let piece = link::FRAMING_BYTES + mt_wire::piece_bytes().map_err(wire)?;
    let pieces: Vec<Vec<u8>> = units
        .iter()
        .map(|unit| unit[mt_wire::LABEL_BYTES..mt_wire::LABEL_BYTES + piece].to_vec())
        .collect();
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

fn read_flight(stream: &mut TcpStream, length: usize) -> Result<Vec<u8>, NetError> {
    assemble_flight(&read_flight_units(stream, length)?, length)
}

// **A refused first flight ends the way an unfinished one does.** A door that dropped the connection
// the moment the last unit of a flight it could not open arrived would answer a probe by the length
// it sent — one unit short is held for the whole patience, the full count is closed at once — and
// that difference is the machine. So what follows a refusal is read and discarded, under the same
// patience between two reads as inside a flight, until the far side ends the connection or falls
// silent for that patience: a side that stops is let go exactly when it would have been let go
// inside a flight. A side that keeps sending is read no further than the largest message this wire
// carries, which is as far as a reader inside a message ever reads. Nothing is written either way.
fn hold_silent(stream: &mut TcpStream) {
    let ceiling = match (mt_wire::cell_bytes(), link::pieces_max()) {
        (Ok(width), Ok(units)) => width.saturating_mul(units),
        _ => return,
    };
    if wait_with_patience(stream).is_err() {
        return;
    }
    let mut sink = [0u8; 4096];
    let mut discarded = 0usize;
    while discarded < ceiling {
        let room = sink.len().min(ceiling - discarded);
        match stream.read(&mut sink[..room]) {
            Ok(0) => return,
            Ok(n) => discarded += n,
            Err(e) if e.kind() == std::io::ErrorKind::Interrupted => {}
            Err(_) => return,
        }
    }
}

// What one operator hands another: one address, the key that machine answers with, and the static
// key a first flight to it is encapsulated to. Nothing else is needed and nothing else exists — a
// first connection comes from the world, and what it yields is one handshake and never a map.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct Acquaintance {
    pub address: String,
    pub answering_key: [u8; size::SIGNING_PUBLIC_KEY],
    pub kem_key: [u8; size::KEM_PUBLIC_KEY],
}

// The two pairs a machine answers the wire with, both drawn from its own secret and from nothing
// else, under two domains, so the same machine on another start answers with the same keys and
// neither key says anything of the other. The seeds they are drawn from are held in wiping wrappers
// and never leave this function.
pub struct Answering {
    public: sign::PublicKey,
    secret: sign::SecretKey,
    kem_public: kem::PublicKey,
    kem_secret: kem::SecretKey,
}

impl Answering {
    pub fn of_machine(machine_secret: &[u8; sign::SEED_BYTES]) -> Self {
        let expanded = mt_seed::answering_key(machine_secret);
        let mut seed = Zeroizing::new([0u8; sign::SEED_BYTES]);
        seed.copy_from_slice(&expanded[..sign::SEED_BYTES]);
        let (public, secret) = sign::keypair_from_seed(&seed);
        let expanded = mt_seed::answering_kem_seed(machine_secret);
        let mut seed = Zeroizing::new([0u8; kem::SEED_BYTES]);
        seed.copy_from_slice(&expanded[..kem::SEED_BYTES]);
        let (kem_public, kem_secret) = kem::keypair_from_seed(&seed);
        Self {
            public,
            secret,
            kem_public,
            kem_secret,
        }
    }

    pub fn public(&self) -> &sign::PublicKey {
        &self.public
    }

    // The static key the acquaintance of this machine names beside its answering key.
    pub fn kem_public(&self) -> &kem::PublicKey {
        &self.kem_public
    }
}

// A key or a secret of a link: thirty-two bytes in a wrapper that wipes them.
type Key = Zeroizing<[u8; 32]>;

// A link that stands: the socket under it, which side opened it, and the secret of the link with
// the two directional keys derived from it (Network, "How a link renews its keys"). The secret
// begins as the master of the handshake and walks one way at every renewal, and the keys this side
// seals and opens with are derived from it exactly as the handshake derives them from the master.
// The channel the four flights opened is taken apart where the link is made and wipes itself, so no
// key of the handshake outlives the first renewal.
pub struct Link {
    stream: TcpStream,
    transcript: [u8; 32],
    opened_it: bool,
    secret: Key,
    sending: Key,
    receiving: Key,
    // The receiving key before the last renewal, kept only until the first unit that opens under the
    // new one: the far side seals under it until it has taken the renewal in.
    previous_receiving: Option<Key>,
    renewal: Renewal,
    // The units this side has sealed under its current sending key, and the ceiling at which it
    // offers a renewal whatever the window (`rekey_units` of the Decree). The count is this side's
    // own, of what it sealed, and never crosses the wire, so nothing can diverge on it.
    sealed: usize,
    ceiling: usize,
    // The latest window whoever runs this side has told it, and the window the secret of the link
    // was set in. A link reads no clock and no chain: the window is told to it, and the first window
    // it is told stands for the window of its handshake.
    window: Option<u64>,
    set_in: Option<u64>,
}

// A renewal this side has begun or answered and that has not completed. What it holds is the
// decapsulation key this side drew for it and, once this side has answered, what its answer carried
// and opened to; the key and the shared secret wipe themselves when the renewal completes or is
// replaced.
enum Renewal {
    Idle,
    Offered(Box<Offer>),
    Answered(Box<Answer>),
}

struct Offer {
    secret: kem::SecretKey,
    public: [u8; size::KEM_PUBLIC_KEY],
}

struct Answer {
    secret: kem::SecretKey,
    public: [u8; size::KEM_PUBLIC_KEY],
    theirs: [u8; size::KEM_PUBLIC_KEY],
    encapsulated: [u8; kem::CIPHERTEXT_BYTES],
    shared: kem::SharedSecret,
}

// What one side put into a renewal: the encapsulation key it drew, the encapsulation it made to the
// key of the other side, and what that encapsulation opens to.
struct Material<'a> {
    public: &'a [u8; size::KEM_PUBLIC_KEY],
    encapsulated: &'a [u8; kem::CIPHERTEXT_BYTES],
    shared: &'a [u8; 32],
}

// The two directional keys of a secret of a link, as this side uses them: the side that opened the
// link seals with the key from initiator to responder and opens with the other, the other side the
// reverse, under the two domains of the handshake.
fn directional(secret: &[u8; 32], opened_it: bool) -> (Key, Key) {
    let to_responder = Zeroizing::new(handshake::initiator_to_responder(secret));
    let to_initiator = Zeroizing::new(handshake::responder_to_initiator(secret));
    if opened_it {
        (to_responder, to_initiator)
    } else {
        (to_initiator, to_responder)
    }
}

// The three messages of a renewal are messages of the link and travel inside it alone: a caller
// neither sends one nor is handed one.
fn of_a_renewal(kind: Kind) -> bool {
    matches!(
        kind,
        Kind::RenewOffer | Kind::RenewAnswer | Kind::RenewFinish
    )
}

// A message of a renewal has the one length its layout fixes, and what the pieces assemble to
// carries the padding of the last piece after it.
fn of_its_length(bytes: &[u8], length: usize) -> Result<&[u8], NetError> {
    bytes.get(..length).ok_or(NetError::Truncated {
        expected: length,
        found: bytes.len(),
    })
}

fn undrawn(_: kem::Undrawn) -> NetError {
    wire(mt_wire::WireError::Undrawn)
}

// The end of a link, held apart from it: a thread reading a link waits without end between two
// messages, so whoever must stop that thread ends the socket under it rather than waiting for the
// far side to. Shutting the socket both ways returns the reading thread at once, on every copy of
// the socket.
pub struct Closer {
    stream: TcpStream,
}

impl Closer {
    // A socket already shut, or one the far side already closed, has nothing left to end.
    pub fn close(&self) {
        let _ = self.stream.shutdown(std::net::Shutdown::Both);
    }
}

impl Link {
    fn standing(stream: TcpStream, channel: Channel, opened_it: bool) -> Result<Self, NetError> {
        let ceiling = mt_wire::rekey_units().map_err(wire)?;
        let secret = Zeroizing::new(*channel.master());
        let (sending, receiving) = directional(&secret, opened_it);
        Ok(Self {
            stream,
            transcript: *channel.transcript(),
            opened_it,
            secret,
            sending,
            receiving,
            previous_receiving: None,
            renewal: Renewal::Idle,
            sealed: 0,
            ceiling,
            window: None,
            set_in: None,
        })
    }

    // What a caller compares out of band to know it reached the machine it meant. The transcript
    // is public by design and both signatures cover it, and a renewal adds nothing to compare.
    pub fn transcript(&self) -> &[u8; 32] {
        &self.transcript
    }

    pub fn closer(&self) -> Result<Closer, NetError> {
        let stream = self.stream.try_clone().map_err(socket)?;
        Ok(Closer { stream })
    }

    // The window this side is in, told by whoever runs it. Windows only advance here: a window
    // earlier than one already told changes nothing.
    pub fn learn_window(&mut self, window: u64) {
        let latest = self.window.map_or(window, |known| known.max(window));
        self.window = Some(latest);
        if self.set_in.is_none() {
            self.set_in = Some(latest);
        }
    }

    // A renewal is due when no renewal of either side is under way and this side is in a window
    // later than the one its secret was set in, or has sealed `rekey_units` units under its sending
    // key: a link renews once in a window, and a window that stalls holds no key over a volume
    // without bound.
    fn due(&self) -> bool {
        let later = match (self.set_in, self.window) {
            (Some(set), Some(now)) => now > set,
            _ => false,
        };
        (later || self.sealed >= self.ceiling) && matches!(self.renewal, Renewal::Idle)
    }

    // A message crosses as the pieces its own count names, each sealed into a unit of the one
    // width under the sending key this side holds. The label of every unit is drawn, so a unit
    // carrying a message and a cell carrying a delivery are one shape to anybody watching.
    //
    // A key seals at most twice `rekey_units` units of its callers' messages: an offer goes out at
    // the ceiling, and a far side that has not completed the renewal within as many units again
    // leaves this side no key it may go on sealing under. The whole message is refused before its
    // first unit, so no message ends halfway on the wire. The messages of a renewal are never
    // refused for the count: a key carries at most one offer, one answer and one finish, since any
    // other ends the link, and refusing them would end the link at the moment it renews.
    fn seal(&mut self, kind: Kind, message: &[u8]) -> Result<(), NetError> {
        let pieces = link::pieces(kind.byte(), message).map_err(wire)?;
        if !of_a_renewal(kind)
            && self.sealed.saturating_add(pieces.len()) > self.ceiling.saturating_mul(2)
        {
            return Err(NetError::KeyExhausted);
        }
        for piece in &pieces {
            let label = mt_wire::draw::label().map_err(wire)?;
            let unit = link::seal_unit(&self.sending, &label, piece).map_err(wire)?;
            write_whole(&mut self.stream, &unit)?;
            self.sealed = self.sealed.saturating_add(1);
        }
        Ok(())
    }

    // A message of a caller, sent under the keys the link holds. A side that has not been told its
    // window cannot know the window has moved, but it knows its own count: at the ceiling it offers
    // before the message exactly as it would in a later window.
    pub fn send(&mut self, kind: Kind, message: &[u8]) -> Result<(), NetError> {
        if of_a_renewal(kind) {
            return Err(NetError::RenewalOutOfTurn);
        }
        if self.due() {
            self.offer()?;
        }
        self.seal(kind, message)
    }

    // A message of a caller in a window. A side about to send in a window later than the one its
    // secret was set in first sends an offer and then its message, which travels under the keys the
    // link holds: the switch takes place when the renewal completes, so a renewal adds units and
    // never a wait, and a link that carries nothing in a window renews nothing in it.
    pub fn send_in(&mut self, window: u64, kind: Kind, message: &[u8]) -> Result<(), NetError> {
        if of_a_renewal(kind) {
            return Err(NetError::RenewalOutOfTurn);
        }
        self.learn_window(window);
        self.send(kind, message)
    }

    fn offer(&mut self) -> Result<(), NetError> {
        let (public, secret) = ephemeral_kem()?;
        let public = *public.as_bytes();
        self.seal(Kind::RenewOffer, &message::encode_renew_offer(&public))?;
        self.renewal = Renewal::Offered(Box::new(Offer { secret, public }));
        Ok(())
    }

    // The next message of the far side. A message of a renewal is taken inside the link and never
    // handed on: the reader goes on to the message after it, so a caller reads what it always read.
    pub fn receive(&mut self) -> Result<(Kind, Vec<u8>), NetError> {
        loop {
            let (kind, message) = self.open_message()?;
            match kind {
                Kind::RenewOffer => self.offered(&message)?,
                Kind::RenewAnswer => self.answered(&message)?,
                Kind::RenewFinish => self.finished(&message)?,
                _ => return Ok((kind, message)),
            }
        }
    }

    // The same, told the window this side is in, so a renewal this side completes is set in it.
    pub fn receive_in(&mut self, window: u64) -> Result<(Kind, Vec<u8>), NetError> {
        self.learn_window(window);
        self.receive()
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
    fn open_message(&mut self) -> Result<(Kind, Vec<u8>), NetError> {
        let width = mt_wire::cell_bytes().map_err(wire)?;
        // Silence between two messages is ordinary and is never bounded; silence inside one is
        // bounded, because the far side has already said how many units it is sending.
        wait_without_end(&self.stream)?;
        let opening = read_exactly(&mut self.stream, width)?;
        wait_with_patience(&self.stream)?;
        let (key, first) = self.open_first(&opening)?;
        let mut held: Vec<Zeroizing<Vec<u8>>> = vec![first];
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

    // The first unit of a message decides the key the rest of it opens under: the current receiving
    // key, or the previous one while the far side has not yet taken a renewal in. The first unit
    // that opens under the current key erases the previous one, and a unit that opens under neither
    // ends the link, exactly as a unit that does not open ends it.
    fn open_first(&mut self, unit: &[u8]) -> Result<(Key, Zeroizing<Vec<u8>>), NetError> {
        match link::open_unit(&self.receiving, unit) {
            Ok(piece) => {
                self.previous_receiving = None;
                Ok((self.receiving.clone(), piece))
            }
            Err(refused) => {
                let earlier = self.previous_receiving.as_ref().ok_or(wire(refused))?;
                let piece = link::open_unit(earlier, unit).map_err(wire)?;
                Ok((earlier.clone(), piece))
            }
        }
    }

    // An offer of the far side. Where both sides offered, the offer of the side that opened the link
    // stands: that side discards the other's in silence, and the other erases the key it drew and
    // answers. An offer while this side has answered one and awaits its finish is out of turn.
    fn offered(&mut self, bytes: &[u8]) -> Result<(), NetError> {
        let theirs = message::parse_renew_offer(of_its_length(bytes, message::renew_offer_len())?)
            .map_err(wire)?;
        match self.renewal {
            Renewal::Offered(_) if self.opened_it => return Ok(()),
            Renewal::Answered(_) => return Err(NetError::RenewalOutOfTurn),
            _ => {}
        }
        // Whatever this side offered is erased before it answers: one renewal stands.
        self.renewal = Renewal::Idle;
        let (encapsulated, shared) =
            kem::encapsulate(&kem::PublicKey::from_bytes(theirs)).map_err(undrawn)?;
        let (public, secret) = ephemeral_kem()?;
        let public = *public.as_bytes();
        let encapsulated = *encapsulated.as_bytes();
        self.seal(
            Kind::RenewAnswer,
            &message::encode_renew_answer(&encapsulated, &public),
        )?;
        self.renewal = Renewal::Answered(Box::new(Answer {
            secret,
            public,
            theirs,
            encapsulated,
            shared,
        }));
        Ok(())
    }

    // The answer to this side's offer: open what the far side encapsulated, encapsulate to the key it
    // drew, seal the finish under the keys this side held, and everything after it under the new.
    fn answered(&mut self, bytes: &[u8]) -> Result<(), NetError> {
        let (their_encapsulation, theirs) =
            message::parse_renew_answer(of_its_length(bytes, message::renew_answer_len())?)
                .map_err(wire)?;
        let Renewal::Offered(offer) = std::mem::replace(&mut self.renewal, Renewal::Idle) else {
            return Err(NetError::RenewalOutOfTurn);
        };
        let Offer { secret, public } = *offer;
        let their_shared =
            kem::decapsulate(&secret, &kem::Ciphertext::from_bytes(their_encapsulation));
        drop(secret);
        let (encapsulated, shared) =
            kem::encapsulate(&kem::PublicKey::from_bytes(theirs)).map_err(undrawn)?;
        self.seal(
            Kind::RenewFinish,
            &message::encode_renew_finish(encapsulated.as_bytes()),
        )?;
        self.switch(
            Material {
                public: &public,
                encapsulated: encapsulated.as_bytes(),
                shared: shared.as_bytes(),
            },
            Material {
                public: &theirs,
                encapsulated: &their_encapsulation,
                shared: their_shared.as_bytes(),
            },
        );
        Ok(())
    }

    // The finish of the renewal this side answered: open it, and seal every unit after it under the
    // new sending key.
    fn finished(&mut self, bytes: &[u8]) -> Result<(), NetError> {
        let their_encapsulation =
            message::parse_renew_finish(of_its_length(bytes, message::renew_finish_len())?)
                .map_err(wire)?;
        let Renewal::Answered(answer) = std::mem::replace(&mut self.renewal, Renewal::Idle) else {
            return Err(NetError::RenewalOutOfTurn);
        };
        let Answer {
            secret,
            public,
            theirs,
            encapsulated,
            shared,
        } = *answer;
        let their_shared =
            kem::decapsulate(&secret, &kem::Ciphertext::from_bytes(their_encapsulation));
        drop(secret);
        self.switch(
            Material {
                public: &public,
                encapsulated: &encapsulated,
                shared: shared.as_bytes(),
            },
            Material {
                public: &theirs,
                encapsulated: &their_encapsulation,
                shared: their_shared.as_bytes(),
            },
        );
        Ok(())
    }

    // The new secret folds in the order of the roles of the handshake — the material of the side
    // that opened the link first — and never in the order of the renewal, so both sides reach one
    // value whichever of them offered. The previous secret is erased here; the previous receiving key
    // stays until the first unit that opens under the new one.
    fn switch(&mut self, mine: Material<'_>, theirs: Material<'_>) {
        let (initiator, responder) = if self.opened_it {
            (mine, theirs)
        } else {
            (theirs, mine)
        };
        let next = Zeroizing::new(handshake::renewed(
            &self.secret,
            initiator.shared,
            responder.shared,
            initiator.public,
            responder.public,
            initiator.encapsulated,
            responder.encapsulated,
        ));
        let (sending, receiving) = directional(&next, self.opened_it);
        self.secret = next;
        self.sending = sending;
        self.sealed = 0;
        self.previous_receiving = Some(std::mem::replace(&mut self.receiving, receiving));
        self.set_in = self.window;
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
// carries a channel only once the fourth has opened and verified under the key the line names. Its
// own answering key crosses only sealed, under a key of the encapsulation to the static key the line
// names, and the responder's never crosses: the line already holds it.
pub fn dial(to: &Acquaintance, answering: &Answering) -> Result<Link, NetError> {
    let address = literal(&to.address)?;
    let mut stream = TcpStream::connect(address).map_err(socket)?;
    stream.set_nodelay(true).map_err(socket)?;
    stream.set_write_timeout(Some(patience())).map_err(socket)?;
    wait_with_patience(&stream)?;

    let (kem_public, kem_secret) = ephemeral_kem()?;
    let line = kem::PublicKey::from_bytes(to.kem_key);
    let (ct_s, ss_s) = kem::encapsulate(&line).map_err(|_| wire(mt_wire::WireError::Undrawn))?;
    let hello_key = handshake::hello_key(
        ss_s.as_bytes(),
        SUITE,
        &to.kem_key,
        kem_public.as_bytes(),
        ct_s.as_bytes(),
    );
    let hello = Hello {
        suite_id: SUITE,
        kem_key: *kem_public.as_bytes(),
        static_ct: *ct_s.as_bytes(),
        sealed_key: handshake::seal_key(hello_key, answering.public.as_bytes())
            .map_err(NetError::Handshake)?,
    };
    write_flight(&mut stream, &hello.encode())?;

    let answer = HelloAnswer::parse(&read_flight(&mut stream, handshake::hello_answer_len())?)
        .map_err(NetError::Handshake)?;
    let ss_r = kem::decapsulate(&kem_secret, &kem::Ciphertext::from_bytes(answer.kem_ct));
    let their_kem = kem::PublicKey::from_bytes(answer.kem_key);
    let (ct_i, ss_i) =
        kem::encapsulate(&their_kem).map_err(|_| wire(mt_wire::WireError::Undrawn))?;

    let keys = Keys::of(
        &hello,
        &answer,
        answering.public.as_bytes(),
        &to.answering_key,
        &to.kem_key,
        ct_i.as_bytes(),
        [ss_s.as_bytes(), ss_r.as_bytes(), ss_i.as_bytes()],
    )
    .map_err(NetError::Handshake)?;
    let signature = handshake::sign_initiator(&answering.secret, keys.transcript())
        .map_err(NetError::Handshake)?;
    let finish = HelloFinish {
        kem_ct: *ct_i.as_bytes(),
        sealed_signature: keys
            .seal_initiator(&signature)
            .map_err(NetError::Handshake)?,
    };
    write_flight(&mut stream, &finish.encode())?;

    let confirm = HelloConfirm::parse(&read_flight(&mut stream, handshake::hello_confirm_len())?)
        .map_err(NetError::Handshake)?;
    // A fourth flight that does not open or does not verify under the key the line names is another
    // machine, or none, at that address.
    let channel = keys
        .initiator_channel(&to.answering_key, &confirm)
        .map_err(|e| match e {
            HandshakeError::Unopened | HandshakeError::Unverified => NetError::NotTheMachineNamed,
            other => NetError::Handshake(other),
        })?;
    Link::standing(stream, channel, true)
}

// A machine reachable from outside answers links it did not choose. What it answers with is the
// second and fourth flights, and it carries a channel only once the third has verified. **A first
// flight that does not open under its static key is answered by no byte**: the connection is held
// silent until the far side ends it or falls silent for one patience, exactly as a flight left
// unfinished is, so a side that was not handed the line cannot tell by its own length whether it
// reached a machine.
pub struct Door(TcpListener);

impl Door {
    pub fn open(address: &str) -> Result<Self, NetError> {
        Ok(Self(TcpListener::bind(literal(address)?).map_err(socket)?))
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

        // The units are read first and apart from what they hold: a socket that ends inside them
        // has ended, and nothing is held for it.
        let units = read_flight_units(&mut stream, handshake::hello_len())?;
        let opened = (|| -> Result<_, NetError> {
            let hello = Hello::parse(&assemble_flight(&units, handshake::hello_len())?)
                .map_err(NetError::Handshake)?;
            let ss_s = kem::decapsulate(
                &answering.kem_secret,
                &kem::Ciphertext::from_bytes(hello.static_ct),
            );
            let hello_key = handshake::hello_key(
                ss_s.as_bytes(),
                hello.suite_id,
                answering.kem_public.as_bytes(),
                &hello.kem_key,
                &hello.static_ct,
            );
            let their_key =
                handshake::open_key(hello_key, &hello.sealed_key).map_err(NetError::Handshake)?;
            Ok((hello, ss_s, their_key))
        })();
        // The gate: a first flight that does not assemble, does not parse or does not open ends
        // here, and the stream is held silent the way an unfinished flight is, then dropped without
        // one byte written to it.
        let (hello, ss_s, their_key) = match opened {
            Ok(opened) => opened,
            Err(refused) => {
                hold_silent(&mut stream);
                return Err(refused);
            }
        };

        let (kem_public, kem_secret) = ephemeral_kem()?;
        let their_kem = kem::PublicKey::from_bytes(hello.kem_key);
        let (ct_r, ss_r) =
            kem::encapsulate(&their_kem).map_err(|_| wire(mt_wire::WireError::Undrawn))?;
        let answer = HelloAnswer {
            suite_id: hello.suite_id,
            kem_key: *kem_public.as_bytes(),
            kem_ct: *ct_r.as_bytes(),
        };
        write_flight(&mut stream, &answer.encode())?;

        let finish = HelloFinish::parse(&read_flight(&mut stream, handshake::hello_finish_len())?)
            .map_err(NetError::Handshake)?;
        let ss_i = kem::decapsulate(&kem_secret, &kem::Ciphertext::from_bytes(finish.kem_ct));
        let keys = Keys::of(
            &hello,
            &answer,
            &their_key,
            answering.public.as_bytes(),
            answering.kem_public.as_bytes(),
            &finish.kem_ct,
            [ss_s.as_bytes(), ss_r.as_bytes(), ss_i.as_bytes()],
        )
        .map_err(NetError::Handshake)?;
        // The fourth flight is sealed before the third is read and crosses only after it verified,
        // since reading the third consumes the keys both seals come of.
        let signature = handshake::sign_responder(&answering.secret, keys.transcript())
            .map_err(NetError::Handshake)?;
        let confirm = HelloConfirm {
            sealed_signature: keys
                .seal_responder(&signature)
                .map_err(NetError::Handshake)?,
        };
        let channel = keys
            .responder_channel(&their_key, &finish)
            .map_err(NetError::Handshake)?;
        write_flight(&mut stream, &confirm.encode())?;
        Link::standing(stream, channel, false)
    }
}

// The renewal of the keys of a link, held where the keys are: these tests read the secret, the keys
// and the renewal in flight of both ends of one real link over a socket, which nothing outside this
// crate can see and which the property is about.
#[cfg(test)]
mod tests {
    use super::*;

    fn met() -> (Link, Link) {
        let far = Answering::of_machine(&[0xA7; 32]);
        let far_key = *far.public().as_bytes();
        let far_kem = *far.kem_public().as_bytes();
        let door = Door::open("127.0.0.1:0").expect("a door opens");
        let address = door.address().expect("a door knows where it stands");
        let waiting = std::thread::spawn(move || door.answer(&far));
        let opened = dial(
            &Acquaintance {
                address,
                answering_key: far_key,
                kem_key: far_kem,
            },
            &Answering::of_machine(&[0xB8; 32]),
        )
        .expect("the handshake stands");
        let answered = waiting
            .join()
            .expect("the thread stands")
            .expect("answered");
        (opened, answered)
    }

    fn query(n: u64) -> Vec<u8> {
        message::encode_state_query(n, message::RootIndex::Machines, &[0x33; 32])
    }

    // One message of a caller from one side to the other in a window, arriving as itself whatever of
    // a renewal travelled beside it.
    fn carries(from: &mut Link, to: &mut Link, window: u64, n: u64) {
        from.send_in(window, Kind::StateQuery, &query(n))
            .expect("it crosses");
        let (kind, arrived) = to.receive_in(window).expect("it arrives");
        assert_eq!(kind, Kind::StateQuery);
        assert_eq!(&arrived[..message::state_query_len()], &query(n)[..]);
    }

    fn at_rest(link: &Link) -> bool {
        matches!(link.renewal, Renewal::Idle)
    }

    fn has_offered(link: &Link) -> bool {
        matches!(link.renewal, Renewal::Offered(_))
    }

    fn awaits_finish(link: &Link) -> bool {
        matches!(link.renewal, Renewal::Answered(_))
    }

    // Both ends hold one secret and each opens with the key the other seals with.
    fn agree(a: &Link, b: &Link) {
        assert_eq!(*a.secret, *b.secret);
        assert_eq!(*a.sending, *b.receiving);
        assert_eq!(*a.receiving, *b.sending);
    }

    #[test]
    fn a_link_that_never_renewed_carries_the_keys_of_its_handshake() {
        let (mut opened, mut answered) = met();
        agree(&opened, &answered);
        assert_eq!(
            *opened.sending,
            handshake::initiator_to_responder(&opened.secret)
        );
        assert_eq!(
            *opened.receiving,
            handshake::responder_to_initiator(&opened.secret)
        );
        assert_ne!(*opened.sending, *opened.receiving);
        // The first window a link is told stands for the window of its handshake, so nothing renews
        // in it, and a caller that never tells a window never renews.
        let first = *opened.secret;
        carries(&mut opened, &mut answered, 5, 1);
        opened
            .send(Kind::StateQuery, &query(2))
            .expect("it crosses");
        answered.receive().expect("it arrives");
        assert_eq!(*opened.secret, first);
        assert!(at_rest(&opened) && at_rest(&answered));
    }

    #[test]
    fn a_renewal_in_a_later_window_walks_the_secret_and_both_sides_switch() {
        let (mut opened, mut answered) = met();
        let first = *opened.secret;
        let first_sending = *opened.sending;
        carries(&mut opened, &mut answered, 5, 1);
        // In a later window the opener offers before its message, and the message still travels
        // under the keys of the handshake.
        carries(&mut opened, &mut answered, 6, 2);
        assert!(has_offered(&opened) && awaits_finish(&answered));
        assert_eq!(*opened.secret, first);
        // The answering side seals under the keys it holds until it opens the finish: its message
        // reaches an opener that has switched, through the receiving key it keeps.
        carries(&mut answered, &mut opened, 6, 3);
        assert_ne!(*opened.secret, first);
        assert!(opened.previous_receiving.is_some());
        carries(&mut opened, &mut answered, 6, 4);
        agree(&opened, &answered);
        assert_ne!(*opened.sending, first_sending);
        assert!(answered.previous_receiving.is_none());
        carries(&mut answered, &mut opened, 6, 5);
        assert!(opened.previous_receiving.is_none());
        assert_eq!((opened.set_in, answered.set_in), (Some(6), Some(6)));
        // Once in a window: more messages in the same window renew nothing.
        carries(&mut opened, &mut answered, 6, 6);
        assert!(at_rest(&opened) && at_rest(&answered));
        // And the side that answered the link offers in its turn, and both sides reach one value.
        let second = *opened.secret;
        carries(&mut answered, &mut opened, 7, 7);
        assert!(has_offered(&answered) && awaits_finish(&opened));
        carries(&mut opened, &mut answered, 7, 8);
        carries(&mut answered, &mut opened, 7, 9);
        agree(&opened, &answered);
        assert_ne!(*opened.secret, second);
        assert_ne!(*opened.secret, first);
    }

    #[test]
    fn two_offers_that_cross_leave_the_offer_of_the_side_that_opened_the_link() {
        let (mut opened, mut answered) = met();
        carries(&mut opened, &mut answered, 5, 1);
        carries(&mut answered, &mut opened, 5, 2);
        // Both sides are about to send in window six, and both offer before reading the other.
        opened
            .send_in(6, Kind::StateQuery, &query(3))
            .expect("it crosses");
        answered
            .send_in(6, Kind::StateQuery, &query(4))
            .expect("it crosses");
        assert!(has_offered(&opened) && has_offered(&answered));
        // The opener discards the other offer in silence and reads the message behind it.
        let (_, arrived) = opened.receive_in(6).expect("it arrives");
        assert_eq!(&arrived[..message::state_query_len()], &query(4)[..]);
        assert!(has_offered(&opened));
        // The other side erases the key it drew and answers the opener.
        let (_, arrived) = answered.receive_in(6).expect("it arrives");
        assert_eq!(&arrived[..message::state_query_len()], &query(3)[..]);
        assert!(awaits_finish(&answered));
        carries(&mut answered, &mut opened, 6, 5);
        carries(&mut opened, &mut answered, 6, 6);
        agree(&opened, &answered);
        assert!(at_rest(&opened) && at_rest(&answered));
        assert_eq!((opened.set_in, answered.set_in), (Some(6), Some(6)));
    }

    // The named wrong implementation: a side that kept opening under the key before the renewal
    // after a unit had opened under the new one. A unit sealed under the old sending key ends the
    // link once the far side has erased it.
    #[test]
    fn a_unit_under_the_key_before_a_renewal_ends_the_link_once_the_new_one_opened() {
        let (mut opened, mut answered) = met();
        carries(&mut opened, &mut answered, 5, 1);
        let old = opened.sending.clone();
        carries(&mut opened, &mut answered, 6, 2);
        carries(&mut answered, &mut opened, 6, 3);
        carries(&mut opened, &mut answered, 6, 4);
        assert!(answered.previous_receiving.is_none());
        let pieces = link::pieces(Kind::StateQuery.byte(), &query(9)).expect("cut");
        let label = mt_wire::draw::label().expect("drawn");
        let unit = link::seal_unit(&old, &label, &pieces[0]).expect("sealed");
        write_whole(&mut opened.stream, &unit).expect("written");
        assert!(answered.receive().is_err());
    }

    // The ceiling: a side that is never told a window still renews once it has sealed `rekey_units`
    // units under one sending key, and its count begins again under the new key.
    #[test]
    fn a_side_at_the_ceiling_renews_without_a_window_and_counts_again() {
        let (mut opened, mut answered) = met();
        assert_eq!(
            opened.ceiling,
            mt_wire::rekey_units().expect("the Decree names it")
        );
        opened.ceiling = 3;
        let first = *opened.secret;
        // A query is one unit, so three of them reach the ceiling and nothing renews before it.
        for n in 0..3 {
            opened
                .send(Kind::StateQuery, &query(n))
                .expect("it crosses");
            answered.receive().expect("it arrives");
        }
        assert!(at_rest(&opened) && opened.sealed == 3);
        // The next message goes behind an offer, under the keys the link holds.
        opened
            .send(Kind::StateQuery, &query(3))
            .expect("it crosses");
        assert!(has_offered(&opened));
        answered.receive().expect("it arrives");
        assert!(awaits_finish(&answered));
        answered
            .send(Kind::StateQuery, &query(4))
            .expect("it crosses");
        opened.receive().expect("it arrives");
        assert_ne!(*opened.secret, first);
        assert_eq!(opened.sealed, 0);
        opened
            .send(Kind::StateQuery, &query(5))
            .expect("it crosses");
        answered.receive().expect("it arrives");
        agree(&opened, &answered);
        assert_eq!(opened.sealed, 1);
        assert!(at_rest(&opened) && at_rest(&answered));
    }

    // The named wrong implementation: a side whose offer goes unanswered and that keeps sealing
    // under one key past its ceiling. A far side that never reads leaves the offer standing, and the
    // link refuses the message that would take the key past twice its ceiling.
    #[test]
    fn a_key_whose_offer_goes_unanswered_seals_no_more_than_twice_its_ceiling() {
        let (mut opened, _silent) = met();
        opened.ceiling = 3;
        let mut sent = 0u64;
        let refused = loop {
            match opened.send(Kind::StateQuery, &query(sent)) {
                Ok(()) => sent += 1,
                Err(error) => break error,
            }
            assert!(sent < 100, "the key seals without bound");
        };
        assert_eq!(refused, NetError::KeyExhausted);
        assert!(has_offered(&opened));
        assert!(opened.sealed <= 2 * opened.ceiling);
        assert!(opened.sealed > opened.ceiling);
        // Nothing is sealed once refused: the next message is refused as well and the count stands.
        let count = opened.sealed;
        assert_eq!(
            opened.send(Kind::StateQuery, &query(sent)).err(),
            Some(NetError::KeyExhausted)
        );
        assert_eq!(opened.sealed, count);
    }

    #[test]
    fn a_message_of_a_renewal_out_of_turn_ends_the_link_and_no_caller_sends_one() {
        let (mut opened, mut answered) = met();
        for kind in [Kind::RenewOffer, Kind::RenewAnswer, Kind::RenewFinish] {
            assert_eq!(
                opened.send(kind, &[0u8; 8]).err(),
                Some(NetError::RenewalOutOfTurn)
            );
            assert_eq!(
                opened.send_in(9, kind, &[0u8; 8]).err(),
                Some(NetError::RenewalOutOfTurn)
            );
        }
        // A finish no answer of this side awaits is refused rather than taken for a key.
        opened
            .seal(
                Kind::RenewFinish,
                &message::encode_renew_finish(&[0x5A; kem::CIPHERTEXT_BYTES]),
            )
            .expect("sealed");
        assert_eq!(answered.receive().err(), Some(NetError::RenewalOutOfTurn));
    }
}
