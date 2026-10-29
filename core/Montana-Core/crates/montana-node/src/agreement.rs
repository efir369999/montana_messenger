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

use std::cmp::Reverse;
use std::collections::{BTreeMap, BTreeSet};

use mt_state::layout::{Confirmation, Pledge};
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

// The kind a pledge is counted under.
fn kind_of(pledge: &Pledge) -> Kind {
    if pledge.is_closing() {
        Kind::Closing
    } else {
        Kind::Open
    }
}

// The contradiction two pledges of one part make, where the set calls them one: of one kind and
// attempt on two names, the lesser name first, or a closing pledge and an open one it contradicts,
// the closing one first.
fn contradiction(held: &Pledge, later: &Pledge) -> Option<Contradiction> {
    let (first, second) = match (kind_of(held), kind_of(later)) {
        (one, other) if one == other => {
            if held.attempt != later.attempt || held.name == later.name {
                return None;
            }
            if held.name < later.name {
                (held, later)
            } else {
                (later, held)
            }
        }
        (Kind::Closing, Kind::Open) if contradicts(held, later) => (held, later),
        (Kind::Open, Kind::Closing) if contradicts(later, held) => (later, held),
        _ => return None,
    };
    Some(Contradiction {
        first: first.clone(),
        second: second.clone(),
    })
}

// The place of a heavy attestation in the canonical order of its window: the chain of its beacon, the
// round of its beacon and its round nullifier, each ascending, the nullifier as 32 bytes. Consensus,
// "The sanction of a double answer": of the heavy attestations of one part the first in this order
// stands, whichever order they were received or handed in.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, PartialOrd, Ord)]
pub struct Place {
    pub chain: u8,
    pub round: u32,
    pub identifier: [u8; 32],
}

impl Place {
    // The place of `held`, answering the beacon of `chain` and `round`.
    pub fn of(chain: u8, round: u32, held: &Confirmation) -> Self {
        Self {
            chain,
            round,
            identifier: held.round_nullifier,
        }
    }
}

// The canonical order of the pledges of one part, kind and attempt: the name ascending as 32 bytes,
// then `since` descending. `STANDS_ON_NONE` is the greatest `u32`, so of two pledges on one name the
// one standing on none, which counts wherever it stands, comes before one that counts only on the
// quorum it names. Consensus, "The sanction of a double answer".
fn rank((name, since): (Name, u32)) -> (Name, Reverse<u32>) {
    (name, Reverse(since))
}

// What a machine holds of the agreement on one proposal: every part's pledge of each kind and attempt,
// the first of its pledges there by `rank`, the open pledges of attempt zero its heavy attestations
// made, every pledge each part made, and the contradictions met.
#[derive(Default)]
pub struct Book {
    window: u64,
    heavy_first: BTreeMap<Part, (Place, Name)>,
    first: BTreeMap<(Kind, u32), BTreeMap<Part, (Name, u32)>>,
    said: BTreeMap<Part, Vec<Pledge>>,
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
    // it attests beside the beacon of its round. Of several heavy attestations of one part the pledge
    // is that of the first by `place`, the pledged name closing a tie so the order is total; the order
    // they are handed in changes nothing.
    pub fn heavy(&mut self, place: Place, part: Part, name: Name) {
        let at = (place, name);
        let first = self.heavy_first.entry(part).or_insert(at);
        if at < *first {
            *first = at;
        }
        let first_name = first.1;
        self.first
            .entry((Kind::Open, 0))
            .or_default()
            .insert(part, (first_name, STANDS_ON_NONE));
    }

    // The name a part's heavy attestation pledged, of the first of them by `place`: what a light
    // attestation of that part must carry (Canon, "The light attestation": "one carrying another name
    // than its heavy's is refused").
    pub fn heavy_name(&self, part: &Part) -> Option<Name> {
        self.heavy_first.get(part).map(|(_, name)| *name)
    }

