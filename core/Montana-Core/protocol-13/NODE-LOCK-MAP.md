# #61 C1: the map of the node lock, its release and forfeit, and the evidence of a violation

Read only. Head `bfee834` (origin/main, "Merge PR #66 (issue #23): Canon 10.0.0 ..."), branch
`agent-609/issue-61`. Written 2026-10-27 UTC by Opus C [agent of Agent 609], claude-opus-5-5. Nothing
was built or run for this map. Paths are from the tree root; `Canon` = `core/docs/Montana Canon.md`,
`Consensus` = `core/docs/Montana Consensus.md`, `Constitution` = `core/docs/Montana Constitution.md`,
`Value` = `core/docs/Montana Value.md`, `Registry` = `core/docs/Montana Registry.md`, `MC` =
`core/Montana-Core`.

**One sentence.** On main, nothing specifies or implements a node lock. Its release and forfeit are
not there either. What exists is the evidence of a double answer and its sanction: the convicted part
loses the coin of its window. That sanction is specified in Consensus and Canon, but not built. The
code detects contradicting pledges and consumes nothing of them. The lock itself rests on the author's
records 224, 231 and 233 and on the draft PR #52, which is not merged. Nothing anywhere fixes how a
convicted part reaches a lock.

## 0. Two words that are not the node lock

- **The "lock" of the agreement** (`Consensus:626-631`, `:650-651`, `:729`, `:731`, `:1272`, `:1282`;
  `MC/crates/montana-node/src/attempt.rs`, `MC/crates/mt-store/src/lib.rs:552`) means something else.
  It is the name and the attempt of a machine's last closing pledge, held per open window and let go
  when the window closes. It is not collateral, and nothing below is about it.
- **"forfeits"** at `MC/crates/mt-proof/src/circuit/frame.rs:72` is about a note filler, and
  `core/docs/Montana App.md:165` is about a client. Neither is about a lock.

## 1. The decisions (outside the tree, the council's chain)

| Record | Time (UTC) | Text (verbatim, Russian) | What it fixes |
|---|---|---|---|
| constitution 224 (answer to 223) | 26.10.2026 15:32:02 | «нет, сам себе не отправляешь а ключ должен прожить т2 окно 14 дней и эти монеты поставить в залог чтобы создать узел - конституцию проверь под эту логику» | a node is raised by a key that lived τ₂ and a lock of coins; the constitution is to be checked against it |
| constitution 230 (answer to 228) | 26.10.2026 15:33:19 | «не 3 монеты а залог 14 дней в монетах как т2 и слэшинг будет позже при необходимости добавлен» | the lock is τ₂ in coins; slashing "later, if needed" |
| constitution 231 (answer to 229), council link 8935 | 26.10.2026 15:35:05 | «... это количество за т2 где каждая секунда = 1 монеты он должен заложить и в случает нарушения протокола любого - слэшинг и исклчение узла из консенсуса» | on **any** protocol violation: slashing **and** exclusion of the node from consensus |
| constitution 233 (answer to 232), council link 8951 | 26.10.2026 15:51:30 | «1) ВЕРНО (1 209 600 монет); 2) верно (узел открывает τ2 + залог, порог 8 для узла снять); 3) сжечь» | amount 1 209 600 coins; the gate is τ₂ plus the lock and nothing else; a slashed lock is **burned** |
| constitution 238 | 26.10.2026 19:14:35 | a question with three options: move the #15 deadline / close #15 partly with slashing as its own task / other | not a decision on the relation; the author's word on it (council link 9173) was «так сделай все тесты на л2 л3 л1» |
| constitution 246, council link 9250 | 26.10.2026 20:37:55, "yes" 21:21:31 | F-1 in #15; «залог τ2 и слэшинг (решение 233) -- отдельным ОЗ: криптосвязь доказательства нарушения с залогом открыта (Canon PR #52 «Evidence to lock»)» | the lock and slashing become #61; the evidence-to-lock link is **open** |

Sources: `/Users/kh./Python/Nothing/Montana/App/Montana-iOS/CouncilWall/constitution.jsonl`, records
`n` 224, 230, 231, 233, 238, 246. The council links are in `claude_agent.jsonl`, `n` 8935, 8951, 9173 and 9250.
The chairman's English of 231 and 233 is in PR #52 comments 6420399577 and 6420491388.

No record fixes any of these: how a convicted part reaches a lock, which violations other than the
double answer count, whether a forfeit may disclose which lock it consumed, how long a lock stands,
when it is released, or whether `node_lock` enters the Decree.

## 2. What exists on main

### 2.1 The evidence: kinds, producer, verifier (specified)

