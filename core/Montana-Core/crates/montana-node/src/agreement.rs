// The agreement on what a window decided, as a count every verifier makes. Consensus, "The agreement on
// what a window decided": in the window after a proposal, the parts of its electorate pledge names in
// attempts; an open pledge counts where it stands on none or on a quorum of open pledges of the
// attempt it names, a closing pledge counts where the open pledges of its own attempt reach the quorum
// on its name, and a name is decided when the closing pledges of one attempt reach the quorum on it.
//
// What stands here reads no clock and no network: it is the book of what a machine holds and the
// counts the set states over it, so every machine holding the same pledges reaches the same answers,
// and a test holds each rule without a wire. The conduct of a machine — when it pledges, how long it
// waits — stands in the pulse, where waiting is.

use std::collections::{BTreeMap, BTreeSet};

use mt_state::layout::Pledge;
use mt_state::STANDS_ON_NONE;

pub type Name = [u8; 32];
pub type Part = [u8; 32];

// The two kinds a pledge is counted under: an open pledge stands on an earlier quorum or on none, a
// closing pledge on the quorum of its own attempt.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Kind {
    Open,
    Closing,
}

// What the quorum of an attempt is read against: the count of the electorate and the committee its
// standing draws, and the votes the verified ballots of each part cast. The rule is the close's own,
// `closes_window` of Canon, so the agreement adds no number of its own.
pub struct Electorate<'a> {
    pub count: u64,
    pub committee: u64,
    pub votes: &'a BTreeMap<Part, u64>,
}

impl Electorate<'_> {
    fn reached(&self, parts: &BTreeSet<Part>) -> bool {
        let votes: u128 = parts
            .iter()
            .map(|part| u128::from(*self.votes.get(part).unwrap_or(&0)))
            .sum();
        mt_pulse::close::closes_window(
            parts.len() as u128,
            u128::from(self.count),
            votes,
            u128::from(self.committee),
        )
        .unwrap_or(false)
    }

    // The parts beyond the share the quorum leaves: more than `T - Q`, which no faulty set within
    // the bound fills alone. `Q` is the least count the quorum share admits.
    fn beyond_the_faulty(&self, parts: usize) -> bool {
        let total = u128::from(self.count);
        let reaches = |c: u128| mt_pulse::close::quorum_reached(c, total).unwrap_or(false);
        let (mut low, mut high) = (0u128, total);
        while low < high {
            let middle = low + (high - low) / 2;
            if reaches(middle) {
                high = middle;
            } else {
                low = middle + 1;
            }
        }
        parts as u128 > total - low
    }
}

// A pair of pledges under one part that the set calls a contradiction: two open pledges of one attempt
// on two names, two closing pledges of one attempt on two names, or a closing pledge on one name and,
// in a later attempt, an open pledge on another standing on none or on an attempt before the closing
// one. Consensus, "Finality": the pairs are the whole evidence.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Contradiction {
    pub first: Pledge,
    pub second: Pledge,
}

// Whether `later`, an open pledge, contradicts `closing` of the same part: an attempt after it, another
// name, standing on none or on an attempt before the closing one.
fn contradicts(closing: &Pledge, later: &Pledge) -> bool {
    closing.part_nullifier == later.part_nullifier
        && later.attempt > closing.attempt
        && later.name != closing.name
        && later
            .stands_on()
            .is_none_or(|since| since < closing.attempt)
}

// What a machine holds of the agreement on one proposal: every part's first pledge of each kind and
// attempt, the open pledges of attempt zero its heavy attestations made, and the contradictions met.
#[derive(Default)]
pub struct Book {
    window: u64,
    first: BTreeMap<(Kind, u32), BTreeMap<Part, (Name, u32)>>,
    held: BTreeMap<(Kind, u32, Part), Pledge>,
    pub contradictions: Vec<Contradiction>,
}

impl Book {
    // The book of the agreement run in `window`, on the proposal of the window before it.
    pub fn of_the_window(window: u64) -> Self {
        Self {
            window,
            ..Self::default()
        }
    }

    // The heavy attestation of a part is its open pledge of attempt zero, standing on none, on the name
    // it attests beside the beacon of its round.
    pub fn heavy(&mut self, part: Part, name: Name) {
        self.first
            .entry((Kind::Open, 0))
            .or_default()
            .entry(part)
            .or_insert((name, STANDS_ON_NONE));
    }

