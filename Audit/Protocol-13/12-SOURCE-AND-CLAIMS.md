# 12. Reconcile source, specification, audits and publication

**Status: open. This directory records current limits explicitly.**

The root repository links this audit separately; the closed criteria are the
rows marked closed in the table of `README.md`, written from `PROTOCOL-13.json`.
Its application releases remain separately identified in `RELEASES.md`. Candidate
native fixes are not described as present in the pinned public core snapshot.
Historical closure prose is not current end-to-end proof; unresolved findings
override it. The old and native core generations are evaluated separately.

Candidate proof changes update Canon/Core versions, AIR identifiers, parameter
digest, serialized widths and Genesis. The current candidate Genesis is the
`genesis_state_hash` that `Montana Canon.md` states; this report does not restate it.
It is not a production trust anchor or an authorization to migrate balances.
No fallback accepting retired vulnerable proof descriptions was added.

The deployed explorer now describes verified signatures and checkpoint
reconstruction within their actual limits, rather than equating root agreement
with finality or recorded sums with authorized supply. Website evidence and core
acceptance evidence remain distinct.

Closure still requires reconciling every outstanding audit entry, including
encoding/table domains, accumulation soundness, entropy assumptions and delivery.
Each closed finding needs a published implementation revision, reproducible
checks and matching statements. Public artifacts are scanned on the separate
host before publication. Historical internal reports require review; their
wholesale publication and whole-repository consistency are not claimed here.

## Closed items

Listed on 2026-10-27 UTC against `main` at `bfee834`. Four of the thirteen
items are closed by the chairman's comment on their issue: #4 (item 1), #10
(item 2), #14 (item 3) and #15 (item 4); no other Protocol-13 issue is closed.
`source/Montana-Core/PROTOCOL-13.json`, and the table of `README.md` written
from it, mark item 1 closed and items 2, 3 and 4 open: the status file has not
followed the closures of 26 and 27 October. Every merge and implementation
commit named below is an ancestor of `main` (`git merge-base --is-ancestor`,
exit 0). Quotations are from the comment whose id is given.

### Item 1, issue #4: the window proof

- Closed 2026-10-25 22:53 UTC. Closing comment 6404533526: "Closed by PR #39,
  merged into `main` as `cdd30047` (2026-10-25 22:52 UTC)."
- Implementation, the same comment: "**Report and status in one commit**
  `1893c052`: `core/Montana-Core/protocol-13/01-WINDOW-PROOF.md` and item 1 of
  `PROTOCOL-13.json` marked `closed`"; "**O-6 on `033c6b7`** (merged as
  `0ac84ae`)". The relation and its verifier are in `WINDOW-RELATION.md`, the
  theorems in `WINDOW-THEOREM.md` (row 1 of `README.md`).
- Check, the same comment: "**The ring of the core on `4451b21`** ... fmt 0;
  Clippy `-D warnings` 0; build-tests 0; 92 test binaries, all exit 0: 702
  passed, 0 failed, 5 ignored"; "**Lean:** `formal/Window.lean` (blob
  `a9fd7faa`, 1586 lines): exit 0, no `sorry`"; "CI `audit-tools` passed on
  `e0eb65c`."

### Item 2, issue #10: only a verified canonical Proposal closes

- Closed 2026-10-26 15:39 UTC. Closing comment 6420198473: "**Item 2 of
  Protocol-13 is closed by PR #58, merged as `084273c1` (2026-10-26 15:38:50
  UTC).**"
- Implementation: comment 6417725558 names "`cce95b2` (box 4) and `bd62ded`
  (box 3)". The closing comment names the report `02-CANONICAL-PROPOSAL.md` and
  the verdict in PR #58 (comment 6420183989). The report the verdict read is
  the one of `3c418a4` (`git show 3c418a4:Audit/Protocol-13/02-CANONICAL-PROPOSAL.md`);
  on `main` the file is the copy of `core/Montana-Core/protocol-13/` that
  `67db3cc` wrote back.
- Check, closing comment 6420198473: "on Lauterbourg-3 at `cb4283c`, the 43 test
  binaries of `montana-node` gave rc 0: 100 passed, 1 ignored, 0 failed";
  "`mt-store`, `fmt`, `clippy -D warnings` and `metadata --locked` are rc 0";
  "the mutations M1 and M2 make the box 4 and box 3 tests fail"; "CI
  `audit-tools` passed on `3c418a4`."

### Item 3, issue #14: issuance bound to a right

- Closed 2026-10-27 09:00 UTC. Closing comment 6437743716: "Closed: merged into
  main at e612a55; CI audit-tools pass on main (run 40477250041)."
- Implementation: PR #60, "P13-3 (#14): a right is bound to its window,
  recipient, worth and one use -- A1, A2, T4, F-562-1, main merged", merge
  commit `e612a55`. Comment 6424642591 names the A2 recomputation commits
  `dc841a7` and `5d76ec9`. On `main` the frame holds a right's worth to
  `window_credit` (`core/Montana-Core/crates/mt-proof/src/circuit/frame.rs:824-832`).
- Check, comment 6437724909: "Lauterbourg-3 ring a594-60 on the PR #60 branch
  (measurements green after AUDIT 727, d5465b4)"; "CI audit-tools pass on
  ce01975 (run 40476769805)". On `main`,
  `core/Montana-Core/crates/montana-node/tests/issuance_audit.rs:93` is
  `an_oversized_right_is_refused_and_the_right_stays_redeemable_at_its_credit`.

### Item 4, issue #15: one origin of the admission witness

- Closed 2026-10-27 09:00 UTC. Closing comment 6437744613: "Closed: merged into
  main at e612a55; CI audit-tools pass on main (run 40477250041)."
- Implementation: PR #62, "P13-4 (#15): admission witnesses bound to one
  authenticated state -- one-state paths, F-1 (node_commit and suite_id), R6",
  merged into the PR #60 branch as `ce01975` and with it into `main` as
  `e612a55`. Comments 6427650419 and 6427879145 name `880b0b0`, `c8bf49d`
  (`admission_one_state.rs`) and `f0b071f` (F-1, `node_commit` and `suite_id`
  in the public input). On `main` the public input carries `node_commit`
  (`core/Montana-Core/crates/mt-proof/src/circuit/admission.rs:328-336`).
- Check, comment 6437725428: "Lauterbourg-2 ring a594-62 on this branch --
  admission_one_state, admission_audit, measurements (AUDIT 729 at 347f8a7)
  green; four_machines_decide_one_name passed on Lauterbourg-3 (2039 s) and was
  cut by the ring's time cap on Lauterbourg-2 (1226 s, rc -15) -- a cap, not a
  verdict"; "CI audit-tools pass on ce01975 (run 40476769805)."

These closures are the chairman's verdicts on self-verification by the
council's sessions, not an independent external audit.
