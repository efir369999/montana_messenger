//! THE PROTOCOL CORE (iOS MTWalletCore, MTNetworkNode; MontanaCore.xcframework): the reference implementation of the protocol,
//! core/Montana-Core, its boundary crate mt-boundary built unchanged into montana_core.dll (app/protocol-core) and read through
//! its C doors, as a telephone reads it. EVERY SERVER AND PHONE OF OURS IS A NODE (the author's word 06.10.2026 17:2x MSK): this
//! machine opens its own machine of the core -- born once, its secret drawn here and never carried to another computer -- and
//! reaches the machines of the Global TimeChain's genesis by the post-quantum handshake of the set. The person is not opened in
//! the core (iOS: the words stay in the keychain alone), so the core's wallet answers that it is not open, as the phone's does.
//! Missing state stays missing: nothing here mints, pays or enters a note.

use crate::genesis::GENESIS;
use serde::Serialize;
use std::collections::BTreeSet;
use std::ffi::{c_char, CString};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicI64, Ordering};
use std::sync::{Mutex, OnceLock};

type Out32 = unsafe extern "C" fn(*mut i32) -> i32;
type OutUsize = unsafe extern "C" fn(*mut usize) -> i32;
type Open = unsafe extern "C" fn(*const c_char, *const c_char, *mut i32) -> i32;
type Reach = unsafe extern "C" fn(*const c_char) -> i32;
type Bytes = unsafe extern "C" fn(*mut u8) -> i32;
type Head = unsafe extern "C" fn(*mut u64, *mut i32) -> i32;
type LivedAt = unsafe extern "C" fn(usize, *mut u64, *mut u32, *mut usize, *mut u64, *mut u64) -> i32;
type Said = unsafe extern "C" fn(*mut c_char, usize, *mut usize) -> i32;

/// The doors of montana_core.h a client reads (iOS MTWalletCore): the device, the person's standing, the wallet, the machine,
/// its pulse and the reason of a refusal.
struct Doors {
    device_open: Open,
    device_standing: Out32,
    person_stands: Out32,
    wallet_balance: Bytes,
    wallet_notes: OutUsize,
    machine_head: Head,
    machine_reach: Reach,
    pulse_running: Out32,
    pulse_lived: OutUsize,
    pulse_lived_at: LivedAt,
    last_said: Said,
}

/// The library beside the program, loaded once; None -- this build carries no core (iOS: «unavailable on this device»).
fn doors() -> Option<&'static Doors> {
    static DOORS: OnceLock<Option<Doors>> = OnceLock::new();
    DOORS.get_or_init(|| {
        let dll = std::env::current_exe().ok()?.parent()?.join("montana_core.dll");
        load(&dll)
    }).as_ref()
}

#[cfg(windows)]
fn load(dll: &Path) -> Option<Doors> {
    use std::os::windows::ffi::OsStrExt;
    use windows_sys::Win32::System::LibraryLoader::{GetProcAddress, LoadLibraryW};
    if !dll.exists() {
        return None;
    }
    let wide: Vec<u16> = dll.as_os_str().encode_wide().chain(Some(0)).collect();
    let module = unsafe { LoadLibraryW(wide.as_ptr()) };
    if module.is_null() {
        return None;
    }
    macro_rules! door {
        ($name:literal, $ty:ty) => {{
            let f = unsafe { GetProcAddress(module, concat!($name, "\0").as_ptr()) }?;
            unsafe { std::mem::transmute::<unsafe extern "system" fn() -> isize, $ty>(f) }
        }};
    }
    Some(Doors {
        device_open: door!("mtc_device_open", Open),
        device_standing: door!("mtc_device_standing", Out32),
        person_stands: door!("mtc_person_stands", Out32),
        wallet_balance: door!("mtc_wallet_balance", Bytes),
        wallet_notes: door!("mtc_wallet_notes", OutUsize),
        machine_head: door!("mtc_machine_head", Head),
        machine_reach: door!("mtc_machine_reach", Reach),
        pulse_running: door!("mtc_pulse_running", Out32),
        pulse_lived: door!("mtc_pulse_lived", OutUsize),
        pulse_lived_at: door!("mtc_pulse_lived_at", LivedAt),
        last_said: door!("mtc_last_said", Said),
    })
}
#[cfg(not(windows))]
fn load(_dll: &Path) -> Option<Doors> {
    None
}

/// The reason the core gave for its last refusal, in its own words (iOS said(rc)); empty -- none.
fn said(rc: i32) -> String {
    let Some(d) = doors() else { return String::new() };
    if rc == 0 {
        return String::new();
    }
    let mut out = vec![0 as c_char; 512];
    let mut len = 0usize;
    if unsafe { (d.last_said)(out.as_mut_ptr(), out.len(), &mut len) } != 0 {
        return String::new();
    }
    let bytes: Vec<u8> = out[..len.min(out.len())].iter().map(|&c| c as u8).collect();
    String::from_utf8_lossy(&bytes).into_owned()
}

/// One window the pulse lived (iOS MTWalletCore.Window): its number, the share it gives a right to, the window it is redeemed in.
#[derive(Serialize, Clone)]
pub struct Window {
    pub id: u64,
    pub share: u64,
    #[serde(rename = "acceptedIn")]
    pub accepted_in: u64,
}

