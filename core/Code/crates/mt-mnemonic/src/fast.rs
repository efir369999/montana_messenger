// A fast source for quantities that live one frame: a delivery identifier, a chunk identifier,
// a cipher nonce. A full gather of six sources costs milliseconds and is not suitable for every frame;
// taking such quantities from the system generator would make them depend on
// a single die and a single firmware, which we do not trust by construction.
//
// Design: HMAC_DRBG (NIST SP 800-90A, section 10.1.2) on SHA-256. The seed is taken by a full
// gather — the same six sources and the same refusal when fewer than three are alive as for the identity
// root. Each output additionally absorbs a cheap crystal probe, so it does not depend
// only on the seed taken earlier. The seed is refreshed by output count and on process change.
//
// What this gives: no client quantity — neither one living for years nor one living a frame — is taken from
// the system generator alone.
//
// AN OUTPUT NEVER PAYS FOR A GATHER (19.09.2026). Previously the seed refresh ran on the thread and at the
// moment where the 4096th output happened: a full gather (a scheduler thread, thirty-two timer sleeps,
// a buffer walk) on the main thread under a foreign lock cost seconds and the system watchdog killed
// the app; a gather failure at a busy instant was a refusal in the middle of work. Now the next
// seed is gathered in advance by a separate thread once the counter has passed three quarters, and lies
// ready: an output takes it without waiting, and "dead" is pronounced only when a gather proven
// by three windows returned a refusal.

#[cfg(test)]
use std::cell::Cell;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;
use std::thread;

use zeroize::{Zeroize, Zeroizing};

use crate::entropy::{generate_entropy, EntropyError};
use crate::hmac::hmac_sha256;
use crate::sources::quartz_tick;

// No more than this many outputs between seed refreshes. SP 800-90A allows 2^48;
// many orders of magnitude fewer are used, because a refresh here costs milliseconds, not hours,
// and the cost of the margin is negligible.
const RESEED_AFTER: u64 = 4_096;
// The next seed is ordered at three quarters of the way to the refresh.
const PREFETCH_AT: u64 = RESEED_AFTER / 4 * 3;
// If the pre-ordered seed is still not ready after four periods, the machine is not giving
// threads time, and this is also a refusal, named honestly.
const RESEED_HARD_CAP: u64 = RESEED_AFTER * 4;

type Seed = Zeroizing<[u8; 32]>;
static NEXT_SEED: Mutex<Option<Result<Seed, EntropyError>>> = Mutex::new(None);
static PREFETCH_RUNNING: AtomicBool = AtomicBool::new(false);

// Under test a gather is counted on the thread that ran it, and the gathering thread passes a gate
// before it gathers: a test holds the gate and reads whether an output ever gathered on its own thread.
#[cfg(test)]
thread_local! {
    static GATHERS_HERE: Cell<u32> = const { Cell::new(0) };
}
#[cfg(test)]
static GATE: Mutex<()> = Mutex::new(());

fn gather() -> Result<Seed, EntropyError> {
    #[cfg(test)]
    GATHERS_HERE.with(|g| g.set(g.get() + 1));
    generate_entropy()
}

fn order_next_seed() {
    // A ready seed already lies there — do not order a second one: one gather per period, not two.
    if NEXT_SEED
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .is_some()
    {
        return;
    }
    if PREFETCH_RUNNING.swap(true, Ordering::AcqRel) {
        return;
    }
    let spawned = thread::Builder::new()
        .name("mt-entropy-reseed".into())
        .spawn(|| {
            #[cfg(test)]
            let _gate = GATE.lock().unwrap_or_else(|e| e.into_inner());
            let seed = gather();
            *NEXT_SEED.lock().unwrap_or_else(|e| e.into_inner()) = Some(seed);
            PREFETCH_RUNNING.store(false, Ordering::Release);
        });
    if spawned.is_err() {
        // No thread was granted — gather here and now, as before; a rarity, not the path.
        let seed = gather();
        *NEXT_SEED.lock().unwrap_or_else(|e| e.into_inner()) = Some(seed);
        PREFETCH_RUNNING.store(false, Ordering::Release);
    }
}

struct Drbg {
    key: [u8; 32],
    v: [u8; 32],
    counter: u64,
    pid: u32,
}

impl Drbg {
    fn instantiate() -> Result<Self, EntropyError> {
        let seed = gather()?;
        let mut d = Drbg {
            key: [0x00; 32],
            v: [0x01; 32],
            counter: 0,
            pid: std::process::id(),
        };
        d.update(Some(&seed[..]));
        Ok(d)
    }

    // SP 800-90A 10.1.2.2
    fn update(&mut self, provided: Option<&[u8]>) {
        let mut msg = Vec::with_capacity(65 + provided.map_or(0, |p| p.len()));
        msg.extend_from_slice(&self.v);
        msg.push(0x00);
        if let Some(p) = provided {
            msg.extend_from_slice(p);
        }
        self.key = hmac_sha256(&self.key, &msg);
        self.v = hmac_sha256(&self.key, &self.v);
        if let Some(p) = provided {
            msg.clear();
            msg.extend_from_slice(&self.v);
            msg.push(0x01);
            msg.extend_from_slice(p);
            self.key = hmac_sha256(&self.key, &msg);
            self.v = hmac_sha256(&self.key, &self.v);
        }
        msg.zeroize();
    }