- **Kinds.** There are three contradicting pairs under one part-nullifier of one window:
  - two open pledges of one attempt on two names, which includes two heavy attestations naming two names;
  - two closing pledges of one attempt on two names;
  - a closing pledge followed, in a later attempt, by an open pledge on another name standing on none
    or on an attempt before the closing one.

  Sources: `Consensus:717-721`, `:794-800`, `:819-822`. The pair is "the only proof this protocol
  accepts against a machine" (`Consensus:794-796`). The same is in `:950-952` ("what is held against
  a machine is only the equivocation the sanction states") and in conformance `:1368`.
- **Not evidence.** A light attestation, a repeated pledge on one name, a repeated round nullifier
  under one beacon, timing, presence, reachability, silence, timeout and a neighbour's account are not
  evidence (`Consensus:795-796`, `:819-825`; `Canon:5185`).
- **The object.** A pledge has a fixed layout, `pledge_len` 5 343 B: window, attempt, name, since,
  part_nullifier, suite_id, answering_key (the one-time key of the window) and signature
  (`Canon:5223-5248`). A pledge is valid only where the heavy attestation of its part under the same
  key stands (`Consensus:726`, `Canon:5246`). The heavy attestation carries the proof of presence:
  "the bearer is a machine of the electorate of this window and ... the nullifier and the key derive
  from one secret" (`Canon:5163`).
  - *C4, 27.10.2026 UTC, the author's record 295 (decision 290):* on this branch a pledge also
    carries `line_value` (32 B) and its own proof (`PRESENCE_PROOF_LEN`, 333 888 B), so `pledge_len`
    is 339 263 B (Canon, "The pledge of a part"). The 5 343 B above is main at `bfee834`, which this
    map reads.
- **The part.** `part_nf(W) = sponge("mt-part-nf", cells(machine_sk) || W)`, with the spending half
  from the same absorption whose naming half is the admitted leaf (`Canon:2884-2907`,
  `:2973-2975`). One machine yields one value per window, and two machines never collide
  (`Canon:2904`). A second secret yielding the same part is a collision of the proof hash
  (`Canon:3038`, `:5218`). The part joins to nothing across windows (`Consensus:1355`; `Canon:5247`).
- **Who produces it.** Anyone holding both objects: "self-evident to any machine holding both ... a
  local rule with a global result" (`Consensus:810-812`).
- **Who verifies it.** Every machine, identically, by the canonical order of the window, never by
  arrival (`Consensus:810-811`, `:827-829`).
- **When.** The challenge of `W` runs from its proposal to the close of `W + 1`. A pair presented
  after that is refused (`Consensus:778-779`, `:790`; `Canon:2994-2995`). The evidence is discarded
  with that close (`Consensus:812-813`, conformance `:1369`).
- **The sanction today.** It falls on the right of that window and nothing else: "the coin of that
  window is not paid, and nothing beyond that right is touched ... There is no confiscation, no
  exclusion by name and no list of offenders" (`Consensus:802-808`). "An equivocating right loses
  the coin of its window and nothing else" (`Consensus:763-765`). Nothing of the evidence persists
  except the absence of the part from the tree of credited rights (`Consensus:790`, `:830`). The
  convicting pairs stand in the roll of `W + 1` (`Consensus:683-687`, `:813-815`). The tree of
  credited rights leaves the convicted part out (`Canon:627-630`, `:2994-3003`, `:3048`, `:5076`;
  `Value:208`).

### 2.2 The code of the evidence (implemented)

- `MC/crates/montana-node/src/agreement.rs:71-79` holds `Contradiction { first, second }`. `:83-90`
  is the third pair (`contradicts`), and `:104-124` classifies a pair.
- `agreement.rs:156-228` is `Book`. `Book::pledge` (`:206-228`) records every contradicting pair into
  `contradictions` (`:217`). `Book::heavy` (`:181-192`) keeps the canonical first heavy by `Place`.
- `MC/crates/montana-node/src/pulse.rs:652-667` is `gather_pledge`. It counts a pledge only under
  the key its part's heavy proved, holds it in escrow until then, and verifies the signature through
  `attest::verify_pledge` (`MC/crates/montana-node/src/attest.rs:279-287`). The heavy's presence is
  verified against `admitted_root` (`pulse.rs:467-474`).
- `pulse.rs:435-446` refuses a second heavy attestation of one part naming another name. The check
  stands before `book.heavy` (`pulse.rs:498-502`), so that pair never reaches `Book.contradictions`
  and is not held as evidence.
- `contradictions` is read only by tests: `agreement.rs:516-630` and
  `MC/crates/montana-node/tests/a_verdict_reads_no_clock.rs:539`. No production path consumes it,
  carries it, persists it or acts on it.

### 2.3 The lock, its release, its forfeit, burning, exclusion

**Not on main in any document or code.**

- No `node_lock` row in the Decree (`Canon:4731-4778`).
- No lock layout among the Layouts (`Canon:4913-5428`).
- No lock in the candidacy (`Canon:5278-5305`).
- No lock domain in the registry of separators (`Canon:3771` ff.).

