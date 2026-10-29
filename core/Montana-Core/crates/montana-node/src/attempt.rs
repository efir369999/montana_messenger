// The conduct of a machine in the agreement on what a window decided, and the record it keeps of
// it. Consensus, "How a machine pledges": in attempt zero its heavy attestation pledges the name it
// took; then, in every attempt, it closes on what it sees, waits on a spoken quorum, proposes in the
// order of its place, follows the lowest place and moves on. Every wait here is a count of the
// machine's own askings — a span that doubles from attempt to attempt — and enters no rule of
// acceptance: a machine that waited twice as long reaches the same decisions later.
//
// **The conduct reads and writes nothing of the world.** It is handed the book of pledges, the
// record of what this machine already did, and the count of its askings, and it answers with what
// to do now: close on a name, open on a name, replay a roll before following it, or enter a later
// attempt. The pulse signs, keeps and publishes; so every rule of this file holds in a test with no
// wire, and the pulse holds only the order.
//
// **What a machine holds of the agreement** — its attempt, its lock, its valid name and every
// pledge it made — is one record per open window, written before anything it governs is published
// and through a restart, and let go when the window closes (Consensus, "What a machine holds of the
// agreement"; AGREEMENT.md, section 6). It takes the place of the signing lock the store once kept
// for each window and never removed: a machine that forgot a pledge could sign its contradiction,
// and one that read its lock off the points could not tell a pledge never made from a pledge
// whose holders are out of reach.

use crate::agreement::{Book, Electorate, Kind, Name, Part};
use crate::collections::BTreeMap;
use crate::NodeError;
use mt_state::layout::Pledge;
use mt_state::{Layout, STANDS_ON_NONE};

pub use mt_pulse::SPAN_OF_ATTEMPT_ZERO;

// The record of a machine's agreement on the proposal of the window before `window`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Record {
    pub window: u64,
    // The name this machine took of the proposal of the window before: what its heavy attestation
    // pledges in attempt zero, and what it opens on where it holds no valid name.
    pub taken: Name,
    pub attempt: u32,
    // The name and the attempt of its last closing pledge, or none.
    pub lock: Option<(Name, u32)>,
    // The name and the attempt of the newest quorum of open pledges it holds, or none.
    pub valid: Option<(Name, u32)>,
    // Every pledge it made in this window, in the order it made them.
    pub made: Vec<Pledge>,
}

// The width of the fixed part of a record: the window, the name taken, the attempt, two optional
// pairs of a name and an attempt each behind one byte, and the count of pledges — at the widths of
// their types, so no number stands here that the types do not already fix.
const HEAD: usize = size_of::<u64>()
    + size_of::<Name>()
    + size_of::<u32>()
    + (size_of::<u8>() + size_of::<Name>() + size_of::<u32>()) * 2
    + size_of::<u32>();

impl Record {
    // The record a machine opens a window with: attempt zero, no lock, no valid name, nothing made.
    pub fn opened(window: u64, taken: Name) -> Self {
        Self {
            window,
            taken,
            attempt: 0,
            lock: None,
            valid: None,
            made: Vec::new(),
        }
    }

    // The pledge this machine already made of one kind in one attempt, if any: a part pledges once
    // per kind and attempt, and a machine that restarted republishes rather than signs again.
    pub fn made_in(&self, kind: Kind, attempt: u32) -> Option<&Pledge> {
        self.made.iter().find(|held| {
            held.attempt == attempt
                && match kind {
                    Kind::Closing => held.is_closing(),
                    Kind::Open => !held.is_closing(),
                }
        })
    }

    // The bytes a store keeps: every count of fixed width and every value whole. A local format of
    // this tree and no object of the protocol, like the standing a machine keeps of itself.
    pub fn encode(&self) -> Vec<u8> {
        let mut out = Vec::with_capacity(HEAD + self.made.len() * Pledge::expected_len());
        out.extend_from_slice(&self.window.to_le_bytes());
        out.extend_from_slice(&self.taken);
        out.extend_from_slice(&self.attempt.to_le_bytes());
        for held in [self.lock, self.valid] {
            match held {
                Some((name, attempt)) => {
                    out.push(1);
                    out.extend_from_slice(&name);
                    out.extend_from_slice(&attempt.to_le_bytes());
                }
                None => {
                    out.push(0);
                    out.extend_from_slice(&[0u8; 32]);
                    out.extend_from_slice(&[0u8; 4]);
                }
            }
        }
        out.extend_from_slice(&(self.made.len() as u32).to_le_bytes());
        for pledge in &self.made {
            out.extend_from_slice(&pledge.encode());
        }
        out
    }

