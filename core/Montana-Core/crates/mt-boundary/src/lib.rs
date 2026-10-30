// The boundary a client written in another language stands on: the birth of a person, the wallet,
// the machine, its pulse and the coin a window credits, offered as doors rather than reimplemented.
//
// **Nothing here computes.** Every value that crosses this line was derived by the crate that owns
// the mechanism; a door reads its arguments, calls that crate and writes back what came. A number
// of its own would be a second place for a value the set already fixes, so this file declares none
// — not a width, not the worth of a right, not a length of a proof.
//
// **One device is one machine and one person.** A telephone holds one of each, so what stands here
// stands once and the doors take no handle: a second opening is refused rather than shadowing the
// first. The door a machine answers at stands until the process ends, which is what a process on a
// telephone is for.
//
// **What crosses is what a caller may hold.** The words of a person cross once, into a buffer the
// caller wipes, because a person who cannot read their own words cannot keep them. The secret of a
// machine, the branches of a seed and the blinding factor of a note never cross at all: what the
// doors of value hand over are the two public values of a payee and the counts of a ledger.
//
// **No panic crosses.** A door that broke answers with its own code and the reason stands where the
// caller reads reasons, because a panic unwinding into another language is undefined behaviour
// there rather than an error.

use montana_node::certificate::Anchor;
use montana_node::{pulse, Configuration, Machine, NodeError};
use montana_wallet::{pay::Payee, Wallet};
use mt_state::layout::Proposal;
use mt_state::Layout;
use std::ffi::{c_char, CStr};
use std::panic::AssertUnwindSafe;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

// What a door answers with. Well is the only answer that means the work was done; every other one
// is read together with the word this boundary kept, which names what refused.
#[repr(i32)]
enum Answer {
    Well = 0,
    Said = -1,
    Nothing = -2,
    TooSmall = -3,
    Broke = -4,
}

// The device: the machine this telephone is, the wallet of the person holding it, what the pulse
// has lived, and the errand the operator asked of the window it lives next.
struct Standing {
    machine: Arc<Machine>,
    wallet_at: PathBuf,
    lived: Arc<Mutex<Vec<Row>>>,
    running: Arc<AtomicBool>,
    errand: Arc<Mutex<Errand>>,
    paid: Arc<Mutex<Option<Handed>>>,
}

// What a payment left for the one it was paid to. A payee holds the key a note is bound to and
// nothing else of it, so what the payer hands over is the value, the blinding factor and the place
// the note took in the tree — and the note is theirs once they enter it.
//
// **The blinding factor is a secret of that note**: whoever holds it and the key holds the note, so
// it travels the way a person carries anything private and never through a place that keeps it.
#[derive(Clone, Copy)]
struct Handed {
    value: u128,
    rcm: [u8; 32],
    note_pk: [u8; 32],
    position: u64,
}

// What a machine does of its own inside the window it lives, asked before the pulse begins and run
// where the terminal runs it: after the round is entered and before anything of it is attested.
#[derive(Clone, Copy, Default)]
struct Errand {
    redeem: Option<u64>,
    pay: Option<([u8; 32], [u8; 32], u128)>,
}

// One window lived, as numbers a caller reads. Nothing of it names anybody.
#[derive(Clone, Copy)]
struct Row {
    window: u64,
    rounds: u32,
    living: usize,
    worth: u64,
    accepted_in: u64,
}

static DEVICE: Mutex<Option<Standing>> = Mutex::new(None);
static SAID: Mutex<Option<String>> = Mutex::new(None);

fn said(what: impl Into<String>) -> i32 {
    if let Ok(mut held) = SAID.lock() {
        *held = Some(what.into());
    }
    Answer::Said as i32
}

fn door(work: impl FnOnce() -> Result<(), String>) -> i32 {
    match std::panic::catch_unwind(AssertUnwindSafe(work)) {
        Ok(Ok(())) => Answer::Well as i32,
        Ok(Err(what)) => said(what),
        Err(_) => {
            let _ = said("a door of this boundary broke rather than answering");
            Answer::Broke as i32
        }
    }
}

fn text_door(
    work: impl FnOnce() -> Result<String, String>,
    out: *mut c_char,
    cap: usize,
    len: *mut usize,
) -> i32 {
    match std::panic::catch_unwind(AssertUnwindSafe(work)) {
        Ok(Ok(text)) => hand_text(&text, out, cap, len),
        Ok(Err(what)) => said(what),
        Err(_) => {
            let _ = said("a door of this boundary broke rather than answering");
            Answer::Broke as i32
        }
    }
}

