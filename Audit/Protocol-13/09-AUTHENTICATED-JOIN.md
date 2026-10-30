# 9. Authenticate first connection and fast sync

**Status: closed.** A node that holds nothing joins the running chain from an anchor of two
consecutive final proposals, judges every certificate from there at the one door, takes the tables
of its head against the head's roots and follows the head. A false server cannot certify its
snapshot by its own announced root: such a snapshot, a forged anchor and a single altered leaf are
refused. This is our own reproduction on our own servers, not an independent external audit, and no
production readiness is claimed.

## Requirement

Authenticated first connection and fast sync. A new node verifies the history from a trusted
beginning or from a confirmed anchor. A false server cannot certify its snapshot by its own
announced root. Test a real connection of a clean node.

## What holds it (main `2f5a1a2`)

Tests on Lauterbourg-3, run a683-k789-j20 of the tree of main `2f5a1a2` (openssl 3.5, liboqs):

- The walk from an anchor: `pulse::join` (`core/Montana-Core/crates/montana-node/src/pulse.rs`)
  judges every answer at the one door and hands the steps to `certificate::walk`. Tests
  `a_walk_from_an_anchor.rs` (electorate of W-2, a proposal awaiting its certificate is not final,
  below quorum, a ticket against the wrong aggregate), `a_device_joins_the_running_chain.rs` and
  `a_machine_away_walks_back_from_its_own_anchor.rs`: rc 0 (step 2, 19:56:17-20:41:50 UTC): `a_device_joins_the_running_chain` 1 passed (749.6 s), `a_device_takes_the_plane_of_its_head` 2 passed (1034.0 s), `a_machine_away_walks_back_from_its_own_anchor` 1 passed (656.6 s), `a_walk_from_an_anchor` 1 passed (259.7 s); 5 passed, 0 failed.
- The value plane of the join (V1-V4): `tests/a_device_takes_the_plane_of_its_head.rs` -- a
  self-rooted plane refused (V2), one credited leaf altered refused (V3), the honest tables taken
  against the head (V1), the chain's roots held after a restart (V4); each assertion red on the code
  without its check (roads a651-m20, a656-v1).
- The door for a telephone: `mtc_machine_join` (`crates/mt-boundary/include/montana_core.h:75`).
  `cargo test --release -p mt-boundary` exited 0 (19:56:17 UTC), with
  `a_telephone_that_held_nothing_walks_to_the_head_through_the_door ... ok` (687 s) and the gate
  `the_set_and_this_crate_agree ... ok`.

A real connection of a clean node on a host: the network run of PR #78 (`run.py --only s2,s7`,
the file at `654cda8`), built from `2f5a1a2`, once on Lauterbourg-2 and once, as a separate
network, on Lauterbourg-3. Topology A of its `RUN.md` on each: four machines a-d open the network,
a fifth machine e, born with an empty store, joins later from an anchor of two consecutive final
proposals taken from a; every machine lives in a network namespace of its own.

- S2 held on both hosts: windows 0..2 final on the four opening machines, one name for every final
  window, every final cement 3..4 of 4, the logs agree with the stores.
- S7, the forged anchor (byte 44 of the later proposal turned) is refused on both hosts: rc 1,
  `refused: a certificate whose agreement does not decide the proposal it finalizes`, and the
  refusal wrote no chain.
- S7, the honest anchor (windows 0 and 1 of a): e reached the network's head on both hosts and
  logged `walked from window 1 to the head at window 3`.
- Each run held 55 of 56 expectations and exited 1. The one failed check, "the new machine holds
  the network's chain -- differ at [0, 1]", compared e's chain from the anchor's earlier window,
  but the anchor's two proposals are handed in, not walked, and e keeps the chain from the window
  after them. The check is corrected in PR #78 (`8ca8173`). Applied to the evidence of both runs
  (snapshot `04-joined`), the corrected check holds: e's windows 2..3 carry a's names
  (Lauterbourg-2 `d504a66d`, `cc24fb10`; Lauterbourg-3 `fa1922dc`, `bff98073`) and window 2 links
  to the anchor's window 1. The corrected `run.py` is not yet run end to end; that run belongs to
  item 13.

The client carries the door: `MontanaCore.xcframework` of the iOS client is built from `2f5a1a2`
(`SOURCE`: commit `2f5a1a2`, clean=yes), `montana_core.h:75` declares `mtc_machine_join`, `nm`
lists `T _mtc_machine_join` in `libmt_boundary.a`; it ships in build 2325.

## What stays outside

The client does not yet open the door from its screens; a telephone that joins by itself is the
work of a later item. The run on several separate hosts is item 13.
