#!/bin/bash
export PATH=/root/.cargo/bin:$PATH
exec > /srv/montana/gpt-01a1793a-f1.out 2>&1
set -u
run_step() {
  local label="$1"; shift
  printf '%s\n' "$*"
  "$@" > "/srv/montana/gpt-01a1793a-f1-${label}.out" 2>&1
  local rc=$?
  echo "$rc" > "/srv/montana/gpt-01a1793a-f1-${label}.rc"
  echo "$label rc=$rc"
  return "$rc"
}
run_step fmt nice -n 19 rustfmt --edition 2021 crates/montana-node/src/say.rs crates/montana-node/src/status.rs crates/montana-node/src/pulse.rs crates/montana-node/src/lib.rs crates/montana-node/tests/a_stall_names_its_cause.rs || exit $?
git diff --output=/srv/montana/gpt-01a1793a-f1-formatted.patch
run_step build nice -n 19 cargo test --locked --offline -p montana-node --test a_stall_names_its_cause --no-run || exit $?
run_step green nice -n 19 unshare -n bash -c 'ip link set lo up && cargo test --locked --offline -p montana-node --test a_stall_names_its_cause -- --test-threads=2' || exit $?
python3 - <<'MUTATE'
from pathlib import Path
p=Path('crates/montana-node/src/say.rs')
s=p.read_text()
Path('/srv/montana/gpt-01a1793a-f1-say-original.rs').write_text(s)
a='        } else if missing {'
assert s.count(a)==1
p.write_text(s.replace(a,'        } else if self.refusals() > 0 {\n            Verdict::ProofRefused\n'+a))
MUTATE
run_step mutation nice -n 19 unshare -n bash -c 'ip link set lo up && cargo test --locked --offline -p montana-node --test a_stall_names_its_cause a_mutated_attestation -- --test-threads=2'
mutation_rc=$?
cp /srv/montana/gpt-01a1793a-f1-say-original.rs crates/montana-node/src/say.rs
if [ "$mutation_rc" = 101 ]; then echo 0 > /srv/montana/gpt-01a1793a-f1.rc; else echo 1 > /srv/montana/gpt-01a1793a-f1.rc; fi
