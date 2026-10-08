// The wallet in a terminal: a person, what they hold, and what they spend. Every derivation here is
// asked of the crate that owns it — the birth and the branches of `mt-seed`, the envelope of a note
// of `mt-derive`, the writing on a disk of `mt-store` — and what this file holds is the ledger of
// notes and the rules that keep it honest.
//
// **A note is spent once, and the ledger says so before a proof is asked for.** A note carries one
// nullifier, because its commitment binds the half of the key that spends it; a second spending
// therefore collides with the first, and this wallet refuses it at the door rather than building a
// frame the network would refuse — a spender who learns of the collision from the network has
// already published one.
//
// **What a wallet holds is secret and it is written as one.** The notes go through the door of the
// store that closes a file to everyone but its owner, exactly as a machine's own secret does: a
// note names its owner to whoever reads it.

#![forbid(unsafe_code)]
#![deny(clippy::all)]

pub mod pay;

use mt_codec::encode::{CanonicalDecode, CanonicalEncode, DecodeError};
use mt_seed::Branch;
use mt_store::{Store, StoreError};
use std::path::Path;
use zeroize::Zeroizing;

mt_codec::constants! {
    WALLET:
    /// The width one note of this ledger is written at: its value, the three secrets that make its
    /// envelope, the position of its leaf and the commitment it stands at.
    pub const NOTE_BYTES: usize = 152, code "the width one note of this wallet's ledger is written at on a disk, which the set lays out nowhere because a ledger of a wallet is of the device and not of the protocol";
}

#[derive(Debug, PartialEq, Eq)]
pub enum WalletError {
    Store(StoreError),
    Ledger(DecodeError),
    // A note offered whose commitment is not the one its own parts derive. A ledger holding it
    // would hold a note the network cannot verify.
    NotItsOwnCommitment,
    // A note whose nullifier this wallet has already spent. It is refused here rather than in a
    // frame: a spender who learns of the collision from the network has already published one.
    AlreadySpent,
    // A commitment this wallet holds no note for. It is its own answer and never the one above: a
    // person told "already spent" about a note they never held is told something untrue about
    // their own money.
    NotHeld,
    // A value the family of the proof hash refuses: bytes that are not four elements of the field.
    NotOfTheFamily,
    // The person of this wallet could not be born, or has not been.
    NoPerson { said: String },
}

// One note as a wallet holds it. The commitment is not a fourth secret — it is derived from the
// three above it — and it is written down so that a ledger read from a disk can be checked against
// what it claims rather than trusted.
// What this holds is the half of a key that spends a note, so it shows nothing of it and compares
// nothing of it. A derived `Debug` would print the spending half into whatever a test, a log or the
// message of a panic goes to; a derived comparison would compare key material in a time that
// depends on where the first difference stands. What names a note to a person is its commitment,
// and that is public.
#[derive(Clone)]
pub struct Note {
    pub value: u128,
    pub note_pk: [u8; 32],
    pub nf_key: [u8; 32],
    pub rcm: [u8; 32],
    pub position: u64,
    pub commitment: [u8; 32],
}

impl core::fmt::Debug for Note {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        write!(
            f,
            "Note {{ value: {}, position: {}, commitment: {}, secrets: <wiped, never shown> }}",
            self.value,
            self.position,
            self.commitment
                .iter()
                .map(|b| format!("{b:02x}"))
                .collect::<String>()
        )
    }
}

impl Note {
    // The envelope of a note, derived rather than remembered: the commitment binds the naming half
    // of the nullifier key, so a note has one nullifier and one spender.
    pub fn of(
        value: u128,
        note_pk: [u8; 32],
        nf_key: [u8; 32],
        rcm: [u8; 32],
        position: u64,
    ) -> Result<Self, WalletError> {
        let nf_pk = mt_derive::note::nf_pk(&nf_key);
        let commitment = mt_derive::note::commitment(value, &note_pk, &nf_pk, &rcm)
            .ok_or(WalletError::NotOfTheFamily)?;
        Ok(Self {
            value,
            note_pk,
            nf_key,
            rcm,
            position,
            commitment,
        })
    }

