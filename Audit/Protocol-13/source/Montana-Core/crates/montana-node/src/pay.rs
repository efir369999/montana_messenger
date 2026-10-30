// A payment made from a terminal: the machine reaches the one holding the state, asks it where its
// owner's notes stand, builds the frame, and publishes it at the points of the round.
//
// **The paths come over the wire, by the query the set gives for exactly this.** A spender proves
// its notes stand in the tree the far machine holds, and it is that machine that knows where — so
// it asks, and what comes back names a position and never a person.
//
// **What is published names nobody.** A frame is nullifiers, commitments and the nullifier of a
// rate; it carries no amount, no key and no address, and it stands at points every machine computes
// and nobody is told.

use crate::{pulse, round, Machine, NodeError};
use montana_wallet::pay::{Payee, Payment};
use montana_wallet::Wallet;
use mt_proof::poseidon::Digest;
use mt_wire::message::{self, Kind, RootIndex};
use std::path::Path;
use zeroize::Zeroizing;

fn wallet_at(at: &Path) -> Result<Wallet, NodeError> {
    Wallet::open(at).map_err(|e| NodeError::Unreadable {
        what: format!("what this wallet keeps: {e:?}"),
    })
}

fn identifier_of(frame: &[u8]) -> Result<[u8; 32], NodeError> {
    <mt_state::layout::Frame as mt_state::Layout>::parse(frame)
        .map_err(NodeError::Object)?
        .id()
        .map_err(NodeError::Object)
}

fn not_applied() -> NodeError {
    NodeError::Refused {
        what: "a frame its round left without applying",
    }
}

// What a machine does with the right a window minted it: it redeems it into a note of its own
// wallet, in the window that right is accepted in.
//
// **A right is not a note and never becomes one by itself.** A window issues a right; the right is
// extinguished inside a frame, and what comes out is a commitment a person holds — five positions of
// filler and the sixth the right itself, since a machine that has just closed the first window of
// the network holds one right and nothing else. What is published names nobody: nullifiers,
// commitments and the nullifier of a rate, and no amount among them.
//
// The window this right is of is what the operator read off that window when it closed. It is of
// the world in the same way an acquaintance is: the machine cannot ask anybody for it, and nothing
// else it holds implies it. What the right is worth is not asked for: the window's credit, whatever
// the count of that window's cement (Consensus, "The right to a window's coin").
//
// **The note enters the wallet once its frame has applied, and not before.** The frame stands at
// the points of the round and applies with the frames of that round as the machine leaves it, so the
// position the note took is known there, and `settled` is told it — or told why there is none.
pub struct Minted {
    pub value: u128,
    pub position: u64,
}

