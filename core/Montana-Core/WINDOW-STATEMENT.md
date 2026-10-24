# Complete window statement: item 1

Superseded on 2026-10-15 by [WINDOW-RELATION.md](WINDOW-RELATION.md), which states why the relation
below has no prover and what relation replaces it. The confidentiality prerequisite below is closed by
the hiding construction of the scheme; the rest is kept as the record of what was required.

**Acceptance status: open.** This work is limited to the first handover requirement.
The arithmetic component is being repaired; a complete window prover and verifier are still
required. No arithmetic result is a certificate of finality or authority to issue value.

## Required relation

The verifier's authenticated context must fix the Genesis, protocol suite, parent Proposal and
height, predecessor state roots, active population, total standing and historical draw state.
Candidate bytes cannot authenticate their own context. A complete accepting statement must
establish all of the following together:

1. The proposed predecessor and input roots are the authenticated predecessor's values.
2. Each contributing part is unique and belongs to that predecessor's admitted population;
   its weight is the permitted weight from that state, not a claimant-selected scalar.
3. A fresh commitment to the integer sum is linked to those exact contributions. Each
   recommitment proves its child-sum relation, bounded opening and required child verification.
4. The sum satisfies the fixed parent quorum against the authenticated total. The count of
   living machines is a separate committed quantity and is the divisor required by Consensus.
5. Canonical operations produce the proposed output roots under the permitted transitions.
6. The Proposal's one-time signing key is bound to the admitted runner's secret; the ticket
   clears the historical threshold against the specified prior aggregate. Knowing somebody
   else's qualifying ticket does not authorize this key.
7. The history mechanism binds the predecessor statement, every accumulation/reset and the
   terminal discharge to Genesis under a complete soundness argument at Canon's target.

These obligations are conjunctive. A correct threshold check with an invented total, or a valid
arithmetic step over an unauthenticated accumulator, does not satisfy the relation.

## Confidentiality prerequisite

The proof system must hide its private witness before this relation can claim hidden weights.
The presence writer currently fills each of its four lane columns with one word of the
permanent spending half. The proof scheme interpolates those columns without randomization.
The interpolating polynomial of a constant column is that constant; every serialized query
therefore carries the word itself. This is a direct extraction, without a search for the
machine secret or an attack on the hash function.

`montana-node/tests/presence_disclosure_audit.rs` exercises the actual node producer and
`verify_heavy`. Its observer takes only serialized proof bytes and attempts to recover the
spending half and compute part and credit nullifiers at other heights. A passing
`open_finding_*` reproduction confirms the defect, not its repair. The observer neither
recovers a signing key nor establishes that it can spend another machine's funds.

Closing this prerequisite requires a complete witness-hiding construction for the proof
transcript, including the trace, out-of-domain evaluations and FRI material, with its
degree, entropy and soundness accounting. Changing a column's layout or hiding an API field
does not establish that construction. The distinction between trace randomization and the
other polynomial disclosures is discussed in
[Haboeck and Kindi, A note on adding zero-knowledge to STARKs](https://eprint.iacr.org/2024/1037).
This reference is a design input, not a claim that its construction is implemented here.

## Concrete counterexamples

The original arithmetic AIR accepts a zero challenge, which drops its instance, and accepts
chosen nonzero challenges cancelling a fabricated predecessor. Both full proof reproductions
completed on the public source snapshot as well as on the candidate. They exercise the generic
arithmetic verifier, not an implemented complete Proposal verifier.

The standing commitment exposes another necessary distinction. Use zero `r1`, place `eta` in
the first coefficient of `r2`, and set every other coefficient to zero. Four individually bounded
commitments of weight one sum to the same bytes as a bounded commitment of weight five with
first `r2` coefficient minus one:

```
4 * (17 * 1 + 4) = 84 = 17 * 5 - 1
```

The actual integer sum is four. With parent total seven, the real weight fails the current
quorum while the false opening passes it. This does not break the binding of one commitment:
the summed honest opening has already left its randomness bound. It demonstrates why a short
opening of the running sum cannot substitute for the authenticated tree of fresh commitments.
The separate integer example `255 + 1` also requires a carry that coefficient-wise addition of
the encoded commitments does not perform. Both examples reproduce through `mt-suite::standing`
on the separate Linux build host; neither changes production state or establishes a network
exploit against a complete window verifier.

## Arithmetic repair and its exact boundary

The component now constrains a nonzero inverse on every active challenge row. Its checked
prover/verifier API fixes the exact input length and canonical coefficients and recomputes every
challenge from the fixed incoming accumulators and instance. Sampling rejects the incomplete
bucket of the proof field before reduction and rejects zero. Canon specifies those bytes and
the order of derivation. Server validation and the resulting AIR/Genesis migration must precede
publication of this candidate as checked source.

This repairs dropped instances and caller-selected challenges at that component's verifier.
It does not authenticate the incoming accumulator or supply any of obligations 1–7 above.
The generic proof API remains a verifier of its supplied AIR and is not a protocol acceptance
API. The current node does not gain a complete window verifier merely by adding this component.

## Soundness work that cannot be replaced by tests

The current proposed argument assumes that every committed equality is fixed before its
challenge, that every predecessor is authenticated, and that decomposition/recommitment preserves
the claim and its binding. The implementation and a complete theorem must establish these
premises. A proof of scalar multiply-add arithmetic establishes none of them.

For comparison, [Boneh and Chen, LatticeFold, sections 3–4](https://eprint.iacr.org/2024/257.pdf)
separately construct short-opening folding and a computation-checking relation; their range
proof and linearization are part of the soundness construction. This citation is a design
reference, not an assertion that Montana implements that protocol or inherits its theorem.
[LatticeFold+](https://eprint.iacr.org/2025/247) likewise includes a range proof and a dedicated
transformation for folding commitments. Naming decomposition without its binding relation is
not an implementation of either result.

The six nonzero scalar challenges have a challenge space of `(q - 1)^6`; an exact probability
argument must use that space and account for adaptive attempts and history length. The previous
conditional `k / q^6` estimate is not a proof of the required lifetime security bound.

## Acceptance evidence still required

The actual complete verifier must accept a valid window and reject, independently, an
insufficient quorum, a forged weight (including the aggregate above), a wrong input or output
root, and a ticket bound to another key. The test must alter the verifying relation's inputs,
not only refuse a witness in an honest prover. History tests must include a forged parent,
changed or omitted resets, malformed discharge and Genesis substitution. Passing arithmetic
regressions closes only their named defects. Item 1 remains open until the whole relation and
soundness obligations stand.
