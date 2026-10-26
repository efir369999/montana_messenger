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
use mt_state::tables::{self, Table};
use mt_state::Layout;

#[derive(Clone)]
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
    // The rate nullifiers frames presented. They stand in the rate set of the horizon and in no
    // root: the set of nullifiers a proposal carries is of spent notes, rights and openings alone.
    rates: Vec<[u8; 32]>,
    // The frames applied in the window this state last applied one in, by identifier and in the
    // order they applied: the tree of operations a proposal carries holds one window.
    operations: (u64, Vec<[u8; 32]>),
    // The parts of the cements of the windows before, each window's credited by the proposal of the
    // window after it: the tree a right of a window walks to. It moves with no frame.
    credited: mt_proof::credited::Tree,
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
            rates: Vec::new(),
            operations: (0, Vec::new()),
            credited: mt_proof::credited::Tree::new(mt_proof::tree_depth()),
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
    pub fn encode(&self) -> Result<Vec<u8>, NodeError> {
        let sizes = [
            (self.notes.leaves().len(), 32usize),
            (self.spent.len(), 32),
            (self.records.len(), 64),
            (self.nullifiers.len(), 32),
            (self.rates.len(), 32),
            (self.operations.1.len(), 32),
            (self.credited.leaves().len(), 32),
        ];
        let refuses = || NodeError::Refused {
            what: "value plane exceeds its canonical encoding or allocation",
        };
        // The admitted root, the opening window and count, and the window of the operations.
        let mut size = 32usize + 16 + 8;
        for (count, width) in sizes {
            u32::try_from(count).map_err(|_| refuses())?;
            size = size
                .checked_add(4)
                .and_then(|s| count.checked_mul(width).and_then(|n| s.checked_add(n)))
                .ok_or_else(refuses)?;
        }
        let mut out = Vec::new();
        out.try_reserve_exact(size).map_err(|_| refuses())?;
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
        count(&mut out, self.rates.len());
        for nullifier in &self.rates {
            out.extend_from_slice(nullifier);
        }
        out.extend_from_slice(&self.operations.0.to_le_bytes());
        count(&mut out, self.operations.1.len());
        for frame in &self.operations.1 {
            out.extend_from_slice(frame);
        }
        count(&mut out, self.credited.leaves().len());
        for leaf in self.credited.leaves() {
            out.extend_from_slice(&leaf.bytes());
        }
        Ok(out)
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
        let count = |at: &mut usize, width: usize| -> Result<usize, NodeError> {
            let mut four = [0u8; 4];
            four.copy_from_slice(take(4, at)?);
            let held = u32::from_le_bytes(four) as usize;
            // A persisted count cannot reserve memory beyond the bytes that
            // can actually carry its entries, even when the file is corrupt.
            if held > bytes.len().saturating_sub(*at) / width {
                return Err(short());
            }
            Ok(held)
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
        let distinct_values = |at: &mut usize| -> Result<Vec<[u8; 32]>, NodeError> {
            let held = count(at, 32)?;
            let mut values = Vec::with_capacity(held);
            let mut seen = std::collections::BTreeSet::new();
            for _ in 0..held {
                let value = of_bytes(take(32, at)?);
                if !seen.insert(value) {
                    return Err(NodeError::Refused {
                        what: "a persisted spent set repeating a nullifier",
                    });
                }
                values.push(value);
            }
            Ok(values)
        };

        let leaves_held = count(&mut at, 32)?;
        let mut leaves = Vec::with_capacity(leaves_held);
        for _ in 0..leaves_held {
            leaves.push(of_digest(take(32, &mut at)?)?);
        }
        let spent = distinct_values(&mut at)?;
        let admitted = of_digest(take(32, &mut at)?)?;
        let records_held = count(&mut at, 64)?;
        let mut records = std::collections::BTreeMap::new();
        let mut previous_key = None;
        for _ in 0..records_held {
            let key = of_bytes(take(32, &mut at)?);
            if previous_key.is_some_and(|previous| key <= previous) {
                return Err(NodeError::Refused {
                    what: "persisted records repeating a key or outside their encoded order",
                });
            }
            previous_key = Some(key);
            let held = of_digest(take(32, &mut at)?)?;
            records.insert(key, held);
        }
        let nullifiers = distinct_values(&mut at)?;
        let mut eight = [0u8; 8];
        eight.copy_from_slice(take(8, &mut at)?);
        let window = u64::from_le_bytes(eight);
        eight.copy_from_slice(take(8, &mut at)?);
        let opened = u64::from_le_bytes(eight);
        let rates = distinct_values(&mut at)?;
        eight.copy_from_slice(take(8, &mut at)?);
        let of_the_window = u64::from_le_bytes(eight);
        let operations = distinct_values(&mut at)?;
        let credited_held = count(&mut at, 32)?;
        let mut credited = Vec::with_capacity(credited_held);
        for _ in 0..credited_held {
            credited.push(of_digest(take(32, &mut at)?)?);
        }
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
            rates,
            operations: (of_the_window, operations),
            credited: mt_proof::credited::Tree::of_leaves(mt_proof::tree_depth(), credited)
                .map_err(|_| NodeError::Refused {
                    what: "a tree of credited rights deeper than the Decree admits",
                })?,
        })
    }

    // The tree of admitted machines this state stands beside: the root a proposal carries and the
    // cohort its roots are answered for. A frame does not prove against it — a right walks the tree
    // of credited rights below — so it is what the pulse stands on, told to the plane.
    pub fn with_admitted(mut self, admitted: Digest) -> Self {
        self.admitted = admitted;
        self
    }

    // The same value, told rather than built with. **A machine's value plane stands against the
    // same tree of admitted machines its pulse does**, or the roots it answers for a proposal are
    // another cohort's. The pulse learns the cohort when it opens a window, and tells the state in
    // the same breath.
    pub fn admitted(&self) -> Digest {
        self.admitted
    }

    pub fn admits(&mut self, admitted: Digest) {
        self.admitted = admitted;
    }

    // A window credited: the parts of its cement, ascending, entering the tree of credited rights
    // at the proposal of the window after it, whole or not at all. Canon, "The right of a machine to
    // its coin of a window, and what redeems it".
    pub fn credit(&mut self, parts: &[[u8; 32]]) -> Result<(), NodeError> {
        self.credited.credit(parts).map_err(|_| NodeError::Refused {
            what: "a cement the tree of credited rights cannot hold",
        })
    }

    // The root of the tree of credited rights as this plane holds it: the root every frame it
    // applies proves its rights against, and so the one a caller building a frame proves against —
    // what the frame proves and what this state verifies are one value or the machine refuses its
    // own true frame.
    pub fn credited(&self) -> Digest {
        self.credited.root()
    }

    // Where a part stands in the tree of credited rights and the siblings it walks, or nothing for
    // a part no credited cement held: what a machine walks to redeem its right of a window.
    pub fn credited_branch(&self, part: &[u8; 32]) -> Option<(Vec<Digest>, u64)> {
        let position = self.credited.position_of(part)?;
        Some((self.credited.path(position)?, position))
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

    // A value a frame presents is refused where it stands already, whichever of the two sets holds
    // it: a spent note or right, or a rate the horizon holds.
    pub fn is_spent(&self, nullifier: &[u8; 32]) -> bool {
        self.spent.contains(nullifier) || self.rates.contains(nullifier)
    }

    // The seven roots and the count a proposal of `window` carries, recomputed from this plane and
    // the cohort it stands against. `docs/Montana Canon.md`, "The roots of state". The tree of admitted
    // machines is the cohort's, and a plane told another tree is refused rather than mixed with it;
    // the table of machines holds what selection events admit, and an opening cohort writes none.
    pub fn roots(
        &self,
        cohort: &crate::pulse::Cohort,
        window: u64,
        parts: &[[u8; 32]],
    ) -> Result<crate::certificate::Roots, NodeError> {
        if cohort.root() != self.admitted {
            return Err(NodeError::Refused {
                what: "a plane standing against another tree of admitted machines than its cohort",
            });
        }
        let refused = || NodeError::Refused {
            what: "a table of the state its construction cannot hold",
        };
        let nullifier_root =
            tables::root_of_set(Table::Nullifiers, self.spent.iter().chain(&self.nullifiers))
                .ok_or_else(refused)?;
        let machine_root = tables::root_of_set(Table::Machines, []).ok_or_else(refused)?;
        let applied: &[[u8; 32]] = if self.operations.0 == window {
            &self.operations.1
        } else {
            &[]
        };
        let operations_root =
            tables::root_of_sequence(Table::Operations, applied).ok_or_else(refused)?;
        let roll = self.roll(window, parts).id().map_err(NodeError::Object)?;
        Ok(crate::certificate::Roots {
            note_root: self.notes_root().bytes(),
            nullifier_root,
            record_root: self.records_root().bytes(),
            machine_root,
            admitted_root: self.admitted.bytes(),
            credited_root: self.credited().bytes(),
            operations_root,
            roll,
            admitted_count: cohort.count(),
            // The census is carried from the proposal before with the cement of the window, which
            // the plane does not hold; the pulse writes it beside these roots.
            census: Vec::new(),
        })
    }

    // The identifiers of the frames this plane applied in `window`, in the order they applied, and
    // nothing where the tree of operations holds another window.
    pub fn operations_of(&self, window: u64) -> Vec<[u8; 32]> {
        if self.operations.0 == window {
            self.operations.1.clone()
        } else {
            Vec::new()
        }
    }

    // The roll of `window` as this plane applied it: the frames in the order they applied, then the
    // parts of the cement the window decided, ascending. Canon, "The roll of a proposal".
    pub fn roll(&self, window: u64, parts: &[[u8; 32]]) -> mt_state::layout::Roll {
        let frames = if self.operations.0 == window {
            self.operations.1.clone()
        } else {
            Vec::new()
        };
        mt_state::layout::Roll {
            window,
            frames,
            parts: parts.to_vec(),
        }
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
        // Public Rust fields need the same shape check as a wire decoder. In particular an
        // overlong nested run must not manufacture additional public inputs or output leaves.
        frame.bytes().map_err(|_| NodeError::Refused {
            what: "a frame outside its canonical shape",
        })?;
        if !frame.nullifiers_are_distinct() {
            return Err(NodeError::Refused {
                what: "a frame spending one note twice within itself",
            });
        }
        let id = frame.id().map_err(NodeError::Object)?;
        let mut taken = std::collections::BTreeSet::new();
        for spend in &frame.spends {
            for nullifier in spend
                .nullifiers
                .iter()
                .chain(std::iter::once(&spend.rate_nullifier))
            {
                if !taken.insert(*nullifier) {
                    return Err(NodeError::Refused {
                        what: "a frame repeating a spending or rate nullifier",
                    });
                }
                if self.is_spent(nullifier) {
                    return Err(NodeError::Refused {
                        what: "a frame repeating a spent note or rate right",
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
        // A right of a window stands under the tree of credited rights and under no other: the
        // root laid here is the plane's own, so a frame proving a part no credited cement held is
        // refused before anything of it applies.
        let public = mt_proof::circuit::frame::public_of_published(
            &published,
            &self.notes_root(),
            &self.credited(),
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

        // Reserve and validate every fallible operation before either table changes. The tree
        // owns its atomic append; after it succeeds extending these reserved sets cannot fail.
        // This is in-memory atomicity; persistence must commit the enclosing snapshot.
        let reserving = |_| NodeError::Refused {
            what: "cannot reserve the frame's spent set",
        };
        self.spent.try_reserve(taken.len()).map_err(reserving)?;
        self.rates
            .try_reserve(frame.spends.len())
            .map_err(reserving)?;
        self.operations.1.try_reserve(1).map_err(reserving)?;
        let commitments: Vec<_> = frame
            .spends
            .iter()
            .flat_map(|spend| spend.commitments.iter().copied())
            .collect();
        let positions = self
            .notes
            .append_many(&commitments)
            .map_err(|_| NodeError::Refused {
                what: "a frame whose complete commitments cannot enter the tree",
            })?;
        let rates: std::collections::BTreeSet<[u8; 32]> = frame
            .spends
            .iter()
            .map(|spend| spend.rate_nullifier)
            .collect();
        self.spent
            .extend(taken.into_iter().filter(|value| !rates.contains(value)));
        self.rates.extend(rates);
        if self.operations.0 != window {
            self.operations = (window, Vec::new());
        }
        self.operations.1.push(id);
        Ok(positions)
    }

    // A frame as it stands on the wire, read back and applied. The length a delivery is taken at is
    // the width of a frame, which every machine derives from the Decree and none is told.
    pub fn width_of_a_frame() -> usize {
        Frame::expected_len()
    }
}
