// The node's own path of a ballot, through an electorate whose standing is sampled: the units a
// machine holds are the census windows it kept and whose roots the electorate names, its ballot is
// proven over them, and a verifier holding the electorate takes the count the ballot casts. A run of
// two or three machines stands far below the floor of the committee and publishes no ballot, so this
// is where the path the running node takes at a population is exercised whole.
//
// **The wrong implementations it refuses**, named before the assertions: a ballot whose part is
// derived otherwise than the part of the machine's heavy attestation — it would never count for the
// cement, and a sampled electorate would close no window; a verifier taking the count a ballot
// carries off the wire; a ballot proven against another aggregate; a census lived under a root the
// electorate does not name, counted as a unit; and a ballot of an electorate counted whole.

use montana_node::attest::{ballot_of, verify_ballot, LivedCensus};
use montana_node::certificate::Electorate;
use mt_state::layout::Census;

const WINDOW: u64 = 50_000;

fn refused(what: &'static str) -> montana_node::NodeError {
    montana_node::NodeError::Refused { what }
}

// An electorate of window `WINDOW` whose census stands at the floor of the committee, and the census
// windows a machine of it kept: its part in every census cement but one in three, beside five
// strangers' parts.
fn a_sampled_electorate(secret: &[u8; 32]) -> (Electorate, Vec<LivedCensus>) {
    let windows = mt_pulse::standing::census_windows(WINDOW - 2).expect("the Decree names them");
    let seats = mt_genesis::scalar("standing_committee").expect("the Decree names it");
    let depth = mt_proof::tree_depth();
    let mut census = Vec::new();
    let mut lived = Vec::new();
    for (at, window) in windows.iter().enumerate() {
        let mut parts: Vec<[u8; 32]> = (0..5u8)
            .map(|i| {
                mt_proof::poseidon::hash_bytes(mt_codec::domain::MT_PART_NF, &[i, at as u8, 9])
                    .bytes()
            })
            .collect();
        let own = mt_derive::nullifier::part(secret, *window).expect("a window of the field");
        let lives = at % 3 != 1;
        if lives {
            parts.push(own);
        }
        parts.sort_unstable();
        let root = mt_proof::cement::root_of(&parts, depth).expect("distinct ascending parts");
        census.push(Census {
            root: root.bytes(),
            count: seats,
        });
        if lives {
            let (siblings, position) =
                mt_proof::cement::branch_of(&parts, &own, depth).expect("its own part");
            lived.push(LivedCensus {
                window: *window,
                root: root.bytes(),
                siblings,
                position,
            });
        }
    }
    let committee = mt_pulse::standing::committee(seats * census.len() as u64)
        .expect("the committee of a standing at its floor");
    assert_eq!(committee.expected, seats);
    (
        Electorate {
            root: mt_proof::cement::empty_root(),
            count: 3,
            census,
            windows,
            committee,
        },
        lived,
    )
}

#[test]
fn a_ballot_casts_the_units_its_machine_lived_and_a_verifier_takes_that_count() {
    let secret = [0x5Au8; 32];
    let (electorate, lived) = a_sampled_electorate(&secret);

    // An aggregate under which this standing draws a vote at all: the first of a fixed run, so the
    // vector fails the same way twice.
    let spending =
        mt_proof::poseidon::Digest::of_bytes(&mt_derive::nullifier::machine_halves(&secret).0)
            .expect("a digest of the family");
    let threshold = electorate.committee.threshold.to_be_bytes();
    let units: Vec<mt_proof::circuit::ballot::Census> = electorate
        .census_roots()
        .expect("the roots of the census")
        .into_iter()
        .map(|(window, root)| mt_proof::circuit::ballot::Census {
            window,
            root,
            branch: lived
                .iter()
                .find(|one| one.window == window)
                .map(|one| (one.siblings.clone(), one.position)),
        })
        .collect();
    let (aggregate, drawn) = (0..=u8::MAX)
        .map(|at| [at; 32])
        .find_map(|aggregate| {
            let votes =
                mt_proof::circuit::ballot::votes_of(&spending, &units, &aggregate, &threshold)
                    .expect("a standing of the field");
            (votes > 0).then_some((aggregate, votes))
        })
        .expect("a standing of seven units draws a vote under some aggregate of the run");

    let ballot = ballot_of(&secret, WINDOW, &electorate, &aggregate, &lived)
        .expect("the ballot proves")
        .expect("a standing that drew a vote publishes a ballot");
    assert_eq!(ballot.votes, drawn);
    assert_eq!(
        Some(ballot.part_nullifier),
        mt_derive::nullifier::part(&secret, WINDOW),
        "the ballot counts for the part the machine's heavy attestation carries"
    );
    assert_eq!(
        verify_ballot(&ballot, WINDOW, &electorate, &aggregate),
        Ok(drawn)
    );

    // Refused: a count the proof does not carry, and a ballot proven against another aggregate.
    if drawn < electorate.census.len() as u64 {
        let more = mt_state::layout::Ballot {
            votes: drawn + 1,
            ..ballot.clone()
        };
        assert_eq!(
            verify_ballot(&more, WINDOW, &electorate, &aggregate),
            Err(refused("a ballot whose proof does not verify"))
        );
    }
    let mut elsewhere = aggregate;
    elsewhere[0] ^= 1;
    assert_eq!(
        verify_ballot(&ballot, WINDOW, &electorate, &elsewhere),
        Err(refused("a ballot whose proof does not verify"))
    );

    // A census the machine kept under a root the electorate does not name — it closed that window on
    // another cement — is no unit: the standing counted is the six others.
    let mut moved = lived.clone();
    moved[0].root[0] ^= 1;
    let without: Vec<mt_proof::circuit::ballot::Census> = units
        .iter()
        .map(|unit| mt_proof::circuit::ballot::Census {
            branch: if unit.window == lived[0].window {
                None
            } else {
                unit.branch.clone()
            },
            ..unit.clone()
        })
        .collect();
    let fewer = mt_proof::circuit::ballot::votes_of(&spending, &without, &aggregate, &threshold)
        .expect("a standing of the field");
    match ballot_of(&secret, WINDOW, &electorate, &aggregate, &moved).expect("the ballot proves") {
        Some(held) => assert_eq!(held.votes, fewer),
        None => assert_eq!(fewer, 0),
    }

    // An electorate counted whole asks no ballot and takes none.
    let whole = Electorate {
        committee: mt_pulse::standing::committee(0).expect("the committee of nothing"),
        ..electorate.clone()
    };
    assert_eq!(
        ballot_of(&secret, WINDOW, &whole, &aggregate, &lived).expect("nothing to prove"),
        None
    );
    assert_eq!(
        verify_ballot(&ballot, WINDOW, &whole, &aggregate),
        Err(refused("a ballot of an electorate counted whole"))
    );
}