fn hand_text(text: &str, out: *mut c_char, cap: usize, len: *mut usize) -> i32 {
    if out.is_null() || len.is_null() {
        return Answer::Nothing as i32;
    }
    let bytes = text.as_bytes();
    unsafe { *len = bytes.len() };
    if cap < bytes.len() + 1 {
        return Answer::TooSmall as i32;
    }
    unsafe {
        std::ptr::copy_nonoverlapping(bytes.as_ptr(), out as *mut u8, bytes.len());
        *out.add(bytes.len()) = 0;
    }
    Answer::Well as i32
}

fn text_of<'a>(from: *const c_char) -> Result<&'a str, String> {
    if from.is_null() {
        return Err("a text that is nothing".to_string());
    }
    unsafe { CStr::from_ptr(from) }
        .to_str()
        .map_err(|_| "bytes that are not text".to_string())
}

fn hand_bytes(bytes: &[u8], out: *mut u8) -> Result<(), String> {
    if out.is_null() {
        return Err("a place to write to that is nothing".to_string());
    }
    unsafe { std::ptr::copy_nonoverlapping(bytes.as_ptr(), out, bytes.len()) };
    Ok(())
}

fn taken(from: *const u8, width: usize) -> Result<Vec<u8>, String> {
    if from.is_null() {
        return Err("a value that is nothing".to_string());
    }
    let mut out = vec![0u8; width];
    unsafe { std::ptr::copy_nonoverlapping(from, out.as_mut_ptr(), width) };
    Ok(out)
}

fn half_at(from: *const u8, at: usize) -> Result<[u8; 32], String> {
    if from.is_null() {
        return Err("a cohort that is nothing".to_string());
    }
    let mut half = [0u8; 32];
    unsafe {
        std::ptr::copy_nonoverlapping(from.add(at * half.len()), half.as_mut_ptr(), half.len())
    };
    Ok(half)
}

fn wrote<T>(out: *mut T, value: T) -> Result<(), String> {
    if out.is_null() {
        return Err("a place to write to that is nothing".to_string());
    }
    unsafe { *out = value };
    Ok(())
}

// What the device holds, taken under the lock and handed back outside it: a caller of the pulse
// runs on a thread of its own, and a thread holding this lock while it lives a window would be a
// device nothing else could read.
fn of_the_device<T>(work: impl FnOnce(&Standing) -> Result<T, String>) -> Result<T, String> {
    let held = DEVICE
        .lock()
        .map_err(|_| "a boundary another thread left locked".to_string())?;
    let standing = held
        .as_ref()
        .ok_or_else(|| "no device stands; open one first".to_string())?;
    work(standing)
}

fn the_wallet() -> Result<Wallet, String> {
    let at = of_the_device(|standing| Ok(standing.wallet_at.clone()))?;
    Wallet::open(&at).map_err(|e| format!("what this wallet keeps: {e:?}"))
}

fn the_machine() -> Result<Arc<Machine>, String> {
    of_the_device(|standing| Ok(Arc::clone(&standing.machine)))
}

// The reason the last door refused, in the words the crate that refused used. A caller reads it
// after any answer other than well; it names no peer and no person.
#[no_mangle]
pub extern "C" fn mtc_last_said(out: *mut c_char, cap: usize, len: *mut usize) -> i32 {
    let held = match SAID.lock() {
        Ok(held) => held,
        Err(_) => return Answer::Broke as i32,
    };
    match held.as_deref() {
        Some(text) => hand_text(text, out, cap, len),
        None => {
            // Clear stale caller text without manufacturing a refusal in SAID: a second read
            // must still report absence, while bad buffers retain the existing boundary errors.
            match hand_text("", out, cap, len) {
                code if code == Answer::Well as i32 => Answer::Nothing as i32,
                code => code,
            }
        }
    }
}

// Which network this core is of. Two clients disagreeing here are not on one network, whatever
// else they agree on, so a client asks this before it asks anything.
#[no_mangle]
pub extern "C" fn mtc_genesis_state_hash(out: *mut u8) -> i32 {
    door(|| {
        let hash = mt_state::tables::genesis_state_hash()
            .ok_or_else(|| "a Decree with a parameter still unpublished".to_string())?;
        hand_bytes(&hash, out)
    })
}

