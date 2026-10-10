// The byte layer of Montana: the domain-separated hash primitive, the registry of separators,
// the canonical serialization of the type classes, the canonical orders, and the auxiliary
// compositions over SHA-256 the set admits beside them — HMAC, HKDF-Expand, PBKDF2. The set
// states all of it in `docs/Montana Canon.md` — "Primitives", "The hash primitive", "The
// registry of domain separators", "Canonical serialization" — and this is their one
// transcription. The conformance harness parses the set and refuses a build in which the two
// disagree.

#![forbid(unsafe_code)]
#![deny(clippy::all)]

use sha2::{Digest, Sha256};

// A domain is constructable only as a row of the registry below, so a literal separator cannot
// enter a hash from anywhere else in the tree. The mint is of the crate and the declaration is
// the one place that calls it. The alphabet of a name is not decoration: the NUL
// after a domain separates because no name can hold a zero, so no name is the opening of another
// and no two classes share a preimage. That property is therefore held by the type and checked
// where a name is written — a byte outside the alphabet fails the build rather than a test, and a
// test can be deleted while a compiler cannot.
mod sealed {
    #[derive(Clone, Copy, PartialEq, Eq, Debug)]
    pub struct Domain(&'static str);

    impl Domain {
        // Of the crate and no wider: a row of the registry below is the only place a domain is
        // minted, so a name that stands in no row cannot enter a hash from anywhere in the tree.
        pub(crate) const fn of(name: &'static str) -> Self {
            let bytes = name.as_bytes();
            assert!(
                bytes.len() > 3,
                "a name of the registry opens with mt- and carries a name after it"
            );
            assert!(
                bytes[0] == b'm' && bytes[1] == b't' && bytes[2] == b'-',
                "a name of the registry opens with mt-"
            );
            let mut i = 0;
            while i < bytes.len() {
                let byte = bytes[i];
                assert!(
                    byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'-',
                    "a name of the registry is lowercase ascii, a digit or a hyphen, so that the                      NUL after it separates"
                );
                i += 1;
            }
            Self(name)
        }

        pub const fn as_str(self) -> &'static str {
            self.0
        }
    }
}

pub use sealed::Domain;

// A part of a preimage, whose width its own type fixes. Nothing stands between two parts, so the
// concatenation reads one way only because every part is of a width known before it is read — and
// that is a property of the types here rather than a rule somebody keeps.
#[derive(Clone, Copy)]
pub struct Part<'a>(&'a [u8]);

impl<'a> Part<'a> {
    pub const fn of<const N: usize>(bytes: &'a [u8; N]) -> Self {
        Self(bytes)
    }
}

#[derive(Debug, PartialEq, Eq)]
pub enum PartError {
    // A value offered at a width the set does not give it.
    Width { expected: usize, found: usize },
    // A value longer than the count that would precede it.
    TooLong { found: usize },
}

// The preimage of a class, taken part by part. Three doors admit a value and there is no fourth:
// a width its own type carries, a width a row of the set fixes, and a length written before the
// bytes. A value whose width nothing gives ends the preimage instead of standing inside it — the
// door for it answers with the digest rather than with the builder, so nothing can follow it and
// no reader has to guess where it stopped.
pub struct Preimage {
    hasher: Sha256,
}

impl Preimage {
    pub fn under(domain: Domain) -> Self {
        #[cfg(feature = "witness")]
        crate::witness::note(domain.as_str());
        let mut hasher = Sha256::new();
        hasher.update(domain.as_str().as_bytes());
        hasher.update([0u8]);
        Self { hasher }
    }

    pub fn fixed<const N: usize>(mut self, part: &[u8; N]) -> Self {
        self.hasher.update(part);
        self
    }

    // A run of parts of one width: the count is what the length of the preimage gives, since
    // every element is of the same width and what follows the run is of a width of its own.
    pub fn run<const N: usize>(mut self, parts: &[[u8; N]]) -> Self {
        for part in parts {
            self.hasher.update(part);
        }
        self
    }

    // A value of a width the set fixes elsewhere than in a type — a block of the Decree, a scope
    // a layout gives — offered with that width, and refused where the two disagree.
    pub fn declared(mut self, bytes: &[u8], width: usize) -> Result<Self, PartError> {
        if bytes.len() != width {
            return Err(PartError::Width {
                expected: width,
                found: bytes.len(),
            });
        }
        self.hasher.update(bytes);
        Ok(self)
    }

    // A value of no fixed width, standing after the count of its bytes, so that what follows it
    // begins where the count says and nowhere else.
    pub fn counted(mut self, bytes: &[u8]) -> Result<Self, PartError> {
        let length =
            u16::try_from(bytes.len()).map_err(|_| PartError::TooLong { found: bytes.len() })?;
        self.hasher.update(length.to_le_bytes());
        self.hasher.update(bytes);
        Ok(self)
    }

    // The one value that is the whole of the body: it ends the preimage, so nothing can be split
    // from it and nothing can follow it.
    pub fn whole(mut self, body: &[u8]) -> [u8; 32] {
        self.hasher.update(body);
        self.finish()
    }