impl Machine {
    #[allow(clippy::too_many_arguments)]
    pub fn redeem_into(
        &self,
        at: &Path,
        of_the_window: u64,
        window: u64,
        chain: u8,
        round: u32,
        rate_secret: &[u8; 32],
        mut settled: Box<dyn FnMut(Result<Minted, NodeError>) + Send>,
    ) -> Result<(), NodeError> {
        let wallet = wallet_at(at)?;
        let secret = self.machine_secret()?;
        let mut of_the_machine = [0u8; 32];
        of_the_machine.copy_from_slice(&secret[..32]);
        let right = crate::attest::right_of(&of_the_machine, of_the_window)?;
        if right.accepted_in != window {
            return Err(NodeError::Refused {
                what: "a right presented in a window it is not accepted in",
            });
        }
        // **The right walks the part of its window, and only a cement of that window put it in the
        // tree.** The plane of this machine holds the tree of credited rights as the proposals it
        // closed left it; a machine whose part the cement of that window did not hold finds no
        // branch here and has no right of that window to write. Canon, "The right of a machine to
        // its coin of a window, and what redeems it".
        let part = mt_derive::nullifier::part(&of_the_machine, of_the_window).ok_or(
            NodeError::Unprovable {
                what: "the halves of this machine's secret",
            },
        )?;
        let (credited, (siblings, position)) = {
            let plane = self.value()?;
            let branch = plane.credited_branch(&part).ok_or(NodeError::Refused {
                what: "a right of a window whose cement this machine's credited tree does not hold",
            })?;
            (plane.credited(), branch)
        };
        let person = wallet.person().map_err(|_| NodeError::Refused {
            what: "a wallet holding no person",
        })?;
        let person = person.ok_or(NodeError::Refused {
            what: "a wallet holding no person",
        })?;
        let own = montana_wallet::pay::Payee {
            half: mt_derive::note::nf_pk(&person.note_nullifier_key()),
            note_pk: person.payment_key(),
        };
        let root = self.value()?.notes_root();
        let minted = wallet
            .redeem(
                &of_the_machine,
                of_the_window,
                u128::from(right.worth),
                &siblings,
                position,
                &own,
                window,
                rate_secret,
                &root,
                &credited,
            )
            .map_err(|e| NodeError::Unreadable {
                what: format!("a right this machine cannot write a frame for: {e:?}"),
            })?;

        let created = minted
            .created
            .into_iter()
            .next()
            .ok_or(NodeError::Refused {
                what: "a redemption that created no note",
            })?;
        let frame = identifier_of(&minted.frame)?;
        self.stand_the_frame(&minted.frame, window, chain, round)?;
        let at = at.to_path_buf();
        // The note of the redeemed coin, as the wallet of this machine would hold it at a position.
        let wallet_of = at.clone();
        let minted_note = move |position: u64| -> Result<montana_wallet::Note, NodeError> {
            let wallet = wallet_at(&wallet_of)?;
            let person = wallet.person().ok().flatten().ok_or(NodeError::Refused {
                what: "a wallet holding no person",
            })?;
            montana_wallet::Note::of(
                created.value,
                created.note_pk,
                person.note_nullifier_key(),
                created.rcm,
                position,
            )
            .map_err(|_| NodeError::Refused {
                what: "a note that is not of the family",
            })
        };
        let value = created.value;
        self.settle_when_applied(
            (window, chain, round),
            frame,
            // **The operator is told every time**: once as the round leaves, and again where a replay
            // moves the note or leaves the frame out, with the position that now stands or the
            // refusal; and a wallet that would not follow is a refusal the operator reads, never a
            // silence.
            Box::new(move |told| match told {
                // The round left: the note enters the wallet at the position it took.
                crate::Told::Applied(positions) => settled((|| {
                    let position = *positions.first().ok_or(NodeError::Refused {
                        what: "a redemption that took no position",
                    })?;
                    let note = minted_note(position)?;
                    wallet_at(&at)?
                        .enter(note)
                        .map_err(|_| NodeError::Refused {
                            what: "a ledger that would not take the note",
                        })?;
                    Ok(Minted { value, position })
                })()),
                // A replay moved the frame: the note moves to the position the decided roll gave it,
                // and the operator is told the position again.
                crate::Told::Moved(positions) => settled((|| {
                    let position = *positions.first().ok_or(NodeError::Refused {
                        what: "a redemption that took no position",
                    })?;
                    let note = minted_note(position)?;
                    wallet_at(&at)?
                        .move_note(&note.commitment, position)
                        .map_err(|_| NodeError::Refused {
                            what: "a ledger that would not move the note a replay moved",
                        })?;
                    Ok(Minted { value, position })
                })()),
                // The frame applies in no window: the note never stood, and the operator is told so.
                crate::Told::Left => settled((|| {
                    let note = minted_note(0)?;
                    wallet_at(&at)?
                        .forget(&note.commitment)
                        .map_err(|_| NodeError::Refused {
                            what: "a ledger that would not forget the note of a frame applied nowhere",
                        })?;
                    Err(not_applied())
                })()),
                // The window is final: a redemption spends no note of the wallet, so nothing is kept
                // whole to release.
                crate::Told::Final => {}
            }),
        )
    }
}

impl Machine {
    // **A frame stands, and its notices stand with it.** Value states both as one act: the frame at
    // the points of the round its slot names, and one notice at every point of every nullifier it
    // spends, so that two frames spending one note meet at one point wherever they were sent from.
    // Standing them apart would be two places for one act, and the second would be forgotten by
    // whichever caller was written next.
    //
    // What a notice carries is a nullifier and the identifier of the frame — both already published
    // by the frame itself — and no key, no signature and no party.
    pub fn stand_the_frame(
        &self,
        frame: &[u8],
        window: u64,
        chain: u8,
        round: u32,
    ) -> Result<(), NodeError> {
        let points =
            round::points_of_round(window, chain, round).map_err(|_| NodeError::Decree {
                row: "consensus_replicas".to_string(),
            })?;
        for point in &points {
            self.publish_at_the_point(point, window, frame)?;
        }
        for (_, (point, notice)) in notices_of(frame, window)? {
            self.publish_at_the_point(&point, window, &notice)?;
        }
        Ok(())
    }
}

