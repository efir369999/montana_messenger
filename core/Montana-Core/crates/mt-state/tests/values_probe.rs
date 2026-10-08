// Prints the values that the set freezes over an empty value: the new values after
// absence took on a shape. Temporary run, not committed to the tree.
use mt_codec::domain;
use mt_merkle::{empty_internals, AppendTree, KEY_BITS};

fn hex(b: &[u8; 32]) -> String {
    b.iter().map(|x| format!("{x:02x}")).collect()
}

#[test]
fn print_them() {
    let depth = mt_genesis::scalar("note_tree_depth").expect("row") as usize;
    let m = empty_internals(domain::MT_MERKLE_LEAF, domain::MT_MERKLE_NODE, KEY_BITS);
    println!("empty_leaf = {}", hex(&m[0]));
    println!("empty_internal(1) = {}", hex(&m[1]));
    println!("empty_internal({depth}) = {}", hex(&m[depth]));
    println!("empty_internal(256) = {}", hex(&m[256]));
    let f = empty_internals(domain::MT_FABRIC_LEAF, domain::MT_FABRIC_NODE, depth);
    println!("fabric empty_leaf = {}", hex(&f[0]));
    println!("fabric empty_internal(1) = {}", hex(&f[1]));
    println!("fabric empty_internal({depth}) = {}", hex(&f[depth]));
    let mut tree = AppendTree::new(domain::MT_MERKLE_LEAF, domain::MT_MERKLE_NODE, depth);
    println!("note_root (empty) = {}", hex(&tree.root()));
    tree.push([0x11u8; 32]).expect("push");
    println!(
        "note_root (one commitment 0x11 x 32) = {}",
        hex(&tree.root())
    );
    let mut fab = AppendTree::new(domain::MT_FABRIC_LEAF, domain::MT_FABRIC_NODE, depth);
    println!("fabric_root (empty) = {}", hex(&fab.root()));
    fab.push([0x22u8; 32]).expect("push");
    println!("fabric_root (one leaf 0x22 x 32) = {}", hex(&fab.root()));
    for (name, root) in [
        "notes",
        "nullifiers",
        "records",
        "machines",
        "admitted",
        "operations",
    ]
    .iter()
    .zip(mt_state::tables::genesis_roots().iter())
    {
        println!("genesis root {name} = {}", hex(root));
    }
    println!(
        "published_parameters = {}",
        hex(&mt_state::tables::published_parameters_digest())
    );
    match mt_state::tables::genesis_state_hash() {
        Some(value) => println!("genesis_state_hash = {}", hex(&value)),
        None => println!("genesis_state_hash = none: a parameter stands unpublished"),
    }
}
