// A machine of Montana, run from a terminal. What it holds is one secret drawn on it and never
// transmitted, the door it answers at, the acquaintances an operator handed it, and the links that
// stand — and every one of those it asks another crate for rather than doing itself.
//
// **The secret is drawn once, on this machine, and everything derives from it in one direction.**
// It is drawn the way a person's entropy is drawn — six sources with the health tests of the set
// over them — because the set says every device that speaks on the network holds a secret of that
// kind, drawn the same way, that never leaves the device. The store refuses a second drawing, so a
// machine that already stood cannot become a second machine wearing its name.
//
// **An acquaintance is of the world outside, and this protocol holds none of it.** What one
// operator hands another is an address and the key that machine answers with. The address is a
// route and the protocol names no route; what makes it an acquaintance is the key.

#![forbid(unsafe_code)]
#![deny(clippy::all)]

pub mod attest;
pub mod pay;
pub mod pulse;
pub mod round;
pub mod say;
pub mod state;

use mt_codec::size;
use mt_net::{Acquaintance, Answering, Door, Link, NetError};
use mt_store::{Store, StoreError, SECRET_BYTES};
use mt_wire::message::{self, Kind, POINT_BYTES};
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Condvar, Mutex};
use zeroize::Zeroizing;

#[derive(Debug, PartialEq, Eq)]
pub enum NodeError {
    Store(StoreError),
    Net(NetError),
    // The machine could not draw a secret: a source of entropy the set requires was not alive, or
    // the block it produced failed a test of health. A machine born on a broken source looks
    // ordinary and is guessable, and nothing later reveals that — so it is refused, never warned
    // about.
    Unborn { said: String },
    // An acquaintance written in a shape this tree does not read.
    Unreadable { what: String },
    // A row of the Decree this machine reads and the Decree does not carry.
    Decree { row: String },
    // The count of the links this machine holds became unreadable, which is a machine that can no
    // longer hold itself to the ceiling the set fixes. It stops rather than answering past it.
    Uncountable,
    // What this machine could not prove or could not build of its own standing. It names what was
    // being made and never a value of it: a machine that cannot prove its presence answers nothing
    // rather than answering with something a verifier would refuse.
    Unprovable { what: &'static str },
    // What arrived and was refused. The reason reaches this operator and never the sender: every
    // refusal of a far side is silence, and what carries a reason is the local end alone.
    Refused { what: &'static str },
    // An object of another shape than its layout gives.
    Object(mt_state::ObjectError),
}

// A row of the Decree the wire reads and the Decree does not carry. The wire answers with its own
// refusal and this machine names the row, since what a reader of an error wants is the row.
// The points of the window a store holds, computed from the window and the index and from nothing
// else. A store holding no window stands at no point: the rule of the set accepts a deposit at the
// point of the current window alone, and a machine without one has no current window to name.
// Which round a machine is in: the window, the chain and the round, named rather than carried as a
// bare triple through four signatures.
pub type Round = (u64, u8, u32);

// What a machine holds of the round it is in, shared with the threads that carry its links.
type OpenRound = Arc<Mutex<Option<Round>>>;

fn points_of(store: &Store, open: Option<Round>) -> Vec<[u8; POINT_BYTES]> {
    let mut out = match store.head() {
        Ok(Some(window)) => round::points_of_window(window).unwrap_or_default(),
        _ => Vec::new(),
    };
    // And the points of the round this machine is in, where a beacon and the attestations answering
    // it stand. A machine outside a round stands at none of them: the rule of the set accepts a
    // deposit at the point of the current window and of the current round, and a machine holding
    // neither has nothing to hold a deposit against.
    if let Some((window, chain, round)) = open {
        out.extend(round::points_of_round(window, chain, round).unwrap_or_default());
    }
    out
}

fn of_the_decree(row: &str) -> NodeError {
    NodeError::Decree {
        row: row.to_string(),
    }
}

// The links a device answers, beside the entries it chose. It is a row of the Decree and never a
// number of this tree, so a boundary that moves it moves this machine with it.
fn inbound_slots() -> Result<u64, NodeError> {
    mt_genesis::scalar("inbound_slots").ok_or(NodeError::Decree {
        row: "inbound_slots".to_string(),
    })
}

// The acquaintance an operator writes down and hands over: the address, an at-sign, and the key
// that machine answers with in hexadecimal. One line, two values, and no third — there is no
// directory and none can be assembled, so this is the whole of what a first connection is made of.
pub fn write_acquaintance(address: &str, answering_key: &[u8; size::SIGNING_PUBLIC_KEY]) -> String {
    let key: String = answering_key.iter().map(|b| format!("{b:02x}")).collect();
    format!("{address}@{key}")
}

pub fn read_acquaintance(line: &str) -> Result<Acquaintance, NodeError> {
    let (address, key) = line.rsplit_once('@').ok_or_else(|| NodeError::Unreadable {
        what: "an acquaintance is an address, an at-sign and a key".to_string(),
    })?;
    if key.len() != size::SIGNING_PUBLIC_KEY * 2 {
        return Err(NodeError::Unreadable {
            what: format!(
                "a key of {} hexadecimal characters, and this one has {}",
                size::SIGNING_PUBLIC_KEY * 2,
                key.len()
            ),
        });
    }
    let mut answering_key = [0u8; size::SIGNING_PUBLIC_KEY];
    for (at, slot) in answering_key.iter_mut().enumerate() {
        *slot = u8::from_str_radix(&key[at * 2..at * 2 + 2], 16).map_err(|_| {
            NodeError::Unreadable {
                what: "a key of hexadecimal characters".to_string(),
            }
        })?;
    }
    if address.is_empty() {
        return Err(NodeError::Unreadable {
            what: "an acquaintance carries an address".to_string(),
        });
    }
    Ok(Acquaintance {
        address: address.to_string(),
        answering_key,
    })
}

// What an operator hands this machine when starting it. Nothing here is a value of the protocol:
// a route, a directory on a disk and a list of acquaintances are all of the world outside, and the
// Decree holds none of them.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct Configuration {
    pub data: PathBuf,
    pub listen: String,
    pub acquaintances: Vec<String>,
    // The naming halves of the machines admitted to the window, this one among them. An opening
    // cohort witnesses itself, so its halves pass between operators exactly as an acquaintance
    // does; a machine handed none of them answers its door and lives no window.
    pub admitted: Vec<[u8; 32]>,
    // The window to open at, and how many to live. Neither is a value of the protocol: the first
    // is where an operator starts a machine and the second is when it stops, and a machine given
    // no count lives until it is stopped.
    pub from: u64,
    pub windows: Option<u64>,
    // The right of a window, and how many machines that window's cement named, to be redeemed into
    // a note of the wallet below. Both are what the operator read off that window when it closed:
    // the machine cannot ask anybody for them, and nothing it holds implies them.
    pub redeem: Option<(u64, usize)>,
    pub wallet: Option<String>,
    // Whom a living machine pays out of that wallet, and what of it. Both values of a payee are
    // public and name nobody; the file is where what the payee needs is written, closed to its
    // owner, because one of those three values is a secret.
    pub pay_to: Option<([u8; 32], [u8; 32])>,
    pub amount: Option<u128>,
    pub hand_to: Option<String>,
}

impl Configuration {
    pub fn at(data: impl AsRef<Path>, listen: &str) -> Self {
        Self {
            data: data.as_ref().to_path_buf(),
            listen: listen.to_string(),
            acquaintances: Vec::new(),
            admitted: Vec::new(),
            from: 0,
            windows: None,
            redeem: None,
            wallet: None,
            pay_to: None,
            amount: None,
            hand_to: None,
        }
    }
}

// The links a machine did not open, counted against the ceiling the Decree fixes. Three rules of
// the set stand on this count and none of them is this tree's:
//
// **A device holds at most `inbound_slots` links it did not open**, and a further handshake at the
// ceiling is refused in silence. Silence is the refusal itself: an answer saying "full" would tell
// a stranger the state of this machine, and a machine at its ceiling must read exactly like an
// address where nothing listens. So a machine at its ceiling does not answer the door at all — the
// connection waits in the queue of the system and is answered when a slot frees, or it does not.
//
// **A link a machine opened itself stands outside the ceiling**, so the entries it chose are never
// displaced by strangers.
//
// **The count is the machine's own** and is published nowhere: it names no peer, no address and no
// person, and it leaves the machine that holds it.
struct Held {
    standing: Mutex<usize>,
    freed: Condvar,
    ceiling: usize,
}

impl Held {
    fn to_the_ceiling(ceiling: usize) -> Self {
        Self {
            standing: Mutex::new(0),
            freed: Condvar::new(),
            ceiling,
        }
    }