    fn generate(&mut self, out: &mut [u8]) -> Result<(), EntropyError> {
        let pid = std::process::id();
        if pid != self.pid {
            // A new process — a new seed, here and now: it has no foreign thread yet.
            let seed = gather()?;
            self.update(Some(&seed[..]));
            self.counter = 0;
            self.pid = pid;
        }
        if self.counter >= PREFETCH_AT {
            order_next_seed();
        }
        if self.counter >= RESEED_AFTER {
            let ready = NEXT_SEED.lock().unwrap_or_else(|e| e.into_inner()).take();
            match ready {
                Some(Ok(seed)) => {
                    self.update(Some(&seed[..]));
                    self.counter = 0;
                },
                Some(Err(e)) => return Err(e),
                None => {
                    if self.counter >= RESEED_HARD_CAP {
                        return Err(EntropyError::Csprng);
                    }
                    // The seed is still being gathered — the output does not wait for it: SP 800-90A permits 2^48
                    // outputs per seed, our period is millions of times shorter.
                },
            }
        }
        let tick = quartz_tick();
        self.update(Some(&tick));
        let mut filled = 0;
        while filled < out.len() {
            self.v = hmac_sha256(&self.key, &self.v);
            let take = core::cmp::min(32, out.len() - filled);
            out[filled..filled + take].copy_from_slice(&self.v[..take]);
            filled += take;
        }
        // Backtracking resistance: the state after an output does not recover what was issued.
        self.update(Some(&tick));
        self.counter += 1;
        Ok(())
    }
}

static DRBG: Mutex<Option<Drbg>> = Mutex::new(None);

pub fn random_fast(out: &mut [u8]) -> Result<(), EntropyError> {
    let mut guard = DRBG.lock().map_err(|_| EntropyError::Csprng)?;
    if guard.is_none() {
        *guard = Some(Drbg::instantiate()?);
    }
    guard
        .as_mut()
        .expect("created on the line above")
        .generate(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn two_draws_differ() {
        let (mut a, mut b) = ([0u8; 32], [0u8; 32]);
        random_fast(&mut a).unwrap();
        random_fast(&mut b).unwrap();
        assert_ne!(
            a, b,
            "two consecutive outputs coincided — there is no source"
        );
    }

    #[test]
    fn every_length_is_filled() {
        for n in [1usize, 8, 12, 16, 31, 32, 33, 64, 255] {
            let mut buf = vec![0u8; n];
            random_fast(&mut buf).unwrap();
            assert!(buf.iter().any(|&b| b != 0), "output of length {n} is empty");
        }
    }

    #[test]
    fn a_thousand_draws_never_repeat() {
        use std::collections::HashSet;
        let mut seen = HashSet::new();
        for _ in 0..1_000 {
            let mut b = [0u8; 16];
            random_fast(&mut b).unwrap();
            assert!(seen.insert(b), "repeat among a thousand outputs");
        }
    }

    #[test]
    fn reseeding_does_not_break_the_stream() {
        let mut prev = [0u8; 32];
        for _ in 0..(RESEED_AFTER + 16) {
            let mut b = [0u8; 32];
            random_fast(&mut b).unwrap();
            assert_ne!(b, prev);
            prev = b;
        }
    }

    // The vector catches an implementation that gathers the seed on the output thread or waits for it.
    // The gathering thread is held at its gate, so after at most one seed gathered past the gate before
    // the hold the counter climbs past the refresh point with no seed ready, and the outputs go on; a
    // gather that an output ran on its own thread is counted there. No clock is read: the old threshold of
    // two milliseconds measured the host, not the code (an output with no gather beside it took 25-240 ms
    // on Lauterbourg-2, 29.10.2026). An output that waited for the held gather would not return; one that
    // gathered at the refresh point resets the counter and never stands past it.
    #[test]
    fn the_reseeding_draw_never_pays_for_the_gather() {
        let mut b = [0u8; 16];
        random_fast(&mut b).unwrap();
        let before = GATHERS_HERE.with(Cell::get);
        let held = GATE.lock().unwrap_or_else(|e| e.into_inner());
        let mut past = false;
        for _ in 0..RESEED_HARD_CAP {
            random_fast(&mut b).unwrap();
            let counter = DRBG
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .as_ref()
                .expect("instantiated by the first output")
                .counter;
            if counter >= RESEED_AFTER + 64 {
                past = true;
                break;
            }
        }
        drop(held);
        assert_eq!(
            GATHERS_HERE.with(Cell::get),
            before,
            "an output gathered the seed on its own thread"
        );
        assert!(
            past,
            "the outputs never stood past the refresh point while the gather was held"
        );
    }
}
