// The history of a window, walked from an anchor through the one entry point. Consensus, "The join":
// a device that holds nothing but two consecutive final proposals its operator handed it verifies the
// certificate of the later one against the electorate and the aggregate the earlier one carries,
// judges the next proposal whole but for its roots, and takes as the head the newest proposal whose
// certificate verified. Every attestation here is the real node prover's, every proof is verified by
// the real verifier, and every proposal is signed by the key its ticket names.
//
// **The wrong implementations it refuses**, named before the assertions: a walker reading the
// electorate of a window off the proposal of the window before rather than two before — the trees of
// the two differ here, so the attestations of the first window stand against the tree only the
// right reading holds; a walker taking a proposal as final before its own certificate verified — the
// head of a walk handed one step stays at the anchor; a walker counting a certificate below the
// quorum; one judging a ticket against an aggregate the proposal two before does not carry; one
// trusting its anchor beyond the anchor; one taking as the next proposal a proposal the window
// after it does not attest; one stopped by a runner publishing, under the honest name, bytes the
// door refuses — it judges every copy under the name and takes the first that stands; one holding
// that a certificate with any name astray decides nothing — the decided proposal offered alone under
// a split certificate is taken; and one taking the first proposal under any name the window after
// attests — a minority attesting a name the agreement never decides stopped it one step on, short
// of the decided proposal offered beside; and one taking a final beacon no verified attestation of
// the certificate answered — the same beacon, its pair recomputed from the roll, stands refused until
// the light attestations of its round are handed in beside it.
//
// **The electorate of the split is four at a quorum of three.** The Decree names sixty-seven
// hundredths: at three machines the quorum is all three (2 × 100 < 3 × 67), so a split of two and
// one decides nothing and a test of the minority on three machines measures nothing; at four, three
// reach it (3 × 100 ≥ 4 × 67) and one stands astray — the electorate of the acceptance of item 1.

use montana_node::certificate::{
    decided_of, verify_certificate, walk, walk_to_the_open, Anchor, Electorate, Predecessor, Roots,
    Round, Step,
};
use montana_node::pulse::Cohort;
use montana_node::runner::Runner;
use mt_state::layout::Roll;

mod common;
use common::walk::{closing, handed, heavies, lights, opening};

const ANCHOR: u64 = 2_000;

fn refused(what: &'static str) -> montana_node::NodeError {
    montana_node::NodeError::Refused { what }
}

