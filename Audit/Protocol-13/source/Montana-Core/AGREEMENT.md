# Agreement on what a window decided

Date: 2026-10-16. Session: 42. Author of this note: the Architect (Claude), under the author's words
of 2026-10-16 recorded in the chain of the council: close item 1 whole, with nothing left over.

This note is the design gate for the one finding of that work that is not a remainder of item 1. It
states the finding, why no rule local to a machine closes it, what closing it requires, the
construction recommended, and what it costs, so that the author can rule on it as a stage of its own.

## 1. The finding

A window's decision is the proposal its machines take, and its name is taken over what the window
decided: the predecessor, the six roots, the counts, the census and the cement pair (Canon, "The
proposal that closes a window"). Two inputs of that name are what a machine held when it left a
round, and nothing makes two machines hold the same:

- **the cement pair.** A machine advances only on a beacon whose pair equals the cement it holds
  (`montana-node/src/pulse.rs`, `matches_cement`, `reconcile_beacon`), and closes on the first
  advanceable beacon at the quorum (`live_doing`). A machine holding one part more than a beacon at
  the quorum cannot reconcile it and closes later on another beacon with another pair; where the
  quorum asks less than the whole electorate, two machines close one window on two pairs.
- **the frames.** A machine applies the frames standing at the points of a round as it leaves that
  round (Canon, "The roots of state"; `Machine::apply_what_stands`). A frame that reaches one machine
  before it leaves the round and another after has entered one plane and not the other, and the two
  carry two note roots for one window — at any population, three machines included.

Two names for one window part the window after: its heavy attestations attest the name each machine
took, its cement counts parts per name, and where no name reaches the quorum of that window no
machine of it closes. A machine attests one name per window under its part, and a second is the
equivocation the set sanctions, so nothing re-votes. Safety is untouched — two names cannot both
reach a quorum without a third of the electorate signing both — and liveness is not: the set orders
the rounds and the versions of a round (the smaller identifier) but never votes a second time on the
predecessor of a window.

The runs of this tree are of two and three machines, where the quorum asks all and no frame raced a
close; they show neither half.

## 2. Why no local rule closes it

Every rule a machine applies to what it holds — the smaller identifier among the candidates it has
seen, the larger cement, the first to arrive — agrees between two machines only where both saw the
same candidates before they attested, and nothing bounds when a candidate arrives. A machine that
switched after attesting would equivocate; one that never switches keeps a split forever. Agreement
under a bounded fraction of faults and unbounded delays is the problem of Byzantine agreement, and
its known constructions vote more than once: a second vote that locks, or a common coin.

## 3. What closing it requires

- **One decision per window, at the quorum of the electorate**, safe while fewer than a third of it
  signs two ways — the property the set has today and keeps.
- **Liveness once delivery is bounded**: after delays fall below a bound no machine knows in
  advance, every honest machine decides, with waits that grow from attempt to attempt.
- **A decision any machine can adopt**: a proposal names what it applied — the frames in order and
  the parts of its cement — so a machine that left its rounds holding something else recomputes the
  decided state from the named content rather than from its own reading of the points.
- **A certificate a device verifies**: the walk reads the decision off the votes as it reads the
  cement today.

## 4. The construction recommended

An agreement in the manner of Tendermint (Buchman, Kwon, Milosevic, 2018), run inside the window
after over the predecessor of the window, with Montana's own pieces:

- **proposers**: the runners of the window, in the order of their tickets — the order Canon now
  states (`CARRIES_WITHIN`) — so the first proposal of an attempt usually comes from one machine and
  nobody learns whose;
- **the first vote**: the heavy attestation as it stands, attesting the proposal its machine takes;
  later attempts vote under the key that heavy proved, as light attestations do;
- **the second vote and the lock**: a seal — a signature of the part's key over the window, the
  attempt and the name — published once the first votes of an attempt reach the quorum on one name;
  a machine that sealed a name votes only that name in later attempts unless it holds first votes at
  the quorum on another name of a later attempt;
- **the decision**: seals at the quorum on one name, which is what makes the predecessor final and
  what a device walks;
- **the content**: the proposal carries the identifiers of the frames it applied, in the order it
  applied them, and the parts of its cement, so a machine adopting it replays the window's frames
  from that list rather than from the points it happened to read.

## 5. The construction adopted (session 43)

Date: 2026-10-16. Author of this section: the Architect (Claude), session 43, under the author's
words of 2026-10-16 recorded in the chain of the council: "it will be done by session 43 — hand it
over" and, before it, "close item 1 whole, with nothing left over".

The set adopts the recommendation of section 4 with four changes, each forced by a finding against
the recommendation as written; the normative text is Consensus 7.0.0, "The agreement on what a window
decided", with Canon 9.0.0, "The pledge of a part" and "The roll of a proposal".

1. **One pulse per window, standing on the proposal two before.** Round zero of a window links to
   the proposal that fixed its electorate, which is final when the window opens, and the cement of a
   beacon gathers every heavy attestation of the window whatever name it pledges. Finding: a pulse
   standing on the name being decided parts with the names — two pulses, each gathering the living
   of its half — so the cement the next proposal carries parts too, and a window decided past its
   first attempt would leave the next window split on the cement: a cascade with no end.
2. **The proposers of a later attempt are ordered by a place everybody computes.** The place is a
   hash of the part-nullifier, the cemented aggregate of the window two before and the attempt.
   Finding: the ticket order of section 4 is published by nobody, so a machine claiming to come
   first is believed by no rule; a proposer any machine can impersonate is a proposer a faulty
   machine always is, and the agreement would never leave a split it is fed.
3. **Every proposal names its roll.** The frames it applied in order and the parts of its cement,
   in pages chained by identifier, the first named inside the scope of the proposal's name. Finding:
   a machine that left the rounds holding other frames or another cement cannot recompute a name it
   did not take, and following a name it cannot validate would let a faulty proposer finalize roots
   nobody recomputed.
4. **A payer is told again where a replay moves its frame.** Finding: a machine adopting a decided
   name replays the decided roll and its own window again, and the positions it told a payer at the
   leaving of a round move with that replay; a note spends only once its window's root stands in the
   horizon of proving, by which time the decision stands.

The second vote of section 4 — the seal — is the **closing pledge**, a pledge standing on the quorum
of its own attempt; the first vote of a later attempt is an **open pledge**, standing on an earlier
quorum or on none. Every open pledge counts only on the quorum its `since` names, and every closing
pledge only on the quorum of open pledges of its attempt, so two decisions leave three kinds of
contradicting pairs and nothing else ("Finality"): accountability stays a matter of pairs, which is
what Gate 6 of the role asks of a sanction.

## 6. The construction the author chose (session 46)

Date: 2026-10-16. Author of this section: the Architect (Claude), session 46, under the author's
words of 2026-10-16, 21:55 and 21:56 MSK, recorded in the chain of the council: the choice "A" --
the roll of a proposal is one body, its root inside the name of the proposal, with no pages and no
chain of pages; the body stands at the points of the window as frames do and leaves with the windows
the retention lets go; nothing is kept for ever, and the chains of beacons do not change. The text of
050a0f8 (Consensus, "The agreement on what a window decided") is the base; this section names what
the choice changes in it and what was found against the pulse on the way.

**What forces a roll.** A run of 2026-10-16 on six machines on six hosts, a cohort of six and a
quorum of five, closed window 0 on two names: two machines on one proposal, two on another, and two
holding a cement no beacon at the quorum carried, standing in round zero. In the construction of
050a0f8 a machine follows another machine's name only where that name is valid to it: its own, one
the open pledges of an attempt reach the quorum on, or one whose roll it replayed. Take the roll away
and a split of two, two and two leaves the proposer of every later attempt with a name valid to its
own half alone, no quorum of open pledges forms in any attempt, and the window is never decided. The
roots of state record what a window applied (`operations_root`) without naming which objects at the
points produced it, so a machine holding another set cannot find the subset; and the argument of
050a0f8 that the agreement decides once delivery is bounded already stands on "the proposer's own
with its roll at the points".

**The body.**

```
serialize(roll)
  window                          8 B   u64   the window of the proposal the roll belongs to
  frames                          4 B   u32   the frames the window applied, at most frames_per_window
  parts                           8 B   u64   the parts of its cement, equal to the proposal's cement_count
  entry × (frames + parts)       32 B each    the frames in the order they applied, then the parts ascending
roll_len = 20 + 32 × (frames + parts)
roll_id  = SHA-256("mt-roll" || 0x00 || serialize(roll))
```

The proposal's field `roll` is `roll_id` and stands inside the bytes its name is taken over, which
grow from 686 to 718. A body whose length is not `roll_len` of its own two counts is refused before an
entry is read.

**Why one body suffices.** The frames of a window are capped (`frames_per_window`, 273) and the parts
are the cement of the window, at most the count of its electorate, so a body holds at most
`20 + 32 × (273 + T)` bytes. One delivery carries up to 65 535 blocks (`block_count` is a u16,
`mt-wire/src/publish.rs`, `cells_of`), and a point is read by a u16 index (`montana-node/src/pulse.rs`,
`collect_from`), which already bounds a round point to about 124 heavy attestations of 528 cells each;
at that electorate a body is about 12 KB, fewer cells than the one heavy attestation of a single
machine. Pages answered a bound a body does not meet while points are read as they are; a later wire
that widens the index grows the body by 32 bytes for each machine, beside the 391 blocks of that
machine's heavy attestation in the same window.

**Where it stands, and for how long.** At the window points of the window it closes, beside its
proposal, for `retained_windows` windows after that window closes, as the frames it names do; it goes
with them. A beacon carries what it carried.

**The agreement record of a machine: kept, one for each open window.** The handover of session 44
proposed that a machine read its lock back from its own closing pledge at the points after a restart.
Finding: a machine that restarts and reads no pledge of its own cannot tell a pledge never made from a
pledge whose holders are out of its reach, and pledging on that reading lets an honest machine sign
one of the three contradicting pairs the sanction reads. The record stays as 050a0f8 states it -- the
attempt, the lock, the valid name and the pledges made -- written before anything it governs is
published, and let go when its window closes. The store already keeps a choice of this kind
(`mt-store`, `lock_predecessor`, one file for each window, never removed); the record takes its place
and is removed at the close, so a machine holds one record for each open window and no history.

**Taken from 050a0f8 as it stands.** One pulse for each window, standing on the proposal two before
(section 5, change 1); the place of a part (change 2); the payer told again where a replay moves its
frame (change 4); the pledge, the two rules of counting, the decision and the three contradicting
pairs.

**Found against the pulse, closed in the same stage.**

- *The memory of a stalled window.* A point lives by its window (`montana-node/src/lib.rs`,
  `Standing::hold`): inside the open window nothing of a round is let go. Without a quorum the rounds
  keep turning at the pace of the echo -- 4 097 rounds in about 140 seconds on one machine of the run
  -- and every round stands its beacons and light attestations; that machine held 1.25 GB after four
  minutes and was stopped by its kernel. A heavy attestation is verified against the beacon it
  answered, whose chain and round its eligibility reads, and a machine reads past rounds to gather
  late heavy attestations (`pulse.rs`, `HistoricalRounds`), so a bound may let the light attestations
  of a round left behind go but keeps a beacon as long as a heavy attestation that answered it. The
  rule of the bound is part of this stage and is not yet written.
- *A machine holding more cement than the beacon at the quorum.* Two machines of the run held cements of
  six and of five parts whose pair no beacon at the quorum carried, and stood in round zero (`pulse.rs`, `matches_cement`:
  the pair must be equal). The test of four machines carries this case.

**Acceptance.** As section 7 of 050a0f8 states it: four machines at a quorum of three under a held
part, a late frame and a partition that heals; then the run on six machines repeated.
## 7. Gates

- Gate 0 and the global invariants: no new primitive (SHA-256 under two new domains, ML-DSA under
  the part key already proven); every wait is conduct and enters no rule of acceptance [I-3]; the
  place carries the cemented aggregate, the unpredictable-offline atom [I-8]; every quantity is an
  unsigned integer [I-9]; layouts and domains live in Canon alone [I-10];
  pledges, the body of a roll and frames live at their points for `retained_windows` windows and a
  machine's agreement record lives one open window [I-14].
- Gate 4, discretion: a proposer of a later attempt chooses when to include exactly as a runner
  does; Consensus names it ("The one place a proposer chooses, named") with its bound.
- Gate 6, proof requirement: the sanction reads three pairs of signed pledges and nothing else.
- Gate 7, the seed of the place: the part (canonical, fixed by the secret and the window), the
  aggregate (canonical, unpredictable offline), the attempt (canonical, a count).
- Gate 13: the pledge and the body of a roll carry their invariants beside their layouts.
- Gate 15: the light attestation stops being evidence, and every place of the set that said
  otherwise was swept (Consensus, Canon, Constitution, Registry, Value).

## 8. What it costs

The test of four machines with a quorum of three under a held part, a late frame and a partition
that heals, then the run on six machines repeated, is the acceptance of this stage; the walk of a device and the certificate carry the
pledges; the constitution's register no longer names the finding open.