    // The value that says this note is spent. It takes the spending half of the key — the half a
    // holder of the commitment cannot derive — and the position of the leaf, so one commitment at
    // two positions yields two unrelated nullifiers.
    pub fn nullifier(&self) -> Result<[u8; 32], WalletError> {
        mt_derive::note::nullifier(&self.nf_key, &self.commitment, self.position)
            .ok_or(WalletError::NotOfTheFamily)
    }

    // Whether what a ledger claims is what its parts derive. A note read off a disk is checked
    // rather than trusted: a commitment that does not follow is a note the network refuses, and a
    // wallet that carried it would spend a whole window learning that.
    pub fn stands(&self) -> Result<(), WalletError> {
        let held = Self::of(
            self.value,
            self.note_pk,
            self.nf_key,
            self.rcm,
            self.position,
        )?;
        if held.commitment == self.commitment {
            Ok(())
        } else {
            Err(WalletError::NotItsOwnCommitment)
        }
    }
}

impl CanonicalEncode for Note {
    fn encode_into(&self, out: &mut Vec<u8>) {
        self.value.encode_into(out);
        self.note_pk.encode_into(out);
        self.nf_key.encode_into(out);
        self.rcm.encode_into(out);
        self.position.encode_into(out);
        self.commitment.encode_into(out);
    }
}

impl CanonicalDecode for Note {
    fn decode_from(input: &mut &[u8]) -> Result<Self, DecodeError> {
        Ok(Self {
            value: u128::decode_from(input)?,
            note_pk: <[u8; 32]>::decode_from(input)?,
            nf_key: <[u8; 32]>::decode_from(input)?,
            rcm: <[u8; 32]>::decode_from(input)?,
            position: u64::decode_from(input)?,
            commitment: <[u8; 32]>::decode_from(input)?,
        })
    }
}

// What a wallet holds: the notes that stand and the nullifiers it has already spent. The spent are
// kept because a note leaves the held list when it is spent, and a ledger that only removed would
// let the same note be entered again and spent again.
#[derive(Clone, Default, Debug)]
pub struct Ledger {
    pub held: Vec<Note>,
    pub spent: Vec<[u8; 32]>,
}

impl CanonicalEncode for Ledger {
    fn encode_into(&self, out: &mut Vec<u8>) {
        self.held.encode_into(out);
        self.spent.encode_into(out);
    }
}

impl CanonicalDecode for Ledger {
    fn decode_from(input: &mut &[u8]) -> Result<Self, DecodeError> {
        Ok(Self {
            held: Vec::<Note>::decode_from(input)?,
            spent: Vec::<[u8; 32]>::decode_from(input)?,
        })
    }
}

// The person of a wallet: the branches their seed gives, held in wrappers that wipe.
pub struct Person {
    seed: Zeroizing<Vec<u8>>,
}

impl Person {
    // A person born on this device, from six sources with the health tests of the set over them. A
    // bad draw is refused rather than warned about.
    pub fn born() -> Result<(Self, Zeroizing<[u8; 32]>), WalletError> {
        let birth = mt_seed::birth(None).map_err(|e| WalletError::NoPerson {
            said: format!("{e:?}"),
        })?;
        let entropy = birth.entropy.clone();
        Ok((Self::of_entropy(&entropy), entropy))
    }

    pub fn of_entropy(entropy: &[u8; 32]) -> Self {
        Self {
            seed: mt_seed::master_seed(entropy),
        }
    }

    // The words a person writes down. What is stretched is the entropy and never the text, so
    // nothing about how a phrase is typed can move a derived byte. They come back in the wrapper
    // the crate that made them put them in: the twenty-four words **are** the person, and a caller
    // that copied them out of it would hold a copy nothing wipes.
    pub fn words(entropy: &[u8; 32]) -> Zeroizing<String> {
        mt_seed::words::phrase(entropy)
    }

    pub fn of_words(spoken: &str) -> Result<Self, WalletError> {
        let entropy = mt_seed::words::entropy_of(spoken).map_err(|e| WalletError::NoPerson {
            said: format!("{e:?}"),
        })?;
        Ok(Self::of_entropy(&entropy))
    }