// The draw of this device, tested rather than trusted: a constant source does not pass for one and
// the sources of the machine differ between two draws.
#[no_mangle]
pub extern "C" fn mtc_self_test() -> i32 {
    door(|| mt_seed::self_test().map_err(|e| format!("the draw of this device: {e:?}")))
}

// How many sources of entropy are alive on this device, which is what a person is shown before a
// birth. Not one byte of any source stands here.
#[no_mangle]
pub extern "C" fn mtc_sources_alive(out: *mut usize) -> i32 {
    door(|| match mt_seed::birth(None) {
        Ok(birth) => wrote(out, birth.alive()),
        Err(mt_seed::BirthError::TooFewLivingSources { alive }) => wrote(out, alive),
        Err(e) => Err(format!("the draw of this device: {e:?}")),
    })
}

// The device opened: the machine at its own directory answering at the address it was handed, and
// the wallet of the person beside it. Whether the machine was born in this call is answered rather
// than guessed, because an operator watching a second start and being told it was born would be
// watching a machine that lost its standing without being told.
#[no_mangle]
pub extern "C" fn mtc_device_open(
    dir: *const c_char,
    listen: *const c_char,
    born: *mut i32,
) -> i32 {
    door(|| {
        let dir = text_of(dir)?;
        let listen = text_of(listen)?;
        let at = PathBuf::from(dir);
        let machine_at = at.join("machine");
        let wallet_at = at.join("wallet");
        for one in [&machine_at, &wallet_at] {
            std::fs::create_dir_all(one)
                .map_err(|e| format!("a directory this device cannot make: {e}"))?;
        }
        let mut held = DEVICE
            .lock()
            .map_err(|_| "a boundary another thread left locked".to_string())?;
        if held.is_some() {
            return Err("a device already stands; one telephone is one machine".to_string());
        }
        let configuration = Configuration::at(&machine_at, listen);
        let (machine, drew) = Machine::start(&configuration).map_err(|e| format!("{e:?}"))?;
        *held = Some(Standing {
            machine: Arc::new(machine),
            wallet_at,
            lived: Arc::new(Mutex::new(Vec::new())),
            running: Arc::new(AtomicBool::new(false)),
            errand: Arc::new(Mutex::new(Errand::default())),
            paid: Arc::new(Mutex::new(None)),
        });
        wrote(born, i32::from(drew))
    })
}

#[no_mangle]
pub extern "C" fn mtc_device_standing(out: *mut i32) -> i32 {
    door(|| {
        let held = DEVICE
            .lock()
            .map_err(|_| "a boundary another thread left locked".to_string())?;
        wrote(out, i32::from(held.is_some()))
    })
}

// A person born on this device, from six sources with the health tests of the set over them. The
// words come back once: they are the person, and a device that showed them twice would be a device
// keeping them somewhere between the two showings.
#[no_mangle]
pub extern "C" fn mtc_person_bear(out: *mut c_char, cap: usize, len: *mut usize) -> i32 {
    text_door(
        || {
            let wallet = the_wallet()?;
            if wallet.person().map_err(|e| format!("{e:?}"))?.is_some() {
                return Err("a person already stands in this wallet".to_string());
            }
            let (_, entropy) = montana_wallet::Person::born().map_err(|e| format!("{e:?}"))?;
            wallet.bear_person(&entropy).map_err(|e| format!("{e:?}"))?;
            Ok(montana_wallet::Person::words(&entropy).to_string())
        },
        out,
        cap,
        len,
    )
}

// The person of words already written down. What is stretched is the entropy behind them, so a
// phrase typed with another spacing reaches the same person or none at all.
#[no_mangle]
pub extern "C" fn mtc_person_recall(words: *const c_char) -> i32 {
    door(|| {
        let spoken = text_of(words)?;
        let wallet = the_wallet()?;
        if wallet.person().map_err(|e| format!("{e:?}"))?.is_some() {
            return Err("a person already stands in this wallet".to_string());
        }
        let entropy = mt_seed::words::entropy_of(spoken).map_err(|e| format!("{e:?}"))?;
        wallet.bear_person(&entropy).map_err(|e| format!("{e:?}"))
    })
}

#[no_mangle]
pub extern "C" fn mtc_person_stands(out: *mut i32) -> i32 {
    door(|| {
        let wallet = the_wallet()?;
        let stands = wallet.person().map_err(|e| format!("{e:?}"))?.is_some();
        wrote(out, i32::from(stands))
    })
}