// Every notice a frame owes, with the point each stands at. It is read out of the frame alone, so a
// reader of this function and a reader of Value reach the same set.
type AtItsPoint = ([u8; mt_wire::message::POINT_BYTES], Vec<u8>);

pub fn notices_of(frame: &[u8], window: u64) -> Result<Vec<([u8; 32], AtItsPoint)>, NodeError> {
    let object =
        <mt_state::layout::Frame as mt_state::Layout>::parse(frame).map_err(NodeError::Object)?;
    let identifier = object.id().map_err(NodeError::Object)?;
    let replicas = mt_genesis::scalar("consensus_replicas").ok_or(NodeError::Decree {
        row: "consensus_replicas".to_string(),
    })?;
    let mut out = Vec::new();
    for spend in &object.spends {
        for nullifier in &spend.nullifiers {
            let notice = mt_state::layout::Notice {
                nullifier: *nullifier,
                frame: identifier,
            };
            let bytes = mt_state::Layout::encode(&notice);
            for index in 0..replicas {
                let index = u8::try_from(index).map_err(|_| NodeError::Decree {
                    row: "consensus_replicas".to_string(),
                })?;
                out.push((
                    *nullifier,
                    (
                        mt_derive::delivery::notice_point(nullifier, window, index),
                        bytes.clone(),
                    ),
                ));
            }
        }
    }
    Ok(out)
}

impl Machine {
    // **What names this nullifier, read off its own points.** A reader takes the union of what
    // stands at every point of a nullifier and returns the distinct frames named there. One frame
    // named at every point is a settlement this reader may take in the turn; two frames named, or
    // points naming different single frames, is the race — and this function reports it rather than
    // resolving it, because the canonical order of the window resolves it and nothing here may.
    pub fn frames_naming(
        &self,
        nullifier: &[u8; 32],
        window: u64,
    ) -> Result<Vec<[u8; 32]>, NodeError> {
        let replicas = mt_genesis::scalar("consensus_replicas").ok_or(NodeError::Decree {
            row: "consensus_replicas".to_string(),
        })?;
        let mut named: Vec<[u8; 32]> = Vec::new();
        for index in 0..replicas {
            let index = u8::try_from(index).map_err(|_| NodeError::Decree {
                row: "consensus_replicas".to_string(),
            })?;
            let point = mt_derive::delivery::notice_point(nullifier, window, index);
            for body in self.objects_at_the_point(&point, window)? {
                let Ok(notice) = <mt_state::layout::Notice as mt_state::Layout>::parse(&body)
                else {
                    continue;
                };
                if &notice.nullifier != nullifier {
                    continue;
                }
                if !named.contains(&notice.frame) {
                    named.push(notice.frame);
                }
            }
        }
        named.sort_unstable();
        Ok(named)
    }
}

// What a living machine pays out of its own wallet, against the tree it holds itself.
//
// **A machine that holds the points holds the tree.** The payment of the terminal reaches another
// machine and asks it where the payer's notes stand, because the payer is not that machine. A
// machine living a window is that machine: it applied the frames that put those notes where they
// are, so it asks itself, and the path it walks is the one it would have answered anybody with.
//
// **And it applies its own frame as everybody does.** The frame stands at the points of the round
// and applies with the round's frames in the order of their identifiers as the machine leaves it;
// only then does the wallet spend, take back what the payment left and learn where the payee's
// note stands, and `settled` is told it.
//
// What is published names nobody: nullifiers, commitments and the nullifier of a rate, and no
// amount and no key among them.
pub struct Paid {
    pub value: u128,
    pub position: u64,
    pub rcm: [u8; 32],
    pub note_pk: [u8; 32],
}