    // A pledge whose signature and heavy attestation the caller verified. A part counts once per kind
    // and attempt, at its first appearance; a second on another name is a contradiction and adds
    // nothing, and a repetition on the same name adds nothing.
    pub fn pledge(&mut self, pledge: Pledge) {
        if pledge.window != self.window {
            return;
        }
        let kind = if pledge.is_closing() {
            Kind::Closing
        } else {
            Kind::Open
        };
        let met: Vec<Contradiction> = self
            .held
            .iter()
            .filter_map(|((held_kind, _, _), held)| match (kind, held_kind) {
                (Kind::Open, Kind::Closing) if contradicts(held, &pledge) => Some(Contradiction {
                    first: held.clone(),
                    second: pledge.clone(),
                }),
                (Kind::Closing, Kind::Open) if contradicts(&pledge, held) => Some(Contradiction {
                    first: pledge.clone(),
                    second: held.clone(),
                }),
                _ => None,
            })
            .collect();
        self.contradictions.extend(met);
        let at = (kind, pledge.attempt, pledge.part_nullifier);
        if let Some(first) = self.held.get(&at) {
            if first.name != pledge.name {
                self.contradictions.push(Contradiction {
                    first: first.clone(),
                    second: pledge,
                });
            }
            return;
        }
        self.first
            .entry((kind, pledge.attempt))
            .or_default()
            .insert(pledge.part_nullifier, (pledge.name, pledge.since));
        self.held.insert(at, pledge);
    }

    // Every attempt and name the counted open pledges reach the quorum on, attempt by attempt from
    // zero: an open pledge standing on an attempt counts only where that attempt's quorum on its own
    // name is already in the set, and an attempt it stands on is always an earlier one.
    pub fn open_quorums(&self, electorate: &Electorate<'_>) -> BTreeSet<(u32, Name)> {
        let mut reached: BTreeSet<(u32, Name)> = BTreeSet::new();
        for ((kind, attempt), parts) in &self.first {
            if *kind != Kind::Open {
                continue;
            }
            let mut by_name: BTreeMap<Name, BTreeSet<Part>> = BTreeMap::new();
            for (part, (name, since)) in parts {
                if *since == STANDS_ON_NONE || reached.contains(&(*since, *name)) {
                    by_name.entry(*name).or_default().insert(*part);
                }
            }
            for (name, parts) in by_name {
                if electorate.reached(&parts) {
                    reached.insert((*attempt, name));
                }
            }
        }
        reached
    }

    // The decision: the earliest attempt whose closing pledges, each counted where the open pledges of
    // its own attempt reach the quorum on its name, reach the quorum on one name.
    pub fn decided(&self, electorate: &Electorate<'_>) -> Option<(Name, u32)> {
        let quorums = self.open_quorums(electorate);
        for ((kind, attempt), parts) in &self.first {
            if *kind != Kind::Closing {
                continue;
            }
            let mut by_name: BTreeMap<Name, BTreeSet<Part>> = BTreeMap::new();
            for (part, (name, _)) in parts {
                if quorums.contains(&(*attempt, *name)) {
                    by_name.entry(*name).or_default().insert(*part);
                }
            }
            for (name, parts) in by_name {
                if electorate.reached(&parts) {
                    return Some((name, *attempt));
                }
            }
        }
        None
    }

    // Whether the open pledges of `attempt` from distinct parts reach the quorum share whatever names
    // they carry: the spoken quorum a machine waits one span on before it moves on.
    pub fn spoken(&self, attempt: u32, electorate: &Electorate<'_>) -> bool {
        self.first
            .get(&(Kind::Open, attempt))
            .is_some_and(|parts| electorate.reached(&parts.keys().copied().collect()))
    }

    // The latest attempt after `attempt` whose pledges come from more than `T - Q` distinct parts: an
    // attempt a machine behind is drawn into.
    pub fn drawn_into(&self, attempt: u32, electorate: &Electorate<'_>) -> Option<u32> {
        let mut by_attempt: BTreeMap<u32, BTreeSet<Part>> = BTreeMap::new();
        for ((_, at), parts) in &self.first {
            if *at > attempt {
                by_attempt
                    .entry(*at)
                    .or_default()
                    .extend(parts.keys().copied());
            }
        }
        by_attempt
            .into_iter()
            .rev()
            .find(|(_, parts)| electorate.beyond_the_faulty(parts.len()))
            .map(|(at, _)| at)
    }

    // How many pledges the book holds, heavy attestations counted as the open pledges of attempt
    // zero they are: what a machine says of its agreement, and no rule.
    pub fn held(&self) -> usize {
        self.first.values().map(|parts| parts.len()).sum()
    }