    pub fn branch(&self, branch: Branch) -> Zeroizing<Vec<u8>> {
        mt_seed::branch(&self.seed, branch)
    }

    // The key that spends a note paid to this person. What a payer knows of it is the naming half
    // — the value a commitment binds — and what spends the note is the half nobody holding the
    // commitment can derive; both come of this one branch.
    pub fn note_nullifier_key(&self) -> [u8; 32] {
        let branch = self.branch(Branch::Nullifier);
        let mut out = [0u8; 32];
        out.copy_from_slice(&branch[..32]);
        out
    }

    // The key a payment is made to. It is derived from the note branch and shown to whoever pays:
    // what it names is where a note may be sent, and it stands apart from the secret it comes from.
    pub fn payment_key(&self) -> [u8; 32] {
        let note = self.branch(Branch::Note);
        let mut secret = Zeroizing::new([0u8; 32]);
        secret.copy_from_slice(&note[..32]);
        mt_derive::note::note_pk(&secret)
    }
}

// The wallet: a ledger on a disk and the person that reads it.
pub struct Wallet {
    store: Store,
}

impl Wallet {
    pub fn open(at: impl AsRef<Path>) -> Result<Self, WalletError> {
        Ok(Self {
            store: Store::open(at).map_err(WalletError::Store)?,
        })
    }

    // The person this wallet belongs to, kept the way a machine keeps its own secret: in a file
    // closed to everyone but its owner. A wallet that did not remember whose it was could not take
    // a note it was paid — the key a note is bound to lives in the person and nowhere else — and a
    // person read from a terminal on every command is a person typed where a shell keeps it.
    pub fn bear_person(&self, entropy: &[u8; 32]) -> Result<(), WalletError> {
        self.store.bear_secret(entropy).map_err(WalletError::Store)
    }

    pub fn person(&self) -> Result<Option<Person>, WalletError> {
        Ok(self
            .store
            .secret()
            .map_err(WalletError::Store)?
            .map(|entropy| Person::of_entropy(&entropy)))
    }

    // Every note this wallet holds, checked against what its parts derive. A ledger is read rather
    // than trusted, so a file edited by anything other than this wallet is refused here.
    pub fn ledger(&self) -> Result<Ledger, WalletError> {
        let bytes = self.store.notes().map_err(WalletError::Store)?;
        if bytes.is_empty() {
            return Ok(Ledger::default());
        }
        let held = Ledger::decode_exact(&bytes).map_err(WalletError::Ledger)?;
        for note in &held.held {
            note.stands()?;
        }
        Ok(held)
    }

    fn put(&self, ledger: &Ledger) -> Result<(), WalletError> {
        // What is written holds the spending half of every note, so the bytes stand in the wrapper
        // that wipes for as long as they stand in memory at all.
        let bytes = Zeroizing::new(ledger.encode());
        self.store.put_notes(&bytes).map_err(WalletError::Store)
    }

    // A note entered into the ledger. It stands only if its commitment is what its parts derive and
    // its nullifier is one this wallet has not already spent.
    pub fn enter(&self, note: Note) -> Result<(), WalletError> {
        note.stands()?;
        let nullifier = note.nullifier()?;
        let mut ledger = self.ledger()?;
        if ledger.spent.contains(&nullifier) {
            return Err(WalletError::AlreadySpent);
        }
        if ledger.held.iter().any(|n| n.commitment == note.commitment) {
            return Ok(());
        }
        ledger.held.push(note);
        self.put(&ledger)
    }

    // The sum of what stands. Nothing here is a share of anything: a balance is the notes this
    // wallet holds and no view of anybody else's.
    // The note this person hands to another, written to a file closed to its owner. **The blinding
    // factor is a secret**: whoever holds it and the key holds that note, so it is carried across
    // as a file and never printed to a terminal, where a scrollback keeps it, and never given on a
    // command line, where every other process of the machine reads it.
    pub fn hand_over(
        &self,
        at: &Path,
        value: u128,
        rcm: &[u8; 32],
        note_pk: &[u8; 32],
    ) -> Result<(), WalletError> {
        let mut out = String::new();
        out.push_str(&format!("value {value}\n"));
        out.push_str("rcm ");
        for byte in rcm {
            out.push_str(&format!("{byte:02x}"));
        }
        out.push_str("\nnote_pk ");
        for byte in note_pk {
            out.push_str(&format!("{byte:02x}"));
        }
        out.push('\n');
        self.store
            .put_handed_note(at, out.as_bytes())
            .map_err(WalletError::Store)
    }

