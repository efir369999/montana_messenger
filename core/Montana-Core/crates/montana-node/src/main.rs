// The machine, run from a terminal. What this file holds is the reading of what an operator typed
// and the printing of what a machine answers; every rule it stands on is in the library beside it.

use montana_node::{Configuration, Machine, NodeError};
use std::process::ExitCode;

const USAGE: &str = "\
montana-node — a machine of Montana

  montana-node --data <directory> --listen <address> [--acquaintance <line>]...
               [--admitted <half>]... [--from <window>] [--windows <n>]

  --data <directory>     where this machine keeps what it holds between starts
  --listen <address>     where it answers, as an address and a port
  --acquaintance <line>  a machine to reach, as its operator handed it over:
                         an address, an at-sign and the key it answers with
  --admitted <half>      the naming half of a machine admitted to the window, in
                         hexadecimal, as its operator handed it over. Given once for
                         every machine of the cohort — this one included — it is what
                         a cohort that witnesses itself is. Without any of them this
                         machine answers its door and lives no window.
  --from <window>        the window to open at; the first if it is not named
  --windows <n>          how many windows to live before stopping; without it, until
                         the machine is stopped
  --pay-to <half>:<pk>   whom this living machine pays out of --wallet, against the tree it holds
                         itself, publishing the frame at the points of the window it is living. The
                         two values are what the payee's wallet printed of them.
  --amount <n>           what to pay, in the smallest unit
  --hand-to <file>       where to write what the payee needs of the note, closed to its owner
  --redeem <w>:<n>       the right of window <w>, whose cement named <n> machines, redeemed into a
                         note of --wallet. A right is not a note: it is extinguished inside a frame
                         and what comes out is a commitment its holder keeps. It is presented in the
                         window that right is accepted in, which the machine printed when it took
                         it, so --from names that window.
  --help                 this

  montana-node --data <directory> --listen <address> --pay <line>
               --wallet <directory> --to <half>:<note_pk> --amount <n>
               --window <n> --round <chain>:<round>

  --pay <line>           the machine holding the state, as its operator handed it over
  --wallet <directory>   where the person paying keeps the notes they hold
  --to <half>:<note_pk>  whom to pay: two values of thirty-two bytes in hexadecimal,
                         both public and neither a name
  --amount <n>           what to pay, in the smallest unit
  --window <n>           the window the payment belongs to
  --round <chain>:<round>  the round its frame stands at the points of
  --hand-to <file>       where to write the note the payee takes: three values, one of them
                         the blinding factor, which is a secret and is therefore written to a
                         file closed to its owner rather than printed

A first start draws the secret of this machine and prints the acquaintance to hand
to another operator. Every later start takes the secret that stands.
";

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(said) => {
            eprintln!("montana-node: {said}");
            ExitCode::FAILURE
        }
    }
}

