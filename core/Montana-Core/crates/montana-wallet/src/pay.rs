// A payment: the frame one wallet builds to pay another, and what it hands back to its owner.
//
// **A frame has one shape whatever it pays.** The Decree fixes three spends, two notes consumed and
// two created in each, so a payment of one amount and a payment of six are the same object of the
// same width — an observer counts nothing off it. The spends a payment does not need carry the
// payer's own value from one note to another, which is what makes them indistinguishable from the
// one that pays.
//
// **Nothing is arranged with the recipient.** What a payer needs of them is the naming half of
// their nullifier key and the key a note is paid to, both of which are public and neither of which
// names a person. What comes back is the note the recipient will hold, so it reaches them by the
// same wire everything else does.

use crate::{Note, Wallet, WalletError};
use mt_proof::circuit::frame::{Consumed, Created, Frame, Places, Rate, Spend};
use mt_proof::circuit::redemption::{Held, HeldRight};
use mt_proof::poseidon::Digest;

// Whom a payment is for: the naming half of their nullifier key and the key a note of theirs is
// paid to. Both are public values of a person and neither is a name.
#[derive(Clone, Copy)]
pub struct Payee {
    pub half: [u8; 32],
    pub note_pk: [u8; 32],
}

// What a payment turns into: the object that crosses the wire, and the notes it created — the
// first for the payee, the rest the payer's own. A payer enters its own and hands the payee theirs.
pub struct Payment {
    pub frame: Vec<u8>,
    pub created: Vec<Created>,
    pub spent: Vec<[u8; 32]>,
}

// The blinding factors of the notes a payment creates. They are drawn once, here, and they are what
// keeps two payments of one amount from looking alike; a caller supplying them would be choosing
// what must be drawn.
fn drawn(of: &[u8; 32], at: usize) -> [u8; 32] {
    mt_codec::hash(
        mt_codec::domain::MT_NOTE_KEY,
        &[
            mt_codec::Part::of(of),
            mt_codec::Part::of(&(at as u64).to_le_bytes()),
        ],
    )
}

impl Wallet {
    // The frame that pays `amount` to `payee`, over the notes this wallet holds. Every note of the
    // frame is consumed and its value comes back out: the payee takes one note, and the rest
    // returns to the payer as notes of its own. The paths are the ones the state answered with,
    // one per note consumed, in the order the notes are given.
    #[allow(clippy::too_many_arguments)]
    // The first value a machine holds: the share of a window it lived through, turned into a note
    // of its own. Five of the six positions have nothing to put in them and take filler; the sixth
    // consumes the right, and the whole share comes out as one note the machine pays to itself.
    //
    // **This is where value enters a wallet at all.** Minting creates no note — it issues a right —
    // and a right is extinguished inside an ordinary payment, in a redemption position like any
    // other. Until this door is walked no note exists anywhere, so no ordinary payment can be
    // built; after it, the machine holds a note and pays like anybody.
    #[allow(clippy::too_many_arguments)]
    pub fn redeem(
        &self,
        machine_secret: &[u8; 32],
        of_the_window: u64,
        share: u128,
        admitted_siblings: &[Digest],
        admitted_position: u64,
        to: &Payee,
        window: u64,
        rate_secret: &[u8; 32],
        root: &Digest,
        admitted: &Digest,
    ) -> Result<Payment, WalletError> {
        let inputs =
            mt_genesis::scalar("spend_inputs").ok_or(WalletError::NotOfTheFamily)? as usize;
        let outputs =
            mt_genesis::scalar("spend_outputs").ok_or(WalletError::NotOfTheFamily)? as usize;
        let count =
            mt_genesis::scalar("spends_per_frame").ok_or(WalletError::NotOfTheFamily)? as usize;
        let depth = mt_proof::tree_depth();
        let mut spends = Vec::with_capacity(count);
        let mut created_all = Vec::new();
        for at in 0..count {
            let consumed: Vec<Consumed> = (0..inputs)
                .map(|which| Consumed::filler(rate_secret, at * inputs + which, depth))
                .collect();
            let created: Vec<Created> = (0..outputs)
                .map(|which| Created {
                    half: to.half,
                    // The whole share leaves by the first position; the rest create nothing, and
                    // the shape says nothing about which did which.
                    value: if at == 0 && which == 0 { share } else { 0 },
                    note_pk: to.note_pk,
                    rcm: drawn(rate_secret, at * outputs + which),
                })
                .collect();
            created_all.extend(created.iter().cloned());
            spends.push(Spend {
                consumed,
                created,
                rate: Rate {
                    secret: *rate_secret,
                    index: at as u8,
                },
            });
        }
        spends[0].consumed[0] = Consumed::Right(HeldRight {
            machine_secret: *machine_secret,
            window: of_the_window,
            value: share,
            siblings: admitted_siblings.to_vec(),
            position: admitted_position,
        });
        let frame = Frame { spends, window };
        let object = self.prove_and_lay(&frame, window, root, admitted)?;
        Ok(Payment {
            frame: object,
            created: created_all,
            spent: Vec::new(),
        })
    }