// What a payer needs of this person: the naming half of their nullifier key and the key a note of
// theirs is paid to. Both are public and neither is a name.
#[no_mangle]
pub extern "C" fn mtc_person_payee(half: *mut u8, note_pk: *mut u8) -> i32 {
    door(|| {
        let wallet = the_wallet()?;
        let person = wallet
            .person()
            .map_err(|e| format!("{e:?}"))?
            .ok_or_else(|| "a wallet holding no person".to_string())?;
        hand_bytes(&mt_derive::note::nf_pk(&person.note_nullifier_key()), half)?;
        hand_bytes(&person.payment_key(), note_pk)
    })
}

// The sum of what this wallet holds, written as the width the value of a note is written in. It is
// no share of anything and no view of anybody else's.
#[no_mangle]
pub extern "C" fn mtc_wallet_balance(out: *mut u8) -> i32 {
    door(|| {
        let balance = the_wallet()?.balance().map_err(|e| format!("{e:?}"))?;
        hand_bytes(&balance.to_le_bytes(), out)
    })
}

#[no_mangle]
pub extern "C" fn mtc_wallet_notes(out: *mut usize) -> i32 {
    door(|| {
        let ledger = the_wallet()?.ledger().map_err(|e| format!("{e:?}"))?;
        wrote(out, ledger.held.len())
    })
}

// The line an operator hands to another operator: one address and one key, and nothing else.
#[no_mangle]
pub extern "C" fn mtc_machine_acquaintance(out: *mut c_char, cap: usize, len: *mut usize) -> i32 {
    text_door(
        || the_machine()?.acquaintance().map_err(|e| format!("{e:?}")),
        out,
        cap,
        len,
    )
}

// The naming half of this machine, which is what a cohort is built of.
#[no_mangle]
pub extern "C" fn mtc_machine_naming_half(out: *mut u8) -> i32 {
    door(|| {
        let half = the_machine()?.naming_half().map_err(|e| format!("{e:?}"))?;
        hand_bytes(&half, out)
    })
}

// A machine reached and held. A link this machine opened stands outside the ceiling, so an
// acquaintance takes no slot a stranger could.
#[no_mangle]
pub extern "C" fn mtc_machine_reach(line: *const c_char) -> i32 {
    door(|| {
        let line = text_of(line)?;
        the_machine()?
            .reach_and_hold(line)
            .map(|_| ())
            .map_err(|e| format!("{e:?}"))
    })
}

// The door answered, on a thread of its own. It stands for as long as the process does: a machine
// that stopped answering while its window was open would be an address where a neighbour publishes
// into nothing.
#[no_mangle]
pub extern "C" fn mtc_machine_answer() -> i32 {
    door(|| {
        let machine = the_machine()?;
        machine.answer_in_background();
        Ok(())
    })
}

// CNS-20: independent of SAID. A successful read of a stall is not a healthy-node verdict.
#[no_mangle]
pub extern "C" fn mtc_pulse_status(out: *mut c_char, cap: usize, len: *mut usize) -> i32 {
    let status = the_machine()
        .ok()
        .and_then(|machine| machine.counts().status());
    let missing =
        status.is_none_or(|held| held.on() == Some(montana_node::say::Verdict::NoDiagnostics));
    let text = status.map_or_else(|| "no diagnostics".to_string(), |held| held.to_string());
    let answer = hand_text(&text, out, cap, len);
    if missing && answer == Answer::Well as i32 {
        Answer::Nothing as i32
    } else {
        answer
    }
}

#[no_mangle]
pub extern "C" fn mtc_machine_head(window: *mut u64, present: *mut i32) -> i32 {
    door(|| {
        let head = the_machine()?.head().map_err(|e| format!("{e:?}"))?;
        wrote(window, head.unwrap_or_default())?;
        wrote(present, i32::from(head.is_some()))
    })
}

