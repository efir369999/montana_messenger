// VAL-08 / F-562-1: the credit of W-1 is durable only in the one record of the close of W.
// The mutation this refuses credits the machine's live plane before the proposal is taken: a
// withheld proposal then leaves its credit standing in the plane the machine keeps.
use montana_node::pulse::{self, withhold, Cohort};
use montana_node::{Configuration, Machine, NodeError};
use mt_state::layout::Proposal;
use std::cell::RefCell;
use std::rc::Rc;

mod common;
use common::Scratch;

// The refused close of window 2: what the machine holds is read at the moment its own proposal of
// window 2 is handed over, after the candidate plane took the credit of window 1 and before the
// close; the proposal is withheld, so no close of window 2 ever stands.
#[test]
fn a_refused_proposal_leaves_the_previous_credit_root_across_restart() {
    let at = Scratch::named("refused-close-credit");
    let secret = [0x6Du8; 32];
    mt_store::Store::open(&at.0)
        .unwrap()
        .bear_secret(&secret)
        .unwrap();
    let config = Configuration::at(&at.0, "127.0.0.1:0");
    let (machine, _) = Machine::start(&config).unwrap();
    let cohort = Cohort::of(&[Cohort::half_of(&secret)]).unwrap();
    let before = Rc::new(RefCell::new(None));
    let seen = Rc::clone(&before);
    let record = at.0.join("window");
    withhold::own_proposals(Some(Box::new(
        move |machine: &Machine, proposal: &Proposal| {
            if proposal.window != 2 {
                return false;
            }
            if seen.borrow().is_none() {
                *seen.borrow_mut() = Some((
                    proposal.credited_root,
                    machine.value().unwrap().encode().unwrap(),
                    std::fs::read(&record).unwrap(),
                    machine.head().unwrap(),
                    machine.closed_window().unwrap(),
                ));
            }
            true
        },
    )));
    let result = pulse::live(&machine, &cohort, 0, 3, 4).map(|_| ());
    withhold::own_proposals(None);
    assert!(
        matches!(
            result,
            Err(NodeError::Refused {
                what: "a window no proposal of its decision ever stood at"
            })
        ),
        "{result:?}"
    );
    let (candidate, plane, record, head, closed) = before
        .borrow_mut()
        .take()
        .expect("the machine proved its own proposal of window 2");
    let kept = machine.value().unwrap().credited().bytes();
    assert_ne!(
        candidate, kept,
        "the credit of window 1 stands in the plane before the close of window 2"
    );
    assert_eq!(machine.value().unwrap().encode().unwrap(), plane);
    assert_eq!(std::fs::read(at.0.join("window")).unwrap(), record);
    assert_eq!(machine.head().unwrap(), head);
    assert_eq!(machine.closed_window().unwrap(), closed);
    assert!(machine.proposal_of(2).unwrap().is_none());
    drop(machine);
    let (again, born) = Machine::start(&config).unwrap();
    assert!(!born);
    assert_eq!(again.value().unwrap().encode().unwrap(), plane);
    assert_eq!(again.value().unwrap().credited().bytes(), kept);
    assert_eq!(again.head().unwrap(), head);
    assert_eq!(again.closed_window().unwrap(), closed);
    assert!(again.proposal_of(2).unwrap().is_none());
    let part = mt_derive::nullifier::part(&secret, 1).unwrap();
    assert!(again.value().unwrap().credited_branch(&part).is_none());
}

// The accepted close of window 2 makes the same credit durable, and a restart keeps it.
#[test]
fn an_accepted_close_makes_the_credit_durable_across_restart() {
    let at = Scratch::named("accepted-close-credit");
    let secret = [0x6Du8; 32];
    mt_store::Store::open(&at.0)
        .unwrap()
        .bear_secret(&secret)
        .unwrap();
    let config = Configuration::at(&at.0, "127.0.0.1:0");
    let (machine, _) = Machine::start(&config).unwrap();
    let cohort = Cohort::of(&[Cohort::half_of(&secret)]).unwrap();
    pulse::live(&machine, &cohort, 0, 3, 4).unwrap();
    let accepted = machine.proposal_of(2).unwrap().unwrap().credited_root;
    assert_eq!(machine.value().unwrap().credited().bytes(), accepted);
    let part = mt_derive::nullifier::part(&secret, 1).unwrap();
    assert!(machine.value().unwrap().credited_branch(&part).is_some());
    drop(machine);
    let (again, born) = Machine::start(&config).unwrap();
    assert!(!born);
    assert_eq!(again.closed_window().unwrap(), Some(2));
    assert_eq!(again.value().unwrap().credited().bytes(), accepted);
    assert!(again.value().unwrap().credited_branch(&part).is_some());
}
