// The layouts. Each one is a length and an order, and each answers three questions the same way:
// what its total width is, how its fields serialize, and what its signed scope is. The set fixes
// all three in `docs/Montana Canon.md`, "Layouts".
//
// A layout of a fixed width is refused by its length before it is parsed. That is not an
// optimisation: an object of the wrong length is not an object of this protocol, and reading fields
// out of it would be reading fields out of something else.

use mt_codec::size;
use mt_genesis::scalar;

// What a door refuses an object for. A length is the first of them and the cheapest; the rest are
// the structural rules the set states beside each layout, and they stand here rather than in a
// function a caller may forget to call — an object that reached a field of this protocol has
// passed every one of them.
#[derive(Debug, PartialEq, Eq)]
pub enum ObjectError {
    Length { expected: usize, found: usize },
    // The pair of attested identifiers does not ascend, or repeats.
    Attested,
    // The name field is not a lawful normalized name padded with zeros to its width.
    Name,
    // A record claims segments outside the maximum continuity period.
    RecordContinuity,
    // The total byte length can be right while nested spending runs have wrong lengths.
    FrameShape,
    // A ballot casting no vote, or more votes than a standing holds units.
    Votes,
    // A pledge standing on an attempt after its own, made in the attempt no count reaches, or open in
    // attempt zero, whose one open pledge is the heavy attestation.
    Since,
    // A pledge whose `line_value` carries a word at or above the modulus of the proof field: no
    // element of the field of the line, refused before its proof is verified.
    LineValue,
    // A roll naming more frames than a window applies, or parts that do not ascend.
    Roll,
}

// The witness that the length of an input has been compared. Its one field is private, so the
// only place it is ever made is `parse`, after the comparison — `decode` therefore cannot be
// reached over bytes whose length nobody checked, from anywhere.
pub struct LengthChecked(());

// What every layout of a fixed width answers. `signed_scope` is the object without its signature,
// and is the whole of it where there is none to leave out.
pub trait Layout: Sized {
    const NAME: &'static str;

    fn expected_len() -> usize;

    // The width a signature covers: the sum of the fields standing before it, written by the
    // declaration and never by hand. A layout that carries none answers with its whole width.
    fn scope_len() -> usize;

    fn encode(&self) -> Vec<u8>;

    fn decode(bytes: &[u8], checked: LengthChecked) -> Result<Self, ObjectError>;

    // The rule a value answers before it is an object of this protocol, over and above its width.
    // It is answered on both sides: a value read off the wire passes it before it is handed on,
    // and a value assembled here passes it before its bytes are — so an object that breaks it
    // cannot be signed, cannot carry an identifier and cannot be published by the tree that made
    // it. A layout stating no rule answers this the one way there is to answer it.
    fn rule(&self) -> Result<(), ObjectError> {
        Ok(())
    }

    // The one door: the length is compared before a byte is read.
    fn parse(bytes: &[u8]) -> Result<Self, ObjectError> {
        let expected = Self::expected_len();
        if bytes.len() != expected {
            return Err(ObjectError::Length {
                expected,
                found: bytes.len(),
            });
        }
        Self::decode(bytes, LengthChecked(()))
    }

    // The scope a signature covers, taken the one way for every layout: the bytes of the object,
    // kept up to the width the declaration gives. Nothing is subtracted, so no arrangement of
    // fields can cut past zero, and no layout states a scope of its own for its author to state
    // wrongly — a signature is written by the declaration that ends `and a signature`, and the
    // scope is the sum of what stands before it.
    fn signed_scope(&self) -> Result<Vec<u8>, ObjectError> {
        let mut bytes = self.bytes()?;
        bytes.truncate(Self::scope_len());
        Ok(bytes)
    }

    // The one door that hands the bytes of a layout to anybody: the width is compared against the
    // one the set fixes, so a value assembled by hand out of fields of another width cannot become
    // a scope, an identifier or a signature. `encode` writes what it holds; this says whether what
    // it holds is an object of this protocol.
    fn bytes(&self) -> Result<Vec<u8>, ObjectError> {
        let out = self.encode();
        let expected = Self::expected_len();
        if out.len() != expected {
            return Err(ObjectError::Length {
                expected,
                found: out.len(),
            });
        }
        self.rule()?;
        Ok(out)
    }
}

fn take(bytes: &[u8], at: &mut usize, n: usize) -> Vec<u8> {
    let out = bytes[*at..*at + n].to_vec();
    *at += n;
    out
}

fn take_u64(bytes: &[u8], at: &mut usize) -> u64 {
    let mut eight = [0u8; 8];
    eight.copy_from_slice(&bytes[*at..*at + 8]);
    *at += 8;
    u64::from_le_bytes(eight)
}

fn take_u32(bytes: &[u8], at: &mut usize) -> u32 {
    let mut four = [0u8; 4];
    four.copy_from_slice(&bytes[*at..*at + 4]);
    *at += 4;
    u32::from_le_bytes(four)
}

fn take_u16(bytes: &[u8], at: &mut usize) -> u16 {
    let mut two = [0u8; 2];
    two.copy_from_slice(&bytes[*at..*at + 2]);
    *at += 2;
    u16::from_le_bytes(two)
}

// A field of a layout: what it is worth in bytes, how it is written and how it is read back. The
// width comes from the type where a type carries one and from a row of the set where it does not,
// and there is no third source — a field standing under neither rule does not compile.
pub trait Field: Sized {
    fn width() -> usize;
    fn write(&self, out: &mut Vec<u8>);
    // Reachable only behind the door of the length, which compares before a byte is read.
    fn read(bytes: &[u8], at: &mut usize) -> Self;
}

impl<const N: usize> Field for [u8; N] {
    fn width() -> usize {
        N
    }

    fn write(&self, out: &mut Vec<u8>) {
        out.extend_from_slice(self);
    }

    fn read(bytes: &[u8], at: &mut usize) -> Self {
        let mut value = [0u8; N];
        value.copy_from_slice(&bytes[*at..*at + N]);
        *at += N;
        value
    }
}

// A count the Decree fixes, read where a layout states it: a layout taking a count from anywhere
// else would be a second place for a number of the set.
fn count_of(row: &str) -> usize {
    // PANIC-OK: the Decree is a static of this tree and the harness refuses a build in which the
    // set and it disagree, so a missing row is a tree that is not this protocol rather than an
    // input anyone can send.
    scalar(row).expect("the Decree names it") as usize
}

// The kinds a field stands under, each answered in one place: what it is worth, how it writes,
// how it reads, and what type holds it. Four answers to one declaration, given here so that no
// layout can give them differently.
macro_rules! field_width {
    (u8) => {
        1
    };
    (u16) => {
        2
    };
    (u32) => {
        4
    };
    (u64) => {
        8
    };
    ([u8; $n:literal]) => {
        $n
    };
    (bytes ($w:expr)) => {
        $w
    };
    (run ($t:ty; $n:expr)) => {
        $n * <$t as Field>::width()
    };
    (count16 ($t:ty; $n:expr)) => {
        2 + $n * <$t as Field>::width()
    };
}

macro_rules! field_type {
    (u8) => { u8 };
    (u16) => { u16 };
    (u32) => { u32 };
    (u64) => { u64 };
    ([u8; $n:literal]) => { [u8; $n] };
    (bytes ($w:expr)) => { Vec<u8> };
    (run ($t:ty; $n:expr)) => { Vec<$t> };
    (count16 ($t:ty; $n:expr)) => { Vec<$t> };
}

macro_rules! field_write {
    (u8, $out:expr, $value:expr) => {
        $out.push($value)
    };
    (u16, $out:expr, $value:expr) => {
        $out.extend_from_slice(&$value.to_le_bytes())
    };
    (u32, $out:expr, $value:expr) => {
        $out.extend_from_slice(&$value.to_le_bytes())
    };
    (u64, $out:expr, $value:expr) => {
        $out.extend_from_slice(&$value.to_le_bytes())
    };
    ([u8; $n:literal], $out:expr, $value:expr) => {
        $out.extend_from_slice(&$value)
    };
    (bytes ($w:expr), $out:expr, $value:expr) => {
        $out.extend_from_slice(&$value)
    };
    (run ($t:ty; $n:expr), $out:expr, $value:expr) => {
        for item in $value.iter() {
            <$t as Field>::write(item, $out);
        }
    };
    (count16 ($t:ty; $n:expr), $out:expr, $value:expr) => {{
        $out.extend_from_slice(&($value.len() as u16).to_le_bytes());
        for item in $value.iter() {
            <$t as Field>::write(item, $out);
        }
    }};
}

macro_rules! field_read {
    (u8, $bytes:expr, $at:expr) => {{
        let value = $bytes[*$at];
        *$at += 1;
        value
    }};
    (u16, $bytes:expr, $at:expr) => {
        take_u16($bytes, $at)
    };
    (u32, $bytes:expr, $at:expr) => {
        take_u32($bytes, $at)
    };
    (u64, $bytes:expr, $at:expr) => {
        take_u64($bytes, $at)
    };
    ([u8; $n:literal], $bytes:expr, $at:expr) => {
        <[u8; $n] as Field>::read($bytes, $at)
    };
    (bytes ($w:expr), $bytes:expr, $at:expr) => {
        take($bytes, $at, $w)
    };
    (run ($t:ty; $n:expr), $bytes:expr, $at:expr) => {
        (0..$n)
            .map(|_| <$t as Field>::read($bytes, $at))
            .collect::<Vec<$t>>()
    };
    (count16 ($t:ty; $n:expr), $bytes:expr, $at:expr) => {{
        // The count stands on the wire and the set fixes it: a value stating another count is
        // refused before its elements are read, since a width agreeing by accident would let two
        // shapes share one length.
        let stated = usize::from(take_u16($bytes, $at));
        let held: usize = $n;
        if stated != held {
            return Err(ObjectError::Length {
                expected: held,
                found: stated,
            });
        }
        (0..held)
            .map(|_| <$t as Field>::read($bytes, $at))
            .collect::<Vec<$t>>()
    }};
}

