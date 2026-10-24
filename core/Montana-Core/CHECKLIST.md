# The checklist of the living network

**Current review, 2026-10-14:** the observations below are historical operational reports,
not current acceptance of the thirteen protocol requirements. The live loop still uses a
count-based close and a beacon identifier; full window finality and authorized issuance remain
open in [AUDIT.md](AUDIT.md). A historical log saying that a window closed or minted is not
evidence of those missing properties. The current server run and its limits are recorded in
[SESSION-35.md](SESSION-35.md); this review does not reaffirm every earlier host claim.

What must hold on real hosts, in order. One item at a time: built, green in the small, run on the
hosts, and only then the next number. An item is **done** when it was measured on the hosts and the
machines' own accounts say so — never when it merely compiles.

Every item names what proves it, so that nobody has to remember what "works" meant.

## Done, and measured

1. **A machine is born and names itself.** It draws its secret from six sources with the health
   tests over them, refuses a second drawing, and prints where it answers, the acquaintance to hand
   over, the six groups of digits two people compare by voice, and the naming half it stands in a
   window by. — *Measured on three hosts.*

2. **The tree builds from source on any machine.** macOS on ARM64, Ubuntu 24.04 with glibc 2.39,
   Ubuntu 26.04 with glibc 2.43 — each built it itself from the README's commands, with rustup as
   the only tool. A binary built against the older glibc runs on the newer. — *Measured on three.*

3. **Two machines meet.** An acquaintance handed over out of band, a handshake, and one transcript
   computed by both sides. — *Measured over a tunnel and over a port opened to the world; the two
   runs do not differ, which is Network's sentence about routes made a measurement.*

4. **Two machines live windows, one after another.** Rounds, a cement of both, a window closed on
   that cement, and one equal share minted to each — six thousand five hundred million per machine
   per window, which is the baseline halved. — *Measured on two hosts, two windows, twice.*

5. **A machine keeps an account of itself.** Cells arrived, held, and refused under each rule
   separately; objects published and pushed; collections asked and cells pulled; points read back
   and points answered from memory; attestations entered, repeated, and refused with the reason
   each. Written whenever what it holds changes and again while nothing does. — *It found three
   defects in its first hour, including one in itself.*

6. **Three machines close a window.** The quorum asks all three, since the Decree names
   sixty-seven hundredths and not two thirds; the links are one per pair and no more.
   — *Measured on three hosts: all three closed one window on a cement naming three, each minting
   four thousand three hundred and thirty-three million, which is the baseline over three with the
   remainder carried. It took three closures to get there, and the machines' own accounts named each
   one: a point takes a delivery whole or refuses the whole of it; the door counts what arrives at
   it; and a machine opens its window before it opens its door. The last is proven by a number — the
   count of deposits refused for a point this machine did not hold went from one thousand one
   hundred and four to nought.*

## Not yet, and named rather than assumed

7. **A right becomes a note.** A window mints a right; a right is redeemed inside a frame and
   becomes a note a person holds. — *Measured on the hosts. Three of them closed window 1040 on a
   cement of three; the right one machine took there is accepted in window 1183, so the three lived
   that window and the machine redeemed it: four thousand three hundred and thirty-three million at
   position nought, and the wallet on the disk holds it after the node has gone. Three closures got
   it there, each named by the machine rather than guessed — the terminal had no path from a right
   to a note at all; the redemption proved against an empty tree of admitted machines instead of the
   cohort's; and the machine's own value plane verified that proof against an empty tree too, so it
   refused its own true frame.*

8. **A wallet on one host pays a wallet on another, and the payee takes it.** The payer builds the
   frame against the tree as it stands, proves it, publishes it at the points of the round it is
   living; every machine holding those points verifies and applies it; the payee takes the note into
   its own wallet. — *Measured on three hosts. A wallet on a server went from nought to a
   thousand million paid from a machine on a laptop, and a wallet on the laptop from nought to a
   thousand million paid from a machine on a second server — the first value ever to reach a far side in this
   tree. The run named five defects of its own, each by a number rather than a suspicion, and each
   is closed: a payment that destroyed what it did not pay away; a value plane that did not survive
   a stop; an errand carried out after the window it belonged to had closed; a patience that
   measured honest work instead of guarding against a hang; and a machine that dropped the frame it
   had already taken over the wire. What no single host could have shown is why three were needed:
   the defects were legible only in the difference between a fast machine and a slow one.*

   **A payment settles when it stands, and waits for no window.** — *Measured in the small, and
   stated in the set for the first time: a payee spends onward to a third owner inside one window,
   with the cement empty and no proposal anywhere. What one echo does not yet carry is named in the
   register of what the set does not yet fix.*

   **The payer's own frame applies with its round, and its wallet settles after.** — *Green in the
   small on 2026-10-16 (`a_payers_own_frame_applies_with_its_round.rs`): the tree of notes and the
   wallet hold still until the machine leaves the round, and the payer learns where the payee's note
   stands as the round applies the frame in the order of the names. Never on the hosts.*

9. **A machine applies what stands at its points while it lives.** — *Written into the pulse,
   never measured on the hosts.*

10. **A wallet stopped and started again holds the notes it held.** — *Green in the small, never on
    a host.*

11. **A stranger reproduces it.** Somebody who is not this tree's author takes the documents and the
    README and reaches the same state on their own machines. — *Nobody has.*

12. **Windows without end.** Every run above named how many windows to live and stopped. A machine
    that runs until it is stopped, over hours, has never been watched. — *Not run.*

13. **A machine joins a chain already running.** The join of a device that holds nothing, from an
    anchor its operator handed it, walking the retained certificates to the head and verifying
    each as the living did. — *Green in the small on 2026-10-15: two machines live four windows and
    a third walks from an anchor to their head through the one door
    (`montana-node/tests/a_device_joins_the_running_chain.rs`). Never on the hosts.*

## The rule this checklist stands on

An item moves out of "not yet" when the hosts have done it and their own accounts show it — not
when a test passes in the small, and not when the code looks right. Everything above that says
*measured* names where it was measured. Everything that does not is a claim nobody has earned yet.