    pub fn finish(self) -> [u8; 32] {
        self.hasher.finalize().into()
    }
}

pub fn hash(domain: Domain, parts: &[Part<'_>]) -> [u8; 32] {
    let mut preimage = Preimage::under(domain);
    for part in parts {
        preimage.hasher.update(part.0);
    }
    preimage.finish()
}

// The preimage of a class over one body: there being one part, nothing can be split from it, and
// its length is the length of the preimage.
pub fn hash_of_one(domain: Domain, body: &[u8]) -> [u8; 32] {
    Preimage::under(domain).whole(body)
}

// Which domains a run of this tree has actually taken a preimage under. A rule of the set that
// no run ever exercises is a rule nothing compares, and the registry cannot say so about itself:
// it holds names, and a name is not a comparison. The recorder is of the gate alone — it stands
// behind a feature the build script of the harness turns on for its own graph, so a node carries
// none of it.
#[cfg(feature = "witness")]
pub mod witness {
    use std::cell::RefCell;
    use std::collections::BTreeSet;

    thread_local! {
        static TAKEN: RefCell<BTreeSet<&'static str>> = const { RefCell::new(BTreeSet::new()) };
    }

    pub(crate) fn note(name: &'static str) {
        TAKEN.with(|taken| {
            taken.borrow_mut().insert(name);
        });
    }

    pub fn taken() -> Vec<&'static str> {
        TAKEN.with(|taken| taken.borrow().iter().copied().collect())
    }

    pub fn forget() {
        TAKEN.with(|taken| taken.borrow_mut().clear());
    }
}

pub mod wide;

// The registry, written once. A row gives a name to a domain and puts it in the array the gate
// compares, so a name minted without a row cannot exist and a row without a mint cannot either.
// That no two rows carry one name is refused where the rows are written: the check runs in a
// constant, so a repeat fails the build rather than a test — and the separation of every class
// rests on it.
macro_rules! registry {
    ($($name:ident => $text:literal,)+) => {
        pub mod domain {
            use super::Domain;

            $(pub const $name: Domain = Domain::of($text);)+

            pub const REGISTRY: &[Domain] = &[$($name,)+];

            const NAMES: &[&str] = &[$($text,)+];

            const _: () = {
                assert!(
                    super::no_two_names_repeat(NAMES),
                    "two rows of the registry carry one name"
                );
            };

            pub fn by_name(name: &str) -> Option<Domain> {
                REGISTRY.iter().copied().find(|d| d.as_str() == name)
            }
        }
    };
}

const fn same_text(a: &str, b: &str) -> bool {
    let (a, b) = (a.as_bytes(), b.as_bytes());
    if a.len() != b.len() {
        return false;
    }
    let mut i = 0;
    while i < a.len() {
        if a[i] != b[i] {
            return false;
        }
        i += 1;
    }
    true
}

const fn no_two_names_repeat(names: &[&str]) -> bool {
    let mut i = 0;
    while i < names.len() {
        let mut j = i + 1;
        while j < names.len() {
            if same_text(names[i], names[j]) {
                return false;
            }
            j += 1;
        }
        i += 1;
    }
    true
}

