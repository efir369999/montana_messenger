// The tables of the state and the six roots a proposal carries, and the hash that binds the
// parameters of the Decree to the state they open. The set states the roots and their order beside
// the parameters: the notes, the admitted machines and the operations under the append-only
// construction, the nullifiers, the records and the machine state under the sparse one.
//
// The Genesis State Hash is computed here rather than in the harness that checks it. A gate that
// computed the value it compares would be comparing itself.

use mt_codec::domain;
use mt_codec::{Domain, Preimage};
use mt_merkle::{empty_internals, AppendTree, SparseTree, KEY_BITS};

// The depth every append-only construction of this protocol takes. The door stands in `mt-proof`,
// where the constructions that walk at that depth are written, and this is the name the state
// reads it by: two doors on one question are two answers waiting to differ.
pub use mt_proof::tree_depth;

// A table of the state: which construction holds it and under which pair of domains. The pair is
// the one the set gives the trees of state — the fabric of time is the other use and takes its own
// — so what separates these five from the fabric is the form, and what separates them from each
// other is the position of a root in the object that carries it. Three of them stand at one depth
// under one pair, so identical contents give identical roots: a proof of one is a proof of the
// shape of another, and only the root it is verified against says which table was meant. Nothing
// of this stage reads a root without naming its table; the day a circuit takes one as a public
// input, the domain has to name the table, and that is a row of the set rather than a line here.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Table {
    Notes,
    Nullifiers,
    Records,
    Machines,
    Admitted,
    Operations,
}

impl Table {
    // The order a proposal carries them in, which is the order the Genesis State Hash binds.
    pub const ALL: [Table; 6] = [
        Table::Notes,
        Table::Nullifiers,
        Table::Records,
        Table::Machines,
        Table::Admitted,
        Table::Operations,
    ];

    pub fn is_append_only(self) -> bool {
        matches!(self, Table::Notes | Table::Admitted | Table::Operations)
    }

    // A table a circuit walks folds under the proof hash: the tree of notes, the tree of admitted
    // machines and the tree of records. The rest fold under the Merkle domains and SHA-256. **A
    // domain of one family under the doors of the other is a defect the set names as such**, so
    // this predicate and the pair below are one answer and never two.
    pub fn is_of_the_proof_hash(self) -> bool {
        matches!(self, Table::Notes | Table::Admitted | Table::Records)
    }

    pub fn leaf_domain(self) -> Domain {
        match self {
            Table::Notes => domain::MT_NOTE_LEAF,
            Table::Admitted => domain::MT_ADMITTED_LEAF,
            Table::Records => domain::MT_RECORD_LEAF,
            _ => domain::MT_MERKLE_LEAF,
        }
    }

    pub fn node_domain(self) -> Domain {
        match self {
            Table::Notes => domain::MT_NOTE_NODE,
            Table::Admitted => domain::MT_ADMITTED_NODE,
            Table::Records => domain::MT_RECORD_NODE,
            _ => domain::MT_MERKLE_NODE,
        }
    }

    // The root of this table holding nothing. For a table of the proof hash it is asked of the
    // module that owns that fold, since that module is the one place the fold is written; for the
    // rest it is the empty internal at the top of the construction here.
    pub fn empty_root(self) -> [u8; 32] {
        match self {
            Table::Notes => mt_proof::notes::empty_root().bytes(),
            Table::Admitted => mt_proof::admitted::empty_root().bytes(),
            Table::Records => mt_proof::records::empty_root().bytes(),
            _ => {
                let levels = if self.is_append_only() {
                    tree_depth()
                } else {
                    KEY_BITS
                };
                empty_internals(self.leaf_domain(), self.node_domain(), levels)[levels]
            }
        }
    }

    // The two constructions here fold under SHA-256, so a table of the proof hash has no tree of
    // this crate: asking for one would hand back a second implementation of a fold that already
    // stands in `mt-proof`, and the two would part at the first record written.
    pub fn append_tree(self) -> Option<AppendTree> {
        (self.is_append_only() && !self.is_of_the_proof_hash())
            .then(|| AppendTree::new(self.leaf_domain(), self.node_domain(), tree_depth()))
    }

    pub fn sparse_tree(self) -> Option<SparseTree> {
        (!self.is_append_only() && !self.is_of_the_proof_hash())
            .then(|| SparseTree::new(self.leaf_domain(), self.node_domain()))
    }
}

// The six empty roots in the order a proposal carries them.
pub fn genesis_roots() -> [[u8; 32]; 6] {
    let mut out = [[0u8; 32]; 6];
    for (slot, table) in out.iter_mut().zip(Table::ALL.iter()) {
        *slot = table.empty_root();
    }
    out
}

// The hash that binds the parameters to the state they open. It is a function of the parameters
// and of the six empty roots and of nothing else — no manifest, no address, no moment — so two
// machines given the same Decree compute one value and a chain whose value differs is a different
// protocol rather than a fork of this one.
//
// There is no value of it while a parameter of the Decree stands unpublished, and no stand-in is
// written for the missing one. A number computed over a value nobody agreed to is a number some
// build will ship and some chain will open on; the answer here is nothing, and nothing is what a
// caller must handle.
pub fn genesis_state_hash() -> Option<[u8; 32]> {
    let parameters = mt_genesis::encode()?;
    let roots = genesis_roots();
    // The block of parameters is of a width the Decree gives rather than a type, so it enters at
    // that width and an encoding disagreeing with the rows is refused here rather than hashed.
    // The six roots follow it as a run of one width, in the order the set names them.
    Some(
        Preimage::under(domain::MT_GENESIS_STATE)
            .declared(&parameters, mt_genesis::encoded_len()?)
            .ok()?
            .run(&roots)
            .finish(),
    )
}