#[test]
fn a_device_walks_from_its_anchor_to_the_head_and_no_further() {
    let (one, two, three, four) = ([0x11u8; 32], [0x22u8; 32], [0x33u8; 32], [0x44u8; 32]);
    let pair = Cohort::of(&[Cohort::half_of(&one), Cohort::half_of(&two)]).expect("a tree of two");
    let all = Cohort::of(&[
        Cohort::half_of(&one),
        Cohort::half_of(&two),
        Cohort::half_of(&three),
        Cohort::half_of(&four),
    ])
    .expect("a tree of four");
    assert_ne!(pair.root(), all.root());
    let draw = mt_pulse::retarget::draw_threshold().expect("the threshold of the draw");
    let major = mt_state::implemented_major();

    // The anchor: the earlier proposal admits the pair and the later one all four, so the
    // electorate of the window two on is the pair and the electorate of the window three on is the
    // four. The two carry two different cements, which the draws two windows on read.
    let earlier = handed(ANCHOR, [0x10; 32], &pair, [0x0Au8; 32]);
    let later = handed(
        ANCHOR + 1,
        earlier.id().expect("an identifier"),
        &all,
        [0x0Bu8; 32],
    );
    let anchor = Anchor {
        earlier: earlier.clone(),
        later: later.clone(),
    };
    let later_id = later.id().expect("an identifier");
    let earlier_id = earlier.id().expect("an identifier");

    // The window after the anchor: the pair attests the later proposal against the tree the earlier
    // proposal carries, its round zero stands on the earlier proposal, and the runner of the window
    // proposes what it decided.
    let window = ANCHOR + 2;
    let first = opening(window, earlier_id);
    let (answered, closed, standing) = heavies(&[one, two], &pair, window, &first, later_id);
    let last = closing(window, &first, &answered);
    let answering = lights(&standing, &[one, two], &last, later_id);
    // The roll the proposal of this window names: no frames, the parts of the cement ascending.
    let mut parts: Vec<[u8; 32]> = answered.iter().map(|h| h.part_nullifier).collect();
    parts.sort_unstable();
    let roll = Roll {
        window,
        frames: Vec::new(),
        parts: parts.clone(),
    };
    let rolls = [roll.clone()];
    let rounds = [
        Round {
            beacon: &first,
            heavy: &answered,
            light: &[],
            ballots: &[],
        },
        Round {
            beacon: &last,
            heavy: &[],
            light: &answering,
            ballots: &[],
        },
    ];
    let electorate = Electorate::of(&earlier).expect("the electorate of the window");
    let closure = verify_certificate(
        window,
        &electorate,
        Predecessor::Proposal(&later),
        &earlier.cement_aggregate,
        1,
        &rounds,
        &closed,
    )
    .expect("the certificate of the later proposal verifies against the tree two before");
    // The electorate of the window before is another tree, and the attestations of the pair stand
    // nowhere in it: the reading of one window too late refuses an honest certificate.
    assert_eq!(
        verify_certificate(
            window,
            &Electorate::of(&later).expect("an electorate"),
            Predecessor::Proposal(&later),
            &earlier.cement_aggregate,
            1,
            &rounds,
            &closed,
        ),
        Err(refused(
            "an attestation whose proof of presence does not verify"
        ))
    );
    let decided = decided_of(
        &last.id().expect("an identifier"),
        &earlier_id,
        &rounds,
        &closure,
        &electorate,
    )
    .expect("the final beacon of the window");
    let branch = pair.branch_of(&one).expect("its own leaf");
    let runner = Runner::of_the_window(
        &one,
        window,
        &branch.siblings,
        branch.position,
        &earlier.cement_aggregate,
        &draw,
    )
    .expect("the ticket proves")
    .expect("the threshold of the draw clears every machine");
    let roots = Roots {
        note_root: [0x31; 32],
        nullifier_root: [0x41; 32],
        record_root: [0x51; 32],
        machine_root: [0x61; 32],
        admitted_root: all.root().bytes(),
        credited_root: [0x8A; 32],
        operations_root: [0x81; 32],
        roll: roll.id().expect("an identifier"),
        admitted_count: all.count(),
        census: later.census.clone(),
    };
    let next = runner
        .propose(
            mt_state::PROTOCOL_VERSION,
            Predecessor::Proposal(&later),
            &roots,
            &decided,
        )
        .expect("the proposal stands");
    let next_id = next.id().expect("an identifier");

    // The window after that: three of the four attest the next proposal against the tree the later
    // proposal of the anchor carries — the quorum of four.
    let after = ANCHOR + 3;
    let first_after = opening(after, later_id);
    let (answered_after, closed_after, _) =
        heavies(&[one, two, three], &all, after, &first_after, next_id);
    let rounds_after = [Round {
        beacon: &first_after,
        heavy: &answered_after,
        light: &[],
        ballots: &[],
    }];

    // Accepted: the walk verifies the certificate of the anchor's later proposal, judges the next
    // one, verifies its certificate, and stands on it.
    let steps = [
        Step {
            certificate: &rounds,
            pledges: &closed,
            rolls: &rolls,
            next: std::slice::from_ref(&next),
        },
        Step {
            certificate: &rounds_after,
            pledges: &closed_after,
            rolls: &[],
            next: &[],
        },
    ];
    let head = walk(&anchor, &steps, 1, &draw, major).expect("the walk reaches the head");
    assert_eq!(head.earlier, later);
    assert_eq!(head.later.id(), next.id());

    // A proposal awaiting its certificate is not final: handed the first step alone, the walk stands
    // where it began.
    let pending = walk(&anchor, &steps[..1], 1, &draw, major).expect("the anchor's certificate");
    assert_eq!(pending, anchor);

    // Refused: a certificate below the quorum — two of the four.
    let short = [Round {
        beacon: &first_after,
        heavy: &answered_after[..2],
        light: &[],
        ballots: &[],
    }];
    assert_eq!(
        walk(
            &anchor,
            &[
                Step {
                    certificate: &rounds,
                    pledges: &closed,
                    rolls: &rolls,
                    next: std::slice::from_ref(&next),
                },
                Step {
                    certificate: &short,
                    pledges: &closed_after,
                    rolls: &[],
                    next: &[],
                },
            ],
            1,
            &draw,
            major,
        ),
        Err(refused("a cement below the quorum share of the electorate"))
    );

    // The join over the open window of a running network: the newest certificate short of its
    // quorum is a window still closing, and the walk is taken again without it -- the head stays at
    // the anchor, the next proposal awaiting its certificate.
    let the_first = || Step {
        certificate: &rounds,
        pledges: &closed,
        rolls: &rolls,
        next: std::slice::from_ref(&next),
    };
    let (open_head, awaiting) = walk_to_the_open(
        &anchor,
        &[
            the_first(),
            Step {
                certificate: &short,
                pledges: &closed_after,
                rolls: &[],
                next: &[],
            },
        ],
        1,
        &draw,
        major,
    )
    .expect("a window still closing is walked around");
    assert_eq!(open_head, anchor);
    assert_eq!(
        awaiting.map(|held| held.id().expect("an identifier")),
        Some(next_id)
    );

    // Refused, and not walked around: the newest certificate carrying a forged attestation. A
    // retry on every refusal drops the forged window in silence and leaves the device living on from
    // the window before; only a certificate not whole yet is a window still closing (review 508 of
    // item 5, the case of a turned byte in the answers of one step).
    let mut forged_after = answered_after.clone();
    forged_after[0].signature[0] ^= 1;
    let forged_rounds = [Round {
        beacon: &first_after,
        heavy: &forged_after,
        light: &[],
        ballots: &[],
    }];
    assert_eq!(
        walk_to_the_open(
            &anchor,
            &[
                the_first(),
                Step {
                    certificate: &forged_rounds,
                    pledges: &closed_after,
                    rolls: &[],
                    next: &[],
                },
            ],
            1,
            &draw,
            major,
        )
        .map(|_| ()),
        Err(refused(
            "an attestation under a signature that does not verify"
        ))
    );

    // Refused: a next proposal whose ticket was drawn against the aggregate the later proposal
    // carries rather than the earlier one.
    let drawn_late = Runner::of_the_window(
        &one,
        window,
        &branch.siblings,
        branch.position,
        &later.cement_aggregate,
        &draw,
    )
    .expect("the ticket proves")
    .expect("drawn")
    .propose(
        mt_state::PROTOCOL_VERSION,
        Predecessor::Proposal(&later),
        &roots,
        &decided,
    )
    .expect("the proposal stands");
    assert_eq!(drawn_late.id(), next.id());
    assert_eq!(
        walk(
            &anchor,
            &[Step {
                certificate: &rounds,
                pledges: &closed,
                rolls: &rolls,
                next: std::slice::from_ref(&drawn_late),
            }],
            1,
            &draw,
            major,
        ),
        Err(refused("a proposal whose ticket proof does not verify"))
    );

    // Refused: an anchor whose later proposal does not name the earlier one.
    let loose = Anchor {
        earlier: earlier.clone(),
        later: handed(ANCHOR + 1, [0x77; 32], &all, [0x0Bu8; 32]),
    };
    assert_eq!(
        walk(&loose, &steps, 1, &draw, major),
        Err(refused(
            "an anchor of two proposals that are not consecutive"
        ))
    );

    // Refused: an anchor that is not the chain's own — a forged pair, linked to itself, is refused at
    // the first certificate: its heavy attestations enter the cement whatever name they pledge, and
    // its agreement decides the chain's own proposal and not the forged one.
    let forged_earlier = handed(ANCHOR, [0x10; 32], &pair, [0x0Cu8; 32]);
    let forged = Anchor {
        earlier: forged_earlier.clone(),
        later: handed(
            ANCHOR + 1,
            forged_earlier.id().expect("an identifier"),
            &all,
            [0x0Bu8; 32],
        ),
    };
    assert_eq!(
        walk(&forged, &steps, 1, &draw, major),
        Err(refused(
            "a certificate whose agreement does not decide the proposal it finalizes"
        ))
    );

    // A next proposal the window after it does not attest is not taken. Its roots differ, so it
    // decided something else and carries another name; the attestations of the window after name the
    // true one, and the walk stands where it was until a proposal under that name is offered.
    let mut other_roots = roots.clone();
    other_roots.note_root[0] ^= 1;
    let other = runner
        .propose(
            mt_state::PROTOCOL_VERSION,
            Predecessor::Proposal(&later),
            &other_roots,
            &decided,
        )
        .expect("the proposal stands");
    assert_ne!(other.id(), next.id());
    assert_eq!(
        walk(
            &anchor,
            &[
                Step {
                    certificate: &rounds,
                    pledges: &closed,
                    rolls: &rolls,
                    next: std::slice::from_ref(&other),
                },
                Step {
                    certificate: &rounds_after,
                    pledges: &closed_after,
                    rolls: &[],
                    next: &[],
                },
            ],
            1,
            &draw,
            major,
        ),
        Ok(anchor.clone())
    );
    let both = [other.clone(), next.clone()];
    let chosen = walk(
        &anchor,
        &[
            Step {
                certificate: &rounds,
                pledges: &closed,
                rolls: &rolls,
                next: &both,
            },
            Step {
                certificate: &rounds_after,
                pledges: &closed_after,
                rolls: &[],
                next: &[],
            },
        ],
        1,
        &draw,
        major,
    )
    .expect("the attested proposal is taken among two");
    assert_eq!(chosen.later.id(), next.id());

    // A copy of the honest decision under the honest name, re-signed by its runner with a final
    // beacon outside the certificate: the name is one, since the beacon stands outside it, and the
    // door refuses the copy at the beacon. Offered alone it is refused by name; offered beside the
    // honest bytes it stops nothing.
    let mut misplaced = next.clone();
    misplaced.final_beacon = [0x5Au8; 32];
    let seed = mt_derive::pulse::runner_key_seed(&one, window);
    let mut held = [0u8; mt_suite::sign::SEED_BYTES];
    held.copy_from_slice(&seed[..mt_suite::sign::SEED_BYTES]);
    let (key, secret) = mt_suite::sign::keypair_from_seed(&held);
    assert_eq!(key.as_bytes().to_vec(), next.runner_pubkey);
    misplaced.signature = mt_suite::sign::sign(
        &secret,
        &mt_state::Layout::signed_scope(&misplaced).expect("a scope"),
    )
    .expect("the runner owns its key")
    .as_bytes()
    .to_vec();
    assert_eq!(misplaced.id(), next.id());
    assert_eq!(
        walk(
            &anchor,
            &[
                Step {
                    certificate: &rounds,
                    pledges: &closed,
                    rolls: &rolls,
                    next: std::slice::from_ref(&misplaced),
                },
                Step {
                    certificate: &rounds_after,
                    pledges: &closed_after,
                    rolls: &[],
                    next: &[],
                },
            ],
            1,
            &draw,
            major,
        ),
        Err(refused("a final beacon outside the certificate"))
    );
    let copies = [misplaced, next.clone()];
    let past_the_copy = walk(
        &anchor,
        &[
            Step {
                certificate: &rounds,
                pledges: &closed,
                rolls: &rolls,
                next: &copies,
            },
            Step {
                certificate: &rounds_after,
                pledges: &closed_after,
                rolls: &[],
                next: &[],
            },
        ],
        1,
        &draw,
        major,
    )
    .expect("the honest bytes stand beside a refused copy");
    assert_eq!(past_the_copy.later.signature, next.signature);

    // A minority of the window after attesting another name: the fourth machine attests `other` and
    // closes on it, the three close on the honest name — the quorum of four — so `other` stands under
    // an attested name the agreement never decides. Offered alone it is judged whole, and the
    // certificate after refuses it; the honest proposal offered alone under the same split
    // certificate is taken, since a name astray decides nothing against the quorum; offered before
    // the honest proposal the minority name stops nothing.
    let other_id = other.id().expect("an identifier");
    let (mut split_after, mut split_closed, _) =
        heavies(&[one, two, three], &all, after, &first_after, next_id);
    let (astray, astray_closed, _) = heavies(&[four], &all, after, &first_after, other_id);
    split_after.extend(astray);
    split_closed.extend(astray_closed);
    let split_rounds = [Round {
        beacon: &first_after,
        heavy: &split_after,
        light: &[],
        ballots: &[],
    }];
    let past_the_split = walk(
        &anchor,
        &[
            Step {
                certificate: &rounds,
                pledges: &closed,
                rolls: &rolls,
                next: std::slice::from_ref(&next),
            },
            Step {
                certificate: &split_rounds,
                pledges: &split_closed,
                rolls: &[],
                next: &[],
            },
        ],
        1,
        &draw,
        major,
    )
    .expect("the decided proposal is taken under a certificate with one name astray");
    assert_eq!(past_the_split.later.id(), next.id());
    assert_eq!(
        walk(
            &anchor,
            &[
                Step {
                    certificate: &rounds,
                    pledges: &closed,
                    rolls: &rolls,
                    next: std::slice::from_ref(&other),
                },
                Step {
                    certificate: &split_rounds,
                    pledges: &split_closed,
                    rolls: &[],
                    next: &[],
                },
            ],
            1,
            &draw,
            major,
        ),
        Err(refused(
            "a certificate whose agreement does not decide the proposal it finalizes"
        ))
    );
    let minority_first = [other.clone(), next.clone()];
    let past_the_minority = walk(
        &anchor,
        &[
            Step {
                certificate: &rounds,
                pledges: &closed,
                rolls: &rolls,
                next: &minority_first,
            },
            Step {
                certificate: &split_rounds,
                pledges: &split_closed,
                rolls: &[],
                next: &[],
            },
        ],
        1,
        &draw,
        major,
    )
    .expect("the decided proposal is taken past a minority name");
    assert_eq!(past_the_minority.later.id(), next.id());

    // The pair of the proposal is recomputed from the roll standing beside it (Consensus, "The join",
    // 3). Refused: a proposal whose roll was not handed in -- a walker taking the pair off the final
    // beacon alone takes it.
    assert_eq!(
        walk(
            &anchor,
            &[Step {
                certificate: &rounds,
                pledges: &closed,
                rolls: &[],
                next: std::slice::from_ref(&next),
            }],
            1,
            &draw,
            major,
        ),
        Err(refused("a proposal whose roll was not handed in"))
    );

    // Refused: a final beacon whose pair is not the aggregate of the parts the roll names -- the
    // count is the verified two and the quorum is reached, so the beacon passes the door that reads
    // its count against the certificate, and only the recomputation shows its aggregate is no cement.
    let mut forged_last = last.clone();
    forged_last.cement_aggregate = [0x77; 32];
    let forged_answering = lights(&standing, &[one, two], &forged_last, later_id);
    let forged_rounds = [
        Round {
            beacon: &first,
            heavy: &answered,
            light: &[],
            ballots: &[],
        },
        Round {
            beacon: &forged_last,
            heavy: &[],
            light: &forged_answering,
            ballots: &[],
        },
    ];
    let forged_closure = verify_certificate(
        window,
        &electorate,
        Predecessor::Proposal(&later),
        &earlier.cement_aggregate,
        1,
        &forged_rounds,
        &closed,
    )
    .expect("the certificate verifies whatever pair its last beacon carries");
    let forged_decided = decided_of(
        &forged_last.id().expect("an identifier"),
        &earlier_id,
        &forged_rounds,
        &forged_closure,
        &electorate,
    )
    .expect("a final beacon whose count the certificate bounds is read as before");
    let forged_next = runner
        .propose(
            mt_state::PROTOCOL_VERSION,
            Predecessor::Proposal(&later),
            &roots,
            &forged_decided,
        )
        .expect("the proposal stands");
    assert_eq!(
        walk(
            &anchor,
            &[Step {
                certificate: &forged_rounds,
                pledges: &closed,
                rolls: &rolls,
                next: std::slice::from_ref(&forged_next),
            }],
            1,
            &draw,
            major,
        ),
        Err(refused(
            "a roll whose parts do not aggregate to the cement of the decision"
        ))
    );

    // Refused: a final beacon carrying the pair of a set holding a part no verified heavy attestation
    // of the certificate carries, with the roll that names it -- count and aggregate agree, and only
    // the match of the parts against the verified ones refuses it. A walker checking the roll's count
    // and aggregate and not its parts takes it.
    let mut ghosts = vec![parts[0], [0xEE; 32]];
    ghosts.sort_unstable();
    let ghost_roll = Roll {
        window,
        frames: Vec::new(),
        parts: ghosts.clone(),
    };
    let mut ghost_last = last.clone();
    ghost_last.cement_aggregate =
        mt_derive::aggregate::aggregate(&ghosts, window).expect("distinct parts");
    let ghost_answering = lights(&standing, &[one, two], &ghost_last, later_id);
    let ghost_rounds = [
        Round {
            beacon: &first,
            heavy: &answered,
            light: &[],
            ballots: &[],
        },
        Round {
            beacon: &ghost_last,
            heavy: &[],
            light: &ghost_answering,
            ballots: &[],
        },
    ];
    let ghost_closure = verify_certificate(
        window,
        &electorate,
        Predecessor::Proposal(&later),
        &earlier.cement_aggregate,
        1,
        &ghost_rounds,
        &closed,
    )
    .expect("the certificate verifies whatever pair its last beacon carries");
    let ghost_decided = decided_of(
        &ghost_last.id().expect("an identifier"),
        &earlier_id,
        &ghost_rounds,
        &ghost_closure,
        &electorate,
    )
    .expect("a final beacon whose count the certificate bounds is read as before");
    let mut ghost_roots = roots.clone();
    ghost_roots.roll = ghost_roll.id().expect("an identifier");
    let ghost_next = runner
        .propose(
            mt_state::PROTOCOL_VERSION,
            Predecessor::Proposal(&later),
            &ghost_roots,
            &ghost_decided,
        )
        .expect("the proposal stands");
    assert_eq!(
        walk(
            &anchor,
            &[Step {
                certificate: &ghost_rounds,
                pledges: &closed,
                rolls: std::slice::from_ref(&ghost_roll),
                next: std::slice::from_ref(&ghost_next),
            }],
            1,
            &draw,
            major,
        ),
        Err(refused(
            "a roll naming a part no verified heavy attestation of the certificate carries"
        ))
    );

    // Refused: the honest final beacon with no verified attestation answering it (Consensus, "The
    // beacon a window closes on": "and which a verified attestation answered"). Its pair is the
    // cement of the verified parts and the roll recomputes it, so a walker that checks the pair and
    // not the answer takes the proposal; with the light attestations of the final round handed in
    // beside it, the same proposal is taken. A light attestation on another name than its part's
    // heavy pledged, or one answering another beacon, answers nothing.
    const UNANSWERED: &str = "a final beacon no verified attestation of the certificate answered";
    let astray_lights = lights(&standing, &[one, two], &last, [0x99; 32]);
    let elsewhere = lights(&standing, &[one, two], &first, later_id);
    for unanswering in [&[][..], &astray_lights[..], &elsewhere[..]] {
        let unanswered = [
            Round {
                beacon: &first,
                heavy: &answered,
                light: &[],
                ballots: &[],
            },
            Round {
                beacon: &last,
                heavy: &[],
                light: unanswering,
                ballots: &[],
            },
        ];
        assert_eq!(
            walk(
                &anchor,
                &[
                    Step {
                        certificate: &unanswered,
                        pledges: &closed,
                        rolls: &rolls,
                        next: std::slice::from_ref(&next),
                    },
                    Step {
                        certificate: &rounds_after,
                        pledges: &closed_after,
                        rolls: &[],
                        next: &[],
                    },
                ],
                1,
                &draw,
                major,
            ),
            Err(refused(UNANSWERED))
        );
    }
}