    // The open pledges of `attempt`, part by part, with the name and the attempt each stands on.
    pub fn open_of(&self, attempt: u32) -> Vec<(Part, Name, u32)> {
        self.first
            .get(&(Kind::Open, attempt))
            .map(|parts| {
                parts
                    .iter()
                    .map(|(part, (name, since))| (*part, *name, *since))
                    .collect()
            })
            .unwrap_or_default()
    }

    // The name the counted open pledges of `attempt` reach the quorum on: what a closing pledge of
    // that attempt stands on, and what "It closes on what it sees" reads. Two names reach it only
    // where more than the fault bound signed both, which "Finality" states; the book answers with
    // the first in the order of names where it ever holds two, so every holder answers alike.
    pub fn open_quorum_of(&self, attempt: u32, electorate: &Electorate<'_>) -> Option<Name> {
        self.open_quorums(electorate)
            .into_iter()
            .find(|(at, _)| *at == attempt)
            .map(|(_, name)| name)
    }

    // The valid name of a machine holding this book: the name and the attempt of the newest quorum
    // of open pledges it holds, or none. Consensus, "What a machine holds of the agreement".
    pub fn valid_name(&self, electorate: &Electorate<'_>) -> Option<(Name, u32)> {
        self.open_quorums(electorate)
            .into_iter()
            .next_back()
            .map(|(at, name)| (name, at))
    }

    // Whether `name` is backed by a quorum of open pledges of some attempt: one of the three ways a
    // name is valid to a machine. Consensus, "valid to a machine".
    pub fn backs(&self, name: &Name, electorate: &Electorate<'_>) -> bool {
        self.open_quorums(electorate)
            .iter()
            .any(|(_, held)| held == name)
    }

    // The open pledge of `attempt` from the part at the lowest place, with the name and the attempt
    // it stands on: what a follower takes two spans after it entered the attempt. The place is
    // Canon's, over the cemented aggregate of the window two before.
    pub fn lowest_place_open(
        &self,
        attempt: u32,
        aggregate: &[u8; 32],
    ) -> Option<(Part, Name, u32)> {
        self.open_of(attempt)
            .into_iter()
            .min_by_key(|(part, _, _)| place(part, aggregate, attempt))
    }

    // Whether an open pledge of `attempt` stands from a part whose place is below `mine`: what a
    // proposer checks before it publishes its own.
    pub fn holds_open_below(&self, attempt: u32, mine: &[u8; 32], aggregate: &[u8; 32]) -> bool {
        self.open_of(attempt)
            .iter()
            .any(|(part, _, _)| place(part, aggregate, attempt) < *mine)
    }
}

// The place of a part in an attempt: Canon, "The round of a chain, in integers". The parts propose in
// ascending order of it, compared unsigned and big-endian over the full width, and nothing in it is
// anyone's to choose.
pub fn place(part: &Part, aggregate: &[u8; 32], attempt: u32) -> [u8; 32] {
    let mut body = Vec::with_capacity(32 + 32 + 4);
    body.extend_from_slice(part);
    body.extend_from_slice(aggregate);
    body.extend_from_slice(&attempt.to_le_bytes());
    mt_codec::hash_of_one(mt_codec::domain::MT_PROPOSER, &body)
}

#[cfg(test)]
mod tests {
    use super::*;

    const X: Name = [0x58; 32];
    const Y: Name = [0x59; 32];

    fn part(i: u8) -> Part {
        [i; 32]
    }

    fn pledge(at: u8, attempt: u32, name: Name, since: u32) -> Pledge {
        Pledge {
            window: 7,
            attempt,
            name,
            since,
            part_nullifier: part(at),
            suite_id: 1,
            answering_key: vec![0xA1; mt_codec::size::SIGNING_PUBLIC_KEY],
            signature: vec![0xF0; mt_codec::size::SIGNATURE],
        }
    }