    // **What a payment did not pay away comes back here, and this is the one place that knows it.**
    // A frame creates a note for the payee at its first position and every other note of it for the
    // payer: the value of the notes it spent that the payment did not carry away. A payer that
    // published the frame and entered nothing spends its notes and holds nothing — the value stands
    // in the tree where nobody reaches it, the blinding factor that opens it having lived only in
    // the payment. The positions are the ones the tree answered with, in the order the frame writes
    // its commitments, so a created note and its place are read out of one index. A created note of
    // no value is a blank the shape of a frame requires and never a holding, so it enters nothing.
    pub fn enter_what_it_left(
        &self,
        payment: &crate::pay::Payment,
        positions: &[u64],
        nf_key: &[u8; 32],
    ) -> Result<(), WalletError> {
        for (which, left) in payment.created.iter().enumerate().skip(1) {
            if left.value == 0 {
                continue;
            }
            let at = positions.get(which).ok_or(WalletError::NotHeld)?;
            self.enter(Note::of(left.value, left.note_pk, *nf_key, left.rcm, *at)?)?;
        }
        Ok(())
    }

    pub fn balance(&self) -> Result<u128, WalletError> {
        Ok(self.ledger()?.held.iter().map(|n| n.value).sum())
    }

    // Spending a note: the nullifier is written down and the note leaves the held list, in one
    // write. **A second spending of one note is refused here** — the note's commitment binds the
    // half of the key that spends it, so one note has one nullifier and the network would refuse
    // the second; refusing it at the door is what keeps a spender from publishing the first half of
    // a collision.
    pub fn spend(&self, commitment: &[u8; 32]) -> Result<[u8; 32], WalletError> {
        let mut ledger = self.ledger()?;
        // A commitment this wallet holds no note for is answered for what it is. It cannot be
        // answered as "already spent" even where it was: what a wallet keeps of a spending is the
        // nullifier, and a nullifier is derived from the secrets of a note this wallet no longer
        // holds — so a commitment alone cannot be joined to it. The guard that a note is spent once
        // stands where it can stand: a note offered again is refused by its own nullifier at
        // `enter`, before it can be spent a second time.
        let at = ledger
            .held
            .iter()
            .position(|n| n.commitment == *commitment)
            .ok_or(WalletError::NotHeld)?;
        let nullifier = ledger.held[at].nullifier()?;
        if ledger.spent.contains(&nullifier) {
            return Err(WalletError::AlreadySpent);
        }
        ledger.held.remove(at);
        ledger.spent.push(nullifier);
        self.put(&ledger)?;
        Ok(nullifier)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    struct Scratch(PathBuf);

    impl Scratch {
        fn named(what: &str) -> Self {
            let at = std::env::temp_dir().join(format!("montana-wallet-{what}"));
            std::fs::create_dir_all(&at).expect("a scratch directory is writable");
            Self(at)
        }
    }

    impl Drop for Scratch {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }

    fn a_note(which: u8, value: u128, position: u64) -> Note {
        Note::of(
            value,
            [0x20 + which; 32],
            [0x30 + which; 32],
            [0x80 + which; 32],
            position,
        )
        .expect("a note of the family")
    }

    #[test]
    fn a_note_is_its_own_commitment_and_a_doctored_one_is_refused() {
        let note = a_note(1, 5_000_000_000, 3);
        note.stands().expect("a note derived here stands");
        let mut doctored = note.clone();
        doctored.value += 1;
        assert_eq!(doctored.stands(), Err(WalletError::NotItsOwnCommitment));
        let mut moved = note.clone();
        moved.rcm[0] ^= 1;
        assert_eq!(moved.stands(), Err(WalletError::NotItsOwnCommitment));
    }

    #[test]
    fn one_note_has_one_nullifier_and_a_second_spending_is_refused() {
        let scratch = Scratch::named("double-spend");
        let wallet = Wallet::open(&scratch.0).expect("a wallet opens");
        let note = a_note(2, 7, 11);
        wallet.enter(note.clone()).expect("it is entered");
        assert_eq!(wallet.balance().expect("a wallet answers"), 7);

        let nullifier = wallet.spend(&note.commitment).expect("the first spending");
        assert_eq!(nullifier, note.nullifier().expect("a nullifier"));
        assert_eq!(wallet.balance().expect("a wallet answers"), 0);

        // The second spending is refused for what it is — this wallet holds no note at that
        // commitment — and re-entering the note is refused by its own nullifier, which is where the
        // guard that a note is spent once can actually stand: a wallet that no longer holds a note
        // cannot derive its nullifier from a commitment, and answering "already spent" to a
        // commitment it never held would be telling a person something untrue about their money.
        assert_eq!(wallet.spend(&note.commitment), Err(WalletError::NotHeld));
        assert_eq!(wallet.enter(note.clone()), Err(WalletError::AlreadySpent));
        assert_eq!(wallet.balance().expect("a wallet answers"), 0);
        // And a commitment that was never this wallet's at all is answered the same way as one it
        // spent, because from a commitment alone the two are the same fact.
        let stranger = a_note(9, 1, 99);
        assert_eq!(
            wallet.spend(&stranger.commitment),
            Err(WalletError::NotHeld)
        );
    }

    #[test]
    fn a_wallet_stopped_and_started_again_holds_the_notes_it_held() {
        let scratch = Scratch::named("restart");
        let first = Wallet::open(&scratch.0).expect("a wallet opens");
        for (which, value, position) in [(3u8, 100u128, 1u64), (4, 250, 2), (5, 7, 3)] {
            first
                .enter(a_note(which, value, position))
                .expect("entered");
        }
        let spent = first.ledger().expect("read").held[1].commitment;
        first.spend(&spent).expect("the second is spent");
        let before = first.balance().expect("a wallet answers");
        assert_eq!(before, 107);
        drop(first);

        let again = Wallet::open(&scratch.0).expect("a wallet opens again");
        assert_eq!(again.balance().expect("a wallet answers"), before);
        assert_eq!(again.ledger().expect("read").held.len(), 2);
        // And what it spent it still knows it spent.
        assert_eq!(again.ledger().expect("read").spent.len(), 1);
    }

    #[test]
    fn a_ledger_edited_by_anything_but_this_wallet_is_refused_rather_than_read() {
        let scratch = Scratch::named("doctored-ledger");
        let wallet = Wallet::open(&scratch.0).expect("a wallet opens");
        wallet.enter(a_note(6, 42, 4)).expect("entered");
        let mut bytes = wallet.ledger().expect("read").encode();
        // A value moved by one, and the commitment left where it stood: the ledger claims a note
        // the network would refuse, and this wallet refuses it first.
        bytes[2] ^= 1;
        wallet
            .store
            .put_notes(&bytes)
            .expect("something other than this wallet wrote it");
        assert_eq!(
            wallet.ledger().err(),
            Some(WalletError::NotItsOwnCommitment)
        );
    }

    #[test]
    fn a_person_reaches_the_same_keys_from_the_same_words() {
        let entropy = [0x11u8; 32];
        let spoken = Person::words(&entropy);
        assert_eq!(spoken.split(' ').count(), 24);
        let born = Person::of_entropy(&entropy);
        let recovered = Person::of_words(&spoken).expect("the words are read back");
        assert_eq!(born.payment_key(), recovered.payment_key());
        // And a different person reaches other keys.
        let other = Person::of_entropy(&[0x12u8; 32]);
        assert_ne!(born.payment_key(), other.payment_key());
    }

    #[test]
    fn the_width_of_a_note_is_the_one_the_register_holds() {
        let note = a_note(7, 1, 1);
        assert_eq!(note.encode().len(), NOTE_BYTES);
    }
}
