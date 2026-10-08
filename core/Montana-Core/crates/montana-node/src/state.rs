// The state a machine holds of the value plane, and what a frame does to it.
//
// **A frame is verified before it is applied, and applied whole or not at all.** The proof is
// checked against the description of a frame and the public input a verifier lays from the object
// itself; the nullifiers are checked against what has already been spent; and only then do the
// commitments enter the tree. A machine that appended first and verified after would hold a tree
// no other machine holds.
//
// **Nothing here reads a note.** What crosses is nullifiers, commitments and the nullifier of a
// rate — values that name nobody — and this state holds exactly those. Who paid whom, and how
// much, is not in what a machine keeps, because it is not in what a machine is given.

use crate::NodeError;
use mt_proof::poseidon::Digest;
use mt_state::layout::Frame;
use mt_state::Layout;

pub struct State {
    notes: mt_proof::notes::Tree,
    spent: Vec<[u8; 32]>,
    admitted: Digest,
    // The records of the identity plane, by the key each stands at — which is its own commitment,
    // so a record stands where nothing about its holder places it.
    records: std::collections::BTreeMap<[u8; 32], Digest>,
    // The rights already spent, of every kind: a nullifier present is a nullifier refused.
    nullifiers: Vec<[u8; 32]>,
    // How many records this window has opened, against the ceiling the Decree fixes.
    opened: (u64, u64),
}

impl Default for State {
    fn default() -> Self {
        Self::new()
    }
}

impl State {
    pub fn new() -> Self {
        Self {
            notes: mt_proof::notes::Tree::new(mt_proof::tree_depth()),
            spent: Vec::new(),
            admitted: mt_proof::admitted::empty_root(),
            records: std::collections::BTreeMap::new(),
            nullifiers: Vec::new(),
            opened: (0, 0),
        }
    }

    // **What this plane is, written down, so that a stop does not destroy it.** A tree of notes is a
    // function of its leaves in their order and of nothing else, and everything else here is a set
    // or a pair of counts — so the whole plane is those leaves, those sets and those counts, and
    // reading them back rebuilds the tree rather than trusting a second copy of it. Nothing written
    // here is a secret of anybody: leaves, nullifiers and roots are what the network publishes, and
    // a person's own notes live in their wallet and not in this.
    //
    // The order is the order of the fields, counts before what they count, every count four bytes
    // little-endian and every value thirty-two — so an implementation reading it back reads it in
    // one pass and a file of another shape is refused rather than read half.
    pub fn encode(&self) -> Vec<u8> {
        let mut out = Vec::new();
        let count = |out: &mut Vec<u8>, n: usize| out.extend_from_slice(&(n as u32).to_le_bytes());
        count(&mut out, self.notes.leaves().len());
        for leaf in self.notes.leaves() {
            out.extend_from_slice(&leaf.bytes());
        }
        count(&mut out, self.spent.len());
        for nullifier in &self.spent {
            out.extend_from_slice(nullifier);
        }
        out.extend_from_slice(&self.admitted.bytes());
        count(&mut out, self.records.len());
        for (key, held) in &self.records {
            out.extend_from_slice(key);
            out.extend_from_slice(&held.bytes());
        }
        count(&mut out, self.nullifiers.len());
        for nullifier in &self.nullifiers {
            out.extend_from_slice(nullifier);
        }
        out.extend_from_slice(&self.opened.0.to_le_bytes());
        out.extend_from_slice(&self.opened.1.to_le_bytes());
        out
    }