    // Room for one more link, waited for rather than refused loudly: while the ceiling stands full
    // the door is not answered at all, which is the silence the set asks for. A reply saying "full"
    // would publish the state of this machine to whoever asked.
    fn wait_for_room(&self) -> Result<(), NodeError> {
        let mut standing = self.standing.lock().map_err(|_| NodeError::Uncountable)?;
        while *standing >= self.ceiling {
            standing = self
                .freed
                .wait(standing)
                .map_err(|_| NodeError::Uncountable)?;
        }
        Ok(())
    }

    // The slot a link that now stands takes. It is counted **after** the door answered, so a door
    // waiting for a caller that never comes holds nothing: what the count names is links that
    // stand and never a machine's own patience.
    fn took(&self) -> Result<usize, NodeError> {
        let mut standing = self.standing.lock().map_err(|_| NodeError::Uncountable)?;
        *standing += 1;
        Ok(*standing)
    }

    fn release(&self) {
        if let Ok(mut standing) = self.standing.lock() {
            *standing = standing.saturating_sub(1);
            self.freed.notify_one();
        }
    }

    fn standing(&self) -> usize {
        self.standing.lock().map(|held| *held).unwrap_or(0)
    }
}

// What stands at the points of the window this machine holds. A point is a function of the window
// and an index alone — nobody chooses one, and every machine computes the same sixteen bytes — so
// what a machine does here is hold what was left at a point it stands at and answer nothing about
// who left it: it keeps no record of who deposited and none of who asked.
//
// **A deposit is accepted at the point of the current window alone**, which is the rule of the set
// and is why a machine holding no window holds nothing: it has no window whose points it could
// compute, so every deposit is refused in silence rather than kept against a window that may never
// come. **What stands at one point never exceeds the round it may hold** — one beacon and one
// attestation of every machine admitted to the window, since the nullifier of a machine's part
// bounds it to one entry. It is not the bound of one answer: that is the cells of the largest
// single object, and a point held to it would refuse the first attestation answering a beacon.
// A point is read in as many answers as it takes, and the asker names how many cells it holds.
// **A point lives its window and the one after it, and then goes.** The set accepts a deposit at the
// point of the current window and refuses one at a past point in silence; a holder that kept the
// past points anyway would hold every point of every window it ever answered, and a sender that
// deposited into the current window, waited for it to turn and repeated would spend that holder's
// memory without breaking a single rule. So each point is held beside the window it belongs to, and
// a window turning drops what belonged to the windows before the last one. The last one stays
// because the set keeps the heavy attestations of a window at their points until the proof of that
// window stands — the bridge a machine one window behind walks to the head (Canon, "The points a
// round stands at"). A holder that let go of them the moment its own window turned left that
// machine nothing to collect: two machines on two hosts closed windows 0 and 1 and then waited on
// each other for ever, the one ahead in window 2 for an attestation the one behind could not make
// without the attestation of window 1 the other had already dropped (Lauterbourg and Moscow,
// 06.10.2026). This tree builds no proof of a window, so the bridge is held one window long: what a
// machine one window behind needs, and a bound no sender can grow.
// What one point holds: the window it belongs to, the cells deposited at it, and the deliveries
// that have begun to stand there. The third is what lets a point take a delivery whole or refuse
// the whole of it — a delivery already begun is counted for, and one not begun enters only where
// the whole of it fits.
// The window a point lives, the cells standing at it in the order they arrived, the deliveries
// begun, and the digests of the standing cells — the last because a repetition is answered by a
// lookup and never by a walk: the ceiling of a point is the round and the slots the set admits,
// and a door that compared a cell against everything standing would slow by the square of what
// it honestly holds.
struct AtAPoint {
    window: u64,
    cells: Vec<Vec<u8>>,
    begun: Vec<[u8; POINT_BYTES]>,
    digests: std::collections::BTreeSet<[u8; 32]>,
}

// What one point last read back as: the window it belonged to, the count of cells that produced the
// reading, and the objects that came of them.
type ReadBack = (u64, usize, Vec<Vec<u8>>);

struct Standing {
    at: Mutex<BTreeMap<[u8; POINT_BYTES], AtAPoint>>,
}

impl Standing {
    fn empty() -> Self {
        Self {
            at: Mutex::new(BTreeMap::new()),
        }
    }

    // `of_a_delivery` is which delivery this cell belongs to and how many blocks that delivery
    // declares, read off the cell under the keys of the point — which every machine computes, so a
    // holder needs no right of its own to read it. A cell whose delivery cannot be read is not of
    // this point and is refused.
    fn hold(
        &self,
        point: [u8; POINT_BYTES],
        window: u64,
        cell: Vec<u8>,
        ceiling: usize,
        of_a_delivery: Option<([u8; POINT_BYTES], u16)>,
    ) -> say::Took {
        let Ok(mut at) = self.at.lock() else {
            return say::Took::PastTheCeiling;
        };
        // What belonged to the windows before the last one goes here rather than at some later
        // sweep: a holder with no moment of release is a holder that never releases.
        at.retain(|_, held| window <= held.window.saturating_add(1));
        let standing = at.entry(point).or_insert(AtAPoint {
            window,
            cells: Vec::new(),
            begun: Vec::new(),
            digests: std::collections::BTreeSet::new(),
        });
        // **A cell already standing is not held twice.** A machine reads a point over and over
        // while it stands at a round, and what it reads it writes at its own point so that it is
        // read once from the wire; without this a point fills with copies of the round it holds
        // and then refuses the round it was meant to hold. A repetition adds nothing and is
        // lawful, exactly as a repeated attestation is to a cement.
        // A local key of the store and never a value of the protocol: raw, because the domains
        // of the registry are protocol surfaces and a dedup key of one machine's memory is not
        // one. It hashes the whole cell, since a shorter key would let a crafted cell shadow a
        // lawful one as its repetition.
        let digest: [u8; 32] = {
            use sha2::{Digest as _, Sha256};
            Sha256::digest(&cell).into()
        };
        if standing.digests.contains(&digest) {
            return say::Took::Repeated;
        }
        // **A point takes a delivery whole or not at all.** Where a delivery has not begun to
        // stand here, what remains of the bound must hold the whole of it; where it has, its
        // remaining cells are already counted for and go in. A holder that took the head of a
        // delivery and refused its tail would hold a body with a hole in it, and a body with a hole
        // reads back as nothing.
        let Some((delivery, declared)) = of_a_delivery else {
            return say::Took::AnotherPoint;
        };
        let begun = standing.begun.contains(&delivery);
        if !begun && standing.cells.len() + usize::from(declared) > ceiling {
            return say::Took::PastTheCeiling;
        }
        if !begun {
            standing.begun.push(delivery);
        }
        standing.digests.insert(digest);
        standing.cells.push(cell);
        say::Took::Held
    }