registry! {
        MT_OP => "mt-op",
        MT_NODEREG => "mt-nodereg",
        MT_PROPOSAL => "mt-proposal",
        MT_WINDOW_PROOF => "mt-window-proof",
        MT_SAFETY => "mt-safety",
        MT_NODE_COMMIT => "mt-node-commit",
        MT_WEIGHT => "mt-weight",
        MT_MERKLE_LEAF => "mt-merkle-leaf",
        MT_MERKLE_NODE => "mt-merkle-node",
        MT_TICKET => "mt-ticket",
        MT_ROUND_ATT => "mt-round-att",
        MT_BEACON => "mt-beacon",
        MT_FRAME => "mt-frame",
        MT_ROUND_NF => "mt-round-nf",
        MT_RUNNER_KEY => "mt-runner-key",
        MT_BC_AGGREGATE => "mt-bc-aggregate",
        MT_BC_AGGREGATE_EMPTY => "mt-bc-aggregate-empty",
        MT_SELECTION => "mt-selection",
        MT_NODEREG_SORT => "mt-nodereg-sort",
        MT_CASCADE => "mt-cascade",
        MT_GENESIS_STATE => "mt-genesis-state",
        MT_SEED => "mt-seed",
        // The label is frozen on the wire; the branch it names is the signing branch of a person.
        MT_SIGNING_KEY => "mt-account-key",
        MT_NODE_KEY => "mt-node-key",
        MT_NOTE_KEY => "mt-note-key",
        MT_NF_KEY => "mt-nf-key",
        MT_KEY_HALVES => "mt-key-halves",
        MT_NOTE_PK => "mt-note-pk",
        MT_FABRIC_LEAF => "mt-fabric-leaf",
        MT_FABRIC_NODE => "mt-fabric-node",
        MT_NOTE_CM => "mt-note-cm",
        MT_NOTE_NF => "mt-note-nf",
        MT_RATE_NF => "mt-rate-nf",
        MT_ACT_NF => "mt-act-nf",
        MT_RECORD_NF => "mt-record-nf",
        MT_CREDIT_NF => "mt-credit-nf",
        MT_ADMITTED_LEAF => "mt-admitted-leaf",
        MT_ADMITTED_NODE => "mt-admitted-node",
        MT_OPERATOR_NF => "mt-operator-nf",
        MT_PART_NF => "mt-part-nf",
        MT_OPEN_NF => "mt-open-nf",
        MT_NOISE_PQ_V1_MASTER => "mt-noise-pq-v1-master",
        MT_NOISE_PQ_V1_I2R => "mt-noise-pq-v1-i2r",
        MT_NOISE_PQ_V1_R2I => "mt-noise-pq-v1-r2i",
        MT_NOISE_PQ_V1_SIG_R => "mt-noise-pq-v1-sig-r",
        MT_NOISE_PQ_V1_SIG_I => "mt-noise-pq-v1-sig-i",
        MT_NOISE_PQ_V1_TRANSCRIPT => "mt-noise-pq-v1-transcript",
        MT_LOOKUP_NF => "mt-lookup-nf",
        MT_CHANNEL_SLOT => "mt-channel-slot",
        MT_CHANNEL_KEY => "mt-channel-key",
        MT_CHANNEL_HEAD => "mt-channel-head",
        MT_CHANNEL_POINT => "mt-channel-point",
        MT_NAME_COMMIT_OP => "mt-name-commit-op",
        MT_NAME_REVEAL_OP => "mt-name-reveal-op",
        MT_NAME_RENEW_OP => "mt-name-renew-op",
        MT_CHANNEL_COMMIT_OP => "mt-channel-commit-op",
        MT_CHANNEL_REVEAL_OP => "mt-channel-reveal-op",
        MT_CHANNEL_PUB_OP => "mt-channel-pub-op",
        MT_PART_KEY => "mt-part-key",
        MT_ENTROPY_MIX => "mt-entropy-mix",
        MT_NAME_SLOT => "mt-name-slot",
        MT_NAME_OWN => "mt-name-own",
        MT_NAME_CHAIN => "mt-name-chain",
        MT_NAME_COMMIT => "mt-name-commit",
        MT_OWNER_KEY => "mt-owner-key",
        MT_ENTRY => "mt-entry",
        MT_NAME_CONTACT_KEY => "mt-name-contact-key",
        MT_NAME_TAG => "mt-name-tag",
        MT_NAME_FIRST => "mt-name-first",
        MT_TAG => "mt-tag",
        MT_STEP => "mt-step",
        MT_SLOT => "mt-slot",
        MT_RELAY_SEAL => "mt-relay-seal",
        MT_RELAY_PATH => "mt-relay-path",
        MT_STANDING_MATRIX => "mt-standing-matrix",
        MT_FOLD_WORK => "mt-fold-work",
        MT_FOLD_NODE => "mt-fold-node",
        MT_PIPE_KEY => "mt-pipe-key",
        MT_COLLECT => "mt-collect",
        MT_ROUND_POINT => "mt-round-point",
        MT_WINDOW_POINT => "mt-window-point",
        MT_NOTICE_POINT => "mt-notice-point",
        MT_DELIVERY => "mt-delivery",
        MT_PROOF_TRANSCRIPT => "mt-proof-transcript",
        MT_PROOF_QUERY => "mt-proof-query",
        MT_APP => "mt-app",
        MT_APP_ENCRYPTION_KEY => "mt-app-encryption-key",
        MT_PROOF_AIR => "mt-proof-air",
        MT_PROOF_LEAF => "mt-proof-leaf",
        MT_PROOF_NODE => "mt-proof-node",
        MT_NOTE_LEAF => "mt-note-leaf",
        MT_NOTE_NODE => "mt-note-node",
        MT_RECORD_LEAF => "mt-record-leaf",
        MT_RECORD_NODE => "mt-record-node",
        MT_HORIZON_LEAF => "mt-horizon-leaf",
        MT_HORIZON_NODE => "mt-horizon-node",
}

