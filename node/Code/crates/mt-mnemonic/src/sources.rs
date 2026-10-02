// Корень никогда не берётся из одного источника. Так устроен и Bitcoin Core, где системный
// генератор смешивается с инструкциями процессора, счётчиками времени и внутренним пулом;
// так же поступает аппаратный кошелёк, складывающий свою случайность с чужой.
//
// Правило сложения: отсутствие необязательного источника рождение не отменяет, отсутствие
// системного — отменяет. Результат непредсказуем, пока непредсказуем хотя бы один источник.
//
// ЖИВОСТЬ ИСТОЧНИКА ИЗМЕРЯЕТСЯ, А НЕ ПРЕДПОЛАГАЕТСЯ. Прежде трое из пяти считались живыми по
// факту, что код для них отработал: длина набранного постоянна, значит признак жизни стоял
// всегда, значит счётчик не опускался ниже трёх ни на одной машине — и порог, ради которого он
// заведён, не мог сработать никогда. Теперь у всех семи одно правило: источник жив, когда его
// собственные замеры РАЗЛИЧАЮТСЯ между собой. Набор одинаковых чисел есть отсутствие источника,
// названное его именем.

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use mt_codec::domain;
use zeroize::{Zeroize, Zeroizing};

use crate::sha256_raw;

pub const JITTER_ROUNDS: usize = 256;
pub const MEMORY_ROUNDS: usize = 128;
pub const QUARTZ_SAMPLES: usize = 64;
pub const SCHEDULER_SAMPLES: usize = 32;
pub const TIMER_SAMPLES: usize = 32;

// ЗАМЕР В ШАГАХ ЧАСОВ, НЕ В ЕДИНИЦАХ РАБОТЫ (19.09.2026). Часы Apple шагают по 24 МГц — по 41,67 нс,
// и число различных значений замера ФИКСИРОВАННОЙ работы падает с ростом скорости кристалла: на
// iPhone 17 (A19) 4096 умножений укладывались в горстку шагов, «дрожание» и «память» глохли, и
// живая машина получала отказ — одиннадцать падений у двух тестировщиков за неделю на пяти сборках
// подряд. Порог, «выведенный замером на этой машине», был константой одной машины.
//
// Теперь работа каждого замера калибруется ПО САМОЙ ИЗМЕРЯЕМОЙ ВЕЛИЧИНЕ: она удваивается, пока
// пробные замеры не покажут долю моды не выше четверти — двойной запас к порогу живости в
// половину — и не меньше TICKS_PER_SAMPLE шагов ЭТИХ часов. Кривая измерена (19.09, Apple M):
// 24 шага на замер — мода 42 %, 181 — 22 %, 579 — 12 %, 1017 — 8 %, 1645 — 3 %: шум копится с
// работой, квантование остаётся постоянным, и доля моды падает монотонно. Быстрый кристалл просто
// делает больше работы, пока его замеры не начнут различаться. Правило живости не меняется — оно
// начинает измерять то, что называет, и на любом кристалле.
pub const TICKS_PER_SAMPLE: u64 = 256;
// Пробных замеров на шаг калибровки и допустимая доля моды среди них (не выше четверти).
const PROBE_SAMPLES: usize = 32;
const PROBE_MODE_NUM: usize = 1;
const PROBE_MODE_DEN: usize = 4;
// «Мертва» — свойство машины, а не мгновения: вердикт ставится только когда замеры не различаются
// ни в одном из трёх окон, каждое в четыре раза шире предыдущего (256, 1024, 4096 шагов).
pub const PROOF_SCALES: [u64; 3] = [1, 4, 16];
// Калибровка начинается с этого числа единиц работы и удваивает его, пока замер не покроет окно.
const CALIBRATION_START: u64 = 1_024;
const CALIBRATION_CAP: u64 = 1 << 28;
// Потолок одного замера: на часах с грубым шагом (миллисекунда у иной виртуальной машины) окно в
// шагах раздуло бы сбор до минут; выше двух миллисекунд на замер источник честно измеряется
// тем, что есть, и умирает, если не различается.
const MAX_SAMPLE_NS: u64 = 2_000_000;

