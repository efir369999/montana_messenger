# Published F-1 channel characterization

Source under test: `a835c1c3ff4bc95ea3c75e02391d3d69e2e08833`, unchanged core crates.
Executed on L2 on 2026-10-26 with Rust 1.92.0, a fresh target directory and private
loopback-only network namespace. Both tests pass: 2 passed, 0 failed, 0 ignored,
0 filtered out. `RESULTS.json` binds the final files to the observed checks.

The first test creates two valid real-library XK handshakes. With no authenticated
expected peer key, the middle holds each channel key, opens a synthetic channel
payload and reseals it for the other channel. It also checks the public identity-key
bytes in the handshake messages. The negative control corrupts a signature and
observes rejection. Signature verification works; this API does not bind the
signature to an externally authenticated intended peer.

This extends already-public AUDIT F-1. It is not a TLS bypass, an application
registration experiment, an inner-letter decryption or a phone/GPA measurement.
The application paths and external authentication boundary are in ../CLAIM-MAP.md.

## Reproduce

From this directory, in an isolated Linux test environment with the documented native
crypto prerequisites:

```sh
cargo +1.92.0 fetch --locked
cargo +1.92.0 fmt -p montana-channel-audit --check
cargo +1.92.0 test --release --locked --offline --jobs 2 -- --test-threads=1
```

Run the test command with loopback in a private network namespace, as in ../run.py.
Do not reuse a target directory from another source snapshot. Cargo.lock was seeded
from the pinned Code lock and resolved for the standalone probe; every registry
name/version/checksum is present in that original lock. No newer registry version was
introduced. The isolated command and log digests are recorded in RESULTS.json.

The first setup attempt lacked cached `futures 0.3.31` and stopped before tests.
After fetching the fixed dependencies, both tests passed. The first formatting check
used `--all`, traversed path dependencies, and reported existing Code formatting as
well as one import in this new probe. Only the new probe's import was formatted.
The final package-scoped formatting check and both tests passed. Earlier failed setup
and formatting logs are retained privately; they are not silently converted to passes.

## Published F-13 parser boundaries

`handshake_boundary.rs` adds one test, with two valid native-library controls (with
and without a one-time prekey). Every proper prefix, each possible appended byte,
each invalid flag, and stale checks at both u64 endpoints were rejected: 19,450
malformed/stale inputs, no panic. The valid controls derived the same session root.
The L2 package formatting check and this test passed; BOUNDARY-RESULTS.json and
boundary-tests.log record the separate run at CPUWeight=1 and MemoryMax=512 MiB.
This is deterministic boundary coverage of this parser, not an exhaustive fuzz
campaign, a WASM test, a proof of all panic paths or a deployed-app experiment.