    // Read back whole or refused: a record of another shape is not this machine's.
    pub fn decode(bytes: &[u8]) -> Result<Self, NodeError> {
        let short = || NodeError::Refused {
            what: "an agreement record shorter than what it declares",
        };
        let mut at = 0usize;
        let mut take = |n: usize| -> Result<&[u8], NodeError> {
            let end = at.checked_add(n).ok_or_else(short)?;
            let held = bytes.get(at..end).ok_or_else(short)?;
            at = end;
            Ok(held)
        };
        let four = |b: &[u8]| u32::from_le_bytes([b[0], b[1], b[2], b[3]]);
        let eight = |b: &[u8]| {
            let mut w = [0u8; 8];
            w.copy_from_slice(b);
            u64::from_le_bytes(w)
        };
        let name = |b: &[u8]| {
            let mut n = [0u8; 32];
            n.copy_from_slice(b);
            n
        };
        let window = eight(take(8)?);
        let taken = name(take(32)?);
        let attempt = four(take(4)?);
        let mut pairs = [None, None];
        for pair in pairs.iter_mut() {
            let flag = take(1)?[0];
            let held = name(take(32)?);
            let at = four(take(4)?);
            *pair = match flag {
                0 => None,
                1 => Some((held, at)),
                _ => {
                    return Err(NodeError::Refused {
                        what: "an agreement record whose flag is neither none nor one",
                    })
                }
            };
        }
        let count = four(take(4)?) as usize;
        let width = Pledge::expected_len();
        let mut made = Vec::with_capacity(count.min(1 << 16));
        for _ in 0..count {
            made.push(Pledge::parse(take(width)?).map_err(NodeError::Object)?);
        }
        if at != bytes.len() {
            return Err(NodeError::Refused {
                what: "an agreement record longer than what it declares",
            });
        }
        Ok(Self {
            window,
            taken,
            attempt,
            lock: pairs[0],
            valid: pairs[1],
            made,
        })
    }
}

// What the conduct asks the pulse to do now. The pulse signs and keeps before it publishes, and
// enters an attempt by writing the record first.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Action {
    // Publish the closing pledge of the current attempt on `name`, and take it as the lock.
    Close(Name),
    // Publish an open pledge of the current attempt on `name`, standing on `since` or on none.
    Open(Name, u32),
    // Replay the roll of `name` before it can be followed: the name is neither the one this machine
    // took nor backed by a quorum, and a name is valid to a machine only one of three ways.
    Replay(Name),
    // Enter the attempt named.
    Enter(u32),
}

// What the conduct has learnt of a name it was asked to replay: valid, or not that proposal's.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Replayed {
    Valid,
    Invalid,
}

// The span of an attempt: the span of attempt zero doubled once per attempt, in a machine's own
// askings. It saturates rather than wraps, since a wait past what a count carries is a wait past
// what any machine lives.
pub fn span_of(attempt: u32) -> u32 {
    if attempt >= u32::BITS {
        return u32::MAX;
    }
    u32::try_from(u64::from(SPAN_OF_ATTEMPT_ZERO) << attempt).unwrap_or(u32::MAX)
}

// The share of a span a part's place stands at, read off the leading bytes of the place as the
// share of the ticket order is read off a ticket: a place at the bottom of the width waits nothing
// of it, one at the top waits almost all of it.
pub fn share_of(span: u32, place: &[u8; 32]) -> u32 {
    let lead = u64::from(u16::from_be_bytes([place[0], place[1]]));
    u32::try_from((u64::from(span) * lead) >> u16::BITS).unwrap_or(span)
}