// Мера живости — доля САМОГО ЧАСТОГО замера, оценка min-entropy по самому частому значению
// (NIST SP 800-90B, раздел 6.3.1). Доля не выше половины означает не меньше одного бита
// непредсказуемости на замер. Порог выведен замером, а не назначен: на этой машине самое частое
// значение занимает от двух до двенадцати процентов у всех временных источников, тогда как у
// мёртвого источника оно занимает все сто. Запас — вчетверо, и он держится, когда машина занята.
//
// Доля РАЗЛИЧНЫХ замеров на эту роль не годится: она плавает вместе с загрузкой машины —
// на свободной семьдесят пять процентов, на занятой сорок, — и порог по ней отказал бы
// честному телефону в разгар работы. Ложный отказ так же плох, как ложный пропуск.
const MAX_REPEAT_NUM: usize = 1;
const MAX_REPEAT_DEN: usize = 2;
// Меньше четырёх различных значений — не источник, а колебание между двумя числами.
const MIN_DISTINCT_CHUNKS: usize = 4;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SourceReport {
    pub os_csprng: bool,
    pub jitter: bool,
    pub memory: bool,
    pub quartz: bool,
    pub scheduler: bool,
    pub timer: bool,
    /// В каком окне доказательства снят отчёт: 1, 4 или 16 (× TICKS_PER_SAMPLE шагов часов).
    pub scale: u64,
    /// Шаг часов этой машины в наносекундах.
    pub step_ns: u64,
}

impl SourceReport {
    pub const TOTAL: usize = 6;
    pub fn count(&self) -> usize {
        usize::from(self.os_csprng)
            + usize::from(self.jitter)
            + usize::from(self.memory)
            + usize::from(self.quartz)
            + usize::from(self.scheduler)
            + usize::from(self.timer)
    }
}

// Одно правило живости на все семь источников: замеры обязаны различаться между собой.
// Источник, который отработал и вернул одно и то же число, живым не считается.
fn is_alive(bytes: &[u8], samples: usize) -> bool {
    if samples < MIN_DISTINCT_CHUNKS || bytes.len() < samples * 8 {
        return false;
    }
    if distinct_chunks(bytes) < MIN_DISTINCT_CHUNKS {
        return false;
    }
    max_repeat(bytes) * MAX_REPEAT_DEN <= samples * MAX_REPEAT_NUM
}

// Сколько раз повторяется самый частый замер. Отсюда берётся оценка непредсказуемости на
// замер: доля этого значения и есть вероятность угадать замер наилучшей догадкой.
fn max_repeat(bytes: &[u8]) -> usize {
    let mut v: Vec<&[u8]> = bytes.chunks(8).collect();
    v.sort_unstable();
    let mut best = 0usize;
    let mut run = 0usize;
    let mut prev: Option<&[u8]> = None;
    for c in v {
        if Some(c) == prev {
            run += 1;
        } else {
            run = 1;
            prev = Some(c);
        }
        if run > best {
            best = run;
        }
    }
    best
}

// Шаг часов этой машины: наименьшая ненулевая разность двух подряд чтений. Свойство железа, не
// мгновения, поэтому берётся один раз за процесс. На Apple — 41–42 нс (таймбаза 24 МГц).
pub fn clock_step_ns() -> u64 {
    static STEP: OnceLock<u64> = OnceLock::new();
    *STEP.get_or_init(|| {
        let mut best = u64::MAX;
        for _ in 0..4_096 {
            let a = Instant::now();
            let mut b = Instant::now();
            let mut spins = 0u32;
            while b == a && spins < 100_000 {
                b = Instant::now();
                spins += 1;
            }
            let d = b.duration_since(a).as_nanos() as u64;
            if d != 0 && d < best {
                best = d;
            }
        }
        if best == u64::MAX { 1 } else { best.max(1) }
    })
}