/// What the core says of the wallet (iOS MTWalletCore.Snapshot): the confirmed balance in decimal digits, the notes behind it,
/// the last window the machine confirmed, whether the pulse runs and the windows it lived, the newest first.
#[derive(Serialize, Clone)]
pub struct Snapshot {
    pub balance: String,
    pub notes: usize,
    #[serde(rename = "lastConfirmedWindow")]
    pub last_confirmed_window: Option<u64>,
    #[serde(rename = "pulseRunning")]
    pub pulse_running: bool,
    pub windows: Vec<Window>,
}

/// Why the core says nothing of the wallet (iOS MTWalletCore.Absence): no core in this build, the device not standing, the person
/// not opened, or a door refused.
pub fn read() -> Result<Snapshot, &'static str> {
    let Some(d) = doors() else { return Err("unavailable") };
    unsafe {
        let mut standing = 0i32;
        if (d.device_standing)(&mut standing) != 0 {
            return Err("refused");
        }
        if standing != 1 {
            return Err("device");
        }
        if (d.person_stands)(&mut standing) != 0 {
            return Err("refused");
        }
        if standing != 1 {
            return Err("person");
        }
        let mut bytes = [0u8; 16];
        let (mut notes, mut present, mut head, mut running, mut count) = (0usize, 0i32, 0u64, 0i32, 0usize);
        if (d.wallet_balance)(bytes.as_mut_ptr()) != 0 || (d.wallet_notes)(&mut notes) != 0 || (d.machine_head)(&mut head, &mut present) != 0
            || (d.pulse_running)(&mut running) != 0 || (d.pulse_lived)(&mut count) != 0 {
            return Err("refused");
        }
        // a bounded view of the core's receipts; the core keeps the source, nothing here mints
        let mut windows = vec![];
        for i in count.saturating_sub(100)..count {
            let (mut window, mut rounds, mut living, mut share, mut accepted) = (0u64, 0u32, 0usize, 0u64, 0u64);
            if (d.pulse_lived_at)(i, &mut window, &mut rounds, &mut living, &mut share, &mut accepted) != 0 {
                return Err("refused");
            }
            windows.push(Window { id: window, share, accepted_in: accepted });
        }
        windows.reverse();
        Ok(Snapshot { balance: u128::from_le_bytes(bytes).to_string(), notes, last_confirmed_window: (present == 1).then_some(head),
                      pulse_running: running == 1, windows })
    }
}

/// How many machines of the genesis this computer's node holds a link to (iOS MTNetworkNode.reached); -1 -- the machine not opened.
static REACHED: AtomicI64 = AtomicI64::new(-1);
static JOINING: AtomicBool = AtomicBool::new(false);
static HELD: Mutex<BTreeSet<usize>> = Mutex::new(BTreeSet::new());

pub fn reached() -> Option<i64> {
    let n = REACHED.load(Ordering::SeqCst);
    (n >= 0).then_some(n)
}
pub fn genesis_count() -> usize {
    GENESIS.len()
}

/// THE NODE JOINS (iOS MTNetworkNode.join): opened once at the folder «Core» of this person's data -- the machine's secret never
/// leaves this computer -- answering at a loopback door, and every machine of the genesis not yet held reached, off the window's
/// thread.
pub fn join(data: &Path) {
    // once a minute at most: the page reads itself every few seconds, the telephone joins once an opening
    static LAST: AtomicI64 = AtomicI64::new(0);
    let now = crate::wire::now_ms();
    if doors().is_none() || HELD.lock().unwrap().len() >= GENESIS.len() || now - LAST.load(Ordering::SeqCst) < 60_000
        || JOINING.swap(true, Ordering::SeqCst) {
        return;
    }
    LAST.store(now, Ordering::SeqCst);
    let dir = data.join("Core");
    std::thread::spawn(move || {
        let missing: Vec<usize> = (0..GENESIS.len()).filter(|i| !HELD.lock().unwrap().contains(i)).collect();
        if let Some(got) = reach(&dir, &missing) {
            let mut held = HELD.lock().unwrap();
            held.extend(got);
            REACHED.store(held.len() as i64, Ordering::SeqCst);
        }
        JOINING.store(false, Ordering::SeqCst);
    });
}

fn reach(dir: &PathBuf, missing: &[usize]) -> Option<Vec<usize>> {
    let d = doors()?;
    let mut standing = 0i32;
    if unsafe { (d.device_standing)(&mut standing) } != 0 {
        return None;
    }
    if standing == 0 {
        std::fs::create_dir_all(dir).ok()?;
        let (path, listen) = (CString::new(dir.to_string_lossy().as_bytes()).ok()?, CString::new("127.0.0.1:0").ok()?);
        let mut born = 0i32;
        let rc = unsafe { (d.device_open)(path.as_ptr(), listen.as_ptr(), &mut born) };
        crate::trace_line(&format!("core_node open rc={rc} born={born} {}", said(rc)));
        if rc != 0 {
            return None;
        }
    }
    let mut got = vec![];
    for &i in missing {
        let Ok(line) = CString::new(GENESIS[i]) else { continue };
        let rc = unsafe { (d.machine_reach)(line.as_ptr()) };
        crate::trace_line(&format!("core_node reach {i} rc={rc} {}", said(rc)));
        if rc == 0 {
            got.push(i);
        }
    }
    Some(got)
}
