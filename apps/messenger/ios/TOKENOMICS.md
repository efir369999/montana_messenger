# Asymptotic Emission in Montana: One Second, One Coin

**An integer model of a currency whose supply is the lived time of its people**

Working paper of the Montana council, revision 1, 22 October 2026. Written for the cryptography
mailing list (Metzdowd) and for the reviewers of the public repositories. The paper describes the
set of Montana as it stands on the day of writing and changes nothing in it. Every statement about
the set carries a path and a line. Every number is computed by the reference program of Appendix B
in integer arithmetic, and no number in this text was typed from memory.

Sources cited by revision:

- the constitution of the council, `CouncilWall/constitution.jsonl` of the messenger repository, head `rollback-898` b8767d5f
- the coin chain of the application layer, `Audit/COIN-TX-V3.md`, the same head
- the fold of the coin chain in Rust, `Code/crates/mt-coin/src/lib.rs` of the protocol repository, branch `core/mt-coin-231`, head 32a9a474
- the consensus set at Canon 4.2.0, `docs/Montana Canon.md`, `docs/Montana Consensus.md`, `docs/Montana Constitution.md`, `docs/Montana Value.md`, `docs/Montana App.md`, `docs/Montana Identity.md` of the protocol repository, working tree at `feat/s3-stage1`, head ae36d1f9
- the consensus set at Canon 5.0.0 (one second, one coin), the same files on branch `spec/mint-second-99`, head 14058d39
- the client, `Code/Montana/MTWalletCore.swift` and `Code/Montana/MTWalletScreen.swift` of the messenger repository, head b8767d5f

## Abstract

Montana issues one coin to one living participant for one second of life, and nothing else issues a
coin. This paper states that rule as three axioms of the set, builds the emission model they imply
in integer arithmetic, and studies its limit behaviour. The model has two layers. In the application
layer (the coin chain of a key, COIN-TX-V3) a key of age x seconds has been credited exactly x coins
of emission, by a fold the core performs and no device can accelerate. In the consensus layer (Canon
5.0.0) a window pays every living machine the seconds the window lasted, a second being a fixed count
of network echoes rather than a clock reading, so the rate holds at one coin a second at every size of
the network. Aggregate supply is therefore the integral of the living population over time: it has no
ceiling, it grows by exactly the number of living participants each second, and its relative growth
falls as the inverse of the age of the system, so the inflation rate is asymptotically zero while the
stock is unbounded. The asymptote of the model lives in two places, both proven here in integers: in
the rate, which vanishes as 1/t, and in the person, who cannot hold more coins of emission than the
seconds of a lifetime, three billion and some, about three banknotes of one Montana. We give the
formal model, eleven families of test vectors each refusing a named wrong implementation, the
equilibrium analysis of the rule (existence is the dominant strategy, the only lever is the count of
admitted machines, and admission is priced in time), the comparison with the Nakamoto schedule, the
Monero tail, the Ethereum base-fee burn, and the monetary rules of Fisher, Friedman, Hayek, Gesell,
Cahn and Szabo, the attacks the model does and does not close, and eight open questions for the
author where the constitution, the specification and the code do not say the same thing.

## 1. Problem statement

A monetary rule answers three questions: who may create a unit, how many, and when. Proof-of-work
answers all three with computation. Proof-of-stake answers them with capital. Montana answers them
with lived time: one unit for one second of one life, the second counted by the network and not by a
clock. The question of this paper is what economy such a rule produces.

Three things make the question non-trivial.

1. **The unit of scarcity is not scarce in the usual sense.** Time passes for everyone at the same
   rate and cannot be bought. A rule that pays time has no natural ceiling and no natural floor: it
   pays as long as there are people. Whether such a supply is inflationary, deflationary or neither
   is a matter of the limit, and the limit must be computed, not asserted.
2. **The identity of the participant is the whole problem.** A rule that pays one coin per second
   per person pays n coins per second to whoever can be n persons. Montana does not detect common
   ownership (Consensus 5.0.0, lines 1036-1041, quoted in section 8). What bounds the attacker is
   the price of admission, and the price is time. The model must therefore say how fast an adversary
   can grow the set of paid machines and what that costs in seconds.
3. **The set is in motion.** The application layer runs one second, one coin since 20 October 2026
   and moves the mint inside the core on 23 October 2026. The consensus set at Canon 4.2.0 still
   carries a fixed mint of 13 000 000 000 coins a window divided equally among the living, and the
   branch at Canon 5.0.0 replaces it with one second, one coin. The author's word of 21 October
   2026 names the direction (section 2.4). The decision of the council that would make it the
   genesis of the global TimeChain is open (section 11, question 1). This paper models both rules
   and shows where they meet.

The method is the one the set demands of itself: integer arithmetic only (no floating point enters a
formula), a test vector for every formula that names the wrong implementation it refuses, and a
statement of every limit by name rather than by omission.

## 2. The axioms of the set

The axioms are the author's words as the constitution of the council holds them, quoted in the
original with a translation, with the chain link that holds each.

### 2.1 Axiom A1, the rate

`CouncilWall/constitution.jsonl:12`, article 11, link 12 of 06.10.2026 15:27:48:

> 1 second — 1 Coin.

One second, one Coin.

### 2.2 Axiom A2, the ticker

`CouncilWall/constitution.jsonl:13`, article 12, link 13:

> The ticker of the Montana Time Coin is $TCM.

The ticker of the Montana Time Coin is TCM.

### 2.3 Axiom A3, the banknote

`CouncilWall/constitution.jsonl:14`, article 13, link 14:

> 1 Nakamoto coin — 1 Montana banknote — is 1 billion Coins.

One unit of the Nakamoto currency, one Montana as a banknote, one billion Coins. The author's
chain, link 536 of 04.10.2026 17:56: «article 13 of the constitution — 1 Nakamoto coin = 1 Montana banknote = 1 billion
Coins». The banknote is a unit of account: one Montana is 10^9 coins, as the client holds it
(`MTWalletCore.swift:174`, `coinsPerMontana = 1_000_000_000`, and `:329`, «a Montana is a billion
coins»). The axiom fixes a unit, not a price. What one Montana is worth in any other currency is the
answer of whoever exchanges it (COIN-TON, section 4 of that document, «the rate is the person's answer
to how much is your hour now»). Section 6.4 computes what one Montana is in lived time.

### 2.4 The author's words that fix the reading of A1

- 19.10.2026 12:3x UTC, as `Audit/COIN-TX-V3.md:137-139` quotes them: «this is the ceiling, an
  invariant, the constitution — nothing else can mint or speed it up, no music, VPN and so on: VPN on,
  the app active, the person online — 1 second, 1 coin», and 13:4x: «bring everything to one owner of
  the function 1 coin = 1 second, and that is all».
- 21.10.2026 13:5x UTC, chain link 3897: «the rule in Rust for the node, and with us 1 coin = 1 second,
  no 13 billion for a coin any more».
- 21.10.2026 14:1x UTC, chain link 3898: «only the core mints // 1 coin - 1 second, the client merely
  shows it, it does not mint».
- 19.10.2026 14:4x UTC, chain link 3008: «the rate 1 Coin = 0.000000001 TCM = 1 s». This word reads TCM as the billion-coin unit. Article 12 reads
  TCM as the ticker of the Coin. Section 11, question 2, names the difference.

### 2.5 The axioms of the consensus set that carry A1

Canon 5.0.0, `docs/Montana Canon.md:4741` on `spec/mint-second-99`:

> `window_seconds` — the seconds a window of `target_rounds` rounds on each chain is worth to every
> living machine, one coin a second | 60

Constitution 4.0.0, `docs/Montana Constitution.md:804-809` on the same branch:

> the monetary constitution — one second, one coin: every living machine holds a right to the seconds
> of each window it lived in, a second being a count of rounds Genesis fixes and no later act may
> change, so that nothing — no machine, no crowd, no service a person runs — mints faster than one
> coin a second; the issuance of a window is the count of its living times that worth with the count
> private, supply never decreasing, no halving driven by the protocol, no premiums, no protocol-level
> burning

Consensus 4.0.0, `docs/Montana Consensus.md:1061-1065` on the same branch:

> A second of Montana is `target_rounds / window_seconds` rounds of one chain — a count of echoes of
> the network and never a reading of a clock — so a second is worth one coin to every living machine.
> A window that closes in fewer rounds is worth fewer seconds, and the fraction of a second a window
> does not reach is not paid: the worth never rounds up, so no window mints faster than one coin a
> second to anyone, and nothing a machine runs — no service, no count of devices, no duty — adds to it.

### 2.6 The axiom the consensus set at 4.2.0 still carries

Canon 4.2.0, `docs/Montana Canon.md:4480` on `feat/s3-stage1`:

> `emission_schedule` — rows of `(height, mint)`, the mint of a window read by height, ascending | (0, 13 000 000 000)

