# F1: untrusted refusals do not choose the stall verdict

Refs #21. Review 6417443853, F1 only. 2026-10-26 UTC.

Base: `f0d96e505a7b115bfaa1ef1c891ee4bef2a760ce`.
The formatted source patch applied to that base has SHA-256
`6759b509d5cb3df8e88d8133bbf681326616e4758647be3cea82855b44a294f7`.
It exactly matches the five staged Rust files in this change. Documentation and
these evidence files were added afterward; no Rust change followed the run.

On L3, own tree `/srv/montana/gpt-01a1793a-f1`, target
`/srv/montana/gpt-01a1793a-f1-target`; unit `gpt-01a1793a-f1`:
MemoryMax=12G, MemorySwapMax=0, CPUWeight=20, CARGO_BUILD_JOBS=6,
HOME=/root. Available memory before the accepted start: 27 GB.
SSH banner timeout/disconnect delayed the initial submission; those attempts
established no test result. The later start was confirmed by systemd.

Commands run from `core/Montana-Core` (full runner retained as `run.sh`):

1. `nice -n 19 rustfmt --edition 2021 crates/montana-node/src/say.rs crates/montana-node/src/status.rs crates/montana-node/src/pulse.rs crates/montana-node/src/lib.rs crates/montana-node/tests/a_stall_names_its_cause.rs` -- exit 0.
2. `nice -n 19 cargo test --locked --offline -p montana-node --test a_stall_names_its_cause --no-run` -- exit 0.
3. `nice -n 19 unshare -n bash -c 'ip link set lo up && cargo test --locked --offline -p montana-node --test a_stall_names_its_cause -- --test-threads=2'` -- exit 0, 4 passed, 179.36 s.
4. Mutation: reinsert `else if self.refusals() > 0 { Verdict::ProofRefused }`
   before the missing-data/quorum distinction in `Counts::observe`.
   `nice -n 19 unshare -n bash -c 'ip link set lo up && cargo test --locked --offline -p montana-node --test a_stall_names_its_cause a_mutated_attestation -- --test-threads=2'`
   -- exit 101, both selected tests failed, 160.90 s. Both failures name
   `Stalled { on: ProofRefused, ... }`, not a build/environment error.
   The runner restores the original source after retaining the failure log.

The source-only `git diff --check` passed before staging the raw logs. The full
`git diff --cached --check` then returned 2: the unchanged green log ends in a
blank line. The command sequence mistakenly continued to the commit; this receipt
was corrected before the first push. `git diff HEAD^ HEAD --check --
core/Montana-Core/crates/montana-node` returned 0; `git show --format= --check HEAD`
returned 2 for that raw-log blank line only. The log is preserved byte-for-byte.
No build/test ran on the Mac.

The system now reports the missing evidence/quorum and the cumulative local
refusal count side by side. The two new regressions use a real turned signature
byte, with the production verifier. This is the implementing session's check,
not an independent external audit or chairman acceptance. F2-F4, integration
with current main, the full fmt/Clippy/test ring and item 10 acceptance remain
open. This run proves no wire anonymity or other Protocol-13 item.

## Artifact SHA-256

- `gpt-01a1793a-f1-build.out`: `2e14ab8bc6f09258ce44fdb55a2238064f41871a089495bab751adfc5591c483`
- `gpt-01a1793a-f1-green.out`: `d7cf6a964270aa88e9f013914c0df5b64279d127d46cf4657fae88c95163d8b3`
- `gpt-01a1793a-f1-mutation.out`: `9cd2edf6a7d0d371984e3558049f45de8ceac8a229211d6cad8bba44a699f65e`
- `gpt-01a1793a-f1.out`: `c27b3e209a6faf1c893a5650563bc776bcb6d2240ffbe90c2a5598df9b33449b`
- `gpt-01a1793a-f1.rc`: `9a271f2a916b0b6ee6cecb2426f0b3206ef074578be55d9bc94f6f3fe3ab86aa`
- `run.sh`: `78acbe93e4f05dffb712b7e7f84fac785d6f9b984d778284a9b092dff2b8affd`

GPT agent [gpt-01a1793a], model id not visible to the agent
Product: Codex desktop; exact runtime model ID unavailable.
