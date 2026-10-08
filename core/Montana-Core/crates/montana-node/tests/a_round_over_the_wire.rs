// The scenario the Registry asks of this stage for the points a round and a window stand at: two
// machines meet by an acquaintance, and one deposits at the points every machine computes alone
// while the other — holding those points because it holds that window — keeps what was left there
// and answers nothing about who left it.
//
// **Nothing here is arranged between the two.** The points are a function of the window and the
// index, so the depositor and the holder arrive at the same sixteen bytes without exchanging them.
// **And the rule of the set is what refuses the rest**: a deposit at the point of another window is
// refused in silence, which is why a machine holding no window holds nothing at all.
//
// What the scenario does not reach is the cement, and the reason is written in `AUDIT.md` rather
// than worked around: a machine's first attestation of a window is heavy and carries a proof the
// set requires and names no constraint set for, so no machine can make one and this tree writes no
// object whose contents the set does not define.

use montana_node::{round, Configuration, Machine};
use mt_state::Layout;
use mt_wire::message::{self, Kind};
use std::path::PathBuf;
use std::time::{Duration, Instant};

mod common;
use common::Scratch;

// A machine holds the window its head names, and a head moves only onto a window whose proposal
// stands beside it. What this hands in is the proposal of a window, which is what a machine that had
// joined a chain would hold; the chain itself is what the two walls of this stage stand in the way
// of, and neither of them is in the way of the points.
fn holding_the_window(at: &PathBuf, window: u64) {
    let store = mt_store::Store::open(at).expect("a store opens");
    // A proposal has one length and no other, so what stands here stands at that length: a machine
    // answering a head query with anything else would be answering with what is not a proposal.
    store
        .put_proposal(window, &vec![0x7Au8; message::head_answer_len() - 8])
        .expect("stored");
    store
        .set_head(window)
        .expect("the head follows what it names");
}

fn stands_within(deadline: Duration, what: impl Fn() -> bool) -> bool {
    let start = Instant::now();
    while start.elapsed() < deadline {
        if what() {
            return true;
        }
        std::thread::sleep(Duration::from_millis(10));
    }
    what()
}

