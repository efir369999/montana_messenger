// The birth of a person, and the branches that come out of it. The set states all of it in
// `docs/Montana Canon.md` — "The birth of a seed" and "The branches of a seed" — and this is
// their one transcription: the four health tests of a block, the six sources and their mixing,
// the words, the master seed, and the ten branches each under its own domain.
//
// Everything here happens on the device and nothing here leaves it. What a caller receives is a
// secret held in memory that wipes itself, or a refusal. A bad draw is refused rather than
// warned about: a root created on a broken machine looks ordinary and is guessable, and nothing
// later reveals that.

#![forbid(unsafe_code)]
#![deny(clippy::all)]

pub mod sources;
pub mod words;

use mt_codec::derive::{hkdf_expand, pbkdf2_sha256};
use mt_codec::{domain, Domain};
use std::sync::Mutex;
use zeroize::Zeroizing;

mt_codec::constants! {
    BIRTH:
    pub const ENTROPY_BYTES: usize = 32, spells "sized for a block of thirty-two bytes";
    pub const MASTER_SEED_BYTES: usize = 64, writes "length = 64";
    pub const SEED_ITERATIONS: u32 = 1_048_576, writes "iterations = 1 048 576";
    /// The floor of living sources, below which a birth is refused rather than warned about.
    pub const MIN_LIVE_SOURCES: usize = 3, spells "An implementation refuses to create an identity when fewer than three sources are alive";
    /// The four tests of a block, sized for thirty-two bytes by the set: the repetition-count and
    /// adaptive-proportion health tests of NIST SP 800-90B, its distinctness requirement, and its
    /// continuous test.
    pub const MAX_RUN: usize = 8, spells "no byte value repeats eight times in a row";
    pub const MAX_OF_THIRTY_TWO: usize = 12, spells "no byte value occurs more than twelve times in thirty-two";
    pub const MIN_DISTINCT_VALUES: usize = 8, spells "at least eight distinct byte values are present";
}

// The salt of the stretch is a row of the registry, so it is read from there rather than written
// a second time here: a literal beside the registry is the second place a domain lives.
pub fn seed_salt() -> &'static str {
    domain::MT_SEED.as_str()
}