// The join of a device that holds nothing, from the anchor its operator handed it: the bytes of
// the proposals of two consecutive final windows, the earlier and the later. Consensus, "The join":
// the anchor is a line of the world outside, as an acquaintance is, and the trust in it is the trust
// this device places in the operator who started it — so the door takes it as it was handed and
// judges none of it here. The proposals pass the one door of their layout, and the walk judges the
// pair and every certificate after it and trusts no answer; what comes back is the window the head
// stands at. A device walks or lives and never both at once: a walk while the pulse runs is refused,
// and the pulse is refused while a walk runs. The walk runs on the caller's thread, so a caller
// asks it from a thread of its own.
#[no_mangle]
pub extern "C" fn mtc_machine_join(
    earlier: *const u8,
    earlier_len: usize,
    later: *const u8,
    later_len: usize,
    window: *mut u64,
) -> i32 {
    door(|| {
        if window.is_null() {
            return Err("a place to write to that is nothing".to_string());
        }
        let proposal = |from: *const u8, len: usize| -> Result<Proposal, String> {
            <Proposal as Layout>::parse(&taken(from, len)?).map_err(|e| format!("{e:?}"))
        };
        let anchor = Anchor {
            earlier: proposal(earlier, earlier_len)?,
            later: proposal(later, later_len)?,
        };
        let (machine, running) = of_the_device(|standing| {
            Ok((Arc::clone(&standing.machine), Arc::clone(&standing.running)))
        })?;
        let walking = Walking::begun(&running)?;
        let head = pulse::join(&machine, &anchor, pulse::WAITS_UP_TO).map_err(|e| format!("{e:?}"));
        drop(walking);
        wrote(window, head?.later.window)
    })
}

// The device marked as busy for as long as a walk lasts, and marked free again however the walk
// ends — a walk that refused and a walk that broke leave a device the pulse may begin on.
struct Walking<'a>(&'a AtomicBool);

impl<'a> Walking<'a> {
    fn begun(running: &'a AtomicBool) -> Result<Self, String> {
        running
            .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
            .map_err(|_| "a pulse or a walk already running".to_string())?;
        Ok(Self(running))
    }
}

impl Drop for Walking<'_> {
    fn drop(&mut self) {
        self.0.store(false, Ordering::SeqCst);
    }
}

#[no_mangle]
pub extern "C" fn mtc_machine_links(
    held: *mut usize,
    ceiling: *mut usize,
    reached: *mut usize,
) -> i32 {
    door(|| {
        let machine = the_machine()?;
        let (standing, at_most) = machine.holding();
        wrote(held, standing)?;
        wrote(ceiling, at_most)?;
        wrote(reached, machine.reached())
    })
}

// The account this machine keeps of its own doings, as the one line an operator reads. Every count
// of it names nobody.
#[no_mangle]
pub extern "C" fn mtc_machine_account(out: *mut c_char, cap: usize, len: *mut usize) -> i32 {
    text_door(|| Ok(the_machine()?.counts().line()), out, cap, len)
}

// The right of a window turned into a note, asked before the pulse begins and done inside the
// window that right is accepted in. The window it is the right of is what the operator read off
// that window when it closed: the machine cannot ask anybody for it and nothing it holds implies it.
//
// **The count of the cement prices nothing now.** A right is worth the window's credit whatever its cement
// counted (Consensus, "The right to a window's coin"). The door still takes the count, so the
// clients standing on it do not move with the rule, and it reads it for one thing only: a window
// whose cement named nobody issued no right, and asking to redeem one is refused here.
#[no_mangle]
pub extern "C" fn mtc_errand_redeem(of_the_window: u64, living: usize) -> i32 {
    door(|| {
        if living == 0 {
            return Err("a window whose cement named nobody issued no right".to_string());
        }
        of_the_device(|standing| {
            let mut errand = standing
                .errand
                .lock()
                .map_err(|_| "an errand another thread left locked".to_string())?;
            errand.redeem = Some(of_the_window);
            Ok(())
        })
    })
}

// What a living machine pays out of its own wallet, against the tree it holds itself. Both values
// of the payee are public and name nobody.
#[no_mangle]
pub extern "C" fn mtc_errand_pay(half: *const u8, note_pk: *const u8, amount: *const u8) -> i32 {
    door(|| {
        let half = half_at(half, 0)?;
        let note_pk = half_at(note_pk, 0)?;
        let amount = taken(amount, std::mem::size_of::<u128>())?;
        let mut written = [0u8; std::mem::size_of::<u128>()];
        written.copy_from_slice(&amount);
        let amount = u128::from_le_bytes(written);
        of_the_device(|standing| {
            let mut errand = standing
                .errand
                .lock()
                .map_err(|_| "an errand another thread left locked".to_string())?;
            errand.pay = Some((half, note_pk, amount));
            Ok(())
        })
    })
}