impl Machine {
    #[allow(clippy::too_many_arguments)]
    pub fn pay_of_its_own(
        &self,
        at: &Path,
        to: &Payee,
        amount: u128,
        window: u64,
        chain: u8,
        round: u32,
        rate_secret: &[u8; 32],
        mut settled: Box<dyn FnMut(Result<Paid, NodeError>) + Send>,
    ) -> Result<(), NodeError> {
        let wallet = wallet_at(at)?;
        let ledger = wallet.ledger().map_err(|_| NodeError::Refused {
            what: "a ledger this wallet cannot read",
        })?;
        let mine = ledger.held.first().ok_or(NodeError::Refused {
            what: "a wallet holding no note to pay from",
        })?;
        let own = Payee {
            half: mt_derive::note::nf_pk(&mine.nf_key),
            note_pk: mine.note_pk,
        };
        // The paths of the notes being spent, walked in the tree this machine holds.
        let mut paths = Vec::new();
        for note in &ledger.held {
            paths.push(
                self.value()?
                    .path_of(note.position)
                    .ok_or(NodeError::Refused {
                        what: "a note this machine's tree does not hold",
                    })?,
            );
        }
        let (root, credited) = {
            let value = self.value()?;
            (value.notes_root(), value.credited())
        };
        let payment = wallet
            .pay(
                to,
                amount,
                window,
                rate_secret,
                &own,
                &paths,
                &root,
                &credited,
            )
            .map_err(|e| NodeError::Unreadable {
                what: format!("a payment this wallet cannot write a frame for: {e:?}"),
            })?;

        let frame = identifier_of(&payment.frame)?;
        self.stand_the_frame(&payment.frame, window, chain, round)?;
        let at = at.to_path_buf();
        let nf_key = Zeroizing::new(mine.nf_key);
        self.settle_when_applied(
            (window, chain, round),
            frame,
            // **The operator is told every time**: once as the round leaves, and again where a replay
            // moves the frame or leaves it out of every window, with the positions that now stand or
            // the refusal; a wallet that would not follow is a refusal the operator reads.
            Box::new(move |told| match told {
                // The round left and the frame applied: the notes it spent leave the wallet, what it
                // did not pay away comes back at the positions it took, and the operator is told.
                crate::Told::Applied(positions) => settled((|| {
                    let wallet = wallet_at(&at)?;
                    for commitment in &payment.spent {
                        wallet.spend(commitment).map_err(|_| NodeError::Refused {
                            what: "a note this wallet holds",
                        })?;
                    }
                    // What the payment did not pay away is the payer's own, and the wallet is what
                    // knows it.
                    wallet
                        .enter_what_it_left(&payment, &positions, &nf_key)
                        .map_err(|_| NodeError::Refused {
                            what: "a ledger that would not take the note a payment left",
                        })?;
                    paid_at(&payment, &positions)
                })()),
                // A replay moved the frame: every note the payment left the payer moves to the
                // position the decided roll gave it, and the operator is told the payee's position
                // again.
                crate::Told::Moved(positions) => settled((|| {
                    let wallet = wallet_at(&at)?;
                    for (which, left) in payment.created.iter().enumerate().skip(1) {
                        if left.value == 0 {
                            continue;
                        }
                        let position = *positions.get(which).ok_or(NodeError::Refused {
                            what: "a replay that gave a note of the payment no position",
                        })?;
                        let note = montana_wallet::Note::of(
                            left.value,
                            left.note_pk,
                            *nf_key,
                            left.rcm,
                            position,
                        )
                        .map_err(|_| NodeError::Refused {
                            what: "a note that is not of the family",
                        })?;
                        wallet
                            .move_note(&note.commitment, position)
                            .map_err(|_| NodeError::Refused {
                                what: "a ledger that would not move the note a replay moved",
                            })?;
                    }
                    paid_at(&payment, &positions)
                })()),
                // The frame applies in no window: the notes it spent stand again, what it left never
                // stood, and the operator is told so.
                crate::Told::Left => settled((|| {
                    let wallet = wallet_at(&at)?;
                    wallet
                        .take_back(&payment.spent)
                        .map_err(|_| NodeError::Refused {
                        what: "a ledger that would not take back the notes of a frame applied nowhere",
                    })?;
                    for left in payment.created.iter().skip(1) {
                        let note = montana_wallet::Note::of(
                            left.value,
                            left.note_pk,
                            *nf_key,
                            left.rcm,
                            0,
                        )
                        .map_err(|_| NodeError::Refused {
                            what: "a note that is not of the family",
                        })?;
                        wallet.forget(&note.commitment).map_err(|_| NodeError::Refused {
                            what: "a ledger that would not forget the note of a frame applied nowhere",
                        })?;
                    }
                    Err(not_applied())
                })()),
                // The window of the frame is final: the notes it spent are past moving and past
                // taking back, so the wallet lets go of what it kept of them whole; the nullifiers
                // stay. A wallet that would not is a refusal the operator reads.
                crate::Told::Final => {
                    if let Err(why) = wallet_at(&at).and_then(|wallet| {
                        wallet.release(&payment.spent).map_err(|_| NodeError::Refused {
                            what: "a ledger that would not release the notes of a final spending",
                        })
                    }) {
                        settled(Err(why));
                    }
                }
            }),
        )
    }
}

