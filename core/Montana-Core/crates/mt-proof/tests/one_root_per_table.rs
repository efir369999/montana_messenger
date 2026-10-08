// A table of the proof hash and the module that owns its fold are one value, or the six roots a
// genesis carries are not the roots the set freezes. They were two for as long as nothing put them
// beside each other: a table handed its own domains to the fold of the state, which is SHA-256, and
// the set names a domain of one family under the doors of the other a defect in as many words.

use mt_state::tables::Table;

#[test]
fn a_table_of_the_proof_hash_and_the_owner_of_its_fold_are_one_value() {
    for table in Table::ALL.iter().filter(|t| t.is_of_the_proof_hash()) {
        let owned = match table {
            Table::Notes => mt_proof::notes::empty_root().bytes(),
            Table::Admitted => mt_proof::admitted::empty_root().bytes(),
            Table::Records => mt_proof::records::empty_root().bytes(),
            other => panic!("a table of the proof hash with no owner named: {other:?}"),
        };
        assert_eq!(table.empty_root(), owned, "{table:?}");
    }
}

#[test]
fn the_two_constructions_of_the_state_refuse_a_table_of_the_proof_hash() {
    for table in Table::ALL.iter().filter(|t| t.is_of_the_proof_hash()) {
        assert!(table.append_tree().is_none(), "{table:?}");
        assert!(table.sparse_tree().is_none(), "{table:?}");
    }
}

#[test]
fn the_three_families_of_a_genesis_stand_apart() {
    let six = mt_state::tables::genesis_roots();
    for (at, root) in six.iter().enumerate() {
        for other in six.iter().skip(at + 1) {
            if root == other {
                assert_eq!(
                    six[1], six[3],
                    "two roots of a genesis agree that are not the two sparse tables of the state"
                );
            }
        }
    }
}