// Сколько единиц работы нужно замеру, чтобы (а) занимать не меньше TICKS_PER_SAMPLE × scale
// шагов часов и (б) на пробной выборке различаться: мода не выше четверти. Удвоение с
// CALIBRATION_START до потолка; сама калибровка — тёплый прогон, поэтому первый холодный
// замер в выборку не попадает. У потолка возвращается что есть — источник честно измерится и
// умрёт, если не различается.
fn calibrate(scale: u64, mut work: impl FnMut(u64)) -> u64 {
    let need = Duration::from_nanos(
        TICKS_PER_SAMPLE.saturating_mul(scale).saturating_mul(clock_step_ns()).min(MAX_SAMPLE_NS),
    );
    let mut units = CALIBRATION_START;
    loop {
        let mut probe = Vec::with_capacity(PROBE_SAMPLES * 8);
        let mut total = Duration::ZERO;
        for _ in 0..PROBE_SAMPLES {
            let start = Instant::now();
            work(units);
            let took = start.elapsed();
            total += took;
            probe.extend_from_slice(&(took.as_nanos() as u64).to_le_bytes());
        }
        let long_enough = total / PROBE_SAMPLES as u32 >= need;
        let noisy_enough = distinct_chunks(&probe) >= MIN_DISTINCT_CHUNKS
            && max_repeat(&probe) * PROBE_MODE_DEN <= PROBE_SAMPLES * PROBE_MODE_NUM;
        let at_cap = units >= CALIBRATION_CAP || total / PROBE_SAMPLES as u32 >= Duration::from_nanos(MAX_SAMPLE_NS);
        if (long_enough && noisy_enough) || at_cap {
            return units;
        }
        units *= 2;
    }
}

fn lcg_work(units: u64) {
    let mut acc: u64 = 0x9E37_79B9_7F4A_7C15;
    for i in 0..units {
        acc = acc.wrapping_mul(6_364_136_223_846_793_005).wrapping_add(i | 1);
        std::hint::black_box(acc);
    }
}

// Дрожание исполнения: одна и та же короткая работа никогда не занимает ровно столько же
// тактов — мешают кэш, предсказатель переходов, температура, соседние ядра. Младшие биты
// замеров и есть шум, которого не выдаёт ни ядро системы, ни её генератор.
fn jitter_bytes(scale: u64) -> Vec<u8> {
    // Работы должно быть заметно больше разрешения часов, иначе замер вернёт одно и то же
    // число, и «дрожание» окажется выдумкой. Сколько именно — решают часы этой машины.
    let units = calibrate(scale, lcg_work);
    let mut out = Vec::with_capacity(JITTER_ROUNDS * 8);
    for _ in 0..JITTER_ROUNDS {
        let start = Instant::now();
        lcg_work(units);
        out.extend_from_slice(&(start.elapsed().as_nanos() as u64).to_le_bytes());
    }
    out
}

// Обращение к памяти: ход по цепочке ссылок внутри буфера, заведомо большего ближних уровней
// кэша. Задержка каждого шага решается тем, что в кэше лежит сейчас, работой соседних ядер и
// контроллером памяти — механизм, отличный от дрожания чистого счёта.
fn memory_bytes(scale: u64) -> Vec<u8> {
    const CELLS: usize = 1 << 16; // 64K ячеек по 8 байт = 512 КиБ: мимо ближних уровней кэша
    const STRIDE: usize = 20_011; // взаимно прост с длиной: обход накрывает все ячейки
    let mut chain: Vec<usize> = vec![0; CELLS];
    let mut idx = 0usize;
    for slot in chain.iter_mut() {
        idx = (idx + STRIDE) % CELLS;
        *slot = idx;
    }
    // Размер кэша — свойство чужого железа (L2 у A19 вмещает весь буфер): живость источника
    // держится не на промахе кэша, а на том, что ход по цепочке занимает не меньше K шагов часов.
    let mut pos = 0usize;
    let steps = calibrate(scale, |n| {
        for _ in 0..n {
            pos = chain[pos];
            std::hint::black_box(pos);
        }
    });
    let mut out = Vec::with_capacity(MEMORY_ROUNDS * 8);
    for _ in 0..MEMORY_ROUNDS {
        let start = Instant::now();
        for _ in 0..steps {
            pos = chain[pos];
            std::hint::black_box(pos);
        }
        out.extend_from_slice(&(start.elapsed().as_nanos() as u64).to_le_bytes());
    }
    chain.zeroize();
    out
}


