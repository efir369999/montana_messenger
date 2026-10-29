# GPA documents: source-derived leakage and historical evidence

**Status: open. Refs #5.** This directory proposes the single core-line home of the four
GPA documents, for intake by the chair under
[`CONTRIBUTING.md:28-30` at `2c7eb0d`](https://github.com/efir369999/montana_messenger/blob/2c7eb0df782da1679d20fc220499e9e3ab72c6b6/CONTRIBUTING.md#L28-L30).
The publisher's documented source is `Montana-Core/protocol-13/`
([published folder description](https://github.com/efir369999/montana_messenger/blob/2c7eb0df782da1679d20fc220499e9e3ab72c6b6/Audit/Protocol-13/README.md#L40-L44)).
This PR does not edit the generated `Audit/` copy or `RELEASES.md`, and is not merged
as it stands. Intake, publication and field verification remain separate decisions.

## Current reading (points 4 and 5 only)

- [INTERSECTION-MODEL.md](INTERSECTION-MODEL.md), sections 4 and 5: leakage of the
  published code at **`2c7eb0df782da1679d20fc220499e9e3ab72c6b6`**, source-derived
  sizes/counts, event triggers, cells versus link units, observer boundaries,
  unresolved physical-link behavior and a conditional anonymity notion.
- [FINDINGS-F2-F3.md](FINDINGS-F2-F3.md): F3 **open on both the agent and phone**;
  corrected historical phone lines 1778–1779 and 2774, plus current-main lines
  1784–1785 and 2783; exact revisions and compatibility limits beside each citation.
- [LEMMA.md](LEMMA.md): historical per-unit argument and reported measurements,
  explicitly limited to their trees/instrument; section 4 reads **on the agent's
  branch only** for the proposed agent F3 fix.

Only reading and writing were performed. No cargo, build, test, benchmark, timing
experiment or device trace was run. Arithmetic in the leakage tables follows source
layouts; it is not a new traffic measurement. The runtime/compatibility work in the
chair's points 1–3 remains open. The authenticated window proof stays in
[#4](https://github.com/efir369999/montana_messenger/issues/4); the external audit
stays in [#2](https://github.com/efir369999/montana_messenger/issues/2).

## Historical PR #7 report retained below

The following report is imported from
[`82a50ef1d522f35aea801751664aa439bf771ae9:Audit/GPA/README.md`](https://github.com/efir369999/montana_messenger/blob/82a50ef1d522f35aea801751664aa439bf771ae9/Audit/GPA/README.md#L1-L254).
Source: `Audit/GPA/README.md:1-254` at that commit. Its baseline, measurements and “this pull request” refer to **PR #7**, not this
contribution or today's shipped transport. Its historical whole-application absence
claims, “keystroke” shorthand, all-objects indistinguishability language and F3 status
are superseded by the current source reading linked above. Unquoted historical
sweep conclusions are retained as the earlier agent's report, not fresh findings.
For current main, the cutters still contain the length-dependent copy
(`core/Montana-Core/crates/mt-wire/src/erasure.rs:237-239`, `src/link.rs:48-50` at
`2c7eb0df782da1679d20fc220499e9e3ab72c6b6`); the old report's fix/timing claims
must not be silently transferred to that published tree.

---

## Original report: Gate -1, intersection model and timing

**Status: open.** Of the six mechanisms a reviewer lists against a global passive adversary (GPA),
two exist in the reference core as code with vectors, one exists in the set and in code as a
derivation but is wired into no sending loop, two are forbidden by the set in the form the reviewer
names, and one is replaced by a different construction. The claim of the set against intersection is
stated in [INTERSECTION-MODEL.md](INTERSECTION-MODEL.md) with every open point named. Twelve
constant-time measurements stand over the paths where a padding block and a letter block must cost
the same; two of them found a leak in the cutters of the reference core, fixed in this pull request,
and their numbers before and after are below, on two machines. Nothing else here is closed.

This report answers issue #5 of this repository. It touches neither the window proof (#4) nor the
scope of the external audit proposal (#2); where it meets them it says so.

**Baseline.** Commit `2c6951f8b887b7e42bfe745f5bb42cdb207508f7` of this repository: the normative set
in `core/docs/`, the reference core in `core/Montana-Core/`, the client core in `core/Code/`, the
messenger application in `apps/messenger/`. Line numbers are of that commit. Two sources outside this
repository are read for completeness and are named as such: the iOS client source tree the published
application is built from (its public snapshot is `apps/messenger/ios`), and the crate `mt-agent` of
the repository `efir369999/montana_core` at commit `5be748583d650703cbcf134a8d8d9abf9cee091a`.

## 1. Gate -1: what exists, and what is words

Rule of this table: a mechanism *exists* only where a line of code is quoted and a test or vector
stands over it; *derivation only* where the formula is implemented and frozen but no running path
calls it; *words* where the set describes it and no code does; *forbidden* where the set rejects the
mechanism in the form named. `core/docs/Montana Registry.md` lines 123-147 is the set's own register:
every row of the network that is not the handshake, the tag or the cell is marked *awaits stage 18*.

| Mechanism named by the reviewer | In the set | Reference core (`core/Montana-Core`) | Client core (`core/Code`) and the application | Verdict |
|---|---|---|---|---|
| **Constant-rate sending** | Forbidden for correspondence: *"A constant rate would be the worst solution ... Synthetic filler therefore does not exist"* (`core/docs/Montana Constitution.md` 389-395; `core/docs/Montana Network.md` 514-520). Required for a stream only: *"A stream runs at a constant rate for the life of the pipe"* (Network 493-494). | None found. No stream code exists; the node writes a unit the moment it seals it (`crates/mt-net/src/lib.rs` 242-251). | None found. No code of the client core or of the application sets a sending rate; the voice and video path of the application rides WebRTC (`apps/messenger/ios`, `MontanaCall.swift`), whose rate is the codec's and is not measured here. | **Forbidden** for correspondence; **words** for streams. |
| **Padding to one length** | *"Its length is `cell_bytes` whatever it carries"*, `cell_bytes` = 1232 (Canon 897, 1929-1961); a unit of a link is the same width (Canon 2198-2224); *"No length crosses the wire"* (Network 182-185). | **Exists.** `crates/mt-wire/src/lib.rs` 49-52 (the one width, read from the Decree); `src/cell.rs` 208-223 (a cell of another length is refused), 236-277 (seal and open); `src/link.rs` 28-54 (the last piece padded with zeros inside the seal), 94-120 (a unit sealed to the one width); `src/draw.rs` 71-83 (a flight's filling is drawn, not zero); `crates/mt-net/src/lib.rs` 123-145 (the four flights cross as whole units). The erasure code pads a body to whole blocks and whole groups with zeros (`src/erasure.rs` 224-263). Used by the node: `crates/montana-node/src/lib.rs` 676, `src/pulse.rs` 770-781. Vectors and shape tests: `crates/mt-wire/tests/wire.rs`, `tests/shape.rs`. | **Partly, by size bucket, not one length.** Media blobs: `crates/mt-messenger-e2e/src/media.rs` 28-38 `pad_len` rounds a size up with overhead below 1/16, zero-filled inside the AEAD; reached from the application through `crates/mt-bindings/src/ffi_e2e.rs` 390-394 and `MontanaMediaKit.swift` 161-184 (zero fill at 163-164). Padding buckets `{256 ... 1 MiB}`: `crates/mt-overlay/src/inbox.rs` 4-10, called only from a test (`tests/e2e_stage2_offline.rs` 32-34). Uniform 1024-byte frames: `crates/mt-net/src/framing.rs` 1-26, 117-147, with no caller outside its own tests and a fuzz target. Handshake messages are padded to a *random* length up to 1024 (`crates/mt-noise-pq/src/xx_libp2p_upgrade.rs` 21-58): variable, not one length. Outside this repository, `mt-agent` pads letters to one of **two** sizes, 2048 and 1536 (`montana_core` `Code/crates/mt-agent/src/letter.rs` 7, 24-31; `src/card.rs` 41, 357-360): finding F3 below. | **Exists** in the reference core. **Buckets, not one length** in the client line. |
| **Poisson delays** | Not Poisson. Deferred mail leaves after a delay *drawn uniformly over the residues of its chain not yet reached*, bounded by the window, never applied to live traffic; the set argues against a shaped profile (Canon 1211-1225; Network 434-442; Constitution 480-485). | **Words.** Registry NET-08 *awaits stage 18*. No code draws a delay for mail. (`crates/mt-derive/src/nullifier.rs` 140-142 draws a delay, but for the redemption of a right, not for a letter.) | None found. The sweep of the client core and of the application for `poisson`, `jitter`, `delay`, `slot` finds no sending delay; sending happens when sealing does. | **Words**, and the words say *uniform*, not Poisson. |
| **Cover traffic** | **Forbidden.** *"Synthetic filler therefore does not exist, and neither does a price for it: the same bytes carry other people's letters"* (Constitution 389-395); a sleeping tenant's link is held *"with the transit it carries in any case"*, *"not with empty filler"* (Network 509-512; conformance point 8, line 716). What stands in its place is carriage, and the padding blocks inside a delivery. | **Exists in its place:** padding blocks of a delivery (`src/erasure.rs` 245-263) ride cells identical to letter blocks (`tests/shape.rs` 124-157). Carriage as a duty: `crates/montana-node/src/lib.rs` 771-793 (a link is carried for its life). No synthetic cell is ever made. | **Scaffolding only.** `crates/mt-net/src/framing.rs` 53-59 builds padding frames and 193-202 requires one in five frames to be padding; nothing outside the file's tests calls either. Were it live, the padding frame would announce itself: `FLAG_PADDING` stands in the three-byte plaintext header (lines 4, 21). Finding F2. | **Forbidden** by the set; dead code in the client line. |
| **Single-use queues** | A tag is *"spent once; it belongs to a window and is spent in that window"* and *"recorded at the holder for the window and nowhere else"* (Constitution 461-479; Network 127-153; conformance point 2, line 710). | **Derivation only.** The tag of a window, the label of a step and the sender's ephemeral identity are implemented and frozen (`crates/mt-derive/src/tag.rs` 36-45, 88-95; vectors in the same file and in `crates/mt-conformance`). The holder's record of a spent right is Registry NET-07, *awaits stage 18*; the node's `is_spent` (`crates/montana-node/src/state.rs` 196-197, 221) is of notes and openings of consensus, not of carriage. | **Rotating, not single-use.** Montana Unlinkable Queues: a queue holds random `recv_id`/`send_id` and a `rotation_epoch` (`crates/mt-overlay/src/muq.rs` 18-27); the postman carries them over TLS in two hops (`crates/mt-postman/src/muq.rs` 1-8); the application derives its queue keys once per launch (`MontanaQueueAddressing.swift` 77-125) and reaches a postman at an operator's address (`MontanaNameBook.swift` 572-574; `MontanaPhoneNode.swift` 9, 352). | **Derivation exists; spending is words** (stage 18). Client queues are long-lived. |
| **Onion routing** | **Replaced.** *"No one lays a route ... A sender knows the keys of nobody but its own acquaintances and builds no layers on their behalf"* (Constitution 450-459). Each hop re-seals the cell under the key of its next handshake and writes one slot of a seal array that is full of drawn values from the origin (Network 205-276; Canon 1949-1967). | **The step exists; the path is words.** `crates/mt-wire/src/cell.rs` 284-303 `carry`: open, write the seal at `seal_slot(relay_seal(owner, path_id(inner)))`, re-seal with a fresh nonce; `src/draw.rs` 85-93 the full drawn array; `crates/mt-derive/src/tag.rs` 61-86 the three derivations; a two-hop path in `tests/wire.rs` 104-175. No node forwards a cell hop by hop: Registry NET-03, NET-04, NET-13 *await stage 18*; the node deposits an object straight at an acquaintance (`crates/montana-node/src/lib.rs` 866-898; `src/pulse.rs` 846-863), and nothing calls `cell::carry` outside the tests of `mt-wire`. | **Scaffolding.** Dandelion++ stem/fluff (`crates/mt-net/src/dandelion.rs` 1-15) has no caller outside its own tests. The postman's two hops (entry proxy, host) are what the application uses: two machines of the operator, TLS between them, no re-sealing per step. | **Step exists as code and vectors; the path over several machines is words** (stage 18). |

Three consequences the table forces, stated so they cannot be read wider or narrower:

1. **Today's shipped transport is reactive.** The reference node writes a unit when it seals it
   (`crates/mt-net/src/lib.rs` 242-251) and the application seals media at the moment of sending
   (`MontanaMediaKit.swift` 161); the canonical slot is a frozen derivation with vectors
   (`crates/mt-derive/src/tag.rs` 110-117; `crates/mt-conformance/src/parse.rs` 2768) and nothing
   else. This is a reactive write path; equality of a physical send timestamp with a keystroke was not established. Every in-window property of the set stands on the slot
   and holds for no running code.
2. **The one-length cell and the per-step re-seal are real and tested** — and they are what the
   timing tests below stand over, because they are the surfaces an implementation could leak through
   even once the slot lands.
3. **The chair's reading of 21.10 — nothing of a GPA model in the client — is confirmed** for the
   application by a fresh sweep: `apps/messenger/ios` and the client source tree searched for `GPA`,
   `global passive`, `intersection`, `chaff`, `cover traffic`, `poisson`, `onion`, `constant rate`,
   `cell_bytes` match on none of them in the sense of this model (the word `intersection` stands
   twice in `MontanaWakePush.swift` 535-536 for the intersection of two sets of doors, and
   `constant rate` twice in `TOKENOMICS.md` 483 and 764 for the growth of a population; neither is
   a mechanism of the transport). The application's traffic shaping is the media size bucket
   named above and nothing else that the sweep or the FFI surface (`crates/mt-bindings/src/ffi_e2e.rs`)
   shows.

## 2. The intersection model

[INTERSECTION-MODEL.md](INTERSECTION-MODEL.md): the setting, the adversary, the property the set
claims word for word, what it explicitly does not claim, the intersection attack stated against the
setting, and the five things a proof would require. Each is marked open.

## 3. Timing: a padding block and a letter block cost the same

Montana carries no synthetic cover, so "cover versus real" takes, in this code, the one form the
set allows: a **padding block** (the zeros `erasure::cut` and `erasure::groups` fill a delivery
with, `crates/mt-wire/src/erasure.rs` 224-263) against a **letter block**. Both ride a cell; an origin
seals both twice, every hop carries both, and a link seals a unit of padding as it seals a unit of a
message. If any of those paths cost a different time for the two, an observer with a clock reads the
size of a letter — the one quantity the one width exists to hide.

The instrument is `crates/mt-wire/tests/dudect/mod.rs`, the dudect method of Reparaz, Balasch and
Verbauwhede (DATE 2017): two classes, interleaved samples, the slowest tenth dropped, Welch's t,
threshold 10. It was already in the tree for the erasure code (`tests/timing.rs`); this pull request
moves it into one module both files share and adds the measurements of the cell and the link in
`tests/timing_cell.rs`. Run:

```
cargo test -p mt-wire --test timing_cell --test timing -- --test-threads=1 --nocapture
```

| Test (`tests/timing_cell.rs`) | Path under the clock | Class A | Class B | Wrong implementation it rejects |
|---|---|---|---|---|
| `the_origin_seals_a_padding_block_and_a_letter_block_in_one_time` | `cell::seal_pipe_with_nonce` then `cell::seal_cell_with_nonce` (`src/cell.rs` 95-107, 246-260) | padding block | letter block | an origin that spares a block of zeros the seal (see the power test) |
| `a_hop_carries_a_padding_block_and_a_letter_block_in_one_time` | `cell::carry` (`src/cell.rs` 284-303) | cell of a padding block | cell of a letter block | a hop whose work depends on what the pipe layer holds |
| `a_hop_carries_a_cell_from_the_origin_and_one_that_has_travelled_in_one_time` | `cell::carry` | cell fresh from the origin | the same cell after six owners' hops | a hop that searches the seal array or whose cost grows with the slots written |
| `a_unit_of_padding_and_a_unit_of_a_message_seal_in_one_time` | `link::seal_unit` (`src/link.rs` 94-120) | unit of zeros | unit of a message | a link that seals padding differently |
| `cutting_a_body_that_fills_its_last_block_and_one_that_barely_does_costs_the_same` | `erasure::cut` (`src/erasure.rs` 229-243) | body of three full blocks | body of two blocks and one byte | `cut_that_copies`: the cutter of the baseline, whose copy follows the length of the body |
| `cutting_a_message_that_fills_its_last_piece_and_one_that_barely_does_costs_the_same` | `link::pieces` (`src/link.rs` 31-54) | message of three full pieces | message of two pieces and one byte | `pieces_that_copy`: the link of the baseline, whose copy follows the length of the message |
| `the_measurement_catches_an_origin_that_spares_a_padding_block_the_seal` | the named wrong implementation `seal_pipe_that_leaks` | padding block | letter block | **must fail the threshold**: proves the instrument has power at the scale of a seal (microseconds) |
| `the_measurement_catches_a_cutter_whose_copy_follows_the_length_of_the_body` | the named wrong implementation `cut_that_copies` (`src/erasure.rs` 229-243 at the baseline, word for word) | body of three full blocks | body of two blocks and one byte | **must fail the threshold**: proves the instrument has power at the scale of a copy (nanoseconds) |
| `the_measurement_catches_a_link_whose_copy_follows_the_length_of_the_message` | the named wrong implementation `pieces_that_copy` (`src/link.rs` 31-54 at the baseline) | message of three full pieces | message of two pieces and one byte | the same, for the link |

The four measurements of the cutters take 50 000 samples of four cuts each where the five of the seal
take 2000 of one call: the copy they look for is some ten nanoseconds in a cut of half a microsecond,
and on a machine whose noise comes in bursts longer than a sample only the count of samples raises the
t of a real difference (the constants `CUTTER_SAMPLES` and `CUTS_PER_SAMPLE` in `tests/timing_cell.rs`
carry the reasoning and the numbers). The two power checks of the cutters assert, before timing
anything, that the wrong implementation writes the bytes the right one writes, so that the clock is
the only thing that tells them apart.

`tests/timing.rs` keeps its three measurements of the erasure code (parity, reconstruction, and the
multiplication that returns early on a zero as its own power check), now on the shared instrument.

### Measured, first machine: the author's

Machine: Apple M1, 8 cores, macOS 26.7; Rust 1.92.0; `cargo` under `taskpolicy -b` with two build
jobs and one test thread, as the workspace pins (`core/Montana-Core/.cargo/config.toml`). Welch's t
over 2000 interleaved samples per class (500 for reconstruction, 250 for the leaking multiplication),
slowest tenth dropped, with the measurements of the cutters as they first stood: 2000 samples of one
cut. A t below 10 is "no leak seen at this power"; the power checks must exceed 10 or the other
numbers mean nothing.

| Measurement | t before the fix (release, baseline cutters) | t after the fix (release) |
|---|---|---|
| origin seals padding vs letter (`seal_pipe_with_nonce` + `seal_cell_with_nonce`) | 0.54 | 0.28 |
| hop carries padding vs letter (`carry`) | 0.16 | 0.38 |
| hop carries fresh vs six-hop cell (`carry`) | 0.01 | 0.23 |
| unit seals padding vs message (`seal_unit`) | 0.01 | 0.07 |
| `erasure::cut`, full vs barely-filled last block, 2000 samples of one cut | **33.64 — fail** | 0.47 |
| `link::pieces`, full vs barely-filled last piece, 2000 samples of one cut | **51.93 — fail** | 0.12 |
| power: origin sparing a padding block the seal (must exceed 10) | 309.40 | 200.18 |
| `erasure::parity` zeros vs drawn (`tests/timing.rs`) | 0.21 | 0.32 |
| `erasure::reconstruct` zeros vs drawn, 500 samples | 0.96 | 0.03 |
| power: multiplication returning early on a zero, 250 samples (must exceed 10) | 61.96 | 43.84 |

Two runs, each the full `mt-wire` suite in release (`cargo test --release -p mt-wire`): the first
with the cutters as they stood at the baseline, the second with `lay`. Every other test of the crate
(vectors, shape, wire, erasure, handshake) passed in both runs. The same suite in the debug build:
all 59 tests pass; the cutters after the fix measure t = 0.36 (`cut`) and t = 0.62 (`pieces`), the
other cell and link measurements 0.01 to 0.59, the two power checks 152.36 and 48.41. Before the fix
the debug build passed the cutters too (its own overhead hid the copy), which is why the release
numbers are the ones this report stands on.

### Measured, second machine: the council's check, and what it changed

Machine: a KVM guest of four vCPUs (AMD EPYC, 2.0 GHz), Ubuntu, kernel 6.8, with a Montana node
running beside the tests; Rust of the workspace; `nice -n -20`, one test thread, each test binary in
its own network namespace; one target directory per tree. The chair's check ran the measurements of
the cutters as they first stood against the tree *without* the fix, five rounds:

| Round | `erasure::cut`, baseline cutter, 2000 samples of one cut | `link::pieces`, baseline cutter, 2000 samples of one cut |
|---|---|---|
| 1 | 7.50 | 12.57 |
| 2 | 9.11 | 5.94 |
| 3 | 7.04 | 9.26 |
| 4 | 0.16 | 5.98 |
| 5 | 2.60 | 6.02 |

The leaking cutters passed in four rounds of five on that machine: the copy of ten nanoseconds stood
under its noise, and the one power check of the file (a spared seal, two microseconds) did not show
that the instrument could see a difference a hundred times smaller. The measurements were changed to
50 000 samples of four cuts (the noise of that machine comes in bursts longer than a sample, so more
cuts per sample buy nothing and only more samples do), and the two power checks of the cutters were
added. The same five rounds, release, with the measurements as they now stand:

| Measurement | tree without the fix (41a8ee0), five rounds | tree with the fix, five rounds |
|---|---|---|
| `erasure::cut`, full vs barely-filled last block | **56.28, 21.22, 29.48, 29.78, 37.48 — fail** | 0.98, 0.31, 2.64, 0.23, 0.01 |
| `link::pieces`, full vs barely-filled last piece | **40.59, 38.66, 37.65, 57.88, 41.44 — fail** | 1.69, 2.18, 1.76, 1.39, 1.76 |
| power: `cut_that_copies` (must exceed 10) | 27.11, 36.67, 24.71, 29.04, 28.13 | 27.97, 28.18, 22.60, 27.21, 26.35 |
| power: `pieces_that_copy` (must exceed 10) | 78.96, 90.80, 67.15, 84.32, 74.96 | 67.49, 65.85, 70.04, 75.96, 164.25 |
| power: origin sparing a padding block the seal | 467.73 to 768.59 | 480.08 to 960.12 |
| the four measurements of the seal and the hop | 0.01 to 1.57 | 0.04 to 1.08 |

The tree without the fix fails the two measurements of the cutters in every round and the tree with
the fix passes every measurement in every round; that is the property the rule of this repository
asks of a test — that it name the wrong implementation it rejects, and reject it. The four
measurements of the cutters run in the release build and are marked ignored, with the reason, in the
debug build: a block laid without optimization costs a hundred microseconds where the copy they look
for costs ten nanoseconds, so the debug build measures itself (on the second machine it took the
file to 110 seconds and put the copy of the baseline at t = 8.4). The first machine's debug run above
showed the same, and this report has stood on release numbers from the start.

What the numbers say, and do not say: a t below 10 means that at this count of samples on this
machine the two classes are not told apart; it is not a proof of constant time, and a GPA with a
longer trace or a quieter machine could in principle see what this did not. On the second machine
the cutters with the fix stand at t near one to three at 50 000 samples, consistently of one sign:
the body that barely reaches its last block reads one byte of the body over and over where the full
body reads them in sequence, and a trace some hundred times longer would see that. The three power
checks show that the instrument sees an early return that skips the work of one block and a copy
that follows the length by one block; it would not see a difference under a nanosecond.

The cost of the fix was measured on the second machine as well: three blocks cut with the copying
cutter of the baseline took 0.6 microseconds; with `lay` as it was first written (a lookup with
`get` and a fallback, an addition checked for overflow because the release profile checks it) 4.3
microseconds, a loop of single bytes with two checks that can panic inside it; with `lay` as it now
stands (the clamped position indexed directly on a body known to hold a byte, the position formed by
a wrapping add) 2.5 microseconds. The remaining four times over a copy is the price of reading every
byte through a clamped index, which no vector step of this target performs; the bytes written are the
same in all three forms, and the unit test and the two power checks hold them.

## 4. Findings

**F1 — `erasure::cut` and `link::pieces` took a time that followed the length of the body. Found by
the tests, fixed.** Both copied `end - at` bytes of the last block (`src/erasure.rs` 237-239 and
`src/link.rs` 48-50 at the baseline): one copy of up to one block followed the length. In the release
build the instrument saw it at t = 33.64 (`cut`) and t = 51.93 (`pieces`); the debug build hid it under
its own overhead, which is why release numbers are the ones that count. The quantity leaked is the
length of the body, which the one width hides on the wire; the clock that reads it is the sender's
own, and it reaches the wire through the moment of sending — wholesale today (reactive sending), and
after stage 18 only as far as the slot lets it. The fix is one function, `lay` (`src/lib.rs`), that
writes every byte of a block by a mask on the position and no branch on the length; both cutters call
it. The bytes produced are identical, so every frozen vector stands, and a unit test holds the bytes
(`a_block_is_laid_as_a_copy_and_a_zero_fill_would_lay_it`). After the fix: t = 0.47 (`cut`)
and t = 0.12 (`pieces`) on the first machine.

The council's check found that the two measurements, as they first stood, did not reject the leaking
cutters on its own machine (four rounds of five passed, t = 0.2 to 9.3), so they stood for nothing
there; the measurements were raised to 50 000 samples, the two cutters of the baseline were written
into the test file as the named wrong implementations, and two power checks now assert that the
instrument sees them. With that, the tree without the fix fails both measurements in every round
and the tree with the fix passes them (section 3). The check also found the first `lay` seven times
slower than the copy it replaced and rewrote it to 1.7 times faster, same bytes (section 3).

**F2 — the client line's cover frames would announce themselves.** `crates/mt-net/src/framing.rs`
places `FLAG_PADDING` in a three-byte plaintext header (lines 1-8, 21, 53-59) and requires one in five
frames to be padding (193-202). Nothing outside the file's own tests and a fuzz target calls it, so no
shipped byte carries the flag today. **Documented, not fixed:** the set forbids synthetic filler
outright, so the right change is removal with the rest of the earlier line, not a repair of a flag.

**F3 — open on both agent and phone; historical agent evidence follows.** A first
letter is padded to 1536 bytes (`Code/crates/mt-agent/src/card.rs` 41, 357-360), every later letter to
2048 (`src/letter.rs` 7, 24-31); the sealed lengths differ by 512 bytes on the wire of the postman
(`src/card.rs` 583 asserts the first). The decoded envelope class distinguishes first from continuing contact; physical-link classification additionally needs the transport mapping in the current model. The padding itself is zeros inside the AEAD and the branch in
`pad_envelope` is on the length bound only. **Documented here, to be filed against `montana_core`**;
this pull request does not touch that repository.

**F4 — the set describes stage 18 and the code runs stage 13.** The canonical slot, the holder rule,
the path, the right spent at the holder, the deferred delay, the digest set and the stable entries
are registered as awaiting stage 18 (`core/docs/Montana Registry.md` 127-144). Until then no sentence
of the set about the GPA is a property of the running code, and the application's transport (a
postman over TLS, two hops of one operator) is outside the set's model altogether. This is the
finding the table in section 1 is; it is restated here so the status line of this folder cannot be
read as anything but open.

## 5. What this pull request changes in the tree

- `core/Montana-Core/crates/mt-wire/tests/dudect/mod.rs` — the instrument, shared.
- `core/Montana-Core/crates/mt-wire/tests/timing.rs` — the erasure measurements on the shared instrument; no measurement changed.
- `core/Montana-Core/crates/mt-wire/tests/timing_cell.rs` — the nine measurements of section 3: seven of the paths, two power checks of the cutters beside the one of the seal.
- `core/Montana-Core/crates/mt-wire/src/lib.rs`, `src/erasure.rs`, `src/link.rs` — the fix of F1: `lay`, and the two cutters calling it. Bytes unchanged; a unit test holds them.
- `Audit/GPA/README.md`, `Audit/GPA/INTERSECTION-MODEL.md`, one line in `Audit/README.md`.

No file of the normative set, of the client core or of the application is changed; of the reference
core's library code, the two cutters named above and nothing else. The first measurements and the
first form of the fix are self-verification by the implementing agent on the project's own machine;
the second machine of section 3 is the council's check of this pull request, which changed the
measurements of the cutters and the form of `lay` as that section states. Neither is an independent
audit.