and Consensus 4.2.0, `docs/Montana Consensus.md:1052-1060`: «A window mints a fixed quantity and
issues, to each living machine, a right to a share of it. [...] one equal part to every living
machine, with the remainder that does not divide carried forward rather than appropriated.» The code
of the core at this revision reads the row by height and divides it (`Montana-Core/crates/montana-node/src/attest.rs:259-264,
279-301`, `Montana-Core/crates/mt-genesis/src/lib.rs:88`). Section 5.3 models this rule and section 5.4
computes where the two rules meet.

### 2.7 What the axioms exclude

The axioms, read with the constitutional layer quoted in 2.5, exclude by construction: a halving or
any rule that mints differently over time by itself, a premium to any role, a lottery of emission, a
burn at the protocol level, a fee or a rent as a protocol notion (`docs/Montana App.md:56-62`: «no
fee, no rent, no subscription exists as a protocol notion»), and any clock reading inside the
protocol (`docs/Montana Constitution.md:336-340`, [I-15] of the Constitution). The emission function
is therefore constrained to be a function of lived seconds alone, with a coefficient of one.

## 3. Definitions and notation

All quantities are non-negative integers. No formula of this paper divides except by the floor
division ⌊a / b⌋, with the multiplication performed before the division.

- t: a second. In the application layer a second is the second of the node's clock at which it took a
  record (`Audit/COIN-TX-V3.md`, section 2: «The node's at of a record is the node's second when it
  took it, never less than the at of the record before it on the chain»). In the consensus layer a
  second is a count of rounds (section 5.1).