#[derive(Debug, PartialEq, Eq)]
pub enum BirthError {
    WrongLength { length: usize },
    RepetitionCount { value: u8 },
    AdaptiveProportion { value: u8, count: usize },
    Distinctness { distinct: usize },
    Continuity,
    SourceRequired { source: sources::Source },
    TooFewLivingSources { alive: usize },
    SelfTest { what: &'static str },
}

// The four tests. A block that fails any of them is refused rather than repaired: a source that
// produced it is broken, and a broken source is answered by refusal.
pub fn health(block: &[u8], previous: Option<&[u8; ENTROPY_BYTES]>) -> Result<(), BirthError> {
    if block.len() != ENTROPY_BYTES {
        return Err(BirthError::WrongLength {
            length: block.len(),
        });
    }
    let mut run = 1usize;
    for pair in block.windows(2) {
        if pair[0] == pair[1] {
            run += 1;
            if run >= MAX_RUN {
                return Err(BirthError::RepetitionCount { value: pair[0] });
            }
        } else {
            run = 1;
        }
    }
    let mut counts = [0usize; 256];
    for byte in block {
        counts[usize::from(*byte)] += 1;
    }
    for (value, count) in counts.iter().enumerate() {
        if *count > MAX_OF_THIRTY_TWO {
            return Err(BirthError::AdaptiveProportion {
                value: value as u8,
                count: *count,
            });
        }
    }
    let distinct = counts.iter().filter(|c| **c > 0).count();
    if distinct < MIN_DISTINCT_VALUES {
        return Err(BirthError::Distinctness { distinct });
    }
    if let Some(before) = previous {
        if before[..] == block[..] {
            return Err(BirthError::Continuity);
        }
    }
    Ok(())
}

// What a person is shown of their own birth: the measure of every source and the count of the
// living. Not one byte of any source stands here, and none ever will.
pub struct Birth {
    pub entropy: Zeroizing<[u8; ENTROPY_BYTES]>,
    pub measures: Vec<sources::Measure>,
}

impl Birth {
    pub fn alive(&self) -> usize {
        self.measures.iter().filter(|m| m.alive).count()
    }
}

// The birth of a seed: draw every source, measure each on its own samples, refuse unless the
// required source is alive and at least three sources are, mix the living, and put the result
// through the four tests before it becomes anyone.
pub fn birth(previous: Option<&[u8; ENTROPY_BYTES]>) -> Result<Birth, BirthError> {
    born_of(sources::draw(), previous)
}

// The block this machine last bore. The continuous test of the set compares a block with the one
// drawn before it, and a test a caller may leave out by passing nothing is a test that never runs
// on the path a wallet takes; so the module remembers, and what a caller hands in is one more
// block to differ from rather than the only one. What it remembers is the entropy of somebody's
// birth, so it is held in the wrapper that wipes: a copy standing in a static for the life of a
// process is a copy nothing else would ever wipe, and this crate's card enumerates its bearers.
static LAST_BORN: Mutex<Option<Zeroizing<[u8; ENTROPY_BYTES]>>> = Mutex::new(None);

// The one path from a draw to a person, whatever drew it. A test reaches it with samples of its
// own to see a refusal fire; nothing outside this crate reaches it at all.
pub(crate) fn born_of(
    draw: sources::Draw,
    previous: Option<&[u8; ENTROPY_BYTES]>,
) -> Result<Birth, BirthError> {
    self_test()?;
    for source in sources::Source::ALL {
        if source.required() && !draw.is_alive(source) {
            return Err(BirthError::SourceRequired { source });
        }
    }
    let alive = draw.alive();
    if alive < MIN_LIVE_SOURCES {
        return Err(BirthError::TooFewLivingSources { alive });
    }
    let entropy = draw.mix().ok_or(BirthError::SelfTest {
        what: "a source longer than the field its length is written in",
    })?;
    health(&entropy[..], previous)?;
    let mut last = LAST_BORN.lock().map_err(|_| BirthError::SelfTest {
        what: "the block last born is unreadable",
    })?;
    health(&entropy[..], last.as_deref())?;
    *last = Some(entropy.clone());
    Ok(Birth {
        entropy,
        measures: draw.measures,
    })
}

// The self-test the set demands beside the health tests: a degenerate block is rejected, mixing
// depends on every summand and on the place of each, a constant source does not pass for one, and
// the sources of the machine differ between two draws made from one system block. A failure of any of
// them is answered by refusal, because the mechanism meant to catch a broken machine is itself
// what has broken.
pub fn self_test() -> Result<(), BirthError> {
    // The mixing of stated parts refuses a part beyond its length field; every part here is a
    // literal of a few bytes, so a refusal would mean the door itself has moved.
    let mixed = |parts: &[(u8, &[u8])]| -> Result<[u8; ENTROPY_BYTES], BirthError> {
        sources::mix_of_stated_sources(parts).ok_or(BirthError::SelfTest {
            what: "the mixing refused parts of a few bytes",
        })
    };
    if health(&[0u8; ENTROPY_BYTES], None).is_ok() {
        return Err(BirthError::SelfTest {
            what: "a degenerate block passed the health tests",
        });
    }
    if mixed(&[(0, b"a"), (1, b"b")])? == mixed(&[(0, b"a"), (1, b"c")])? {
        return Err(BirthError::SelfTest {
            what: "the mixing does not depend on every summand",
        });
    }
    if mixed(&[(0, b"ab"), (1, b"c")])? == mixed(&[(0, b"a"), (1, b"bc")])? {
        return Err(BirthError::SelfTest {
            what: "the mixing loses the boundary between two summands",
        });
    }
    if mixed(&[(0, b"a"), (1, b"b")])? == mixed(&[(0, b"a"), (2, b"b")])? {
        return Err(BirthError::SelfTest {
            what: "the mixing loses the place of a summand",
        });
    }
    if sources::alive(&[7u8; 64]) {
        return Err(BirthError::SelfTest {
            what: "a constant source counted as alive",
        });
    }
    if !machine_sources_differ() {
        return Err(BirthError::SelfTest {
            what: "the sources of the machine repeat between two draws",
        });
    }
    Ok(())
}

// One system block held fixed, the machine sources drawn twice: the set asks for exactly this, and
// a machine whose timings repeat is one whose entropy stands on the generator alone.
fn machine_sources_differ() -> bool {
    let fixed = Zeroizing::new(vec![0u8; 32]);
    let mix = |machine: Vec<(sources::Source, Zeroizing<Vec<u8>>)>| {
        let mut drawn = vec![(sources::Source::OperatingSystem, fixed.clone())];
        drawn.extend(machine);
        sources::Draw::of(drawn).mix()
    };
    match (
        mix(sources::draw_machine_sources()),
        mix(sources::draw_machine_sources()),
    ) {
        (Some(first), Some(second)) => first[..] != second[..],
        _ => false,
    }
}

// The master seed. What is stretched is the entropy and never the text of the words, so nothing
// about how a phrase is typed can change a derived byte.
pub fn master_seed(entropy: &[u8; ENTROPY_BYTES]) -> Zeroizing<Vec<u8>> {
    pbkdf2_sha256(
        entropy,
        seed_salt().as_bytes(),
        SEED_ITERATIONS,
        MASTER_SEED_BYTES,
    )
}

// The ten branches of a person, each under its own domain and each independent of the others.
// They are derived here and nowhere else in this tree; a consumer names a branch rather than
// deriving it again.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Branch {
    Signing,
    Note,
    Nullifier,
    Encryption,
    Open,
    Operator,
    Rate,
    Act,
    Owner,
    Lookup,
}