// The timing a machine holds of its current attempt, which is conduct and is not kept: the asking
// it entered the attempt at, and the askings it first held a spoken quorum without a name and its
// own closing pledge without a decision at.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Conduct {
    entered_at: u32,
    spoken_at: Option<u32>,
    closed_at: Option<u32>,
}

// What the conduct reads of the world at one asking.
pub struct Seen<'a> {
    pub book: &'a Book,
    pub electorate: &'a Electorate<'a>,
    pub record: &'a Record,
    pub part: &'a Part,
    pub aggregate: &'a [u8; 32],
    pub replayed: &'a BTreeMap<Name, Replayed>,
}

impl Conduct {
    // A machine entering an attempt at this asking: the spans of the attempt count from here.
    pub fn entering(&mut self, now: u32) {
        self.entered_at = now;
        self.spoken_at = None;
        self.closed_at = None;
    }

    // The steps of "How a machine pledges", at one asking. At most one pledge is asked for per
    // asking, so the record the pulse writes between two askings is what the next one reads.
    pub fn tick(&mut self, now: u32, seen: &Seen<'_>) -> Vec<Action> {
        let Seen {
            book,
            electorate,
            record,
            part,
            aggregate,
            replayed,
        } = *seen;
        let mut out = Vec::new();
        if book.decided(electorate).is_some() {
            return out;
        }
        let attempt = record.attempt;
        let span = span_of(attempt);
        let since_entry = now.saturating_sub(self.entered_at);
        let open_quorum = book.open_quorum_of(attempt, electorate);

        // 1. It closes on what it sees: the open pledges of the attempt at the quorum on a name,
        // once.
        let closed = record.made_in(Kind::Closing, attempt).is_some();
        if !closed {
            if let Some(name) = open_quorum {
                self.closed_at.get_or_insert(now);
                out.push(Action::Close(name));
                return out;
            }
        } else {
            self.closed_at.get_or_insert(now);
        }

        // 5, first half, read before any pledge: pledges of a later attempt from more than the faulty
        // can fill draw a machine into that attempt before it says anything in its own. A machine
        // behind its cohort holds the quorum the others reached there, and its valid name stands on
        // that later attempt; pledged in its own attempt it would stand on an attempt after itself,
        // which no pledge does (Consensus, "How a machine pledges", 3: an open pledge stands on an
        // earlier attempt or on none; mt-state `since_of_a_pledge` refuses it as `Since`).
        if let Some(later) = book.drawn_into(attempt, electorate) {
            out.push(Action::Enter(later));
            return out;
        }

        // Pledging, from attempt one on and once per attempt: attempt zero is pledged by the heavy
        // attestation, a part pledges one open pledge per attempt, and a machine that closed in this
        // attempt waits on the decision rather than opens beside its closing pledge. Following is
        // read before proposing where both are due at one asking: a machine due to follow holds a
        // pledge at a lower place than its own, and following it is what gathers the quorum.
        if attempt > 0 && !closed && record.made_in(Kind::Open, attempt).is_none() {
            // 4. It follows the lowest place, two spans after it entered: the same name on the same
            // `since`, where it holds the quorum that `since` names or the `since` is none, where the
            // name is valid to it, and where its lock admits it. Otherwise it pledges nothing.
            if since_entry >= span.saturating_mul(2) {
                if let Some((_, name, since)) = book.lowest_place_open(attempt, aggregate) {
                    let backed = since == STANDS_ON_NONE
                        || book.open_quorums(electorate).contains(&(since, name));
                    let admitted = match record.lock {
                        None => true,
                        Some((locked, at)) => {
                            locked == name || (since != STANDS_ON_NONE && since >= at)
                        }
                    };
                    if backed && admitted {
                        let valid = name == record.taken || book.backs(&name, electorate);
                        match (valid, replayed.get(&name)) {
                            (true, _) | (false, Some(Replayed::Valid)) => {
                                out.push(Action::Open(name, since));
                                return out;
                            }
                            // A roll not yet validated is asked for, and the asking stops nothing
                            // below: a machine waiting on a roll that never comes still moves on.
                            (false, None) => out.push(Action::Replay(name)),
                            (false, Some(Replayed::Invalid)) => {}
                        }
                    }
                }
            }
            // 3. It proposes in the order of its place: one span of listening, then the share of a
            // further span its place stands at, unless an open pledge from a lower place stands by
            // then — or a roll it is replaying to follow.
            let mine = crate::agreement::place(part, aggregate, attempt);
            if out.is_empty()
                && since_entry >= span.saturating_add(share_of(span, &mine))
                && !book.holds_open_below(attempt, &mine, aggregate)
            {
                out.push(match record.valid {
                    Some((name, at)) => Action::Open(name, at),
                    None => Action::Open(record.taken, STANDS_ON_NONE),
                });
                return out;
            }
        }

        // 2. It waits on a spoken quorum: open pledges of the attempt from distinct parts at the
        // quorum share and no name among them at the quorum, or its own closing pledge and no
        // decision — one span, then the attempt after.
        if open_quorum.is_none() && book.spoken(attempt, electorate) {
            self.spoken_at.get_or_insert(now);
        }
        if let Some(at) = [self.spoken_at, self.closed_at].into_iter().flatten().min() {
            if now.saturating_sub(at) >= span {
                out.push(Action::Enter(attempt.saturating_add(1)));
                return out;
            }
        }

        // 5. It moves on: four spans after it entered without a decision (drawn forward by a later
        // attempt is read above, before any pledge).
        if since_entry >= span.saturating_mul(4) {
            out.push(Action::Enter(attempt.saturating_add(1)));
            return out;
        }
        out
    }
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