// Кварц. Часы, которые считают ход времени внутри машины, и часы, которые называют календарную
// дату, ведутся разными механизмами: первый — от кристалла, второй правится извне. Расхождение
// между ними за короткий промежуток есть физическое свойство ЭТОГО кристалла: он плывёт от
// температуры, питания и возраста, и никакая внешняя сторона это расхождение не воспроизводит.
// Берутся младшие биты, где шум, а не старшие, где ход.
fn quartz_drift(scale: u64) -> Vec<u8> {
    let units = calibrate(scale, lcg_work);
    let mut out = Vec::with_capacity(QUARTZ_SAMPLES * 8);
    for _ in 0..QUARTZ_SAMPLES {
        let mono = Instant::now();
        let wall = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_nanos() as u64).unwrap_or(0);
        // работа между двумя взглядами на часы: расхождение накапливается на ней, и её
        // столько, чтобы оно накопилось на K шагов
        lcg_work(units);
        let elapsed_mono = mono.elapsed().as_nanos() as u64;
        let wall_after = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_nanos() as u64).unwrap_or(0);
        let elapsed_wall = wall_after.wrapping_sub(wall);
        out.extend_from_slice(&elapsed_mono.wrapping_sub(elapsed_wall).to_le_bytes());
    }
    out
}

// Расписание. Соседний поток считает вперёд, пока этот делает короткую работу; сколько тот
// успел, решают планировщик, число занятых ядер и чужая нагрузка — то, чего не знает ни
// генератор системы, ни кристалл. Там, где второй поток не пускают вовсе, замеры совпадут, и
// источник честно окажется мёртвым.
fn scheduler_bytes(scale: u64) -> Vec<u8> {
    let counter = Arc::new(AtomicU64::new(0));
    let stop = Arc::new(AtomicU64::new(0));
    let worker = {
        let counter = Arc::clone(&counter);
        let stop = Arc::clone(&stop);
        thread::Builder::new()
            .name("mt-entropy-sched".into())
            .spawn(move || {
                while stop.load(Ordering::Relaxed) == 0 {
                    counter.fetch_add(1, Ordering::Relaxed);
                }
            })
            .ok()
    };
    // Замер — «сколько успел сосед, пока я работал», а не «успел ли сосед вообще родиться»:
    // в первую секунду запуска планировщик отдаёт квант новому потоку не сразу, и без этого
    // ожидания все замеры были бы нулями по вине момента, не машины. Ждать — не дольше 50 мс.
    let born = Instant::now();
    while counter.load(Ordering::Relaxed) == 0 && born.elapsed() < Duration::from_millis(50) {
        thread::yield_now();
    }
    let units = calibrate(scale, lcg_work);
    let mut out = Vec::with_capacity(SCHEDULER_SAMPLES * 8);
    let mut last = counter.load(Ordering::Relaxed);
    for _ in 0..SCHEDULER_SAMPLES {
        lcg_work(units);
        thread::yield_now();
        let now = counter.load(Ordering::Relaxed);
        out.extend_from_slice(&now.wrapping_sub(last).to_le_bytes());
        last = now;
    }
    stop.store(1, Ordering::Relaxed);
    if let Some(w) = worker {
        let _ = w.join();
    }
    out
}