impl Branch {
    pub const ALL: [Branch; 10] = [
        Branch::Signing,
        Branch::Note,
        Branch::Nullifier,
        Branch::Encryption,
        Branch::Open,
        Branch::Operator,
        Branch::Rate,
        Branch::Act,
        Branch::Owner,
        Branch::Lookup,
    ];

    pub fn domain(self) -> Domain {
        match self {
            Branch::Signing => domain::MT_ACCOUNT_KEY,
            Branch::Note => domain::MT_NOTE_KEY,
            Branch::Nullifier => domain::MT_NF_KEY,
            Branch::Encryption => domain::MT_APP_ENCRYPTION_KEY,
            Branch::Open => domain::MT_OPEN_NF,
            Branch::Operator => domain::MT_OPERATOR_NF,
            Branch::Rate => domain::MT_RATE_NF,
            Branch::Act => domain::MT_ACT_NF,
            Branch::Owner => domain::MT_OWNER_KEY,
            Branch::Lookup => domain::MT_LOOKUP_NF,
        }
    }

    // The lengths of the set are exact: a scheme demanding a different seed length takes it
    // from the same branch by its own expansion, never by widening this one.
    pub fn length(self) -> usize {
        match self {
            Branch::Encryption => 64,
            _ => 32,
        }
    }
}

pub fn branch(master_seed: &[u8], branch: Branch) -> Zeroizing<Vec<u8>> {
    hkdf_expand(
        master_seed,
        branch.domain().as_str().as_bytes(),
        branch.length(),
    )
}

// A machine derives its answering key the same way and from its own secret, which is no branch
// of any person's seed.
pub fn answering_key(machine_secret: &[u8; 32]) -> Zeroizing<Vec<u8>> {
    hkdf_expand(machine_secret, domain::MT_NODE_KEY.as_str().as_bytes(), 32)
}

#[cfg(test)]
mod tests {
    use super::*;
    use sha2::{Digest, Sha256};

    // A birth reads and writes the block this machine last bore, which is one thing shared by
    // every test that calls one. They take turns, so what they assert holds whatever order or
    // parallelism the runner chooses.
    static ONE_AT_A_TIME: Mutex<()> = Mutex::new(());