    #[allow(clippy::too_many_arguments)]
    fn tick(
        conduct: &mut Conduct,
        now: u32,
        book: &Book,
        electorate: &Electorate<'_>,
        record: &Record,
        me: &Part,
        aggregate: &[u8; 32],
        replayed: &BTreeMap<Name, Replayed>,
    ) -> Vec<Action> {
        conduct.tick(
            now,
            &Seen {
                book,
                electorate,
                record,
                part: me,
                aggregate,
                replayed,
            },
        )
    }

    // A record read back is the record written, and one shorter or longer than it declares is
    // refused whole. The wrong implementation refused: one reading a clipped record as a record
    // with fewer pledges — it would have forgotten a pledge and signed its contradiction.
    #[test]
    fn a_record_reads_back_whole_or_is_refused() {
        let mut record = Record::opened(7, X);
        record.attempt = 3;
        record.lock = Some((Y, 2));
        record.valid = Some((X, 3));
        record.made.push(pledge(1, 1, X, STANDS_ON_NONE));
        record.made.push(pledge(1, 2, Y, 2));
        let bytes = record.encode();
        assert_eq!(Record::decode(&bytes).expect("reads back"), record);
        assert_eq!(record.made_in(Kind::Closing, 2), Some(&record.made[1]));
        assert_eq!(record.made_in(Kind::Open, 2), None);
        assert_eq!(record.made_in(Kind::Open, 1), Some(&record.made[0]));
        let mut clipped = bytes.clone();
        clipped.truncate(bytes.len() - 1);
        assert!(Record::decode(&clipped).is_err());
        let mut over = bytes.clone();
        over.push(0);
        assert!(Record::decode(&over).is_err());
        let mut flagged = bytes.clone();
        flagged[8 + 32 + 4] = 2;
        assert!(Record::decode(&flagged).is_err());
        let empty = Record::opened(9, Y);
        assert_eq!(Record::decode(&empty.encode()).expect("reads back"), empty);
    }

    // The span doubles from attempt to attempt and saturates rather than wraps; the share of a
    // place is read off its leading bytes. The wrong implementations refused: one with one span for
    // every attempt, and one whose share overflows at the top of the width.
    #[test]
    fn the_span_doubles_and_the_share_reads_the_place() {
        assert_eq!(span_of(0), SPAN_OF_ATTEMPT_ZERO);
        assert_eq!(span_of(1), SPAN_OF_ATTEMPT_ZERO * 2);
        assert_eq!(span_of(3), SPAN_OF_ATTEMPT_ZERO * 8);
        assert_eq!(span_of(31), u32::MAX);
        assert_eq!(span_of(u32::MAX), u32::MAX);
        assert_eq!(share_of(1_000, &[0x00; 32]), 0);
        assert_eq!(share_of(1_000, &[0x80; 32]), 501);
        assert_eq!(share_of(u32::MAX, &[0xFF; 32]), u32::MAX - 65_536);
    }

