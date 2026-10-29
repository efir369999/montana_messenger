// What a machine says of itself, and why it says anything at all.
//
// **Silence is what a machine says to a stranger, and never what it writes for its own operator.**
// The wire refuses without a word by design — a deposit of another width, a point of a past window,
// a point already carrying the round it may hold, a collection from a machine at its ceiling — and
// it must, because an answer naming the reason publishes the state of this machine to whoever
// asked. Its own account is not the wire. An operator who cannot see which refusal fired is an
// operator who must guess, and a guess costs what a measurement would have answered.
//
// **Every quantity here names nobody.** They are counts of this machine's own doings — how many
// cells it took, how many it refused and for which of the four reasons, how many it published, how
// many it pulled, how many attestations verified and how many did not and why. No peer, no address,
// no person and no amount appears in any of them, so an account written to an operator's console
// discloses nothing that the points of a round do not already publish.

use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Mutex;

// CNS-20: local observation only; never an input to consensus or to the wire.
//
// There is no verdict `proof refused`. Every refusal this machine counts is of an object that
// arrived at a public point, which anyone may deposit, so a refusal names no cause of a shortfall
// (issue #21, F1a); it is counted beside the verdict as `refused N` and never chosen as one.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Verdict {
    NoData,
    NoQuorum,
    NoDiagnostics,
}

impl Verdict {
    // CNS-20 operator exit codes, requested by issue #21; never protocol values. Code 3 was
    // `proof refused` and is retired with it, not given to another verdict.
    pub fn exit_code(self) -> u8 {
        match self {
            Self::NoQuorum => 1,
            Self::NoData => 2,
            Self::NoDiagnostics => 4,
        }
    }

    pub fn from_line(line: &str) -> Option<Self> {
        [Self::NoData, Self::NoQuorum, Self::NoDiagnostics]
            .into_iter()
            .find(|on| {
                let name = on.to_string();
                line == name
                    || line.starts_with(&format!("{name}:"))
                    || line.starts_with(&format!("{name}; asking "))
            })
    }
}

impl std::fmt::Display for Verdict {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(match self {
            Self::NoData => "no data",
            Self::NoQuorum => "no quorum",
            Self::NoDiagnostics => "no diagnostics",
        })
    }
}

// CNS-20: what the pulse of this run last did, in three readings an operator never confuses
// (issue #21, F2). A window it closed and a shortfall it waits on inside the patience of that wait
// are a healthy node and read 0; only a shortfall the patience ran out on, or a diagnostic that is
// gone, is a stall and reads its verdict's code. `waited` and `patience` are the pulse's own count
// of askings at that wait and its budget, shown and never a new threshold.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PulseStatus {
    Closed {
        window: u64,
        refused: u64,
    },
    Waiting {
        on: Verdict,
        asking: u32,
        waited: u32,
        patience: u32,
        refused: u64,
    },
    Stalled {
        on: Verdict,
        asking: u32,
        refused: u64,
    },
}

impl PulseStatus {
    // The shortfall named, where the reading has one.
    pub fn on(&self) -> Option<Verdict> {
        match *self {
            Self::Closed { .. } => None,
            Self::Waiting { on, .. } | Self::Stalled { on, .. } => Some(on),
        }
    }

    pub fn asking(&self) -> u32 {
        match *self {
            Self::Closed { .. } => 0,
            Self::Waiting { asking, .. } | Self::Stalled { asking, .. } => asking,
        }
    }

    pub fn refused(&self) -> u64 {
        match *self {
            Self::Closed { refused, .. }
            | Self::Waiting { refused, .. }
            | Self::Stalled { refused, .. } => refused,
        }
    }

    pub fn exit_code(&self) -> u8 {
        match *self {
            Self::Stalled { on, .. } => on.exit_code(),
            Self::Closed { .. } | Self::Waiting { .. } => 0,
        }
    }