// Whether a field carries the name a signature takes. A layout that holds one declares it by
// ending `and a signature`, which writes the field itself; a field of that name written by hand
// would be a second way to say one thing, and the two would part on the day one of them moved.
const fn is_the_name_of_a_signature(name: &str) -> bool {
    let bytes = name.as_bytes();
    let mine = b"signature";
    if bytes.len() != mine.len() {
        return false;
    }
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] != mine[i] {
            return false;
        }
        i += 1;
    }
    true
}

// The body of a declaration, written once: the struct, the writer, the reader, the expected
// length, the width a signature covers and the rule a value answers before it becomes an object.
// Nothing here is written per layout, so nothing here can disagree with itself.
macro_rules! layout_body {
    (
        $(#[$sattr:meta])*
        $name:ident, $label:literal, scope: $scope:expr
        $(, checked by $check:path)?
        , { $( $(#[$fattr:meta])* $fname:ident : $fkind:tt $(($($fargs:tt)*))? ),+ $(,)? }
    ) => {
        $(#[$sattr])*
        #[derive(Debug, Clone, PartialEq, Eq)]
        pub struct $name {
            $( $(#[$fattr])* pub $fname: field_type!($fkind $(($($fargs)*))?), )+
        }

        impl Layout for $name {
            const NAME: &'static str = $label;

            fn expected_len() -> usize {
                0 $( + field_width!($fkind $(($($fargs)*))?) )+
            }

            fn scope_len() -> usize {
                $scope
            }

            fn encode(&self) -> Vec<u8> {
                let mut out = Vec::with_capacity(Self::expected_len());
                $( field_write!($fkind $(($($fargs)*))?, &mut out, self.$fname); )+
                out
            }

            fn decode(bytes: &[u8], _checked: LengthChecked) -> Result<Self, ObjectError> {
                let at = &mut 0usize;
                let value = Self {
                    $( $fname: field_read!($fkind $(($($fargs)*))?, bytes, at), )+
                };
                value.rule()?;
                Ok(value)
            }

            $(
                fn rule(&self) -> Result<(), ObjectError> {
                    $check(self)
                }
            )?
        }
    };
}

// One declaration per layout, in two shapes and no third: a layout that ends `and a signature`
// carries one, and a layout that does not carries none.
//
// The signature is written by the declaration rather than by its author, so it stands last by
// construction and the scope it covers is the sum of the widths above it — never a subtraction
// from the whole, which is what could answer nonsense on a layout shorter than a signature. A
// field of that name written by hand fails to compile, so the two ways of saying one thing are
// one way.
macro_rules! layout {
    (
        $(#[$sattr:meta])*
        $name:ident, $label:literal
        $(, checked by $check:path)?
        , { $( $(#[$fattr:meta])* $fname:ident : $fkind:tt $(($($fargs:tt)*))? ),+ $(,)? } and a signature
    ) => {
        layout_body! {
            $(#[$sattr])*
            $name, $label, scope: 0 $( + field_width!($fkind $(($($fargs)*))?) )+
            $(, checked by $check)?
            , {
                $( $(#[$fattr])* $fname : $fkind $(($($fargs)*))? , )+
                signature: bytes(size::SIGNATURE),
            }
        }
    };

    (
        $(#[$sattr:meta])*
        $name:ident, $label:literal
        $(, checked by $check:path)?
        , { $( $(#[$fattr:meta])* $fname:ident : $fkind:tt $(($($fargs:tt)*))? ),+ $(,)? }
    ) => {
        const _: () = {
            $(
                assert!(
                    !is_the_name_of_a_signature(stringify!($fname)),
                    "a layout carrying a signature ends `and a signature`, which writes the field"
                );
            )+
        };

        layout_body! {
            $(#[$sattr])*
            $name, $label, scope: Self::expected_len()
            $(, checked by $check)?
            , { $( $(#[$fattr])* $fname : $fkind $(($($fargs)*))? ),+ }
        }
    };
}

// A structure standing inside a layout rather than beside one: it has no length of its own on the
// wire and no scope, and what it owes is the three answers of a field.
macro_rules! nested {
    (
        $(#[$sattr:meta])*
        $name:ident, { $( $(#[$fattr:meta])* $fname:ident : $fkind:tt $(($($fargs:tt)*))? ),+ $(,)? }
    ) => {
        $(#[$sattr])*
        #[derive(Debug, Clone, PartialEq, Eq)]
        pub struct $name {
            $( $(#[$fattr])* pub $fname: field_type!($fkind $(($($fargs)*))?), )+
        }

        impl Field for $name {
            fn width() -> usize {
                0 $( + field_width!($fkind $(($($fargs)*))?) )+
            }

            fn write(&self, out: &mut Vec<u8>) {
                $( field_write!($fkind $(($($fargs)*))?, out, self.$fname); )+
            }

            fn read(bytes: &[u8], at: &mut usize) -> Self {
                Self {
                    $( $fname: field_read!($fkind $(($($fargs)*))?, bytes, at), )+
                }
            }
        }
    };
}
// The register of the layouts this tree holds. It is written once, here, and the gate compares it
// against the set: a layout without a row of the set fails, and a row of the set without a layout
// fails with it. A count would pass a tree that lost one as readily as one that kept it.
pub const NAMES: &[(&str, &str)] = &[
    ("proposal", "proposal"),
    ("frame", "frame"),
    ("confirmation", "confirmation"),
    ("light attestation", "light_attestation"),
    ("candidacy", "candidacy"),
    ("beacon", "beacon"),
    ("notice", "notice"),
    ("commitment over a slot", "name_commit"),
    ("renewal of a slot", "name_renew"),
    ("reveal of a name", "name_reveal"),
    ("reveal of a channel", "channel_reveal"),
    ("publication of a channel", "channel_publication"),
    ("committed record of a person", "record"),
    ("opening", "opening"),
    ("action", "action"),
    ("ballot", "ballot"),
    ("pledge", "pledge"),
];

// The bodies this tree holds: objects whose length is a function of their own counts, each count
// bounded before an entry is read. The gate compares this register with the set as it compares the
// one above, so a body the set lays out and this tree does not hold fails the build with its name.
pub const BODIES: &[(&str, &str)] = &[("roll", "roll")];

// ── The proposal that closes a window ──────────────────────────────────────────────────────────

nested! {
    /// One census window of the standing a proposal carries: the root of the tree of its cement and
    /// how many parts that cement names.
    Census, {
        root: [u8; 32],
        count: u64,
    }
}

layout! {
    Proposal, "proposal", {
        window: u64,
        protocol_version: u32,
        previous: [u8; 32],
        note_root: [u8; 32],
        nullifier_root: [u8; 32],
        record_root: [u8; 32],
        machine_root: [u8; 32],
        admitted_root: [u8; 32],
        /// The root of the tree of credited rights once this proposal has appended the parts of
        /// the cement of the window before it: the root a right of that window walks to.
        credited_root: [u8; 32],
        operations_root: [u8; 32],
        /// The identifier of the roll: the frames the window applied in the order they applied, then
        /// the parts of its cement. Inside the name, since it is what the window decided, and a
        /// function of what the roots and the cement already fix.
        roll: [u8; 32],
        /// The machines the tree of admitted machines holds, recomputed with its root: the count the
        /// electorate of the window two on is read against.
        admitted_count: u64,
        /// The aggregate and the count of the cement of the window, its living whatever names they
        /// pledged: the state the final beacon carried, recomputed by every verifier from the heavy
        /// attestations it holds.
        cement_aggregate: [u8; 32],
        cement_count: u64,
        /// The census windows the standing of the electorate is counted over, newest first: the
        /// standing of the window two on is the sum of their counts, and a ballot walks their roots.
        census: run(Census; count_of("standing_censuses")),
        suite_id: u16,
        /// The beacon the runner closed the window on, carrying the cement above: the evidence a
        /// device behind reads the cement off, and outside the name, because two branches of the
        /// versions of a round carrying one cement are one decision.
        final_beacon: [u8; 32],
        runner_pubkey: bytes(size::SIGNING_PUBLIC_KEY),
        /// Under the description of the ticket, at the height of the presence and of its length.
        ticket_proof: bytes(super::PRESENCE_PROOF_LEN),
    } and a signature
}

// The major component stands in the upper sixteen bits and the minor in the lower: a machine
// refuses a proposal whose major exceeds the one it implements, and one whose value stands below
// its predecessor's, so rules never roll back inside one chain.
impl Proposal {
    // The identifier of a proposal, over the fields the window decided, under the proposal domain.
    // `docs/Montana Canon.md`, "The proposal that closes a window".
    pub fn id(&self) -> Result<[u8; 32], ObjectError> {
        let mut bytes = self.encode();
        bytes.truncate(super::PROPOSAL_DECIDED_LEN);
        Ok(super::identifier(mt_codec::domain::MT_PROPOSAL, &bytes))
    }

    pub fn major(&self) -> u16 {
        (self.protocol_version >> 16) as u16
    }

    pub fn minor(&self) -> u16 {
        (self.protocol_version & 0xFFFF) as u16
    }
}

// ── The frame of a payment ─────────────────────────────────────────────────────────────────────

nested! {
    Spend, {
        nullifiers: run([u8; 32]; count_of("spend_inputs")),
        commitments: run([u8; 32]; count_of("spend_outputs")),
        rate_nullifier: [u8; 32],
    }
}

layout! {
    /// It carries no key and no signature, and it names no window: a verifier holds the window it
    /// is applying and the ceiling of openings that window allows.
    Opening, "opening", {
        open_nullifier: [u8; 32],
        record_commit: [u8; 32],
        proof: bytes(super::PROOF_LEN),
    }
}

layout! {
    /// Anchoring a hash, changing a key, witnessing and closing are one object: the plane
    /// publishes what a transition is and never which transition it was.
    Action, "action", {
        record_nullifier: [u8; 32],
        successor_commit: [u8; 32],
        act_nullifier: [u8; 32],
        proof: bytes(super::PROOF_LEN),
    }
}

layout! {
    /// A frame carries no signature: its whole is its scope.
    Frame, "frame", checked by frame_shape, {
        spends: run(Spend; count_of("spends_per_frame")),
        proof: bytes(super::PROOF_LEN),
    }
}

fn frame_shape(frame: &Frame) -> Result<(), ObjectError> {
    if frame.spends.len() != count_of("spends_per_frame")
        || frame.proof.len() != super::PROOF_LEN
        || frame.spends.iter().any(|spend| {
            spend.nullifiers.len() != count_of("spend_inputs")
                || spend.commitments.len() != count_of("spend_outputs")
        })
    {
        return Err(ObjectError::FrameShape);
    }
    Ok(())
}

impl Frame {
    // The name of a frame, taken by the rule every identifier of this set is taken by: the class
    // domain of the object over its signed scope, which for an object carrying no signature is the
    // whole of its canonical bytes. A notice of a spend names the frame by this and by nothing
    // else, so two readers of one frame reach one name.
    pub fn id(&self) -> Result<[u8; 32], ObjectError> {
        Ok(super::identifier(
            mt_codec::domain::MT_FRAME,
            &self.signed_scope()?,
        ))
    }

    // Every nullifier in one frame is distinct, and a repeat within a frame is refused without
    // looking further.
    pub fn nullifiers_are_distinct(&self) -> bool {
        let mut seen: Vec<[u8; 32]> = self
            .spends
            .iter()
            .flat_map(|s| s.nullifiers.iter().copied())
            .collect();
        let before = seen.len();
        seen.sort_unstable();
        seen.dedup();
        before == seen.len()
    }
}

// ── The confirmation of a window, and its light form ───────────────────────────────────────────

// `attested` holds exactly two identifiers — the beacon of the round and the proposal of the
// previous window — ascending, so the width of the object is one number.
mt_codec::constants! {
    ATTESTED:
    pub const ATTESTED_COUNT: usize = 2, spells "`attested` holds exactly two identifiers — the beacon of the round";
}

// `attested` ascends lexicographically and holds no repeat: an implementation sorting it any other
// way produces a different identifier for the same attestation.
pub fn attested_is_canonical(attested: &[[u8; 32]]) -> bool {
    attested.windows(2).all(|pair| pair[0] < pair[1])
}

fn attested_of_confirmation(value: &Confirmation) -> Result<(), ObjectError> {
    ordered(&value.attested)?;
    canonical_line_value(&value.line_value)
}

fn attested_of_light(value: &LightAttestation) -> Result<(), ObjectError> {
    ordered(&value.attested)
}

fn ordered(attested: &[[u8; 32]]) -> Result<(), ObjectError> {
    if attested_is_canonical(attested) {
        Ok(())
    } else {
        Err(ObjectError::Attested)
    }
}

layout! {
    Confirmation, "confirmation", checked by attested_of_confirmation, {
        window: u64,
        attested: count16([u8; 32]; ATTESTED_COUNT),
        part_nullifier: [u8; 32],
        round_nullifier: [u8; 32],
        line_value: [u8; 32],
        suite_id: u16,
        answering_key: bytes(size::SIGNING_PUBLIC_KEY),
        proof: bytes(super::PRESENCE_PROOF_LEN),
    } and a signature
}

layout! {
    LightAttestation, "light attestation", checked by attested_of_light, {
        window: u64,
        attested: count16([u8; 32]; ATTESTED_COUNT),
        part_nullifier: [u8; 32],
        round_nullifier: [u8; 32],
        suite_id: u16,
        answering_key: bytes(size::SIGNING_PUBLIC_KEY),
    } and a signature
}

// ── The candidacy of a machine ─────────────────────────────────────────────────────────────────

layout! {
    /// It carries no signature and no key: its whole is its scope.
    Candidacy, "candidacy", {
        window: u64,
        naming_half: [u8; 32],
        node_commit: [u8; 32],
        operator_nullifier: [u8; 32],
        suite_id: u16,
        proof: bytes(super::PROOF_LEN),
    }
}

// ── The notice of a spend ─────────────────────────────────────────────────────────────────────

layout! {
    Notice, "notice", {
        nullifier: [u8; 32],
        frame: [u8; 32],
    }
}

// ── The beacon of a round ──────────────────────────────────────────────────────────────────────

layout! {
    /// The cement a beacon carries is the aggregate over the part-nullifiers of the heavy
    /// attestations published so far, each at most once, with the window as its context, beside
    /// their count; every verifier recomputes both and refuses a beacon whose pair differs.
    Beacon, "beacon", {
        window: u64,
        chain: u8,
        round: u32,
        previous: [u8; 32],
        cement_aggregate: [u8; 32],
        cement_count: u64,
        /// The votes the ballots of those parts drew, each part's at most once: the evidence the
        /// close of the window reads beside the count, and no value of what the window decided.
        cement_votes: u64,
    }
}

impl Beacon {
    // The identifier every beacon links to its predecessor by, taken under the beacon domain
    // over signed scope — which for an object carrying no signature is the whole of it.
    pub fn id(&self) -> Result<[u8; 32], ObjectError> {
        Ok(super::identifier(
            mt_codec::domain::MT_BEACON,
            &self.signed_scope()?,
        ))
    }
}

// ── The ballot of a part ───────────────────────────────────────────────────────────────────────

layout! {
    /// It carries no key and no signature: the proof binds the part, the window and the count, and
    /// nobody but the holder of the half that derived the part can write one.
    Ballot, "ballot", checked by votes_of_a_ballot, {
        window: u64,
        part_nullifier: [u8; 32],
        votes: u64,
        proof: bytes(super::PROOF_LEN),
    }
}

// A ballot casts at least one vote and no more than a standing holds units: one that casts none says
// nothing, and one that casts more says what no proof of this set can assert.
fn votes_of_a_ballot(value: &Ballot) -> Result<(), ObjectError> {
    if value.votes == 0 || value.votes > count_of("standing_censuses") as u64 {
        return Err(ObjectError::Votes);
    }
    Ok(())
}

// ── The pledge of a part ───────────────────────────────────────────────────────────────────────

layout! {
    /// What a part says in an attempt of the agreement on the proposal of the window before: which
    /// name it stands behind, and on which quorum. It names no machine. It carries the line of its
    /// slot at the abscissa of that name, and the proof that its part's half drew that value.
    Pledge, "pledge", checked by rules_of_a_pledge, {
        window: u64,
        attempt: u32,
        name: [u8; 32],
        since: u32,
        part_nullifier: [u8; 32],
        line_value: [u8; 32],
        suite_id: u16,
        answering_key: bytes(size::SIGNING_PUBLIC_KEY),
        proof: bytes(super::PRESENCE_PROOF_LEN),
    } and a signature
}

fn rules_of_a_pledge(value: &Pledge) -> Result<(), ObjectError> {
    since_of_a_pledge(value)?;
    canonical_line_value(&value.line_value)
}

// `line_value`, on a pledge and on a confirmation alike, is an element of the field of the line, four
// canonical words, and nothing else: a word written at or above the modulus is a second spelling of a
// value, and the proof would be read against a line nobody drew. Refused here, before anything reads
// the proof.
fn canonical_line_value(line_value: &[u8; 32]) -> Result<(), ObjectError> {
    mt_proof::line::L::from_bytes(line_value)
        .map(|_| ())
        .ok_or(ObjectError::LineValue)
}

// A pledge stands on its own attempt (closing), on an earlier one or on none (open). One standing on a
// later attempt says what nobody saw, one made in the attempt numbered as none could never be told
// from a pledge standing on none, and an open pledge of attempt zero would be a second first vote
// beside the heavy attestation, which is the one open pledge of that attempt.
fn since_of_a_pledge(value: &Pledge) -> Result<(), ObjectError> {
    let none = super::STANDS_ON_NONE;
    if value.attempt == none
        || (value.since != none && value.since > value.attempt)
        || (value.attempt == 0 && value.since == none)
    {
        return Err(ObjectError::Since);
    }
    Ok(())
}

impl Pledge {
    // A closing pledge stands on the quorum of its own attempt; every other pledge is open.
    pub fn is_closing(&self) -> bool {
        self.since == self.attempt
    }

    // The attempt whose quorum an open pledge stands on, or none.
    pub fn stands_on(&self) -> Option<u32> {
        (self.since != super::STANDS_ON_NONE).then_some(self.since)
    }
}

// ── The roll of a proposal ─────────────────────────────────────────────────────────────────────

// A body rather than a layout: its length is a function of its own two counts. Both are bounded
// before an entry is read — the frames by what a window applies, the parts by the width of the
// field and then by the length the bytes actually have — so the door compares one length, computed
// from the head, before it reads anything after the head.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Roll {
    pub window: u64,
    pub frames: Vec<[u8; 32]>,
    pub parts: Vec<[u8; 32]>,
}

impl Roll {
    pub const NAME: &'static str = "roll";
    // The window, the count of frames and the count of parts, at the widths of their types.
    const HEAD: usize = size_of::<u64>() + size_of::<u32>() + size_of::<u64>();

    // `roll_len` of the set, or nothing where the counts reach past what a length can hold.
    pub fn len_of(frames: u64, parts: u64) -> Option<usize> {
        let entries = frames.checked_add(parts)?;
        let tail = entries.checked_mul(32)?;
        usize::try_from(tail).ok()?.checked_add(Self::HEAD)
    }

    fn rule(&self) -> Result<(), ObjectError> {
        if self.frames.len() > count_of("frames_per_window")
            || !self.parts.windows(2).all(|pair| pair[0] < pair[1])
        {
            return Err(ObjectError::Roll);
        }
        Ok(())
    }

    pub fn encode(&self) -> Vec<u8> {
        let mut out = Vec::with_capacity(Self::HEAD + 32 * (self.frames.len() + self.parts.len()));
        out.extend_from_slice(&self.window.to_le_bytes());
        out.extend_from_slice(&(self.frames.len() as u32).to_le_bytes());
        out.extend_from_slice(&(self.parts.len() as u64).to_le_bytes());
        for entry in self.frames.iter().chain(self.parts.iter()) {
            out.extend_from_slice(entry);
        }
        out
    }

    // The one door: the head is read, the length its counts give is compared with the length the
    // bytes have, and only then is an entry read.
    pub fn parse(bytes: &[u8]) -> Result<Self, ObjectError> {
        if bytes.len() < Self::HEAD {
            return Err(ObjectError::Length {
                expected: Self::HEAD,
                found: bytes.len(),
            });
        }
        let at = &mut 0usize;
        let window = take_u64(bytes, at);
        let frames = u64::from(take_u32(bytes, at));
        let parts = take_u64(bytes, at);
        if frames > count_of("frames_per_window") as u64 {
            return Err(ObjectError::Roll);
        }
        let expected = Self::len_of(frames, parts).ok_or(ObjectError::Roll)?;
        if bytes.len() != expected {
            return Err(ObjectError::Length {
                expected,
                found: bytes.len(),
            });
        }
        let mut entry = || <[u8; 32] as Field>::read(bytes, at);
        let frames = (0..frames).map(|_| entry()).collect();
        let parts = (0..parts).map(|_| entry()).collect();
        let roll = Self {
            window,
            frames,
            parts,
        };
        roll.rule()?;
        Ok(roll)
    }

    // The bytes of a roll, handed out only where it answers its rule.
    pub fn bytes(&self) -> Result<Vec<u8>, ObjectError> {
        self.rule()?;
        Ok(self.encode())
    }

    // `roll_id` of the set: the identifier the proposal carries in its field `roll`.
    pub fn id(&self) -> Result<[u8; 32], ObjectError> {
        Ok(super::identifier(mt_codec::domain::MT_ROLL, &self.bytes()?))
    }
}

// ── The three objects of a name, and the three of a channel ────────────────────────────────────

layout! {
    /// A commitment carries thirty-two bytes and nothing else: it names no slot, so nothing about
    /// it says which name was meant until a reveal arrives. The two spaces share this shape.
    SlotCommit, "commitment over a slot", {
        commitment: [u8; 32],
    }
}

layout! {
    SlotRenew, "renewal of a slot", {
        slot: [u8; 32],
        link: [u8; 32],
    }
}

// The name field holds `name_length` bytes of the normalized name followed by zeros to the fixed
// width, and every derivation reads the first `name_length` bytes: the padding enters no hash.
fn name_field() -> usize {
    count_of("name_max_length")
}

// What both reveals ask of their name field before either becomes an object: the stated length
// fits, the padding is zero, and what stands in front of it is a name of this protocol by the one
// rule that decides that. A reveal carrying anything else is refused where it arrives — the set
// says a name outside the alphabet, the bounds or the leading-letter rule is refused **before** a
// slot is derived from it, and a door that read the field and left the rule to a later caller
// would be the place that promise breaks.
fn named(name_length: u8, name: &[u8]) -> Result<(), ObjectError> {
    let length = usize::from(name_length);
    if length > name.len() {
        return Err(ObjectError::Name);
    }
    if name[length..].iter().any(|b| *b != 0) {
        return Err(ObjectError::Name);
    }
    if !mt_derive::name::is_normalized(&name[..length]) {
        return Err(ObjectError::Name);
    }
    Ok(())
}

fn named_of_name(value: &NameReveal) -> Result<(), ObjectError> {
    named(value.name_length, &value.name)
}

fn named_of_channel(value: &ChannelReveal) -> Result<(), ObjectError> {
    named(value.name_length, &value.name)
}

layout! {
    NameReveal, "reveal of a name", checked by named_of_name, {
        name_length: u8,
        name: bytes(name_field()),
        blind: [u8; 32],
        contact_root: bytes(size::KEM_PUBLIC_KEY),
    }
}

layout! {
    ChannelReveal, "reveal of a channel", checked by named_of_channel, {
        name_length: u8,
        name: bytes(name_field()),
        blind: [u8; 32],
        channel_root: bytes(size::SIGNING_PUBLIC_KEY),
        suite_id: u16,
    }
}

impl NameReveal {
    // The normalized name is the first `name_length` bytes; the padding is zero and enters no
    // hash. A value that came through `parse` has already answered for all of it; a value a caller
    // assembled by hand has not, so the rule is asked here too and the answer is nothing rather
    // than a slot.
    pub fn normalized(&self) -> Option<&[u8]> {
        named(self.name_length, &self.name).ok()?;
        Some(&self.name[..usize::from(self.name_length)])
    }
}

impl ChannelReveal {
    pub fn normalized(&self) -> Option<&[u8]> {
        named(self.name_length, &self.name).ok()?;
        Some(&self.name[..usize::from(self.name_length)])
    }
}

// ── A publication of a channel ─────────────────────────────────────────────────────────────────

layout! {
    ChannelPublication, "publication of a channel", {
        slot: [u8; 32],
        window: u64,
        previous: [u8; 32],
        body_root: [u8; 32],
    } and a signature
}

// ── The committed record of a person ───────────────────────────────────────────────────────────

// The width of the bitmap a record holds: `max_entry_segments`, the most segments any gate demands.
fn continuity_width() -> Option<u32> {
    scalar("max_entry_segments")
        .and_then(|n| u32::try_from(n).ok())
        .filter(|&n| n != 0 && n <= u64::BITS)
}

// The low `count` bits of a bitmap: the segments of a period of `count` ending with the newest.
fn low_bits(count: u32) -> u64 {
    let older = u64::BITS.saturating_sub(count);
    u64::MAX.checked_shr(older).unwrap_or(0)
}

fn record_continuity(record: &Record) -> Result<(), ObjectError> {
    let maximum = continuity_width().ok_or(ObjectError::RecordContinuity)?;
    if record.segment_bitmap.checked_shr(maximum).unwrap_or(0) != 0 {
        return Err(ObjectError::RecordContinuity);
    }
    Ok(())
}

layout! {
    /// The record is a preimage and never appears on the wire or in state; only its commitment
    /// does. Its field set **awaits Canon** — it freezes with the one open link the Constitution
    /// names — so an implementation reproduces the order and the widths and claims no conformance
    /// over them.
    Record, "committed record of a person", checked by record_continuity, {
        segment_bitmap: u64,
        last_active_segment: u32,
        opened_window: u64,
        own_height: u32,
        operator_nf: [u8; 32],
        fabric_root: [u8; 32],
        suite_id: u16,
        current_pubkey: bytes(size::SIGNING_PUBLIC_KEY),
        blind: [u8; 32],
    }
}

impl Record {
    // What a gate compares is the number of segments lived, never a run of them. The rules of
    // continuity read it (Canon, "The rules of continuity", rules 2 and 3; constitution records 297
    // and 300). Bit `i` stands for the segment `last_active_segment - i`, so the newest is bit 0.
    // The bitmap is shifted left by the distance from the segment it was written against to the
    // current one, and only the low `in_force` bits are counted: the segments of the period in force,
    // which ends with the current segment. A bitmap read without the shift measures continuity
    // against a past that has moved. One read without the mask counts segments lived before the
    // period began.
    pub fn segments_lived(&self, current_segment: u32, in_force: u32) -> u32 {
        // Refuse reserved bits before shifting: otherwise an invented bit can
        // enter the permitted region merely by waiting. In-memory constructors
        // have not necessarily passed through the layout decoder.
        let Some(width) = continuity_width() else {
            return 0;
        };
        if record_continuity(self).is_err() || current_segment < self.last_active_segment {
            return 0;
        }
        let distance = current_segment - self.last_active_segment;
        // A period wider than the bitmap reads no segment the bitmap could not have kept: an
        // action drops what passes the width, and a reading does not count it either.
        let shifted = self.segment_bitmap.checked_shl(distance).unwrap_or(0);
        (shifted & low_bits(in_force.min(width))).count_ones()
    }

    // The bitmap and the segment an action applied in `segment` leaves (rule 2). The bitmap shifts
    // left by the distance from the segment it was written against, bit 0 is set for the segment
    // acted in, and whatever passes the width of the bitmap leaves it. An action in the segment
    // already written changes nothing. An action in a segment before it is no lawful transition and
    // yields nothing, since `last_active_segment` never decreases.
    pub fn continuity_after_action(&self, segment: u32) -> Option<(u64, u32)> {
        let width = continuity_width()?;
        if record_continuity(self).is_err() || segment < self.last_active_segment {
            return None;
        }
        let distance = segment - self.last_active_segment;
        let shifted = self.segment_bitmap.checked_shl(distance).unwrap_or(0);
        Some(((shifted | 1) & low_bits(width), segment))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // The totals the set writes beside each layout. They are asserted rather than restated: a width
    // that moves in one place and not the other fails here, and the family carrying a proof is
    // marked because it awaits the reference artifact.
    #[test]
    fn no_total_is_written_twice_and_every_one_of_them_stands() {
        // The value of each total lives in the set and nowhere else: the gate compares the code
        // against every place the set states it, and the test below compares the code against its
        // own arithmetic. A list of numbers here would be a third copy of what the set owns, and a
        // third copy is what drifts — this file held one, and it drifted the first time a length of
        // the set moved. What is checked here instead is that every total is a positive number and
        // that no two objects of different shapes were given one length by a copied line.
        let totals = [
            (Proposal::NAME, Proposal::expected_len()),
            (Frame::NAME, Frame::expected_len()),
            (Confirmation::NAME, Confirmation::expected_len()),
            (LightAttestation::NAME, LightAttestation::expected_len()),
            (Candidacy::NAME, Candidacy::expected_len()),
            (Beacon::NAME, Beacon::expected_len()),
            (SlotCommit::NAME, SlotCommit::expected_len()),
            (SlotRenew::NAME, SlotRenew::expected_len()),
            (NameReveal::NAME, NameReveal::expected_len()),
            (ChannelReveal::NAME, ChannelReveal::expected_len()),
            (ChannelPublication::NAME, ChannelPublication::expected_len()),
            (Ballot::NAME, Ballot::expected_len()),
            (Pledge::NAME, Pledge::expected_len()),
        ];
        for (name, total) in totals {
            assert!(total > 0, "the total of {name} is zero");
        }
        let carrying: Vec<usize> = totals
            .iter()
            .filter(|(_, total)| *total > super::super::PRESENCE_PROOF_LEN)
            .map(|(_, total)| *total)
            .collect();
        let mut distinct = carrying.clone();
        distinct.sort_unstable();
        distinct.dedup();
        assert_eq!(
            carrying.len(),
            distinct.len(),
            "two objects carrying a proof share one total, which one copied line would explain"
        );
    }

    // The arithmetic of each total, from the sizes and the parameters rather than from the number
    // above: this is what catches a total that was written by hand and a size that moved.
    #[test]
    fn every_total_is_the_sum_of_the_fields_the_set_names() {
        use mt_codec::size;
        let censuses = count_of("standing_censuses");
        assert_eq!(
            Proposal::expected_len(),
            8 + 4
                + 10 * 32
                + 8
                + 32
                + 8
                + censuses * (32 + 8)
                + 2
                + size::SIGNING_PUBLIC_KEY
                + super::super::PRESENCE_PROOF_LEN
                + size::SIGNATURE
        );
        // The decided fields stand from the height through the suite, the census among them.
        assert_eq!(
            super::super::PROPOSAL_DECIDED_LEN,
            8 + 4 + 9 * 32 + 8 + 32 + 8 + censuses * (32 + 8) + 2
        );
        assert_eq!(Ballot::expected_len(), 8 + 32 + 8 + super::super::PROOF_LEN);
        assert_eq!(
            Pledge::expected_len(),
            8 + 4
                + 32
                + 4
                + 32
                + 32
                + 2
                + size::SIGNING_PUBLIC_KEY
                + super::super::PRESENCE_PROOF_LEN
                + size::SIGNATURE
        );
        assert_eq!(
            LightAttestation::expected_len(),
            8 + 2 + 64 + 32 + 32 + 2 + size::SIGNING_PUBLIC_KEY + size::SIGNATURE
        );
        // The heavy is the light with `line_value` and the proof (record 309).
        assert_eq!(
            Confirmation::expected_len(),
            LightAttestation::expected_len() + 32 + super::super::PRESENCE_PROOF_LEN
        );
        assert_eq!(Beacon::expected_len(), 8 + 1 + 4 + 32 + 32 + 8 + 8);
    }

    fn a_proposal() -> Proposal {
        Proposal {
            window: 1000,
            protocol_version: (3 << 16) | 2,
            previous: [0x11; 32],
            final_beacon: [0x22; 32],
            note_root: [0x33; 32],
            nullifier_root: [0x44; 32],
            record_root: [0x55; 32],
            machine_root: [0x66; 32],
            admitted_root: [0x77; 32],
            credited_root: [0xAA; 32],
            operations_root: [0x88; 32],
            roll: [0xBB; 32],
            admitted_count: 3,
            cement_aggregate: [0x99; 32],
            cement_count: 2,
            census: (0..count_of("standing_censuses"))
                .map(|at| Census {
                    root: [0xC0 + at as u8; 32],
                    count: at as u64,
                })
                .collect(),
            suite_id: 1,
            runner_pubkey: vec![0xA1; mt_codec::size::SIGNING_PUBLIC_KEY],
            ticket_proof: vec![0x00; super::super::PRESENCE_PROOF_LEN],
            signature: vec![0xF0; mt_codec::size::SIGNATURE],
        }
    }

    // The identifier of a proposal stands over the fields the window decided. The named wrong
    // implementations: one hashing the whole object, which agrees with the serialization hash the
    // set freezes and disagrees with the identifier — a name over proof bytes is a name a runner
    // redraws by reproving — and one hashing through the final beacon or the runner's key, under
    // which two branches or two runners of one decision publish two names and the cement of the next
    // window parts between them.
    #[test]
    fn the_identifier_of_a_proposal_ignores_the_runner_the_proof_and_the_signature() {
        let one = a_proposal();
        let reproven = Proposal {
            ticket_proof: vec![0x5A; super::super::PRESENCE_PROOF_LEN],
            signature: vec![0x0F; mt_codec::size::SIGNATURE],
            ..a_proposal()
        };
        assert_eq!(one.id(), reproven.id());
        let another_runner = Proposal {
            runner_pubkey: vec![0xB2; mt_codec::size::SIGNING_PUBLIC_KEY],
            ..a_proposal()
        };
        assert_eq!(one.id(), another_runner.id());
        let mut through_the_beacon = one.encode();
        through_the_beacon.truncate(super::super::PROPOSAL_DECIDED_LEN + 32);
        assert_ne!(
            Ok(super::super::identifier(
                mt_codec::domain::MT_PROPOSAL,
                &through_the_beacon
            )),
            one.id(),
            "a name over the final beacon is another name"
        );
        // The beacon a runner closed on is where the window decided, not what it decided: two
        // branches of the versions of a round carrying one cement are one name.
        let another_branch = Proposal {
            final_beacon: [0x23; 32],
            ..a_proposal()
        };
        assert_eq!(one.id(), another_branch.id());
        let moved = Proposal {
            cement_aggregate: [0x9A; 32],
            ..a_proposal()
        };
        assert_ne!(one.id(), moved.id());
        // The two public facts the windows after it stand on are of the name as well.
        let recounted = Proposal {
            cement_count: 3,
            ..a_proposal()
        };
        assert_ne!(one.id(), recounted.id());
        // And the standing the window two on is counted over: a census moved is another decision.
        let mut recensused = a_proposal();
        recensused.census[3].count += 1;
        assert_ne!(one.id(), recensused.id());
        let whole = super::super::identifier(mt_codec::domain::MT_PROPOSAL, &one.encode());
        assert_ne!(
            Ok(whole),
            one.id(),
            "a name over the whole object is another name"
        );
    }

    fn a_confirmation() -> Confirmation {
        Confirmation {
            window: 1000,
            attested: vec![[0x10; 32], [0x20; 32]],
            part_nullifier: [0x30; 32],
            round_nullifier: [0x40; 32],
            line_value: [0x41; 32],
            suite_id: 1,
            answering_key: vec![0xA1; mt_codec::size::SIGNING_PUBLIC_KEY],
            proof: vec![0x00; super::super::PRESENCE_PROOF_LEN],
            signature: vec![0xF0; mt_codec::size::SIGNATURE],
        }
    }

    fn a_frame() -> Frame {
        let spends = mt_genesis::scalar("spends_per_frame").expect("named") as usize;
        let inputs = mt_genesis::scalar("spend_inputs").expect("named") as usize;
        let outputs = mt_genesis::scalar("spend_outputs").expect("named") as usize;
        Frame {
            spends: (0..spends)
                .map(|s| Spend {
                    nullifiers: (0..inputs).map(|i| [(s * 8 + i) as u8; 32]).collect(),
                    commitments: (0..outputs)
                        .map(|o| [(0x80 + s * 8 + o) as u8; 32])
                        .collect(),
                    rate_nullifier: [(0xC0 + s) as u8; 32],
                })
                .collect(),
            proof: vec![0x00; super::super::PROOF_LEN],
        }
    }

    #[test]
    fn every_layout_round_trips_and_answers_its_own_length() {
        macro_rules! round_trip {
            ($value:expr, $t:ty) => {{
                let value = $value;
                let bytes = value.encode();
                assert_eq!(bytes.len(), <$t>::expected_len(), "{}", <$t>::NAME);
                let back = <$t>::parse(&bytes).expect(<$t>::NAME);
                assert_eq!(back, value, "{}", <$t>::NAME);
                assert_eq!(back.encode(), bytes, "{}", <$t>::NAME);
            }};
        }
        round_trip!(a_proposal(), Proposal);
        round_trip!(a_confirmation(), Confirmation);
        round_trip!(a_frame(), Frame);
        round_trip!(
            LightAttestation {
                window: 1000,
                attested: vec![[0x10; 32], [0x20; 32]],
                part_nullifier: [0x30; 32],
                round_nullifier: [0x40; 32],
                suite_id: 1,
                answering_key: vec![0xA1; mt_codec::size::SIGNING_PUBLIC_KEY],
                signature: vec![0xF0; mt_codec::size::SIGNATURE],
            },
            LightAttestation
        );
        round_trip!(
            Candidacy {
                naming_half: [0x7A; 32],
                window: 1000,
                node_commit: [0x11; 32],
                operator_nullifier: [0x22; 32],
                suite_id: 1,
                proof: vec![0x00; super::super::PROOF_LEN],
            },
            Candidacy
        );
        round_trip!(
            Beacon {
                window: 1000,
                chain: 0,
                round: 7,
                previous: [0xEE; 32],
                cement_aggregate: [0x11; 32],
                cement_count: 5,
                cement_votes: 2,
            },
            Beacon
        );
        round_trip!(
            Ballot {
                window: 1000,
                part_nullifier: [0x30; 32],
                votes: 3,
                proof: vec![0x00; super::super::PROOF_LEN],
            },
            Ballot
        );
        round_trip!(
            SlotCommit {
                commitment: [0x99; 32]
            },
            SlotCommit
        );
        round_trip!(
            SlotRenew {
                slot: [0x11; 32],
                link: [0x22; 32]
            },
            SlotRenew
        );
        round_trip!(
            NameReveal {
                name_length: 5,
                name: {
                    let mut field = vec![0u8; name_field()];
                    field[..5].copy_from_slice(b"alice");
                    field
                },
                blind: [0xDD; 32],
                contact_root: vec![0xCC; mt_codec::size::KEM_PUBLIC_KEY],
            },
            NameReveal
        );
        round_trip!(
            ChannelReveal {
                name_length: 5,
                name: {
                    let mut field = vec![0u8; name_field()];
                    field[..5].copy_from_slice(b"alice");
                    field
                },
                blind: [0xDD; 32],
                channel_root: vec![0xA1; mt_codec::size::SIGNING_PUBLIC_KEY],
                suite_id: 1,
            },
            ChannelReveal
        );
        round_trip!(
            ChannelPublication {
                slot: [0x21; 32],
                window: 1000,
                previous: [0xAB; 32],
                body_root: [0xCD; 32],
                signature: vec![0xF0; mt_codec::size::SIGNATURE],
            },
            ChannelPublication
        );
        round_trip!(
            Record {
                segment_bitmap: 0b1011,
                last_active_segment: 3,
                opened_window: 1000,
                own_height: 4,
                operator_nf: [0x22; 32],
                fabric_root: [0x77; 32],
                suite_id: 1,
                current_pubkey: vec![0xA1; mt_codec::size::SIGNING_PUBLIC_KEY],
                blind: [0xBB; 32],
            },
            Record
        );
        round_trip!(a_pledge(3, 1), Pledge);
    }

    fn a_pledge(attempt: u32, since: u32) -> Pledge {
        Pledge {
            window: 1000,
            attempt,
            name: [0x4E; 32],
            since,
            part_nullifier: [0x30; 32],
            line_value: [0x31; 32],
            suite_id: 1,
            answering_key: vec![0xA1; mt_codec::size::SIGNING_PUBLIC_KEY],
            proof: vec![0x5A; super::super::PRESENCE_PROOF_LEN],
            signature: vec![0xF0; mt_codec::size::SIGNATURE],
        }
    }

    // `line_value` is four canonical words: a word at the modulus, or past it, is refused written
    // and read, whichever of the four it stands in. The wrong implementation refused: one reading
    // the words modulo the prime, which takes `P` for zero.
    #[test]
    fn a_pledge_carries_its_line_value_in_canonical_words_only() {
        let p = mt_proof::field::P.to_le_bytes();
        for at in 0..4 {
            for word in [p, u64::MAX.to_le_bytes()] {
                let mut pledge = a_pledge(3, 1);
                pledge.line_value[at * 8..at * 8 + 8].copy_from_slice(&word);
                let bytes = pledge.encode();
                assert_eq!(pledge.bytes(), Err(ObjectError::LineValue), "word {at}");
                assert_eq!(
                    Pledge::parse(&bytes),
                    Err(ObjectError::LineValue),
                    "word {at}"
                );
            }
        }
        let mut below = a_pledge(3, 1);
        below.line_value[..8].copy_from_slice(&(mt_proof::field::P - 1).to_le_bytes());
        assert!(below.bytes().is_ok() && Pledge::parse(&below.encode()).is_ok());
    }

    // The same rule on the confirmation, whose `line_value` is the line of the open slot of attempt
    // zero (record 309): a word at the modulus is refused written and read.
    #[test]
    fn a_confirmation_carries_its_line_value_in_canonical_words_only() {
        let p = mt_proof::field::P.to_le_bytes();
        for at in 0..4 {
            let mut held = a_confirmation();
            held.line_value[at * 8..at * 8 + 8].copy_from_slice(&p);
            let bytes = held.encode();
            assert_eq!(held.bytes(), Err(ObjectError::LineValue), "word {at}");
            assert_eq!(
                Confirmation::parse(&bytes),
                Err(ObjectError::LineValue),
                "word {at}"
            );
        }
        assert!(a_confirmation().bytes().is_ok());
    }

    // A pledge stands on its own attempt, an earlier one or none, and never opens attempt zero. The
    // wrong implementations refused: one reading `since` without bounding it by the attempt (a pledge
    // standing on a quorum nobody has seen yet), and one admitting an open pledge of attempt zero
    // beside the heavy attestation, which is that attempt's one open pledge.
    #[test]
    fn a_pledge_stands_on_its_own_attempt_an_earlier_one_or_none() {
        let none = super::super::STANDS_ON_NONE;
        for (attempt, since, lawful) in [
            (0, 0, true),
            (3, 3, true),
            (3, 1, true),
            (3, none, true),
            (0, none, false),
            (3, 4, false),
            (none, none, false),
            (none, 0, false),
        ] {
            let pledge = a_pledge(attempt, since);
            let written = pledge.bytes();
            let read = Pledge::parse(&pledge.encode());
            if lawful {
                assert!(written.is_ok() && read.is_ok(), "{attempt} on {since}");
            } else {
                assert_eq!(written, Err(ObjectError::Since), "{attempt} on {since}");
                assert_eq!(read, Err(ObjectError::Since), "{attempt} on {since}");
            }
        }
        assert!(a_pledge(3, 3).is_closing() && !a_pledge(3, 1).is_closing());
        assert_eq!(a_pledge(3, 1).stands_on(), Some(1));
        assert_eq!(a_pledge(3, none).stands_on(), None);
    }

    fn a_roll() -> Roll {
        Roll {
            window: 1000,
            frames: vec![[0x0F; 32], [0x0A; 32], [0x0C; 32]],
            parts: vec![[0x31; 32], [0x32; 32]],
        }
    }

    // A roll is read through one door that compares the length its head states before an entry, and
    // its identifier holds the order of the frames. The wrong implementations refused: one sorting the
    // frames (the order they applied is what a replay reproduces, so two orders are two rolls), one
    // writing the parts before the frames, and one reading entries past a head whose counts the bytes
    // do not carry.
    #[test]
    fn a_roll_is_its_frames_in_order_then_its_parts_ascending() {
        let roll = a_roll();
        let bytes = roll.bytes().expect("a lawful roll");
        assert_eq!(Roll::len_of(3, 2), Some(bytes.len()));
        assert_eq!(bytes.len(), 20 + 32 * 5);
        assert_eq!(Roll::parse(&bytes), Ok(roll.clone()));
        let id = roll.id().expect("an identifier");
        let mut sorted = roll.clone();
        sorted.frames.sort_unstable();
        assert_ne!(sorted.id().expect("an identifier"), id);
        let swapped = Roll {
            window: roll.window,
            frames: roll.parts.clone(),
            parts: vec![[0x0A; 32], [0x0C; 32], [0x0F; 32]],
        };
        assert_ne!(swapped.id().expect("an identifier"), id);
        let mut short = bytes.clone();
        short.pop();
        assert_eq!(
            Roll::parse(&short),
            Err(ObjectError::Length {
                expected: bytes.len(),
                found: bytes.len() - 1
            })
        );
        assert!(matches!(
            Roll::parse(&bytes[..19]),
            Err(ObjectError::Length { .. })
        ));
        let mut claims_more = bytes.clone();
        claims_more[12..20].copy_from_slice(&u64::MAX.to_le_bytes());
        assert_eq!(Roll::parse(&claims_more), Err(ObjectError::Roll));
    }

    // A roll naming more frames than a window applies, or parts that do not ascend, is refused where it
    // is written and where it is read.
    #[test]
    fn a_roll_beyond_a_window_or_with_parts_out_of_order_is_refused() {
        let most = count_of("frames_per_window");
        let full = Roll {
            window: 1000,
            frames: vec![[0x01; 32]; most],
            parts: Vec::new(),
        };
        assert!(full.bytes().is_ok());
        let over = Roll {
            frames: vec![[0x01; 32]; most + 1],
            ..full.clone()
        };
        assert_eq!(over.bytes(), Err(ObjectError::Roll));
        assert_eq!(Roll::parse(&over.encode()), Err(ObjectError::Roll));
        let mut descending = a_roll();
        descending.parts.reverse();
        assert_eq!(descending.bytes(), Err(ObjectError::Roll));
        assert_eq!(Roll::parse(&descending.encode()), Err(ObjectError::Roll));
        let mut repeated = a_roll();
        repeated.parts[1] = repeated.parts[0];
        assert_eq!(repeated.bytes(), Err(ObjectError::Roll));
    }

    // A ballot casting no vote, or more than a standing holds units, is refused where it is written
    // and where it is read: the named wrong implementation takes the count off the wire and lets a
    // ballot of nought votes or of more votes than census windows reach a cement.
    #[test]
    fn a_ballot_casts_between_one_vote_and_a_unit_of_every_census() {
        let censuses = count_of("standing_censuses") as u64;
        let ballot = |votes: u64| Ballot {
            window: 1000,
            part_nullifier: [0x30; 32],
            votes,
            proof: vec![0x00; super::super::PROOF_LEN],
        };
        assert!(ballot(1).bytes().is_ok());
        assert!(ballot(censuses).bytes().is_ok());
        for votes in [0, censuses + 1, u64::MAX] {
            assert_eq!(ballot(votes).bytes(), Err(ObjectError::Votes), "{votes}");
            assert_eq!(
                Ballot::parse(&ballot(votes).encode()),
                Err(ObjectError::Votes)
            );
        }
    }

    #[test]
    fn an_object_of_the_wrong_length_is_refused_before_it_is_parsed() {
        let bytes = a_proposal().encode();
        let expected = Proposal::expected_len();
        assert_eq!(
            Proposal::parse(&bytes[..bytes.len() - 1]),
            Err(ObjectError::Length {
                expected,
                found: expected - 1
            })
        );
        let mut longer = bytes.clone();
        longer.push(0);
        assert_eq!(
            Proposal::parse(&longer),
            Err(ObjectError::Length {
                expected,
                found: expected + 1
            })
        );
        assert_eq!(
            Proposal::parse(&[]),
            Err(ObjectError::Length { expected, found: 0 })
        );
        // Every fixed layout answers the same way, and none of them reads a byte to say so.
        assert!(Frame::parse(&[0u8; 3]).is_err());
        assert!(Confirmation::parse(&[0u8; 3]).is_err());
        assert!(Candidacy::parse(&[0u8; 3]).is_err());
        assert!(Beacon::parse(&[0u8; 3]).is_err());
        assert!(SlotCommit::parse(&[0u8; 31]).is_err());
        assert!(SlotRenew::parse(&[0u8; 63]).is_err());
        assert!(NameReveal::parse(&[0u8; 3]).is_err());
        assert!(ChannelReveal::parse(&[0u8; 3]).is_err());
        assert!(ChannelPublication::parse(&[0u8; 3]).is_err());
        assert!(Record::parse(&[0u8; 3]).is_err());
    }

    #[test]
    fn a_count_of_attested_identifiers_other_than_two_is_refused() {
        let mut bytes = a_confirmation().encode();
        // The count field stands after the window.
        bytes[8] = 3;
        assert!(Confirmation::parse(&bytes).is_err());
    }

    // The rule of an object is answered where the object is written as well as where it is read.
    // The named wrong implementation this refuses is the one that checks on the reading side
    // alone: under it a machine assembles a confirmation whose two attested identifiers stand in
    // the wrong order, signs it, takes an identifier over it and publishes it, and only the far
    // side refuses — which is a machine of this protocol producing an object of no protocol.
    #[test]
    fn an_object_that_breaks_its_rule_is_refused_where_it_is_written() {
        let held = a_confirmation();
        assert!(held.bytes().is_ok());
        let mut wrong = a_confirmation();
        wrong.attested.reverse();
        assert_eq!(wrong.rule(), Err(ObjectError::Attested));
        assert_eq!(wrong.bytes(), Err(ObjectError::Attested));
        assert_eq!(wrong.signed_scope(), Err(ObjectError::Attested));
        // And a repeat is refused the same way, on both sides.
        let mut repeated = a_confirmation();
        repeated.attested[1] = repeated.attested[0];
        assert_eq!(repeated.bytes(), Err(ObjectError::Attested));
    }

    #[test]
    fn signed_scope_is_every_byte_but_the_signature() {
        let proposal = a_proposal();
        let bytes = proposal.encode();
        let scope = proposal
            .signed_scope()
            .expect("a proposal of its own width");
        assert_eq!(scope.len(), bytes.len() - mt_codec::size::SIGNATURE);
        assert_eq!(scope[..], bytes[..scope.len()]);
        // And every layout that carries one answers the same way, rather than the one a test
        // happened to name: the width a signature covers is the width of the object less the
        // signature, at all four of them.
        for (whole, scope) in [
            (Proposal::expected_len(), Proposal::scope_len()),
            (Confirmation::expected_len(), Confirmation::scope_len()),
            (
                LightAttestation::expected_len(),
                LightAttestation::scope_len(),
            ),
            (
                ChannelPublication::expected_len(),
                ChannelPublication::scope_len(),
            ),
        ] {
            assert_eq!(scope, whole - mt_codec::size::SIGNATURE);
        }
        // A layout carrying none answers with its whole, and the two answers are one rule.
        assert_eq!(Beacon::scope_len(), Beacon::expected_len());
        assert_eq!(Frame::scope_len(), Frame::expected_len());
        // An object with no signature to leave out is its whole scope.
        let candidacy = Candidacy {
            naming_half: [0x7A; 32],
            window: 1,
            node_commit: [0; 32],
            operator_nullifier: [0; 32],
            suite_id: 1,
            proof: vec![0; super::super::PROOF_LEN],
        };
        assert_eq!(candidacy.signed_scope(), Ok(candidacy.encode()));
    }

    #[test]
    fn an_object_of_the_wrong_width_yields_no_scope_and_no_identifier() {
        // The fields of a layout are open, so a value can be assembled out of parts of another
        // width. Such a value is not an object of this protocol, and every door that would hand its
        // bytes onward says so: it neither cuts a scope out of it nor takes an identifier over it,
        // and above all it does not cut a scope out of bytes shorter than the width the
        // declaration gives — the width is kept, never subtracted.
        let empty = Proposal {
            runner_pubkey: Vec::new(),
            ticket_proof: Vec::new(),
            signature: Vec::new(),
            ..a_proposal()
        };
        let expected = Proposal::expected_len();
        // The fixed fields: the window, the version, ten digests, the admitted count, the cement
        // pair, the census of the standing — a root and a count per census window — and the suite.
        let fixed = 8 + 4 + 10 * 32 + 8 + 32 + 8 + count_of("standing_censuses") * (32 + 8) + 2;
        assert_eq!(empty.encode().len(), fixed);
        assert_eq!(
            empty.bytes(),
            Err(ObjectError::Length {
                expected,
                found: fixed
            })
        );
        assert!(empty.signed_scope().is_err());
    }

    #[test]
    fn a_frame_carries_no_root_no_window_and_no_repeat_of_a_nullifier() {
        let frame = a_frame();
        assert!(frame.nullifiers_are_distinct());
        let mut repeated = frame.clone();
        let first = repeated.spends[0].nullifiers[0];
        repeated.spends[1].nullifiers[0] = first;
        assert!(!repeated.nullifiers_are_distinct());
        // The layout holds spends and a proof and nothing else: its length leaves no room for a
        // root or a window.
        let (spends, inputs, outputs) = (
            count_of("spends_per_frame"),
            count_of("spend_inputs"),
            count_of("spend_outputs"),
        );
        assert_eq!(
            Frame::expected_len(),
            spends * (inputs + outputs + 1) * 32 + super::super::PROOF_LEN
        );
    }

    #[test]
    fn a_correct_total_length_does_not_hide_malformed_nested_runs() {
        let mut frame = a_frame();
        let moved = frame.spends[0].nullifiers.pop().unwrap();
        frame.spends[1].nullifiers.push(moved);
        assert_eq!(frame.encode().len(), Frame::expected_len());
        assert_eq!(frame.bytes(), Err(ObjectError::FrameShape));
        assert!(frame.id().is_err());
        let mut frame = a_frame();
        let moved = frame.spends[0].commitments.pop().unwrap();
        frame.spends[1].commitments.push(moved);
        assert_eq!(frame.bytes(), Err(ObjectError::FrameShape));
    }

    #[test]
    fn the_attested_pair_is_canonical_only_when_it_ascends() {
        assert!(attested_is_canonical(&[[0x10; 32], [0x20; 32]]));
        assert!(!attested_is_canonical(&[[0x20; 32], [0x10; 32]]));
        assert!(!attested_is_canonical(&[[0x10; 32], [0x10; 32]]));
    }

    #[test]
    fn the_version_of_a_proposal_reads_as_a_major_and_a_minor() {
        let proposal = a_proposal();
        assert_eq!(proposal.major(), 3);
        assert_eq!(proposal.minor(), 2);
        // A comparison of the whole field is what both rules of the set read.
        let older = Proposal {
            protocol_version: (3 << 16) | 1,
            ..a_proposal()
        };
        assert!(older.protocol_version < proposal.protocol_version);
    }

    #[test]
    fn the_padding_of_a_name_enters_no_hash_and_a_dirty_field_is_refused() {
        let mut field = vec![0u8; name_field()];
        field[..5].copy_from_slice(b"alice");
        let reveal = NameReveal {
            name_length: 5,
            name: field.clone(),
            blind: [0xDD; 32],
            contact_root: vec![0xCC; mt_codec::size::KEM_PUBLIC_KEY],
        };
        assert_eq!(reveal.normalized(), Some(&b"alice"[..]));
        let mut dirty = field;
        dirty[10] = 1;
        let smuggled = NameReveal {
            name: dirty,
            ..reveal.clone()
        };
        assert_eq!(smuggled.normalized(), None);
        let overlong = NameReveal {
            name_length: 200,
            ..reveal
        };
        assert_eq!(overlong.normalized(), None);
    }

    #[test]
    fn a_pair_of_attested_identifiers_that_does_not_ascend_is_refused_at_the_door() {
        // The rule stood as a function nothing called; it stands at the door now, so an object
        // whose pair descends or repeats never becomes an object at all — two sortings of one
        // attestation would otherwise be two identifiers of it.
        let mut descending = a_confirmation();
        descending.attested = vec![[0x20; 32], [0x10; 32]];
        assert_eq!(
            Confirmation::parse(&descending.encode()),
            Err(ObjectError::Attested)
        );
        let mut repeated = a_confirmation();
        repeated.attested = vec![[0x10; 32], [0x10; 32]];
        assert_eq!(
            Confirmation::parse(&repeated.encode()),
            Err(ObjectError::Attested)
        );
        let light = LightAttestation {
            window: 1000,
            attested: vec![[0x20; 32], [0x10; 32]],
            part_nullifier: [0x30; 32],
            round_nullifier: [0x40; 32],
            suite_id: 1,
            answering_key: vec![0xA1; mt_codec::size::SIGNING_PUBLIC_KEY],
            signature: vec![0xF0; mt_codec::size::SIGNATURE],
        };
        assert_eq!(
            LightAttestation::parse(&light.encode()),
            Err(ObjectError::Attested)
        );
    }

    #[test]
    fn a_reveal_carrying_anything_but_a_lawful_name_is_refused_at_the_door() {
        let lawful = |bytes: &[u8]| -> Vec<u8> {
            let mut field = vec![0u8; name_field()];
            field[..bytes.len()].copy_from_slice(bytes);
            field
        };
        let of = |length: u8, bytes: &[u8]| NameReveal {
            name_length: length,
            name: lawful(bytes),
            blind: [0xDD; 32],
            contact_root: vec![0xCC; mt_codec::size::KEM_PUBLIC_KEY],
        };
        NameReveal::parse(&of(5, b"alice").encode()).expect("a lawful name passes");
        // Shorter than the bound, outside the alphabet, not opening with a letter, of a length
        // the field does not hold, and with the padding written into: each is refused before a
        // slot could be derived from it.
        for (length, bytes) in [
            (0u8, &b""[..]),
            (3, b"abc"),
            (5, b"ab cd"),
            (5, b"1abcd"),
            (5, b"Alice"),
            (200, b"alice"),
        ] {
            assert_eq!(
                NameReveal::parse(&of(length, bytes).encode()),
                Err(ObjectError::Name),
                "{bytes:?} at length {length}"
            );
        }
        let mut dirty = of(5, b"alice");
        dirty.name[10] = 1;
        assert_eq!(NameReveal::parse(&dirty.encode()), Err(ObjectError::Name));
        // The same door on the other space of slots.
        let channel = ChannelReveal {
            name_length: 3,
            name: lawful(b"abc"),
            blind: [0xDD; 32],
            channel_root: vec![0xA1; mt_codec::size::SIGNING_PUBLIC_KEY],
            suite_id: 1,
        };
        assert_eq!(
            ChannelReveal::parse(&channel.encode()),
            Err(ObjectError::Name)
        );
    }

    fn a_record_of(segment_bitmap: u64, last_active_segment: u32) -> Record {
        Record {
            segment_bitmap,
            last_active_segment,
            opened_window: 0,
            own_height: 0,
            operator_nf: [0; 32],
            fabric_root: [0; 32],
            suite_id: 1,
            current_pubkey: vec![0; mt_codec::size::SIGNING_PUBLIC_KEY],
            blind: [0; 32],
        }
    }

    #[test]
    fn the_segments_of_a_record_are_counted_after_the_shift() {
        // Four segments lived, written against segment ten: bit 0 is segment ten and bit 3 is
        // segment seven (rule 2, records 297 and 300). With fourteen in force they all count until
        // the period, which ends with the current segment, leaves segment seven behind at twenty-one.
        let record = a_record_of(0b1111, 10);
        assert_eq!(record.segments_lived(10, 14), 4);
        assert_eq!(record.segments_lived(20, 14), 4);
        assert_eq!(record.segments_lived(21, 14), 3);
        assert_eq!(record.segments_lived(23, 14), 1);
        assert_eq!(record.segments_lived(24, 14), 0);
        // A bitmap read without the shift would answer four at every segment, which is the defect
        // the shift exists to prevent. The old reader shifted right, read the low bits as the oldest,
        // and answered nought at twenty.
        assert_ne!(record.segments_lived(24, 14), record.segments_lived(10, 14));
        // A segment before the one the bitmap is written against reads nothing.
        assert_eq!(record.segments_lived(9, 14), 0);
    }

    #[test]
    fn segments_lived_before_the_period_in_force_do_not_count() {
        // Ten segments lived, the newest of them twenty segments before the segment written against
        // (bits 20 to 29), as Agent 492 reported of the old reader: with fourteen in force none
        // count, and with the whole width in force all ten do (rule 3, records 297 and 300).
        let record = a_record_of(0b11_1111_1111 << 20, 100);
        assert_eq!(record.segments_lived(100, 14), 0);
        assert_eq!(record.segments_lived(100, 25), 5);
        assert_eq!(record.segments_lived(100, 56), 10);
        // A period wider than the bitmap counts nothing the bitmap could not have kept: at segment
        // 127 the record's segments are 71 to 80, and 71 lies past the width of fifty-six.
        assert_eq!(record.segments_lived(127, 64), 9);
        assert_eq!(record.segments_lived(100, 0), 0);
    }

    #[test]
    fn an_action_writes_its_segment_into_bit_nought() {
        // Segments ten, nine and seven lived (rule 2, records 297 and 300).
        let record = a_record_of(0b1011, 10);
        // An action in the segment already written changes nothing.
        assert_eq!(record.continuity_after_action(10), Some((0b1011, 10)));
        // Two segments on, the bitmap shifts left by two and segment twelve takes bit 0.
        assert_eq!(record.continuity_after_action(12), Some((0b10_1101, 12)));
        // A segment before the one written against is no lawful transition.
        assert_eq!(record.continuity_after_action(9), None);
        // Far enough on, every older segment has passed the width and only the new one stands.
        assert_eq!(record.continuity_after_action(10 + 56), Some((1, 66)));
        assert_eq!(record.continuity_after_action(10 + 64), Some((1, 74)));
        assert_eq!(
            record.continuity_after_action(u32::MAX),
            Some((1, u32::MAX))
        );
        // A full bitmap stays full: the oldest segment leaves as the newest enters, and the
        // successor stands inside the width the layout holds a record to.
        let width = continuity_width().expect("the Decree names it");
        let full = a_record_of(low_bits(width), 10);
        let (bitmap, last) = full.continuity_after_action(11).expect("lawful");
        assert_eq!((bitmap, last), (low_bits(width), 11));
        assert!(a_record_of(bitmap, last).bytes().is_ok());
        // What an action writes is what a gate reads: segment twelve and the three before it.
        let (bitmap, last) = record.continuity_after_action(12).expect("lawful");
        let next = a_record_of(bitmap, last);
        assert_eq!(next.segments_lived(12, 14), 4);
        assert_eq!(next.segments_lived(12, 1), 1);
        assert_eq!(next.segments_lived(12, 3), 2);
    }
}
