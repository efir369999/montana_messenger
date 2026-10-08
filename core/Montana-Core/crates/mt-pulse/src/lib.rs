// The pulse of Montana, without proofs. What a window is made of before a circuit enters it: the
// eligibility of a machine for a round, the ticket of the draw, the two thresholds and their
// recomputations, the close of a window, the slots a selection event offers, the cement, and the
// fold the cement is opened over.
//
// Every number here comes from the Decree through `mt-genesis`; every derivation from `mt-derive`;
// every commitment from `mt-suite`. Nothing in this crate invents a value, and the conformance
// harness refuses a build in which the set and it disagree.

#![forbid(unsafe_code)]
#![deny(clippy::all)]

pub mod close;
pub mod fold;
pub mod retarget;
pub use mt_codec::wide;

pub use wide::U256;

mt_codec::constants! {
    CHAINS:
    /// The chain a cohort that witnesses itself opens on: the first of the ones the cascade
    /// entitles. The set names how many chains a window carries and never which of them a cohort
    /// begins at, because the cascade reaches for the rest only when a runner falls silent.
    pub const OPENING_CHAIN: u8 = 0, code "the first of the chains the cascade entitles, which is where a cohort that witnesses itself stands; the set names the count of chains and never which one is opened on";
    /// How many askings a machine spends before writing its account again while it waits at a
    /// round. A round is made of waiting, so a machine that spoke only when it moved would be
    /// silent for exactly the stretch an operator needs to see into.
    pub const SAYS_EVERY: u32 = 200, code "how often a machine writes its own account while it waits, which is the cadence of a person watching a console and no quantity of the protocol: a machine told twice as often cements the same windows";
    /// How many askings a machine spends at a round before it gives that round up. It guards
    /// against a hang and measures no honest work: a round waits for an echo, and an echo may be a
    /// neighbour building the proof of a frame it publishes inside this very window.
    pub const WAITS_UP_TO: u32 = 144_000, code "how long a machine stands at a round before giving it up, which is a guard against talking to nobody and no quantity of the protocol: nothing measures how long an echo flies, so a bound cut to the length of an ordinary echo turns a neighbour's honest work into a lost round";
    /// How many askings a machine spends before it dials again an acquaintance that did not answer
    /// when it started. A machine of a cohort started before its neighbour finds nobody at the
    /// address, and a machine that dialled once and never again is left with no link of its own:
    /// it can be written into and never ask, so a window it falls one behind in is a window it
    /// never leaves.
    pub const REACHES_AGAIN_EVERY: u32 = 400, code "how often a machine dials again an acquaintance that did not answer at its start, which is the patience of an operator restarting a neighbour and no quantity of the protocol: a machine that dialled twice as often holds the same link one asking sooner";
}

#[derive(Debug, PartialEq, Eq)]
pub enum PulseError {
    // The Decree names every number this crate reads; a tree without one of them is not this
    // protocol, and a tree whose Decree is incomplete opens no chain at all.
    DecreeIncomplete,
    // A count no run of this protocol produces, offered to a rule that would have to wrap to
    // accept it.
    CountBeyondWidth,
    // A fold over no leaves is not a fold: a window that cemented nothing has no tree.
    NoLeaves,
    // Two attestations under one part-nullifier offered to the tree. Which of them entered the
    // cement is decided by arrival and not by a sort, so the tree refuses the pair rather than
    // choosing between them.
    RepeatedPart,
}

// A value clears a threshold when it falls **below** it, compared as an unsigned big-endian
// integer over the full width. Both the ticket of the draw and the eligibility of a round are
// compared this way, and they are one function because they are one comparison — a second copy of
// it is the place the two would drift apart.
pub fn clears(value: &[u8; 32], threshold: &U256) -> bool {
    U256::from_be_bytes(value) < *threshold
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_value_clears_when_it_falls_below_and_never_at_the_threshold_itself() {
        let threshold = U256::from_u64(1 << 20);
        let mut low = [0u8; 32];
        low[29] = 0x0F;
        assert!(clears(&low, &threshold));
        assert!(!clears(&threshold.to_be_bytes(), &threshold));
        let mut high = [0u8; 32];
        high[0] = 1;
        assert!(!clears(&high, &threshold));
        // Nothing clears a threshold of zero, and everything but the top clears the widest one.
        assert!(!clears(&[0u8; 32], &U256::ZERO));
        assert!(clears(&[0u8; 32], &U256::ONE));
    }

    #[test]
    fn the_comparison_reads_the_most_significant_byte_first() {
        // The named wrong implementation: a comparison reading the value from the other end. A
        // vector standing on a value whose two ends agree could not tell them apart, so this one
        // stands on a value whose ends differ.
        let mut value = [0u8; 32];
        value[0] = 0x00;
        value[31] = 0xFF;
        let threshold = U256::from_u64(0x1_0000);
        assert!(clears(&value, &threshold));
        let mut reversed = value;
        reversed.reverse();
        assert!(!clears(&reversed, &threshold));
    }
}