fn run() -> Result<(), String> {
    let held: Vec<String> = std::env::args().skip(1).collect();
    if held.iter().any(|a| a == "--help" || a == "-h") {
        print!("{USAGE}");
        return Ok(());
    }
    let (configuration, payment) = read_configuration(&held)?;

    let (machine, born) = Machine::start(&configuration).map_err(said)?;
    if born {
        println!("this machine was born: it drew its secret and will not draw another");
    }
    println!("answering at {}", machine.address().map_err(said)?);
    // Two values with two purposes: the line a machine reads, and the digits a person compares.
    println!(
        "hand this to another operator: {}",
        machine.acquaintance().map_err(said)?
    );
    println!(
        "check these digits with them by voice: {}",
        machine.fingerprint()
    );
    // The half this machine is named by in the tree of admitted machines. It passes between
    // operators exactly as the acquaintance above does, and it names no owner, no address and no
    // person.
    println!(
        "hand this over too, to stand in one window: {}",
        hex(&machine.naming_half().map_err(said)?)
    );
    match machine.head().map_err(said)? {
        Some(window) => println!("holding the chain to window {window}"),
        None => println!("holding no window yet"),
    }

    // A link this machine opened is carried rather than printed and dropped: the value falling out
    // of scope closes the socket, and two machines that shook hands and hung up carry nothing for
    // each other. It stands outside the ceiling, so an acquaintance takes no slot a stranger could.
    let mut unreached: Vec<String> = Vec::new();
    for line in &configuration.acquaintances {
        match machine.reach_and_hold(line) {
            Ok(transcript) => {
                let shown: String = transcript.iter().map(|b| format!("{b:02x}")).collect();
                println!("reached {line}\n  transcript {shown}");
            }
            // A machine that did not answer is one line of an operator's morning and not a reason
            // to stop: the others may answer, and this one is dialled again once the machine lives.
            Err(e) => {
                eprintln!("could not reach {line}: {}", said(e));
                unreached.push(line.clone());
            }
        }
    }

    if let Some(asked) = payment {
        return pay_and_report(&machine, &asked);
    }

    let (_, ceiling) = machine.holding();
    println!("answering up to {ceiling} links until stopped");

    // A machine handed no cohort answers its door and lives no window: it has no tree of admitted
    // machines to prove its presence against, and a machine that made one up would be proving
    // something no other machine holds.
    if configuration.admitted.is_empty() {
        println!("no machine was named as admitted, so this one lives no window");
        return machine.serve().map_err(said);
    }
    let cohort = montana_node::pulse::Cohort::of(&configuration.admitted).map_err(said)?;
    let half = machine.naming_half().map_err(said)?;
    if !cohort.holds(&half) {
        return Err(format!(
            "this machine is not among the {} named as admitted; hand its own half over too: {}",
            cohort.count(),
            hex(&half)
        ));
    }
    println!(
        "living from window {} in a cohort of {}",
        configuration.from,
        cohort.count()
    );

    // The door and the pulse stand at once: the door answers the links strangers open, and the
    // pulse asks over the links this machine opened. Neither waits on the other, which is what
    // lets a machine answer while it is standing at a round.
    // **A machine opens its window before it opens its door.** A deposit is held only at a point of
    // the round the machine stands in, so anything arriving before it has entered one is refused for
    // a round it had not yet begun — and a neighbour that published in that moment publishes into
    // nothing and never learns. The window is entered first, and the door answers after.
    machine
        .enter_round(configuration.from, montana_node::pulse::opening_chain(), 0)
        .map_err(said)?;
    let machine = std::sync::Arc::new(machine);
    let answering = std::sync::Arc::clone(&machine);
    std::thread::spawn(move || {
        let _ = answering.serve();
    });
    for line in unreached {
        montana_node::pulse::reach_again(std::sync::Arc::clone(&machine), line);
    }
    let windows = configuration.windows.unwrap_or(u64::MAX);
    // **What this machine does of its own is done inside the window, not after it.** A frame stands
    // at the points of the round its slot names, and a machine releases those points the moment its
    // window closes — so an errand run after the window publishes into points nobody holds, and the
    // only machine that takes it is one still lagging behind. It is carried into the pulse, which
    // runs it after this machine has entered the round and before it attests anything.
    let cohort_of_the_errand = &cohort;
    let errand =
        |machine: &montana_node::Machine, window: u64| -> Result<(), montana_node::NodeError> {
            let cohort = cohort_of_the_errand;
            let out = (|| -> Result<(), String> {
                // The right of a window turned into a note of a wallet, in the window that right
                // is accepted in — and it is done here, where the machine does stand at the points
                // of that window, rather than after a close that has already released them.
                if let Some((of_the_window, living)) = configuration.redeem {
                    let at = configuration
                        .wallet
                        .as_deref()
                        .ok_or("--redeem asks for --wallet")?;
                    let wallet = montana_wallet::Wallet::open(at)
                        .map_err(|e| format!("what this wallet keeps: {e:?}"))?;
                    let rate_secret = *mt_wire::draw::block::<32>()
                        .map_err(|e| format!("nothing to draw from: {e:?}"))?;
                    let minted = machine
                        .redeem_into(
                            &wallet,
                            cohort,
                            of_the_window,
                            living,
                            window,
                            montana_node::pulse::opening_chain(),
                            0,
                            &rate_secret,
                        )
                        .map_err(|e| format!("{e:?}"))?;
                    println!(
                        "the right of window {of_the_window} is a note now: {} at position {}",
                        minted.value, minted.position
                    );
                    println!(
                        "this wallet holds {}",
                        wallet.balance().map_err(|e| format!("a balance: {e:?}"))?
                    );
                }
                // And what a living machine pays out of its own wallet, against the tree it holds itself.
                if let Some((half, note_pk)) = configuration.pay_to {
                    let at = configuration
                        .wallet
                        .as_deref()
                        .ok_or("--pay-to asks for --wallet")?;
                    let file = configuration
                        .hand_to
                        .as_deref()
                        .ok_or("--pay-to asks for --hand-to")?;
                    let amount = configuration.amount.ok_or("--pay-to asks for --amount")?;
                    let wallet = montana_wallet::Wallet::open(at)
                        .map_err(|e| format!("what this wallet keeps: {e:?}"))?;
                    let rate_secret = *mt_wire::draw::block::<32>()
                        .map_err(|e| format!("nothing to draw from: {e:?}"))?;
                    let paid = machine
                        .pay_of_its_own(
                            &wallet,
                            &montana_wallet::pay::Payee { half, note_pk },
                            amount,
                            window,
                            montana_node::pulse::opening_chain(),
                            0,
                            &rate_secret,
                        )
                        .map_err(|e| format!("{e:?}"))?;
                    wallet
                        .hand_over(
                            std::path::Path::new(file),
                            paid.value,
                            &paid.rcm,
                            &paid.note_pk,
                        )
                        .map_err(|e| format!("the note handed to the payee: {e:?}"))?;
                    println!(
                "paid {} — the note for the payee stands in {file}, closed to its owner alone",
                paid.value
            );
                    println!("its position in the tree of notes is {}", paid.position);
                    println!(
                        "this wallet holds {} now",
                        wallet.balance().map_err(|e| format!("a balance: {e:?}"))?
                    );
                }
                Ok(())
            })();
            out.map_err(|what| montana_node::NodeError::Unreadable { what })
        };
    let lived = montana_node::pulse::live_doing(
        &machine,
        &cohort,
        configuration.from,
        windows,
        montana_node::pulse::WAITS_UP_TO,
        Some(&errand),
    )
    .map_err(said)?;
    for one in &lived {
        println!(
            "window {} closed after {} rounds on a cement naming {} machines",
            one.window, one.rounds, one.living
        );
        println!(
            "  it mints {} to this machine, accepted in window {}",
            one.right.share, one.right.accepted_in
        );
    }
    Ok(())
}