    fn four(votes: &BTreeMap<Part, u64>) -> Electorate<'_> {
        Electorate {
            count: 4,
            committee: 0,
            votes,
        }
    }

    // A split of two and two at attempt zero decides nothing; three parts opening attempt one on X
    // and closing on it decide X in attempt one. The wrong implementation refused: one counting the
    // heavy attestations of both names together toward one quorum.
    #[test]
    fn a_split_heavy_vote_is_decided_by_a_later_attempt() {
        let votes = BTreeMap::new();
        let electorate = four(&votes);
        let mut book = Book::of_the_window(7);
        book.heavy(part(1), X);
        book.heavy(part(2), X);
        book.heavy(part(3), Y);
        book.heavy(part(4), Y);
        assert!(book.open_quorums(&electorate).is_empty());
        assert!(book.spoken(0, &electorate));
        assert_eq!(book.decided(&electorate), None);
        for at in 1..=3 {
            book.pledge(pledge(at, 1, X, STANDS_ON_NONE));
        }
        assert!(book.open_quorums(&electorate).contains(&(1, X)));
        assert_eq!(book.decided(&electorate), None);
        for at in 1..=3 {
            book.pledge(pledge(at, 1, X, 1));
        }
        assert_eq!(book.decided(&electorate), Some((X, 1)));
        assert!(book.contradictions.is_empty());
    }

    // A closing pledge counts only on the open quorum of its own attempt, and an open pledge standing
    // on an attempt counts only where that attempt reached the quorum on its name. The wrong
    // implementations refused: one counting closing pledges by themselves, and one counting an open
    // pledge on whatever attempt it names.
    #[test]
    fn a_pledge_counts_only_on_the_quorum_it_names() {
        let votes = BTreeMap::new();
        let electorate = four(&votes);
        let mut book = Book::of_the_window(7);
        for at in 1..=3 {
            book.pledge(pledge(at, 2, X, 2));
        }
        assert_eq!(book.decided(&electorate), None);
        for at in 1..=3 {
            book.pledge(pledge(at, 3, Y, 2));
        }
        assert!(!book.open_quorums(&electorate).contains(&(3, Y)));
        for at in 1..=3 {
            book.pledge(pledge(at, 2, Y, STANDS_ON_NONE));
        }
        assert!(book.open_quorums(&electorate).contains(&(3, Y)));
    }

    // The three contradicting pairs, and the pledge that is not one: an open pledge of a later attempt
    // standing on an attempt at or after the closing one is what a lock admits.
    #[test]
    fn the_three_pairs_are_evidence_and_a_freed_pledge_is_not() {
        let mut book = Book::of_the_window(7);
        book.pledge(pledge(1, 1, X, STANDS_ON_NONE));
        book.pledge(pledge(1, 1, Y, STANDS_ON_NONE));
        assert_eq!(book.contradictions.len(), 1);
        book.pledge(pledge(2, 1, X, 1));
        book.pledge(pledge(2, 1, Y, 1));
        assert_eq!(book.contradictions.len(), 2);
        book.pledge(pledge(3, 1, X, 1));
        book.pledge(pledge(3, 2, Y, 1));
        assert_eq!(book.contradictions.len(), 2);
        book.pledge(pledge(3, 3, Y, STANDS_ON_NONE));
        assert_eq!(book.contradictions.len(), 3);
        book.pledge(pledge(4, 4, Y, 0));
        book.pledge(pledge(4, 2, X, 2));
        assert_eq!(book.contradictions.len(), 4);
        book.pledge(pledge(1, 1, X, STANDS_ON_NONE));
        assert_eq!(book.contradictions.len(), 4);
        assert!(book
            .contradictions
            .iter()
            .all(|pair| { pair.first.part_nullifier == pair.second.part_nullifier }));
    }

    // A machine behind is drawn into an attempt by more than `T - Q` parts and never by fewer: at four
    // machines and a quorum of three, two parts draw and one does not.
    #[test]
    fn a_machine_is_drawn_forward_by_more_than_the_faulty_can_fill() {
        let votes = BTreeMap::new();
        let electorate = four(&votes);
        let mut book = Book::of_the_window(7);
        book.pledge(pledge(1, 3, X, STANDS_ON_NONE));
        assert_eq!(book.drawn_into(0, &electorate), None);
        book.pledge(pledge(2, 3, Y, STANDS_ON_NONE));
        assert_eq!(book.drawn_into(0, &electorate), Some(3));
        assert_eq!(book.drawn_into(3, &electorate), None);
    }

    // The valid name is the newest quorum of open pledges, and a name is backed by any quorum. The
    // wrong implementation refused: one answering the earliest quorum, which would stand a proposer
    // of a later attempt on a quorum its lock may be past.
    #[test]
    fn a_valid_name_is_the_newest_open_quorum() {
        let votes = BTreeMap::new();
        let electorate = four(&votes);
        let mut book = Book::of_the_window(7);
        assert_eq!(book.valid_name(&electorate), None);
        for at in 1..=3 {
            book.pledge(pledge(at, 1, X, STANDS_ON_NONE));
        }
        assert_eq!(book.valid_name(&electorate), Some((X, 1)));
        assert_eq!(book.open_quorum_of(1, &electorate), Some(X));
        assert_eq!(book.open_quorum_of(2, &electorate), None);
        for at in 1..=3 {
            book.pledge(pledge(at, 2, Y, STANDS_ON_NONE));
        }
        assert_eq!(book.valid_name(&electorate), Some((Y, 2)));
        assert!(book.backs(&X, &electorate));
        assert!(book.backs(&Y, &electorate));
        assert!(!book.backs(&[0x5A; 32], &electorate));
    }

    // The lowest place is the least place compared unsigned and big-endian over the full width,
    // which is the order of the byte arrays. The wrong implementation refused: one comparing the
    // places little-endian, which the vector below tells apart from the right one by construction.
    #[test]
    fn the_lowest_place_is_read_big_endian_over_the_full_width() {
        let aggregate = [0x33; 32];
        let parts: Vec<Part> = (1..=6).map(part).collect();
        let mut book = Book::of_the_window(7);
        for at in 1..=6 {
            book.pledge(pledge(at, 1, X, STANDS_ON_NONE));
        }
        let big = parts
            .iter()
            .min_by_key(|part| place(part, &aggregate, 1))
            .copied()
            .expect("six parts");
        let little = parts
            .iter()
            .min_by_key(|part| {
                let mut reversed = place(part, &aggregate, 1);
                reversed.reverse();
                reversed
            })
            .copied()
            .expect("six parts");
        assert_ne!(big, little, "the vector does not tell the two orders apart");
        assert_eq!(
            book.lowest_place_open(1, &aggregate)
                .map(|(part, _, _)| part),
            Some(big)
        );
        let mine = place(&big, &aggregate, 1);
        assert!(!book.holds_open_below(1, &mine, &aggregate));
        let highest = parts
            .iter()
            .max_by_key(|part| place(part, &aggregate, 1))
            .copied()
            .expect("six parts");
        assert!(book.holds_open_below(1, &place(&highest, &aggregate, 1), &aggregate));
        assert_eq!(book.lowest_place_open(2, &aggregate), None);
    }

    // The frozen vectors of the place, computed from the formula of Canon ("The round of a chain, in
    // integers": SHA-256("mt-proposer" || 0x00 || part_nf || A || a_4B_LE)) and held here byte for
    // byte until Canon carries them. Each rejects one wrong implementation: the first any other
    // domain, separator or field order; the second one leaving the attempt out of the preimage (the
    // place would not move with it); the third one swapping the part and the aggregate (the two are
    // the same width, and only the order tells them apart); the fourth one writing the attempt
    // big-endian, which at 256 is the byte string 00 00 01 00 in place of 00 01 00 00.
    #[test]
    fn the_frozen_vectors_of_the_place_reproduce() {
        fn hex(bytes: &[u8; 32]) -> String {
            bytes.iter().map(|b| format!("{b:02x}")).collect()
        }
        let part = [0x11u8; 32];
        let aggregate = [0x33u8; 32];
        assert_eq!(
            hex(&place(&part, &aggregate, 1)),
            "430bafb243a6b07ed4cb9340acd703ca59587af774155eb8687a219addc126bc"
        );
        assert_eq!(
            hex(&place(&part, &aggregate, 2)),
            "af654e51a968a99462dcb79fbe5d0771dc079138de0cec4429e4140ec89c91a5"
        );
        assert_eq!(
            hex(&place(&aggregate, &part, 1)),
            "c8aa49a5f8b663c194867bfa0d3e4a800ae40259b1583d2011028a85cc821cbd"
        );
        assert_eq!(
            hex(&place(&part, &aggregate, 256)),
            "bd8966b1fc6d150404f4fbdf9a80f85734dac9766d658ba5a2bcc970d805addc"
        );
        // The big-endian attempt, named so that the vector above is seen to tell it apart.
        assert_ne!(
            hex(&place(&part, &aggregate, 256)),
            "58208cfe10fbac91291e681ac86cd9977912f0b9d5331f69633b64f8a5be694d"
        );
    }

    // The place reads the part, the aggregate and the attempt, each where the set puts it. The wrong
    // implementations refused: one leaving the attempt out (one order for every attempt) and one
    // swapping the part and the aggregate.
    #[test]
    fn the_place_of_a_part_moves_with_its_attempt() {
        let aggregate = [0x33; 32];
        let first = place(&part(1), &aggregate, 0);
        assert_eq!(first, place(&part(1), &aggregate, 0));
        assert_ne!(first, place(&part(1), &aggregate, 1));
        assert_ne!(first, place(&aggregate, &part(1), 0));
        assert_ne!(first, place(&part(2), &aggregate, 0));
    }
}
