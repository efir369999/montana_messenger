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

pub mod agreement;
pub mod attempt;
pub mod attest;
pub mod certificate;
pub mod collections;
#[cfg(kani)]
mod kani_decree;
pub mod pay;
pub mod private;
pub mod pulse;
pub mod round;
pub mod runner;
pub mod say;
pub mod state;
#[cfg(unix)]
pub mod status;

use mt_codec::size;
use mt_net::{Acquaintance, Answering, Door, Link, NetError};
use mt_store::{Store, StoreError, SECRET_BYTES};
use mt_wire::message::{self, Kind, POINT_BYTES};
use crate::collections::BTreeMap;
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
    Unborn {
        said: String,
    },
    // An acquaintance written in a shape this tree does not read.
    Unreadable {
        what: String,
    },
    // A row of the Decree this machine reads and the Decree does not carry.
    Decree {
        row: String,
    },
    // The count of the links this machine holds became unreadable, which is a machine that can no
    // longer hold itself to the ceiling the set fixes. It stops rather than answering past it.
    Uncountable,
    // What this machine could not prove or could not build of its own standing. It names what was
    // being made and never a value of it: a machine that cannot prove its presence answers nothing
    // rather than answering with something a verifier would refuse.
    Unprovable {
        what: &'static str,
    },
    // What arrived and was refused. The reason reaches this operator and never the sender: every
    // refusal of a far side is silence, and what carries a reason is the local end alone.
    Refused {
        what: &'static str,
    },
    // The round's context is known, but its cement cannot yet be reconstructed
    // from verified heavy attestations. More data may resolve this; no clock can.
    UnreconciledCement,
    // CNS-20: a local waiting budget ended, granting no authority to close.
    Stalled {
        on: say::Verdict,
        what: &'static str,
    },
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

// What a machine does once a frame of its own has applied in the order of its round: it is told the
// positions the frame's commitments took, or nothing where the round left without applying it.
// What a payer is told of its frame: the positions it took as its round left, the positions a
// replay of a decided roll moved it to, or that it applies in no window. Consensus, "When the
// decision is not the name a machine took": "A payer learns what its frame took as the round
// carrying it leaves ... and where a replay moves it, the replay tells it again".
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Told {
    Applied(Vec<u64>),
    Moved(Vec<u64>),
    Left,
    // The window of the frame is final: nothing moves it again, and what was kept to move it goes.
    Final,
}

// A settlement is told as the round leaves and again by every replay that moves its frame, so it is
// a closure called more than once.
pub type Settlement = Box<dyn FnMut(Told) + Send>;

type Settling = Arc<Mutex<Vec<(Round, [u8; 32], Settlement)>>>;

type Carriers = Mutex<Vec<(mt_net::Closer, std::thread::JoinHandle<()>)>>;

// The settlements of frames whose rounds left, with the positions they were told, kept until the
// window of the frame is final: what a replay tells again, and what goes when nothing can move it.
type Retelling = Arc<Mutex<Vec<(u64, [u8; 32], Settlement, Option<Vec<u64>>)>>>;