    // The reading back from the line `Display` writes, and nothing else.
    pub fn parse(line: &str) -> Option<Self> {
        fn number<T: std::str::FromStr>(text: &str) -> Option<T> {
            text.parse().ok()
        }
        let verdict = |text: &str| {
            [Verdict::NoData, Verdict::NoQuorum, Verdict::NoDiagnostics]
                .into_iter()
                .find(|on| on.to_string() == text)
        };
        let (head, refused) = line.rsplit_once("; refused ")?;
        let refused = number(refused)?;
        if let Some(window) = head.strip_prefix("closed window ") {
            return Some(Self::Closed {
                window: number(window)?,
                refused,
            });
        }
        if let Some(waiting) = head.strip_prefix("waiting: ") {
            let (on, rest) = waiting.split_once("; asking ")?;
            let (asking, rest) = rest.split_once("; waited ")?;
            let (waited, patience) = rest.split_once(" of ")?;
            return Some(Self::Waiting {
                on: verdict(on)?,
                asking: number(asking)?,
                waited: number(waited)?,
                patience: number(patience)?,
                refused,
            });
        }
        let (on, asking) = head.split_once("; asking ")?;
        Some(Self::Stalled {
            on: verdict(on)?,
            asking: number(asking)?,
            refused,
        })
    }
}

impl std::fmt::Display for PulseStatus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Closed { window, refused } => {
                write!(f, "closed window {window}; refused {refused}")
            }
            Self::Waiting {
                on,
                asking,
                waited,
                patience,
                refused,
            } => write!(
                f,
                "waiting: {on}; asking {asking}; waited {waited} of {patience}; refused {refused}"
            ),
            Self::Stalled {
                on,
                asking,
                refused,
            } => write!(f, "{on}; asking {asking}; refused {refused}"),
        }
    }
}

// One count, held so that every thread of a machine may raise it: the door answers on threads of
// its own while the pulse asks on the thread it was called from.
#[derive(Default)]
pub struct Counts {
    status: Mutex<Option<PulseStatus>>,
    door_lost: AtomicBool,
    pub light_refused: AtomicU64,
    pub ballots_refused: AtomicU64,
    pub proposals_refused: AtomicU64,
    // What arrived at the door before any rule looked at it. Held apart from what was taken so
    // that a machine holding nothing can say whether nothing came or everything was refused — the
    // two look alike from outside and are opposite inside.
    pub deposits_arrived: AtomicU64,
    pub deposits_taken: AtomicU64,
    pub deposits_repeated: AtomicU64,
    pub deposits_of_another_width: AtomicU64,
    pub deposits_at_another_point: AtomicU64,
    // Refused because this machine stood in no round at all when it came. Held apart from a point
    // of another round, because the two are opposite: one is a machine that has not opened its
    // window yet, the other a machine that has moved past the round the sender is in.
    pub deposits_before_a_round: AtomicU64,
    pub deposits_past_the_ceiling: AtomicU64,
    pub collections_answered: AtomicU64,
    pub cells_answered: AtomicU64,
    pub publications: AtomicU64,
    pub cells_published: AtomicU64,
    pub pushes_carried: AtomicU64,
    pub pushes_lost: AtomicU64,
    pub collections_asked: AtomicU64,
    pub cells_pulled: AtomicU64,
    pub points_read_back: AtomicU64,
    pub points_read_from_memory: AtomicU64,
    pub attestations_entered: AtomicU64,
    pub attestations_repeated: AtomicU64,
    pub attestations_of_another_window: AtomicU64,
    pub attestations_undrawn: AtomicU64,
    pub attestations_unsigned: AtomicU64,
    pub attestations_unproven: AtomicU64,
    pub attestations_refused: AtomicU64,
    // The pledges of the agreement: booked under a proven key, refused under one, and made by this
    // machine.
    pub pledges_booked: AtomicU64,
    pub pledges_refused: AtomicU64,
    pub pledges_made: AtomicU64,
}

impl Counts {
    pub fn status(&self) -> Option<PulseStatus> {
        let held = self.status.lock().ok().and_then(|held| *held);
        if self.door_lost.load(Ordering::Acquire) {
            Some(PulseStatus::Stalled {
                on: Verdict::NoDiagnostics,
                asking: held.map_or(0, |status| status.asking()),
                refused: self.refusals(),
            })
        } else {
            held
        }
    }

    fn hold(&self, status: PulseStatus) {
        if let Ok(mut held) = self.status.lock() {
            *held = Some(status);
        }
    }

