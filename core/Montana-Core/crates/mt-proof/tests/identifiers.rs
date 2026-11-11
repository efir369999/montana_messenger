// The identifiers of every description the network accepts proofs under, printed from the
// descriptions themselves so the set freezes what runs and nothing else.
use mt_proof::circuit::{admission, ballot, frame, opening, presence, ticket};

#[test]
fn the_identifiers_of_the_six_descriptions() {
    let depth = mt_proof::tree_depth();
    let places = frame::Places::of(depth).expect("the Decree names the shape of a frame");
    // The height comes from the constant the gate compares and never from a literal: this test
    // prints what a person copies into the set, so a literal here would print the identifier of a
    // circuit the network does not accept while the gate compared the one it does.
    let of_frame = frame::description(&places, mt_proof::params::ROWS_LOG2)
        .expect("the frame's description stands")
        .identifier();
    // PANIC-OK: a description is built from the constants of this tree and from no input anyone
    // sends; a refusal here is the assembly having moved, which is what this test exists to say.
    let of_ticket = ticket::description()
        .expect("the ticket's description stands")
        .identifier();
    let of_admission = admission::description()
        .expect("the admission's description stands")
        .identifier();
    let of_presence = presence::description()
        .expect("the presence's description stands")
        .identifier();
    let of_opening = opening::description()
        .expect("the opening's description stands")
        .identifier();
    let of_ballot = ballot::description()
        .expect("the ballot's description stands")
        .identifier();
    for (name, id) in [
        ("frame", of_frame),
        ("ticket", of_ticket),
        ("admission", of_admission),
        ("presence", of_presence),
        ("opening", of_opening),
        ("ballot", of_ballot),
    ] {
        let hex: String = id.iter().map(|b| format!("{b:02x}")).collect();
        println!("identifier of the {name} = {hex}");
    }
    let mut bound = Vec::new();
    for id in [
        of_frame,
        of_ticket,
        of_admission,
        of_presence,
        of_opening,
        of_ballot,
    ] {
        bound.extend_from_slice(&id);
    }
    let air = mt_codec::hash_of_one(mt_codec::domain::MT_PROOF_AIR, &bound);
    let hex: String = air.iter().map(|b| format!("{b:02x}")).collect();
    println!("air_hash over the six, in order = {hex}");
    // The Decree binds the same six in the same order: a description that reaches the network and
    // not this list would print an air_hash the Decree does not carry.
    let decree = mt_genesis::PARAMETERS
        .iter()
        .find_map(|entry| match entry {
            mt_genesis::Entry::Hash(name, value) if *name == "air_hash" => Some(*value),
            _ => None,
        })
        .expect("the Decree names air_hash");
    assert_eq!(air, decree);
}