#[test]
fn what_is_deposited_at_the_points_of_a_window_stands_at_them() {
    let far_at = Scratch::named("round-far");
    let near_at = Scratch::named("round-near");
    let window = 1_000u64;
    holding_the_window(&far_at.0, window);

    let (far, _) = Machine::start(&Configuration::at(&far_at.0, "127.0.0.1:0"))
        .expect("the far machine starts");
    let line = far.acquaintance().expect("an acquaintance is written");
    let points = far.points().expect("the Decree names the replicas");
    assert_eq!(
        points,
        round::points_of_window(window).expect("named"),
        "a machine stands at the points of the window it holds"
    );
    assert_eq!(far.points_standing(), 0);

    let waiting = std::thread::spawn(move || {
        far.answer_one().expect("a link is answered");
        far
    });

    let (near, _) = Machine::start(&Configuration::at(&near_at.0, "127.0.0.1:0"))
        .expect("the near machine starts");
    let mut link = near.reach(&line).expect("the far machine answers");

    // The near machine computes the same points without being told them, and deposits one whole
    // delivery at every one of them. **A point holds deliveries and never loose bytes:** a cell
    // carries the point and the window of the delivery it belongs to, and a holder that took bytes
    // it cannot read as a delivery would hold a body it can never answer with.
    let mine = round::points_of_window(window).expect("named");
    let carried: Vec<Vec<Vec<u8>>> = mine
        .iter()
        .enumerate()
        .map(|(index, point)| {
            mt_wire::publish::cells_of(point, window, &[0xC0 + index as u8; 64])
                .expect("a body cuts into cells")
        })
        .collect();
    for (point, cells) in mine.iter().zip(&carried) {
        for cell in cells {
            let deposit = message::encode_deposit(point, cell).expect("a deposit is written");
            link.send(Kind::Deposit, &deposit).expect("it crosses");
        }
    }
    // And one at the points of another window, which the rule of the set refuses in silence.
    let elsewhere = round::points_of_window(window + 1).expect("named");
    for point in &elsewhere {
        let cells = mt_wire::publish::cells_of(point, window + 1, &[0xEE; 64])
            .expect("a body cuts into cells");
        let deposit = message::encode_deposit(point, &cells[0]).expect("written");
        link.send(Kind::Deposit, &deposit).expect("it crosses");
    }

    let far = waiting.join().expect("the thread stands");
    // **The wait reads what the assertion reads.** Cells cross the link one by one, so a point
    // stands the moment its first cell is held while the rest of its delivery is still on the wire;
    // a wait on the count of points let the comparison below run against a delivery half arrived,
    // and on a loaded machine it did, twice (07.10.2026). Whether what stands is whole is the
    // question, so that is what is waited for, and a holder that kept part of a delivery fails here
    // by name rather than by a race.
    assert!(
        stands_within(Duration::from_secs(10), || far.points_standing()
            == mine.len()
            && mine
                .iter()
                .zip(&carried)
                .all(|(point, cells)| &far.standing_at(point) == cells)),
        "what was deposited did not stand whole at the points"
    );
    for (point, cells) in mine.iter().zip(&carried) {
        assert_eq!(
            &far.standing_at(point),
            cells,
            "what stands at a point is not what was deposited there"
        );
    }
    for point in &elsewhere {
        assert!(
            far.standing_at(point).is_empty(),
            "a deposit at the point of another window was kept"
        );
    }

    // And the other half of carriage: a collection takes what stands there. The right to what
    // stands at the point of a channel is public, so the collection presents nothing.
    let one = mt_wire::cell_bytes().expect("named");
    for (point, cells) in mine.iter().zip(&carried) {
        link.send(
            Kind::CollectPublic,
            &message::encode_collect_public(point, 0),
        )
        .expect("it crosses");
        let (kind, arrived) = link.receive().expect("an answer arrives");
        assert_eq!(kind, Kind::CollectAnswer);
        let declared = usize::from(u16::from_le_bytes([arrived[0], arrived[1]]));
        let width = 2 + declared * one;
        assert_eq!(
            message::parse_collect_answer(&arrived[..width]),
            Ok(cells.clone()),
            "what a collection took is not what stood at the point"
        );
    }

    // A collection from a point nothing stands at is answered with zero cells, which is the
    // ordinary answer and is indistinguishable from any other: asking says nothing about whether
    // anything waits.
    link.send(
        Kind::CollectPublic,
        &message::encode_collect_public(&elsewhere[0], 0),
    )
    .expect("it crosses");
    let (kind, arrived) = link.receive().expect("an answer arrives");
    assert_eq!(kind, Kind::CollectAnswer);
    assert_eq!(message::parse_collect_answer(&arrived[..2]), Ok(Vec::new()));

    // And the join asks for the newest proposal by naming the network with the hash it computed
    // itself: a machine of another network is told apart before a byte of a proposal is parsed.
    let ours = mt_state::tables::genesis_state_hash().expect("the Decree is complete");
    link.send(Kind::HeadQuery, &message::encode_head_query(&ours))
        .expect("it crosses");
    let (kind, arrived) = link.receive().expect("an answer arrives");
    assert_eq!(kind, Kind::HeadAnswer);
    assert_eq!(
        message::parse_head_answer(&arrived[..message::head_answer_len()]),
        Ok((0, vec![0x7Au8; message::head_answer_len() - 8]))
    );

    // A head query naming another network is answered with silence rather than with a proposal, and
    // the link stands: what follows it is answered as before.
    let mut theirs = ours;
    theirs[0] ^= 1;
    link.send(Kind::HeadQuery, &message::encode_head_query(&theirs))
        .expect("it crosses");
    link.send(
        Kind::CollectPublic,
        &message::encode_collect_public(&mine[0], 0),
    )
    .expect("it crosses");
    let (kind, arrived) = link.receive().expect("the collection is answered");
    assert_eq!(
        kind,
        Kind::CollectAnswer,
        "a query of another network was answered"
    );
    let declared = usize::from(u16::from_le_bytes([arrived[0], arrived[1]]));
    assert_eq!(
        declared,
        carried[0].len(),
        "a collection answered with something other than the whole delivery standing there"
    );
}

// A machine holding no window holds no points, so a deposit reaches nothing rather than being kept
// against a window that may never come.
#[test]
fn a_machine_holding_no_window_stands_at_no_point() {
    let at = Scratch::named("round-windowless");
    let (machine, _) =
        Machine::start(&Configuration::at(&at.0, "127.0.0.1:0")).expect("a machine starts");
    assert!(machine.points().expect("a machine answers").is_empty());
    let point = round::points_of_window(1_000).expect("named")[0];
    let one = mt_wire::cell_bytes().expect("named");
    assert!(!machine
        .take_deposit(&point, &vec![0xAB; one])
        .expect("a machine answers"));
    assert_eq!(machine.points_standing(), 0);
}