fn points_of(store: &Store, open: Option<Round>) -> Vec<[u8; POINT_BYTES]> {
    let mut out = match store.head() {
        Ok(Some(window)) => round::points_of_window(window).unwrap_or_default(),
        _ => Vec::new(),
    };
    // And the points of the round this machine is in, where a beacon and the attestations answering
    // it stand, beside the points of its window, where the proposal closing that window stands. A
    // machine outside a round stands at none of them: the rule of the set accepts a deposit at the
    // point of the current window and of the current round, and a machine holding neither has
    // nothing to hold a deposit against.
    if let Some((window, chain, round)) = open {
        out.extend(round::points_of_round(window, chain, round).unwrap_or_default());
        out.extend(round::points_of_window(window).unwrap_or_default());
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
    // Whether the operator opens a network on this machine, and how many windows to live. Neither
    // is a value of the protocol. Opening is an act of the operator on an empty store and the one
    // way to window zero; a machine not asked to open lives only from an anchor (Consensus, "The
    // cold start"). A machine given no count lives until it is stopped.
    pub open: bool,
    pub windows: Option<u64>,
    // The window whose right is to be redeemed into a note of the wallet below, which the operator
    // read off that window when it closed. The right is worth the window's credit, so nothing else of the
    // window is asked for.
    pub redeem: Option<u64>,
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
            open: false,
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
// **A point lives its window and the retention after it, and then goes.** The set accepts a deposit at the
// point of the current window and refuses one at a past point in silence; a holder that kept the
// past points anyway would hold every point of every window it ever answered, and a sender that
// deposited into the current window, waited for it to turn and repeated would spend that holder's
// memory without breaking a single rule. So each point is held beside the window it belongs to, and
// a window turning drops what belonged to the windows before the last one. The last one stays
// because the set keeps the heavy attestations of a window at their points for `retained_windows`
// windows after it closes — the certificate a machine behind walks to the head (Consensus, "The
// certificate of a window"). A holder that let go of them the moment its own window turned left
// that machine nothing to collect: two machines on two hosts closed windows 0 and 1 and then waited
// on each other for ever, the one ahead in window 2 for an attestation the one behind could not make
// without the attestation of window 1 the other had already dropped (two hosts of one cohort,
// 06.10.2026). So a point lives for `retained_windows` windows after its own and then goes, and the
// count is read from the Decree when the machine starts.
// What one point holds: the window it belongs to, the cells deposited at it, and the deliveries
// that have begun to stand there. The third is what lets a point take a delivery whole or refuse
// the whole of it — a delivery already begun is counted for, and one not begun enters only where
// the whole of it fits.
// The window a point lives, how many cells stand at it, the deliveries begun, and the digests of the
// standing cells — the last because a repetition is answered by a lookup and never by a walk: the
// ceiling of a point is the round and the slots the set admits, and a door that compared a cell
// against everything standing would slow by the square of what it honestly holds.
// **The cells themselves stand in one place, the file of the point** (issue #63). A point held its
// cells in memory beside the file they were appended to, and what was read back held them again as
// objects; a window that did not close stood at a new round every few seconds, and the cohort of
// three was killed for its memory (Amsterdam at 320 MiB, Moscow at 1 GiB) while every round of the
// window was still owed to its walk. What memory holds of a point is its count and its digests, a
// few dozen bytes a cell against the whole width of one, and a reader is handed the range of the
// file it asks for.
struct AtAPoint {
    window: u64,
    count: usize,
    begun: Vec<[u8; POINT_BYTES]>,
    digests: crate::collections::BTreeSet<[u8; 32]>,
}

// What one point last read back as: the window it belonged to, the count of cells that produced the
// reading, when it was last asked for, the bytes of its objects and the objects.
struct Read {
    window: u64,
    count: usize,
    asked: u64,
    bytes: usize,
    objects: Vec<Vec<u8>>,
}

// What points last read back as. **It holds a ceiling of bytes, and the point asked for longest ago
// goes first** (issue #63): it held every point of the window it was read in, and a window standing
// at round after round held every round of it a second time. What goes is read again from the cells
// the next time it is asked for; a live round is asked for many times a second and stays.
struct ReadBack {
    points: BTreeMap<[u8; POINT_BYTES], Read>,
    bytes: usize,
    asked: u64,
    ceiling: usize,
}

impl ReadBack {
    fn to_the_ceiling(ceiling: usize) -> Self {
        Self {
            points: BTreeMap::new(),
            bytes: 0,
            asked: 0,
            ceiling,
        }
    }

    // The objects a point read back as, where the count that produced them still stands.
    fn of(&mut self, point: &[u8; POINT_BYTES], window: u64, count: usize) -> Option<Vec<Vec<u8>>> {
        self.asked = self.asked.saturating_add(1);
        let asked = self.asked;
        let held = self.points.get_mut(point)?;
        if held.window != window || held.count != count {
            return None;
        }
        held.asked = asked;
        Some(held.objects.clone())
    }

    // A reading kept: the windows before it go, and then the readings asked for longest ago until
    // this one fits. A reading wider than the whole ceiling is not kept at all.
    fn keep(&mut self, point: [u8; POINT_BYTES], window: u64, count: usize, objects: Vec<Vec<u8>>) {
        if let Some(gone) = self.points.remove(&point) {
            self.bytes = self.bytes.saturating_sub(gone.bytes);
        }
        let mut freed = 0usize;
        self.points.retain(|_, held| {
            let stays = held.window >= window;
            if !stays {
                freed = freed.saturating_add(held.bytes);
            }
            stays
        });
        self.bytes = self.bytes.saturating_sub(freed);
        let bytes: usize = objects.iter().map(Vec::len).sum();
        if bytes > self.ceiling {
            return;
        }
        while self.bytes.saturating_add(bytes) > self.ceiling {
            let Some(oldest) = self
                .points
                .iter()
                .min_by_key(|(_, held)| held.asked)
                .map(|(key, _)| *key)
            else {
                break;
            };
            if let Some(gone) = self.points.remove(&oldest) {
                self.bytes = self.bytes.saturating_sub(gone.bytes);
            }
        }
        self.asked = self.asked.saturating_add(1);
        self.bytes = self.bytes.saturating_add(bytes);
        self.points.insert(
            point,
            Read {
                window,
                count,
                asked: self.asked,
                bytes,
                objects,
            },
        );
    }
}

struct Standing {
    at: Mutex<BTreeMap<[u8; POINT_BYTES], AtAPoint>>,
    retained: u64,
    // The window whose points, and those of every window before it, were dropped from the disk
    // last: the disk follows the memory's retention, once per window turning.
    pruned_through: Mutex<u64>,
    // Where the cells of every point stand, and the width each of them is cut at.
    store: Arc<Store>,
    cell_width: usize,
}

impl Standing {
    fn empty(retained: u64, store: Arc<Store>, cell_width: usize) -> Self {
        Self {
            at: Mutex::new(BTreeMap::new()),
            retained,
            pruned_through: Mutex::new(0),
            store,
            cell_width,
        }
    }

    // **What the machine held at its points stands again.** The cells the store kept, by window and
    // point, in the order they were taken: the deliveries begun and the digests are read off the
    // cells themselves, under the keys every machine computes for the point. A cell that does not
    // read as a cell of its point is not of this point and is left out.
    fn loaded(retained: u64, store: &Arc<Store>, cell_width: usize) -> Result<Self, NodeError> {
        let standing = Self::empty(retained, Arc::clone(store), cell_width);
        let kept = store.cells_standing(cell_width).map_err(NodeError::Store)?;
        {
            let mut at = standing.at.lock().map_err(|_| NodeError::Uncountable)?;
            for (window, point, cells) in kept {
                let read = cells.len();
                let held = at.entry(point).or_insert(AtAPoint {
                    window,
                    count: 0,
                    begun: Vec::new(),
                    digests: crate::collections::BTreeSet::new(),
                });
                // A point lives one window, and its file is the one under that window: a file of
                // the same point under another window is not of it.
                if held.window != window {
                    continue;
                }
                let mut taken: Vec<Vec<u8>> = Vec::with_capacity(read);
                for cell in cells {
                    let Some((delivery, _)) = mt_wire::publish::delivery_of(&point, window, &cell)
                    else {
                        continue;
                    };
                    use sha2::{Digest as _, Sha256};
                    let digest: [u8; 32] = Sha256::digest(&cell).into();
                    if !held.digests.insert(digest) {
                        continue;
                    }
                    if !held.begun.contains(&delivery) {
                        held.begun.push(delivery);
                    }
                    held.count += 1;
                    taken.push(cell);
                }
                // The file holds exactly what the point took, in the order it took it: a cell
                // left out here and kept there would shift every index a reader asks for.
                if taken.len() != read {
                    store
                        .put_cells(window, &point, &taken)
                        .map_err(NodeError::Store)?;
                }
            }
        }
        Ok(standing)
    }

    // Whether the disk is due to let go of the windows the memory let go of: once per window.
    fn prune_due(&self, window: u64) -> bool {
        let Ok(mut through) = self.pruned_through.lock() else {
            return false;
        };
        let below = window.saturating_sub(self.retained);
        if below > *through {
            *through = below;
            return true;
        }
        false
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
        // What belonged to the windows before the retention goes here rather than at some later
        // sweep: a holder with no moment of release is a holder that never releases.
        let retained = self.retained;
        at.retain(|_, held| window <= held.window.saturating_add(retained));
        let standing = at.entry(point).or_insert(AtAPoint {
            window,
            count: 0,
            begun: Vec::new(),
            digests: crate::collections::BTreeSet::new(),
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
        if !begun && standing.count + usize::from(declared) > ceiling {
            return say::Took::PastTheCeiling;
        }
        // **The cell goes to the disk under the lock that counts it**, so the count of a point and
        // the cells of its file are one order: a reader handed the cells from an index reads the
        // ones the count names. A cell the disk did not take is not held.
        if self
            .store
            .append_cell(standing.window, &point, &cell)
            .is_err()
        {
            return say::Took::Unkept;
        }
        if !begun {
            standing.begun.push(delivery);
        }
        standing.digests.insert(digest);
        standing.count += 1;
        say::Took::Held
    }

    // How many cells stand at a point. It is what tells a reader that nothing has arrived since it
    // last looked, without opening a single cell of what stands.
    fn count_at(&self, point: &[u8; POINT_BYTES]) -> usize {
        self.at
            .lock()
            .map(|at| at.get(point).map(|held| held.count).unwrap_or(0))
            .unwrap_or(0)
    }

    fn at(&self, point: &[u8; POINT_BYTES]) -> Vec<Vec<u8>> {
        self.cells_of(point, 0, usize::MAX)
    }

    // The cells of a point from `from`, at most `take` of them, read off its file, and never past
    // the count: a cell is appended before it is counted, so what the count names is on the disk.
    fn cells_of(&self, point: &[u8; POINT_BYTES], from: usize, take: usize) -> Vec<Vec<u8>> {
        let Some((window, count)) = self
            .at
            .lock()
            .ok()
            .and_then(|at| at.get(point).map(|held| (held.window, held.count)))
        else {
            return Vec::new();
        };
        let from = from.min(count);
        let take = (count - from).min(take);
        if take == 0 {
            return Vec::new();
        }
        self.store
            .cells_at(window, point, self.cell_width, from, take)
            .unwrap_or_default()
    }

    // Only points already accepted in this open window may receive late
    // answers. Retention from an older window is not a right to deposit there.
    fn holds_point(&self, point: &[u8; POINT_BYTES], window: u64) -> bool {
        self.at
            .lock()
            .is_ok_and(|at| at.get(point).is_some_and(|held| held.window == window))
    }

    fn points_standing(&self) -> usize {
        self.at.lock().map(|at| at.len()).unwrap_or(0)
    }
}

// Local and remote deposits use the same ownership rule. Moving a round
// cannot revoke the point where a still-in-flight heavy answer must arrive.
fn deposit_window(store: &Store, open: Option<Round>) -> u64 {
    open.map(|(window, _, _)| window)
        .or_else(|| store.head().ok().flatten())
        .unwrap_or(0)
}

fn accepts_point(
    store: &Store,
    open: Option<Round>,
    standing: &Standing,
    point: &[u8; POINT_BYTES],
) -> bool {
    points_of(store, open).contains(point)
        || (open.is_some() && standing.holds_point(point, deposit_window(store, open)))
}

// A link this machine opened, and what it has already taken over it. **The count a collection names
// is an index into the holder's own list**, so it belongs to the link it was read over rather than
// to the point: two acquaintances hold different cells at one point, and one count for both would
// skip what the second holds.
struct Reached {
    link: Link,
    taken: BTreeMap<[u8; POINT_BYTES], RemotePoint>,
}

// A successful socket write is not evidence that the holder accepted a cell.
// Only a collection acknowledging the exact bytes suppresses a later retry.
// Keep hashes only for cells this machine also accepts, under its point bound.
// **A push the far side does not acknowledge is tried again later, not at once.** A machine that
// left a window refuses in silence every cell of that window's points, and a neighbour still in it
// that pushed what it holds at every asking would spend both machines' doors on refusals — hundreds
// of thousands of them in one run — for as long as it stood there. So the askings between two
// pushes of the same unacknowledged cells double, and start again from one the moment a collection
// from that far side brings something new, which says it stands at that point still. Conduct of
// this machine alone; it changes nothing of what is published or taken.
struct RemotePoint {
    window: u64,
    read: u16,
    acknowledged: crate::collections::BTreeSet<[u8; 32]>,
    asked: u32,
    pushes_again_at: u32,
    backoff: u32,
}

// **What a close hands the store.** The proposal of the window before that the agreement decided,
// onto which the head moves — none where the window before is the Genesis or a window this machine
// did not live; the proposal of the window closing as this machine took it; the plane the window
// left; the decided state of the window before, which a replay of the decided roll of this window
// starts from; and the census window this machine lived, where this window is one and its part is in
// the cement.
#[derive(Clone)]
pub struct Closing {
    pub head: Option<mt_state::layout::Proposal>,
    pub taken: mt_state::layout::Proposal,
    pub plane: state::State,
    pub before: Option<state::State>,
    pub census: Option<attest::LivedCensus>,
}

// **What a machine keeps of the last window it closed**, in the record of that window, beside the
// head and the number the store reads: the proposal of that window as this machine took it, the
// plane it closed the window on, the decided state of the window before, and its standing.
//
// The proposal stands here and not only among the proposals of the store because the close of the
// next window rewrites the proposal of this one under the decided name before the record of that
// close stands: a machine stopped between the two would otherwise hold its plane beside a proposal
// whose roots are not its own. Each part is written as its length, eight bytes little-endian, and
// its bytes; a decided state of no window is a length of nought, which no plane encodes to.
#[derive(Clone)]
pub struct Kept {
    pub taken: mt_state::layout::Proposal,
    pub plane: state::State,
    pub before: Option<state::State>,
    pub census: Vec<attest::LivedCensus>,
}

impl Kept {
    pub fn encode(&self) -> Result<Zeroizing<Vec<u8>>, NodeError> {
        let taken = mt_state::Layout::bytes(&self.taken).map_err(NodeError::Object)?;
        let plane = self.plane.encode()?;
        let before = match &self.before {
            Some(state) => state.encode()?,
            None => Vec::new(),
        };
        let census = Zeroizing::new(attest::LivedCensus::encode(&self.census));
        let mut out = Zeroizing::new(Vec::new());
        for part in [&taken[..], &plane[..], &before[..], &census[..]] {
            out.extend_from_slice(&(part.len() as u64).to_le_bytes());
            out.extend_from_slice(part);
        }
        Ok(out)
    }

    pub fn decode(bytes: &[u8]) -> Result<Self, NodeError> {
        let short = || NodeError::Refused {
            what: "a record of a window shorter than what it declares",
        };
        let mut rest = bytes;
        let mut parts: Vec<&[u8]> = Vec::new();
        for _ in 0..4 {
            let eight = rest.get(..8).ok_or_else(short)?;
            let mut width = [0u8; 8];
            width.copy_from_slice(eight);
            let width = usize::try_from(u64::from_le_bytes(width)).map_err(|_| short())?;
            let end = width.checked_add(8).ok_or_else(short)?;
            parts.push(rest.get(8..end).ok_or_else(short)?);
            rest = &rest[end..];
        }
        if !rest.is_empty() {
            return Err(NodeError::Refused {
                what: "a record of a window longer than what it declares",
            });
        }
        Ok(Self {
            taken: <mt_state::layout::Proposal as mt_state::Layout>::parse(parts[0])
                .map_err(NodeError::Object)?,
            plane: state::State::decode(parts[1])?,
            before: if parts[2].is_empty() {
                None
            } else {
                Some(state::State::decode(parts[2])?)
            },
            census: attest::LivedCensus::decode(parts[3])?,
        })
    }

    // **The plane a record keeps gives the roots of the proposal it keeps beside it.** Every
    // proposal a close takes is verified against the roots recomputed from the plane it closes on
    // (`pulse::take_the_proposal`, `certificate::verify_proposal`), and the close keeps the two
    // together, so the seven tables of the plane at the window of the proposal give the roots that
    // proposal carries. A plane or a proposal changed on the disk gives others, and is refused
    // whole: a machine living on it would hold notes no proposal of the network names and prove
    // paths nobody else can verify. The proposal compared is the one in the record and not the one
    // of the archive of proposals, which the close of a machine that took another name rewrites
    // before its own record stands. The roll and the count are not compared: the plane holds
    // neither the cement nor the cohort they are recomputed from.
    pub fn stands_under_its_proposal(&self) -> Result<(), NodeError> {
        let taken = &self.taken;
        let carried = [
            taken.note_root,
            taken.nullifier_root,
            taken.record_root,
            taken.machine_root,
            taken.admitted_root,
            taken.credited_root,
            taken.operations_root,
        ];
        if self.plane.tables_of(taken.window)? != carried {
            return Err(NodeError::Refused {
                what: "a kept plane whose roots are not those of the proposal kept beside it",
            });
        }
        Ok(())
    }
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
    read_back: Arc<Mutex<ReadBack>>,
    // The account this machine keeps of its own doings. Every count of it names nobody, and it is
    // what an operator reads instead of guessing.
    counts: Arc<say::Counts>,
    // The census windows this machine lived and the branch its part walks in each of their cements:
    // its standing, which it proves in a ballot and publishes nowhere.
    census: Arc<Mutex<Vec<attest::LivedCensus>>>,
    // The frames of this machine's own standing at the points of a round, each with what the
    // machine does once the round applies it; and those whose rounds left, told once and told again
    // where a replay moves them, until their window is final.
    settling: Settling,
    retelling: Retelling,
    // The threads carrying the links this machine answered or was handed, each with the end of its
    // link. **A machine stopped lets its store go.** Every such thread holds the store, and one
    // still reading a link the far side kept open held the lock of the root after the machine was
    // dropped, so a start on that store in the same process was refused as held by another.
    carriers: Carriers,
}

// Every link the machine carries is ended and every thread carrying one is waited for, so the store
// goes with the machine: the threads drop what they hold of it before the fields of the machine do.
impl Drop for Machine {
    fn drop(&mut self) {
        let carriers = match self.carriers.get_mut() {
            Ok(carriers) => std::mem::take(carriers),
            Err(poisoned) => std::mem::take(poisoned.into_inner()),
        };
        for (closer, _) in &carriers {
            closer.close();
        }
        for (_, carrier) in carriers {
            let _ = carrier.join();
        }
    }
}

impl Machine {
    // The first start draws the secret; every later one takes the secret that stands. Which of the
    // two happened is answered rather than guessed, because an operator watching a machine start
    // for the second time and being told it was born would be watching a machine that lost its
    // standing without being told.
    pub fn start(configuration: &Configuration) -> Result<(Self, bool), NodeError> {
        let store = Store::open(&configuration.data).map_err(NodeError::Store)?;
        // **What the machine held of the value plane stands again**: the plane of the last window it
        // closed, kept in the record of that close. A note takes its position in the tree of notes,
        // and a path is proven against that tree — so a plane that lived in memory alone made every
        // note die with the run that created it, and a person paid held a note their own machine
        // could no longer prove a path for. What is read here is what this machine wrote, and a
        // record that does not read back whole is refused rather than half-read. **And the standing
        // it earned stands again**, from the same record: a machine that forgot the census windows it
        // lived would vote as a stranger until it had lived them all a second time.
        //
        // **What reads back whole is still not trusted.** The plane is held to the proposal the
        // same record keeps for the window it closed, and a record whose plane gives other roots is
        // refused before a secret is drawn, a door opened or anything held (issue #19, step K3).
        // The head and the window closed name proposals the store holds, or the store refused to
        // open (`StoreError::HeadWithoutItsProposal`, `StoreError::ClosedWithoutItsProposal`).
        let record = store.window().map_err(NodeError::Store)?;
        let kept = if record.kept.is_empty() {
            None
        } else {
            let kept = Kept::decode(&record.kept)?;
            kept.stands_under_its_proposal()?;
            Some(kept)
        };
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
        let retained = mt_genesis::scalar("retained_windows").ok_or(NodeError::Decree {
            row: "retained_windows".to_string(),
        })?;
        let cell_width = mt_wire::cell_bytes().map_err(|_| of_the_decree("cell_bytes"))?;
        let store = Arc::new(store);
        let standing = Standing::loaded(retained, &store, cell_width)?;
        let (held_value, census) = match kept {
            None => (state::State::new(), Vec::new()),
            Some(kept) => (kept.plane, kept.census),
        };
        Ok((
            Self {
                open: Arc::new(Mutex::new(None)),
                store,
                answering,
                door,
                held: Arc::new(Held::to_the_ceiling(ceiling)),
                standing: Arc::new(standing),
                value: Arc::new(Mutex::new(held_value)),
                reached: Arc::new(Mutex::new(Vec::new())),
                admitted: Arc::new(Mutex::new(0)),
                read_back: Arc::new(Mutex::new(ReadBack::to_the_ceiling(
                    mt_store::READ_BACK_BYTES,
                ))),
                counts: Arc::new(say::Counts::default()),
                census: Arc::new(Mutex::new(census)),
                settling: Arc::new(Mutex::new(Vec::new())),
                retelling: Arc::new(Mutex::new(Vec::new())),
                carriers: Mutex::new(Vec::new()),
            },
            born,
        ))
    }

    // The census windows this machine lived, as it kept them.
    pub fn lived_census(&self) -> Result<Vec<attest::LivedCensus>, NodeError> {
        Ok(self
            .census
            .lock()
            .map_err(|_| NodeError::Uncountable)?
            .clone())
    }

    // What this machine holds of the value plane, for as long as the caller holds the guard. A
    // machine that handed out a copy would be handing out a state that stops being the one it
    // applies frames to the moment the next frame arrives.
    pub fn value(&self) -> Result<std::sync::MutexGuard<'_, state::State>, NodeError> {
        self.value.lock().map_err(|_| NodeError::Uncountable)
    }

    // **A frame of this machine's own applies with the frames of its round, and not before.** Canon,
    // "The roots of state": a frame applies once, when a machine leaves the round whose points carry
    // it, among the frames of that round in ascending order of identifier. A payer that applied its
    // own at once would order its round otherwise than every other machine and part from them on the
    // roots, so what its frame took it learns as the round leaves, here.
    pub fn settle_when_applied(
        &self,
        round: Round,
        frame: [u8; 32],
        settlement: Settlement,
    ) -> Result<(), NodeError> {
        self.settling
            .lock()
            .map_err(|_| NodeError::Uncountable)?
            .push((round, frame, settlement));
        Ok(())
    }

    // The settlements of the round this machine leaves, each told what its frame took — or that the
    // round passed it over; one of an earlier window, whose round this machine left without reading
    // it, is told the same. Each is then kept with what it was told, for a replay to tell again.
    fn settle(&self, left: Round, took: &BTreeMap<[u8; 32], Vec<u64>>) -> Result<(), NodeError> {
        let due: Vec<(Round, [u8; 32], Settlement)> = {
            let mut held = self.settling.lock().map_err(|_| NodeError::Uncountable)?;
            let (due, waiting) = std::mem::take(&mut *held)
                .into_iter()
                .partition(|(round, _, _)| *round == left || round.0 < left.0);
            *held = waiting;
            due
        };
        let mut kept = self.retelling.lock().map_err(|_| NodeError::Uncountable)?;
        for (round, frame, mut settlement) in due {
            let told = took.get(&frame).cloned();
            settlement(match &told {
                Some(positions) => Told::Applied(positions.clone()),
                None => Told::Left,
            });
            kept.push((round.0, frame, settlement, told));
        }
        Ok(())
    }

    // **Told again.** The frames of `window` as a replay applied them, by their positions: every
    // settlement of that window whose positions moved is told where to, and one whose frame the
    // replay left out is told that it applies in no window. Consensus, "When the decision is not the
    // name a machine took".
    pub fn retell(
        &self,
        window: u64,
        positions: &BTreeMap<[u8; 32], Vec<u64>>,
    ) -> Result<usize, NodeError> {
        let mut kept = self.retelling.lock().map_err(|_| NodeError::Uncountable)?;
        let mut retold = 0usize;
        for (of, frame, settlement, told) in kept.iter_mut() {
            if *of != window {
                continue;
            }
            let now = positions.get(frame).cloned();
            if now == *told {
                continue;
            }
            // A frame the round passed over that the decided roll holds applies for the first time
            // here, and is told so as such: the payer spends and enters anew, not moves.
            settlement(match (&*told, &now) {
                (None, Some(applied)) => Told::Applied(applied.clone()),
                (Some(_), Some(moved)) => Told::Moved(moved.clone()),
                (_, None) => Told::Left,
            });
            *told = now;
            retold += 1;
        }
        Ok(retold)
    }

    // The settlements of every window at or below `window` go: the window is final and no replay
    // moves its frames again. Each is told so first, so that what a payer kept to follow a replay --
    // the spent notes whole -- goes with them.
    pub fn settled_through(&self, window: u64) -> Result<(), NodeError> {
        let mut kept = self.retelling.lock().map_err(|_| NodeError::Uncountable)?;
        let (due, waiting): (Vec<_>, Vec<_>) = std::mem::take(&mut *kept)
            .into_iter()
            .partition(|(of, _, _, _)| *of <= window);
        *kept = waiting;
        drop(kept);
        for (_, _, mut settlement, _) in due {
            settlement(Told::Final);
        }
        Ok(())
    }

    // The tree of admitted machines this plane stands against, told. It is kept with the plane at
    // the close of the window, as everything the plane of an open window holds is.
    pub fn admits_the_tree(&self, admitted: mt_proof::poseidon::Digest) -> Result<(), NodeError> {
        self.value()?.admits(admitted);
        Ok(())
    }

    // The frames standing at the points of the round this machine is in, verified and applied in
    // ascending order of their identifiers. A frame stands at the points of the round its canonical
    // slot names, exactly as a beacon and the attestations answering it do — so a machine reads the
    // round it is in and no other, and it does so as it leaves the round: Canon, "The roots of
    // state". What does not read back as a whole frame is passed over in silence: a machine answers
    // a malformed deposit with nothing, exactly as it answers everything else.
    pub fn apply_what_stands(&self) -> Result<usize, NodeError> {
        let Some((window, chain, at)) = self.round_of_the_machine() else {
            return Ok(0);
        };
        let mut current = self.value()?;
        let mut state = current.clone();
        let points = round::points_of_round(window, chain, at).map_err(|_| NodeError::Decree {
            row: "consensus_replicas".to_string(),
        })?;
        let width = state::State::width_of_a_frame();
        // The frames of the round by their identifiers: a frame standing at every point of the round
        // is one frame, and the order they apply in is the order of the names and never the order
        // the points or the deliveries came in.
        let mut frames: BTreeMap<[u8; 32], mt_state::layout::Frame> = BTreeMap::new();
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
            let Ok(id) = frame.id() else {
                continue;
            };
            frames.entry(id).or_insert(frame);
        }
        let mut took: BTreeMap<[u8; 32], Vec<u64>> = BTreeMap::new();
        for (id, frame) in &frames {
            // A frame already applied is refused by the state, which holds its nullifiers, and the
            // refusal is passed over here.
            if let Ok(positions) = state.apply(frame, window) {
                took.insert(*id, positions);
            }
        }
        // **What the round put into the plane is held in memory, and kept at the close of the
        // window**, in the one record of that close (`Machine::close`). Canon, "The roots of state":
        // the frames of a round apply as a machine leaves it, and what a verifier recomputes the
        // roots from is the state once the frames of the window have applied. A plane written at
        // every round stood on the disk ahead of the head by a part of a window, a mixture no
        // restart could tell from a close.
        *current = state;
        drop(current);
        self.settle((window, chain, at), &took)?;
        Ok(took.len())
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

    // A proposal kept under its window. It is written before anything points at it, so a machine
    // stopped between the two holds a proposal nothing names rather than a head naming nothing.
    pub fn keep_proposal(&self, proposal: &mt_state::layout::Proposal) -> Result<(), NodeError> {
        let bytes = mt_state::Layout::bytes(proposal).map_err(NodeError::Object)?;
        self.store
            .put_proposal(proposal.window, &bytes)
            .map_err(NodeError::Store)
    }

    // The proposal of a window this machine kept, read back whole or refused.
    pub fn proposal_of(
        &self,
        window: u64,
    ) -> Result<Option<mt_state::layout::Proposal>, NodeError> {
        match self.store.proposal(window).map_err(NodeError::Store)? {
            None => Ok(None),
            Some(bytes) => <mt_state::layout::Proposal as mt_state::Layout>::parse(&bytes)
                .map(Some)
                .map_err(NodeError::Object),
        }
    }

    // The head moves onto a proposal the agreement of the window after it decided, and onto no
    // other: the store refuses a head naming a proposal it does not hold, and this door refuses a
    // head that leaves a decided window — "A decided window is never abandoned by a machine that
    // verified its decision" (Consensus, "Finality").
    pub fn finalize(&self, window: u64) -> Result<(), NodeError> {
        if self.head()?.is_some_and(|held| held > window) {
            return Err(NodeError::Refused {
                what: "a head that leaves a decided window",
            });
        }
        self.store.set_head(window).map_err(NodeError::Store)
    }

    // The record of this machine's agreement on one open window, kept before anything it governs is
    // published and through a restart, and let go at the close. Consensus, "What a machine holds of
    // the agreement"; the store holds one file for each open window and never a history.
    pub fn keep_agreement(&self, record: &attempt::Record) -> Result<(), NodeError> {
        self.store
            .put_agreement(record.window, &record.encode())
            .map_err(NodeError::Store)
    }

    // The opening of a window's record, exclusive: what stands afterwards is this record or the one
    // another process of this store opened first, and the caller compares the name taken.
    pub fn open_agreement(&self, record: &attempt::Record) -> Result<attempt::Record, NodeError> {
        let standing = self
            .store
            .open_agreement(record.window, &record.encode())
            .map_err(NodeError::Store)?;
        attempt::Record::decode(&standing)
    }

    // **The decided state of the head this machine holds**, from the record of the last window it
    // closed: the state that record keeps of the window before the one it closed, where that window
    // is the head. It is what a machine that walked back replays the windows it missed over. None
    // where the record keeps no such state or the head is not the window before the one closed.
    pub fn decided_state_of_the_head(&self) -> Result<Option<(u64, state::State)>, NodeError> {
        let record = self.store.window().map_err(NodeError::Store)?;
        if record.kept.is_empty() {
            return Ok(None);
        }
        let kept = Kept::decode(&record.kept)?;
        match (record.head, record.closed, kept.before) {
            (Some(head), Some(closed), Some(before)) if head.checked_add(1) == Some(closed) => {
                Ok(Some((head, before)))
            }
            _ => Ok(None),
        }
    }

    // The last window this machine closed, or none.
    pub fn closed_window(&self) -> Result<Option<u64>, NodeError> {
        self.store.closed().map_err(NodeError::Store)
    }

    // **Whether this store holds anything of a chain**: a head, a window it closed, the proposal of
    // the first window or its record of the agreement on it. An operator opens a network only on a
    // store holding none of them (Consensus, "The cold start"). The bytes are asked for and not
    // read: a proposal or a record that does not parse is still something this machine wrote, and
    // a store holding it is not empty. A machine reaches no later window without closing one, so
    // these four are everything a chain leaves in a store.
    pub fn holds_a_chain(&self) -> Result<bool, NodeError> {
        Ok(self.head()?.is_some()
            || self.closed_window()?.is_some()
            || self.store.proposal(0).map_err(NodeError::Store)?.is_some()
            || self.store.agreement(0).map_err(NodeError::Store)?.is_some())
    }

    // A window closed: the number that refuses it to be opened again is written first, then its
    // record is let go — so no restart finds a closed window without a record and pledges a second
    // name for it (Consensus, "What a machine holds of the agreement"; "The way back").
    pub fn let_go_of(&self, window: u64) -> Result<(), NodeError> {
        self.store.put_closed(window).map_err(NodeError::Store)?;
        self.drop_agreement(window)
    }

    pub fn agreement_of(&self, window: u64) -> Result<Option<attempt::Record>, NodeError> {
        match self.store.agreement(window).map_err(NodeError::Store)? {
            None => Ok(None),
            Some(bytes) => attempt::Record::decode(&bytes).map(Some),
        }
    }

    // The doors that drop a record are `let_go_of` and `close`, which write the number first: a
    // caller that dropped the record alone would leave a closed window open to a second pledge.
    fn drop_agreement(&self, window: u64) -> Result<(), NodeError> {
        self.store.drop_agreement(window).map_err(NodeError::Store)
    }

    // **A window closes in one writing.** The proposal of the window before that the agreement
    // decided and the proposal of this window are kept first, since nothing may name a proposal the
    // store does not hold; then one record carries the head, the number of the window closed, the
    // plane the window left, the decided state of the window before and the standing; then the record
    // of the agreement of the window goes. Issue #19: the tables, the proposal, the state and the
    // record of a window survive a crash together. Consensus, "The agreement": the decision "makes
    // the proposal of the window before final, and it is the event the pulse names as the close of
    // the window"; a machine whose name was not decided "holds what results as the decided state of
    // the window before"; the record of the agreement goes "when the window they govern closes".
    //
    // **What this machine holds moves only once the record stands.** A close refused before or at
    // the writing leaves the plane and the standing in memory as they were, beside the record of
    // the close before; a failed flush of the directory is not a rollback, since every reader
    // already reads the new record, and the memory follows it.
    pub fn close(&self, closing: Closing) -> Result<(), NodeError> {
        let Closing {
            head: decided,
            taken,
            plane,
            before,
            census: lived,
        } = closing;
        let window = taken.window;
        let standing = self.store.window().map_err(NodeError::Store)?;
        if standing.closed.is_some_and(|closed| window <= closed) {
            return Err(NodeError::Refused {
                what: "a close of a window this machine already closed",
            });
        }
        // "A decided window is never abandoned by a machine that verified its decision"
        // (Consensus, "Finality").
        let head = match &decided {
            Some(decided) if standing.head.is_some_and(|held| held > decided.window) => {
                return Err(NodeError::Refused {
                    what: "a head that leaves a decided window",
                })
            }
            Some(decided) => Some(decided.window),
            None => standing.head,
        };
        // The census windows this machine lived, with the one this close lived replacing what stood
        // for that window: the newest `standing_censuses` of them are what a standing counts.
        let mut census = self.lived_census()?;
        if let Some(lived) = lived {
            let censuses = mt_pulse::standing::censuses().map_err(|_| NodeError::Decree {
                row: "standing_censuses".to_string(),
            })?;
            census.retain(|one| one.window != lived.window);
            census.push(lived);
            census.sort_by_key(|one| std::cmp::Reverse(one.window));
            census.truncate(censuses);
        }
        let kept = Kept {
            taken,
            plane,
            before,
            census,
        };
        let record = mt_store::WindowRecord {
            head,
            closed: Some(window),
            kept: kept.encode()?,
        };
        if let Some(decided) = &decided {
            self.keep_proposal(decided)?;
        }
        self.keep_proposal(&kept.taken)?;
        let written = self.store.commit_window(&record);
        if written.is_ok() || matches!(&written, Err(StoreError::CommitUncertain { .. })) {
            *self.value()? = kept.plane;
            *self.census.lock().map_err(|_| NodeError::Uncountable)? = kept.census;
        }
        written.map_err(NodeError::Store)?;
        self.drop_agreement(window)
    }

    // **What this machine holds of the plane of a window**: the plane the last close left, for the
    // window that close closed, and the decided state of the window before, for that one — what a
    // machine has to answer a device that walked to its head and asks for the tables of the head.
    // Nothing for any other window: a machine keeps no plane further back.
    pub fn plane_of(&self, window: u64) -> Result<Option<state::State>, NodeError> {
        let record = self.store.window().map_err(NodeError::Store)?;
        if record.kept.is_empty() {
            return Ok(None);
        }
        let kept = Kept::decode(&record.kept)?;
        Ok(if kept.taken.window == window {
            Some(kept.plane)
        } else if kept.taken.window.checked_sub(1) == Some(window) {
            kept.before
        } else {
            None
        })
    }

    // **A device that walked to a head holds the plane of that head**, judged before it reaches here
    // (pulse::take_the_plane). It is kept in the record of the window as a close keeps the plane it
    // closed on, beside the proposal whose roots it answers for and under the head and the window
    // closed the walk wrote, and held in memory only once the record stands — so it stands again after
    // a restart. The device lived no window: it holds no decided state of the window before, and its
    // standing is what it already held.
    pub fn hold_the_plane(
        &self,
        head: &mt_state::layout::Proposal,
        plane: state::State,
    ) -> Result<(), NodeError> {
        let standing = self.store.window().map_err(NodeError::Store)?;
        if standing.head != Some(head.window) {
            return Err(NodeError::Refused {
                what: "a plane of another window than the head this machine holds",
            });
        }
        let kept = Kept {
            taken: head.clone(),
            plane,
            before: None,
            census: self.lived_census()?,
        };
        let record = mt_store::WindowRecord {
            head: standing.head,
            closed: standing.closed,
            kept: kept.encode()?,
        };
        let written = self.store.commit_window(&record);
        if written.is_ok() || matches!(&written, Err(StoreError::CommitUncertain { .. })) {
            *self.value()? = kept.plane;
        }
        written.map_err(NodeError::Store)
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
    // A round of a window this machine already closed is refused: the record of that window is
    // gone, and a machine standing in it again could pledge what contradicts what it pledged.
    pub fn enter_round(&self, window: u64, chain: u8, round: u32) -> Result<(), NodeError> {
        if self.closed_window()?.is_some_and(|closed| window <= closed) {
            return Err(NodeError::Refused {
                what: "a round of a window this machine already closed",
            });
        }
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
        let open = self.round_of_the_machine();
        if !accepts_point(&self.store, open, &self.standing, point) {
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
        let window = deposit_window(&self.store, open);
        let of_a_delivery = mt_wire::publish::delivery_of(point, window, cell);
        let took = self
            .standing
            .hold(*point, window, cell.to_vec(), ceiling, of_a_delivery);
        if took == say::Took::Unkept {
            self.counts.raise(&self.counts.pushes_lost);
            return Err(NodeError::Refused {
                what: "a cell the disk of this machine did not take",
            });
        }
        if took == say::Took::Held {
            let_go_on_the_disk(&self.store, &self.standing, window)?;
        }
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
        let closer = link.closer().map_err(NodeError::Net)?;
        let standing = self.held.took()?;
        let held = Arc::clone(&self.held);
        let open = Arc::clone(&self.open);
        let standing_at_the_points = Arc::clone(&self.standing);
        let value = Arc::clone(&self.value);
        let store = Arc::clone(&self.store);
        let width = mt_wire::cell_bytes().map_err(|_| of_the_decree("cell_bytes"))?;
        let admitted = Arc::clone(&self.admitted);
        let counts = Arc::clone(&self.counts);
        let carrier = std::thread::spawn(move || {
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
        self.keep_carrier(closer, carrier)?;
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
        let closer = link.closer().map_err(NodeError::Net)?;
        let open = Arc::clone(&self.open);
        let standing_at_the_points = Arc::clone(&self.standing);
        let value = Arc::clone(&self.value);
        let store = Arc::clone(&self.store);
        let width = mt_wire::cell_bytes().map_err(|_| of_the_decree("cell_bytes"))?;
        let admitted = Arc::clone(&self.admitted);
        let counts = Arc::clone(&self.counts);
        let carrier = std::thread::spawn(move || {
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
        self.keep_carrier(closer, carrier)
    }

    // A carrier is kept until the machine stops. Those whose links already ended go as the next one
    // comes, so a machine answering for months holds the threads that stand and no more.
    fn keep_carrier(
        &self,
        closer: mt_net::Closer,
        carrier: std::thread::JoinHandle<()>,
    ) -> Result<(), NodeError> {
        let mut carriers = self.carriers.lock().map_err(|_| NodeError::Uncountable)?;
        carriers.retain(|(_, carrier)| !carrier.is_finished());
        carriers.push((closer, carrier));
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

    // **The plane of `window` as each machine this one reached offers it**, every table read whole
    // over the link it was asked on, laid out by `State::encoded_of_leaves` with the tree of admitted
    // machines this device stands against. Each offer is judged alone by its caller against the roots
    // of a head it verified (pulse::take_the_plane); how many offers agree decides nothing (Consensus,
    // "The join"). A link that answers with another kind, malformed bytes or past the reach of a
    // count offers nothing.
    pub fn planes_offered(
        &self,
        window: u64,
        admitted: mt_proof::poseidon::Digest,
    ) -> Result<Vec<Vec<u8>>, NodeError> {
        let Some(network) = mt_state::tables::genesis_state_hash() else {
            return Err(NodeError::Refused {
                what: "a network whose Genesis State Hash this build cannot compute",
            });
        };
        let mut offers = Vec::new();
        let mut held = self.reached.lock().map_err(|_| NodeError::Uncountable)?;
        'links: for one in held.iter_mut() {
            let mut tables: [Vec<u8>; 7] = Default::default();
            for table in message::TableIndex::ALL {
                let Ok(bound) = message::table_answer_max(table) else {
                    continue 'links;
                };
                let gathered = &mut tables[usize::from(table.byte())];
                let mut from: u32 = 0;
                loop {
                    let query = message::encode_table_query(&network, window, table, from);
                    if one.link.send(Kind::TableQuery, &query).is_err() {
                        continue 'links;
                    }
                    let Ok((kind, arrived)) = one.link.receive() else {
                        continue 'links;
                    };
                    if kind != Kind::TableAnswer || arrived.len() < 4 {
                        continue 'links;
                    }
                    let mut four = [0u8; 4];
                    four.copy_from_slice(&arrived[..4]);
                    let declared = u32::from_le_bytes(four) as usize;
                    let width = declared
                        .saturating_mul(table.leaf_bytes())
                        .saturating_add(4);
                    if arrived.len() < width {
                        continue 'links;
                    }
                    let Ok(leaves) = message::parse_table_answer(table, &arrived[..width]) else {
                        continue 'links;
                    };
                    gathered.extend_from_slice(&leaves);
                    if declared < bound {
                        break;
                    }
                    let Some(next) = u32::try_from(declared)
                        .ok()
                        .and_then(|n| from.checked_add(n))
                    else {
                        continue 'links;
                    };
                    from = next;
                }
            }
            if let Ok(plane) = state::State::encoded_of_leaves(window, admitted, &tables) {
                offers.push(plane);
            }
        }
        Ok(offers)
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

    // Reconcile a point in both directions. Retained cells are retried until a
    // collection returns those exact bytes, including cells learned from a
    // different peer. Thus an inbound-only holder can receive late evidence.
    // Reconciliation transports bytes; the proof verifier grants authority.
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
                one.taken
                    .retain(|_, known| window <= known.window.saturating_add(1));
                let known = one.taken.entry(*point).or_insert_with(|| RemotePoint {
                    window,
                    read: 0,
                    acknowledged: crate::collections::BTreeSet::new(),
                    asked: 0,
                    pushes_again_at: 0,
                    backoff: 0,
                });
                if known.window != window {
                    known.window = window;
                    known.read = 0;
                    known.acknowledged.clear();
                    known.asked = 0;
                    known.pushes_again_at = 0;
                    known.backoff = 0;
                }
                known.asked = known.asked.saturating_add(1);
                self.counts.raise(&self.counts.collections_asked);
                let Ok(cells) = pulse::collect_from(&mut one.link, point, known.read) else {
                    continue;
                };
                self.counts
                    .raise_by(&self.counts.cells_pulled, cells.len() as u64);
                let read = u16::try_from(cells.len()).unwrap_or(u16::MAX);
                known.read = known.read.saturating_add(read);
                if read > 0 {
                    known.backoff = 0;
                    known.pushes_again_at = known.asked;
                }
                use sha2::{Digest as _, Sha256};
                for cell in &cells {
                    if self.take_deposit(point, cell)? {
                        known.acknowledged.insert(Sha256::digest(cell).into());
                    }
                }
                if known.asked < known.pushes_again_at {
                    continue;
                }
                let mut carried = false;
                for cell in self.standing_at(point) {
                    let digest: [u8; 32] = Sha256::digest(&cell).into();
                    if !known.acknowledged.contains(&digest) {
                        if pulse::deposit_at(&mut one.link, point, &cell).is_err() {
                            self.counts.raise(&self.counts.pushes_lost);
                            break;
                        }
                        carried = true;
                    }
                }
                if carried {
                    self.counts.raise(&self.counts.pushes_carried);
                    known.backoff = known.backoff.max(1).saturating_mul(2);
                    known.pushes_again_at = known.asked.saturating_add(known.backoff);
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
            let mut held = self.read_back.lock().map_err(|_| NodeError::Uncountable)?;
            if let Some(objects) = held.of(point, window, standing) {
                self.counts.raise(&self.counts.points_read_from_memory);
                return Ok(objects);
            }
        }
        self.counts.raise(&self.counts.points_read_back);
        let objects = mt_wire::publish::objects_of(point, window, &self.standing_at(point))
            .map_err(|_| NodeError::Refused {
                what: "cells at a point the wire cannot read back",
            })?;
        let mut held = self.read_back.lock().map_err(|_| NodeError::Uncountable)?;
        held.keep(*point, window, standing, objects.clone());
        Ok(objects)
    }

    // What stands at a point of a window this machine does not stand in, read from every
    // acquaintance it reached and held nowhere: a device walking the past deposits nothing and keeps
    // nothing at a point, and the cells it reads are bound to the window and the point they were cut
    // for, so a cell of another point or window reads back as nothing.
    pub fn collect_public(
        &self,
        point: &[u8; POINT_BYTES],
        window: u64,
    ) -> Result<Vec<Vec<u8>>, NodeError> {
        use sha2::{Digest as _, Sha256};
        let mut cells: Vec<Vec<u8>> = Vec::new();
        let mut seen: crate::collections::BTreeSet<[u8; 32]> = crate::collections::BTreeSet::new();
        {
            let mut held = self.reached.lock().map_err(|_| NodeError::Uncountable)?;
            for one in held.iter_mut() {
                self.counts.raise(&self.counts.collections_asked);
                let Ok(arrived) = pulse::collect_from(&mut one.link, point, 0) else {
                    continue;
                };
                self.counts
                    .raise_by(&self.counts.cells_pulled, arrived.len() as u64);
                for cell in arrived {
                    if seen.insert(Sha256::digest(&cell).into()) {
                        cells.push(cell);
                    }
                }
            }
        }
        mt_wire::publish::objects_of(point, window, &cells).map_err(|_| NodeError::Refused {
            what: "cells at a point the wire cannot read back",
        })
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

    // Both operator interfaces share the same watcher, including a panic of the door thread.
    pub fn answer_in_background(
        self: &Arc<Self>,
    ) -> std::thread::JoinHandle<Result<(), NodeError>> {
        let machine = Arc::clone(self);
        let watch = self.counts.watch_door();
        std::thread::spawn(move || {
            let _watch = watch;
            machine.serve()
        })
    }

    // Answering links until the machine is stopped.
    pub fn serve(&self) -> Result<(), NodeError> {
        loop {
            // A handshake that failed took no slot and is no reason to stop: the next caller may be
            // whoever this machine is waiting for.
            match self.answer_one() {
                Ok(_) | Err(NodeError::Net(_)) => {}
                Err(error) => return Err(error),
            }
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
            Kind::TableQuery => answer_the_table(link, store, &message),
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
        if !accepts_point(store, held, standing, &point) {
            if held.is_none() {
                counts.raise(&counts.deposits_before_a_round);
            } else {
                counts.raise(&counts.deposits_at_another_point);
            }
            return Ok(());
        }
        {
            let window = deposit_window(store, held);
            let of_a_delivery = mt_wire::publish::delivery_of(&point, window, &cell);
            let took = standing.hold(point, window, cell.clone(), ceiling, of_a_delivery);
            if took == say::Took::Unkept
                || (took == say::Took::Held && let_go_on_the_disk(store, standing, window).is_err())
            {
                counts.raise(&counts.pushes_lost);
            }
            match took {
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
    let held = standing.cells_of(&point, usize::from(after), bound);
    let Ok(answer) = message::encode_collect_answer(&held) else {
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

// **A table of a plane this machine holds whole, from the leaf the asker names.** The plane is the
// one the last close kept, of the window it closed or of the window before it, read from the record
// of the window and never from memory, which moves under a frame; any other window, another network
// or a table read to its end is answered with zero leaves, which the asker does not tell apart.
fn answer_the_table(link: &mut Link, store: &Store, message: &[u8]) -> Result<(), NetError> {
    let width = message::table_query_len();
    if message.len() < width {
        return Ok(());
    }
    let Ok((asked, window, table, from)) = message::parse_table_query(&message[..width]) else {
        return Ok(());
    };
    let Some(ours) = mt_state::tables::genesis_state_hash() else {
        return Ok(());
    };
    if asked != ours {
        return Ok(());
    }
    let Ok(bound) = message::table_answer_max(table) else {
        return Ok(());
    };
    let one = table.leaf_bytes();
    let leaves = plane_held(store, window)
        .map(|plane| plane.leaves_of(table, window))
        .unwrap_or_default();
    let start = (from as usize).saturating_mul(one).min(leaves.len());
    let end = start
        .saturating_add(bound.saturating_mul(one))
        .min(leaves.len());
    let Ok(answer) = message::encode_table_answer(table, &leaves[start..end]) else {
        return Ok(());
    };
    link.send(Kind::TableAnswer, &answer)
}

// The plane the record of the window keeps for `window`: the plane of the window the last close
// closed, or the decided state of the window before it, and nothing for any other.
fn plane_held(store: &Store, window: u64) -> Option<state::State> {
    let record = store.window().ok()?;
    if record.kept.is_empty() {
        return None;
    }
    let kept = Kept::decode(&record.kept).ok()?;
    if kept.taken.window == window {
        Some(kept.plane)
    } else if kept.taken.window.checked_sub(1) == Some(window) {
        kept.before
    } else {
        None
    }
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
    // The newest proposal this machine holds, and nothing beside it: a joining device verifies its
    // way to the head from its own anchor and takes this as a hint of where the head stands.
    let Ok(answer) = message::encode_head_answer(&proposal) else {
        return Ok(());
    };
    link.send(Kind::HeadAnswer, &answer)
}

// The windows the memory let go of are let go of on the disk too, once per window turning. The cell
// itself went to the disk where the point took it, under the lock that counted it.
fn let_go_on_the_disk(store: &Store, standing: &Standing, window: u64) -> Result<(), NodeError> {
    if standing.prune_due(window) {
        store
            .drop_points_before(window.saturating_sub(standing.retained))
            .map_err(NodeError::Store)?;
    }
    Ok(())
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
            let unique = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .expect("a test timestamp")
                .as_nanos();
            let at = std::env::temp_dir().join(format!(
                "montana-node-{what}-{}-{unique}",
                std::process::id()
            ));
            fs::create_dir(&at).expect("a fresh scratch directory is writable");
            Self(at)
        }
    }

    // Scratch artifacts are retained for inspection; tests never remove existing files.

    // CNS-20: rejects a terminal door error swallowed by the serving loop or by its caller.
    #[test]
    fn a_dead_door_reaches_the_verdict_and_cannot_be_erased_by_the_pulse() {
        let at = Scratch::named("dead-door");
        let machine = Arc::new(
            Machine::start(&Configuration::at(&at.0, "127.0.0.1:0"))
                .unwrap()
                .0,
        );
        let held = Arc::clone(&machine.held);
        assert!(std::thread::spawn(move || {
            let _held = held.standing.lock().unwrap();
            panic!("corrupt this test's link counter");
        })
        .join()
        .is_err());
        assert_eq!(
            machine.answer_in_background().join().unwrap(),
            Err(NodeError::Uncountable)
        );
        let counts = machine.counts();
        assert_eq!(
            counts.status().unwrap().on(),
            Some(say::Verdict::NoDiagnostics)
        );
        assert_eq!(counts.observe(true, 7, 0, 1), say::Verdict::NoDiagnostics);
        assert_eq!(counts.status().unwrap().exit_code(), 4);
    }

    // CNS-20: a panic must take the same path as an ordinary terminal door error.
    #[test]
    fn an_unwinding_door_leaves_no_diagnostics() {
        let counts = Arc::new(say::Counts::default());
        counts.observe(false, 3, 0, 1);
        let watch = counts.watch_door();
        assert!(std::thread::spawn(move || {
            let _watch = watch;
            panic!("this test's door unwinds");
        })
        .join()
        .is_err());
        assert_eq!(
            counts.status(),
            Some(say::PulseStatus::Stalled {
                on: say::Verdict::NoDiagnostics,
                asking: 3,
                refused: 0,
            })
        );
    }

    // **A point holds its cells on the disk alone, and what was read back holds a ceiling** (issue
    // #63). The wrong implementations refused: a point answering from a copy in memory beside its
    // file, under which a range read here is not the range of the file, and a read-back holding
    // every point of the window it was read in, under which the bytes it holds pass the ceiling.
    #[test]
    fn a_point_holds_its_cells_on_the_disk_alone_and_what_was_read_back_holds_a_ceiling() {
        let scratch = Scratch::named("cells-on-the-disk");
        let store = Arc::new(Store::open(&scratch.0).expect("a fresh store opens"));
        let width = 4;
        let standing = Standing::empty(2, Arc::clone(&store), width);
        let point = [7u8; POINT_BYTES];
        let delivery = Some(([9u8; POINT_BYTES], 3));
        let cells: Vec<Vec<u8>> = (0u8..3).map(|i| vec![i; width]).collect();
        for cell in &cells {
            assert_eq!(
                standing.hold(point, 5, cell.clone(), 8, delivery),
                say::Took::Held
            );
        }
        assert_eq!(
            standing.hold(point, 5, cells[0].clone(), 8, delivery),
            say::Took::Repeated
        );
        assert_eq!(standing.count_at(&point), 3);
        assert_eq!(standing.at(&point), cells);
        assert_eq!(standing.cells_of(&point, 1, 1), vec![cells[1].clone()]);
        assert!(standing.cells_of(&point, 3, 4).is_empty());
        assert_eq!(
            store
                .cells_at(5, &point, width, 0, usize::MAX)
                .expect("the file of the point reads"),
            cells
        );

        let mut read_back = ReadBack::to_the_ceiling(100);
        for i in 0u8..10 {
            read_back.keep([i; POINT_BYTES], 5, 1, vec![vec![i; 30]]);
            assert!(
                read_back.bytes <= 100,
                "the read-back held {} bytes",
                read_back.bytes
            );
        }
        assert_eq!(
            read_back.of(&[9; POINT_BYTES], 5, 1),
            Some(vec![vec![9; 30]])
        );
        assert_eq!(read_back.of(&[0; POINT_BYTES], 5, 1), None);
        read_back.keep([42; POINT_BYTES], 5, 1, vec![vec![0; 101]]);
        assert_eq!(read_back.of(&[42; POINT_BYTES], 5, 1), None);
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