// Таймер. У сна просят наименьший срок, а получают больше: превышение решают тиканье
// прерываний, состояние сна ядер и чужая работа. Берётся именно превышение — на сколько машина
// промахнулась мимо просьбы, — а не сам срок.
fn timer_bytes() -> Vec<u8> {
    const ASKED_NS: u64 = 1_000;
    let mut out = Vec::with_capacity(TIMER_SAMPLES * 8);
    for _ in 0..TIMER_SAMPLES {
        let start = Instant::now();
        thread::sleep(Duration::from_nanos(ASKED_NS));
        let got = start.elapsed().as_nanos() as u64;
        out.extend_from_slice(&got.wrapping_sub(ASKED_NS).to_le_bytes());
    }
    out
}

// Дешёвая проба того же кристалла: два взгляда на часы разной природы и ничего больше.
// Стоит наносекунды, поэтому её можно брать на КАЖДЫЙ выпуск быстрого источника — и тогда
// ни один выпуск не зависит только от зерна, взятого когда-то раньше.
pub(crate) fn quartz_tick() -> [u8; 24] {
    let mono = Instant::now();
    let wall = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_nanos() as u64).unwrap_or(0);
    let here = &mono as *const _ as u64;
    let mut out = [0u8; 24];
    out[..8].copy_from_slice(&(mono.elapsed().as_nanos() as u64).to_le_bytes());
    out[8..16].copy_from_slice(&wall.to_le_bytes());
    out[16..].copy_from_slice(&here.to_le_bytes());
    out
}

fn distinct_chunks(bytes: &[u8]) -> usize {
    let mut v: Vec<&[u8]> = bytes.chunks(8).collect();
    v.sort_unstable();
    v.dedup();
    v.len()
}

fn absorb(buf: &mut Vec<u8>, tag: u8, part: &[u8]) {
    buf.push(tag);
    buf.extend_from_slice(&(part.len() as u32).to_le_bytes());
    buf.extend_from_slice(part);
}

/// Мера одного источника: сколько замеров снято, сколько среди них различных, как часто
/// повторяется самый частый и признан ли источник живым. Ни одного байта источника здесь нет и
/// быть не может — только счёт, потому что человек вправе видеть, на чём стоит его личность, а
/// видеть сами замеры не вправе никто.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SourceMeasure {
    pub samples: u16,
    pub distinct: u16,
    pub max_repeat: u16,
    pub alive: bool,
}

impl SourceMeasure {
    fn of(bytes: &[u8], samples: usize) -> Self {
        SourceMeasure {
            samples: samples.min(u16::MAX as usize) as u16,
            distinct: distinct_chunks(bytes).min(u16::MAX as usize) as u16,
            max_repeat: max_repeat(bytes).min(u16::MAX as usize) as u16,
            alive: is_alive(bytes, samples),
        }
    }
}

/// Снять меры всех семи источников на ЭТОЙ машине. Порядок тот же, что у сложения: генератор
/// системы, инструкция процессора, дрожание исполнения, обращение к памяти, дрейф кварца,
/// расписание, промах таймера. Стоит столько же, сколько само рождение, и берётся по запросу.
pub fn measure_sources() -> [SourceMeasure; SourceReport::TOTAL] {
    let mut os = [0u8; 32];
    let os_ok = getrandom::getrandom(&mut os).is_ok();
    let jit = jitter_bytes(1);
    let mem = memory_bytes(1);
    let qz = quartz_drift(1);
    let sched = scheduler_bytes(1);
    let tim = timer_bytes();
    [
        SourceMeasure::of(if os_ok { &os[..] } else { &[] }, if os_ok { 4 } else { 0 }),
        SourceMeasure::of(&jit, JITTER_ROUNDS),
        SourceMeasure::of(&mem, MEMORY_ROUNDS),
        SourceMeasure::of(&qz, QUARTZ_SAMPLES),
        SourceMeasure::of(&sched, SCHEDULER_SAMPLES),
        SourceMeasure::of(&tim, TIMER_SAMPLES),
    ]
}

