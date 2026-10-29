# Findings F2 and F3: corrected status and source evidence

**Status: open.** This documentation contribution addresses points 4 and 5 of the
[chair's final comment](https://github.com/efir369999/montana_messenger/issues/5#issuecomment-6372813946).
It changes no transport implementation and executes no builds, tests or measurements.
The former document is preserved in history at
[`ebd5a7d4fdb5872383f94755d2e978caef4df034:Audit/GPA/FINDINGS-F2-F3.md`](https://github.com/efir369999/montana_messenger/blob/ebd5a7d4fdb5872383f94755d2e978caef4df034/Audit/GPA/FINDINGS-F2-F3.md).
The assertions of agent-fix intake and compatibility with every phone are corrected below.

## Source revisions

- **M**, this repository's main read for this contribution:
  `2c7eb0df782da1679d20fc220499e9e3ab72c6b6`.
- **H**, a published historical phone snapshot in this repository:
  [`f92d90aff1a49ff15f132853afa028b2cea5d897`](https://github.com/efir369999/montana_messenger/blob/f92d90aff1a49ff15f132853afa028b2cea5d897/apps/messenger/ios/Code/Montana/MontanaWakePush.swift#L1778).
- **A**, the separately published `efir369999/montana_core` snapshot:
  `f2bf694cfd0dc6bc3f8803c8037ee3df13eafbb0`.
  Its [card.rs](https://github.com/efir369999/montana_core/blob/f2bf694cfd0dc6bc3f8803c8037ee3df13eafbb0/core/Code/crates/mt-agent/src/card.rs#L41) and [letter.rs](https://github.com/efir369999/montana_core/blob/f2bf694cfd0dc6bc3f8803c8037ee3df13eafbb0/core/Code/crates/mt-agent/src/letter.rs#L7) files were read from GitHub, not inferred from
  the earlier report. This is a different repository and not a path on M.
- The chair's private-line revision `ec2d343` and proposed fix `af821e63` are
  historical attributions in the linked comment, not accessible commits verified
  in this contribution. They are not substituted for M or A.

## F3 — open on the agent line and the phone line

### Agent correction, checked against the source

At **A**, `core/Code/crates/mt-agent/src/card.rs:41` reads
`pub const FIRST_ENVELOPE_SIZE: usize = 1536;`; lines 357–360 check and resize to
that constant. At the same commit, `core/Code/crates/mt-agent/src/letter.rs:7`
reads `pub const ENVELOPE_SIZE: usize = 2048;`, used at lines 24–31.
The first wake body serializes a sealed envelope as base64 under `env`
(`card.rs:352-372`). The two plain padding classes therefore differ by 512 bytes.
This supports **open on the agent line**, not “the agent fix is in the core line”.

The proposed change `af821e63` is **on the agent's branch only**, as the chair
states. This contribution does not certify that private branch's diff, tests,
intake, publication or deployment. Taking the change into the core line and
running its acceptance checks is point 1 of the chair's assignment, outside
this reading-and-writing contribution.

### Phone correction, checked at two public revisions

| Check | Historical phone H | Current main M |
|---|---|---|
| First-letter size check | `apps/messenger/ios/Code/Montana/MontanaWakePush.swift:1778`: `guard body.count <= 1536 else { return nil }` | same check at `:1784` |
| First-letter padding | same file `:1779`: `body.append(Data(count: 1536 - body.count))` | same padding at `:1785` |
| First-letter reader floor | same file `:2774`: `guard plain.count > 1092 else { continue }` | same floor at `:2783` |
| Continuing-letter padding | comparison below is pinned to M | `apps/messenger/ios/Code/Montana/MTNodeWire.swift:107,124-126`: 2048, size check and padding; called by `MontanaWakePush.swift:1568-1569` |

The chair attributed 1778–1779 and 2774 to source build 2303 / `ece5b866`.
These exact source lines were independently found at public commit H; this does
not assert that H is that private build. M's source listing is build 2311
(`RELEASES.md:18`). Current references must use the shifted lines on M.

At M, the notification extension has the same lower-bound check at
`apps/messenger/ios/Code/MontanaNSE/NotificationService.swift:790,819`.
At A, the agent reader uses a lower floor at `card.rs:43,290-298`.
These quoted checks do not impose an upper bound of 1536. **They do not prove
that every reader actually in service accepts a new 2048-byte first envelope**:
the oldest installed build, the rest of every reader path, push payload limits
and delivery behavior were not observed here. That compatibility proof and the
phone change remain point 2 of the chair's assignment, open.

### Scope of the observable distinction

The raw padding split is a source fact; a claim about what a physical-link
observer can classify must also account for seal overhead, base64/JSON, HTTP/TLS,
metadata, route choice and other traffic. The endpoint and physical-link views
are separated in [INTERSECTION-MODEL.md section 4](INTERSECTION-MODEL.md#4-todays-leakage-source-derived-with-open-boundaries).
That section also covers the unpadded live-letter path, long-text blobs and media
buckets. The wake-envelope constant is not a bound on every letter representation.

The historical normative rationale remains the first-letter invariants and one
shape requirement at **M**, `core/docs/Montana Network.md:298-305,324,686` and
`core/docs/Montana Constitution.md:382-385`. This is the target requirement,
not evidence that any of the above paths already meets it.

## F2 — separate the published source from the chair's intake record

At **M**, `core/Code/crates/mt-net/src/framing.rs:1-26` defines a 1024-byte
frame whose clear header contains `FLAG_PADDING`; lines 53–59 construct padding
and lines 193–202 check its fraction. This is the source of the historical F2
finding. It is not a demonstrated observation of a current phone connection.
Its removal on `fable-2/issue-5` is inspectable at **`4afd94a`** in
`core/Code/crates/mt-net/src/lib.rs:5-26` (re-export absent) and the
[deletion diff](https://github.com/efir369999/montana_messenger/commit/4afd94ae202755f54214dcda697d97c2729fb2f4) for `core/Code/crates/mt-net/src/framing.rs`
(old lines 1–394). The chair reports intake as `67cf1e5` on the private core line;
that intake is attributed to the chair, not re-verified by a run here.

The normative prohibition remains at **M**,
`core/docs/Montana Constitution.md:389-395` and
`core/docs/Montana Network.md:509-520`: carrying other traffic is not synthetic
filler. The new documentation adds no filler, flags, delay or alternate cipher.
Publication/acceptance is governed by **M**, `CONTRIBUTING.md:28-30`.

## What remains open / next

1. Agent F3 intake and its acceptance run: chair's point 1.
2. Phone F3 compatibility with the oldest live reader, implementation and field
   evidence: chair's point 2.
3. All-link counts, sizes and moments on a pinned deployment: chair's point 3;
   the source-derived function records precisely where that evidence is missing.
4. The relationship-anonymity proof and across-window bound: model section 5.
5. The authenticated window proof remains
   [#4](https://github.com/efir369999/montana_messenger/issues/4), with no duplicate
   implementation or closure here; external audit remains
   [#2](https://github.com/efir369999/montana_messenger/issues/2).

The four GPA documents now have one proposed source home:
`core/Montana-Core/protocol-13/GPA/`. The publisher's documented source mapping
is at **M**, `Audit/Protocol-13/README.md:40-44`; the chair takes this contribution
into the core line before a later publication. No generated `Audit/` copy or
`RELEASES.md` entry is changed by this contribution.