    // How many cells stand at a point. It is what tells a reader that nothing has arrived since it
    // last looked, without opening a single cell of what stands.
    fn count_at(&self, point: &[u8; POINT_BYTES]) -> usize {
        self.at
            .lock()
            .map(|at| at.get(point).map(|held| held.cells.len()).unwrap_or(0))
            .unwrap_or(0)
    }

    fn at(&self, point: &[u8; POINT_BYTES]) -> Vec<Vec<u8>> {
        self.at
            .lock()
            .map(|at| {
                at.get(point)
                    .map(|held| held.cells.clone())
                    .unwrap_or_default()
            })
            .unwrap_or_default()
    }

    fn points_standing(&self) -> usize {
        self.at.lock().map(|at| at.len()).unwrap_or(0)
    }
}

// A link this machine opened, and what it has already taken over it. **The count a collection names
// is an index into the holder's own list**, so it belongs to the link it was read over rather than
// to the point: two acquaintances hold different cells at one point, and one count for both would
// skip what the second holds.
struct Reached {
    link: Link,
    taken: BTreeMap<[u8; POINT_BYTES], (u64, u16)>,
}

// A machine that has been born: its store, the key it answers with, the door it stands at, the
// count of the links it did not open, and what stands at its points.
pub struct Machine {
    // The round this machine is in, or none while it is in no round. It is what says which points
    // it stands at beside those of its window, and it moves as the pulse moves.
    open: OpenRound,
    store: Arc<Store>,
    answering: Answering,
    door: Door,
    held: Arc<Held>,
    standing: Arc<Standing>,
    // The state of the value plane this machine holds. A frame reaches it through the points of a
    // window, and a spender reaches its own leaf through the query the set gives for exactly that.
    value: Arc<Mutex<state::State>>,
    // The links this machine opened, kept for the asking. **A link a machine opened is its way of
    // asking, and a link it answered is its way of being asked.** A deposit and a collection are
    // both requests whose answer comes back on the link they went out on, so a link the pulse uses
    // cannot also be read by a thread of its own — the thread would take the answer. Keeping the
    // two kinds apart is what lets a pulse ask without racing anybody for what comes back.
    reached: Arc<Mutex<Vec<Reached>>>,
    // How many machines this machine knows the window admits. It is what the ceiling of a point is
    // read from — a point holds one beacon and one attestation of every admitted machine — and a
    // machine that knows of none holds a point to a beacon and one attestation, which is the least
    // a round can be.
    admitted: Arc<Mutex<u64>>,
    // What the cells of a point last read back as, and how many cells stood when they did. It is
    // not a second place for what stands — the cells are the one place, and this is the answer the
    // last reading of them gave, held against the count that produced it so that it cannot outlive
    // what it was read from.
    read_back: Arc<Mutex<BTreeMap<[u8; POINT_BYTES], ReadBack>>>,
    // The account this machine keeps of its own doings. Every count of it names nobody, and it is
    // what an operator reads instead of guessing.
    counts: Arc<say::Counts>,
}

impl Machine {
    // The first start draws the secret; every later one takes the secret that stands. Which of the
    // two happened is answered rather than guessed, because an operator watching a machine start
    // for the second time and being told it was born would be watching a machine that lost its
    // standing without being told.
    pub fn start(configuration: &Configuration) -> Result<(Self, bool), NodeError> {
        let store = Store::open(&configuration.data).map_err(NodeError::Store)?;
        let born = match store.secret().map_err(NodeError::Store)? {
            Some(_) => false,
            None => {
                let birth = mt_seed::birth(None).map_err(|e| NodeError::Unborn {
                    said: format!("{e:?}"),
                })?;
                // The secret of a machine never stands outside a wrapper that wipes, from the draw
                // that makes it to the file that keeps it: a copy on the stack is a copy nothing
                // wipes, and a stack frame is reused by whatever the next call puts in it.
                let mut secret = Zeroizing::new([0u8; SECRET_BYTES]);
                secret.copy_from_slice(&birth.entropy[..]);
                store.bear_secret(&secret).map_err(NodeError::Store)?;
                true
            }
        };
        // PANIC-OK: the secret was either read above or written above, so a store answering with
        // nothing here is a store that lost it between two lines of this function.
        let secret = store
            .secret()
            .map_err(NodeError::Store)?
            .expect("the secret this machine just drew or just read");
        let answering = Answering::of_machine(&secret);
        let door = Door::open(&configuration.listen).map_err(NodeError::Net)?;
        let ceiling = usize::try_from(inbound_slots()?).map_err(|_| NodeError::Decree {
            row: "inbound_slots".to_string(),
        })?;
        // **What the machine held of the value plane stands again.** A note takes its position in
        // the tree of notes, and a path is proven against that tree — so a plane that lived in
        // memory alone made every note die with the run that created it, and a person paid held a
        // note their own machine could no longer prove a path for. What is read here is what this
        // machine wrote, and a file that does not read back whole is refused rather than half-read.
        let kept = store.value().map_err(NodeError::Store)?;
        let held_value = if kept.is_empty() {
            state::State::new()
        } else {
            state::State::decode(&kept)?
        };
        Ok((
            Self {
                open: Arc::new(Mutex::new(None)),
                store: Arc::new(store),
                answering,
                door,
                held: Arc::new(Held::to_the_ceiling(ceiling)),
                standing: Arc::new(Standing::empty()),
                value: Arc::new(Mutex::new(held_value)),
                reached: Arc::new(Mutex::new(Vec::new())),
                admitted: Arc::new(Mutex::new(0)),
                read_back: Arc::new(Mutex::new(BTreeMap::new())),
                counts: Arc::new(say::Counts::default()),
            },
            born,
        ))
    }

    // What this machine holds of the value plane, for as long as the caller holds the guard. A
    // machine that handed out a copy would be handing out a state that stops being the one it
    // applies frames to the moment the next frame arrives.
    pub fn value(&self) -> Result<std::sync::MutexGuard<'_, state::State>, NodeError> {
        self.value.lock().map_err(|_| NodeError::Uncountable)
    }

    // **A frame applied is a frame kept.** The plane changes only where a frame enters it, so the
    // writing stands here and in no other place: a caller that applied and forgot to keep would
    // leave a note standing in memory and nowhere else, which is the defect this closes.
    pub fn apply_and_keep(
        &self,
        frame: &mt_state::layout::Frame,
        window: u64,
    ) -> Result<Vec<u64>, NodeError> {
        let mut state = self.value()?;
        let positions = state.apply(frame, window)?;
        self.store
            .put_value(&state.encode())
            .map_err(NodeError::Store)?;
        Ok(positions)
    }

    // The tree of admitted machines this plane stands against, told and kept.
    pub fn admits_the_tree(&self, admitted: mt_proof::poseidon::Digest) -> Result<(), NodeError> {
        let mut state = self.value()?;
        state.admits(admitted);
        self.store
            .put_value(&state.encode())
            .map_err(NodeError::Store)
    }