// What an operator asked to be paid, read off the command line and nothing more. Every value of it
// is public: two keys of the payee, an amount, a window and a round.
struct Asked {
    line: String,
    wallet: String,
    half: [u8; 32],
    note_pk: [u8; 32],
    amount: u128,
    window: u64,
    chain: u8,
    round: u32,
    hand_to: String,
}

fn pay_and_report(machine: &Machine, asked: &Asked) -> Result<(), String> {
    let wallet = montana_wallet::Wallet::open(&asked.wallet)
        .map_err(|e| format!("what this wallet keeps: {e:?}"))?;
    // Whom the change comes back to is this person, and this person is the one whose notes are
    // being spent: the keys of it are read off the first note the ledger holds.
    let ledger = wallet
        .ledger()
        .map_err(|e| format!("the ledger on the disk: {e:?}"))?;
    let mine = ledger
        .held
        .first()
        .ok_or("this wallet holds no note to pay from")?;
    let own = montana_wallet::pay::Payee {
        half: mt_derive::note::nf_pk(&mine.nf_key),
        note_pk: mine.note_pk,
    };
    // The blinding factors of the notes a payment creates are drawn from this value, so it is drawn
    // here and never typed: a payer that supplied it would be choosing what must be drawn.
    let rate_secret =
        *mt_wire::draw::block::<32>().map_err(|e| format!("nothing to draw from: {e:?}"))?;
    let payment = machine
        .pay(
            &asked.line,
            &wallet,
            &montana_wallet::pay::Payee {
                half: asked.half,
                note_pk: asked.note_pk,
            },
            &own,
            asked.amount,
            asked.window,
            asked.chain,
            asked.round,
            &rate_secret,
            &machine.value().map_err(said)?.notes_root(),
            &mt_proof::admitted::empty_root(),
        )
        .map_err(said)?;
    println!("the frame stands at the points of round {}", asked.round);
    let created = payment.created.first().ok_or("a payment created no note")?;
    // What the payee needs of the note it was paid is written to the file the operator named, and
    // that file is closed to everyone but its owner. The blinding factor among those three values
    // is a secret — whoever holds it and the key holds the note — so it is carried across as a file
    // and never printed here, where a scrollback keeps it.
    wallet
        .hand_over(
            std::path::Path::new(&asked.hand_to),
            created.value,
            &created.rcm,
            &created.note_pk,
        )
        .map_err(|e| format!("the note handed to the payee: {e:?}"))?;
    println!(
        "paid {} — the note for the payee stands in {}, closed to its owner alone",
        created.value, asked.hand_to
    );
    println!("the position of their note comes of the window that applies this frame");
    for commitment in &payment.spent {
        wallet
            .spend(commitment)
            .map_err(|e| format!("a note this wallet holds: {e:?}"))?;
    }
    println!("{} notes left this ledger", payment.spent.len());
    Ok(())
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

fn read32(said: &str) -> Result<[u8; 32], String> {
    if said.len() != 64 {
        return Err("a key is sixty-four hexadecimal characters".to_string());
    }
    let mut out = [0u8; 32];
    for (at, slot) in out.iter_mut().enumerate() {
        *slot = u8::from_str_radix(&said[at * 2..at * 2 + 2], 16)
            .map_err(|_| "a key of hexadecimal characters".to_string())?;
    }
    Ok(out)
}

fn said(e: NodeError) -> String {
    match e {
        NodeError::Store(e) => format!("what this machine keeps: {e:?}"),
        NodeError::Net(e) => format!("the wire: {e:?}"),
        NodeError::Decree { row } => format!("the Decree carries no row {row}"),
        NodeError::Uncountable => {
            "this machine can no longer count the links it holds, and stops rather than answering \
             past the ceiling the set fixes"
                .to_string()
        }
        NodeError::Unborn { said } => {
            format!("this machine cannot draw a secret and will not stand on a weak one: {said}")
        }
        NodeError::Unreadable { what } => format!("an acquaintance is unreadable: {what}"),
        NodeError::Unprovable { what } => format!(
            "this machine could not build {what}, and answers nothing rather than answering with \
             what a verifier would refuse"
        ),
        NodeError::Refused { what } => format!("refused: {what}"),
        NodeError::Object(e) => format!("an object of another shape than its layout gives: {e:?}"),
    }
}

// What an operator typed. A flag naming no value, or a flag this machine does not know, is an
// error rather than a default: a machine started with a misspelt flag and a default beside it is a
// machine doing something its operator did not ask for.
fn read_configuration(held: &[String]) -> Result<(Configuration, Option<Asked>), String> {
    let mut data: Option<String> = None;
    let mut listen: Option<String> = None;
    let mut acquaintances: Vec<String> = Vec::new();
    let mut pay: Option<String> = None;
    let mut wallet: Option<String> = None;
    let mut to: Option<String> = None;
    let mut amount: Option<u128> = None;
    let mut window: Option<u64> = None;
    let mut at_round: Option<String> = None;
    let mut hand_to: Option<String> = None;
    let mut admitted: Vec<[u8; 32]> = Vec::new();
    let mut from: Option<u64> = None;
    let mut windows: Option<u64> = None;
    let mut redeem: Option<String> = None;
    let mut pay_to: Option<String> = None;
    let mut at = 0usize;
    while at < held.len() {
        let flag = held[at].as_str();
        let value = || -> Result<String, String> {
            held.get(at + 1)
                .cloned()
                .ok_or_else(|| format!("{flag} names no value"))
        };
        match flag {
            "--data" => {
                data = Some(value()?);
                at += 2;
            }
            "--listen" => {
                listen = Some(value()?);
                at += 2;
            }
            "--acquaintance" => {
                acquaintances.push(value()?);
                at += 2;
            }
            "--admitted" => {
                admitted.push(read32(&value()?)?);
                at += 2;
            }
            "--from" => {
                from = Some(
                    value()?
                        .parse()
                        .map_err(|_| "--from names a number".to_string())?,
                );
                at += 2;
            }
            "--pay-to" => {
                pay_to = Some(value()?);
                at += 2;
            }
            "--redeem" => {
                redeem = Some(value()?);
                at += 2;
            }
            "--windows" => {
                windows = Some(
                    value()?
                        .parse()
                        .map_err(|_| "--windows names a number".to_string())?,
                );
                at += 2;
            }
            "--pay" => {
                pay = Some(value()?);
                at += 2;
            }
            "--wallet" => {
                wallet = Some(value()?);
                at += 2;
            }
            "--to" => {
                to = Some(value()?);
                at += 2;
            }
            "--amount" => {
                amount = Some(
                    value()?
                        .parse()
                        .map_err(|_| "--amount names a number".to_string())?,
                );
                at += 2;
            }
            "--window" => {
                window = Some(
                    value()?
                        .parse()
                        .map_err(|_| "--window names a number".to_string())?,
                );
                at += 2;
            }
            "--round" => {
                at_round = Some(value()?);
                at += 2;
            }
            "--hand-to" => {
                hand_to = Some(value()?);
                at += 2;
            }
            other => return Err(format!("this machine does not know {other}\n\n{USAGE}")),
        }
    }
    let data = data
        .ok_or_else(|| format!("--data names where this machine keeps what it holds\n\n{USAGE}"))?;
    let listen =
        listen.ok_or_else(|| format!("--listen names where this machine answers\n\n{USAGE}"))?;
    let configuration = Configuration {
        data: std::path::PathBuf::from(data),
        listen,
        acquaintances,
        admitted,
        from: from.unwrap_or(0),
        windows,
        redeem: match redeem {
            None => None,
            Some(said) => {
                let (window, living) = said
                    .split_once(':')
                    .ok_or("--redeem is <window>:<machines the cement named>")?;
                let window: u64 = window
                    .parse()
                    .map_err(|_| "--redeem names a window as a number".to_string())?;
                let living: usize = living
                    .parse()
                    .map_err(|_| "--redeem names a count as a number".to_string())?;
                Some((window, living))
            }
        },
        wallet: wallet.clone(),
        pay_to: match pay_to {
            None => None,
            Some(said) => {
                let (half, note_pk) = said
                    .split_once(':')
                    .ok_or("--pay-to is <half>:<the key a note is paid to>")?;
                Some((read32(half)?, read32(note_pk)?))
            }
        },
        amount,
        hand_to: hand_to.clone(),
    };
    // A payment is asked for whole or not at all: a flag of it without the rest is an operator
    // asking for something this machine cannot do, and a default in its place would be this machine
    // paying somebody the operator did not name.
    let asked = match pay {
        None => None,
        Some(line) => {
            let wallet = wallet.ok_or("--pay asks for --wallet")?;
            let to = to.ok_or("--pay asks for --to")?;
            let (half, note_pk) = to.split_once(':').ok_or("--to is <half>:<note_pk>")?;
            let at_round = at_round.ok_or("--pay asks for --round")?;
            let (chain, round) = at_round
                .split_once(':')
                .ok_or("--round is <chain>:<round>")?;
            Some(Asked {
                line,
                wallet,
                half: read32(half)?,
                note_pk: read32(note_pk)?,
                amount: amount.ok_or("--pay asks for --amount")?,
                window: window.ok_or("--pay asks for --window")?,
                chain: chain
                    .parse()
                    .map_err(|_| "a chain is a number below two hundred fifty-six".to_string())?,
                round: round
                    .parse()
                    .map_err(|_| "a round is a number".to_string())?,
                hand_to: hand_to.ok_or("--pay asks for --hand-to")?,
            })
        }
    };
    Ok((configuration, asked))
}