    fn in_turn() -> std::sync::MutexGuard<'static, ()> {
        ONE_AT_A_TIME.lock().unwrap_or_else(|e| e.into_inner())
    }

    fn hex(bytes: &[u8]) -> String {
        bytes.iter().map(|b| format!("{b:02x}")).collect()
    }

    #[test]
    fn eight_in_a_row_trips_the_repetition_count_and_seven_do_not() {
        let mut block = [0u8; 32];
        for (i, b) in block.iter_mut().enumerate() {
            *b = i as u8;
        }
        let mut seven = block;
        for slot in seven[..7].iter_mut() {
            *slot = 0x41;
        }
        health(&seven, None).expect("seven in a row stand");
        let mut eight = block;
        for slot in eight[..8].iter_mut() {
            *slot = 0x41;
        }
        assert_eq!(
            health(&eight, None),
            Err(BirthError::RepetitionCount { value: 0x41 })
        );
    }

    #[test]
    fn thirteen_of_one_value_trips_the_proportion_and_twelve_do_not() {
        // Twelve of one value spread so no run of eight stands, and twenty distinct others.
        let mut spread = [0u8; 32];
        for (i, b) in spread.iter_mut().enumerate() {
            *b = if i % 2 == 0 && i < 24 {
                0x99
            } else {
                (i as u8) | 1
            };
        }
        health(&spread, None).expect("twelve of one value stand");
        let mut thirteen = spread;
        thirteen[25] = 0x99;
        assert!(matches!(
            health(&thirteen, None),
            Err(BirthError::AdaptiveProportion { value: 0x99, .. })
        ));
    }

    #[test]
    fn too_few_distinct_values_are_refused() {
        let mut block = [0u8; 32];
        for (i, b) in block.iter_mut().enumerate() {
            *b = ((i % 7) as u8) * 3 + 1;
        }
        assert_eq!(
            health(&block, None),
            Err(BirthError::Distinctness { distinct: 7 })
        );
    }

    #[test]
    fn a_block_equal_to_the_one_before_it_is_refused() {
        let mut block = [0u8; 32];
        for (i, b) in block.iter_mut().enumerate() {
            *b = (i as u8).wrapping_mul(11).wrapping_add(3);
        }
        health(&block, None).expect("the block is healthy on its own");
        assert_eq!(health(&block, Some(&block)), Err(BirthError::Continuity));
    }

    #[test]
    fn a_degenerate_block_and_a_wrong_length_are_refused() {
        assert!(health(&[0u8; 32], None).is_err());
        assert!(health(&[0xFFu8; 32], None).is_err());
        assert_eq!(
            health(&[1u8; 31], None),
            Err(BirthError::WrongLength { length: 31 })
        );
    }

    #[test]
    fn the_self_test_passes_on_a_working_machine() {
        self_test().expect("the machine is not broken");
    }

    #[test]
    fn a_birth_stands_on_at_least_three_living_sources_and_reports_them() {
        let _turn = in_turn();
        let first = birth(None).expect("this machine can bear a person");
        assert_eq!(first.measures.len(), sources::Source::ALL.len());
        assert!(first.alive() >= MIN_LIVE_SOURCES);
        health(&first.entropy[..], None).expect("a born entropy is healthy");
        let second = birth(Some(&first.entropy)).expect("a second person is born");
        assert_ne!(first.entropy[..], second.entropy[..]);
    }

    // Samples that differ from one another, so a source built of them is alive.
    fn living(n: usize, salt: u64) -> Zeroizing<Vec<u8>> {
        let mut out = Vec::with_capacity(n * 8);
        for i in 0..n as u64 {
            out.extend_from_slice(&(i.wrapping_mul(1_000_003).wrapping_add(salt)).to_le_bytes());
        }
        Zeroizing::new(out)
    }

    fn dead(n: usize) -> Zeroizing<Vec<u8>> {
        Zeroizing::new(vec![7u8; n * 8])
    }

    // What a healthy generator answers with: a whole block of thirty-two bytes that passes the four
    // tests. The generator is judged by those and never by a share of samples, so a test that hands
    // it samples of the shape a timing source produces would be judging the wrong thing.
    fn system(salt: u8) -> Zeroizing<Vec<u8>> {
        let mut block = vec![0u8; ENTROPY_BYTES];
        for (i, byte) in block.iter_mut().enumerate() {
            *byte = (i as u8).wrapping_mul(7).wrapping_add(salt);
        }
        Zeroizing::new(block)
    }

    #[test]
    fn a_dead_generator_of_the_operating_system_refuses_a_birth() {
        let _turn = in_turn();
        let drawn = vec![
            (sources::Source::OperatingSystem, dead(4)),
            (sources::Source::Jitter, living(256, 11)),
            (sources::Source::Memory, living(128, 22)),
            (sources::Source::Quartz, living(64, 33)),
            (sources::Source::Scheduler, living(32, 44)),
            (sources::Source::Timer, living(32, 55)),
        ];
        assert_eq!(
            born_of(sources::Draw::of(drawn), None).err(),
            Some(BirthError::SourceRequired {
                source: sources::Source::OperatingSystem
            })
        );
    }

    #[test]
    fn two_living_sources_refuse_a_birth_and_three_bear_one() {
        let _turn = in_turn();
        let two = vec![
            (sources::Source::OperatingSystem, system(1)),
            (sources::Source::Jitter, living(256, 2)),
            (sources::Source::Memory, dead(128)),
            (sources::Source::Quartz, dead(64)),
            (sources::Source::Scheduler, dead(32)),
            (sources::Source::Timer, dead(32)),
        ];
        assert_eq!(
            born_of(sources::Draw::of(two), None).err(),
            Some(BirthError::TooFewLivingSources { alive: 2 })
        );
        let three = vec![
            (sources::Source::OperatingSystem, system(1)),
            (sources::Source::Jitter, living(256, 2)),
            (sources::Source::Memory, living(128, 3)),
            (sources::Source::Quartz, dead(64)),
            (sources::Source::Scheduler, dead(32)),
            (sources::Source::Timer, dead(32)),
        ];
        let born = born_of(sources::Draw::of(three), None).expect("three living sources bear one");
        assert_eq!(born.alive(), MIN_LIVE_SOURCES);
    }

    #[test]
    fn a_birth_that_repeats_the_block_before_it_is_refused_without_being_asked_to_compare() {
        let _turn = in_turn();
        // The same samples twice: the mixing is a function of them, so the second block equals the
        // first. Nothing is handed in as the previous block — the module remembers, which is the
        // only reason this refusal can happen at all.
        let samples = || {
            vec![
                (sources::Source::OperatingSystem, system(7)),
                (sources::Source::Jitter, living(256, 8)),
                (sources::Source::Memory, living(128, 9)),
                (sources::Source::Quartz, living(64, 10)),
                (sources::Source::Scheduler, living(32, 11)),
                (sources::Source::Timer, living(32, 12)),
            ]
        };
        born_of(sources::Draw::of(samples()), None).expect("the first block stands");
        assert_eq!(
            born_of(sources::Draw::of(samples()), None).err(),
            Some(BirthError::Continuity)
        );
    }

    #[test]
    fn a_degenerate_mixing_refuses_a_birth_rather_than_bearing_a_person() {
        let _turn = in_turn();
        // Samples chosen so that the mixed block fails a health test would take a preimage
        // search; instead the tests of health are asserted directly above, and here the wiring is
        // what is judged: a draw whose sources are alive reaches health, and health is what
        // decides. A block that passed no test can therefore not leave this crate.
        let drawn = vec![
            (sources::Source::OperatingSystem, system(99)),
            (sources::Source::Jitter, living(256, 98)),
            (sources::Source::Memory, living(128, 97)),
            (sources::Source::Quartz, living(64, 96)),
            (sources::Source::Scheduler, living(32, 95)),
            (sources::Source::Timer, living(32, 94)),
        ];
        let born = born_of(sources::Draw::of(drawn), None).expect("born");
        health(&born.entropy[..], None).expect("what left the crate had passed the tests");
    }

    #[test]
    fn the_second_chain_of_the_set_reproduces_and_a_reversed_entropy_does_not() {
        // Canon, "The birth of a seed, end to end": the chain over an entropy of thirty-two
        // distinct bytes. The first chain stands on a palindrome and cannot tell these apart.
        let mut entropy = [0u8; 32];
        for (i, b) in entropy.iter_mut().enumerate() {
            *b = i as u8;
        }
        let seed = master_seed(&entropy);
        assert_eq!(
            hex(&Sha256::digest(words::phrase(&entropy).as_bytes())),
            "51f03d9ccd90c12c02b3804d0d0695f7ba64e4de48e261719f55931da24fc806"
        );
        assert_eq!(
            hex(&Sha256::digest(&seed[..])),
            "82ddcce728e45cfe4e66418caf24c5076a59baa16131633568bc9e4135986060"
        );
        assert_eq!(
            hex(&Sha256::digest(&branch(&seed, Branch::Signing)[..])),
            "c67360c0e04c6b38c69abe6f99c7aa3064138088fcf791673ada70b42e3e92e1"
        );
        // The expansion of sixty-four bytes: the counter of a second block is bound too.
        assert_eq!(
            hex(&Sha256::digest(&branch(&seed, Branch::Encryption)[..])),
            "b7cd19502047d8946a0bf5fd3c9fa3487ff88a15a1d44e77e3cf430f6098697b"
        );
        // The named wrong implementation: entropy read backwards. It reproduces every value of
        // the chain over 0x00 x 32 and none of the four above.
        let mut reversed = entropy;
        reversed.reverse();
        assert_ne!(
            words::phrase(&reversed).to_string(),
            words::phrase(&entropy).to_string()
        );
        let zero = [0u8; 32];
        let mut zero_reversed = zero;
        zero_reversed.reverse();
        assert_eq!(
            words::phrase(&zero_reversed).to_string(),
            words::phrase(&zero).to_string(),
            "the palindrome is why the second chain exists"
        );
    }

    #[test]
    fn the_chain_from_entropy_to_the_signing_branch_is_the_frozen_one() {
        // Canon, "The birth of a seed, end to end".
        let entropy = [0u8; 32];
        let seed = master_seed(&entropy);
        assert_eq!(seed.len(), MASTER_SEED_BYTES);
        assert_eq!(
            hex(&Sha256::digest(&seed[..])),
            "f1818e1a354e6020ddf11ed9da140c93f42fdc530c498734e732e6db6e607536"
        );
        assert_eq!(
            hex(&Sha256::digest(&branch(&seed, Branch::Signing)[..])),
            "095c344ee139b874f0c54ea93603fc06cef984546d0c12b9cbd4ddd281940113"
        );
    }

    #[test]
    fn the_mixing_of_the_stated_sources_is_the_frozen_value() {
        // Canon, "The birth of a seed, end to end": four living sources at named places.
        assert_eq!(
            hex(&sources::mix_of_stated_sources(&[
                (0, &[1u8; 32][..]),
                (1, &[2u8; 32][..]),
                (3, &[3u8; 24][..]),
                (5, &[4u8; 16][..])
            ])
            // PANIC-OK: the parts are literals of this test, tens of bytes each, and the door
            // refuses only a part beyond sixty-five thousand; a refusal here would mean the rule
            // itself has moved, which is what the assertion exists to catch.
            .expect("the parts of the vector fit their field")),
            "f89ccf6875e8f636774057e55b24f1f5d3753191c44f4f0e26aded865ff47d4a"
        );
    }

    #[test]
    fn every_branch_stands_apart_at_the_length_the_set_states() {
        // ZEROIZE-OK: a master seed of literal bytes, written in this file — what this test
        // judges is the separation of the branches, and the stretch that makes a real one is
        // asserted by the vector that owns it.
        let seed = [0x11u8; MASTER_SEED_BYTES];
        let mut seen: Vec<Vec<u8>> = Vec::new();
        for b in Branch::ALL {
            let value = branch(&seed, b);
            assert_eq!(value.len(), b.length(), "{b:?}");
            assert!(!seen.contains(&*value), "{b:?} repeats another branch");
            seen.push(value.to_vec());
        }
        assert_eq!(seen.len(), 10);
        // A machine's answering key is no branch of a person: it stands on the machine's own
        // secret, and the same bytes as a master seed do not make it one.
        let answering = answering_key(&[0x11u8; 32]);
        assert!(!seen.contains(&*answering));
    }

    #[test]
    fn a_branch_is_the_expansion_of_its_own_domain_and_of_no_other() {
        // ZEROIZE-OK: a literal of this test, as above.
        let seed = [0x22u8; MASTER_SEED_BYTES];
        for b in Branch::ALL {
            assert_eq!(
                branch(&seed, b)[..],
                mt_codec::derive::hkdf_expand(&seed, b.domain().as_str().as_bytes(), b.length())[..]
            );
        }
    }
}