    pub fn decode(bytes: &[u8]) -> Result<Self, NodeError> {
        let short = || NodeError::Refused {
            what: "a value plane shorter than what it declares",
        };
        let mut at = 0usize;
        let take = |n: usize, at: &mut usize| -> Result<&[u8], NodeError> {
            let end = at.checked_add(n).ok_or_else(short)?;
            let held = bytes.get(*at..end).ok_or_else(short)?;
            *at = end;
            Ok(held)
        };
        let count = |at: &mut usize| -> Result<usize, NodeError> {
            let mut four = [0u8; 4];
            four.copy_from_slice(take(4, at)?);
            Ok(u32::from_le_bytes(four) as usize)
        };
        let of_digest = |held: &[u8]| -> Result<Digest, NodeError> {
            let mut out = [0u8; 32];
            out.copy_from_slice(held);
            Digest::of_bytes(&out).ok_or(NodeError::Refused {
                what: "a value of the plane that is not a digest of the family",
            })
        };
        let of_bytes = |held: &[u8]| -> [u8; 32] {
            let mut out = [0u8; 32];
            out.copy_from_slice(held);
            out
        };

        let leaves_held = count(&mut at)?;
        let mut leaves = Vec::with_capacity(leaves_held);
        for _ in 0..leaves_held {
            leaves.push(of_digest(take(32, &mut at)?)?);
        }
        let spent_held = count(&mut at)?;
        let mut spent = Vec::with_capacity(spent_held);
        for _ in 0..spent_held {
            spent.push(of_bytes(take(32, &mut at)?));
        }
        let admitted = of_digest(take(32, &mut at)?)?;
        let records_held = count(&mut at)?;
        let mut records = std::collections::BTreeMap::new();
        for _ in 0..records_held {
            let key = of_bytes(take(32, &mut at)?);
            let held = of_digest(take(32, &mut at)?)?;
            records.insert(key, held);
        }
        let nullifiers_held = count(&mut at)?;
        let mut nullifiers = Vec::with_capacity(nullifiers_held);
        for _ in 0..nullifiers_held {
            nullifiers.push(of_bytes(take(32, &mut at)?));
        }
        let mut eight = [0u8; 8];
        eight.copy_from_slice(take(8, &mut at)?);
        let window = u64::from_le_bytes(eight);
        eight.copy_from_slice(take(8, &mut at)?);
        let opened = u64::from_le_bytes(eight);
        if at != bytes.len() {
            return Err(NodeError::Refused {
                what: "a value plane longer than what it declares",
            });
        }
        Ok(Self {
            notes: mt_proof::notes::Tree::of_leaves(mt_proof::tree_depth(), leaves).map_err(
                |_| NodeError::Refused {
                    what: "a tree of notes deeper than the Decree admits",
                },
            )?,
            spent,
            admitted,
            records,
            nullifiers,
            opened: (window, opened),
        })
    }

    // The tree of admitted machines this state stands beside. A frame carries it as a public value
    // whichever branch its redemptions took, so the state names it rather than each caller.
    pub fn with_admitted(mut self, admitted: Digest) -> Self {
        self.admitted = admitted;
        self
    }

    // The same value, told rather than built with. **A machine's value plane stands against the
    // same tree of admitted machines its pulse does**: a frame redeeming a right proves that the
    // machine is among those the window admitted, and a state holding an empty tree verifies that
    // proof against a tree standing for nobody — so the machine refuses its own true frame. The
    // pulse learns the cohort when it opens a window, and tells the state in the same breath.
    // The tree of admitted machines this state stands against, as a caller building a frame needs
    // it: what the frame proves and what this state verifies are one value or the machine refuses
    // its own true frame.
    pub fn admitted(&self) -> Digest {
        self.admitted
    }

    pub fn admits(&mut self, admitted: Digest) {
        self.admitted = admitted;
    }

    pub fn notes_root(&self) -> Digest {
        self.notes.root()
    }

    pub fn notes_held(&self) -> u64 {
        self.notes.len()
    }

    pub fn path_of(&self, position: u64) -> Option<Vec<Digest>> {
        self.notes.path(position)
    }

    pub fn is_spent(&self, nullifier: &[u8; 32]) -> bool {
        self.spent.contains(nullifier)
    }

    // A commitment entering the tree outside a frame: what a window's minting writes, and what a
    // cohort starts from. It is not a door a frame goes through — a frame goes through the one
    // below, which verifies first.
    pub fn witness(&mut self, commitment: &[u8; 32]) -> Result<u64, NodeError> {
        self.notes.push(commitment).map_err(|_| NodeError::Refused {
            what: "a commitment the tree of notes cannot hold",
        })
    }

    pub fn records_root(&self) -> Digest {
        mt_proof::records::root_of_leaves(&self.records)
    }

    pub fn records_held(&self) -> usize {
        self.records.len()
    }

    pub fn path_of_a_record(&self, key: &[u8; 32]) -> Option<Vec<Digest>> {
        mt_proof::records::path_of_leaves(&self.records, key)
    }

    pub fn is_spent_right(&self, nullifier: &[u8; 32]) -> bool {
        self.nullifiers.contains(nullifier)
    }

