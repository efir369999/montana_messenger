// The heavy attestation of a window carries the line of the open slot of attempt zero at the name it
// attests, and its proof of presence asserts that value (Canon, "What its proof asserts", since the
// author's record 309, and "Invariants of a confirmation"). The door checks the proof at the name
// the caller reads off its round -- the identifier among `attested` that is not the beacon -- and at
// the `line_value` the attestation carries.
//
// **The wrong implementations it refuses**, named before the assertions: the heavy of c850ca3's
// node, which carried zeros for `line_value` -- there an honest heavy fails the door; a door that
// read the proof without the name or the value -- there a heavy whose value was moved and signed
// again is counted; a door that parsed `line_value` after the proof, or never -- there bytes that
// are no element of the field reach the verifier; and a standing that answered any name with the
// proof of one -- there a heavy of a name its presence was not made for leaves the machine.

use montana_node::attest::{verify_heavy, Standing};
use montana_node::pulse::Cohort;
use montana_node::NodeError;
use mt_state::layout::Confirmation;
use mt_state::Layout;

const WINDOW: u64 = 9;
const BEACON: [u8; 32] = [0x44; 32];
const NAME: [u8; 32] = [0x55; 32];
const OTHER: [u8; 32] = [0x66; 32];
const SECRET: [u8; 32] = [0x71; 32];
const UNPROVEN: &str = "an attestation whose proof of presence does not verify";

fn refused(what: &'static str) -> Result<(), NodeError> {
    Err(NodeError::Refused { what })
}

// Signs a moved confirmation again under the machine's own one-time key, so that the signature
// stands and only the proof, or the parse before it, is left to refuse it.
fn signed_again(mut held: Confirmation) -> Confirmation {
    let seed = mt_derive::pulse::part_key_seed(&SECRET, WINDOW);
    let mut bytes = [0u8; mt_suite::sign::SEED_BYTES];
    bytes.copy_from_slice(&seed[..mt_suite::sign::SEED_BYTES]);
    let (_, key) = mt_suite::sign::keypair_from_seed(&bytes);
    held.signature = mt_suite::sign::sign(&key, &held.signed_scope().expect("scope"))
        .expect("the machine owns its key")
        .as_bytes()
        .to_vec();
    held
}

#[test]
fn the_presence_asserts_the_line_at_the_name_it_attests() {
    let cohort = Cohort::of(&[Cohort::half_of(&SECRET)]).expect("the cohort stands");
    let branch = cohort.branch_of(&SECRET).expect("its own leaf");
    let root = cohort.root();
    let everything = mt_pulse::U256::from_be_bytes(&[0xff; 32]);
    let door = |held: &Confirmation, name: &[u8; 32]| {
        verify_heavy(held, name, &root, &[0x33; 32], 0, 7, &everything)
    };
    let standing =
        Standing::of_the_window(&SECRET, WINDOW, &NAME, &branch.siblings, branch.position)
            .expect("the admitted machine proves its presence");
    let heavy = standing
        .heavy(&SECRET, BEACON, NAME)
        .expect("a heavy attestation stands");

    // The value is the line, not zeros, and the honest heavy passes at the name it attests.
    assert_eq!(heavy.line_value, standing.line_value);
    assert_ne!(heavy.line_value, [0u8; 32]);
    assert_eq!(door(&heavy, &NAME), Ok(()));

    // The other identifier it attests is the beacon: the line was not drawn there.
    assert_eq!(door(&heavy, &BEACON), refused(UNPROVEN));
    // A name it does not attest is refused before the proof is read.
    assert_eq!(
        door(&heavy, &OTHER),
        refused("a name the attestation does not attest")
    );

    // A moved value, signed again, is refused by the proof.
    let mut moved = heavy.clone();
    moved.line_value[0] ^= 1;
    assert_eq!(door(&signed_again(moved), &NAME), refused(UNPROVEN));

    // Bytes that are no element of the field are no confirmation of this protocol: the rule of the
    // layout refuses them where they are written, so nobody can sign them, and the door refuses
    // them at the scope, before the signature and before the proof (Canon, "Invariants of a
    // confirmation").
    let mut outside = heavy.clone();
    outside.line_value = [0xff; 32];
    assert_eq!(
        outside.signed_scope(),
        Err(mt_state::ObjectError::LineValue)
    );
    assert_eq!(
        door(&outside, &NAME),
        Err(NodeError::Object(mt_state::ObjectError::LineValue))
    );

    // The standing answers only the name its presence was made for.
    assert_eq!(
        standing.heavy(&SECRET, BEACON, OTHER).map(|_| ()),
        refused("a heavy attestation of a name this window's presence was not made for")
    );
}