    // The frames standing at the points of the round this machine is in, verified and applied in
    // the order the points are named. A frame stands at the points of the round its canonical slot
    // names, exactly as a beacon and the attestations answering it do — so a machine reads the
    // round it is in and no other. What does not read back as a whole frame is passed over in
    // silence: a machine answers a malformed deposit with nothing, exactly as it answers
    // everything else.
    pub fn apply_what_stands(&self) -> Result<usize, NodeError> {
        let Some((window, chain, at)) = self.round_of_the_machine() else {
            return Ok(0);
        };
        let mut state = self.value()?;
        let points = round::points_of_round(window, chain, at).map_err(|_| NodeError::Decree {
            row: "consensus_replicas".to_string(),
        })?;
        let width = state::State::width_of_a_frame();
        let mut applied = 0;
        for point in &points {
            let cells = self.standing_at(point);
            if cells.is_empty() {
                continue;
            }
            let Ok(Some(bytes)) = mt_wire::publish::object_of(point, window, &cells, width) else {
                continue;
            };
            let Ok(frame) = <mt_state::layout::Frame as mt_state::Layout>::parse(&bytes) else {
                continue;
            };
            // A frame already applied stands at every point of the window, so a second point
            // carrying it is the ordinary case and not an error: what refuses it is the state,
            // which holds its nullifiers, and the refusal is passed over here.
            if state.apply(&frame, window).is_ok() {
                applied += 1;
            }
        }
        // What the round put into the plane is kept once, at the end of the round rather than at
        // every frame of it: the writing is of the whole plane, so writing it per frame would write
        // the same bytes as many times as the round carried frames — and the moment of the writing
        // would then say how many frames a round carried.
        if applied > 0 {
            self.store
                .put_value(&state.encode())
                .map_err(NodeError::Store)?;
        }
        Ok(applied)
    }

    // The line an operator hands to another operator. It names where this machine stands and the
    // key it answers with, and nothing else exists to name.
    pub fn acquaintance(&self) -> Result<String, NodeError> {
        let address = self.door.address().map_err(NodeError::Net)?;
        Ok(write_acquaintance(
            &address,
            self.answering.public().as_bytes(),
        ))
    }

    pub fn answering_key(&self) -> &[u8; size::SIGNING_PUBLIC_KEY] {
        self.answering.public().as_bytes()
    }

    // What a person compares out of band, and it is not the key. The key is nineteen hundred and
    // fifty-two bytes — a wall of hexadecimal nobody reads aloud or checks by eye — and the set
    // says plainly what people compare instead: the fingerprint of the identity key, six groups of
    // five digits, one number for speech, screen and a scanned code alike. **Two values with two
    // purposes**: the key is what a machine verifies on every handshake, the fingerprint is what
    // two operators check once.
    pub fn fingerprint(&self) -> String {
        mt_derive::fingerprint::shown(self.answering.public().as_bytes())
    }

    pub fn address(&self) -> Result<String, NodeError> {
        self.door.address().map_err(NodeError::Net)
    }

    pub fn head(&self) -> Result<Option<u64>, NodeError> {
        self.store.head().map_err(NodeError::Store)
    }

    // Reaching an acquaintance. A machine answering with another key is not the machine the
    // operator meant, and the error says which of the two failed — this end is the operator's and
    // carries reasons; the far end is told nothing at all.
    pub fn reach(&self, line: &str) -> Result<Link, NodeError> {
        let acquaintance = read_acquaintance(line)?;
        mt_net::dial(&acquaintance, &self.answering).map_err(NodeError::Net)
    }

    // Answering one link this machine did not open.
    pub fn answer(&self) -> Result<Link, NodeError> {
        self.door.answer(&self.answering).map_err(NodeError::Net)
    }

    // How many links this machine holds that it did not open, and the ceiling it holds them to.
    // What an operator reads; what nothing publishes.
    pub fn holding(&self) -> (usize, usize) {
        (self.held.standing(), self.held.ceiling)
    }

    // The points this machine stands at: those of the window it holds, and none while it holds no
    // window. Nobody chooses them and nobody is told them — every machine computes the same sixteen
    // bytes from the window and the index.
    pub fn points(&self) -> Result<Vec<[u8; POINT_BYTES]>, NodeError> {
        Ok(points_of(&self.store, self.round_of_the_machine()))
    }

    // Which round this machine is in. A machine that entered none stands at the points of its
    // window alone.
    pub fn round_of_the_machine(&self) -> Option<Round> {
        self.open.lock().ok().and_then(|held| *held)
    }

    // Entering a round, and leaving it: what a machine stands at moves with the pulse rather than
    // being fixed when it started.
    pub fn enter_round(&self, window: u64, chain: u8, round: u32) -> Result<(), NodeError> {
        let mut held = self.open.lock().map_err(|_| NodeError::Uncountable)?;
        *held = Some((window, chain, round));
        Ok(())
    }

    // A deposit, taken or refused in silence. What is refused is a cell of another width, a point
    // of another window — the rule of the set, and the reason a machine holding no window holds
    // nothing — and a point already carrying what an answer may hold.
    // **The yes-or-no of the door answers lawful, not new.** A repetition adds nothing and is
    // lawful — the set says so of a repeated cell exactly as it says it of a repeated part-nullifier
    // in a cement — so a door that answered no to it would report a refusal where none happened.
    // What is refused is a cell of another width, a point this machine does not hold, and a
    // delivery the bound cannot take whole. Which of the two lawful answers it was is what the
    // saying door below tells the operator.
    pub fn take_deposit(&self, point: &[u8; POINT_BYTES], cell: &[u8]) -> Result<bool, NodeError> {
        Ok(matches!(
            self.take_deposit_saying(point, cell)?,
            say::Took::Held | say::Took::Repeated
        ))
    }

    // The same door, answering **why** rather than yes-or-no. The wire tells whoever deposited
    // nothing at all; this is what the machine writes for its own operator.
    pub fn take_deposit_saying(
        &self,
        point: &[u8; POINT_BYTES],
        cell: &[u8],
    ) -> Result<say::Took, NodeError> {
        if cell.len() != mt_wire::cell_bytes().map_err(|_| of_the_decree("cell_bytes"))? {
            self.counts.raise(&self.counts.deposits_of_another_width);
            return Ok(say::Took::AnotherWidth);
        }
        if !self.points()?.contains(point) {
            if self.round_of_the_machine().is_none() {
                self.counts.raise(&self.counts.deposits_before_a_round);
            } else {
                self.counts.raise(&self.counts.deposits_at_another_point);
            }
            return Ok(say::Took::AnotherPoint);
        }
        let ceiling = self.point_ceiling()?;
        // The window a point belongs to is the one this machine holds, or the one of the round it
        // stands in where it holds no window yet: a point of the round and a point of the window
        // both live that window and go with it.
        let window = match self.head()? {
            Some(window) => window,
            None => self.round_of_the_machine().map(|(w, _, _)| w).unwrap_or(0),
        };
        let of_a_delivery = mt_wire::publish::delivery_of(point, window, cell);
        let took = self
            .standing
            .hold(*point, window, cell.to_vec(), ceiling, of_a_delivery);
        match took {
            say::Took::Held => self.counts.raise(&self.counts.deposits_taken),
            say::Took::Repeated => self.counts.raise(&self.counts.deposits_repeated),
            say::Took::PastTheCeiling => self.counts.raise(&self.counts.deposits_past_the_ceiling),
            _ => {}
        }
        Ok(took)
    }