    // The steps of attempt zero under a split of two and two: a spoken quorum without a name enters
    // attempt one after one span, and not before. The wrong implementations refused: one entering
    // at once, and one never entering (the window stands forever, as on the six hosts).
    #[test]
    fn a_spoken_quorum_without_a_name_enters_the_next_attempt_after_one_span() {
        let votes = BTreeMap::new();
        let electorate = four(&votes);
        let mut book = Book::of_the_window(7);
        book.heavy(crate::agreement::Place::default(), part(1), X);
        book.heavy(crate::agreement::Place::default(), part(2), X);
        let record = Record::opened(7, X);
        let replayed = BTreeMap::new();
        let aggregate = [0x33; 32];
        let me = part(1);
        let mut conduct = Conduct::default();
        conduct.entering(0);
        let at = |conduct: &mut Conduct, now: u32, book: &Book| {
            tick(
                conduct,
                now,
                book,
                &electorate,
                &record,
                &me,
                &aggregate,
                &replayed,
            )
        };
        assert!(at(&mut conduct, 1, &book).is_empty());
        book.heavy(crate::agreement::Place::default(), part(3), Y);
        book.heavy(crate::agreement::Place::default(), part(4), Y);
        let spoke = 5;
        assert!(at(&mut conduct, spoke, &book).is_empty());
        assert!(at(&mut conduct, spoke + span_of(0) - 1, &book).is_empty());
        assert_eq!(
            at(&mut conduct, spoke + span_of(0), &book),
            vec![Action::Enter(1)]
        );
    }

    // In attempt one a proposer listens one span, waits the share of its place, and publishes its
    // own open pledge on the name it took — unless an open pledge from a lower place stands by
    // then. The wrong implementations refused: one proposing before its share, and one proposing
    // beside a lower place.
    #[test]
    fn a_proposer_waits_its_share_and_yields_to_a_lower_place() {
        let votes = BTreeMap::new();
        let electorate = four(&votes);
        let aggregate = [0x33; 32];
        let mut book = Book::of_the_window(7);
        book.heavy(crate::agreement::Place::default(), part(1), X);
        book.heavy(crate::agreement::Place::default(), part(2), X);
        book.heavy(crate::agreement::Place::default(), part(3), Y);
        book.heavy(crate::agreement::Place::default(), part(4), Y);
        let parts: Vec<Part> = (1..=4).map(part).collect();
        let mut by_place = parts.clone();
        by_place.sort_by_key(|part| crate::agreement::place(part, &aggregate, 1));
        let (lowest, highest) = (by_place[0], by_place[3]);
        let replayed = BTreeMap::new();
        let mut record = Record::opened(7, X);
        record.attempt = 1;
        let span = span_of(1);
        let share = share_of(span, &crate::agreement::place(&lowest, &aggregate, 1));
        let mut conduct = Conduct::default();
        conduct.entering(0);
        let at = |conduct: &mut Conduct, now: u32, book: &Book, me: &Part| {
            tick(
                conduct,
                now,
                book,
                &electorate,
                &record,
                me,
                &aggregate,
                &replayed,
            )
        };
        assert!(at(&mut conduct, span, &book, &lowest).is_empty());
        assert!(at(&mut conduct, span + share - 1, &book, &lowest).is_empty());
        assert_eq!(
            at(&mut conduct, span + share, &book, &lowest),
            vec![Action::Open(X, STANDS_ON_NONE)]
        );
        // The highest place, holding the lowest's open pledge of attempt one, proposes nothing.
        book.pledge(Pledge {
            part_nullifier: lowest,
            ..pledge(0, 1, Y, STANDS_ON_NONE)
        });
        let share = share_of(span, &crate::agreement::place(&highest, &aggregate, 1));
        let mut conduct = Conduct::default();
        conduct.entering(0);
        assert!(at(&mut conduct, span + share, &book, &highest).is_empty());
    }

