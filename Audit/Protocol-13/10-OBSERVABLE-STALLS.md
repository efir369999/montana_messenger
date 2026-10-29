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
not establish finality. Historical (marked 2026-10-27 UTC): the repair is no longer pending as a test: `three_machines_live_a_window` passed in the ring of `4451b21` (92 test binaries, all exit 0, one host, `01-WINDOW-PROOF.md:57`). This item stays open; a run on several hosts stays item 13.

Closure requires the actually used network and operator interfaces to
distinguish insufficient quorum, missing authenticated data, proof rejection
and unavailable diagnostics. A reachable but stalled peer must remain visibly
stalled. Missing status must not display success. Time since progress is an
observation only and cannot authorize a successor or lower the quorum.

The website already distinguishes checkpoint reconstruction and signatures from
finality and authorized issuance. That correction does not supply the missing
core diagnostic service or certify the nodes behind a checkpoint.

## Refused deposits and the observed shortfall

A public deposit that fails verification cannot establish why a quorum or its
supporting data is absent. The node keeps `no data` or `no quorum` as the
observed shortfall and reports the cumulative process-local refusal count beside
it (`refused N`). That count includes rejected proof-bearing objects; it neither
attributes the shortfall to them nor identifies a depositor. A dead diagnostic
door still overrides the observation with `no diagnostics`.

The regression `a_stall_names_its_cause` deposits an attestation with a turned
signature byte beside valid attestations while closing pledges are withheld.
Its required verdict stays `no quorum`, with a nonzero refusal count. A separate
missing-data fixture makes the same check for `no data`. Neither observation
enters a proposal or a state root, and neither authorizes a close.

## No verdict `proof refused`

After the refusal counts stopped selecting the verdict, nothing produced
`proof refused`, and an operator verdict a node can never give is dead surface.
It is removed, not given a new source. Every refusal the node counts is of an
object that arrived at a public point, which anyone may deposit; the node's own
objects that it cannot build end at once as `Unprovable` and never reach a
patience exit. Consensus names what monitoring reports
(`Montana Consensus.md`, "The liveness price"): an electorate that does not
return, data that is not delivered, a missing eligible proposer or verified
certificate. It names no refused proof as a condition. Canon keeps the reasons
of refusal in the machine's own account ("Invariants of the messages of the
wire"), which is where they stay: as `refused N` beside the verdict and in the
per-reason counts of the account line.

The verdicts are therefore `no quorum` (exit 1), `no data` (exit 2) and
`no diagnostics` (exit 4). Exit 3 is retired and given to no other verdict.
Proof rejection is still distinguishable, as the count beside the verdict, but
never as the cause of a shortfall.

## Three readings: closed, waiting, stalled

The live reading of a running node is one of three, and `--status` tells them
apart by text and by exit code:

- `closed window W; refused N` -- the last thing the pulse did was close W.
  It stays the reading while the next window opens. Exit 0.
- `waiting: <verdict>; asking A; waited X of P; refused N` -- a shortfall
  awaited inside the patience of that wait, `X` askings of its budget `P`
  spent. Both are the pulse's own counts, shown and never a threshold. Exit 0:
  a wait inside the budget is a healthy node, not a stall.
- `<verdict>; asking A; refused N` -- the patience ran out on that shortfall,
  or the diagnostic door is gone. Nothing was closed. Exit 1 (`no quorum`),
  2 (`no data`) or 4 (`no diagnostics`).

A node that has made no reading yet in this run, or whose endpoint is absent,
reads `no diagnostics` (exit 4). The regression
`the_status_tells_a_close_a_wait_and_a_stall_apart` closes a window and reads
exit 0 through the binary, then reads a withheld round while it waits (exit 0,
`waiting: no data`) and again after its patience ran out (exit 2).

A quorum shortfall whose rounds keep turning does not exhaust a patience,
because the patience counts the askings of one wait, and so it reads
`waiting: no quorum` with exit 0 for as long as the rounds turn. Whether a
machine should give such a window up at all is the open Gate 0 question of
this item (`Consensus` "the chain may remain halted indefinitely" against
`WAITS_UP_TO`); this reading neither answers nor hides it.

## A status read never takes the store's lock

`status::read` used to probe the data directory's lock. When no node held it,
the probe held it for an instant, and a node starting in that instant refused
its own store as held by another, so an operator polling `--status` during a
restart could stop the restart. The read now takes no lock at all. That the
owner lives is proved by the endpoint: only a status server answers it, the
server holds the very machine that holds the store's lock, and it stops
answering when that owner goes. The locator is read again after the answer, so
a restart between the two never passes the old endpoint's answer off as the new
process's. The regression `a_status_read_in_a_loop_never_stops_a_node_from_starting`
restarts a node fifty times while another thread reads the status in a loop,
and requires every start to succeed.

## A patience that runs out closes nothing, and a restart goes on

`a_patience_run_out_closes_nothing_and_a_restart_goes_on` holds three of the
four patience exits to the second half of Consensus "The liveness price"
(monitoring authorizes no transition): the pulse returns the typed stall, the
reading is that stall, and the head, the last window closed, the kept proposal,
the note root and the census windows stand as before the wait. The record of
the agreement the wait made survives a restart unchanged, and the restarted
machine goes on as the cold start lets it (`Consensus`, "The cold start"): its
store holds that record and closed no window, so it holds a chain and no
anchor; asked to live window zero again it is refused as a store that holds a
chain, and the refusal writes nothing. It enters the network only from an
anchor, by "The join", which a test of one process cannot hand it.

- `a round no beacon ever stood at` (a machine one round ahead of its beacon);
- `waiting budget exhausted: agreement undecided` (closing pledges withheld);
- `a window no proposal of its decision ever stood at` (its own proposal held
  back).

A restart that goes on to close the window it stalled in is not possible in
this tree: the cold start refuses window zero to a store holding a chain, and
`live_doing` starts at no window past the first, because the proposals a window
stands on are held in memory. A node stalled inside a window resumes only from
an anchor.

The exit `a decided proposal that never stood at the points with its roll` is
not reached: its world is a window after a close whose agreement decides a name
the machine did not take, and a machine of this tree neither starts a pulse at
a window past the first (`pulse.rs`, the windows standing on no proposal before
them are refused) nor takes a deposit at a round it has left, so a fixture of
one process cannot arrange it. It stays open for a test with peers.
