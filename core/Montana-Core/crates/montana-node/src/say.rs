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

use std::sync::atomic::{AtomicU64, Ordering};

// One count, held so that every thread of a machine may raise it: the door answers on threads of
// its own while the pulse asks on the thread it was called from.
#[derive(Default)]
pub struct Counts {
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
}

impl Counts {
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
             refused {}w/{}d/{}s/{}p/{}o",
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
}