// The pulse of this machine: it enters the window, stands at the points of its rounds, answers
// every beacon it sees, gathers what verifies into its cement and closes the window when the cement
// reaches the share — taking the right to the coin that window credits. It runs on a thread of its own, and what
// it lived is read by the doors below.
#[no_mangle]
pub extern "C" fn mtc_pulse_begin(halves: *const u8, count: usize, from: u64, windows: u64) -> i32 {
    door(|| {
        if count == 0 {
            return Err("a cohort of nobody".to_string());
        }
        let mut named = Vec::with_capacity(count);
        for at in 0..count {
            named.push(half_at(halves, at)?);
        }
        let (machine, wallet_at, lived, running, errand, paid) = of_the_device(|standing| {
            Ok((
                Arc::clone(&standing.machine),
                standing.wallet_at.clone(),
                Arc::clone(&standing.lived),
                Arc::clone(&standing.running),
                Arc::clone(&standing.errand),
                Arc::clone(&standing.paid),
            ))
        })?;
        if running.load(Ordering::SeqCst) {
            return Err("a pulse already running".to_string());
        }
        let cohort = pulse::Cohort::of(&named).map_err(|e| format!("{e:?}"))?;
        let half = machine.naming_half().map_err(|e| format!("{e:?}"))?;
        if !cohort.holds(&half) {
            return Err(
                "this machine stands in no cohort of this window; hand its own half over too"
                    .to_string(),
            );
        }
        // Taken before the round is entered, so a walk begun in between finds the device busy
        // rather than a pulse entering a round under it.
        running
            .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
            .map_err(|_| "a pulse or a walk already running".to_string())?;
        let entered = machine
            .enter_round(from, pulse::opening_chain(), 0)
            .map_err(|e| format!("{e:?}"))
            .and_then(|()| {
                errand
                    .lock()
                    .map(|held| *held)
                    .map_err(|_| "an errand another thread left locked".to_string())
            });
        let asked = match entered {
            Ok(asked) => asked,
            Err(what) => {
                running.store(false, Ordering::SeqCst);
                return Err(what);
            }
        };
        std::thread::spawn(move || {
            let work = |machine: &Machine, window: u64| -> Result<(), NodeError> {
                run_the_errand(machine, &wallet_at, asked, window, &paid)
            };
            match pulse::live_doing(
                &machine,
                &cohort,
                from,
                windows,
                pulse::WAITS_UP_TO,
                Some(&work),
            ) {
                Ok(rows) => {
                    if let Ok(mut held) = lived.lock() {
                        // A window whose cement does not hold this machine's part credited it
                        // nothing, and its row says so with a worth of nought.
                        for one in rows {
                            held.push(Row {
                                window: one.window,
                                rounds: one.rounds,
                                living: one.living,
                                worth: one.right.as_ref().map_or(0, |right| right.worth),
                                accepted_in: one
                                    .right
                                    .as_ref()
                                    .map_or(0, |right| right.accepted_in),
                            });
                        }
                    }
                }
                Err(e) => {
                    let _ = said(format!("the pulse stopped: {e:?}"));
                }
            }
            running.store(false, Ordering::SeqCst);
        });
        Ok(())
    })
}

// The errand of a living machine, run where the terminal runs it: after the round is entered and
// before anything of the window is attested, because a frame stands at the points of the round its
// slot names and a machine releases those points the moment its window closes.
fn run_the_errand(
    machine: &Machine,
    wallet_at: &std::path::Path,
    asked: Errand,
    window: u64,
    paid: &Arc<Mutex<Option<Handed>>>,
) -> Result<(), NodeError> {
    if asked.redeem.is_none() && asked.pay.is_none() {
        return Ok(());
    }
    if let Some(of_the_window) = asked.redeem {
        let rate = *mt_wire::draw::block::<32>().map_err(|e| NodeError::Unreadable {
            what: format!("nothing to draw from: {e:?}"),
        })?;
        // The note enters the wallet as the round applies the frame; what the device reads after
        // is the wallet, so nothing is handed back here.
        machine.redeem_into(
            wallet_at,
            of_the_window,
            window,
            pulse::opening_chain(),
            0,
            &rate,
            Box::new(|_| {}),
        )?;
    }
    if let Some((half, note_pk, amount)) = asked.pay {
        let rate = *mt_wire::draw::block::<32>().map_err(|e| NodeError::Unreadable {
            what: format!("nothing to draw from: {e:?}"),
        })?;
        // What the payee is handed stands once the round has applied the frame and the position of
        // the payee's note is known; until then the last payment reads as none.
        let paid = Arc::clone(paid);
        machine.pay_of_its_own(
            wallet_at,
            &Payee { half, note_pk },
            amount,
            window,
            pulse::opening_chain(),
            0,
            &rate,
            Box::new(move |settled| {
                if let (Ok(done), Ok(mut held)) = (settled, paid.lock()) {
                    *held = Some(Handed {
                        value: done.value,
                        rcm: done.rcm,
                        note_pk: done.note_pk,
                        position: done.position,
                    });
                }
            }),
        )?;
    }
    Ok(())
}