    // The account this machine keeps of itself, as one line.
    pub fn account(&self) -> String {
        self.counts.line()
    }

    pub fn counts(&self) -> Arc<say::Counts> {
        Arc::clone(&self.counts)
    }

    // What stands at one point, which is what a collection from it would carry.
    pub fn standing_at(&self, point: &[u8; POINT_BYTES]) -> Vec<Vec<u8>> {
        self.standing.at(point)
    }

    // How many points of this machine carry anything. What an operator reads; what nothing
    // publishes, since a point names nobody and a count of them names nobody either.
    pub fn points_standing(&self) -> usize {
        self.standing.points_standing()
    }

    // Answering one link and handing it to a thread of its own. The door goes back to answering the
    // moment the link is handed over, so a far side that says nothing holds one thread and never
    // this machine; and while the ceiling stands full the door is not answered at all, which is the
    // silence the set asks for rather than a reply that would publish the state of this machine.
    pub fn answer_one(&self) -> Result<usize, NodeError> {
        self.held.wait_for_room()?;
        let link = self.door.answer(&self.answering).map_err(NodeError::Net)?;
        let standing = self.held.took()?;
        let held = Arc::clone(&self.held);
        let open = Arc::clone(&self.open);
        let standing_at_the_points = Arc::clone(&self.standing);
        let value = Arc::clone(&self.value);
        let store = Arc::clone(&self.store);
        let width = mt_wire::cell_bytes().map_err(|_| of_the_decree("cell_bytes"))?;
        let admitted = Arc::clone(&self.admitted);
        let counts = Arc::clone(&self.counts);
        std::thread::spawn(move || {
            let mut link = link;
            let _carried = carry_until_it_ends(
                &mut link,
                &store,
                &open,
                &standing_at_the_points,
                &value,
                &admitted,
                &counts,
                width,
            );
            held.release();
        });
        Ok(standing)
    }

    // A link this machine opened, handed to a thread of its own. It stands **outside** the ceiling
    // for the reason the count of held links states: the entries a machine chose are never
    // displaced by strangers, so an acquaintance an operator handed over takes no slot a stranger
    // could have taken.
    //
    // A caller that dropped the link instead would close the socket where it stood: a machine that
    // reached another and then let the value fall out of scope has shaken hands and hung up, and
    // the two carry nothing for each other. What a link is for is what crosses it afterwards, so
    // reaching and carrying are one call rather than two a caller must remember to make in order.
    pub fn carry(&self, link: Link) -> Result<(), NodeError> {
        let open = Arc::clone(&self.open);
        let standing_at_the_points = Arc::clone(&self.standing);
        let value = Arc::clone(&self.value);
        let store = Arc::clone(&self.store);
        let width = mt_wire::cell_bytes().map_err(|_| of_the_decree("cell_bytes"))?;
        let admitted = Arc::clone(&self.admitted);
        let counts = Arc::clone(&self.counts);
        std::thread::spawn(move || {
            let mut link = link;
            let _carried = carry_until_it_ends(
                &mut link,
                &store,
                &open,
                &standing_at_the_points,
                &value,
                &admitted,
                &counts,
                width,
            );
        });
        Ok(())
    }

    // Reaching an acquaintance and keeping the link for the asking: the one call a machine makes of
    // a line another operator handed it. What comes back is the transcript both sides computed,
    // which is what a caller prints; the link itself is kept and never handed out, so there is no
    // value a caller can drop and no socket that closes because nobody held it.
    pub fn reach_and_hold(&self, line: &str) -> Result<[u8; 32], NodeError> {
        let link = self.reach(line)?;
        let transcript = *link.transcript();
        self.reached
            .lock()
            .map_err(|_| NodeError::Uncountable)?
            .push(Reached {
                link,
                taken: BTreeMap::new(),
            });
        Ok(transcript)
    }

    // The half this machine is named by in the tree of admitted machines. An operator hands it to
    // another operator exactly as it hands an acquaintance, and the two reach the same tree from
    // the halves alone. It is derived from the secret and never chosen, so a machine cannot stand
    // anywhere but where its secret puts it, and it names no owner, no address and no person.
    pub fn naming_half(&self) -> Result<[u8; 32], NodeError> {
        let secret = self.machine_secret()?;
        let mut held = [0u8; 32];
        held.copy_from_slice(&secret[..32]);
        Ok(pulse::Cohort::half_of(&held))
    }

    // How many machines the window admits, as this machine knows it. A pulse tells it when it opens
    // a window against a cohort; what it changes is how much one point may hold.
    pub fn admits(&self, count: u64) -> Result<(), NodeError> {
        *self.admitted.lock().map_err(|_| NodeError::Uncountable)? = count;
        Ok(())
    }

    // How many cells stand at one of this machine's points.
    pub fn cells_standing_at(&self, point: &[u8; POINT_BYTES]) -> usize {
        self.standing.count_at(point)
    }

    // What one point of this machine may hold: the round it may carry.
    fn point_ceiling(&self) -> Result<usize, NodeError> {
        let admitted = *self.admitted.lock().map_err(|_| NodeError::Uncountable)?;
        message::point_ceiling(admitted).map_err(|_| of_the_decree("cell_bytes"))
    }

    // How many acquaintances this machine holds a link to. What an operator reads; what nothing
    // publishes, since it names no peer.
    pub fn reached(&self) -> usize {
        self.reached.lock().map(|held| held.len()).unwrap_or(0)
    }

    // An object of consensus put at a point: written at this machine's own point first, then
    // deposited at the same point of every machine it can ask.
    //
    // **A point is one blackboard and a deposit is how a copy of it reaches another machine.** So a
    // machine that only answered links still sees everything, because whoever dialled it writes
    // into it; and a machine that dialled sees what the other holds, because it collects from the
    // same point. Two hosts of which one dialled the other therefore converge without either being
    // told anything beyond the acquaintance.
    // Whether what remains of a point's bound holds a delivery of this many cells. **A point takes a
    // delivery whole or not at all**: a holder that took the first cells and refused the rest would
    // hold a body with a hole in it, which reads back as nothing — so a point at its bound would
    // stop answering with anything whole exactly when the round it carries matters most.
    pub fn point_holds_room_for(&self, point: &[u8; POINT_BYTES], cells: usize) -> bool {
        match self.point_ceiling() {
            Ok(ceiling) => self.cells_standing_at(point) + cells <= ceiling,
            Err(_) => false,
        }
    }

    pub fn publish_at_the_point(
        &self,
        point: &[u8; POINT_BYTES],
        window: u64,
        object: &[u8],
    ) -> Result<usize, NodeError> {
        let cells =
            mt_wire::publish::cells_of(point, window, object).map_err(|_| NodeError::Refused {
                what: "an object the wire cannot cut into cells",
            })?;
        self.counts.raise(&self.counts.publications);
        self.counts
            .raise_by(&self.counts.cells_published, cells.len() as u64);
        for cell in &cells {
            self.take_deposit(point, cell)?;
        }
        let mut held = self.reached.lock().map_err(|_| NodeError::Uncountable)?;
        let mut carried = 0usize;
        for one in held.iter_mut() {
            // A machine that stopped answering is one line of an operator's morning and not a
            // reason to stop publishing to the others.
            if cells
                .iter()
                .all(|cell| pulse::deposit_at(&mut one.link, point, cell).is_ok())
            {
                carried += 1;
                self.counts.raise(&self.counts.pushes_carried);
            } else {
                self.counts.raise(&self.counts.pushes_lost);
            }
        }
        Ok(carried)
    }