- k: a coin key, identified by `from = SHA-256(pubkey)`. b_k is its birth, the node second of its
  first record (section 3 of COIN-TX-V3, «birth: the at of the chain's first record»).
- x = t − b_k: the seconds the key has lived at t.
- m_k(t): the key's `minted`, the sum of everything emission ever credited to it up to t.
- p_k(t): the key's `proven`, the coins its chain proves it holds.
- L(t): the number of living participants at t. In the application layer, the keys with a chain. In
  the consensus layer, the machines whose part-nullifier entered the cement of the window
  (`docs/Montana Consensus.md:1045` at 5.0.0: «A machine is living in a window when its part-nullifier
  entered the cement of that window, and by no other condition»).
- S(t): the aggregate supply, the sum over keys of m_k(t) in the application model, and the sum over
  windows of the issuance in the consensus model.
- Y = 31 557 600, the seconds of a Julian year (365.25 days of 86 400 seconds). Used only to express
  durations. No formula of the protocol reads it.
- M = 10^9, the coins of one Montana (axiom A3).

## 4. The emission of one key: the application layer

The coin chain of a key is a sequence of signed records (GENESIS, MINT, SEND, RECV, REFUND), folded
in order into a state (`Audit/COIN-TX-V3.md`, section 3). The fold is one function of the core, the
crate `mt-coin` of Montana Core, named `fold-6` (`Code/crates/mt-coin/src/lib.rs:23` on
`core/mt-coin-231`: `pub const TX_FOLD: &str = "fold-6"`). The node, every replica, every phone that
keeps a copy and the Explorer fold by it. Three rules of that fold are the emission rule, and they
succeeded one another at three named seconds. The constants and formulas below are quotations of
those two sources at the revisions named in the front matter, and this paper is not a second place
for any of them.

### 4.1 The allowance under one second, one coin (fold-5)

From `TX_SECOND_CUT` = 1 792 443 600 (19.10.2026 21:00 UTC), `Audit/COIN-TX-V3.md:142-144`:

```
A(x) = x                       for x ≥ 0, A(0) = 0
allowance(t1) = A(t1 − birth) − minted
```

A MINT of amount a over the interval [t0, t1) is taken only if a ≤ allowance(t1), with t0 ≥ mint_end,
t1 − t0 ≥ 60 and t1 ≤ at (section 3 of COIN-TX-V3, the MINT rule). The rule a MINT is weighed by is
chosen by the second the node took it at, never by its interval (`Code/crates/mt-coin/src/lib.rs:410-416`):

```rust
pub fn allowance(lived: u64, at: u64) -> u128 {
    if TX_SECOND_CUT <= at { u128::from(lived) } else { a2(lived) }
}
```

**Lemma 1 (the sum stays under time).** For every key and every second t ≥ TX_SECOND_CUT, the sum of
the amounts of the MINTs taken at or after the cut is at most (t − b_k) − m_pre, where m_pre is what
the key minted before the cut. Proof: each MINT taken at second at ≥ cut satisfies a ≤ A(t1 − b) −
minted ≤ (at − b) − minted, and minted is increased by a on acceptance, so after the MINT minted ≤
at − b. The bound is monotone in at. A refused MINT leaves the state as it stood (section 3 of
COIN-TX-V3). ∎

### 4.2 The chain mints the key's time itself (fold-6)

From `TX_TIME_CUT` = 1 792 702 800 (22.10.2026 21:00 UTC), the fold credits the seconds of a key's life
at every record it takes, before the record's kind is folded (`Audit/COIN-TX-V3.md`, section 3, «THE
KEY'S TIME»; `Code/crates/mt-coin/src/lib.rs:418-430`):

```rust
pub fn time_step(s: &KeyState, at: u64) -> KeyState {
    let lived = u128::from(at.saturating_sub(s.birth));
    if at < TX_TIME_CUT || s.height == 0 || lived <= s.minted {
        return *s;
    }
    KeyState { proven: s.proven + lived - s.minted, minted: lived, ..*s }
}
```

In the notation of section 3, with x = at − b_k:

```
m_k' = max(m_k, x)
p_k' = p_k + (m_k' − m_k)
```

The balance a phone shows is the same step applied at the node's current second, never below the
head's own second (`lib.rs:434-436`, `at_now`). No phone lays a MINT for its time any more: a MINT
taken from the cut on finds the allowance at most 0, because the time step has already set minted to
at − b ≥ t1 − b (section 4 of COIN-TX-V3, «every MINT is refused «allowance»»). The client agrees
(`MTWalletCore.swift:3848-3855`, `timeCut`, `timeStep`, and `:4465`, which lays no MINT from the cut).

**Theorem 1 (the emission of a key).** Under fold-6, for every key k and every node second t ≥ b_k at
which its state is read,

```
m_k(t) = max( m_k^pre , t − b_k )
```

where m_k^pre is the sum of the MINTs the key was credited before TX_TIME_CUT (each of them bounded by
the rule in force at its own second, A_2 before TX_SECOND_CUT and A between the cuts). In particular,
a key born at or after TX_TIME_CUT has m_k(t) = t − b_k exactly: one coin for every second of life, no
more and no fewer, and the equality is independent of everything the key or its owner did.

Proof. The time step is the only place of the fold that increases minted from TX_TIME_CUT on (the MINT
branch cannot, by the paragraph above). It sets minted to max(minted, at − b). Reading the state at t
applies the step at max(t, last_at) ≥ t, and last_at ≤ t for a state read at t. By induction over the
records, minted after the record taken at at equals max(m^pre, at − b), and reading at t gives
max(m^pre, t − b). For a key born at or after the cut, m^pre = 0 and height ≥ 1 from its GENESIS, so
m_k(t) = t − b_k. ∎

**Corollary 1 (nothing accelerates).** No field of any record enters the time step except `birth`
and `at`. A record's amount, kind, interval, the count of records, the device, the build, music, a
call, a tunnel: none of them is an argument of `time_step`. This is the author's word of 19.10.2026
15:3x in the form of a function signature.

**Corollary 2 (idempotence and monotonicity).** Applying the time step twice at the same second is
applying it once. Applying it at t and then at t' ≥ t equals applying it at t' alone. The fold of a
chain is therefore independent of how often it is read, and a replica that folds later than the chain
node reaches the same state.

### 4.3 The retired rule: the doubling curve A_2 (fold-3 and fold-4)

Before TX_SECOND_CUT a MINT was weighed by the doubling rule (`Audit/COIN-TX-V3.md:157-161`,
`Code/crates/mt-coin/src/lib.rs:386-406`):

```
A_2(x) = Σ_{s=1}^{x} 2 × min(13, max(1, bit_length(s) − 1)),     A_2(0) = 0
```

The s-th second of a key's life paid twice its level, the level being the count of whole doublings of
s since birth, at least 1 and at most 13. The rate per second therefore rose from 2 at s = 1 to 26 at
s ≥ 8192 (bit_length(8192) − 1 = 13) and stayed there: a saturating curve of the rate, concave in the
count of lived seconds, with an asymptote of 26 coins a second reached after 2^13 seconds, about two
hours and sixteen minutes. Over a day it paid A_2(86 400) = 2 213 664 coins, 25 whole coins a second
and 53 664 more. The rule still weighs every MINT taken before the cut (a re-fold must not change a
record's fate) and still bounds every GENESIS announcement: TX_GENESIS_CAP = A_2(TX_V2_CUT −
TX_COIN_EPOCH) = A_2(4 233 600) = 110 040 864 (`lib.rs:24`, checked by Appendix B).

This is the only saturating emission curve the set ever carried, and the author retired it on
19.10.2026 in favour of A(x) = x (section 2.4). Section 11, question 6, asks the author to confirm
that the «asymptotic emission» of the task is the asymptote of sections 6.2-6.4 and not this curve.

### 4.4 What a key's chain does not do

A key's emission is not a payment to anyone and names no one: a MINT, and from fold-6 the time step,
is a source with no parent in the graph of the coins' appearance (`Audit/COIN-TX-V3.md`, section 10).
A SEND moves proven coins first and declared coins second, a RECV opens a SEND by its blind, a REFUND
returns an unsettled SEND after a day. None of them changes m_k. The sum of proven over all keys
differs from S(t) only by coins in flight (SENDs not yet settled) and by the two named legacies of
section 10.3. The conservation of the application layer is therefore additive and public, unlike the
conservation of the consensus layer (section 5.5), and the Explorer checks it by folding every chain.

## 5. The emission of a window: the consensus layer

### 5.1 A second is a count of echoes (Canon 5.0.0)

The protocol reads no clock ([I-15] of the Constitution). It counts rounds, and a round is one echo
across a sample of the network scattered like the population. Canon 5.0.0 derives the second from the
planet (`docs/Montana Canon.md:659-690` on `spec/mint-second-99`): a round trip of light in fibre over
half the circumference, 2 × 20 000 km at 200 000 km/s, is 0.2 s, so a window of `target_rounds` = 284
echoes lasts at least 56.8 s, the nearest whole minute above it is 60, and a second of Montana is 284
rounds over 60 seconds, about 4.73 rounds of one chain. The worth of a window's right, in coins, is
(`Canon.md:673`, `Consensus.md:1058`):

```
window_value(r, k) = ⌊ window_seconds × r / (k × target_rounds) ⌋ = ⌊ 60 r / (284 k) ⌋
```

where r is the count of rounds the window ran summed over its chains and k the count of chains in
force at its height, both public and both read from the beacon chains every machine verifies.

**Theorem 2 (one coin a second at every population).** For every window, the issuance to one living
machine satisfies

```
window_value(r, k) ≤ 60 r / (284 k)
```

with equality when 284 k divides 60 r, and the shortfall is strictly less than one coin. Since 60 r /
(284 k) is the number of Montana seconds the window lasted, no window pays any machine more than one
coin per second of its duration, and a window that closes in fewer rounds pays fewer seconds. Proof:
⌊a / b⌋ ≤ a / b with a − b ⌊a / b⌋ < b. ∎

The set says the same in words (`Consensus.md:1063-1065`, quoted in 2.5) and in the Canon's defence of
the row (`Canon.md:685-690`): a fixed coin per window would pay a one-round window as a full one,
hundreds of times a second, while the network is small, and a clock would be a second its owner sets.
The vectors of the set (`Consensus.md:1067-1079`) are reproduced in Appendix A, V-E.

The issuance of a window is the count of the living times that worth (`Consensus.md:1081`):

```
I(W) = L(W) × window_value(r_W, k_W)
```

L(W) is computed inside the window's proof and never leaves it. The total ever issued is, in the words
of the set, «a quantity no one reads» (`Consensus.md:1083`). Section 5.5 draws the consequence for
the macro model.

### 5.2 The time constants the second induces

With one window of 284 rounds on each chain worth 60 seconds, the parameters of the Decree that are
written in windows (`Canon.md:4740-4777` on the branch) acquire durations. They are the time
constants of the Sybil defence of section 8.

| Parameter | Value in windows | Duration at 60 s a window |
|---|---|---|
| τ₂, the period of adaptation | 20 160 | 1 209 600 s = 14 days |
| segment_windows | 1 440 | 86 400 s = 1 day |
| continuity_period = 14 segments | 20 160 | 14 days, 2 of 3 required present |
| selection_interval | 336 | 20 160 s = 5 h 36 min |
| membership_term = 2 τ₂ | 40 320 | 28 days |
| candidate_expiry = 3 τ₂ | 60 480 | 42 days |
| max_entry_segments | 56 segments | 56 days |
| k_step, one chain added, to the cap of 8 | 96 τ₂ | 1 344 days |

The durations hold where a window takes its target of 284 rounds a chain, that is above the floor of
the crowd. Below it a window takes fewer rounds and the same count of windows passes in less lived
time (`Canon.md:4802-4806`: «The young network mints no faster than the old: the length of a window
in rounds falls with the population below the floor of the crowd and stands at the target above it,
and a right is worth the rounds of its window and never the window»).

### 5.3 The rule at Canon 4.2.0: a fixed mint divided equally

The set on `feat/s3-stage1` carries one row, (0, 13 000 000 000): every window mints 13 × 10^9 coins,
thirteen Montana, and issues to each of the L living machines one right to an equal share, the
remainder that does not divide carried forward (`Consensus.md:1052-1060`, `attest.rs:259-264`):

```
share(L) = ⌊ 13 000 000 000 / L ⌋
carry(L) = 13 000 000 000 − L × share(L)
```

The division is exact in integers and the carry is at most L − 1 coins (Appendix A, V-I). The
constitution of this revision forbids a halving and permits a founder to shape the early height by
writing rows, not powers (`docs/Montana Constitution.md:804-811` on `feat/s3-stage1`), so the only
nonlinearity this rule admits is a step at a height named in the genesis.

### 5.4 Where the two rules meet

Under the fixed mint, a living machine's income per window is ⌊13 × 10^9 / L⌋ coins. Under one second,
one coin, it is 60 coins at the target length. The two coincide at

```
L* = ⌊ 13 000 000 000 / 60 ⌋ = 216 666 666 living machines (remainder 40)
```

Below L* the fixed mint pays every machine more than one coin a second (13 × 10^9 coins to one machine
alone in a window of 60 seconds is 216 666 666 coins a second). Above L* it pays less. The fixed mint
is thus a rule whose per-capita rate falls as 1 / L with the population, while one second, one coin is
a rule whose per-capita rate is constant and whose aggregate rate grows as L. The author's word
«no 13 billion» (section 2.4) chooses the second. The council's decision line that would make it the
genesis of the global TimeChain is open (`constitution.jsonl:41`, status `decide`, no `decided` row).

### 5.5 Conservation and its honest price

In the consensus layer the issuance is conserved by proof, not by addition (`docs/Montana Value.md:187-189`
on the branch): per payment what is created equals what is consumed, per window the change of supply
equals the issuance, and globally the sum of unspent notes and unredeemed rights equals the supply,
«held by proof and induction and unverifiable by addition — amounts are hidden and rights are
private». The set names the price (`Value.md:191-195`): a breach of issuance cannot be detected by
summation, and the integrity of issuance rests on the correctness of the proof scheme and on two
independent verifiers accepting and rejecting identically.

For this paper the consequence is that S(t) of section 6 is a model quantity in the consensus layer:
it follows from the rule and the population, and no observer measures it. In the application layer of
section 4 the same quantity is additive and public, folded by anyone from the chains.

## 6. Aggregate supply and its asymptotics

### 6.1 The supply function

Let the participants be born at seconds b_1 ≤ b_2 ≤ … and let L(t) be the number of them with b_k ≤ t.
Under Theorem 1 (keys born after TX_TIME_CUT) and under Theorem 2 at the target length of a window,
each living participant is credited one coin per second, so

```
S(t) = Σ_{k : b_k ≤ t} (t − b_k)                        (discrete)
ΔS(t) = S(t + 1) − S(t) = L(t + 1)                     (one coin per living participant per second)
```

The second line is the whole monetary rule in one identity: the money supply grows each second by the
number of people alive in it. S has no ceiling: as long as L ≥ 1, S is strictly increasing, which is
the «supply never decreasing» of the constitutional layer. S also has no floor other than zero: a
network of no one mints nothing.

### 6.2 The asymptote of the rate

Define the relative growth over the next year in basis points, in integers:

```
ρ_bp(t) = ⌊ 10 000 × ( S(t + Y) − S(t) ) / S(t) ⌋
```

**Theorem 3 (asymptotic disinflation).** If the population is bounded, 1 ≤ L(t) ≤ L_max for all t ≥
t_0, then ρ_bp(t) → 0 as t → ∞, and for a constant population L the exact value is

```
ρ_bp(t) = ⌊ 10 000 × Y / (t − t_0) ⌋
```

independent of L. Proof. For constant L born at t_0, S(t) = L (t − t_0) and S(t + Y) − S(t) = L Y, so the
ratio is Y / (t − t_0). In general S(t + Y) − S(t) ≤ L_max Y while S(t) ≥ Σ (t − b_k) ≥ L(t_0)(t − t_0) ≥
(t − t_0), so the ratio is at most L_max Y / (t − t_0) → 0. ∎

The author's book states the same law in words (chapter 50, «Service», line 163):
«The total number of coins grows linearly. Inflation falls asymptotically to zero — a constant emission
is divided by a growing volume. After a year — one hundred percent. After ten — ten. After a hundred — one.
After a thousand — tenths.» The computed values for a constant population (Appendix A, V-G):

| Age of the system | Growth over the next year, basis points | As a percentage |
|---|---|---|
| 1 year | 10 000 | 100 % |
| 2 years | 5 000 | 50 % |
| 10 years | 1 000 | 10 % |
| 50 years | 200 | 2 % |
| 100 years | 100 | 1 % |
| 1 000 years | 10 | 0.1 % |

With a population growing at a constant rate β per second from t_0 (one key per second in the vector
of Appendix A, V-F), S(T) = β T (T + 1) / 2 and the relative growth falls as 2 / T: slower by a factor
of two, still to zero. Whatever the demography, as long as humanity is finite, the inflation rate of
Montana is asymptotically zero. The stock is unbounded and the rate vanishes: this is the first
asymptote of the model.

### 6.3 Classification of the limit

Three classes of emission rules are distinguished by the limits of the stock S and of the relative
rate ρ:

1. **Bounded stock, vanishing rate.** The Nakamoto schedule: S → 20 999 999.9769 BTC (Appendix A,
   V-J), ρ falls geometrically by halving. The scarcity is in the stock.
2. **Unbounded stock, vanishing rate, constant absolute flow.** The Monero tail emission: 0.6 XMR per
   two-minute block for ever, S linear, ρ ~ 1 / t. The flow is a constant of the protocol and does not
   depend on how many people use it.
3. **Unbounded stock, vanishing rate, flow equal to the living population.** Montana: ΔS = L, S ~ ∫ L,
   ρ ~ L / ∫ L. The flow is not a constant of the protocol but the count of people, and the per-capita
   flow is the constant: one coin a second to everyone, at every size of the network (Theorem 2).

Class 3 is the one in which the per-capita stock, and not only the aggregate rate, has a limit. That
is the second asymptote.

### 6.4 The asymptote of the person

By Theorem 1 a key of age x holds at most x coins of emission. A person's life bounds x. In Julian
years (Appendix A, V-H):

| Lived time | Coins of emission | In Montana (10^9 coins) |
|---|---|---|
| 1 day | 86 400 | 0.0000864 |
| 1 Julian year | 31 557 600 | 0.0315576 |
| 31 years 251 days 7 h 46 min 40 s | 1 000 000 000 | exactly 1 |
| 80 years | 2 524 608 000 | 2 and 524 608 000 coins |
| 100 years | 3 155 760 000 | 3 and 155 760 000 coins |

One Montana is 11 574 days, 1 hour, 46 minutes and 40 seconds of life. A century is three Montana and
a little more. No person, by emission alone, ever holds a fourth banknote. The per-capita stock
converges to the length of a life, and the aggregate stock to the summed lifetimes of everyone who
ever lived in the network. In a stationary population of L people each living λ seconds, the stock
converges to L λ / 2 on average per cohort and the share of one person to 1 / L: the distribution of
emission is, in the limit, perfectly equal and bounded above by mortality.

The levels the client shows are the digits of π in coins (`MTWalletCore.swift:326-342`, «Box n holds
the first n digits of π as whole coins — 3, 31, 314 … 3 141 592 653 589 — each a share of a Montana»).
Read against one coin a second they are durations of a life (Appendix A, V-H):

| Level | Coins | Lived time by emission |
|---|---|---|
| 6 | 314 159 | 3 days |
| 7 | 3 141 592 | 36 days |
| 8 | 31 415 926 | 363 days |
| 9 | 314 159 265 | 9 years 348 days |
| 10 | 3 141 592 653 | 99 years 201 days |
| 11 | 31 415 926 535 | 995 years |
| 13 | 3 141 592 653 589 | 99 551 years |

Levels 10 and above are not reachable from one key's emission within a human life. They are reachable
only by transfers, that is by what other people chose to give for one's time. The client already
states the principle: «THE LEVEL IS A READING, NEVER A RATE» (`MTWalletCore.swift:343-346`). This table
is its arithmetic.

### 6.5 The equation of exchange in a time-denominated economy

Fisher's equation of exchange, M V = P T, relates the money stock M, its velocity V, the price level P
and the volume of transactions T. In Montana the unit of account is a second of life, so a price is
a number of seconds and the stock M is the lived time of the population not yet spent. If velocity and
the real volume of transactions per person are stationary, the equation says that the price level in
seconds grows with the per-capita stock, that is with the age of the population in the network, and
stops growing when the population is stationary and mortality balances emission (section 6.4). The
rule therefore produces a price level that converges rather than a price level that falls without
bound as in a capped currency, or one that rises without bound as under a constant-percentage rule.
This paragraph states what follows from the identity under its assumptions. It is not a prediction:
V and T are not quantities of the protocol, and the set measures neither.

## 7. Equilibrium and properties

The role requires an equilibrium analysis of every monetary mechanism before it is called valid
(actor classes, the equilibrium of their strategies, viability at the start, stability in the long
run). The rule is simple enough for the analysis to be short, and the shortness is the result.

### 7.1 Actors and strategies

- **A person** owns a seed, hence one coin key (drawn by role from the seed, COIN-TX-V3, section 10),
  and devices that run the client.
- **A device** folds, shows, sends and keeps copies. Since fold-6 it mints nothing (Theorem 1).
- **A chain node** orders the records of the keys in its half of the table and folds them by the core.
  It mints nothing either: `time_step` is a function of `birth` and `at`, and the node's only
  discretion is `at`, its own second, which section 10.1 treats.
- **A holder** keeps a replica and signs roots. A signature proves what the holder folded, not that it
  is independent (COIN-TX-V3, section 12).
- **An adversary** controls many seeds, many devices, perhaps a node of its own.

**Proposition 1 (existence is dominant).** In the emission game of the application layer, the payoff of
a key over any interval is the length of the interval (Theorem 1) whatever action its owner takes. No
strategy of a single key strictly improves on doing nothing, and no strategy worsens it short of
spending. The game of one key is trivial and its unique equilibrium is to exist.

**Proposition 2 (the only lever is the count of keys).** The payoff of an adversary over an interval
of length T is n T where n is the count of keys it has had alive over the interval. The emission game
of the layer is therefore the game of creating keys, and section 8 is its analysis.

In the consensus layer the same two propositions hold with «key» replaced by «admitted living
machine»: the right of a window is the same for every living machine (`Consensus.md:344-347` on the
branch, «Every living machine holds the same right to a window's seconds»), it does not depend on duty
(`:479-480`), the runner on duty earns nothing for running (the constitutional layer: «no personal
reward to the runner»), and nothing a machine runs adds to it (`:1065`).

### 7.2 Viability at the start

A capped currency pays its first participants most and relies on fees once the cap is near. Montana
has no fees as a protocol notion (`docs/Montana App.md:56-62`), so a cap would leave the machines that
carry the network unpaid at the end. One second, one coin pays the same rate on the first day and on
the ten-thousandth: the first participant earns one coin a second and so does the billionth. The
young network does not mint faster than the old (Theorem 2 and `Canon.md:4802-4806`), so there is no
early-adopter premium in the consensus layer. In the application layer there is a named legacy: keys
that minted under A_2 before 20.10.2026 hold up to 26 coins a second of that period and mint nothing
more until their life covers it (section 10.3).

Under the fixed mint of Canon 4.2.0 the first participants would have received 13 × 10^9 coins a
window each while they were few (section 5.4). The author's word of 21.10.2026 removes that premium.

### 7.3 Stability in the long run

- **No cliff.** There is no halving, no final block, no change of rule at any height (the
  constitutional layer, 2.5). The function S is piecewise linear with slope L and no discontinuity of
  slope other than births and deaths.
- **Vanishing inflation without a cap.** Theorem 3. The holders of coins are not diluted faster than
  the population grows, and in a stationary population the dilution of one person's share tends to the
  mortality rate.
- **Monotone supply.** No burn at the protocol level, no decay of a balance, no demurrage. A lost key
  freezes its coins for ever and nothing reclaims them, so the circulating supply is at most S(t) and
  unknown (section 10.4).
- **No treasury.** The remainder of a division is carried forward and never appropriated (Canon 4.2.0)
  or does not arise (Canon 5.0.0, where the worth is per machine and nothing is divided).

### 7.4 Fee-less by construction, time-based by construction

The constitution of the set holds anti-spam, anti-bloat and anti-Sybil defences to time-based
primitives exclusively (`docs/Montana Constitution.md:247-252` on `feat/s3-stage1`, [I-12] «Time-based
scarcity»: «The scarce resource of the protocol is time: the TimeChain, the window periods, the chain
length of a machine, the activity of a record, the continuity of life»). The role of the architect
names the same invariant I-15 in its own list. The emission rule is the monetary face of that
invariant: the thing the network pays for is the thing it rations with.

### 7.5 On the deflationary sink

The role of the architect lists an invariant I-13, «Deflationary sink — paid services burn, not a
treasury». The seven documents of the consensus set carry no burn: the constitutional layer forbids
«protocol-level burning» (`Constitution.md:807-809`), the closing of an identity record «burns not one
coin» (`docs/Montana Identity.md:179-183`), and an application charges by ordinary transfers between
people (`App.md:56-58`). The application layer's chain has no record kind that destroys coins. The sink
of I-13, if it exists, lives in the applications and their services, outside the protocol, and this
paper models none, because none is in the set. Section 11, question 3.

## 8. Sybil resistance by time

Proposition 2 makes the whole security of the emission rule the cost of a second living participant.
The set answers differently in its two layers, and this section states both answers with their
numbers.

### 8.1 The application layer: keys are free, and the set says so

A fresh key opens its chain by a GENESIS of 0, its only free record (COIN-TX-V3, section 7). Births
are counted node-wide: TX_BIRTHS_PM = 120 a minute a node (`montana-node-store.py:711`), that is
172 800 keys a day a node and 345 600 a day on the two chain nodes of the table. By Theorem 1 each of
them earns one coin a second from its birth. An adversary that opens 172 800 keys on one node in a day
holds, a day later, 172 800 × 86 400 = 14 929 920 000 coins, fourteen Montana and 929 920 000 coins, and
twice that from both nodes. The set names this openly (`Audit/COIN-TX-V3.md`, section 12, «MINTING
STANDS ON A KEY'S AGE, AND KEYS ARE FREE — the critic's P-1 of Agent 95, 19.10.2026, open») and names
the closure: the consensus layer, where «a coin is born of witnessed time, not of a key's age».

The bound of the application layer is therefore a bound per key and not per person. Its honest
statement is: the emission of one key cannot be accelerated (Corollary 1), the emission of one person
can be multiplied by the count of keys the two nodes admit, 345 600 a day. The two nodes' pace table
(section 7 of COIN-TX-V3) is a rate limit and not a cost: a rate limit bounds the slope of the attack,
not its integral.

### 8.2 The consensus layer: admission is priced in time

In the consensus set a right is extinguished only by walking to a leaf of the tree of admitted
machines (`docs/Montana Canon.md:2790` on `feat/s3-stage1`: «A redemption of a right walks to a leaf
of the tree of admitted machines. Without that walk the nullifier binds nothing a network can check
[...] That is a mint, and the walk is what closes it»). Admission to that tree is the gate, and the
set states its price (`docs/Montana Consensus.md:1028-1041` on `spec/mint-second-99`):

> reachability is bought with sockets and bytes rather than with anything that cannot be multiplied,
> so a thousand processes on one machine would answer as a thousand living machines and take a thousand
> rights. What cannot be multiplied is a place in the tree of admitted machines, which costs a lived
> continuity period and a one-time right to raise a machine, and admission to which runs at the bounded
> rate a selection event fixes.
>
> Common ownership of several machines is not detected by this protocol and this protocol does not
> undertake to detect it. What bounds it is price and not detection, and the price is time: every
> claimant passes the continuity gate before a candidacy stands, every admission spends a one-time
> right that names nobody, and the rate of admission is bounded per event. A barrier of time rather
> than of money is the choice this set makes everywhere, and it is the choice here.

With the durations of section 5.2 the price of one more paid machine is: a continuity period of 14
segments of one day with at least 2 of 3 present (14 days of lived presence before a candidacy
stands), a one-time right to raise a machine, and a place in an admission that runs once per
selection interval of 5 h 36 min at a rate the Decree bounds (`admission_divisor` 130,
`adaptive_entry_threshold` 1 over 100, `adaptive_entry_multiplier` 100, `max_entry_segments` 56). A
candidacy expires after 42 days and a membership term lasts 28 days.

**Proposition 3 (the adversary's emission is bounded by admission, not by money).** Let a(T) be the
count of machines an adversary has had admitted by time T. Its emission by T is at most Σ over its
machines of their admitted lifetimes, hence at most a(T) × T. The admission rate per selection event
is bounded by the Decree and the continuity gate delays the first admission of any machine by at
least the continuity period, so a(T) = 0 for T below 14 days and a(T) grows at most linearly in T
afterwards at the admission rate, whatever the adversary spends. Its emission therefore grows at most
quadratically in T, and no expenditure of money or computation raises the exponent or the constant.
∎

The proposition states the shape of the bound. Its constant, the count of admissions a selection event
admits, is a function of the population and of the rows named above, and this paper does not compute
it: the adaptive entry rule reads the state of the network, and a number computed here from an assumed
population would be a number from memory.

### 8.3 What the price of time does and does not buy

- It buys a bound on the rate of growth of the adversary's share, and it makes the bound the same for
  the rich and the poor adversary, which is the point of the choice.
- It does not buy detection: n machines of one owner are n living machines once admitted, and they
  earn n coins a second for as long as they live. The set says so, and this paper repeats it rather
  than claiming otherwise.
- It does not buy anything in the application layer today: the two chain nodes admit keys at a rate,
  not at a price, and the closure is the move of the coin to the consensus layer (section 8.1).

## 9. Comparison with other monetary rules

The comparison states the published rule of each system and the limit it implies, and nothing about
their prices. The numbers for the other systems are computed from their published rules by the
program of Appendix B.

### 9.1 The table

| Rule | What is scarce | Flow per unit time | Limit of the stock | Limit of the rate | Per-capita bound | Fees | Burn |
|---|---|---|---|---|---|---|---|
| Nakamoto 2008, schedule of the reference implementation | computation | 50 × 2^−i coins a block, halving every 210 000 blocks | 2 099 999 997 690 000 satoshi (33 eras) | geometric to zero | none | required, the stated successor of the subsidy | none at protocol level |
| Monero tail emission | computation | 0.6 XMR a block of 120 s, for ever | none, linear | 1 / t | none | yes | none |
| Ethereum after EIP-1559 and the merge | stake | issuance grows with the square root of the stake, base fee burned | none, may fall | may be negative | none | yes, base fee plus tip | the base fee |
| Friedman's k-percent rule | a rule of the issuer | k % of the stock a year | none, exponential | constant k | none | n/a | n/a |
| Montana, Canon 4.2.0 | time (a window) | 13 × 10^9 coins a window to the living equally | none, linear in windows | 1 / t | none, 1 / L per window | none | none |
| Montana, Canon 5.0.0 and COIN-TX-V3 | lived time | L coins a second | none, the integral of the population | L / ∫L → 0 | one coin a second, a lifetime | none | none |

### 9.2 The Nakamoto schedule

The incentive section of the 2008 paper describes a block reward as the way coins enter circulation
and names the transition to fees once a predetermined number of coins exists. The schedule itself is
in the reference implementation: 50 coins a block, halved every 210 000 blocks, the subsidy truncated
to a whole satoshi. Summing the schedule in integers (Appendix A, V-J) gives 2 099 999 997 690 000
satoshi over 33 eras, 20 999 999 coins and 97 690 000 satoshi: the famous 21 million is an upper bound
the sum never reaches, because truncation loses 2 310 000 satoshi over the schedule. The scarcity is a
constant of the code, in the words of the author's book (chapter 82, line 41: the scarcity
of the Nakamoto coin is set by a number in the code, the scarcity of the time coin is set by time
itself). Axiom A3 puts one Montana of 10^9 coins level with one such unit, which has 10^8 satoshi: a
Montana is divided ten times finer than the unit it is set against, and its subunit has a physical
meaning the satoshi lacks.

### 9.3 The Monero tail

Monero pays a fixed 0.6 XMR a block of two minutes without end, having reached the tail of its earlier
decreasing schedule in 2022. Per Julian year that is 262 980 blocks and 157 788 XMR (Appendix B). The
stock is linear and the rate falls as 1 / t: the same limit class in the rate as Montana (section 6.3),
but the flow is a constant of the protocol per block, independent of the count of users, so the
per-capita flow falls as the network grows. In Montana the per-capita flow is the constant and the
aggregate flow follows the people.

### 9.4 Ethereum after EIP-1559

EIP-1559 (London, August 2021) burns the base fee of every transaction, and the issuance to validators
after the merge grows with the square root of the total stake. Net issuance may therefore be negative
when fees are high. This is the opposite construction to Montana on two counts: a fee is a protocol
notion there and is forbidden here (`App.md:56-62`), and a protocol-level burn exists there and is
forbidden here (`Constitution.md:807-809`). The architect's invariant I-13 names a burn of paid
services. Where it applies, it applies to applications and not to the protocol (section 7.5).

### 9.5 Fisher, Friedman, Hayek

Fisher's identity is applied in section 6.5. Friedman's k-percent rule fixes the growth of the stock
at a constant percentage, an exponential stock and a constant rate, chosen so that a rule and not a
committee governs money. Montana shares the motive, a rule fixed at genesis that no later act may
change (the constitutional layer), and inverts the shape: a constant absolute flow per person, a
stock linear in population-time and a rate that vanishes. Hayek's competing private currencies
without a central issuer answer the question «who decides the rule»: in Montana no one decides it
after genesis, and the only competition is the one Hayek wanted, between currencies at an exchange.
The set already builds that exchange (COIN-TON on `spec/coin-swap-ton-78`, a pair of TCM against
Gram with the price the owner's own answer to «how much is your hour now»).

### 9.6 Gesell and Cahn: time as decay, time as unit

Gesell's demurrage makes money lose value with time to force it to circulate. Montana is the exact
inverse: time pays the holder of a life, and a held coin loses nothing (section 7.3). Cahn's time
banking makes the hour the unit and declares every hour equal. Montana makes the second the unit at
emission (every second of every life pays one coin, which is Cahn's equality at the source) and
leaves the exchange rate of a person's time to that person (COIN-TON, section 4, `price =
hour_nanogram div 3600`). The equality is in the issuance, the inequality is in the market, and the
set states both without pretending that the second cancels the first.

### 9.7 Szabo's bit gold and unforgeable costliness

Bit gold made a unit costly to create by a computation that cannot be reused, and valuable by that
cost. Montana makes a unit costly to create by a second of life that cannot be relived, witnessed by
the network (consensus layer) or by the chain node's clock (application layer). The costliness is
unforgeable in the same sense, and the resource is one every person has in equal measure, which no
computation is. The price of that choice is section 8: a life is unforgeable, a key is not, and the
set must witness the one and not the other.

### 9.8 Stock-to-flow and the method of this paper

The stock-to-flow model of 2019 fitted a price to the ratio of stock to annual flow and was criticised
for fitting the past rather than predicting. This paper makes no price claim and fits nothing. Every
quantity in it is a theorem about a rule or a computation from it, and the rule is the one the set
publishes with its target, its derivation, its sensitivity and its defence (Canon 5.0.0, `:659-690`).
Where the set does not publish a number (the admission count per event, section 8.2), the paper
publishes no number either.

## 10. Attacks and the limits of the model

Every limit below is named in the set or found in this analysis. None is claimed closed that the set
does not close.

### 10.1 The clock of the application layer

The consensus layer reads no clock ([I-15] of the Constitution, `Constitution.md:336-340`). The
application layer does: a record's `at` is the chain node's second, and `birth` is the `at` of the
first record. Theorem 1 is therefore exact with respect to the node's clock and not to physical time.
Two chain nodes hold the table (COIN-TX-V3, section 2), and every replica, phone and the Explorer
re-fold their records with the `at` the node wrote, so a node that moved its clock forward would be
caught by nothing in the fold and by every replica that compares its own second to the node's. The
model's honest statement: in the application layer the second is the node's, and the trust in the
node's second is the deviation from [I-15] that the move of the coin to the consensus layer removes.

### 10.2 A key born in the past

A birth is the `at` of a first record, set by the node, never by the signer (section 1 of COIN-TX-V3
names the signer's `birth` field as «shown, never counted»). A key cannot be born in the past. A key
that opened its chain early and did nothing mints the same as a key that did everything: Corollary 1.

### 10.3 The named legacies of the application layer

- **MINTs taken before TX_SECOND_CUT stand** at up to 26 coins a second under A_2 (section 4.3). A key
  that minted 3 000 000 in its first seven days (604 800 seconds) mints nothing more until its life
  reaches its 3 000 000th second, about 34.7 days (COIN-TX-V3, section 4). The excess over lived time
  at the cut is measured on the nodes, not assumed (section 12 of the same document).
- **A GENESIS above 0 taken before TX_GENESIS_GATE** (18.10.2026 20:15 UTC) could announce up to
  TX_GENESIS_CAP = 110 040 864 declared coins on a key with no past. Declared coins are spent after
  proven, are never called proven, and stay declared in every chain they reach (section 3). The count
  of such announcements is measured on the nodes.
- **A v2 record whose receiver minted its credit** before the sender's REFUND took the record back
  (fold-4) leaves those coins standing twice: at most 17 records and 11 045 606 coins since 12.10.2026
  (section 12).

These three are finite, dated and bounded, and S(t) of section 6 holds up to them.

### 10.4 Frozen coins and the circulating supply

Nothing in either layer destroys a coin, and nothing reclaims a coin whose key is lost. The
circulating supply is therefore at most S(t), and the difference is unobservable: the set holds no
liveness of a key as a protocol quantity in the coin chain. In the consensus layer even S(t) is
unobservable (section 5.5). The model of section 6 is a model of issuance, not of circulation.

### 10.5 Floor loss in the consensus layer

A window that does not reach a whole second of Montana pays nothing for the fraction (Theorem 2). The
loss is strictly less than one coin per machine per window and is not carried forward in Canon 5.0.0.
Over a day of 1 440 windows at the target length the loss is zero (284 rounds pay exactly 60). Below
the target it is at most 1 440 coins a day a machine, under 1.7 % of a day's 86 400, and it is the
price of never rounding up.

### 10.6 Parallel chains and the count k

The worth divides by the count of chains k in force (section 5.1), so a network of k chains pays a
window's seconds once and not k times. A wrong implementation that forgot k would pay 120 coins for
568 rounds over two chains (Appendix A, V-E).

### 10.7 What a signature of a holder proves

A holder's signature on a root proves what that holder folded, and one person may run many holders
(COIN-TX-V3, section 12). The quorum of the Explorer counts signatures. The proof a visitor needs no
one else for is the fold of the chain itself, which the Explorer performs in the browser.

### 10.8 The limits of the asymptote

Theorem 3 assumes a bounded population. It is a theorem about the real population of a finite
planet, not about the count of keys an adversary can open (section 8.1): in the application layer as
it stands the «population» of keys is bounded only by the nodes' birth rate, and S(t) can be made to
grow faster than the people. The asymptote of section 6.4 (a person holds at most a lifetime of coins)
is a theorem about a key and becomes a theorem about a person only in the consensus layer, where a
machine costs lived continuity and an admission. The model is therefore exact for the consensus rule
and conditional for the application rule, and the condition is the one the set itself names open.

## 11. Open questions for the author

Where the constitution of the council, the specification and the code do not say the same thing,
this paper names the difference and decides nothing.

1. **The genesis row of the global TimeChain.** Canon 4.2.0 on `feat/s3-stage1` carries
   `emission_schedule (0, 13 000 000 000)` (`Canon.md:4480`), and Montana Core 0.19.0 encodes and
   divides it (`attest.rs:279-301`). Canon 5.0.0 on `spec/mint-second-99` carries `window_seconds 60`
   (`Canon.md:4741`) and Core 0.20.0 under it. The author's word of 21.10.2026 13:5x UTC («no 13
   billion») names the direction. The decision line 41 of the council (22.10.2026 12:53 UTC) names the price,
   a new Genesis State Hash and a new genesis of the global TimeChain, and stands at `decide` without a
   `decided` row. This paper models both rules (sections 5.3-5.4).
2. **What TCM names.** Article 12 of the constitution makes TCM the ticker of the Coin (one second).
   COIN-TON on `spec/coin-swap-ton-78` builds the jetton TCM with decimals 0, one unit a second. The
   author's word of 19.10.2026 14:4x UTC («1 Coin = 0.000000001 TCM = 1 s») and the client since build
   2250 (`MTWalletScreen.swift:156-159`: «coins, never TCM (a TCM is a billion of them)»;
   `MTWalletCore.swift:2751`, the ticker, and `:174`, `coinsPerMontana`) make TCM the billion-coin
   unit, the Montana of article 13. One name, two units.
3. **The deflationary sink.** The architect's invariant I-13 names a burn of paid services. The
   constitutional layer forbids protocol-level burning and the set carries no burn (section 7.5).
   Either I-13 is an invariant of the applications only, and the role should say so, or the set lacks
   a mechanism it is meant to have.
4. **Two numberings of the invariants.** The role's list I-1..I-16 and the Constitution's [I-1]..[I-18]
   number the same territory differently: time-based scarcity is I-15 in the role and [I-12] in the
   Constitution (`Constitution.md:247`), state lifecycle is I-14 and [I-11] (`:217`), and [I-15] of the
   Constitution is «No external time inside the protocol» (`:336`). A public text must say which list
   it cites. This paper cites the Constitution's numbers in brackets and the role's without.
5. **The encoding of the emission row in the retired tree.** `Code/crates/mt-genesis/src/lib.rs:45,75`
   (the tree whose VERSION.md targets the retired Protocol v36.1.0) writes `emission_moneta` as a bare
   u128, while Canon requires a two-byte count of rows followed by (height, mint) pairs
   (`Canon.md:4557-4559`). `Montana-Core/crates/mt-genesis/src/lib.rs:5-8,69-75` encodes by Canon. The
   two trees agree numerically only while the schedule has one row at height 0. The retired tree is a
   second source of truth of a consensus constant while it stays in the repository.
6. **The word «asymptotic».** The only saturating emission curve the set ever carried, A_2 (section
   4.3), was retired by the author on 19.10.2026. Under the rule in force the asymptotes are the
   vanishing inflation rate (Theorem 3) and the lifetime bound of a person (section 6.4). The author
   is asked to confirm that this is the asymptotic emission the task names, so that the title of the
   work and its frame are the author's and not the paper's.
7. **The clock of the application layer** (section 10.1) is a reading of a node's clock inside a rule
   that bounds money. It is a deviation from [I-15] of the Constitution, named in COIN-TX-V3 as the
   closure the consensus layer brings, and this paper asks whether it is to be recorded in the
   deviation tracker of the code (C-10) until the coin moves.
8. **Keys are free** (section 8.1, P-1 of Agent 95, open since 19.10.2026). The application layer's
   emission is bounded per key and not per person, and the two chain nodes admit 345 600 keys a day.
   The set names the closure. The question is the date.

## 12. Conclusion

One second, one coin is a monetary rule with no parameters to tune: the coefficient is one, the
exponent is one, the ceiling is a lifetime, and the only remaining question of economics, who counts
as a person, is answered by the set with time and not with money. The rule's aggregate supply is the
lived time of its people, its inflation rate falls as the inverse of its age, and no action of any
participant moves either. The paper has proven these statements in integers, reproduced the vectors
of the set and added its own, and named every place where the set is still in motion.

## Appendix A. Test vectors

Every vector was computed by the program of Appendix B. Each family names the wrong implementation it
refuses. Vectors marked «set» reproduce vectors the set publishes at the cited place and were
recomputed here.

**V-A. A(x) = x, the allowance under one second, one coin (section 4.1).**
A(0) = 0, A(60) = 60, A(86 400) = 86 400, A(1 000 000 000) = 1 000 000 000. Refuses: the doubling rule
after the cut (A_2(86 400) = 2 213 664), counting the second of birth as the first paid second plus one
(A(60) = 61), and a rule that pays a level above one (any multiple of x).

**V-B. allowance(t1) = A(t1 − birth) − minted (section 4.1, set: COIN-TX-V3 V11).**
Key L born at C − 100, C = TX_SECOND_CUT. MINT 100 over [b, b + 300) at C + 200: allowance 300 − 0 =
300, taken. MINT 250 over [b + 300, b + 360) at C + 500: 360 − 100 = 260, taken. MINT 71 over [b + 360,
b + 420) at C + 500: 420 − 350 = 70, refused. MINT 70 there: taken, minted 420. Refuses: weighing a MINT
by its own interval alone (the 250 refused, the interval allows 60), forgetting what the key minted
(the 71 taken), and choosing the rule by t1 instead of at (key K of the set's V11: a MINT of 1 over
[b + 6 800, b + 6 870) at C + 10 on a key that minted 140 000 before the cut is refused, 6 870 − 140 000
below zero, while A_2(6 870) − 140 000 = 8 526 would take it).

**V-C. The time step (section 4.2, set: COIN-TX-V3 V12).**
Key T born at D − 1 000, D = TX_TIME_CUT. MINT 300 at D − 500: proven 300, minted 300. SEND 1 000 at
D + 100: the step first folds lived 1 100, proven 300 + 800 = 1 100, minted 1 100, then the SEND, proven
100. MINT 1 over [b + 400, b + 1 060) at D + 200: the step sets minted 1 200, allowance 1 060 − 1 200 below
zero, refused, the state stands at proven 100, minted 1 100. Read at D + 300: proven 300, minted 1 300.
Key K of V-B, birth C − 7 000, minted 140 000: its SEND of 1 at D (D − C = 259 200) folds lived 266 200,
proven 140 000 + 126 200 − 1 = 266 199. Refuses: a fold with no time step (the SEND refused, overspend on
300), the step applied after the kind (the same refusal), crediting the seconds without subtracting
the MINTs (T proven 400 after the SEND, K 406 199), applying the step before D (the MINT of 300 at D −
500 refused), and a balance read from the head's state alone (proven 100, minted 1 100).

**V-D. A_2(x), the doubling rule (section 4.3, set: COIN-TX-V3 V3).**
1:2, 2:4, 3:6, 4:10, 7:22, 8:28, 15:70, 16:78, 8 191:180 230, 8 192:180 256, 8 193:180 282,
86 400:2 213 664, and TX_GENESIS_CAP = A_2(4 233 600) = 110 040 864. Refuses: a level of bit_length(s)
without the minus one (A_2(2) = 6), a level rounded up (A_2(3) = 8), the factor 2 left out (every value
halved), seconds counted from 0 (A_2(1) = 4), and a ceiling other than 13 (A_2(8 193) − A_2(8 192) must
be 26).

**V-E. window_value(r, k) = ⌊60 r / (284 k)⌋ (section 5.1, set: Consensus 5.0.0 :1067-1079).**
(284, 1) = 60, (71, 1) = 15, (300, 1) = 63, (5, 1) = 1, (4, 1) = 0, (568, 2) = 60, (142, 2) = 15, and
two of this paper's own: (283, 1) = 59, (289, 1) = 61. Refuses: a fixed coin per window (71 rounds
paying 60), a worth of a round rounded before the multiplication (284 rounds paying 0), the count of
chains left out (568 rounds over two chains paying 120), and a worth rounded up (300 rounds paying 64,
4 rounds paying 1, 283 rounds paying 60).

**V-F. S(T) with one birth a second from second 0 (section 6.1).**
S(1) = 1, S(2) = 3, S(10) = 55, S(60) = 1 830, S(3 600) = 6 481 800, S(86 400) = 3 732 523 200 = 86 400 ×
86 401 / 2. Refuses: the continuous approximation T² / 2 (50 at T = 10), counting the key born at T as
having lived a second (S(1) = 2), and a floating-point sum (any value that is not the integer).

**V-G. ρ_bp(t) for a constant population (section 6.2).**
At ages of 1, 2, 10, 50, 100 and 1 000 Julian years: 10 000, 5 000, 1 000, 200, 100, 10 basis points.
Refuses: dividing by the stock at the end of the year instead of its start (5 000, 3 333, 909, 196,
99, 9), and any dependence on L (the values are the same for L = 1 and L = 10^9).

**V-H. The banknote and the lifetime (section 6.4).**
10^9 s = 11 574 days 1 h 46 min 40 s = 31 Julian years and 21 714 400 s (251 days 7 h 46 min 40 s).
100 Julian years = 3 155 760 000 coins = 3 Montana and 155 760 000 coins. 80 years = 2 524 608 000 = 2
Montana and 524 608 000. Level 8 of π = 31 415 926 coins = 363 days. Level 10 = 3 141 592 653 coins =
99 Julian years and 201 days. Refuses: a year of 365 days (10^9 s would be 31 years and 255 days, a
century 3 153 600 000), a Montana of 10^8 coins (the subunit count of the unit it is set against), and
a level table read as a rate.

**V-I. The equal share of a fixed mint (section 5.3).**
⌊13 × 10^9 / L⌋ with carry: L = 1: 13 000 000 000, carry 0. L = 3: 4 333 333 333, carry 1. L = 7:
1 857 142 857, carry 1. L = 13: 1 000 000 000, carry 0. L = 10^6: 13 000, carry 0. The meeting point
L* = ⌊13 × 10^9 / 60⌋ = 216 666 666, remainder 40. Refuses: a share rounded up (L = 3 paying
4 333 333 334), a carry dropped, and a share in floating point.

**V-J. The Nakamoto schedule summed in satoshi (section 9.2).**
Σ over eras i ≥ 0 of 210 000 × ⌊50 × 10^8 / 2^i⌋ while the subsidy is positive = 2 099 999 997 690 000
satoshi over 33 eras = 20 999 999 coins and 97 690 000 satoshi. Refuses: 21 × 10^6 coins exactly (the
sum without truncation), 32 eras (the era with a subsidy of one satoshi left out), and a sum in
floating point.

**V-K. The adversary of the application layer (section 8.1).**
120 births a minute a node × 1 440 minutes = 172 800 keys a day a node. A day later they hold 172 800 ×
86 400 = 14 929 920 000 coins = 14 Montana and 929 920 000 coins. Refuses: a bound that counts seconds
and not keys (86 400 coins), and one that forgets the second node (the table has two).

## Appendix B. The reference program

Every number of this paper is printed by the program below, in integer arithmetic. It depends on
nothing outside the Python standard library and uses no floating-point operation. The formulas it
recomputes belong to the places cited beside them. The program is the paper's own check and not a
second home of any constant of the set.

```python
# Montana tokenomics, the numbers of the paper. Integers only.
Y = 31557600            # seconds of a Julian year, 365.25 days
M = 10 ** 9             # coins of one Montana (constitution, article 13)
TX_V2_CUT = 1792443600  # mt-coin lib.rs:14, 19.10.2026 21:00 UTC
TX_SECOND_CUT = TX_V2_CUT
TX_COIN_EPOCH = 1788210000   # lib.rs:17, 31.08.2026 21:00 UTC
TX_TIME_CUT = 1792702800     # lib.rs:19, 22.10.2026 21:00 UTC
WINDOW_SECONDS, TARGET_ROUNDS = 60, 284   # Canon 5.0.0 :4741, :4773

def a2(x):
    # COIN-TX-V3 section 4, mt-coin lib.rs:389-406: the doubling rule before the second's cut
    total, lo, k = 0, 1, 0
    while lo <= x:
        hi = min(x, 2 * lo - 1)
        level = 1 if k < 1 else (13 if 13 < k else k)
        total += (hi - lo + 1) * level
        lo *= 2
        k += 1
    return 2 * total

def allowance(lived, at):
    # lib.rs:410-416
    return lived if TX_SECOND_CUT <= at else a2(lived)

def time_step(proven, minted, birth, height, at):
    # lib.rs:420-430, fold-6
    lived = max(0, at - birth)
    if at < TX_TIME_CUT or height == 0 or lived <= minted:
        return proven, minted
    return proven + lived - minted, lived

def window_value(r, k):
    # Canon 5.0.0 :673, Consensus 5.0.0 :1058
    return (WINDOW_SECONDS * r) // (k * TARGET_ROUNDS)

def supply_one_birth_a_second(T):
    return sum(T - b for b in range(T))

def growth_bp(age_seconds):
    # a constant population: growth over the next year in basis points
    return (10000 * Y) // age_seconds

def share(mint, living):
    return divmod(mint, living)

def nakamoto_satoshi():
    total, subsidy, eras = 0, 50 * 10 ** 8, 0
    while 0 < subsidy:
        total += 210000 * subsidy
        subsidy //= 2
        eras += 1
    return total, eras

def duration(seconds):
    d, r = divmod(seconds, 86400)
    h, r = divmod(r, 3600)
    mi, s = divmod(r, 60)
    return d, h, mi, s

assert [a2(x) for x in (1, 2, 3, 4, 7, 8, 15, 16)] == [2, 4, 6, 10, 22, 28, 70, 78]
assert [a2(x) for x in (8191, 8192, 8193, 86400)] == [180230, 180256, 180282, 2213664]
assert a2(TX_V2_CUT - TX_COIN_EPOCH) == 110040864
assert a2(8193) - a2(8192) == 26
assert [window_value(r, k) for r, k in ((284, 1), (71, 1), (300, 1), (5, 1), (4, 1), (568, 2), (142, 2))] == [60, 15, 63, 1, 0, 60, 15]
assert (window_value(283, 1), window_value(289, 1)) == (59, 61)

C, D = TX_SECOND_CUT, TX_TIME_CUT
# V-B, key L
b = C - 100
minted = 0
assert allowance(300, C + 200) - minted == 300
minted += 100
assert allowance(360, C + 500) - minted == 260
minted += 250
assert allowance(420, C + 500) - minted == 70
# V-C, key T
bT = D - 1000
proven, minted = 300, 300
proven, minted = time_step(proven, minted, bT, 2, D + 100)
assert (proven, minted) == (1100, 1100)
proven -= 1000
p2, m2 = time_step(proven, minted, bT, 3, D + 200)
assert (p2, m2) == (200, 1200) and allowance(1060, D + 200) - m2 < 0
assert time_step(proven, minted, bT, 3, D + 300) == (300, 1300)
# V-C, key K
bK = C - 7000
assert time_step(140000, 140000, bK, 2, D) == (266200, 266200)
assert D - C == 259200

assert [supply_one_birth_a_second(T) for T in (1, 2, 10, 60, 3600)] == [1, 3, 55, 1830, 6481800]
assert supply_one_birth_a_second(86400) == 86400 * 86401 // 2 == 3732523200
assert [growth_bp(y * Y) for y in (1, 2, 10, 50, 100, 1000)] == [10000, 5000, 1000, 200, 100, 10]
assert duration(M) == (11574, 1, 46, 40)
assert divmod(M, Y) == (31, 21714400)
assert divmod(100 * Y, M) == (3, 155760000)
assert divmod(80 * Y, M) == (2, 524608000)
assert [share(13 * M, L) for L in (1, 3, 7, 13, 10 ** 6)] == [(13 * M, 0), (4333333333, 1), (1857142857, 1), (M, 0), (13000, 0)]
assert divmod(13 * M, 60) == (216666666, 40)
assert nakamoto_satoshi() == (2099999997690000, 33)
assert divmod(2099999997690000, 10 ** 8) == (20999999, 97690000)
assert (Y // 120, 6 * (Y // 120) // 10) == (262980, 157788)
assert 120 * 1440 == 172800 and 172800 * 86400 == 14929920000
assert (20160 * 60, 1440 * 60, 336 * 60) == (1209600, 86400, 20160)
digits = "3141592653589793238"
levels = [int(digits[:n]) for n in range(1, 14)]
assert levels[7] // 86400 == 363 and divmod(levels[8], Y)[0] == 9 and divmod(levels[9], Y)[0] == 99
print("every number of the paper recomputed")
```

The program is executed by the author of this paper against the file as committed and prints its last
line. A reader who changes any constant of the set sees an assertion fail at the line that cites it.

## Bibliography

Works of the set, cited by path and line at the revisions of the front matter:

- [S1] The constitution of the Montana council. `CouncilWall/constitution.jsonl`, articles 11, 12, 13
  (lines 12-14), decision line 41.
- [S2] Coin record v3. `Audit/COIN-TX-V3.md`, sections 1-12.
- [S3] The fold of a coin key's chain. `Code/crates/mt-coin/src/lib.rs`, branch `core/mt-coin-231`.
- [S4] Montana Canon 4.2.0, Consensus, Constitution 3.12.0, Value, App, Identity. `docs/` of the protocol
  repository at `feat/s3-stage1`.
- [S5] Montana Canon 5.0.0, Consensus 4.0.0, Constitution 4.0.0, Value 3.7.0. The same files at
  `spec/mint-second-99`.
- [S6] Coin on TON: the TCM jetton, LEAVE and ARRIVE, the hour price. `Audit/COIN-TON.md` at
  `spec/coin-swap-ton-78`.
- [S7] The client. `Code/Montana/MTWalletCore.swift`, `Code/Montana/MTWalletScreen.swift`.
- [S8] The author's books. chapter 50 «Service», line 163;
  chapter 82, lines 41 and 119-125; chapter 77 «Money», lines 146 and 250-260 (Russian originals).

External works. The facts this paper takes from them are the published rules named in section 9, and
no quotation from them is made. The references were not re-read from their first editions during the
writing and should be checked against them before the paper leaves the council.

- [1] Nakamoto, S. (2008). Bitcoin: A Peer-to-Peer Electronic Cash System. Self-published, section 6, Incentive. <!-- FOREIGN-APP-OK: the title of the cited paper -->
- [2] The Monero Project. Tail emission of 0.6 XMR per block, in force since 2022. Monero protocol documentation.
- [3] Buterin, V., Conner, E., Dudley, R., Slipper, M., Norden, I., Bakhta, A. (2019). EIP-1559: Fee market change for ETH 1.0 chain. Ethereum Improvement Proposals.
- [4] Fisher, I. (1911). The Purchasing Power of Money. Macmillan, New York.
- [5] Friedman, M. (1960). A Program for Monetary Stability. Fordham University Press, New York.
- [6] Hayek, F. A. (1976). Denationalisation of Money. Institute of Economic Affairs, London.
- [7] Gesell, S. (1916). Die natürliche Wirtschaftsordnung durch Freiland und Freigeld. Selbstverlag, Les Hauts Geneveys.
- [8] Cahn, E. S. (2000). No More Throw-Away People: The Co-Production Imperative. Essential Books, Washington.
- [9] Szabo, N. (2005). Bit gold. Unenumerated, December 2005.
- [10] PlanB (2019). Modeling Bitcoin's Value with Scarcity. Medium, March 2019. <!-- FOREIGN-APP-OK: the title of the cited article -->
- [11] NIST (2024). FIPS 204, Module-Lattice-Based Digital Signature Standard. The signature of every coin record, [S2] section 1.
- [12] NIST (2015). FIPS 180-4, Secure Hash Standard. The identifier of every record and every root, [S2] sections 1 and 6.
