// The wallet, run from a terminal. What this file holds is the reading of what an operator typed
// and the printing of what a wallet answers; every rule it stands on is in the library beside it.

use montana_wallet::{Note, Person, Wallet, WalletError};
use std::io::Read;
use std::process::ExitCode;
use zeroize::Zeroizing;

const USAGE: &str = "\
montana-wallet — what a person holds, and what they spend

  montana-wallet --data <directory> <what>

  born                 draw a person on this device, print the words they write down and the
                       two public values a payer needs of them
  words                read the twenty-four words from the standard input, and print the two
                       public values a payer needs of that person
  balance              the sum of the notes this wallet holds
  notes                every note that stands, and every nullifier already spent
  spend <commitment>   spend one note by its commitment, in hexadecimal
  take <position>      take a note somebody paid you: its three values are read from the
                       standard input, in the order the payer's file writes them — the value,
                       the key it is paid to, and the blinding factor

The words are the whole of a person. Written down they restore this wallet on any
device; read by anybody else they are that person, so they are printed once and
kept nowhere — and they are never given on the command line, where every other
process on this machine reads them and the history of a shell keeps them.
";

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(said) => {
            eprintln!("montana-wallet: {said}");
            ExitCode::FAILURE
        }
    }
}

fn read32(said: &str) -> Result<[u8; 32], String> {
    if said.len() != 64 {
        return Err("a value of thirty-two bytes is sixty-four hexadecimal characters".to_string());
    }
    let mut out = [0u8; 32];
    for (at, slot) in out.iter_mut().enumerate() {
        *slot = u8::from_str_radix(&said[at * 2..at * 2 + 2], 16)
            .map_err(|_| "a value of hexadecimal characters".to_string())?;
    }
    Ok(out)
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

fn run() -> Result<(), String> {
    let held: Vec<String> = std::env::args().skip(1).collect();
    if held.is_empty() || held.iter().any(|a| a == "--help" || a == "-h") {
        print!("{USAGE}");
        return Ok(());
    }
    let (data, rest) = match held.split_first() {
        Some((flag, rest)) if flag == "--data" => match rest.split_first() {
            Some((data, rest)) => (data.clone(), rest.to_vec()),
            None => return Err("--data names where this wallet keeps what it holds".to_string()),
        },
        _ => return Err(format!("--data comes first\n\n{USAGE}")),
    };
    let wallet = Wallet::open(&data).map_err(said)?;

    match rest.first().map(String::as_str) {
        Some("born") => {
            let (person, entropy) = Person::born().map_err(said)?;
            wallet.bear_person(&entropy).map_err(said)?;
            println!("write these words down; they are the whole of this person:");
            println!("{}", &*Person::words(&entropy));
            // **A payer needs two values of a person and not one.** The key a note is paid to says
            // where value goes; the half a person is named by is what the frame binds it to, and
            // without it nobody can be paid at all. Both are public and neither names anybody: a
            // half is a derivation of a key that never leaves this device, and a payment key is
            // what it says it is.
            println!("paid to: {}", hex(&person.payment_key()));
            println!(
                "hand a payer these two, in this order: {}:{}",
                hex(&mt_derive::note::nf_pk(&person.note_nullifier_key())),
                hex(&person.payment_key())
            );
        }
        Some("words") => {
            // The whole of a person is read from the standard input and never from the arguments of
            // a command: what stands in `argv` is readable by every other process on this machine
            // and is written into the history of a shell, and a secret read from either of those is
            // a secret that has left. What is read here stands in the wrapper that wipes.
            if rest.len() > 1 {
                return Err(
                    "the words are read from the standard input, not from the command line: \
                     `montana-wallet --data <directory> words < phrase.txt`"
                        .to_string(),
                );
            }
            let mut spoken = Zeroizing::new(String::new());
            std::io::stdin()
                .read_to_string(&mut spoken)
                .map_err(|e| format!("the words could not be read: {e}"))?;
            let person = Person::of_words(&spoken).map_err(said)?;
            let entropy = mt_seed::words::entropy_of(&spoken)
                .map_err(|e| format!("the words are not a person: {e:?}"))?;
            wallet.bear_person(&entropy).map_err(said)?;
            println!("paid to: {}", hex(&person.payment_key()));
            println!(
                "hand a payer these two, in this order: {}:{}",
                hex(&mt_derive::note::nf_pk(&person.note_nullifier_key())),
                hex(&person.payment_key())
            );
        }
        Some("balance") => println!("{}", wallet.balance().map_err(said)?),
        Some("notes") => {
            let ledger = wallet.ledger().map_err(said)?;
            for note in &ledger.held {
                println!(
                    "holding {} at position {} — {}",
                    note.value,
                    note.position,
                    hex(&note.commitment)
                );
            }
            for spent in &ledger.spent {
                println!("spent {}", hex(spent));
            }
            println!(
                "{} standing, {} spent, {} in all",
                ledger.held.len(),
                ledger.spent.len(),
                wallet.balance().map_err(said)?
            );
        }
        Some("spend") => {
            let named = rest.get(1).ok_or("spend names a commitment")?;
            if named.len() != 64 {
                return Err("a commitment is sixty-four hexadecimal characters".to_string());
            }
            let mut commitment = [0u8; 32];
            for (at, slot) in commitment.iter_mut().enumerate() {
                *slot = u8::from_str_radix(&named[at * 2..at * 2 + 2], 16)
                    .map_err(|_| "a commitment of hexadecimal characters".to_string())?;
            }
            let nullifier = wallet.spend(&commitment).map_err(said)?;
            println!("spent; its nullifier is {}", hex(&nullifier));
        }
        Some("take") => {
            // The blinding factor of a note is a secret, so it is read from the standard input and
            // never from the command line, exactly as the words of a person are.
            let named = rest
                .get(1)
                .ok_or("take names the position the note stands at")?;
            let position: u64 = named
                .parse()
                .map_err(|_| "a position is a number".to_string())?;
            let person = wallet
                .person()
                .map_err(said)?
                .ok_or("this wallet holds no person: `born` it, or restore it with `words`")?;
            let mut spoken = Zeroizing::new(String::new());
            std::io::stdin()
                .read_to_string(&mut spoken)
                .map_err(|e| format!("the note could not be read: {e}"))?;
            let lines: Vec<&str> = spoken
                .lines()
                .map(str::trim)
                .filter(|l| !l.is_empty())
                .collect();
            let [value, note_pk, rcm] = lines[..] else {
                return Err(
                    "a note is three lines: the value, the key, the blinding factor".to_string(),
                );
            };
            let note = Note::of(
                value
                    .parse()
                    .map_err(|_| "a value is a number".to_string())?,
                read32(note_pk)?,
                person.note_nullifier_key(),
                read32(rcm)?,
                position,
            )
            .map_err(said)?;
            let commitment = note.commitment;
            wallet.enter(note).map_err(said)?;
            println!("taken; it stands at {}", hex(&commitment));
        }
        other => {
            return Err(format!(
                "this wallet does not know {}\n\n{USAGE}",
                other.unwrap_or("nothing")
            ))
        }
    }
    Ok(())
}

fn said(e: WalletError) -> String {
    match e {
        WalletError::Store(e) => format!("what this wallet keeps: {e:?}"),
        WalletError::Ledger(e) => format!("the ledger on the disk is not one this wallet wrote: {e:?}"),
        WalletError::NotItsOwnCommitment => {
            "a note whose commitment is not what its own parts derive — the network would refuse it"
                .to_string()
        }
        WalletError::AlreadySpent => {
            "that note is spent: one note has one nullifier, and a second spending collides with the first"
                .to_string()
        }
        WalletError::NotHeld => "this wallet holds no note at that commitment".to_string(),
        WalletError::NotOfTheFamily => {
            "a value the family of the proof hash refuses".to_string()
        }
        WalletError::NoPerson { said } => format!("no person: {said}"),
    }
}