    // Every object standing at a point: what this machine holds there, and what the machines it can
    // ask hold there. Whatever comes back is written at its own point, so what was collected once
    // is not collected again and a runner reads its own holder from then on.
    pub fn objects_at_the_point(
        &self,
        point: &[u8; POINT_BYTES],
        window: u64,
    ) -> Result<Vec<Vec<u8>>, NodeError> {
        {
            let mut held = self.reached.lock().map_err(|_| NodeError::Uncountable)?;
            for one in held.iter_mut() {
                // **What was read once is not read again.** A collection names the count of cells
                // the asker already holds *of that holder*, so the count belongs to the link it was
                // read over and not to this machine's own point: a machine asking from zero every
                // time would pull the whole round over the wire and open every cell of it again,
                // twenty-five milliseconds later, for as long as it stood at that round.
                //
                // A point lives its window and goes with it, so a count kept against another window
                // is no count at all and the reading begins again.
                let already = match one.taken.get(point) {
                    Some((stood, read)) if *stood == window => *read,
                    _ => 0,
                };
                self.counts.raise(&self.counts.collections_asked);
                let Ok(cells) = pulse::collect_from(&mut one.link, point, already) else {
                    continue;
                };
                self.counts
                    .raise_by(&self.counts.cells_pulled, cells.len() as u64);
                let read = u16::try_from(cells.len()).unwrap_or(u16::MAX);
                one.taken
                    .insert(*point, (window, already.saturating_add(read)));
                for cell in &cells {
                    self.take_deposit(point, cell)?;
                }
            }
        }
        // **What was read back once is not read back again.** Taking the objects of a point opens
        // every cell standing there, and a machine standing at a round looks at its points many
        // times a second; a reader that read them back on every look would spend its core opening
        // the same round over and over — and it is exactly the core the far side needs to finish
        // the proof this machine is waiting for. The count of cells at the point is the key: it can
        // only grow while a window stands, so a count that has not moved is a point that has not
        // moved, and a window turning drops the point with everything read of it.
        let standing = self.standing.count_at(point);
        {
            let held = self.read_back.lock().map_err(|_| NodeError::Uncountable)?;
            if let Some((stood, count, objects)) = held.get(point) {
                if *stood == window && *count == standing {
                    self.counts.raise(&self.counts.points_read_from_memory);
                    return Ok(objects.clone());
                }
            }
        }
        self.counts.raise(&self.counts.points_read_back);
        let objects = mt_wire::publish::objects_of(point, window, &self.standing_at(point))
            .map_err(|_| NodeError::Refused {
                what: "cells at a point the wire cannot read back",
            })?;
        let mut held = self.read_back.lock().map_err(|_| NodeError::Uncountable)?;
        held.retain(|_, (stood, _, _)| *stood >= window);
        held.insert(*point, (window, standing, objects.clone()));
        Ok(objects)
    }

    // The secret this machine was born with. It never leaves this crate: what needs it is the pulse
    // — the draw of a ticket, the nullifier of a part, the key a window is answered under — and all
    // of that stands beside this file.
    pub(crate) fn machine_secret(&self) -> Result<Zeroizing<[u8; SECRET_BYTES]>, NodeError> {
        self.store
            .secret()
            .map_err(NodeError::Store)?
            .ok_or(NodeError::Refused {
                what: "a machine that holds no secret",
            })
    }

    // Answering links until the machine is stopped.
    pub fn serve(&self) -> Result<(), NodeError> {
        loop {
            // A handshake that failed took no slot and is no reason to stop: the next caller may be
            // whoever this machine is waiting for.
            let _ = self.answer_one();
        }
    }
}

// What a machine does with a link that stands: it reads what crosses, dispatches it and counts it.
// **What a message is rides in the framing of every piece and inside the seal**, so a machine
// answers rather than guesses: a deposit at a point of the current window or round is kept, a
// collection from that point is answered with what stands there, a query for a leaf of the tree of
// notes is answered with the path to it, a head query naming this network is answered with the
// newest proposal held and one naming another network with silence. A piece of a kind outside the
// vocabulary ends the link, and a kind this machine does not serve is read, counted and dropped —
// a reply saying "not for me" is information about this machine that a stranger asked for and did
// not earn.
#[allow(clippy::too_many_arguments)]
fn carry_until_it_ends(
    link: &mut Link,
    store: &Store,
    open: &OpenRound,
    standing: &Standing,
    value: &Mutex<state::State>,
    admitted: &Mutex<u64>,
    counts: &say::Counts,
    cell_width: usize,
) -> usize {
    let mut carried = 0usize;
    while let Ok((kind, message)) = link.receive() {
        carried += 1;
        // What arrived is read as what it says it is. The kind rides in the framing of every piece,
        // under the seal, so a machine dispatches rather than guesses — and a kind outside the
        // vocabulary never reaches here, because the link ended where it was read.
        let answered = match kind {
            Kind::Deposit => {
                counts.raise(&counts.deposits_arrived);
                take_the_deposit(
                    store, open, standing, admitted, counts, cell_width, &message,
                )
            }
            Kind::CollectPublic => answer_the_collection(link, standing, &message),
            // A collection from a pipe presents a right of the current window. A machine of this
            // stage holds nothing at a pipe, and an answer of zero cells is the ordinary answer and
            // is indistinguishable from any other, so asking says nothing about whether anything
            // waits.
            Kind::Collect => answer_with_nothing(link),
            Kind::HeadQuery => answer_the_head(link, store, &message),
            Kind::StateQuery => answer_the_state(link, value, &message),
            // An answer nobody asked for, and the messages a machine of this stage does not serve:
            // read, counted and dropped, because a reply saying "not for me" is information about
            // this machine that a stranger asked for and did not earn.
            _ => Ok(()),
        };
        // A far side that cannot be answered — a socket that closed under the answer — ends the
        // link here rather than being answered again.
        if answered.is_err() {
            break;
        }
    }
    carried
}

// A deposit is accepted at the points of the current window and of the round this machine is in,
// and at no others. They are read at this moment and never held from the moment the link was
// answered: a window moves while a link stands, and so does a round.
// **The ceiling of a point is read when a deposit arrives.** A door answers a link before the pulse
// tells the machine how many machines the window admits, so a ceiling taken once at the answering of
// a link is the ceiling of a machine that knows of nobody — one beacon and one attestation — and
// every deposit past that is refused for the life of that link. What a machine puts at its own
// points goes nowhere near this door and passes, so the refusal falls on its neighbours alone: the
// machine fills its own cement and never theirs, and no window closes.
fn take_the_deposit(
    store: &Store,
    open: &OpenRound,
    standing: &Standing,
    admitted: &Mutex<u64>,
    counts: &say::Counts,
    cell_width: usize,
    message: &[u8],
) -> Result<(), NetError> {
    let Ok(ceiling) = message::point_ceiling(admitted.lock().map(|held| *held).unwrap_or(0)) else {
        return Ok(());
    };
    let Ok(width) = message::deposit_len() else {
        return Ok(());
    };
    if message.len() < width {
        return Ok(());
    }
    if let Ok((point, cell)) = message::parse_deposit(&message[..width]) {
        let held = open.lock().ok().and_then(|held| *held);
        if cell.len() != cell_width {
            counts.raise(&counts.deposits_of_another_width);
            return Ok(());
        }
        if !points_of(store, held).contains(&point) {
            if held.is_none() {
                counts.raise(&counts.deposits_before_a_round);
            } else {
                counts.raise(&counts.deposits_at_another_point);
            }
            return Ok(());
        }
        {
            let window = match store.head() {
                Ok(Some(window)) => window,
                _ => held.map(|(w, _, _)| w).unwrap_or(0),
            };
            let of_a_delivery = mt_wire::publish::delivery_of(&point, window, &cell);
            match standing.hold(point, window, cell, ceiling, of_a_delivery) {
                say::Took::Held => counts.raise(&counts.deposits_taken),
                say::Took::Repeated => counts.raise(&counts.deposits_repeated),
                say::Took::PastTheCeiling => counts.raise(&counts.deposits_past_the_ceiling),
                _ => {}
            }
        }
    }
    Ok(())
}

