# 13. Reproduce distributed finality and joining

**Status: open. Server testing has not established canonical network finality.**

The author authorized the same engineer to run the acceptance scenario on a
separate server. That removes the need to wait for another operator; it does
not turn self-verification into an independent external audit.

All verification after the author's server-only instruction runs on the
separate Linux host. Native network tests use an isolated network namespace
with its own loopback. They do not add host listeners or change production
units, firewall, clocks or stored user data.

A complete-workspace attempt stopped at the three-machine test: the process
had not completed after about sixteen minutes and reached approximately
3.5 GiB resident memory. A bounded diagnostic showed growing rounds with only
one or two of three heavy participants. The historical-read cursor starved
early rounds while the tip advanced. A repaired scheduler is being checked.
The interrupted sweep is not a pass. Historical (marked 2026-10-27 UTC): this paragraph is the state of the separate-host diagnostic. `three_machines_live_a_window` passed in the ring of `4451b21` (92 test binaries, all exit 0, one host, `01-WINDOW-PROOF.md:57`); that the scheduler was repaired is not recorded in this folder. A run on several hosts stays this item.

Even a repaired three-machine count-based scenario would not close this item.
The acceptance package must contain actual canonical Proposals, proofs and roots
for weighted multi-node closure, quorum loss and recovery, partition, return,
restart and authenticated fresh-node joining. No single participant may reach
quorum alone. The same public verifier must reject the adversarial artifacts.

Kaito's complete anonymous node/client/minting workflow remains unverified.
An isolated demo, advancing counter, matching roots or selected green tests
cannot be substituted for these artifacts and acceptance cases.
