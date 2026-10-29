// Generates candidate Genesis vectors from the owning implementation. This does not approve
// them: mt-conformance still compares the published Canon values on the subsequent test/build.
fn main() {
    fn hex(bytes: &[u8]) -> String {
        bytes.iter().map(|b| format!("{b:02x}")).collect()
    }
    use mt_proof::circuit::{admission, ballot, frame, opening, pledge, presence, ticket};
    let places = frame::Places::of(mt_proof::tree_depth()).expect("frame shape");
    let descriptions = [
        (
            "frame",
            frame::description(&places, mt_proof::params::ROWS_LOG2).expect("frame"),
        ),
        ("ticket", ticket::description().expect("ticket")),
        ("admission", admission::description().expect("admission")),
        ("presence", presence::description().expect("presence")),
        ("opening", opening::description().expect("opening")),
        ("ballot", ballot::description().expect("ballot")),
        ("pledge", pledge::description().expect("pledge")),
    ];
    let mut bound = Vec::new();
    for (name, description) in descriptions {
        let id = description.identifier();
        println!("identifier of the {name} = {}", hex(&id));
        bound.extend_from_slice(&id);
    }
    println!(
        "air_hash = {}",
        hex(&mt_codec::hash_of_one(
            mt_codec::domain::MT_PROOF_AIR,
            &bound
        ))
    );
    println!(
        "parameters = {}",
        hex(&mt_genesis::encode().expect("complete Decree"))
    );
    for (table, root) in mt_state::tables::Table::ALL
        .iter()
        .zip(mt_state::tables::genesis_roots())
    {
        println!("{table:?} = {}", hex(&root));
    }
    println!(
        "published_parameters = {}",
        hex(&mt_state::tables::published_parameters_digest())
    );
    println!(
        "genesis_state_hash = {}",
        hex(&mt_state::tables::genesis_state_hash().expect("complete Decree"))
    );
}
