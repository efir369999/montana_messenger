//! THE PROTOCOL CORE ON WINDOWS (iOS MontanaCore.xcframework, core/Montana-Core/tools/build-for-a-telephone.sh): the boundary
//! crate mt-boundary as it stands in the core, linked whole into one library. Nothing is written here but the list that keeps
//! every door of montana_core.h in the library: each door is the core's own function, exported under its own name.

pub use mt_boundary::*;

/// The doors of montana_core.h, held so the linker keeps every one of them in the library (held, never read).
#[allow(dead_code)]
struct Doors([*const (); 28]);
unsafe impl Sync for Doors {}

#[used]
static DOORS: Doors = Doors([
    mt_boundary::mtc_last_said as *const (),
    mt_boundary::mtc_genesis_state_hash as *const (),
    mt_boundary::mtc_self_test as *const (),
    mt_boundary::mtc_sources_alive as *const (),
    mt_boundary::mtc_device_open as *const (),
    mt_boundary::mtc_device_standing as *const (),
    mt_boundary::mtc_person_bear as *const (),
    mt_boundary::mtc_person_recall as *const (),
    mt_boundary::mtc_person_stands as *const (),
    mt_boundary::mtc_person_payee as *const (),
    mt_boundary::mtc_wallet_balance as *const (),
    mt_boundary::mtc_wallet_notes as *const (),
    mt_boundary::mtc_machine_acquaintance as *const (),
    mt_boundary::mtc_machine_naming_half as *const (),
    mt_boundary::mtc_machine_reach as *const (),
    mt_boundary::mtc_machine_answer as *const (),
    mt_boundary::mtc_machine_head as *const (),
    mt_boundary::mtc_machine_links as *const (),
    mt_boundary::mtc_machine_account as *const (),
    mt_boundary::mtc_errand_redeem as *const (),
    mt_boundary::mtc_errand_pay as *const (),
    mt_boundary::mtc_pulse_begin as *const (),
    mt_boundary::mtc_pulse_running as *const (),
    mt_boundary::mtc_pulse_lived as *const (),
    mt_boundary::mtc_pulse_lived_at as *const (),
    mt_boundary::mtc_paid_last as *const (),
    mt_boundary::mtc_wallet_enter as *const (),
    mt_boundary::mtc_measure_redemption as *const (),
]);
