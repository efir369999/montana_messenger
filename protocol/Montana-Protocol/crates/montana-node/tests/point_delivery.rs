//! Public point replication must survive a receiver that enters late and a
//! topology with inbound-only holders. Transport success is not acceptance.
use montana_node::{round, Configuration, Machine};
use std::sync::atomic::Ordering;
use std::time::{Duration, Instant};

mod common;
use common::Scratch;

fn connect(from: &Machine, to: &Machine) {
    std::thread::scope(|scope| {
        let answer = scope.spawn(|| to.answer_one().unwrap());
        from.reach_and_hold(&to.acquaintance().unwrap()).unwrap();
        answer.join().unwrap();
    });
}

fn until(mut ready: impl FnMut() -> bool) -> bool {
    let deadline = Instant::now() + Duration::from_secs(5);
    loop {
        if ready() {
            return true;
        }
        if Instant::now() >= deadline {
            return false;
        }
        std::thread::sleep(Duration::from_millis(10));
    }
}

#[test]
fn a_refused_early_delivery_is_retried_until_the_holder_acknowledges_it() {
    let near_at = Scratch::named("retry-near");
    let far_at = Scratch::named("retry-far");
    let (near, _) = Machine::start(&Configuration::at(&near_at.0, "127.0.0.1:0")).unwrap();
    let (far, _) = Machine::start(&Configuration::at(&far_at.0, "127.0.0.1:0")).unwrap();
    connect(&near, &far);
    near.enter_round(17, 0, 0).unwrap();
    let point = round::points_of_round(17, 0, 0).unwrap()[0];
    near.publish_at_the_point(&point, 17, &[0xA7; 64]).unwrap();
    // Collection is a wire barrier after the early deposit, not a sleep-based
    // assumption about which thread processed it first.
    near.objects_at_the_point(&point, 17).unwrap();
    assert!(far.standing_at(&point).is_empty());
    assert!(far.counts().deposits_before_a_round.load(Ordering::Relaxed) > 0);
    far.enter_round(17, 0, 0).unwrap();
    assert!(
        until(|| {
            near.objects_at_the_point(&point, 17).unwrap();
            !far.objects_at_the_point(&point, 17).unwrap().is_empty()
        }),
        "a successful early socket write suppressed delivery to the late holder"
    );
    // The returned cells acknowledge acceptance. Further unchanged reads must
    // not keep pushing the same delivery or increase the holder's storage.
    near.objects_at_the_point(&point, 17).unwrap();
    let pushes = near.counts().pushes_carried.load(Ordering::Relaxed);
    let cells = far.cells_standing_at(&point);
    for _ in 0..3 {
        near.objects_at_the_point(&point, 17).unwrap();
    }
    assert_eq!(near.counts().pushes_carried.load(Ordering::Relaxed), pushes);
    assert_eq!(far.cells_standing_at(&point), cells);
}

#[test]
fn collected_evidence_reaches_another_inbound_only_holder() {
    let locations = [
        Scratch::named("relay-a"),
        Scratch::named("relay-b"),
        Scratch::named("relay-c"),
    ];
    let machines: Vec<_> = locations
        .iter()
        .map(|at| {
            let (machine, _) = Machine::start(&Configuration::at(&at.0, "127.0.0.1:0")).unwrap();
            machine.enter_round(18, 0, 0).unwrap();
            machine
        })
        .collect();
    connect(&machines[0], &machines[1]);
    connect(&machines[0], &machines[2]);
    let point = round::points_of_round(18, 0, 0).unwrap()[0];
    machines[1]
        .publish_at_the_point(&point, 18, &[0xB8; 64])
        .unwrap();
    assert!(machines[2].standing_at(&point).is_empty());
    assert!(
        until(|| {
            machines[0].objects_at_the_point(&point, 18).unwrap();
            !machines[2]
                .objects_at_the_point(&point, 18)
                .unwrap()
                .is_empty()
        }),
        "collecting a peer's evidence did not relay it to the other holder"
    );
    assert_eq!(
        machines[1].objects_at_the_point(&point, 18).unwrap(),
        machines[2].objects_at_the_point(&point, 18).unwrap()
    );
}

// One link carries the points of three windows. The node tells its links the window of every
// point it publishes at and collects from, so the second and the third window each open behind a
// renewal of the link (Network, "When a link renews"): an offer before the first deposit, the
// answer and the finish taken in by the reads of the collection. A renewal that broke would end
// the link, and the next window would reach nothing.
#[test]
fn one_link_carries_three_windows_and_renews_between_them() {
    let near_at = Scratch::named("renew-near");
    let far_at = Scratch::named("renew-far");
    let (near, _) = Machine::start(&Configuration::at(&near_at.0, "127.0.0.1:0")).unwrap();
    let (far, _) = Machine::start(&Configuration::at(&far_at.0, "127.0.0.1:0")).unwrap();
    connect(&near, &far);
    for window in [17u64, 18, 19] {
        near.enter_round(window, 0, 0).unwrap();
        far.enter_round(window, 0, 0).unwrap();
        let point = round::points_of_round(window, 0, 0).unwrap()[0];
        let object = [window as u8; 64];
        assert_eq!(
            near.publish_at_the_point(&point, window, &object).unwrap(),
            1,
            "the link did not carry the deposits of window {window}"
        );
        assert!(
            until(|| {
                near.objects_at_the_point(&point, window).unwrap();
                !far.objects_at_the_point(&point, window).unwrap().is_empty()
            }),
            "the far side did not take in the object of window {window}"
        );
        assert_eq!(
            near.objects_at_the_point(&point, window).unwrap(),
            far.objects_at_the_point(&point, window).unwrap()
        );
    }
    assert_eq!(near.reached(), 1, "the link ended across a renewal");
}
