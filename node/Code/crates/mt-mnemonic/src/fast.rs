// Быстрый источник для величин, живущих один кадр: идентификатор посылки, идентификатор куска,
// одноразовое число шифра. Полный сбор шести источников стоит миллисекунды и на каждый кадр
// не годится; брать такие величины у генератора системы — значит поставить их зависимость от
// одного кристалла и одной прошивки, которым мы не доверяем по построению.
//
// Устройство: HMAC_DRBG (NIST SP 800-90A, раздел 10.1.2) на SHA-256. Зерно берётся полным
// сбором — те же шесть источников и тот же отказ, когда живых меньше трёх, что у корня
// личности. Каждый выпуск дополнительно впитывает дешёвую пробу кварца, поэтому не зависит
// только от зерна, взятого раньше. Зерно обновляется по счёту выпусков и при смене процесса.
//
// Что это даёт: ни одна величина клиента — ни живущая годы, ни живущая кадр — не берётся у
// генератора системы в одиночку.
//
// ВЫПУСК НИКОГДА НЕ ПЛАТИТ ЗА СБОР (19.09.2026). Прежде обновление зерна шло на том потоке и в тот
// момент, где случился 4096-й выпуск: полный сбор (поток планировщика, тридцать два сна таймера,
// обход буфера) на главном потоке под чужим замком стоил секунды и сторож системы убивал
// приложение; провал сбора в занятое мгновение был отказом посреди работы. Теперь следующее
// зерно собирается заранее отдельным потоком, когда счётчик прошёл три четверти, и лежит
// готовым: выпуск берёт его, не ожидая, а «мертва» произносится только когда сбор, доказанный
// тремя окнами, вернул отказ.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;
use std::thread;

use zeroize::{Zeroize, Zeroizing};

use crate::entropy::{generate_entropy, EntropyError};
use crate::hmac::hmac_sha256;
use crate::sources::quartz_tick;

// Между обновлениями зерна — не больше этого числа выпусков. SP 800-90A разрешает 2^48;
// взято на много порядков меньше, потому что обновление здесь стоит миллисекунды, а не часы,
// и цена запаса ничтожна.
const RESEED_AFTER: u64 = 4_096;
// Следующее зерно заказывается на трёх четвертях пути к обновлению.
const PREFETCH_AT: u64 = RESEED_AFTER / 4 * 3;
// Если заранее заказанное зерно всё ещё не готово после четырёх сроков — машина не отдаёт
// потокам время, и это тоже отказ, названный честно.
const RESEED_HARD_CAP: u64 = RESEED_AFTER * 4;

type Seed = Zeroizing<[u8; 32]>;
static NEXT_SEED: Mutex<Option<Result<Seed, EntropyError>>> = Mutex::new(None);
static PREFETCH_RUNNING: AtomicBool = AtomicBool::new(false);

fn order_next_seed() {
    // Готовое зерно уже лежит — второго не заказывать: один сбор на срок, не два.
    if NEXT_SEED.lock().unwrap_or_else(|e| e.into_inner()).is_some() {
        return;
    }
    if PREFETCH_RUNNING.swap(true, Ordering::AcqRel) {
        return;
    }
    let spawned = thread::Builder::new()
        .name("mt-entropy-reseed".into())
        .spawn(|| {
            let seed = generate_entropy();
            *NEXT_SEED.lock().unwrap_or_else(|e| e.into_inner()) = Some(seed);
            PREFETCH_RUNNING.store(false, Ordering::Release);
        });
    if spawned.is_err() {
        // Потока не дали — сбор здесь и сейчас, как прежде; редкость, не путь.
        let seed = generate_entropy();
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
        let seed = generate_entropy()?;
        let mut d = Drbg { key: [0x00; 32], v: [0x01; 32], counter: 0, pid: std::process::id() };
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
            // Новый процесс — новое зерно, здесь и сейчас: чужого потока у него ещё нет.
            let seed = generate_entropy()?;
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
                    // Зерно ещё собирается — выпуск его не ждёт: SP 800-90A допускает 2^48
                    // выпусков на зерно, наш срок в миллионы раз короче.
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
        // Обратная секретность: состояние после выпуска не восстанавливает выданное.
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
    guard.as_mut().expect("создан строкой выше").generate(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn two_draws_differ() {
        let (mut a, mut b) = ([0u8; 32], [0u8; 32]);
        random_fast(&mut a).unwrap();
        random_fast(&mut b).unwrap();
        assert_ne!(a, b, "два выпуска подряд совпали — источника нет");
    }

    #[test]
    fn every_length_is_filled() {
        for n in [1usize, 8, 12, 16, 31, 32, 33, 64, 255] {
            let mut buf = vec![0u8; n];
            random_fast(&mut buf).unwrap();
            assert!(buf.iter().any(|&b| b != 0), "выпуск длины {n} пуст");
        }
    }

    #[test]
    fn a_thousand_draws_never_repeat() {
        use std::collections::HashSet;
        let mut seen = HashSet::new();
        for _ in 0..1_000 {
            let mut b = [0u8; 16];
            random_fast(&mut b).unwrap();
            assert!(seen.insert(b), "повтор среди тысячи выпусков");
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

    // Вектор ловит реализацию, которая собирает зерно на потоке выпуска: у неё 4096-й выпуск
    // стоит столько же, сколько полный сбор (миллисекунды и сны таймера), у этой — микросекунды,
    // потому что зерно заказано заранее. Порог — сотая доля сбора: сбор на этой машине не
    // короче двух миллисекунд (256 замеров по 256 шагов часов), выпуск — не длиннее ста
    // микросекунд.
    #[test]
    fn the_reseeding_draw_never_pays_for_the_gather() {
        for _ in 0..(RESEED_AFTER + 64) {
            let mut b = [0u8; 16];
            random_fast(&mut b).unwrap();
        }
        // дождаться готового зерна, чтобы следующий срок обновления взял его сразу
        let born = std::time::Instant::now();
        while PREFETCH_RUNNING.load(Ordering::Acquire) && born.elapsed() < std::time::Duration::from_secs(5) {
            thread::yield_now();
        }
        let mut worst = std::time::Duration::ZERO;
        for _ in 0..(RESEED_AFTER + 64) {
            let mut b = [0u8; 16];
            let t = std::time::Instant::now();
            random_fast(&mut b).unwrap();
            worst = worst.max(t.elapsed());
        }
        assert!(worst < std::time::Duration::from_millis(2), "выпуск заплатил за сбор: {worst:?}");
    }
}
