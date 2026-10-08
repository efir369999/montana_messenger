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
    ("proof of a window", "window_proof"),
    ("frame", "frame"),
    ("confirmation", "confirmation"),
    ("light attestation", "light_attestation"),
    ("candidacy", "candidacy"),
    ("node of the fold", "fold_node"),
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
];

// ── The proposal that closes a window ──────────────────────────────────────────────────────────

layout! {
    Proposal, "proposal", {
        window: u64,
        protocol_version: u32,
        previous: [u8; 32],
        final_beacon: [u8; 32],
        note_root: [u8; 32],
        nullifier_root: [u8; 32],
        record_root: [u8; 32],
        machine_root: [u8; 32],
        admitted_root: [u8; 32],
        operations_root: [u8; 32],
        suite_id: u16,
        runner_pubkey: bytes(size::SIGNING_PUBLIC_KEY),
        ticket_proof: bytes(super::PROOF_LEN),
    } and a signature
}

// The major component stands in the upper sixteen bits and the minor in the lower: a machine
// refuses a proposal whose major exceeds the one it implements, and one whose value stands below
// its predecessor's, so rules never roll back inside one chain.
impl Proposal {
    // The identifier of a proposal, over its deterministic fields alone, under the proposal
    // domain. `docs/Montana Canon.md`, "The proposal that closes a window".
    pub fn id(&self) -> Result<[u8; 32], ObjectError> {
        let mut bytes = self.encode();
        bytes.truncate(super::PROPOSAL_DETERMINISTIC_LEN);
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
    Frame, "frame", {
        spends: run(Spend; count_of("spends_per_frame")),
        proof: bytes(super::PROOF_LEN),
    }
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
    ordered(&value.attested)
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
        weight_commit: bytes(super::WEIGHT_COMMIT_BYTES),
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

layout! {
    /// The proof of a window, carried apart. It carries no signature and no key: a proof is judged
    /// by verifying, and its whole is its scope. `docs/Montana Canon.md`, "The proof of a window,
    /// carried apart".
    WindowProof, "proof of a window", {
        window: u64,
        proposal: [u8; 32],
        proof: bytes(super::PROOF_LEN),
    }
}

impl WindowProof {
    pub fn id(&self) -> Result<[u8; 32], ObjectError> {
        Ok(super::identifier(
            mt_codec::domain::MT_WINDOW_PROOF,
            &self.signed_scope()?,
        ))
    }
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

// ── The node of the fold ───────────────────────────────────────────────────────────────────────

layout! {
    FoldNode, "node of the fold", {
        left: [u8; 32],
        right: [u8; 32],
        commitment: bytes(super::WEIGHT_COMMIT_BYTES),
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
    Beacon, "beacon", {
        window: u64,
        chain: u8,
        round: u32,
        previous: [u8; 32],
        cement_state: bytes(super::WEIGHT_COMMIT_BYTES),
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

impl FoldNode {
    // A node of the fold carries no signature, so its scope is the whole of its canonical bytes,
    // and its identifier is taken over that under the class domain of the fold.
    pub fn id(&self) -> Result<[u8; 32], ObjectError> {
        Ok(super::identifier(
            mt_codec::domain::MT_FOLD_NODE,
            &self.signed_scope()?,
        ))
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

layout! {
    /// The record is a preimage and never appears on the wire or in state; only its commitment
    /// does. Its field set **awaits Canon** — it freezes with the one open link the Constitution
    /// names — so an implementation reproduces the order and the widths and claims no conformance
    /// over them.
    Record, "committed record of a person", {
        segment_bitmap: u64,
        last_active_segment: u32,
        opened_window: u64,
        own_height: u32,
        fabric_root: [u8; 32],
        suite_id: u16,
        current_pubkey: bytes(size::SIGNING_PUBLIC_KEY),
        blind: [u8; 32],
    }
}

impl Record {
    // What a gate compares is the number of segments lived, never a run of them, and the bitmap is
    // read only after shifting it by the distance from the segment it was written against to the
    // current one: a bitmap read without the shift measures continuity against a past that has
    // moved.
    pub fn segments_lived(&self, current_segment: u32) -> u32 {
        if current_segment < self.last_active_segment {
            return 0;
        }
        let distance = current_segment - self.last_active_segment;
        if distance >= 64 {
            return 0;
        }
        (self.segment_bitmap >> distance).count_ones()
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
            (WindowProof::NAME, WindowProof::expected_len()),
            (Frame::NAME, Frame::expected_len()),
            (Confirmation::NAME, Confirmation::expected_len()),
            (LightAttestation::NAME, LightAttestation::expected_len()),
            (Candidacy::NAME, Candidacy::expected_len()),
            (FoldNode::NAME, FoldNode::expected_len()),
            (Beacon::NAME, Beacon::expected_len()),
            (SlotCommit::NAME, SlotCommit::expected_len()),
            (SlotRenew::NAME, SlotRenew::expected_len()),
            (NameReveal::NAME, NameReveal::expected_len()),
            (ChannelReveal::NAME, ChannelReveal::expected_len()),
            (ChannelPublication::NAME, ChannelPublication::expected_len()),
        ];
        for (name, total) in totals {
            assert!(total > 0, "the total of {name} is zero");
        }
        let carrying: Vec<usize> = totals
            .iter()
            .filter(|(_, total)| *total > super::super::PROOF_LEN)
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
        assert_eq!(
            Proposal::expected_len(),
            8 + 4
                + 8 * 32
                + 2
                + size::SIGNING_PUBLIC_KEY
                + super::super::PROOF_LEN
                + size::SIGNATURE
        );
        assert_eq!(
            LightAttestation::expected_len(),
            8 + 2 + 64 + 32 + 32 + 2 + size::SIGNING_PUBLIC_KEY + size::SIGNATURE
        );
        assert_eq!(
            Confirmation::expected_len(),
            LightAttestation::expected_len()
                + super::super::WEIGHT_COMMIT_BYTES
                + super::super::PRESENCE_PROOF_LEN
        );
        assert_eq!(
            Beacon::expected_len(),
            8 + 1 + 4 + 32 + super::super::WEIGHT_COMMIT_BYTES
        );
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
            operations_root: [0x88; 32],
            suite_id: 1,
            runner_pubkey: vec![0xA1; mt_codec::size::SIGNING_PUBLIC_KEY],
            ticket_proof: vec![0x00; super::super::PROOF_LEN],
            signature: vec![0xF0; mt_codec::size::SIGNATURE],
        }
    }

    // The identifier of a proposal stands over the deterministic fields alone. The named wrong
    // implementation hashes the whole object: it agrees with the serialization hash the set
    // freezes and disagrees with the identifier — and a name over proof bytes is a name a runner
    // redraws by reproving.
    #[test]
    fn the_identifier_of_a_proposal_ignores_the_proof_and_the_signature() {
        let one = a_proposal();
        let reproven = Proposal {
            ticket_proof: vec![0x5A; super::super::PROOF_LEN],
            signature: vec![0x0F; mt_codec::size::SIGNATURE],
            ..a_proposal()
        };
        assert_eq!(one.id(), reproven.id());
        let moved = Proposal {
            final_beacon: [0x23; 32],
            ..a_proposal()
        };
        assert_ne!(one.id(), moved.id());
        let whole = super::super::identifier(mt_codec::domain::MT_PROPOSAL, &one.encode());
        assert_ne!(
            Ok(whole),
            one.id(),
            "a name over the whole object is another name"
        );
    }

    #[test]
    fn the_proof_of_a_window_has_one_width_and_one_name() {
        let held = WindowProof {
            window: 1000,
            proposal: [0x99; 32],
            proof: vec![0x00; super::super::PROOF_LEN],
        };
        assert_eq!(held.encode().len(), WindowProof::expected_len());
        assert_eq!(
            WindowProof::expected_len(),
            8 + 32 + super::super::PROOF_LEN
        );
        // No signature and no key: the scope is the whole of it.
        assert_eq!(WindowProof::scope_len(), WindowProof::expected_len());
        let other = WindowProof {
            proposal: [0x9A; 32],
            ..held.clone()
        };
        assert_ne!(held.id(), other.id());
    }

    fn a_confirmation() -> Confirmation {
        Confirmation {
            window: 1000,
            attested: vec![[0x10; 32], [0x20; 32]],
            part_nullifier: [0x30; 32],
            round_nullifier: [0x40; 32],
            weight_commit: vec![0x11; super::super::WEIGHT_COMMIT_BYTES],
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
            FoldNode {
                left: [0xAB; 32],
                right: [0xCD; 32],
                commitment: vec![0x11; super::super::WEIGHT_COMMIT_BYTES],
                proof: vec![0x00; super::super::PROOF_LEN],
            },
            FoldNode
        );
        round_trip!(
            Beacon {
                window: 1000,
                chain: 0,
                round: 7,
                previous: [0xEE; 32],
                cement_state: vec![0x11; super::super::WEIGHT_COMMIT_BYTES],
            },
            Beacon
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
                fabric_root: [0x77; 32],
                suite_id: 1,
                current_pubkey: vec![0xA1; mt_codec::size::SIGNING_PUBLIC_KEY],
                blind: [0xBB; 32],
            },
            Record
        );
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
        assert!(FoldNode::parse(&[0u8; 3]).is_err());
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
        assert_eq!(empty.encode().len(), 8 + 4 + 8 * 32 + 2);
        assert_eq!(
            empty.bytes(),
            Err(ObjectError::Length {
                expected,
                found: 8 + 4 + 8 * 32 + 2
            })
        );
        assert!(empty.signed_scope().is_err());
        // And a beacon of the wrong width names nothing.
        let short = Beacon {
            window: 1000,
            chain: 0,
            round: 7,
            previous: [0xEE; 32],
            cement_state: Vec::new(),
        };
        assert!(short.id().is_err());
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

    #[test]
    fn the_segments_of_a_record_are_counted_after_the_shift() {
        // Four segments lived, written against segment ten. Read at segment ten the count is four;
        // read at twelve, two of them have moved out of the window.
        let record = Record {
            segment_bitmap: 0b1111,
            last_active_segment: 10,
            opened_window: 0,
            own_height: 0,
            fabric_root: [0; 32],
            suite_id: 1,
            current_pubkey: vec![0; mt_codec::size::SIGNING_PUBLIC_KEY],
            blind: [0; 32],
        };
        assert_eq!(record.segments_lived(10), 4);
        assert_eq!(record.segments_lived(12), 2);
        assert_eq!(record.segments_lived(14), 0);
        // A bitmap read without the shift would answer four at every segment, which is the defect
        // the shift exists to prevent.
        assert_ne!(record.segments_lived(12), record.segments_lived(10));
    }
}