// ── Смотровое окно. Существует только под признаком проверочных векторов: в боевой сборке
// этих функций в библиотеке физически нет, и наружу не выходит ни одного байта источника.
// Наружу выходят только МЕРЫ — сколько байт дал источник, сколько среди них различного и
// признан ли он живым, — потому что человек вправе видеть, на чём стоит его личность.
#[cfg(any(test, feature = "vectors"))]
pub struct SourceFacts {
    pub name: &'static str,
    pub what: &'static str,
    pub bytes: usize,
    pub samples: usize,
    pub distinct_chunks: usize,
    pub distinct_bytes: usize,
    pub max_repeat: usize,
    pub alive: bool,
    pub alive_rule: &'static str,
}

#[cfg(any(test, feature = "vectors"))]
fn distinct_byte_values(bytes: &[u8]) -> usize {
    let mut seen = [false; 256];
    for b in bytes {
        seen[*b as usize] = true;
    }
    seen.iter().filter(|x| **x).count()
}

#[cfg(any(test, feature = "vectors"))]
fn facts(name: &'static str, what: &'static str, bytes: &[u8], samples: usize) -> SourceFacts {
    SourceFacts {
        name,
        what,
        bytes: bytes.len(),
        samples,
        distinct_chunks: distinct_chunks(bytes),
        distinct_bytes: distinct_byte_values(bytes),
        max_repeat: max_repeat(bytes),
        alive: is_alive(bytes, samples),
        alive_rule: "жив, когда самый частый замер занимает не больше половины и различных значений не меньше четырёх",
    }
}

/// Смотровое окно калибровки: доля моды и число различных у замера работы в `units` единиц —
/// кривая «шум от объёма работы» на этой машине. Только под признаком проверочных векторов.
#[cfg(any(test, feature = "vectors"))]
pub fn jitter_probe(units: u64, samples: usize) -> (usize, usize, u64) {
    let mut out = Vec::with_capacity(samples * 8);
    let mut total = 0u64;
    for _ in 0..samples {
        let start = Instant::now();
        lcg_work(units);
        let ns = start.elapsed().as_nanos() as u64;
        total += ns;
        out.extend_from_slice(&ns.to_le_bytes());
    }
    (distinct_chunks(&out), max_repeat(&out) * 100 / samples, total / samples as u64)
}

#[cfg(any(test, feature = "vectors"))]
pub fn survey() -> Vec<SourceFacts> {
    let mut os = [0u8; 32];
    let os_ok = getrandom::getrandom(&mut os).is_ok();
    vec![
        facts(
            "генератор системы",
            "getrandom ядра операционной системы; на телефоне — тот же, что стоит за SecRandomCopyBytes",
            if os_ok { &os[..] } else { &[] },
            if os_ok { 4 } else { 0 },
        ),
        facts(
            "дрожание исполнения",
            "256 замеров одной и той же короткой работы: кэш, предсказатель переходов, температура, соседние ядра",
            &jitter_bytes(1),
            JITTER_ROUNDS,
        ),
        facts(
            "обращение к памяти",
            "128 замеров хода по цепочке ссылок мимо ближних уровней кэша: состояние кэша, соседние ядра, контроллер памяти",
            &memory_bytes(1),
            MEMORY_ROUNDS,
        ),
        facts(
            "дрейф кварца",
            "64 расхождения между монотонными часами кристалла и календарными, правящимися извне",
            &quartz_drift(1),
            QUARTZ_SAMPLES,
        ),
        facts(
            "расписание",
            "32 замера того, сколько соседний поток успел насчитать: планировщик, число ядер, чужая нагрузка",
            &scheduler_bytes(1),
            SCHEDULER_SAMPLES,
        ),
        facts(
            "промах таймера",
            "32 превышения над наименьшим запрошенным сном: тиканье прерываний, сон ядер, чужая работа",
            &timer_bytes(),
            TIMER_SAMPLES,
        ),
    ]
}

static LAST_REPORT: Mutex<Option<SourceReport>> = Mutex::new(None);

/// Отчёт последнего сбора — чтобы дневник назвал, на чём стоит случайность этого прогона
/// и какие источники сочла мёртвыми, если счёл. Ни одного байта источника здесь нет.
pub fn last_report() -> Option<SourceReport> {
    *LAST_REPORT.lock().unwrap_or_else(|e| e.into_inner())
}

