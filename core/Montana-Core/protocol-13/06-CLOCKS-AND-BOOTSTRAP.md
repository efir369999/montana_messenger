# 6. Remove clock authority and implicit private bootstrap

**Status: open across both protocol generations.**

The native candidate removes round-dependent quorum lowering and self-selected
restart authority. Exhausting a polling budget returns an error; it cannot
manufacture a verified answer. Targeted tests exercised that refusal. Polling
delays remain scheduling choices, not evidence permitting a close.

This does not establish clock independence of the earlier `Code` runtime. Its
historical fallback and bootstrap paths require separate verification; earlier
entries in `core/Code/docs/SPEC_DEVIATIONS.md` are dated history, not current
closure evidence. The container's explicit isolated mode must not be presented
as authenticated joining of the public network.

Closure requires replaying the same authenticated protocol state under
different clock values, scheduler delays and machine speeds, with identical
validity and proposer eligibility. The test must exercise the used runtime
paths in both generations and cover initialization. A timer may schedule an
attempt or report a stall; it must not grant consensus authority. Test-only
population, threshold or trust-anchor settings must be explicitly isolated and
unavailable as silent production defaults.

No deployed host's clock was changed during this review.
