// A payment that crosses the wire: one machine holds the state, the other's owner builds a frame
// and publishes it at the points of the window, and the machine holding the state reads its own
// points and applies what stands there.
//
// **Neither side is told where the frame goes.** The points of a window are a function of the
// window and the index alone, so a payer computes them and the machine holding them computes the
// same sixteen bytes; the keys of the cells come of the point, so what the machine stores it could
// not read if it wanted to and what a collector reads it derives without asking.
//
// **The machine applies what it holds, not what it was told to apply.** It walks its own points,
// reads back whatever reads back as a frame, verifies the proof against the tree as it stands and
// appends. A deposit that is not a frame is passed over in silence.

use montana_node::{pulse, round, Configuration, Machine};
use montana_wallet::{Note, Wallet};

mod common;
use common::{of, payee_of, Scratch};

const WINDOW: u64 = 1_000;
const CHAIN: u8 = 0;
const ROUND: u32 = 0;

#[test]
fn a_frame_published_at_the_points_of_a_window_is_applied_by_the_machine_holding_them() {
    let holding_at = Scratch::named("crossing-holding");
    let paying_at = Scratch::named("crossing-paying");
    let ledger_at = Scratch::named("crossing-ledger");
    let payer = Wallet::open(&ledger_at.0).expect("a wallet opens");
    let (of_payer, payer_key) = payee_of(0xA1);
    let (of_payee, _) = payee_of(0xB2);

    // The machine that holds the state, and the payer's own machine reaching it.
    let (holding, _) = Machine::start(&Configuration::at(&holding_at.0, "127.0.0.1:0"))
        .expect("the machine starts");
    let (paying, _) =
        Machine::start(&Configuration::at(&paying_at.0, "127.0.0.1:0")).expect("the payer starts");

    // The notes the payer stands in the machine's tree with. They are witnessed by the machine
    // holding the state, which is the tree the payer will prove against.
    let inputs = mt_genesis::scalar("spend_inputs").expect("the Decree names it");
    let count = mt_genesis::scalar("spends_per_frame").expect("the Decree names it");
    let taking = (inputs * count) as usize;
    for at in 0..taking {
        let note = Note::of(
            1_000_000_000,
            of_payer.note_pk,
            payer_key,
            of(0xC3, at as u8),
            at as u64,
        )
        .expect("a note of the family");
        holding
            .value()
            .expect("the machine holds its state")
            .witness(&note.commitment)
            .expect("the tree takes it");
        payer.enter(note).expect("the ledger takes it");
    }
    let root = holding
        .value()
        .expect("the machine holds its state")
        .notes_root();

    let line = holding.acquaintance().expect("an acquaintance is written");
    let waiting = std::thread::spawn(move || {
        holding.answer_one().expect("a link is answered");
        holding
    });
    let mut link = paying.reach(&line).expect("the far side answers");
    let holding = waiting.join().expect("the thread stands");

    // The paths come over the wire, by the query the set gives for exactly this: the window, the
    // root, and the position of the leaf. What comes back names a position and never a person.
    let mut paths: Vec<Vec<mt_proof::poseidon::Digest>> = Vec::new();
    for at in 0..taking as u64 {
        let mut key = [0u8; 32];
        key[..8].copy_from_slice(&at.to_le_bytes());
        link.send(
            mt_wire::message::Kind::StateQuery,
            &mt_wire::message::encode_state_query(WINDOW, mt_wire::message::RootIndex::Notes, &key),
        )
        .expect("the query crosses");
        let (kind, answered) = link.receive().expect("the machine answers");
        assert_eq!(kind, mt_wire::message::Kind::StateAnswer);
        let proof = mt_wire::message::parse_state_answer(
            &answered[..4 + {
                let mut declared = [0u8; 4];
                declared.copy_from_slice(&answered[..4]);
                u32::from_le_bytes(declared) as usize
            }],
        )
        .expect("an answer of a state query");
        assert!(
            !proof.is_empty(),
            "a leaf that was written answered with nothing"
        );
        paths.push(
            proof
                .chunks(32)
                .map(|sibling| {
                    let mut bytes = [0u8; 32];
                    bytes.copy_from_slice(sibling);
                    mt_proof::poseidon::Digest::of_bytes(&bytes).expect("a digest of the family")
                })
                .collect(),
        );
    }

    let payment = payer
        .pay(
            &of_payee,
            250_000_000,
            WINDOW,
            &of(0xD4, 0),
            &of_payer,
            &paths,
            &root,
            &mt_proof::admitted::empty_root(),
        )
        .expect("a payment of what the payer holds");

    // The frame is published at the first point of the round its slot names. Nobody is told the
    // point: both sides compute it, and the payer seals under keys it derives from it.
    holding
        .enter_round(WINDOW, CHAIN, ROUND)
        .expect("the machine stands in the round");
    let points =
        round::points_of_round(WINDOW, CHAIN, ROUND).expect("the Decree names the replicas");
    let cells = pulse::publish_at(&mut link, &points[0], WINDOW, &payment.frame)
        .expect("the frame stands at the point");
    assert!(
        cells > 1,
        "a frame is larger than a cell and rode in one cell"
    );

    // The machine holding the state reads its own points and applies what stands there. The link is
    // dropped first, so what is applied is what was stored and not what is in flight.
    drop(link);
    let mut stood = 0;
    for _ in 0..200 {
        if holding.standing_at(&points[0]).len() >= cells {
            stood = holding.standing_at(&points[0]).len();
            break;
        }
        std::thread::sleep(std::time::Duration::from_millis(50));
    }
    assert_eq!(stood, cells, "the deposits did not all reach the machine");

    let before = holding
        .value()
        .expect("the machine holds its state")
        .notes_held();
    let applied = holding
        .apply_what_stands()
        .expect("the machine walks its own points");
    assert_eq!(applied, 1, "the frame standing at a point was not applied");
    assert_eq!(
        holding
            .value()
            .expect("the machine holds its state")
            .notes_held(),
        before + payment.created.len() as u64,
        "the commitments the frame creates did not enter the tree"
    );

    // Applied once and not twice: the same frame stands at every point of the window, and the state
    // refuses the second reading by the nullifiers it already holds.
    let again = holding
        .apply_what_stands()
        .expect("the machine walks its own points");
    assert_eq!(again, 0, "a frame already applied was applied again");
    assert_eq!(
        holding
            .value()
            .expect("the machine holds its state")
            .notes_held(),
        before + payment.created.len() as u64
    );
}