// A collection from the point of a channel presents no right, because the right there is public.
// What it presents is the point and the count of cells of it the asker already holds; the answer
// carries the cells standing there from that index, at most the bound of one answer, and an answer
// of zero cells is the ordinary one.
//
// **The reading of a point takes more than one answer.** A beacon and every attestation answering it
// stand at the round points of one round, and the bound of one answer is the cells of the largest
// single object — so an asker without the index reads the first object of a point and never the
// rest, and its runner gathers nothing.
fn answer_the_collection(
    link: &mut Link,
    standing: &Standing,
    message: &[u8],
) -> Result<(), NetError> {
    let width = message::collect_public_len();
    if message.len() < width {
        return Ok(());
    }
    let Ok((point, after)) = message::parse_collect_public(&message[..width]) else {
        return Ok(());
    };
    let Ok(bound) = message::collect_answer_max() else {
        return Ok(());
    };
    let held = standing.at(&point);
    let from = usize::from(after).min(held.len());
    let take = (held.len() - from).min(bound);
    let Ok(answer) = message::encode_collect_answer(&held[from..from + take]) else {
        return Ok(());
    };
    link.send(Kind::CollectAnswer, &answer)
}

fn answer_with_nothing(link: &mut Link) -> Result<(), NetError> {
    let Ok(answer) = message::encode_collect_answer(&[]) else {
        return Ok(());
    };
    link.send(Kind::CollectAnswer, &answer)
}

// A head query names the network by the hash the asker computed itself, so an answerer of another
// network is told apart before a byte of its proposal is parsed. A machine holding no window
// answers nothing at all: there is no shorter proposal and no longer one, so silence is what it has
// to say.
// The leaf a spender asks for, answered with the path to it and nothing beside it. The query names
// the window, the root and the key; what comes back is a proof of that leaf, and a proof of length
// zero is the ordinary answer for a leaf that does not exist — so asking says nothing about whether
// anything stands there.
//
// **What is answered is a position and never a person.** A path through the tree of notes names the
// leaf and the siblings of it; it does not say whose note stands there, because nothing in the tree
// does.
fn answer_the_state(
    link: &mut Link,
    value: &Mutex<state::State>,
    message: &[u8],
) -> Result<(), NetError> {
    let width = message::state_query_len();
    if message.len() < width {
        return Ok(());
    }
    let Ok((_window, root, key)) = message::parse_state_query(&message[..width]) else {
        return Ok(());
    };
    // Of the five roots this machine answers for one: the tree of notes, which is what a spender
    // walks. A query for another is answered with the length of nothing, exactly as a query for a
    // leaf that does not exist is.
    let mut position = [0u8; 8];
    position.copy_from_slice(&key[..8]);
    let path = match (root, value.lock()) {
        (message::RootIndex::Notes, Ok(held)) => held.path_of(u64::from_le_bytes(position)),
        _ => None,
    };
    let answer = match path {
        Some(siblings) => {
            let mut out = Vec::with_capacity(siblings.len() * 32);
            for sibling in &siblings {
                out.extend_from_slice(&sibling.bytes());
            }
            out
        }
        None => Vec::new(),
    };
    link.send(Kind::StateAnswer, &message::encode_state_answer(&answer))
}

fn answer_the_head(link: &mut Link, store: &Store, message: &[u8]) -> Result<(), NetError> {
    let width = message::head_query_len();
    if message.len() < width {
        return Ok(());
    }
    let Ok(asked) = message::parse_head_query(&message[..width]) else {
        return Ok(());
    };
    let Some(ours) = mt_state::tables::genesis_state_hash() else {
        return Ok(());
    };
    if asked != ours {
        return Ok(());
    }
    let Ok(Some(window)) = store.head() else {
        return Ok(());
    };
    let Ok(Some(proposal)) = store.proposal(window) else {
        return Ok(());
    };
    // The proven height beside the head. This tree builds no window proofs yet — the proof of a
    // window is the work stage fourteen owes, and AUDIT holds it with what it blocks — so what an
    // answerer honestly names as proven is the height before Genesis: nought, which no window
    // stands at. A joining device reading it learns the truth: nothing here is proven yet.
    let Ok(answer) = message::encode_head_answer(0, &proposal) else {
        return Ok(());
    };
    link.send(Kind::HeadAnswer, &answer)
}

