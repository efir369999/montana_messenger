# Historical per-unit lemma: scope, assumptions and reported measurements

**Status: open.** This file retains the historical statement about the cited PR #7 reference-core trees against a global passive adversary (GPA), as a lemma with its assumptions and its evidence,
so that what stands is not read wider than it is. Everything the lemma does not state is open and is
listed at the end. The proof the set would need is the one
[INTERSECTION-MODEL.md](INTERSECTION-MODEL.md) section 5 lists, and none of its five lines is closed
by this file.

**Trees.** The normative set and the client core are read at commit
`f2c2b6f` of this repository (`core/docs/`, `core/Code/`; the files quoted are unchanged since
`2c6951f`, the baseline of [README.md](README.md)). The reference core is read at two trees: the
baseline `2c6951f` (`core/Montana-Core/`), where the cutters leak (finding F1 of README.md), and the
head of pull request #7, `82a50ef`, where the historical report records no detected leak at its stated measurement power. Line numbers name the tree they are of.


**Provenance and correction.** Imported from
[`ebd5a7d4fdb5872383f94755d2e978caef4df034:Audit/GPA/LEMMA.md`](https://github.com/efir369999/montana_messenger/blob/ebd5a7d4fdb5872383f94755d2e978caef4df034/Audit/GPA/LEMMA.md).
All timing numbers below are retained historical reports, not measurements rerun or
independently validated by this contribution. They do not certify current main
`2c7eb0df782da1679d20fc220499e9e3ab72c6b6`. The current source-derived leakage,
including handshake plaintext, two link units per deposit cell, variable live-letter
length and reactive scheduling, is [INTERSECTION-MODEL.md](INTERSECTION-MODEL.md),
sections 4–5. Equal width alone is not ciphertext or relationship indistinguishability.

## 1. The lemma

Let a *unit* be what one machine of the reference core writes to a link: a cell of a delivery or a
unit of a link message. Let an observer hold a clock at the writing machine and read the wire after
it.

**Lemma (one length, one time per unit).** Under the assumptions of section 2:

1. **Length.** Each successfully constructed unit covered by the cited encoders is exactly `cell_bytes` = 1232 bytes long,
   at the unit layer: a block of a letter, a block of zeros that pads a delivery, a piece of a
   link message, the padding of its last piece, or a piece of a handshake flight. A flight may occupy several units. A unit of any other
   length is refused before a field of it is read. Two bodies of one length leave one shape: the
   same count of blocks, groups and cells.
2. **Time.** On the four paths where a unit is produced or carried, the historical instrument did not detect a difference according to whether the unit holds padding or a letter, or how far a cell has travelled,
   or (at `82a50ef`) how much of its last block a body fills — *as measured*: Welch's t below 10
   between the two classes on two machines at the sample counts of section 3, with power checks
   that put a named wrong implementation above the threshold on both.

That is the whole statement. It is about one unit at one machine; it says nothing about which
machines a unit touches, when a machine writes one, or how many it writes in a window.

## 2. Assumptions

- **A1 (the set's width).** `cell_bytes` is read from the Decree and is 1232 (`core/docs/Montana
  Canon.md` 4652: *the one length of everything that crosses the wire*; `core/Montana-Core/crates/mt-wire/src/lib.rs` 49-52).
- **A2 (the wire is the reference core's).** The length statement covers the cited framing/encoding routines; the timing statement
  covers only the measured seal/cutter paths. Unsealed handshake flights are outside the
  timing statement and are not cryptographically indistinguishable by virtue of width. It is not about the messenger application, whose transport is a postman
  over TLS with the size buckets README.md names (Gate -1 table, row *padding to one length*).
- **A3 (the clock).** "Time" is wall time of the writing machine as the instrument of
  `core/Montana-Core/crates/mt-wire/tests/dudect/mod.rs` measures it: two classes interleaved, the
  slowest tenth of each dropped, Welch's t (`mod.rs` 30-71), threshold 10 (`mod.rs` 16). The
  measurement is of the optimized build; the cutters' four measurements are ignored with a reason in
  the debug build (`tests/timing_cell.rs` 192-196, 219-223, 337-341, 370-374 at `82a50ef`).
- **A4 (what "as measured" means).** A t below 10 at N samples on a machine means the classes were
  not told apart at that count on that machine. It is not a proof of constant time; a longer trace or
  a quieter machine could see what these did not (README.md, section 3, *what the numbers say*).
- **A5 (sending at the cited baseline).** No assumption is made about the moment of sending. At that baseline the reference
  node writes a unit when it seals it (`core/Montana-Core/crates/mt-net/src/lib.rs` 242-251); the
  canonical slot is a derivation with vectors and nothing more (README.md, consequence 1).

## 3. Evidence

### 3.1 Length (part 1 of the lemma) -- by construction, held by vectors

| Claim | Code (`core/Montana-Core/crates/mt-wire`, `2c6951f` and `82a50ef` alike) | Held by |
|---|---|---|
| a cell of another length is refused at its one door | `src/cell.rs` 208-223 (`Cell::parse` compares the length before anything is read) | `tests/wire.rs` 69 `a_cell_of_the_wrong_length_is_discarded_in_silence` |
| a delivery is cut into blocks of one width, the last padded with zeros inside the seal | `src/erasure.rs` 230-243 (`cut`), 245-263 (`groups`) | `tests/shape.rs` 128 `two_bodies_of_one_length_leave_one_shape`; the frozen cell `tests/wire.rs` 20 |
| a link message is cut into pieces of one width, the last padded, the kind inside the seal | `src/link.rs` 32-54 (`pieces`), 92-120 (`seal_unit`) | `tests/wire.rs` 87 (two machines through a third), 296 |
| the four flights of a handshake cross as whole units of the one width | `core/Montana-Core/crates/mt-net/src/lib.rs` 123-145 | `core/Montana-Core/crates/mt-net/tests/` |
| beyond the label no byte of a cell stands still across sealings; the seal array is not told from drawn bytes | `src/draw.rs` 71-93; `src/cell.rs` 284-303 (`carry`) | `tests/shape.rs` 45, 79, 162 |
| no length crosses the wire; where a message ends is read from the message | the set: `core/docs/Montana Network.md` 182-185; `core/docs/Montana Canon.md` 2271 (*never synthetic filler*) | -- |

### 3.2 Time (part 2 of the lemma) -- as measured

Tests of `core/Montana-Core/crates/mt-wire/tests/timing_cell.rs` at `82a50ef` (line of the test
function), the path under the clock, and the measured t on the two machines README.md section 3
describes (release build; the first machine's numbers are the author's single run, the second
machine's are the council's five rounds on the tree with the fix):

| Test (line) | Path | Samples per class | t, first machine | t, second machine, five rounds |
|---|---|---|---|---|
| `the_origin_seals_a_padding_block_and_a_letter_block_in_one_time` (82) | `cell::seal_pipe_with_nonce` + `seal_cell_with_nonce`, `src/cell.rs` 95-107, 246-260 | 2000 | 0.28 | 0.04 to 1.08 |
| `a_hop_carries_a_padding_block_and_a_letter_block_in_one_time` (101) | `cell::carry`, `src/cell.rs` 284-303 | 2000 | 0.38 | 0.04 to 1.08 |
| `a_hop_carries_a_cell_from_the_origin_and_one_that_has_travelled_in_one_time` (122) | `cell::carry` | 2000 | 0.23 | 0.04 to 1.08 |
| `a_unit_of_padding_and_a_unit_of_a_message_seal_in_one_time` (143) | `link::seal_unit`, `src/link.rs` 92-120 | 2000 | 0.07 | 0.04 to 1.08 |
| `cutting_a_body_that_fills_its_last_block_and_one_that_barely_does_costs_the_same` (197) | `erasure::cut` through `lay`, `src/lib.rs` 134 | 50 000 x 4 cuts | 0.47 | 0.98, 0.31, 2.64, 0.23, 0.01 |
| `cutting_a_message_that_fills_its_last_piece_and_one_that_barely_does_costs_the_same` (224) | `link::pieces` through `lay` | 50 000 x 4 cuts | 0.12 | 1.69, 2.18, 1.76, 1.39, 1.76 |
| power: `the_measurement_catches_an_origin_that_spares_a_padding_block_the_seal` (266), must exceed 10 | `seal_pipe_that_leaks` (252) | 2000 | 200.18 | 480.08 to 960.12 |
| power: `the_measurement_catches_a_cutter_whose_copy_follows_the_length_of_the_body` (342), must exceed 10 | `cut_that_copies` (300) = the baseline cutter | 50 000 x 4 | -- | 27.97, 28.18, 22.60, 27.21, 26.35 |
| power: `the_measurement_catches_a_link_whose_copy_follows_the_length_of_the_message` (375), must exceed 10 | `pieces_that_copy` (317) = the baseline link | 50 000 x 4 | -- | 67.49, 65.85, 70.04, 75.96, 164.25 |

At the baseline `2c6951f` the two cutter measurements fail on both machines (first machine 33.64 and
51.93; second machine, five rounds, 21.22 to 56.28 and 37.65 to 57.88): part 2 of the lemma does
**not** hold at the baseline for the length of a body, and the historical measurements at `82a50ef` supply only the bounded evidence of A4. The three erasure
measurements of `tests/timing.rs` (parity, reconstruction, and the early-returning multiplication as
their power check) hold at both trees.

The same measurements were run once more by the council on the core line the public `core/` folder
is published from (branch `publish/core-english`, with the five `mt-wire` commits of pull request #7
ported onto it), on the second machine: see section 3.3.

### 3.3 The port to the core line (council, 23.10.2026)

The `mt-wire` tree of the core line differs from the baseline of pull request #7 in `src/lib.rs`
(two names of the message vocabulary) and `src/message.rs` only; the five commits of the pull
request apply without a conflict and the frozen vectors (`tests/wire.rs`, `tests/shape.rs`) stand.
Release build, second machine, one run of the whole crate and then five rounds of
`tests/timing_cell.rs` per tree, one target directory per tree (the tree without `lay` fails the two cutter measurements in every
round and the tree with `lay` passes all nine in every round):

| Measurement | core line without `lay` (tests of `82a50ef`), five rounds | core line with `lay`, five rounds |
|---|---|---|
| `erasure::cut`, full vs barely-filled last block | **32.11, 25.58, 24.05, 35.91, 24.36 -- fail** | 0.24, 3.56, 0.70, 2.81, 1.10 |
| `link::pieces`, full vs barely-filled last piece | **39.76, 36.46, 38.56, 46.76, 39.22 -- fail** | 0.72, 2.30, 0.83, 2.71, 0.95 |
| power: `cut_that_copies` | 31.75, 33.13, 30.76, 33.09, 40.52 | 23.26, 34.85, 26.00, 32.13, 19.84 |
| power: `pieces_that_copy` | 54.66, 60.06, 58.72, 65.28, 84.59 | 58.47, 114.83, 63.21, 73.56, 98.43 |
| power: origin sparing a padding block the seal | 509.80 to 586.41 | 99.48 to 722.03 |
| the four measurements of the seal and the hop | 0.02 to 0.69 | 0.00 to 1.71 |

## 4. What the lemma does not say

- Nothing about **which lines a unit touches** (`S_r`, `R_r` of INTERSECTION-MODEL.md section 4) or
  about **when** a machine writes one. A5 identifies a reactive write, not equality with a keystroke timestamp; current source evidence is in model section 4.
- Nothing about **count**: a delivery of more blocks is more cells, and the set deliberately leaves
  the size of a letter observable to the machine holding its pipe, bounded by the window
  (`core/docs/Montana Network.md` 688). The one length hides the length of a body inside a cell,
  not the number of cells.
- Nothing about **the path over several machines**, the holder rule, the right spent at the holder,
  the deferred delay, the digest set: registered as awaiting stage 18 (`core/docs/Montana
  Registry.md` 123-147), with no running code (README.md F4).
- Nothing about **the application** (A2). F3 remains **open on the agent line too**.
  The proposed first-letter size fix is **on the agent's branch only**, per the chair's
  [correction](https://github.com/efir369999/montana_messenger/issues/5#issuecomment-6372813946).
  The independently read public agent snapshot `efir369999/montana_core` at
  `f2bf694cfd0dc6bc3f8803c8037ee3df13eafbb0` still has 1536 in
  `core/Code/crates/mt-agent/src/card.rs:41,357-360` and 2048 in
  `core/Code/crates/mt-agent/src/letter.rs:7,24-31`. The phone also retains its
  separate first-letter class. See [FINDINGS-F2-F3.md](FINDINGS-F2-F3.md) for the
  verified phone line mapping and the live-reader compatibility gap.
- Nothing about **a proof**: the leakage function, the notion, the in-window theorem, the
  across-window bound and the implementation of stage 18 (INTERSECTION-MODEL.md section 5, points
  1 to 5) stay open. Part 2 of this lemma is the code-level witness that point 3 of that list
  names; it is a measurement, not a theorem.
- Nothing about **the window proof**: the authentication of the height a slot is read from is
  Protocol-13 item 1 and is tracked in issue #4; this file neither closes nor restates it.

## 5. Historical reproduction command (not executed for this contribution)

```
cd core/Montana-Core
cargo test -p mt-wire --release --test timing_cell --test timing -- --test-threads=1 --nocapture
```

The tree must hold the five `mt-wire` commits of pull request #7 (`1a96156`, `41a8ee0`, `a59044d`,
`84f14be`, `6f22f0a`); at `2c6951f` the two cutter measurements are expected to fail, which is
finding F1.