    // Two spans after entering, a follower takes the open pledge at the lowest place: the same name
    // on the same `since`, where its lock admits it and the name is valid to it; a name it cannot
    // validate is replayed first, and one its lock refuses is not followed. The wrong implementations
    // refused: one following before two spans, one following against its lock, and one following a
    // name it never validated.
    #[test]
    fn a_follower_takes_the_lowest_place_only_where_its_lock_admits() {
        let votes = BTreeMap::new();
        let electorate = four(&votes);
        let aggregate = [0x33; 32];
        let mut book = Book::of_the_window(7);
        for at in 1..=4 {
            book.heavy(
                crate::agreement::Place::default(),
                part(at),
                if at <= 2 { X } else { Y },
            );
        }
        let parts: Vec<Part> = (1..=4).map(part).collect();
        let lowest = parts
            .iter()
            .min_by_key(|part| crate::agreement::place(part, &aggregate, 1))
            .copied()
            .expect("four parts");
        let me = parts
            .iter()
            .max_by_key(|part| crate::agreement::place(part, &aggregate, 1))
            .copied()
            .expect("four parts");
        book.pledge(Pledge {
            part_nullifier: lowest,
            ..pledge(0, 1, Y, STANDS_ON_NONE)
        });
        let mut record = Record::opened(7, X);
        record.attempt = 1;
        let mut replayed = BTreeMap::new();
        let span = span_of(1);
        let tick_at = |conduct: &mut Conduct, now, record: &Record, replayed: &BTreeMap<_, _>| {
            tick(
                conduct,
                now,
                &book,
                &electorate,
                record,
                &me,
                &aggregate,
                replayed,
            )
        };
        let mut conduct = Conduct::default();
        conduct.entering(0);
        // Before two spans: nothing, whatever stands.
        assert!(tick_at(&mut conduct, 2 * span - 1, &record, &replayed).is_empty());
        // Y is neither the name taken nor backed: a replay is asked for, then followed.
        assert_eq!(
            tick_at(&mut conduct, 2 * span, &record, &replayed),
            vec![Action::Replay(Y)]
        );
        replayed.insert(Y, Replayed::Invalid);
        assert!(tick_at(&mut conduct, 2 * span, &record, &replayed).is_empty());
        replayed.insert(Y, Replayed::Valid);
        assert_eq!(
            tick_at(&mut conduct, 2 * span, &record, &replayed),
            vec![Action::Open(Y, STANDS_ON_NONE)]
        );
        // A lock on X from attempt zero refuses an open pledge on Y standing on none.
        record.lock = Some((X, 0));
        assert!(tick_at(&mut conduct, 2 * span, &record, &replayed).is_empty());
        // The lock admits the same name, and a `since` at or after the lock's attempt.
        record.lock = Some((Y, 0));
        assert_eq!(
            tick_at(&mut conduct, 2 * span, &record, &replayed),
            vec![Action::Open(Y, STANDS_ON_NONE)]
        );
        // Having pledged in this attempt, it pledges nothing more in it.
        record.made.push(Pledge {
            part_nullifier: me,
            ..pledge(0, 1, Y, STANDS_ON_NONE)
        });
        assert!(tick_at(&mut conduct, 2 * span, &record, &replayed).is_empty());
    }