// What the last payment left for its payee, if one was made. Three values and a place: the payer
// hands them over, and the payee enters the note by the door below.
#[no_mangle]
pub extern "C" fn mtc_paid_last(
    value: *mut u8,
    rcm: *mut u8,
    note_pk: *mut u8,
    position: *mut u64,
    present: *mut i32,
) -> i32 {
    door(|| {
        let paid = of_the_device(|standing| Ok(Arc::clone(&standing.paid)))?;
        let held = *paid
            .lock()
            .map_err(|_| "what was paid, left locked by another thread".to_string())?;
        let Some(one) = held else {
            return wrote(present, 0);
        };
        hand_bytes(&one.value.to_le_bytes(), value)?;
        hand_bytes(&one.rcm, rcm)?;
        hand_bytes(&one.note_pk, note_pk)?;
        wrote(position, one.position)?;
        wrote(present, 1)
    })
}

// The note a payee was paid, entered into their own wallet. What they were handed is public of the
// note and private of it — the value, the key it is paid to, the blinding factor and the place —
// and the key that spends it is the person's own and never travels.
#[no_mangle]
pub extern "C" fn mtc_wallet_enter(
    value: *const u8,
    rcm: *const u8,
    note_pk: *const u8,
    position: u64,
) -> i32 {
    door(|| {
        let amount = taken(value, std::mem::size_of::<u128>())?;
        let mut written = [0u8; std::mem::size_of::<u128>()];
        written.copy_from_slice(&amount);
        let rcm = half_at(rcm, 0)?;
        let note_pk = half_at(note_pk, 0)?;
        let wallet = the_wallet()?;
        let person = wallet
            .person()
            .map_err(|e| format!("{e:?}"))?
            .ok_or_else(|| "a wallet holding no person".to_string())?;
        let note = montana_wallet::Note::of(
            u128::from_le_bytes(written),
            note_pk,
            person.note_nullifier_key(),
            rcm,
            position,
        )
        .map_err(|e| format!("{e:?}"))?;
        wallet.enter(note).map_err(|e| format!("{e:?}"))
    })
}

#[no_mangle]
pub extern "C" fn mtc_pulse_running(out: *mut i32) -> i32 {
    door(|| {
        let running = of_the_device(|standing| Ok(Arc::clone(&standing.running)))?;
        wrote(out, i32::from(running.load(Ordering::SeqCst)))
    })
}

#[no_mangle]
pub extern "C" fn mtc_pulse_lived(out: *mut usize) -> i32 {
    door(|| {
        let lived = of_the_device(|standing| Ok(Arc::clone(&standing.lived)))?;
        let held = lived
            .lock()
            .map_err(|_| "what was lived, left locked by another thread".to_string())?;
        wrote(out, held.len())
    })
}

// One window of what was lived, read by its place. Every value of it is a count and none names a
// machine. The fourth is what the window credited this machine: the window's credit where its part stood in
// the cement, nought where it did not.
#[no_mangle]
pub extern "C" fn mtc_pulse_lived_at(
    at: usize,
    window: *mut u64,
    rounds: *mut u32,
    living: *mut usize,
    worth: *mut u64,
    accepted_in: *mut u64,
) -> i32 {
    door(|| {
        let lived = of_the_device(|standing| Ok(Arc::clone(&standing.lived)))?;
        let held = lived
            .lock()
            .map_err(|_| "what was lived, left locked by another thread".to_string())?;
        let row = held
            .get(at)
            .ok_or_else(|| "a window this device has not lived".to_string())?;
        wrote(window, row.window)?;
        wrote(rounds, row.rounds)?;
        wrote(living, row.living)?;
        wrote(worth, row.worth)?;
        wrote(accepted_in, row.accepted_in)
    })
}