// What a payer is told of a payment: the payee's note, its value and the position it stands at.
fn paid_at(payment: &montana_wallet::pay::Payment, positions: &[u64]) -> Result<Paid, NodeError> {
    let created = payment.created.first().ok_or(NodeError::Refused {
        what: "a payment that created no note",
    })?;
    Ok(Paid {
        value: created.value,
        position: *positions.first().ok_or(NodeError::Refused {
            what: "a payment that took no position",
        })?,
        rcm: created.rcm,
        note_pk: created.note_pk,
    })
}

// The path to one leaf of the tree of notes, asked of the machine holding it. Nothing comes back
// for a leaf that does not stand there, which is the ordinary answer and not an error.
fn path_of(link: &mut mt_net::Link, window: u64, position: u64) -> Result<Vec<Digest>, NodeError> {
    let mut key = [0u8; 32];
    key[..8].copy_from_slice(&position.to_le_bytes());
    link.send(
        Kind::StateQuery,
        &message::encode_state_query(window, RootIndex::Notes, &key),
    )
    .map_err(NodeError::Net)?;
    let (kind, arrived) = link.receive().map_err(NodeError::Net)?;
    if kind != Kind::StateAnswer || arrived.len() < 4 {
        return Err(NodeError::Refused {
            what: "an answer of another kind than a state query's",
        });
    }
    let mut declared = [0u8; 4];
    declared.copy_from_slice(&arrived[..4]);
    let width = 4 + u32::from_le_bytes(declared) as usize;
    if arrived.len() < width {
        return Err(NodeError::Refused {
            what: "an answer of a state query shorter than it declares",
        });
    }
    let proof = message::parse_state_answer(&arrived[..width]).map_err(|_| NodeError::Refused {
        what: "an answer of a state query that does not parse",
    })?;
    if proof.is_empty() || proof.len() % 32 != 0 {
        return Err(NodeError::Refused {
            what: "a leaf this far side does not hold",
        });
    }
    proof
        .chunks(32)
        .map(|sibling| {
            let mut bytes = [0u8; 32];
            bytes.copy_from_slice(sibling);
            Digest::of_bytes(&bytes).ok_or(NodeError::Refused {
                what: "a sibling that is not a digest of the family",
            })
        })
        .collect()
}

impl Machine {
    // A payment carried out whole: reach, ask, build, prove, publish. What comes back is the
    // payment, so the payer can enter its own notes and hand the payee theirs.
    #[allow(clippy::too_many_arguments)]
    pub fn pay(
        &self,
        line: &str,
        wallet: &Wallet,
        payee: &Payee,
        own: &Payee,
        amount: u128,
        window: u64,
        chain: u8,
        at: u32,
        rate_secret: &[u8; 32],
        root: &Digest,
        credited: &Digest,
    ) -> Result<Payment, NodeError> {
        let mut link = self.reach(line)?;
        let inputs = mt_genesis::scalar("spend_inputs").ok_or(NodeError::Decree {
            row: "spend_inputs".to_string(),
        })?;
        let count = mt_genesis::scalar("spends_per_frame").ok_or(NodeError::Decree {
            row: "spends_per_frame".to_string(),
        })?;
        let ledger = wallet.ledger().map_err(|_| NodeError::Refused {
            what: "a ledger this wallet did not write",
        })?;
        let taking = (inputs * count) as usize;
        if ledger.held.len() < taking {
            return Err(NodeError::Refused {
                what: "fewer notes than a frame of this Decree consumes",
            });
        }
        let mut paths = Vec::with_capacity(taking);
        for note in &ledger.held[..taking] {
            paths.push(path_of(&mut link, window, note.position)?);
        }
        let payment = wallet
            .pay(
                payee,
                amount,
                window,
                rate_secret,
                own,
                &paths,
                root,
                credited,
            )
            .map_err(|_| NodeError::Unprovable {
                what: "a frame over the notes this wallet holds",
            })?;
        let points = round::points_of_round(window, chain, at).map_err(|_| NodeError::Decree {
            row: "consensus_replicas".to_string(),
        })?;
        // A frame stands at the points of its round for whoever holds them, so it is published at
        // every one of them rather than handed to a machine chosen here.
        for point in &points {
            pulse::publish_at(&mut link, point, window, &payment.frame)?;
        }
        Ok(payment)
    }
}
