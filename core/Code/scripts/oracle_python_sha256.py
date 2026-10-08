#!/usr/bin/env python3
"""
External SHA-256 oracle for Montana M4 composite hash compositions.

Purpose: Pass 25 (Independent Oracle / Differential Check) per CRITIC.md.
The current unit tests cross-check `domain::X` constants against the literals
`b"mt-X"` through the SAME Rust SHA-256 implementation — circular validation.
This script provides a computation from Python `hashlib.sha256` (CPython OpenSSL
binding) — an independent reference for cross-impl conformance.

Usage:
    python3 scripts/oracle_python_sha256.py

Output: hex digests for every M4 composite hash on binding test inputs.
Tests in crates/mt-lottery/tests/external_oracle.rs + the mt-entry analogue
read this output and assert (or the hardcoded test fixture is updated).

All formulas conform to the spec via the mt-codec::domain registry +
NUL byte separator pattern (mt-crypto::hash):
    SHA-256(domain || 0x00 || part0 || part1 || ...)
"""

import hashlib
import sys


def hash_with_domain(domain: bytes, *parts: bytes) -> bytes:
    """Equivalent of mt-crypto::hash(domain, &[parts]):
    SHA-256(domain || 0x00 || parts[0] || parts[1] || ...).
    """
    h = hashlib.sha256()
    h.update(domain)
    h.update(b"\x00")
    for p in parts:
        h.update(p)
    return h.digest()


def fixed_block(byte_value: int, length: int) -> bytes:
    """Helper — fixed byte repeated. Matches the Rust tests (e.g., [0x11; 32])."""
    return bytes([byte_value]) * length


def run() -> dict:
    """Compute oracle outputs for all M4 composite hashes on binding inputs.

    Inputs correspond to the mt-lottery / mt-entry / mt-consensus determinism
    invariants test vectors — each test uses the same byte patterns,
    the Python oracle output must match the Rust output byte for byte.
    """
    # Common test inputs (matching crates/mt-lottery/tests/determinism_invariants.rs
    # and crates/mt-entry/tests/determinism_invariants.rs)
    t_r = fixed_block(0x11, 32)
    cba = fixed_block(0x22, 32)
    node_id = fixed_block(0x33, 32)
    pubkey = fixed_block(0x33, 1952)  # PUBLIC_KEY_SIZE

    results = {}

    # --- mt-lottery::compute_endpoint ---
    # spec: SHA-256("mt-lottery" || NUL || t_r || cba || node_id || w_le)
    # window_index = 7, u32 LE = 07 00 00 00
    w_le = (7).to_bytes(4, "little")
    results["compute_endpoint(t_r=11..,cba=22..,node_id=33..,w=7)"] = (
        hash_with_domain(b"mt-lottery", t_r, cba, node_id, w_le).hex()
    )

    # --- mt-entry::candidate_ssha_init ---
    # spec: SHA-256("mt-candidate-ssha-init" || NUL || timechain || cba || node_id)
    results["candidate_ssha_init(t_r=11..,cba=22..,node_id=33..)"] = (
        hash_with_domain(b"mt-candidate-ssha-init", t_r, cba, node_id).hex()
    )

    # --- mt-entry::selection_sort_key ---
    # spec: SHA-256("mt-selection" || NUL || timechain || cba || node_id)
    results["selection_sort_key(t_r=11..,cba=22..,node_id=33..)"] = (
        hash_with_domain(b"mt-selection", t_r, cba, node_id).hex()
    )

    # --- mt-entry::nr_sort_key ---
    # spec: SHA-256("mt-nodereg-sort" || NUL || timechain || cba || node_pubkey)
    # node_pubkey = [0x33; 1952] (PUBLIC_KEY_SIZE)
    results["nr_sort_key(t_r=11..,cba=22..,pubkey=33..*1952)"] = (
        hash_with_domain(b"mt-nodereg-sort", t_r, cba, pubkey).hex()
    )

    # --- Distinct domain separators check ---
    # Three different domains for the same (t_r, cba, node_id) input — must produce
    # 3 different outputs (NUL pattern + domain isolation).
    sel = hash_with_domain(b"mt-selection", t_r, cba, node_id)
    ssha = hash_with_domain(b"mt-candidate-ssha-init", t_r, cba, node_id)
    nr = hash_with_domain(b"mt-nodereg-sort", t_r, cba, pubkey)
    distinct = (sel != ssha) and (ssha != nr) and (sel != nr)
    results["distinct_domains_for_three_compositions"] = "PASS" if distinct else "FAIL"

    # --- compute_endpoint dependencies (each input change → different output) ---
    base = hash_with_domain(b"mt-lottery", t_r, cba, node_id, w_le)
    diff_t_r = hash_with_domain(
        b"mt-lottery", fixed_block(0xFF, 32), cba, node_id, w_le
    )
    diff_cba = hash_with_domain(
        b"mt-lottery", t_r, fixed_block(0xFF, 32), node_id, w_le
    )
    diff_node = hash_with_domain(
        b"mt-lottery", t_r, cba, fixed_block(0xFF, 32), w_le
    )
    diff_w = hash_with_domain(b"mt-lottery", t_r, cba, node_id, (8).to_bytes(4, "little"))
    sensitivity = (
        base != diff_t_r and base != diff_cba and base != diff_node and base != diff_w
    )
    results["compute_endpoint_input_sensitivity"] = (
        "PASS" if sensitivity else "FAIL"
    )

    return results


def main():
    results = run()
    print("# External SHA-256 oracle (Python hashlib) for M4 composite hashes")
    print("# Pass 25 Independent Oracle: cross-check Rust mt-crypto::hash output")
    print()
    for key, value in results.items():
        print(f"{key:60s} = {value}")
    # Exit non-zero if distinct/sensitivity checks fail
    if (
        results.get("distinct_domains_for_three_compositions") != "PASS"
        or results.get("compute_endpoint_input_sensitivity") != "PASS"
    ):
        print("\n[FAIL] domain separation or input sensitivity broken")
        sys.exit(1)
    print("\n[PASS] all oracle invariants hold")


if __name__ == "__main__":
    main()
