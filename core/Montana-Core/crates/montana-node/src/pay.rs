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

// What a machine does with the right a window minted it: it redeems it into a note of its own
// wallet, in the window that right is accepted in.
//
// **A right is not a note and never becomes one by itself.** A window issues a right; the right is
// extinguished inside a frame, and what comes out is a commitment a person holds — five positions of
// filler and the sixth the right itself, since a machine that has just closed the first window of
// the network holds one right and nothing else. What is published names nobody: nullifiers,
// commitments and the nullifier of a rate, and no amount among them.
//
// The window whose right this is, and how many machines its cement named, are what the operator
// read off that window when it closed. They are of the world in the same way an acquaintance is:
// the machine cannot ask anybody for them, and nothing else it holds implies them.
pub struct Minted {
    pub value: u128,
    pub position: u64,
}

impl Machine {
    #[allow(clippy::too_many_arguments)]
    pub fn redeem_into(
        &self,
        wallet: &Wallet,
        cohort: &pulse::Cohort,
        of_the_window: u64,
        living: usize,
        window: u64,
        chain: u8,
        round: u32,
        rate_secret: &[u8; 32],
    ) -> Result<Minted, NodeError> {
        let secret = self.machine_secret()?;
        let mut of_the_machine = [0u8; 32];
        of_the_machine.copy_from_slice(&secret[..32]);
        let right = crate::attest::right_of(&of_the_machine, of_the_window, living)?;
        if right.accepted_in != window {
            return Err(NodeError::Refused {
                what: "a right presented in a window it is not accepted in",
            });
        }
        let branch = cohort
            .branch_of(&of_the_machine)
            .ok_or(NodeError::Refused {
                what: "a machine that stands in no cohort of this window",
            })?;
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
        // The tree of admitted machines this redemption proves the machine stands in is the cohort's
        // own, and never an empty one: what the frame asserts is that this machine is among those
        // the window admitted, and an empty root asserts that it is among nobody.
        let admitted = cohort.root();
        let root = self.value()?.notes_root();
        let minted = wallet
            .redeem(
                &of_the_machine,
                of_the_window,
                u128::from(right.share),
                &branch.siblings,
                branch.position,
                &own,
                window,
                rate_secret,
                &root,
                &admitted,
            )
            .map_err(|e| NodeError::Unreadable {
                what: format!("a right this machine cannot write a frame for: {e:?}"),
            })?;

        self.stand_the_frame(&minted.frame, window, chain, round)?;
        let object = <mt_state::layout::Frame as mt_state::Layout>::parse(&minted.frame)
            .map_err(NodeError::Object)?;
        let positions = self.apply_and_keep(&object, window)?;
        let created = minted.created.first().ok_or(NodeError::Refused {
            what: "a redemption that created no note",
        })?;
        let position = *positions.first().ok_or(NodeError::Refused {
            what: "a redemption that took no position",
        })?;
        let note = montana_wallet::Note::of(
            created.value,
            created.note_pk,
            person.note_nullifier_key(),
            created.rcm,
            position,
        )
        .map_err(|_| NodeError::Refused {
            what: "a note that is not of the family",
        })?;
        wallet.enter(note).map_err(|_| NodeError::Refused {
            what: "a ledger that would not take the note",
        })?;
        Ok(Minted {
            value: created.value,
            position,
        })
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
        wallet: &Wallet,
        to: &Payee,
        amount: u128,
        window: u64,
        chain: u8,
        round: u32,
        rate_secret: &[u8; 32],
    ) -> Result<Paid, NodeError> {
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
        let (root, admitted) = {
            let value = self.value()?;
            (value.notes_root(), value.admitted())
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
                &admitted,
            )
            .map_err(|e| NodeError::Unreadable {
                what: format!("a payment this wallet cannot write a frame for: {e:?}"),
            })?;

        self.stand_the_frame(&payment.frame, window, chain, round)?;
        let object = <mt_state::layout::Frame as mt_state::Layout>::parse(&payment.frame)
            .map_err(NodeError::Object)?;
        let positions = self.apply_and_keep(&object, window)?;
        for commitment in &payment.spent {
            wallet.spend(commitment).map_err(|_| NodeError::Refused {
                what: "a note this wallet holds",
            })?;
        }
        // What the payment did not pay away is the payer's own, and the wallet is what knows it.
        wallet
            .enter_what_it_left(&payment, &positions, &mine.nf_key)
            .map_err(|_| NodeError::Refused {
                what: "a ledger that would not take the note a payment left",
            })?;
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
        admitted: &Digest,
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
                admitted,
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