    #[allow(clippy::too_many_arguments)]
    pub fn pay(
        &self,
        payee: &Payee,
        amount: u128,
        window: u64,
        rate_secret: &[u8; 32],
        own: &Payee,
        paths: &[Vec<Digest>],
        root: &Digest,
        admitted: &Digest,
    ) -> Result<Payment, WalletError> {
        let inputs =
            mt_genesis::scalar("spend_inputs").ok_or(WalletError::NotOfTheFamily)? as usize;
        let outputs =
            mt_genesis::scalar("spend_outputs").ok_or(WalletError::NotOfTheFamily)? as usize;
        let count =
            mt_genesis::scalar("spends_per_frame").ok_or(WalletError::NotOfTheFamily)? as usize;
        let ledger = self.ledger()?;
        let taking = inputs * count;
        // A wallet holding fewer notes than a frame has positions spends what it holds and fills
        // the rest: the set says a spend redeeming less than its positions allow holds filler in
        // the others, and the shape of a frame therefore says nothing about how many notes were
        // behind it. A wallet holding one note pays exactly like a wallet holding six.
        if ledger.held.is_empty() {
            return Err(WalletError::NotHeld);
        }
        let real = ledger.held.len().min(taking).min(paths.len());
        let held: Vec<Note> = ledger.held[..real].to_vec();
        let total: u128 = held.iter().map(|n| n.value).sum();
        if amount > total {
            return Err(WalletError::NotHeld);
        }

        let mut spends = Vec::with_capacity(count);
        let mut created_all = Vec::new();
        let mut spent = Vec::new();
        let mut left = total;
        let mut paid = false;
        for at in 0..count {
            let consumed: Vec<Consumed> = (0..inputs)
                .map(|which| {
                    let of_the_frame = at * inputs + which;
                    match held.get(of_the_frame) {
                        Some(note) => Consumed::Note(Held {
                            nf_key: note.nf_key,
                            value: note.value,
                            note_pk: note.note_pk,
                            rcm: note.rcm,
                            siblings: paths[of_the_frame].clone(),
                            position: note.position,
                        }),
                        None => Consumed::filler(rate_secret, of_the_frame, mt_proof::tree_depth()),
                    }
                })
                .collect();
            let of_this: u128 = consumed.iter().map(Consumed::value).sum();
            // The first spend carries the payment; the value it does not pay comes back to the
            // payer, and every later spend carries the payer's own value across unchanged.
            let mut values = Vec::with_capacity(outputs);
            if !paid {
                if amount > of_this {
                    return Err(WalletError::NotHeld);
                }
                values.push(amount);
                values.push(of_this - amount);
                paid = true;
            } else {
                values.push(of_this);
                values.resize(outputs, 0);
            }
            let created: Vec<Created> = values
                .iter()
                .enumerate()
                .map(|(which, value)| {
                    let to = if at == 0 && which == 0 { payee } else { own };
                    Created {
                        half: to.half,
                        value: *value,
                        note_pk: to.note_pk,
                        rcm: drawn(rate_secret, at * outputs + which),
                    }
                })
                .collect();
            left = left.saturating_sub(of_this);
            let from = (at * inputs).min(held.len());
            let to = (at * inputs + inputs).min(held.len());
            for note in &held[from..to] {
                spent.push(note.commitment);
            }
            created_all.extend(created.iter().cloned());
            spends.push(Spend {
                consumed,
                created,
                rate: Rate {
                    secret: *rate_secret,
                    index: at as u8,
                },
            });
        }
        let _ = left;

        let frame = Frame { spends, window };
        Ok(Payment {
            frame: self.prove_and_lay(&frame, window, root, admitted)?,
            created: created_all,
            spent,
        })
    }

    // A frame proven and laid as the object that crosses the wire. Both doors above end here, so
    // there is one place a frame is proven and one place it is written down — a second of either
    // would be a second thing to keep in step with the circuit.
    fn prove_and_lay(
        &self,
        frame: &Frame,
        window: u64,
        root: &Digest,
        admitted: &Digest,
    ) -> Result<Vec<u8>, WalletError> {
        let places = Places::of(mt_proof::tree_depth()).ok_or(WalletError::NotOfTheFamily)?;
        let (trace, _) = mt_proof::circuit::frame::trace_of(
            &places,
            frame,
            admitted,
            mt_proof::params::ROWS_LOG2,
        )
        .ok_or(WalletError::NotOfTheFamily)?;
        let held_description =
            mt_proof::circuit::frame::description(&places, mt_proof::params::ROWS_LOG2)
                .ok_or(WalletError::NotOfTheFamily)?;
        let public = mt_proof::circuit::frame::public_of(frame, &places, root, admitted)
            .ok_or(WalletError::NotOfTheFamily)?;
        let proof = mt_proof::scheme::prove(&held_description, &public, &trace)
            .map_err(|_| WalletError::NotOfTheFamily)?;
        let published: Vec<mt_proof::circuit::frame::Published> = frame
            .spends
            .iter()
            .map(|spend| mt_proof::circuit::frame::published_of(spend, window))
            .collect::<Option<Vec<_>>>()
            .ok_or(WalletError::NotOfTheFamily)?;
        let object = mt_state::layout::Frame {
            spends: published
                .into_iter()
                .map(|held| mt_state::layout::Spend {
                    nullifiers: held.nullifiers,
                    commitments: held.commitments,
                    rate_nullifier: held.rate_nullifier,
                })
                .collect(),
            proof,
        };
        mt_state::Layout::bytes(&object).map_err(|_| WalletError::NotOfTheFamily)
    }
}
