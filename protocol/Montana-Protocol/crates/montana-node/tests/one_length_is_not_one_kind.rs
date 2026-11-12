// A beacon and a light attestation reach a point as bodies of one length, and a reader must still
// tell them apart.
//
// **What is measured.** What stands at a point is padded to the group of the erasure code, so two
// objects of different sizes arrive as bodies of the identical length — which is a property of the
// set and a defence of its own, since a length on the wire then says nothing about what it carries.
// This vector holds that fact as a number, and then holds the consequence for a reader.
//
// **The wrong implementation it refuses**, named before the assertions: one that takes the body
// length for the kind of the object. Under it a machine answers its own attestation as if it were a
// new beacon, publishes another, reads that one back as a beacon too, and fills the point with its
// own echo — until the point reaches its ceiling and refuses the one heavy attestation that would
// have closed the window. That is not a story: it happened on three hosts, and the machine's own
// account carried it — beacons at one round growing from two to two hundred and one, no
// attestations standing at all, six hundred objects published in that round, and ninety-six
// deposits refused past the ceiling.

use mt_state::layout::{Beacon, Confirmation, LightAttestation};
use mt_state::Layout;

mod common;

#[test]
fn a_beacon_and_a_light_attestation_share_one_body_length() {
    let beacon = Beacon::expected_len();
    let light = LightAttestation::expected_len();
    let heavy = Confirmation::expected_len();
    assert_ne!(
        beacon, light,
        "two objects of one size would make this vector measure nothing"
    );
    let of_beacon = mt_wire::message::body_len(beacon).expect("the Decree gives a body length");
    let of_light = mt_wire::message::body_len(light).expect("the Decree gives a body length");
    let of_heavy = mt_wire::message::body_len(heavy).expect("the Decree gives a body length");
    assert_eq!(
        of_beacon, of_light,
        "the collision this vector stands on is gone; a reader may no longer rest on the check that replaced length"
    );
    assert_ne!(
        of_beacon, of_heavy,
        "a heavy attestation shares the beacon's body length, so the collision reaches further than this vector states"
    );
}

#[test]
fn a_light_attestation_read_as_a_beacon_names_another_round() {
    let light = LightAttestation {
        window: 1_000,
        attested: vec![[0x11u8; 32], [0x22u8; 32]],
        part_nullifier: [0x33u8; 32],
        round_nullifier: [0x44u8; 32],
        suite_id: 1,
        answering_key: vec![0xA1u8; mt_codec::size::SIGNING_PUBLIC_KEY],
        signature: vec![0x5Eu8; mt_codec::size::SIGNATURE],
    };
    let bytes = light.encode();
    assert_eq!(bytes.len(), LightAttestation::expected_len());

    // Read as a beacon it parses — nothing about the bytes forbids it — and it names the window it
    // truly carries, since both objects open with that field. What it cannot carry is the chain and
    // the round of the beacon it is mistaken for: those bytes are the head of what it attests, and
    // they name a round nobody stands at.
    let mut padded = bytes.clone();
    padded.resize(Beacon::expected_len(), 0);
    let read = Beacon::parse(&padded).expect("bytes of that length parse as a beacon");
    assert_eq!(read.window, 1_000, "both objects open with the window");
    assert!(
        read.chain != 0 || read.round != 0,
        "a light attestation read as a beacon named the very round it stands at, so the check that tells the two apart cannot tell them apart"
    );
}