// A cell of another width is not a cell; a cell already standing adds nothing and is lawful; and a
// point carrying what it may hold takes no more.
//
// **The ceiling of a point is a round and its slots, not an answer.** One answer carries at most
// the cells of the largest single object, but a round stands at a point as a beacon and every
// attestation answering it — and the frames and openings whose canonical slot names the round
// stand there too, so a point held to the round's own objects alone would refuse every frame
// whole. What it holds is the round's part plus the window's caps on what the slots may bring. A
// machine that knows of no admitted machine holds the least of the round's part; the slots' part
// stands whatever the machine knows.
#[test]
fn a_cell_of_another_width_a_repeat_and_a_point_at_its_ceiling() {
    let at = Scratch::named("round-ceiling");
    let window = 2_000u64;
    holding_the_window(&at.0, window);
    let (machine, _) =
        Machine::start(&Configuration::at(&at.0, "127.0.0.1:0")).expect("a machine starts");
    let point = machine.points().expect("a machine answers")[0];
    let one = mt_wire::cell_bytes().expect("named");
    let delivery = |mark: u8| {
        mt_wire::publish::cells_of(&point, window, &[mark; 64]).expect("a body cuts into cells")
    };

    // A cell of another width is refused before anything of it is read.
    assert!(!machine
        .take_deposit(&point, &vec![0xAB; one - 1])
        .expect("a machine answers"));

    // A cell that already stands is not held twice, and the door says so by holding one — not by
    // refusing. A machine reads a point over and over while it stands at a round and writes what it
    // read at its own point, so a holder that kept every copy would fill with copies of the round it
    // holds and then refuse the round itself.
    let first = delivery(0xC1);
    assert!(machine.take_deposit(&point, &first[0]).expect("answers"));
    assert!(
        machine.take_deposit(&point, &first[0]).expect("answers"),
        "a repeated cell is refused loudly rather than adding nothing"
    );
    assert_eq!(
        machine.standing_at(&point).len(),
        1,
        "a point held one cell twice"
    );

    // And whole deliveries fill it to what it may hold, and no further. The bound is derived from
    // the widths of the Decree and the caps of the window — the round's part and the slots' part —
    // so nothing here names a number; what a delivery declares is what the bound is measured
    // against, since a point takes a delivery whole or refuses the whole of it. The filling rides
    // the largest lawful delivery: the honest ceiling holds the frames of a window, and a walk of
    // sixteen-cell steps to it would be a test of patience rather than of the bound.
    let ceiling = mt_wire::message::point_ceiling(0).expect("named");
    for cell in first.iter().skip(1) {
        assert!(machine.take_deposit(&point, cell).expect("answers"));
    }
    let frame_body = vec![0u8; mt_state::layout::Frame::expected_len()];
    let big = |counter: u32| {
        let mut body = frame_body.clone();
        body[..4].copy_from_slice(&counter.to_le_bytes());
        mt_wire::publish::cells_of(&point, window, &body).expect("a body cuts into cells")
    };
    let each = big(0).len();
    let mut standing = machine.standing_at(&point).len();
    let mut counter = 1u32;
    while standing + each <= ceiling {
        for cell in &big(counter) {
            assert!(machine.take_deposit(&point, cell).expect("answers"));
        }
        standing += each;
        counter += 1;
    }
    let filled = machine.standing_at(&point).len();
    assert_eq!(filled, standing, "the point holds what was deposited");
    assert!(
        filled + each > ceiling,
        "the point stopped short of what its bound admits"
    );
    let past = big(counter + 1);
    assert!(
        !machine.take_deposit(&point, &past[0]).expect("answers"),
        "a delivery the bound cannot take whole was taken in part"
    );
    assert_eq!(
        machine.standing_at(&point).len(),
        filled,
        "a refused delivery left a cell of itself standing"
    );
}

// The other half of the same rule: the points of two rounds do not meet, and nothing is refused
// loudly — the points simply differ, which is what makes withholding a round take holding every one
// of its points at once.
#[test]
fn the_points_of_two_rounds_do_not_meet() {
    let seven = round::points_of_round(1_000, 0, 7).expect("named");
    let eight = round::points_of_round(1_000, 0, 8).expect("named");
    assert!(seven.iter().all(|p| !eight.contains(p)));
    let other_chain = round::points_of_round(1_000, 1, 7).expect("named");
    assert!(seven.iter().all(|p| !other_chain.contains(p)));
    // And the points of a window are not the points of a round of it.
    let of_window = round::points_of_window(1_000).expect("named");
    assert!(of_window.iter().all(|p| !seven.contains(p)));
}