// Where a number of this tree stands in the set, and what it is compared against. A constant is
// declared together with its place — one declaration, as a domain is declared together with its
// row — so a number written without one cannot exist, and the gate reads every register rather
// than a list somebody keeps beside them.
//
// Three of the four kinds are a comparison and the fourth is a reason. A `Row` is a row of a block
// of the set. A `Writes` is a span of the set that carries the number in digits: the span must
// stand in the set and it must carry the value, so moving either side fails the build. A `Spells`
// is the same for a number the set writes in words. A `Code` is of this tree alone and says why
// the set does not hold it — the one kind that compares nothing, and therefore the one a reader
// looks at first.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Place {
    Row(&'static str),
    Writes(&'static str),
    Spells(&'static str),
    Code(&'static str),
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct Constant {
    pub name: &'static str,
    pub value: u128,
    pub place: Place,
}

#[macro_export]
macro_rules! place {
    (row $where:literal) => {
        $crate::Place::Row($where)
    };
    (writes $where:literal) => {
        $crate::Place::Writes($where)
    };
    (spells $where:literal) => {
        $crate::Place::Spells($where)
    };
    (code $why:literal) => {
        $crate::Place::Code($why)
    };
}

// One declaration for a number and its place. The register is written by the macro, so a constant
// declared through it is registered by that act and a constant declared outside it stands in no
// register at all — which is what the gate refuses when it counts the declarations of the sources
// against the rows of the registers.
#[macro_export]
macro_rules! constants {
    (
        $register:ident:
        $(
            $(#[$attr:meta])*
            $vis:vis const $name:ident : $ty:ty = $value:expr, $kind:ident $where:literal;
        )+
    ) => {
        $( $(#[$attr])* $vis const $name: $ty = $value; )+

        pub const $register: &[$crate::Constant] = &[
            $(
                $crate::Constant {
                    name: stringify!($name),
                    value: $name as u128,
                    place: $crate::place!($kind $where),
                },
            )+
        ];
    };
}

// The sizes of the primitives and of the quantities every layout is built from. The set states
// them in `docs/Montana Canon.md` — the suite table and the form table — and this is their one
// transcription: a layout that wrote 1952 or 3309 of its own would be a second place for a number
// that moves only when a suite does.
pub mod size {
    crate::constants! {
        WIDTHS:
        pub const HASH: usize = 32, row "hash_bytes";
        pub const TAG: usize = 16, writes "a label of a step 16 B";
        pub const STEP_SEAL: usize = 16, writes "a seal of a step 16 B";
        pub const AEAD_NONCE: usize = 12, writes "an AEAD nonce 12 B";
        pub const AEAD_TAG: usize = 16, writes "an AEAD tag 16 B";

        /// ML-DSA-65, the signature scheme of consensus and of a person's actions.
        /// Each width stands at its own cell of the row rather than at a span running over two of
        /// them: overlapping places name one another's failures and say nothing of their own.
        pub const SIGNING_SECRET_KEY: usize = 4_032, writes "| 4 032 B |";
        pub const SIGNING_PUBLIC_KEY: usize = 1_952, writes "| 1 952 B |";
        pub const SIGNATURE: usize = 3_309, writes "| 3 309 B |";

        /// ML-KEM-768, applied to client-side encryption.
        pub const KEM_SECRET_KEY: usize = 2_400, writes "whose secret key is 2 400 B";
        pub const KEM_PUBLIC_KEY: usize = 1_184, writes "whose public key is 1 184 B";
        pub const KEM_CIPHERTEXT: usize = 1_088, writes "ciphertext is 1 088 B";
    }
}

pub mod encode {
    #[derive(Debug, PartialEq, Eq)]
    pub enum DecodeError {
        UnexpectedEnd { needed: usize, remaining: usize },
        TrailingBytes { remaining: usize },
        CountMismatch { declared: usize, implied: usize },
    }

    pub trait CanonicalEncode {
        fn encode_into(&self, out: &mut Vec<u8>);

        fn encode(&self) -> Vec<u8> {
            let mut out = Vec::new();
            self.encode_into(&mut out);
            out
        }
    }

    pub trait CanonicalDecode: Sized {
        fn decode_from(input: &mut &[u8]) -> Result<Self, DecodeError>;

        fn decode_exact(bytes: &[u8]) -> Result<Self, DecodeError> {
            let mut input = bytes;
            let value = Self::decode_from(&mut input)?;
            if input.is_empty() {
                Ok(value)
            } else {
                Err(DecodeError::TrailingBytes {
                    remaining: input.len(),
                })
            }
        }
    }

    pub fn take<'a>(input: &mut &'a [u8], n: usize) -> Result<&'a [u8], DecodeError> {
        if input.len() < n {
            return Err(DecodeError::UnexpectedEnd {
                needed: n,
                remaining: input.len(),
            });
        }
        let (head, tail) = input.split_at(n);
        *input = tail;
        Ok(head)
    }

    macro_rules! le_int {
        ($t:ty, $n:expr) => {
            impl CanonicalEncode for $t {
                fn encode_into(&self, out: &mut Vec<u8>) {
                    out.extend_from_slice(&self.to_le_bytes());
                }
            }

            impl CanonicalDecode for $t {
                fn decode_from(input: &mut &[u8]) -> Result<Self, DecodeError> {
                    let bytes = take(input, $n)?;
                    let mut buf = [0u8; $n];
                    buf.copy_from_slice(bytes);
                    Ok(<$t>::from_le_bytes(buf))
                }
            }
        };
    }

    le_int!(u8, 1);
    le_int!(u16, 2);
    le_int!(u32, 4);
    le_int!(u64, 8);
    le_int!(u128, 16);

    impl<const N: usize> CanonicalEncode for [u8; N] {
        fn encode_into(&self, out: &mut Vec<u8>) {
            out.extend_from_slice(self);
        }
    }

    impl<const N: usize> CanonicalDecode for [u8; N] {
        fn decode_from(input: &mut &[u8]) -> Result<Self, DecodeError> {
            let bytes = take(input, N)?;
            let mut buf = [0u8; N];
            buf.copy_from_slice(bytes);
            Ok(buf)
        }
    }

    // Where a struct does not name the count field, the prefix of a variable array is u16
    // little-endian — the set's own rule.
    impl<T: CanonicalEncode> CanonicalEncode for Vec<T> {
        fn encode_into(&self, out: &mut Vec<u8>) {
            // PANIC-OK: no canonical array of this protocol exceeds a u16 count, and every
            // array this tree encodes is of a length a row of the set fixes. A longer one is a
            // defect of the caller rather than an input a stranger sends.
            assert!(self.len() <= usize::from(u16::MAX));
            out.extend_from_slice(&(self.len() as u16).to_le_bytes());
            for item in self {
                item.encode_into(out);
            }
        }
    }

    impl<T: CanonicalDecode> CanonicalDecode for Vec<T> {
        fn decode_from(input: &mut &[u8]) -> Result<Self, DecodeError> {
            let count = u16::decode_from(input)?;
            // The count is a claim the input has not yet backed: every element consumes at
            // least one byte, so the remaining length caps what a two-byte header may make
            // this allocate before the first element is even read.
            let mut items = Vec::with_capacity(usize::from(count).min(input.len()));
            for _ in 0..count {
                items.push(T::decode_from(input)?);
            }
            Ok(items)
        }
    }
}

// The auxiliary compositions the set admits over SHA-256 (Canon, "Primitives"): they carry no
// assumption of their own, and every one of them stands on published vectors — HMAC-SHA-256 of
// RFC 2104, HKDF-Expand of RFC 5869, PBKDF2 of RFC 8018. What passes through them is secret, so
// what they hold on the way out is wiped rather than left for the next frame.
pub mod derive {
    use sha2::{Digest, Sha256};
    use zeroize::{Zeroize, Zeroizing};

    crate::constants! {
        COMPOSITION_WIDTHS:
        /// The block of the compression function, which the standard fixes and the set does not
        /// restate: what the set states of these compositions is which of them it admits.
        const BLOCK: usize = 64, code "the block of SHA-256, fixed by FIPS 180-4";
        const OUT: usize = 32, row "hash_bytes";
    }

    pub fn hmac_sha256(key: &[u8], message: &[u8]) -> [u8; OUT] {
        let mut padded = Zeroizing::new([0u8; BLOCK]);
        if key.len() > BLOCK {
            let digest: [u8; OUT] = Sha256::digest(key).into();
            padded[..OUT].copy_from_slice(&digest);
        } else {
            padded[..key.len()].copy_from_slice(key);
        }
        let mut inner = Sha256::new();
        let mut outer = Sha256::new();
        let mut ipad = Zeroizing::new([0u8; BLOCK]);
        let mut opad = Zeroizing::new([0u8; BLOCK]);
        for i in 0..BLOCK {
            ipad[i] = padded[i] ^ 0x36;
            opad[i] = padded[i] ^ 0x5C;
        }
        inner.update(&ipad[..]);
        inner.update(message);
        let mut middle: [u8; OUT] = inner.finalize().into();
        outer.update(&opad[..]);
        outer.update(middle);
        middle.zeroize();
        outer.finalize().into()
    }

    // HKDF-Expand alone: the set gives a pseudorandom key of full length already, so the
    // extract step would only re-hash what it holds. RFC 5869 §2.3.
    pub fn hkdf_expand(prk: &[u8], info: &[u8], length: usize) -> Zeroizing<Vec<u8>> {
        // PANIC-OK: RFC 5869 stops at 255 blocks, and every expansion of this tree asks for
        // a length a row of the set fixes — thirty-two or sixty-four bytes. A caller asking for
        // more is a defect of the caller rather than an input a stranger sends.
        assert!(length <= 255 * OUT);
        let mut out = Zeroizing::new(Vec::with_capacity(length));
        let mut previous: Vec<u8> = Vec::new();
        // The counter is one byte on the wire and is counted in two: the last block of the
        // longest expansion the rule admits is numbered 255, and a byte incremented past it would
        // wrap where the rule ends rather than stop there.
        let mut counter: u16 = 1;
        while out.len() < length {
            let mut message = Zeroizing::new(Vec::with_capacity(previous.len() + info.len() + 1));
            message.extend_from_slice(&previous);
            message.extend_from_slice(info);
            message.push(counter as u8);
            let block = hmac_sha256(prk, &message);
            previous.zeroize();
            previous = block.to_vec();
            let take = core::cmp::min(OUT, length - out.len());
            out.extend_from_slice(&block[..take]);
            counter += 1;
        }
        previous.zeroize();
        out
    }

    // PBKDF2-HMAC-SHA-256, RFC 8018 §5.2. The count of iterations is what the set states at
    // the use; nothing here chooses it.
    pub fn pbkdf2_sha256(
        password: &[u8],
        salt: &[u8],
        iterations: u32,
        length: usize,
    ) -> Zeroizing<Vec<u8>> {
        // PANIC-OK: the count of iterations is a constant of the register, held against the set on
        // every build; a zero would be a stretch that does not stretch, and it cannot arrive here.
        assert!(iterations >= 1);
        let mut out = Zeroizing::new(Vec::with_capacity(length));
        let mut block_index = 1u32;
        while out.len() < length {
            let mut seed = Zeroizing::new(Vec::with_capacity(salt.len() + 4));
            seed.extend_from_slice(salt);
            seed.extend_from_slice(&block_index.to_be_bytes());
            let mut u = hmac_sha256(password, &seed);
            let mut accumulated = u;
            for _ in 1..iterations {
                u = hmac_sha256(password, &u);
                for (a, b) in accumulated.iter_mut().zip(u.iter()) {
                    *a ^= *b;
                }
            }
            u.zeroize();
            let take = core::cmp::min(OUT, length - out.len());
            out.extend_from_slice(&accumulated[..take]);
            accumulated.zeroize();
            block_index += 1;
        }
        out
    }
}

pub mod order {
    use core::cmp::Ordering;

    // Lexicographic comparison runs from the most significant byte, which for byte slices is
    // the natural slice order.
    pub fn lexicographic(a: &[u8], b: &[u8]) -> Ordering {
        a.cmp(b)
    }

    pub fn sort_ascending<T: AsRef<[u8]>>(items: &mut [T]) {
        items.sort_unstable_by(|a, b| lexicographic(a.as_ref(), b.as_ref()));
    }
}

#[cfg(test)]
mod tests {
    use super::encode::{CanonicalDecode, CanonicalEncode, DecodeError};
    use super::*;

    fn hex(bytes: &[u8]) -> String {
        bytes.iter().map(|b| format!("{b:02x}")).collect()
    }

    // xorshift64*, seeded once: the randomized round trip is the same run on every machine.
    struct Rng(u64);

    impl Rng {
        fn next(&mut self) -> u64 {
            let mut x = self.0;
            x ^= x >> 12;
            x ^= x << 25;
            x ^= x >> 27;
            self.0 = x;
            x.wrapping_mul(0x2545_F491_4F6C_DD1D)
        }
    }

    #[test]
    fn the_frozen_vectors_of_the_primitive_reproduce() {
        // Canon, "Frozen vectors", "The domain-separated primitive".
        let part = [0x11u8; 32];
        assert_eq!(
            hex(&hash_of_one(domain::MT_OP, &part)),
            "50e711d4d67814251fdccb022b04f17a6437d6a4ce2818a822e2a80e28dfe308"
        );
        assert_eq!(
            hex(&hash_of_one(domain::MT_PROPOSAL, &part)),
            "c1fbc6418289edabcbea889f671e6105a939035d3f9f833a5be3b570142e2038"
        );
    }

    #[test]
    fn prefix_related_domains_cannot_collide() {
        // "mt-op" is a prefix of "mt-open-nf"; the NUL after the domain makes the two
        // preimages differ even when the attacker shapes the parts to align.
        let tail = [0xABu8; 8];
        let mut shaped = b"en-nf".to_vec();
        shaped.extend_from_slice(&[0u8]);
        shaped.extend_from_slice(&tail);
        let a = hash_of_one(domain::MT_OP, &shaped);
        let b = hash_of_one(domain::MT_OPEN_NF, &tail);
        assert_ne!(a, b);
    }

    #[test]
    fn parts_are_one_concatenation() {
        let a = hash(domain::MT_OP, &[Part::of(b"ab"), Part::of(b"cd")]);
        let b = hash_of_one(domain::MT_OP, b"abcd");
        let c = hash(
            domain::MT_OP,
            &[Part::of(b"a"), Part::of(b"b"), Part::of(b"cd")],
        );
        assert_eq!(a, b);
        assert_eq!(a, c);
    }

    // What the builder writes is the concatenation the doors of the set describe, and the three
    // doors agree with the two functions that stood before them.
    #[test]
    fn the_builder_writes_the_concatenation_the_set_describes() {
        let a = [0x11u8; 32];
        let b = [0x22u8; 8];
        assert_eq!(
            Preimage::under(domain::MT_OP).fixed(&a).fixed(&b).finish(),
            hash(domain::MT_OP, &[Part::of(&a), Part::of(&b)])
        );
        let run = [[0x33u8; 32], [0x44u8; 32]];
        assert_eq!(
            Preimage::under(domain::MT_OP).run(&run).fixed(&b).finish(),
            hash(
                domain::MT_OP,
                &[Part::of(&run[0]), Part::of(&run[1]), Part::of(&b)]
            )
        );
        assert_eq!(
            Preimage::under(domain::MT_OP)
                .declared(&a[..], 32)
                .expect("the width it has")
                .finish(),
            hash_of_one(domain::MT_OP, &a)
        );
    }

    // The implementation this refuses: one that lays two values of no fixed width beside each
    // other and hashes them as one body. `("ab", "c")` and `("a", "bc")` share that body exactly,
    // so a preimage without the counts gives the two sets of values one value.
    #[test]
    fn a_count_before_a_value_is_what_keeps_two_splittings_apart() {
        let split = |left: &[u8], right: &[u8]| {
            Preimage::under(domain::MT_OP)
                .counted(left)
                .expect("a count holds it")
                .counted(right)
                .expect("a count holds it")
                .finish()
        };
        assert_ne!(split(b"ab", b"c"), split(b"a", b"bc"));
        // What the two would have shared without the counts.
        let laid_beside = hash_of_one(domain::MT_OP, b"abc");
        assert_ne!(split(b"ab", b"c"), laid_beside);
        assert_ne!(split(b"a", b"bc"), laid_beside);
    }

    #[test]
    fn a_value_offered_at_a_width_the_set_does_not_give_it_is_refused() {
        let bytes = [0x55u8; 31];
        assert_eq!(
            Preimage::under(domain::MT_OP)
                .declared(&bytes, 32)
                .map(|_| ())
                .expect_err("a width of thirty-one is not one of thirty-two"),
            PartError::Width {
                expected: 32,
                found: 31
            }
        );
        let long = vec![0u8; usize::from(u16::MAX) + 1];
        assert_eq!(
            Preimage::under(domain::MT_OP)
                .counted(&long)
                .map(|_| ())
                .expect_err("a count of two bytes does not hold it"),
            PartError::TooLong { found: 65_536 }
        );
    }

    #[test]
    fn a_name_the_registry_does_not_hold_yields_nothing() {
        assert!(domain::by_name("mt-op").is_some());
        assert!(domain::by_name("mt-nothing").is_none());
    }

    #[test]
    fn the_round_trip_holds_both_ways_for_every_integer_class() {
        let mut rng = Rng(0x4D54_2D43_4F52_4531);
        for _ in 0..1000 {
            let v = rng.next();
            assert_eq!(u8::decode_exact(&(v as u8).encode()), Ok(v as u8));
            assert_eq!(u16::decode_exact(&(v as u16).encode()), Ok(v as u16));
            assert_eq!(u32::decode_exact(&(v as u32).encode()), Ok(v as u32));
            assert_eq!(u64::decode_exact(&v.encode()), Ok(v));
            let w = (u128::from(rng.next()) << 64) | u128::from(v);
            assert_eq!(u128::decode_exact(&w.encode()), Ok(w));
        }
        for _ in 0..1000 {
            let bytes: Vec<u8> = (0..16).map(|_| rng.next() as u8).collect();
            assert_eq!(
                u8::decode_exact(&bytes[..1]).expect("decodes").encode(),
                &bytes[..1]
            );
            assert_eq!(
                u16::decode_exact(&bytes[..2]).expect("decodes").encode(),
                &bytes[..2]
            );
            assert_eq!(
                u32::decode_exact(&bytes[..4]).expect("decodes").encode(),
                &bytes[..4]
            );
            assert_eq!(
                u64::decode_exact(&bytes[..8]).expect("decodes").encode(),
                &bytes[..8]
            );
            assert_eq!(u128::decode_exact(&bytes).expect("decodes").encode(), bytes);
        }
    }

    #[test]
    fn a_count_the_input_does_not_back_buys_no_allocation_and_is_refused() {
        assert_eq!(
            Vec::<[u8; 32]>::decode_exact(&[0xFF, 0xFF]),
            Err(DecodeError::UnexpectedEnd {
                needed: 32,
                remaining: 0
            })
        );
    }

    #[test]
    fn the_round_trip_holds_both_ways_for_arrays_and_counted_vectors() {
        let mut rng = Rng(0x4D54_2D43_4F52_4532);
        for _ in 0..1000 {
            let mut arr = [0u8; 32];
            for byte in arr.iter_mut() {
                *byte = rng.next() as u8;
            }
            assert_eq!(<[u8; 32]>::decode_exact(&arr.encode()), Ok(arr));

            let len = (rng.next() % 5) as usize;
            let items: Vec<[u8; 16]> = (0..len)
                .map(|_| {
                    let mut item = [0u8; 16];
                    for byte in item.iter_mut() {
                        *byte = rng.next() as u8;
                    }
                    item
                })
                .collect();
            let bytes = items.encode();
            assert_eq!(bytes.len(), 2 + 16 * len);
            let back = Vec::<[u8; 16]>::decode_exact(&bytes).expect("counted vector decodes");
            assert_eq!(back, items);
            assert_eq!(back.encode(), bytes);
        }
    }

    #[test]
    fn a_short_or_padded_input_is_refused_with_the_sizes_named() {
        assert_eq!(
            u64::decode_exact(&[0u8; 7]),
            Err(DecodeError::UnexpectedEnd {
                needed: 8,
                remaining: 7
            })
        );
        assert_eq!(
            u64::decode_exact(&[0u8; 9]),
            Err(DecodeError::TrailingBytes { remaining: 1 })
        );
        assert_eq!(
            Vec::<u64>::decode_exact(&[2, 0, 1, 2, 3, 4, 5, 6, 7, 8]),
            Err(DecodeError::UnexpectedEnd {
                needed: 8,
                remaining: 0
            })
        );
    }

    #[test]
    fn the_decoders_survive_a_storm_of_arbitrary_bytes() {
        let mut rng = Rng(0x4D54_2D43_4F52_4533);
        for _ in 0..4000 {
            let len = (rng.next() % 40) as usize;
            let bytes: Vec<u8> = (0..len).map(|_| rng.next() as u8).collect();
            macro_rules! survives {
                ($t:ty) => {
                    if let Ok(v) = <$t>::decode_exact(&bytes) {
                        assert_eq!(v.encode(), bytes);
                    }
                };
            }
            survives!(u8);
            survives!(u16);
            survives!(u32);
            survives!(u64);
            survives!(u128);
            survives!([u8; 32]);
            survives!(Vec<u64>);
            survives!(Vec<[u8; 16]>);
        }
    }

    #[test]
    fn the_auxiliary_compositions_reproduce_their_published_vectors() {
        use super::derive::{hkdf_expand, hmac_sha256, pbkdf2_sha256};

        // RFC 4231 §4.2, HMAC-SHA-256 case 1.
        assert_eq!(
            hex(&hmac_sha256(&[0x0b; 20], b"Hi There")),
            "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7"
        );
        // RFC 4231 §4.4, case 3: a key longer than the block is hashed first.
        assert_eq!(
            hex(&hmac_sha256(
                &[0xaa; 131],
                b"Test Using Larger Than Block-Size Key - Hash Key First"
            )),
            "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54"
        );

        // RFC 5869 Appendix A.1: the expand step over the case's own PRK.
        let prk = [
            0x07, 0x77, 0x09, 0x36, 0x2c, 0x2e, 0x32, 0xdf, 0x0d, 0xdc, 0x3f, 0x0d, 0xc4, 0x7b,
            0xba, 0x63, 0x90, 0xb6, 0xc7, 0x3b, 0xb5, 0x0f, 0x9c, 0x31, 0x22, 0xec, 0x84, 0x4a,
            0xd7, 0xc2, 0xb3, 0xe5,
        ];
        let info = [0xf0u8, 0xf1, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8, 0xf9];
        assert_eq!(
            hex(&hkdf_expand(&prk, &info, 42)),
            "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865"
        );

        // RFC 7914 §11, PBKDF2-HMAC-SHA-256 with one iteration and with 80 000.
        assert_eq!(
            hex(&pbkdf2_sha256(b"passwd", b"salt", 1, 64)),
            "55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc\
49ca9cccf179b645991664b39d77ef317c71b845b1e30bd509112041d3a19783"
        );
        assert_eq!(
            hex(&pbkdf2_sha256(b"Password", b"NaCl", 80_000, 64)),
            "4ddcd8f60b98be21830cee5ef22701f9641a4418d04c0414aeff08876b34ab56\
a1d425a1225833549adb841b51c9b3176a272bdebba1d078478f62b397f33c8d"
        );
    }

    #[test]
    fn the_expansion_answers_the_length_it_is_asked_for() {
        use super::derive::hkdf_expand;
        let prk = [0x11u8; 32];
        // The longest expansion RFC 5869 admits, and the one below it.
        assert_eq!(
            hkdf_expand(&prk, b"mt-account-key", 255 * 32).len(),
            255 * 32
        );
        assert_eq!(
            hkdf_expand(&prk, b"mt-account-key", 254 * 32 + 1).len(),
            254 * 32 + 1
        );
        for length in [1usize, 31, 32, 33, 64, 65, 200] {
            assert_eq!(hkdf_expand(&prk, b"mt-account-key", length).len(), length);
        }
        // A prefix of a longer expansion is the shorter one: the blocks chain, they do not
        // depend on the length asked for.
        let long = hkdf_expand(&prk, b"mt-note-key", 64);
        let short = hkdf_expand(&prk, b"mt-note-key", 32);
        assert_eq!(&long[..32], &short[..]);
    }

    #[test]
    fn the_canonical_order_ascends_from_the_most_significant_byte() {
        let mut items = [[0x40u8; 32], [0x10u8; 32], [0x90u8; 32]];
        order::sort_ascending(&mut items);
        assert_eq!(items[0], [0x10u8; 32]);
        assert_eq!(items[1], [0x40u8; 32]);
        assert_eq!(items[2], [0x90u8; 32]);
        let mut a = [0u8; 32];
        let mut b = [0u8; 32];
        a[0] = 1;
        b[31] = 0xFF;
        assert_eq!(order::lexicographic(&a, &b), core::cmp::Ordering::Greater);
    }
}