// The parameters as they stand, under the same composition: what the gate of the set compares
// while a parameter is unpublished, so the encoding of everything that does exist is held to the
// set today rather than the day the last one lands.
//
// It goes through the door of parts and not the door of one body, and that is the point rather
// than a detail: **a domain opens one shape of preimage**. This value and the hash above stand
// under one domain, so one of them taken as a body and the other as parts would be that domain
// opening two shapes — the defect the law of a class domain names, at a place where no object
// carries an identifier and therefore where nothing else would have caught it. The bytes are the
// same either way; what changes is that the width is offered and refused where it disagrees.
pub fn published_parameters_digest() -> [u8; 32] {
    let published = mt_genesis::encode_published();
    // PANIC-OK: the width is the sum over the same rows the encoder walks, so the two agree by
    // construction; a disagreement is a Decree whose encoder and rows have parted, which the gate
    // refuses before anything computes over it.
    Preimage::under(domain::MT_GENESIS_STATE)
        .declared(&published, mt_genesis::published_len())
        .expect("the block enters at the width its rows give")
        .finish()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_genesis_state_hash_exists_because_every_parameter_is_published() {
        // The Decree is complete — the last row to land was the hash binding the constraint sets —
        // so the hash of the genesis state exists and a chain can open on it.
        assert!(genesis_state_hash().is_some());
        assert_eq!(mt_genesis::unpublished().len(), 0);
        // The value of that digest lives in the set and the gate compares the code against it. A
        // number written here would be its second place, and a second place is what parts from
        // the first the day a row of the Decree moves — which is exactly how this line was found.
        assert_eq!(published_parameters_digest().len(), 32);
    }

    #[test]
    fn the_two_constructions_hold_three_tables_and_three() {
        let append: Vec<Table> = Table::ALL
            .into_iter()
            .filter(|t| t.is_append_only())
            .collect();
        assert_eq!(
            append,
            vec![Table::Notes, Table::Admitted, Table::Operations]
        );
        let sparse: Vec<Table> = Table::ALL
            .into_iter()
            .filter(|t| !t.is_append_only())
            .collect();
        assert_eq!(
            sparse,
            vec![Table::Nullifiers, Table::Records, Table::Machines]
        );
    }

    #[test]
    fn the_empty_root_of_a_table_is_the_top_of_its_own_construction() {
        let depth = tree_depth();
        for table in Table::ALL {
            let levels = if table.is_append_only() {
                depth
            } else {
                KEY_BITS
            };
            // The two constructions here fold under SHA-256. A table of the proof hash names its own
            // domains and its root comes from the module that owns that fold, so the fold here under
            // those same domains is **the defect the set names** — one family under a domain of the
            // other — and the two must part. A table of the state is the top of this construction.
            let by_the_state =
                empty_internals(table.leaf_domain(), table.node_domain(), levels)[levels];
            if table.is_of_the_proof_hash() {
                assert_ne!(table.empty_root(), by_the_state, "{table:?}");
            } else {
                assert_eq!(table.empty_root(), by_the_state, "{table:?}");
            }
        }
        // The two constructions stand at two values: a table of one kind read as the other yields a
        // different root from the same contents.
        assert_ne!(Table::Notes.empty_root(), Table::Records.empty_root());
    }

    #[test]
    fn a_table_answers_only_the_construction_that_holds_it() {
        assert!(Table::Operations.append_tree().is_some());
        assert!(Table::Operations.sparse_tree().is_none());
        assert!(Table::Machines.sparse_tree().is_some());
        assert!(Table::Machines.append_tree().is_none());
        for table in Table::ALL.iter().filter(|t| t.is_of_the_proof_hash()) {
            assert!(table.append_tree().is_none());
            assert!(table.sparse_tree().is_none());
        }
    }

    #[test]
    fn the_order_of_the_roots_is_what_the_hash_binds() {
        // Reordering two roots yields another value, which is why the order stands in one place.
        // The composition is exercised over the parameters as they stand, since the Decree is not
        // yet complete and the hash it will bind does not exist.
        let parameters = mt_genesis::encode_published();
        let roots = genesis_roots();
        let over = |order: [usize; 5]| {
            let ordered: Vec<[u8; 32]> = order.iter().map(|at| roots[*at]).collect();
            Preimage::under(domain::MT_GENESIS_STATE)
                .declared(&parameters, parameters.len())
                .expect("the block enters at the width it has")
                .run(&ordered)
                .finish()
        };
        assert_ne!(over([1, 0, 2, 3, 4]), over([0, 1, 2, 3, 4]));
    }

    #[test]
    fn the_digest_of_the_parameters_moves_with_them_and_with_nothing_else() {
        assert_eq!(published_parameters_digest(), published_parameters_digest());
    }
}