The only mention is a comment, `MC/crates/mt-genesis/src/lib.rs:77-80`: "tau-2 of them is node_lock".
The derivation it names, τ₂ x `window_credit` = 20 160 x 60 = 1 209 600 (`Canon:4734-4735`), equals
record 233's amount. No row or rule carries it.

## 3. Specified but not implemented

| What the set says | Where | What the code does |
|---|---|---|
| the proposal of `W + 1` credits the cement of `W` less the convicted parts | `Consensus:683-687`, `:780-781`, `:803-806`; `Canon:627-630`, `:2994-3003`, `:3048`, `:5076`; `Value:208` | `pulse.rs:1946-1963` (`credited_by`) credits `roll.parts` whole; the comment there says "the sanction itself is not built (Registry, CNS-10), so the whole cement is credited until it is"; `MC/AUDIT.md:1212-1216` |
| the convicting pairs stand in the roll of `W + 1` | `Consensus:685-687`, `:813-815`, `:830` | the roll layout has no field for them (`Canon:5255-5262`), and their layout is "owed with the sanction itself" (`Canon:3001-3003`, `Consensus:686-687`) |
| whoever holds the evidence keeps it while the challenge is open | `Consensus:812-813` | the heavy pair is refused and dropped (`pulse.rs:438-446`); the pledge pairs live only in the `Book` of the window (`agreement.rs:165`) |
| the scenario of a contradicting pair, its part left out | `Registry:62` (CNS-10, awaits stage 19) | none |
| stage 19: "the sanction of a double answer read from one part-nullifier under two proposal identifiers of one height" | `MC/ROADMAP.md:1152-1163` | none; the wording names only two of the three pairs |

## 4. Implemented but not specified

| What the code does | Where | What the set says |
|---|---|---|
| a comment naming `node_lock` as τ₂ x `window_credit` | `MC/crates/mt-genesis/src/lib.rs:77-80` | no `node_lock` anywhere in `core/docs` on main |
| the second heavy of one part is refused by the first seen in `self.names` (`pulse.rs:497`, `entry().or_insert`), which is arrival order | `pulse.rs:438-446` | "by the canonical order of the window and never by the order of arrival" (`Consensus:827-828`); `Book::heavy` does follow it (`agreement.rs:181-192`) |

## 5. Decided but neither specified on main nor implemented (records 224, 231, 233, 246)

- the lock itself, its amount (1 209 600) and the gate τ₂ plus lock;
- the forfeit ("slashing") on any violation;
- the exclusion of the node from consensus;
- burning of a forfeited lock;
- the evidence-to-lock binding.

Draft PR #52, head `55bd7a99`, is not merged. It carries these, as a proposal, in its Canon:
- `node_lock` at `:4657`;
- "The continuity and node-lock candidacy proposal" at `:5224-5381`, with the lock-bearing candidacy
  at `:5279` ff. and the invariants at `:5337` and `:5344`;
- "Open construction gates" at `:5354-5363`, which names the missing relation;
- draft amendments of Constitution [I-6], [I-12] and the monetary clause, and of Value
  "Conservation of issuance".

## 6. Where main contradicts the decisions

A forfeit or burn rule cannot land in Canon alone without one of these being amended first. They are
for the author, not for C2:

- `Constitution:168-170` [I-6]: "Forbidden without exception: ... freezing, seizure, blocking or
  reversal of value by any actor, including a supermajority".
- `Constitution:248-250`, `:254-257`, `:261-262` [I-12]: "exclusively through canonical time-based
  primitives ... none of them is a quantity of money".
- `Constitution:822-823`: "supply growing strictly monotonically ..., no protocol-level burning".
- `Consensus:763-765`, `:802-808`: the sanction touches nothing beyond the right of one window; no
  confiscation and no exclusion by name.
- `Consensus:790`, `:830`, conformance `:1369`: nothing of the evidence enters persistent state but
  the absent part, and the evidence is discarded with the close.
- `Value:208-209`: supply is the sum of what windows added; no term subtracts a burned lock.
- `Consensus:1356`: the observability ledger says the contradicting pair "names no one".

## 7. Facts C2 rests on

- **One machine.** A convicted part is the part of exactly one admitted machine, up to a collision of
  the proof hash (`Canon:2904`, `:3038`, `:5163`, `:5218`).
- **Its lock.** The lock that machine put up is, per record 224, the lock of its candidacy. A
  candidacy publishes `naming_half` and `node_commit`, and its proof makes the naming half the second
  squeeze of one absorption of the claimant's secret (`Canon:5286-5287`, `:5300`, `:5302`). That is
  the same absorption whose spending half yields every `part_nf(W)` of that machine (`Canon:2889-2899`).
- **The gap.** No verifier holding only the part can reach that naming half or lock: the part joins
  to nothing across windows and to no naming half (`Consensus:1355`; `Canon:5162`, `:5247`). That
  relation is what record 246 calls open.