    // A pledge whose signature and heavy attestation the caller verified. A part counts once per kind
    // and attempt, under the first of its pledges there by `rank`, the way `heavy` keeps the first by
    // `place`: the order they are handed in changes nothing. Every pair of its pledges the set calls
    // a contradiction is evidence, whichever of the two counts, the lesser name first in a pair of
    // one kind and attempt; a repetition of an attempt, a name and a since adds nothing.
    pub fn pledge(&mut self, pledge: Pledge) {
        if pledge.window != self.window {
            return;
        }
        let kind = kind_of(&pledge);
        let said = self.said.entry(pledge.part_nullifier).or_default();
        let content = |held: &Pledge| (held.attempt, held.name, held.since);
        if said.iter().any(|held| content(held) == content(&pledge)) {
            return;
        }
        for held in said.iter() {
            self.contradictions.extend(contradiction(held, &pledge));
        }
        let stands = (pledge.name, pledge.since);
        let parts = self.first.entry((kind, pledge.attempt)).or_default();
        if parts
            .get(&pledge.part_nullifier)
            .is_none_or(|held| rank(stands) < rank(*held))
        {
            parts.insert(pledge.part_nullifier, stands);
        }
        said.push(pledge);
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
            line_value: [0u8; 32],
            suite_id: 1,
            answering_key: vec![0xA1; mt_codec::size::SIGNING_PUBLIC_KEY],
            proof: vec![0x5A; mt_state::PRESENCE_PROOF_LEN],
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

    // A faulty part heavy-attested two names. Its pledge of attempt zero is the name of the first
    // attestation in the canonical order -- chain, then round, then round nullifier, then the name --
    // whichever order the two are handed in, so two verifiers given one certificate count the part
    // under one name. The wrong implementation refused: one keeping the first handed in.
    #[test]
    fn the_first_heavy_attestation_in_the_canonical_order_stands_whatever_the_order_handed_in() {
        let places = [
            Place {
                chain: 0,
                round: 3,
                identifier: [0xFF; 32],
            },
            Place {
                chain: 0,
                round: 4,
                identifier: [0x00; 32],
            },
            Place {
                chain: 1,
                round: 0,
                identifier: [0x00; 32],
            },
            Place {
                chain: 1,
                round: 0,
                identifier: [0x01; 32],
            },
        ];
        let pledged = |book: &Book| book.first[&(Kind::Open, 0)][&part(1)].0;
        for (low, earlier) in places.iter().enumerate() {
            for later in &places[low + 1..] {
                for (name_earlier, name_later) in [(X, Y), (Y, X)] {
                    let mut ascending = Book::of_the_window(7);
                    ascending.heavy(*earlier, part(1), name_earlier);
                    ascending.heavy(*later, part(1), name_later);
                    let mut descending = Book::of_the_window(7);
                    descending.heavy(*later, part(1), name_later);
                    descending.heavy(*earlier, part(1), name_earlier);
                    assert_eq!(pledged(&ascending), name_earlier);
                    assert_eq!(pledged(&descending), name_earlier);
                }
            }
        }
        // One place, two names: the lesser name stands, so the order is total.
        let mut one = Book::of_the_window(7);
        one.heavy(places[0], part(1), Y);
        one.heavy(places[0], part(1), X);
        let mut other = Book::of_the_window(7);
        other.heavy(places[0], part(1), X);
        other.heavy(places[0], part(1), Y);
        assert_eq!(pledged(&one), X);
        assert_eq!(pledged(&other), X);
    }

    // Every order of `items`.
    fn every_order(items: &[Pledge]) -> Vec<Vec<Pledge>> {
        if items.is_empty() {
            return vec![Vec::new()];
        }
        let mut orders = Vec::new();
        for at in 0..items.len() {
            let mut rest = items.to_vec();
            let item = rest.remove(at);
            for mut order in every_order(&rest) {
                order.insert(0, item.clone());
                orders.push(order);
            }
        }
        orders
    }

    // Four heavies on X; parts 1 and 2 close attempt zero on X, and part 4, faulty, closes it on X
    // and on another name. The part counts under the lesser of its two names whatever the order the
    // four are handed in: with the other name above X its pledge on X stands and X is decided in all
    // 24 orders, with it below X the other stands and nothing is decided in any, and the pair is the
    // same evidence in each. The wrong implementation refused: one keeping the first handed in, which
    // decides X in the order bX, bY, h1, h2 and nothing in bY, bX, h1, h2.
    #[test]
    fn a_part_closing_on_two_names_counts_under_the_lesser_in_every_order() {
        const W: Name = [0x57; 32];
        let votes = BTreeMap::new();
        let electorate = four(&votes);
        for (other, decided) in [(Y, Some((X, 0))), (W, None)] {
            let pledges = [
                pledge(4, 0, X, 0),
                pledge(4, 0, other, 0),
                pledge(1, 0, X, 0),
                pledge(2, 0, X, 0),
            ];
            let orders = every_order(&pledges);
            assert_eq!(orders.len(), 24);
            for order in orders {
                let mut book = Book::of_the_window(7);
                for at in 1..=4 {
                    book.heavy(Place::default(), part(at), X);
                }
                for held in order {
                    book.pledge(held);
                }
                assert_eq!(book.decided(&electorate), decided);
                assert_eq!(book.contradictions.len(), 1);
                let pair = &book.contradictions[0];
                assert_eq!(
                    (pair.first.name, pair.second.name),
                    (X.min(other), X.max(other))
                );
            }
        }
    }

    // Part 4, faulty, opens attempt one on X twice: standing on none, and on attempt zero, where X
    // has no quorum. The pledge standing on none stands in every order, so the part counts and X
    // reaches the quorum of attempt one; two pledges of one name are no contradiction. The wrong
    // implementations refused: one keeping the first handed in, and one ordering `since` ascending,
    // under which the pledge on attempt zero stands and counts nothing.
    #[test]
    fn of_two_open_pledges_on_one_name_the_one_standing_on_none_stands() {
        let votes = BTreeMap::new();
        let electorate = four(&votes);
        let pledges = [
            pledge(4, 1, X, STANDS_ON_NONE),
            pledge(4, 1, X, 0),
            pledge(1, 1, X, STANDS_ON_NONE),
            pledge(2, 1, X, STANDS_ON_NONE),
        ];
        for order in every_order(&pledges) {
            let mut book = Book::of_the_window(7);
            book.heavy(Place::default(), part(1), X);
            book.heavy(Place::default(), part(2), X);
            book.heavy(Place::default(), part(3), Y);
            book.heavy(Place::default(), part(4), Y);
            for held in order {
                book.pledge(held);
            }
            let quorums = book.open_quorums(&electorate);
            assert!(!quorums.contains(&(0, X)));
            assert!(quorums.contains(&(1, X)));
            assert!(book.open_of(1).contains(&(part(4), X, STANDS_ON_NONE)));
            assert!(book.contradictions.is_empty());
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
        book.heavy(Place::default(), part(1), X);
        book.heavy(Place::default(), part(2), X);
        book.heavy(Place::default(), part(3), Y);
        book.heavy(Place::default(), part(4), Y);
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

// The agreement checked by a model checker rather than by examples: two machines holding two books
// of one window, the pledges of every honest part the same wherever both hold them and the one
// faulty part pledging anything in either, never decide two names. WINDOW-THEOREM.md, Theorem 1;
// run by `cargo kani -p montana-node -Z stubbing`. Four parts make the quorum three, so two quorums share an
// honest part, and two attempts reach the third contradicting pair. The bound of a loop is the book
// at its fullest: three pledges of each of four parts stand in `said`, four lists of three under
// four keys, so no loop over what it holds runs more than twelve times and the harness is unwound
// to thirteen; a comparison of 32 bytes is a loop of `memcmp` the command line unwinds to
// thirty-three.
// Theorem 1 by enumeration (the author's decision 176, "both", 25.10.2026): the bound of the Kani
// harness `two_books_of_one_window_never_decide_two_names` walked whole, every case run on the book
// itself. The harness is the proof of record; this is the fact beside it.
//
// The bound is the harness's: four parts, the first three honest and the same in both books, the
// fourth free in each; two attempts; names 1 and 2 (0 is a pledge not made); committee 0. What one
// part puts into a book is a content: its heavy attestation, its closing pledges of attempts 0 and
// 1 and its open pledge of attempt 1 (attempt 0 has none but the heavy one), each present or not:
// 3 x 3 x 3 x 5 = 135 contents. A script of the harness is the content holding all it says, and a
// book takes of it exactly the contents below it, item by item, as the harness's `kani::any()`
// choices do. So the walk is: the decision of every book of four contents (135^4), folded over the
// free fourth part, then over the contents below each honest script; two names under one triple of
// honest scripts would be a counterexample. Run: cargo test --release -p montana-node every_book --
// --ignored --nocapture.
//
// `part`, `pledge` and `honest` are the harness's own (agreement.rs, mod proofs), copied while its
// verdicts run on that blob; one module for both comes after them (stage 6 of issue #4).
#[cfg(test)]
mod every_book {
    use super::*;

    const WINDOW: u64 = 7;
    const PARTS: usize = 4;
    const FAULTY: usize = 3;
    const ATTEMPTS: u32 = 2;
    const CONTENTS: usize = 3 * 3 * 3 * 5;

    #[derive(Clone, Copy, PartialEq, Eq)]
    struct Content {
        heavy: u8,
        closing: [u8; ATTEMPTS as usize],
        // 0: none; else 1 + 2 (name - 1) + s, where s = 0 stands on none and s = 1 on attempt 0.
        open: u8,
    }

    fn content(i: usize) -> Content {
        Content {
            heavy: (i % 3) as u8,
            closing: [(i / 3 % 3) as u8, (i / 9 % 3) as u8],
            open: (i / 27) as u8,
        }
    }

    fn open_said(open: u8) -> Option<(u8, u32)> {
        let k = open.checked_sub(1)?;
        Some((k / 2 + 1, if k % 2 == 0 { STANDS_ON_NONE } else { 0 }))
    }

    // The contents a book may take of `script`: each item either absent or the script's own.
    fn below(c: Content, script: Content) -> bool {
        let item = |a: u8, b: u8| a == 0 || a == b;
        item(c.heavy, script.heavy)
            && item(c.closing[0], script.closing[0])
            && item(c.closing[1], script.closing[1])
            && item(c.open, script.open)
    }

    fn part(at: usize) -> Part {
        [at as u8 + 1; 32]
    }

    fn pledge(at: usize, attempt: u32, name: u8, since: u32) -> Pledge {
        Pledge {
            window: WINDOW,
            attempt,
            name: [name; 32],
            since,
            part_nullifier: part(at),
            line_value: [0u8; 32],
            suite_id: 0,
            answering_key: Vec::new(),
            proof: Vec::new(),
            signature: Vec::new(),
        }
    }

    // The honest predicate of the harness, on a script.
    fn honest(at: usize, script: Content) -> bool {
        let open = [None, open_said(script.open)];
        (0..ATTEMPTS).all(|closed| {
            let name = script.closing[closed as usize];
            (0..ATTEMPTS).all(|later| match open[later as usize] {
                None => true,
                Some(_) if name == 0 => true,
                Some((open_name, since)) => !contradicts(
                    &pledge(at, closed, name, closed),
                    &pledge(at, later, open_name, since),
                ),
            })
        })
    }

    // A part's content into the book, in the harness's order: heavy, then per attempt closing and open.
    fn put(book: &mut Book, at: usize, c: Content) {
        if c.heavy != 0 {
            book.heavy(Place::default(), part(at), [c.heavy; 32]);
        }
        for attempt in 0..ATTEMPTS {
            let closing = c.closing[attempt as usize];
            if closing != 0 {
                book.pledge(pledge(at, attempt, closing, attempt));
            }
            if attempt == 1 {
                if let Some((name, since)) = open_said(c.open) {
                    book.pledge(pledge(at, attempt, name, since));
                }
            }
        }
    }

    // The decision of one book as a bit: 1 for name 1, 2 for name 2, 0 for none.
    fn decision(contents: [usize; PARTS], electorate: &Electorate<'_>) -> u8 {
        let mut book = Book::of_the_window(WINDOW);
        for (at, &c) in contents.iter().enumerate() {
            put(&mut book, at, content(c));
        }
        match book.decided(electorate) {
            None => 0,
            Some((name, _)) => {
                assert!(
                    name == [name[0]; 32] && (1..=2).contains(&name[0]),
                    "a name no part pledged"
                );
                1 << (name[0] - 1)
            }
        }
    }

    #[test]
    #[ignore = "the whole bound of Theorem 1: minutes in release; run with --ignored"]
    fn every_book_of_the_bound_decides_at_most_one_name() {
        let index = |a: usize, b: usize, c: usize| (a * CONTENTS + b) * CONTENTS + c;
        // The free part folded away: the names any fourth content lets the first three decide.
        let threads = std::thread::available_parallelism().map_or(1, |n| n.get());
        let mut free = vec![0u8; CONTENTS * CONTENTS * CONTENTS];
        let mut deciding = 0u64;
        std::thread::scope(|s| {
            let rows: Vec<_> = (0..threads)
                .map(|t| {
                    s.spawn(move || {
                        let votes = BTreeMap::new();
                        let electorate = Electorate {
                            count: PARTS as u64,
                            committee: 0,
                            votes: &votes,
                        };
                        let mut out = Vec::new();
                        let mut count = 0u64;
                        for a in (t..CONTENTS).step_by(threads) {
                            for b in 0..CONTENTS {
                                for c in 0..CONTENTS {
                                    let mut bits = 0;
                                    for d in 0..CONTENTS {
                                        let bit = decision([a, b, c, d], &electorate);
                                        count += u64::from(bit != 0);
                                        bits |= bit;
                                    }
                                    out.push((index(a, b, c), bits));
                                }
                            }
                        }
                        (out, count)
                    })
                })
                .collect();
            for row in rows {
                let (out, count) = row.join().expect("a walker failed");
                deciding += count;
                for (i, bits) in out {
                    free[i] = bits;
                }
            }
        });
        // Then each honest part: from contents to the scripts above them.
        let scripts: Vec<Content> = (0..CONTENTS).map(content).collect();
        let fold = |table: &[u8], axis: usize| -> Vec<u8> {
            let mut out = vec![0u8; table.len()];
            for (i, slot) in out.iter_mut().enumerate() {
                let mut at = [
                    i / (CONTENTS * CONTENTS),
                    i / CONTENTS % CONTENTS,
                    i % CONTENTS,
                ];
                let script = scripts[at[axis]];
                for (c, &taken) in scripts.iter().enumerate() {
                    if below(taken, script) {
                        at[axis] = c;
                        *slot |= table[index(at[0], at[1], at[2])];
                    }
                }
            }
            out
        };
        let held = fold(&fold(&fold(&free, 2), 1), 0);
        let honest_of: Vec<Vec<usize>> = (0..FAULTY)
            .map(|at| (0..CONTENTS).filter(|&s| honest(at, scripts[s])).collect())
            .collect();
        let mut triples = 0u64;
        let mut decided_under_honest = 0u64;
        for &x in &honest_of[0] {
            for &y in &honest_of[1] {
                for &z in &honest_of[2] {
                    let bits = held[index(x, y, z)];
                    triples += 1;
                    decided_under_honest += u64::from(bits != 0);
                    assert!(
                        bits != 3,
                        "two names decided under honest scripts {x}, {y}, {z}"
                    );
                }
            }
        }
        // Not vacuous: books decide under honest scripts (the harness's cover), and without the honest
        // predicate the same walk does find two names, so the predicate is what the theorem rests on.
        let dishonest_split = held.iter().filter(|&&bits| bits == 3).count();
        println!(
            "books {}, deciding {deciding}; honest scripts {} {} {}; honest triples {triples}, \
             deciding under them {decided_under_honest}; triples of any scripts deciding both names {dishonest_split}",
            CONTENTS.pow(4),
            honest_of[0].len(),
            honest_of[1].len(),
            honest_of[2].len(),
        );
        assert!(
            decided_under_honest != 0,
            "no book decides: the walk proves nothing"
        );
        assert!(
            dishonest_split != 0,
            "two names never arise even without honesty: the walk is too weak"
        );
    }
}

#[cfg(kani)]
mod proofs {
    use super::*;

    const WINDOW: u64 = 7;
    const PARTS: usize = 4;
    const FAULTY: usize = 3;
    const ATTEMPTS: u32 = 2;

    #[derive(Clone, Copy)]
    struct Said {
        name: u8,
        since: u32,
    }

    // What one part says in one window: its heavy attestation's name and, per attempt, its closing
    // pledge and its open one. A name of nought is a pledge not made.
    #[derive(Clone, Copy)]
    struct Script {
        heavy: u8,
        closing: [u8; ATTEMPTS as usize],
        open: [Said; ATTEMPTS as usize],
    }

    fn any_name() -> u8 {
        let name: u8 = kani::any();
        kani::assume(name <= 2);
        name
    }

    fn any_script() -> Script {
        let mut open = [Said {
            name: 0,
            since: STANDS_ON_NONE,
        }; ATTEMPTS as usize];
        // Attempt zero has no open pledge but the heavy attestation (layout.rs, since_of_a_pledge).
        for (attempt, said) in open.iter_mut().enumerate().skip(1) {
            let since: u32 = kani::any();
            kani::assume(since == STANDS_ON_NONE || (since as usize) < attempt);
            *said = Said {
                name: any_name(),
                since,
            };
        }
        Script {
            heavy: any_name(),
            closing: [any_name(), any_name()],
            open,
        }
    }

    fn part(at: usize) -> Part {
        [at as u8 + 1; 32]
    }

    fn pledge(at: usize, attempt: u32, name: u8, since: u32) -> Pledge {
        Pledge {
            window: WINDOW,
            attempt,
            name: [name; 32],
            since,
            part_nullifier: part(at),
            line_value: [0u8; 32],
            suite_id: 0,
            answering_key: Vec::new(),
            proof: Vec::new(),
            signature: Vec::new(),
        }
    }

    // The honest predicate of Theorem 1: none of the three contradicting pairs. One pledge per kind
    // and attempt rules out the first two by construction; the third is the agreement's own rule.
    fn honest(at: usize, script: &Script) -> bool {
        (0..ATTEMPTS).all(|closed| {
            let name = script.closing[closed as usize];
            (0..ATTEMPTS).all(|later| {
                let open = script.open[later as usize];
                name == 0
                    || open.name == 0
                    || !contradicts(
                        &pledge(at, closed, name, closed),
                        &pledge(at, later, open.name, open.since),
                    )
            })
        })
    }

    // A book holding any part of each script: what reached one machine of the window.
    fn book_of(scripts: &[Script; PARTS]) -> Book {
        let mut book = Book::of_the_window(WINDOW);
        for (at, script) in scripts.iter().enumerate() {
            if script.heavy != 0 && kani::any() {
                book.heavy(Place::default(), part(at), [script.heavy; 32]);
            }
            for attempt in 0..ATTEMPTS {
                let closing = script.closing[attempt as usize];
                if closing != 0 && kani::any() {
                    book.pledge(pledge(at, attempt, closing, attempt));
                }
                let open = script.open[attempt as usize];
                if open.name != 0 && kani::any() {
                    book.pledge(pledge(at, attempt, open.name, open.since));
                }
            }
        }
        book
    }

    #[kani::proof]
    #[kani::unwind(13)]
    #[kani::stub(mt_genesis::ratio, crate::kani_decree::ratio)]
    #[kani::stub(mt_genesis::scalar, crate::kani_decree::scalar)]
    fn two_books_of_one_window_never_decide_two_names() {
        let mut first = [any_script(), any_script(), any_script(), any_script()];
        for (at, script) in first.iter().enumerate().take(FAULTY) {
            kani::assume(honest(at, script));
        }
        let mut second = first;
        second[FAULTY] = any_script();
        first[FAULTY] = any_script();
        let votes = BTreeMap::new();
        let electorate = Electorate {
            count: PARTS as u64,
            committee: 0,
            votes: &votes,
        };
        let one = book_of(&first).decided(&electorate);
        let other = book_of(&second).decided(&electorate);
        // Without it the assertion below could stand only because no two books ever decide.
        kani::cover!(one.is_some() && other.is_some(), "both books decide");
        if let (Some((one, _)), Some((other, _))) = (one, other) {
            assert_eq!(one, other);
        }
    }
}