/// Сбор с доказательством: три окна, каждое вчетверо шире. Живая машина отвечает в первом;
/// «мертва» произносится только когда замеры не различаются ни в одном.
pub fn gather(os_block: &[u8]) -> (Zeroizing<[u8; 32]>, SourceReport) {
    let mut last = None;
    for scale in PROOF_SCALES {
        let (mixed, report) = gather_at(os_block, scale);
        let enough = report.count() >= crate::entropy::MIN_LIVE_SOURCES;
        last = Some((mixed, report));
        if enough {
            break;
        }
    }
    let (mixed, report) = last.expect("окон доказательства не меньше одного");
    *LAST_REPORT.lock().unwrap_or_else(|e| e.into_inner()) = Some(report);
    (mixed, report)
}

fn gather_at(os_block: &[u8], scale: u64) -> (Zeroizing<[u8; 32]>, SourceReport) {
    let jit = jitter_bytes(scale);
    let mem = memory_bytes(scale);
    let qz = quartz_drift(scale);
    let sched = scheduler_bytes(scale);
    let tim = timer_bytes();

    let mut buf: Vec<u8> =
        Vec::with_capacity(512 + jit.len() + mem.len() + qz.len() + sched.len() + tim.len());
    buf.extend_from_slice(domain::ENTROPY_MIX);
    buf.push(0x00);
    absorb(&mut buf, 1, os_block);
    absorb(&mut buf, 2, &jit);
    absorb(&mut buf, 3, &mem);
    absorb(&mut buf, 4, &qz);
    absorb(&mut buf, 5, &sched);
    absorb(&mut buf, 6, &tim);

    let mixed = sha256_raw(&buf);
    buf.zeroize();

    // Живость каждого источника считается по его собственным замерам — одним правилом,
    // одинаковым для всех семи. Ни один не объявляется живым по факту, что код отработал.
    let report = SourceReport {
        os_csprng: is_alive(os_block, os_block.len() / 8),
        jitter: is_alive(&jit, JITTER_ROUNDS),
        memory: is_alive(&mem, MEMORY_ROUNDS),
        quartz: is_alive(&qz, QUARTZ_SAMPLES),
        scheduler: is_alive(&sched, SCHEDULER_SAMPLES),
        timer: is_alive(&tim, TIMER_SAMPLES),
        scale,
        step_ns: clock_step_ns(),
    };
    (Zeroizing::new(mixed), report)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_constant_source_is_not_alive() {
        // Восемь одинаковых замеров: код отработал, источника нет.
        let dead = vec![0x11u8; 8 * 8];
        assert!(!is_alive(&dead, 8), "постоянные замеры не имеют права считаться живыми");
    }

    #[test]
    fn a_varying_source_is_alive() {
        let mut live = Vec::new();
        for i in 0..8u64 {
            live.extend_from_slice(&(i * 1_000_003).to_le_bytes());
        }
        assert!(is_alive(&live, 8));
    }

    #[test]
    fn a_dominating_value_is_not_alive() {
        // Восемь замеров, из них пять — одно и то же число: различных хватает, но угадать
        // замер наилучшей догадкой удаётся чаще, чем в половине случаев.
        let mut lopsided = Vec::new();
        for _ in 0..5 {
            lopsided.extend_from_slice(&7u64.to_le_bytes());
        }
        for i in 1..4u64 {
            lopsided.extend_from_slice(&(i * 1_000_003).to_le_bytes());
        }
        assert!(!is_alive(&lopsided, 8), "перекос к одному значению — источник мёртв");
    }

    #[test]
    fn two_values_alternating_is_not_alive() {
        let mut two = Vec::new();
        for i in 0..8u64 {
            two.extend_from_slice(&(i % 2).to_le_bytes());
        }
        assert!(!is_alive(&two, 8), "колебание между двумя числами источником не считается");
    }

    #[test]
    fn jitter_is_not_constant() {
        let a = jitter_bytes(1);
        assert!(is_alive(&a, JITTER_ROUNDS), "дрожание обязано различаться");
    }

    #[test]
    fn memory_is_not_constant() {
        let m = memory_bytes(1);
        assert!(is_alive(&m, MEMORY_ROUNDS), "обращение к памяти обязано различаться");
    }

    #[test]
    fn quartz_is_not_constant() {
        let q = quartz_drift(1);
        assert!(is_alive(&q, QUARTZ_SAMPLES), "кварц обязан различаться");
    }

    #[test]
    fn scheduler_is_not_constant() {
        let s = scheduler_bytes(1);
        assert!(is_alive(&s, SCHEDULER_SAMPLES), "расписание обязано различаться");
    }

    #[test]
    fn timer_is_not_constant() {
        let t = timer_bytes();
        assert!(is_alive(&t, TIMER_SAMPLES), "промах таймера обязан различаться");
    }

    // Синтетические замеры, квантованные шагом часов Apple (42 нс). Вектор ловит реализацию,
    // измеряющую ФИКСИРОВАННУЮ работу независимо от разрешения часов: на быстром кристалле её
    // замер укладывается в 900 нс ± 3 % — три различных значения, мода за половиной, «мёртв»;
    // замер, растянутый на 256 шагов (10,7 мкс ± 3 %), те же часы оставляют живым.
    fn quantised(base_ns: u64, samples: usize) -> Vec<u8> {
        let step = 42u64;
        let mut out = Vec::with_capacity(samples * 8);
        let mut x: u64 = 0x2545_F491_4F6C_DD1D;
        for _ in 0..samples {
            x ^= x << 13;
            x ^= x >> 7;
            x ^= x << 17;
            let spread = base_ns * 6 / 100 + 1;
            let noise = (x % spread) as i64 - (base_ns * 3 / 100) as i64;
            let v = ((base_ns as i64 + noise) as u64 / step) * step;
            out.extend_from_slice(&v.to_le_bytes());
        }
        out
    }

    #[test]
    fn a_fixed_work_sample_dies_on_a_fast_clock_and_a_calibrated_one_lives() {
        assert!(!is_alive(&quantised(900, JITTER_ROUNDS), JITTER_ROUNDS), "900 нс на шаге 42 нс обязаны быть мертвы");
        let long = TICKS_PER_SAMPLE * 42;
        assert!(is_alive(&quantised(long, JITTER_ROUNDS), JITTER_ROUNDS), "256 шагов обязаны быть живы");
    }

    #[test]
    fn calibration_spans_the_window() {
        let step = clock_step_ns();
        assert!(step >= 1 && step < 1_000_000, "шаг часов вне разумного: {step}");
        let units = calibrate(1, lcg_work);
        let start = Instant::now();
        lcg_work(units);
        let took = start.elapsed().as_nanos() as u64;
        assert!(took >= TICKS_PER_SAMPLE * step / 2, "калиброванная работа {units} заняла {took} нс при шаге {step}");
    }

    #[test]
    fn a_live_machine_answers_in_the_first_window() {
        let (_, r) = gather(&[0x5Au8; 32]);
        assert_eq!(r.scale, 1, "живая машина обязана отвечать в первом окне, отвечает в {}", r.scale);
        assert!(last_report().is_some());
    }

    #[test]
    fn six_sources_are_reported() {
        assert_eq!(SourceReport::TOTAL, 6);
        let (_, report) = gather(&[0u8; 32]);
        assert!(!report.os_csprng, "блок из одних нулей живым не считается");
        assert!(report.count() >= 3, "на этой машине живых источников меньше трёх");
    }

    #[test]
    fn a_dead_system_block_is_survived_by_the_rest() {
        let (a, _) = gather(&[0u8; 32]);
        let (b, _) = gather(&[0u8; 32]);
        assert_ne!(a[..], b[..], "два сбора с одним мёртвым блоком обязаны разойтись");
    }
}
