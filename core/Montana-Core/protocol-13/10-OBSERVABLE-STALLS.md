# 10. Make protocol stalls observable

**Status: open through the complete operator/network path.**

The earlier core has local head, accumulated-share, threshold and progress-age
diagnostics. The native candidate reports unreconciled beacon cement and returns
without advancing when its waiting budget expires. These are useful partial
observations, not a completed status service for either generation.

The separate-host three-node diagnostic exposed another distinction: thousands
of advancing rounds can coexist with an unchanged window and insufficient heavy
participants. Reporting a growing round alone would hide this stall. A pending
historical-read scheduling repair addresses the observed starvation; it does
not establish finality.

Closure requires the actually used network and operator interfaces to
distinguish insufficient quorum, missing authenticated data, proof rejection
and unavailable diagnostics. A reachable but stalled peer must remain visibly
stalled. Missing status must not display success. Time since progress is an
observation only and cannot authorize a successor or lower the quorum.

The website already distinguishes checkpoint reconstruction and signatures from
finality and authorized issuance. That correction does not supply the missing
core diagnostic service or certify the nodes behind a checkpoint.