// What proving costs on the device holding it, measured on the frame a machine proves to turn the
// right of a window into a note — the heaviest thing this protocol asks of a telephone and the one
// the parameters of the scheme were derived against.
//
// **It changes nothing.** The frame is built and proven and then dropped: nothing is published,
// nothing enters the ledger, and the right of no window is spent. What comes back is the time the
// proving took and the width of what it produced.
#[no_mangle]
pub extern "C" fn mtc_measure_redemption(milliseconds: *mut u64, width: *mut usize) -> i32 {
    door(|| {
        let wallet = the_wallet()?;
        let person = wallet
            .person()
            .map_err(|e| format!("{e:?}"))?
            .ok_or_else(|| "a wallet holding no person".to_string())?;
        let own = Payee {
            half: mt_derive::note::nf_pk(&person.note_nullifier_key()),
            note_pk: person.payment_key(),
        };
        let secret = *mt_wire::draw::block::<32>().map_err(|e| format!("{e:?}"))?;
        // The tree of credited rights a window of this machine alone leaves: its part of window
        // nought at position nought, and the walk to it.
        let part = mt_derive::nullifier::part(&secret, 0)
            .ok_or_else(|| "a secret whose halves are no digest of the family".to_string())?;
        let mut credited = mt_proof::credited::Tree::new(mt_proof::tree_depth());
        credited
            .credit(&[part])
            .map_err(|_| "a tree of one credited part".to_string())?;
        let siblings = credited
            .path(0)
            .ok_or_else(|| "the position just credited".to_string())?;
        let right = montana_node::attest::right_of(&secret, 0).map_err(|e| format!("{e:?}"))?;
        let rate = *mt_wire::draw::block::<32>().map_err(|e| format!("{e:?}"))?;
        let root = montana_node::state::State::new().notes_root();
        let began = std::time::Instant::now();
        let minted = wallet
            .redeem(
                &secret,
                right.window,
                u128::from(right.worth),
                &siblings,
                0,
                &own,
                right.accepted_in,
                &rate,
                &root,
                &credited.root(),
            )
            .map_err(|e| format!("{e:?}"))?;
        let spent = began.elapsed();
        wrote(
            milliseconds,
            u64::try_from(spent.as_millis()).unwrap_or(u64::MAX),
        )?;
        wrote(width, minted.frame.len())
    })
}

#[cfg(test)]
mod status_tests {
    use super::*;

    // CNS-20: rejects a boundary that reads SAID as the pulse cause or loses a real live stall.
    #[test]
    fn the_live_pulse_status_is_independent_of_the_last_boundary_error() {
        let at = std::env::temp_dir().join(format!(
            "mt-boundary-status-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let dir = std::ffi::CString::new(at.to_str().unwrap()).unwrap();
        let listen = std::ffi::CString::new("127.0.0.1:0").unwrap();
        let mut born = 0;
        assert_eq!(mtc_device_open(dir.as_ptr(), listen.as_ptr(), &mut born), 0);
        let machine = the_machine().unwrap();
        let cohort = pulse::Cohort::of(&[machine.naming_half().unwrap()]).unwrap();
        let errand = |machine: &Machine, _| machine.enter_round(1, 0, 0);
        assert!(matches!(
            pulse::live_doing(&machine, &cohort, 0, 1, 1, Some(&errand)),
            Err(NodeError::Stalled {
                on: montana_node::say::Verdict::NoData,
                ..
            })
        ));
        assert_eq!(mtc_machine_reach(std::ptr::null()), -1);
        let mut out = [0 as c_char; 256];
        let mut len = 0;
        assert_eq!(mtc_last_said(out.as_mut_ptr(), out.len(), &mut len), 0);
        let original = out[..len].to_vec();
        assert_eq!(mtc_pulse_status(out.as_mut_ptr(), out.len(), &mut len), 0);
        let status: Vec<u8> = out[..len].iter().map(|byte| *byte as u8).collect();
        assert_eq!(
            String::from_utf8(status).unwrap(),
            machine.counts().status().unwrap().to_string()
        );
        assert_eq!(mtc_last_said(out.as_mut_ptr(), out.len(), &mut len), 0);
        assert_eq!(&out[..len], original.as_slice());
        drop(machine.counts().watch_door());
        assert_eq!(mtc_pulse_status(out.as_mut_ptr(), out.len(), &mut len), -2);
        assert_eq!(mtc_last_said(out.as_mut_ptr(), out.len(), &mut len), 0);
        assert_eq!(&out[..len], original.as_slice());
    }
}