    // A refused public deposit proves no cause of the shortfall. Keep its count beside
    // the verdict: an outsider can increase this count but cannot select the verdict.
    // `waited` askings of `patience` are spent at this wait: it is a wait, not yet a stall.
    pub fn observe(&self, missing: bool, asking: u32, waited: u32, patience: u32) -> Verdict {
        let on = if self.door_lost.load(Ordering::Acquire) {
            Verdict::NoDiagnostics
        } else if missing {
            Verdict::NoData
        } else {
            Verdict::NoQuorum
        };
        self.hold(PulseStatus::Waiting {
            on,
            asking,
            waited,
            patience,
            refused: self.refusals(),
        });
        on
    }

    // The patience of a wait ran out on `on`: the reading becomes the stall, and the error the
    // pulse returns is made here so that neither is had without the other. Nothing is closed.
    pub fn exhausted(&self, on: Verdict, what: &'static str) -> crate::NodeError {
        let asking = self.status().map_or(0, |status| status.asking());
        self.hold(PulseStatus::Stalled {
            on,
            asking,
            refused: self.refusals(),
        });
        crate::NodeError::Stalled { on, what }
    }

    // Read only after the record of the close stands.
    pub fn closed(&self, window: u64) {
        self.hold(PulseStatus::Closed {
            window,
            refused: self.refusals(),
        });
    }

    pub fn clear_status(&self) {
        if let Ok(mut held) = self.status.lock() {
            *held = None;
        }
    }

    pub fn watch_door(self: &std::sync::Arc<Self>) -> DoorWatch {
        DoorWatch(std::sync::Arc::clone(self))
    }

    pub fn refusals(&self) -> u64 {
        [
            &self.attestations_undrawn,
            &self.attestations_unsigned,
            &self.attestations_unproven,
            &self.attestations_refused,
            &self.pledges_refused,
            &self.light_refused,
            &self.ballots_refused,
            &self.proposals_refused,
        ]
        .iter()
        .fold(0u64, |sum, count| {
            sum.saturating_add(count.load(Ordering::Relaxed))
        })
    }

    pub fn raise(&self, which: &AtomicU64) {
        which.fetch_add(1, Ordering::Relaxed);
    }

    pub fn raise_by(&self, which: &AtomicU64, howmany: u64) {
        which.fetch_add(howmany, Ordering::Relaxed);
    }

    // The whole account as one line: dense, so that a machine standing at a round for minutes
    // prints one line per round and an operator reads the shape of it at a glance.
    pub fn line(&self) -> String {
        let held = |one: &AtomicU64| one.load(Ordering::Relaxed);
        format!(
            "arrived {} took {} repeat {} refused {}w/{}p/{}n/{}c | published {} in {} cells, pushed {} lost {} \
             | asked {} pulled {} cells | read back {} of memory {} | cement +{} repeat {} \
             refused {}w/{}d/{}s/{}p/{}o | pledges booked {} refused {} made {} | refused light {} ballot {} proposal {}",
            held(&self.deposits_arrived),
            held(&self.deposits_taken),
            held(&self.deposits_repeated),
            held(&self.deposits_of_another_width),
            held(&self.deposits_at_another_point),
            held(&self.deposits_before_a_round),
            held(&self.deposits_past_the_ceiling),
            held(&self.publications),
            held(&self.cells_published),
            held(&self.pushes_carried),
            held(&self.pushes_lost),
            held(&self.collections_asked),
            held(&self.cells_pulled),
            held(&self.points_read_back),
            held(&self.points_read_from_memory),
            held(&self.attestations_entered),
            held(&self.attestations_repeated),
            held(&self.attestations_of_another_window),
            held(&self.attestations_undrawn),
            held(&self.attestations_unsigned),
            held(&self.attestations_unproven),
            held(&self.attestations_refused),
            held(&self.pledges_booked),
            held(&self.pledges_refused),
            held(&self.pledges_made),
            held(&self.light_refused),
            held(&self.ballots_refused),
            held(&self.proposals_refused),
        )
    }
}

// Why a deposit was not held. The wire answers none of these to whoever deposited; the account of
// the machine names all of them.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Took {
    Held,
    Repeated,
    AnotherWidth,
    AnotherPoint,
    PastTheCeiling,
    // The disk did not take it, so the point does not count it: a count its file does not hold
    // would hand a reader an index past the cells.
    Unkept,
}

// A returning or unwinding door cannot leave a healthy-looking observation behind.
pub struct DoorWatch(std::sync::Arc<Counts>);
impl Drop for DoorWatch {
    fn drop(&mut self) {
        self.0.door_lost.store(true, Ordering::Release);
    }
}