    // A closing pledge is made once, on the open quorum of its own attempt, and the lock it sets is
    // the pulse's to write; four spans without a decision move on, and pledges of a later attempt
    // from more than the faulty can fill draw a machine forward. The wrong implementations refused:
    // one closing on a beacon's count rather than a quorum of open pledges on one name, one closing
    // twice in one attempt, one that never moves on, and one drawn forward by a single part.
    #[test]
    fn a_closing_pledge_is_made_once_and_a_machine_moves_on() {
        let votes = BTreeMap::new();
        let electorate = four(&votes);
        let aggregate = [0x33; 32];
        let replayed = BTreeMap::new();
        let mut book = Book::of_the_window(7);
        let mut record = Record::opened(7, X);
        record.attempt = 1;
        let me = part(1);
        let at = |conduct: &mut Conduct, now: u32, book: &Book, record: &Record| {
            tick(
                conduct,
                now,
                book,
                &electorate,
                record,
                &me,
                &aggregate,
                &replayed,
            )
        };
        let span = span_of(1);
        let mut conduct = Conduct::default();
        conduct.entering(0);
        // Four distinct parts on two names: a count at the quorum, no name at it — no closing.
        for part in 1..=4 {
            book.pledge(pledge(
                part,
                1,
                if part <= 2 { X } else { Y },
                STANDS_ON_NONE,
            ));
        }
        assert!(at(&mut conduct, 1, &book, &record).is_empty());
        // Three on one name: the closing pledge, once.
        let mut book = Book::of_the_window(7);
        for part in 1..=3 {
            book.pledge(pledge(part, 1, X, STANDS_ON_NONE));
        }
        let mut conduct = Conduct::default();
        conduct.entering(0);
        assert_eq!(at(&mut conduct, 1, &book, &record), vec![Action::Close(X)]);
        record.made.push(pledge(1, 1, X, 1));
        record.lock = Some((X, 1));
        assert!(at(&mut conduct, 2, &book, &record).is_empty());
        // One span after its own closing pledge without a decision: the attempt after.
        assert_eq!(
            at(&mut conduct, 1 + span, &book, &record),
            vec![Action::Enter(2)]
        );
        // Four spans after entering without a decision, whatever stands: the attempt after.
        let book = Book::of_the_window(7);
        let record = Record::opened(7, X);
        let mut conduct = Conduct::default();
        conduct.entering(10);
        assert!(at(&mut conduct, 10 + 4 * span_of(0) - 1, &book, &record).is_empty());
        assert_eq!(
            at(&mut conduct, 10 + 4 * span_of(0), &book, &record),
            vec![Action::Enter(1)]
        );
        // Pledges of attempt three from two parts — more than `T - Q` at four and three — draw a
        // machine in attempt zero into attempt three; one part does not.
        let mut book = Book::of_the_window(7);
        book.pledge(pledge(2, 3, Y, STANDS_ON_NONE));
        let mut conduct = Conduct::default();
        conduct.entering(0);
        assert!(at(&mut conduct, 1, &book, &record).is_empty());
        book.pledge(pledge(3, 3, Y, STANDS_ON_NONE));
        assert_eq!(at(&mut conduct, 1, &book, &record), vec![Action::Enter(3)]);
        // A decided book asks for nothing: the pulse closes the window.
        let mut book = Book::of_the_window(7);
        for part in 1..=3 {
            book.pledge(pledge(part, 1, X, STANDS_ON_NONE));
            book.pledge(pledge(part, 1, X, 1));
        }
        assert_eq!(book.decided(&electorate), Some((X, 1)));
        assert!(at(&mut conduct, 1, &book, &record).is_empty());
    }

    // A machine behind its cohort, holding the quorum the others reached in a later attempt, is drawn
    // into that attempt before it pledges in its own. The wrong implementation refused: one proposing
    // first, on its valid name standing on that later attempt -- a pledge standing on an attempt after
    // its own, which the layout refuses as `Since`, so the pulse of that machine stopped with
    // `Object(Since)` (four_machines_decide_one_name.rs:217 on a62d6ab, Lauterbourg-2 a588-r2.out).
    #[test]
    fn a_machine_behind_is_drawn_forward_before_it_pledges() {
        let votes = BTreeMap::new();
        let electorate = four(&votes);
        let aggregate = [0x33; 32];
        let replayed = BTreeMap::new();
        let mut book = Book::of_the_window(7);
        for part in 2..=4 {
            book.pledge(pledge(part, 3, Y, STANDS_ON_NONE));
        }
        let mut record = Record::opened(7, X);
        record.attempt = 1;
        record.valid = book.valid_name(&electorate);
        assert_eq!(record.valid, Some((Y, 3)));
        assert!(matches!(
            pledge(1, 1, Y, 3).bytes(),
            Err(mt_state::ObjectError::Since)
        ));
        let span = span_of(1);
        let mut conduct = Conduct::default();
        conduct.entering(0);
        for now in [0, span, 2 * span, 4 * span] {
            assert_eq!(
                tick(
                    &mut conduct,
                    now,
                    &book,
                    &electorate,
                    &record,
                    &part(1),
                    &aggregate,
                    &replayed
                ),
                vec![Action::Enter(3)],
                "at asking {now}"
            );
        }
    }
}