// The one condition that releases a link, and no other: it carried nothing across a whole window.
// Idleness of a person is never observed and never releases anything, a ranking of links is a
// second mechanism the set refuses, and what is read here is the one fact the device holding the
// link already knows.
pub fn released_at_the_window(carried_in_the_window: usize) -> bool {
    carried_in_the_window == 0
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    struct Scratch(PathBuf);

    impl Scratch {
        fn named(what: &str) -> Self {
            let at = std::env::temp_dir().join(format!("montana-node-{what}"));
            let _ = fs::remove_dir_all(&at);
            fs::create_dir_all(&at).expect("a scratch directory is writable");
            Self(at)
        }
    }

    impl Drop for Scratch {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    #[test]
    fn an_acquaintance_is_written_and_read_back_and_a_malformed_one_is_refused() {
        let key = [0x5Au8; size::SIGNING_PUBLIC_KEY];
        let line = write_acquaintance("198.51.100.7:8443", &key);
        let read = read_acquaintance(&line).expect("it reads back");
        assert_eq!(read.address, "198.51.100.7:8443");
        assert_eq!(read.answering_key, key);
        // An address holding an at-sign of its own is read from the last one, so a route with a
        // user in it does not take the key's place.
        let with_at = write_acquaintance("operator@198.51.100.7:8443", &key);
        assert_eq!(
            read_acquaintance(&with_at).expect("it reads back").address,
            "operator@198.51.100.7:8443"
        );
        assert!(read_acquaintance("198.51.100.7:8443").is_err());
        assert!(read_acquaintance("@").is_err());
        assert!(
            read_acquaintance(&format!("a@{}", "zz".repeat(size::SIGNING_PUBLIC_KEY))).is_err()
        );
    }

    #[test]
    fn a_machine_is_born_once_and_answers_with_one_key_ever_after() {
        let scratch = Scratch::named("born-once");
        let configuration = Configuration::at(&scratch.0, "127.0.0.1:0");
        let (first, born) = Machine::start(&configuration).expect("a machine starts");
        assert!(born, "the first start draws the secret");
        let key = *first.answering_key();
        let stood = first.acquaintance().expect("an acquaintance is written");
        drop(first);

        let (again, born_again) = Machine::start(&configuration).expect("a machine starts again");
        assert!(!born_again, "a second start draws nothing");
        assert_eq!(
            *again.answering_key(),
            key,
            "the key a machine answers with moved between two starts"
        );
        // The address moves — the system gives whichever port is free — and the key does not, which
        // is why the key is what an acquaintance is.
        assert_eq!(
            read_acquaintance(&stood).expect("reads").answering_key,
            read_acquaintance(&again.acquaintance().expect("written"))
                .expect("reads")
                .answering_key
        );
    }

    #[test]
    fn two_machines_reach_each_other_by_what_their_operators_handed_over() {
        let near_at = Scratch::named("near");
        let far_at = Scratch::named("far");
        let (far, _) = Machine::start(&Configuration::at(&far_at.0, "127.0.0.1:0"))
            .expect("the far machine starts");
        let line = far.acquaintance().expect("an acquaintance is written");
        let waiting = std::thread::spawn(move || far.answer());

        let (near, _) = Machine::start(&Configuration::at(&near_at.0, "127.0.0.1:0"))
            .expect("the near machine starts");
        let reached = near.reach(&line).expect("the far machine answers");
        let answered = waiting
            .join()
            .expect("the thread stands")
            .expect("answered");
        assert_eq!(reached.transcript(), answered.transcript());
    }

    #[test]
    fn what_a_person_compares_is_the_fingerprint_and_not_the_key() {
        let scratch = Scratch::named("fingerprint");
        let (machine, _) = Machine::start(&Configuration::at(&scratch.0, "127.0.0.1:0"))
            .expect("a machine starts");
        let shown = machine.fingerprint();
        // Six groups of five digits, separated by single spaces: what one operator reads to
        // another over a telephone.
        let groups: Vec<&str> = shown.split(' ').collect();
        assert_eq!(groups.len(), 6, "{shown}");
        assert!(
            groups
                .iter()
                .all(|g| g.len() == 5 && g.chars().all(|c| c.is_ascii_digit())),
            "{shown}"
        );
        // It is of this machine's key and of no other: a second machine shows other digits.
        let other_at = Scratch::named("fingerprint-other");
        let (other, _) = Machine::start(&Configuration::at(&other_at.0, "127.0.0.1:0"))
            .expect("a machine starts");
        assert_ne!(shown, other.fingerprint());
        // And it is the fingerprint of the key the acquaintance carries, so a person comparing the
        // digits has compared the key a machine will verify.
        let carried = read_acquaintance(&machine.acquaintance().expect("written")).expect("reads");
        assert_eq!(shown, mt_derive::fingerprint::shown(&carried.answering_key));
    }

    #[test]
    fn a_machine_holds_the_ceiling_the_decree_names_and_frees_what_it_took() {
        let ceiling = usize::try_from(inbound_slots().expect("the Decree names it")).expect("fits");
        let held = Held::to_the_ceiling(ceiling);
        assert_eq!(held.standing(), 0);
        for expected in 1..=ceiling {
            held.wait_for_room().expect("room while below the ceiling");
            assert_eq!(held.took().expect("a slot"), expected);
        }
        assert_eq!(held.standing(), ceiling);
        // At the ceiling the wait does not end until a slot frees, and nothing is answered while it
        // stands: what is asserted here is the waiting, not a reply to anybody.
        let waited = std::thread::scope(|scope| {
            let waiting = scope.spawn(|| {
                held.wait_for_room()
                    .expect("the wait ends when a slot frees");
                held.took()
            });
            held.release();
            waiting.join().expect("the thread stands")
        });
        assert_eq!(waited.expect("a slot"), ceiling);
        held.release();
        assert_eq!(held.standing(), ceiling - 1);
    }

    #[test]
    fn a_link_that_carried_nothing_across_a_window_is_the_one_that_is_released() {
        assert!(released_at_the_window(0));
        assert!(!released_at_the_window(1));
        assert!(!released_at_the_window(1_000));
    }

    #[test]
    fn a_machine_answers_links_on_threads_of_their_own_and_counts_them() {
        let far_at = Scratch::named("serving");
        let (far, _) = Machine::start(&Configuration::at(&far_at.0, "127.0.0.1:0"))
            .expect("the far machine starts");
        let line = far.acquaintance().expect("an acquaintance is written");
        assert_eq!(far.holding().0, 0);

        let near_at = Scratch::named("reaching");
        let (near, _) = Machine::start(&Configuration::at(&near_at.0, "127.0.0.1:0"))
            .expect("the near machine starts");

        // Two links, answered one after another, each handed to a thread of its own: the door is
        // free again before the first of them has said anything.
        let waiting = std::thread::spawn(move || {
            let first = far.answer_one().expect("a link is answered");
            let second = far.answer_one().expect("a second link is answered");
            (first, second, far)
        });
        let one = near.reach(&line).expect("the far machine answers");
        let two = near.reach(&line).expect("the far machine answers again");
        let (first, second, far) = waiting.join().expect("the thread stands");
        assert_eq!((first, second), (1, 2), "the machine miscounted its links");
        assert_ne!(
            one.transcript(),
            two.transcript(),
            "two links, one transcript"
        );
        // And a link that ends frees the slot it took.
        drop(one);
        drop(two);
        let mut freed = false;
        for _ in 0..200 {
            if far.holding().0 == 0 {
                freed = true;
                break;
            }
            std::thread::sleep(std::time::Duration::from_millis(10));
        }
        assert!(freed, "a link that ended did not free its slot");
    }

    // The named wrong implementation this refuses: a caller that reaches an acquaintance, reads the
    // transcript off the link and lets the value fall out of scope. The handshake completes and the
    // socket closes with it, so the far side's thread ends and the two machines carry nothing for
    // each other — which is a network of two hosts that is not one. The far side's count of held
    // links is what tells the two apart, since it falls when the link it answered ends.
    #[test]
    fn a_link_a_machine_opened_stands_rather_than_closing_where_it_was_read() {
        let far_at = Scratch::named("carried-far");
        let near_at = Scratch::named("carried-near");
        let (far, _) = Machine::start(&Configuration::at(&far_at.0, "127.0.0.1:0"))
            .expect("the far machine starts");
        let line = far.acquaintance().expect("an acquaintance is written");
        let waiting = std::thread::spawn(move || {
            far.answer_one().expect("a link is answered");
            far
        });

        let (near, _) = Machine::start(&Configuration::at(&near_at.0, "127.0.0.1:0"))
            .expect("the near machine starts");
        let transcript = near.reach_and_hold(&line).expect("the far machine answers");
        let far = waiting.join().expect("the thread stands");
        assert_eq!(far.holding().0, 1, "the far side did not count the link");

        // The link stands: what says so is that the far side still holds it after the near side has
        // returned from the call that opened it. A dropped link would have ended that thread, and
        // the count would fall to zero — which is what this waits to see it not do.
        for _ in 0..50 {
            assert_eq!(
                far.holding().0,
                1,
                "the link the near machine opened closed where it was read"
            );
            std::thread::sleep(std::time::Duration::from_millis(10));
        }
        assert_ne!(
            transcript, [0u8; 32],
            "a transcript of nothing is no transcript"
        );
    }

    #[test]
    fn a_machine_holding_no_window_says_so_rather_than_naming_one() {
        let scratch = Scratch::named("no-head");
        let (machine, _) = Machine::start(&Configuration::at(&scratch.0, "127.0.0.1:0"))
            .expect("a machine starts");
        assert_eq!(machine.head().expect("a machine answers"), None);
    }
}