    // An opening applied: the proof verified against what the object publishes and the window being
    // applied, the right refused if already spent, the ceiling of the window held, and only then
    // the record entering the tree at the key its own commitment gives.
    //
    // **The window and the segment come from the machine and never from the object.** A verifier
    // holds both, and a field restating either would be a second place for them to stand — and a
    // claimant free to state its own would open a record into a window it never lived to see.
    pub fn apply_opening(
        &mut self,
        opening: &mt_state::layout::Opening,
        window: u64,
        segment: u32,
    ) -> Result<(), NodeError> {
        if self.is_spent_right(&opening.open_nullifier) {
            return Err(NodeError::Refused {
                what: "an opening under a right already spent",
            });
        }
        let ceiling = mt_genesis::scalar("max_openings_per_window").ok_or(NodeError::Decree {
            row: "max_openings_per_window".to_string(),
        })?;
        let held = if self.opened.0 == window {
            self.opened.1
        } else {
            0
        };
        if held >= ceiling {
            return Err(NodeError::Refused {
                what: "an opening past the ceiling this window admits",
            });
        }
        let nullifier = Digest::of_bytes(&opening.open_nullifier).ok_or(NodeError::Refused {
            what: "a nullifier that is not a digest of the family",
        })?;
        let commitment = Digest::of_bytes(&opening.record_commit).ok_or(NodeError::Refused {
            what: "a commitment that is not a digest of the family",
        })?;
        let public =
            mt_proof::circuit::opening::public_of(&[nullifier, commitment], window, segment);
        let description = mt_proof::circuit::opening::description().ok_or(NodeError::Refused {
            what: "a description of an opening this Decree does not give",
        })?;
        mt_proof::scheme::verify(&description, &public, &opening.proof).map_err(|_| {
            NodeError::Unprovable {
                what: "an opening whose proof does not stand against what it published",
            }
        })?;

        // Past the verification nothing refuses it. The record itself never crosses a wire, so what
        // the tree holds at that key is the commitment: a leaf of this tree is the fold of a record,
        // and a machine that never saw the record holds the fold it was handed.
        self.nullifiers.push(opening.open_nullifier);
        // The commitment an opening publishes **is** the leaf of the tree of records over the
        // record it creates: the key it stands at and the value it folds to are one value, which is
        // what lets a machine hold the tree without ever seeing a record.
        self.records.insert(opening.record_commit, commitment);
        self.opened = (window, held + 1);
        Ok(())
    }

    // A frame applied. The root the proof stands against is the root before this frame, since a
    // spender proved its notes are in the tree as it stood when it built the frame; the
    // commitments this frame creates enter after, and the positions they took come back so a
    // recipient knows where its own note stands.
    pub fn apply(&mut self, frame: &Frame, window: u64) -> Result<Vec<u64>, NodeError> {
        if !frame.nullifiers_are_distinct() {
            return Err(NodeError::Refused {
                what: "a frame spending one note twice within itself",
            });
        }
        for spend in &frame.spends {
            for nullifier in &spend.nullifiers {
                if self.is_spent(nullifier) {
                    return Err(NodeError::Refused {
                        what: "a frame spending a note already spent",
                    });
                }
            }
        }
        let published: Vec<mt_proof::circuit::frame::Published> = frame
            .spends
            .iter()
            .map(|spend| mt_proof::circuit::frame::Published {
                nullifiers: spend.nullifiers.clone(),
                commitments: spend.commitments.clone(),
                rate_nullifier: spend.rate_nullifier,
            })
            .collect();
        let public = mt_proof::circuit::frame::public_of_published(
            &published,
            &self.notes_root(),
            &self.admitted,
            window,
        );
        let places = mt_proof::circuit::frame::Places::of(mt_proof::tree_depth()).ok_or(
            NodeError::Decree {
                row: "spends_per_frame".to_string(),
            },
        )?;
        let held = mt_proof::circuit::frame::description(&places, mt_proof::params::ROWS_LOG2)
            .ok_or(NodeError::Refused {
                what: "a description of a frame this Decree does not give",
            })?;
        mt_proof::scheme::verify(&held, &public, &frame.proof).map_err(|_| {
            NodeError::Unprovable {
                what: "a frame whose proof does not stand against what it published",
            }
        })?;

        // Past the verification nothing can refuse it, so the whole of it enters: the spendings
        // recorded and the commitments appended in the order the frame writes them.
        let mut positions = Vec::new();
        for spend in &frame.spends {
            for nullifier in &spend.nullifiers {
                self.spent.push(*nullifier);
            }
            for commitment in &spend.commitments {
                positions.push(self.witness(commitment)?);
            }
        }
        Ok(positions)
    }

    // A frame as it stands on the wire, read back and applied. The length a delivery is taken at is
    // the width of a frame, which every machine derives from the Decree and none is told.
    pub fn width_of_a_frame() -> usize {
        Frame::expected_len()
    }
}
