use std::path::PathBuf;

use crate::identity::{
    default_data_dir, save_identity, Identity, NodeError, IDENTITY_FILE_MODE, IDENTITY_FILE_SIZE,
};

pub struct InitArgs {
    pub data_dir: Option<PathBuf>,
    pub mnemonic: Option<String>,
    pub entropy_hex: Option<String>,
    pub force: bool,
}

pub fn run(args: InitArgs) -> Result<(), NodeError> {
    let data_dir = args.data_dir.unwrap_or_else(default_data_dir);

    let identity = match (args.mnemonic.as_deref(), args.entropy_hex.as_deref()) {
        (Some(_), Some(_)) => {
            return Err(NodeError::InvalidArguments(
                "specify either --mnemonic or --entropy, not both".into(),
            ))
        },
        (Some(m), None) => Identity::from_mnemonic(m.trim())?,
        (None, Some(hex)) => {
            let entropy = parse_entropy_hex(hex)?;
            Identity::from_entropy(&entropy)?
        },
        (None, None) => {
            // Один источник корня на весь протокол — ядро; узел не берёт
            // случайность сам, как и телефон.
            let entropy = mt_mnemonic::generate_entropy()
                .map_err(|e| NodeError::InvalidArguments(format!("entropy: {e}")))?;
            Identity::from_entropy(&entropy)?
        },
    };

    let path = save_identity(&data_dir, &identity, args.force)?;

    println!("=== montana-node init ===");
    println!();
    println!("data-dir         : {}", data_dir.display());
    println!("identity         : {}", path.display());
    println!("file size        : {IDENTITY_FILE_SIZE} bytes");
    println!("mode             : {IDENTITY_FILE_MODE:o} (owner only)");
    println!();
    println!("--- mnemonic (24 words — write down in a safe place) ---");
    emit_mnemonic(&identity.mnemonic);
    println!();
    println!("--- terminal identifiers ---");
    println!("account_id       : {}", hex_lower(&identity.account_id()));
    println!("node_id          : {}", hex_lower(&identity.node_id()));
    println!(
        "master_seed_fp   : {} (8-byte fingerprint, not secret)",
        hex_lower(&identity.master_seed_fingerprint())
    );
    // Оператор собирает genesis-manifest по ЭТОЙ строке, поэтому печатается тот
    // идентификатор, которым узел представляется в сети: производный от node_pk (ML-DSA-65),
    // тот же, что предъявляет Noise_PQ XX. Прежде здесь печатался транспортный libp2p-ключ, и
    // всякий входящий вызов к такому узлу отвергался несовпадением идентификатора.
    match mt_net_transport::derive_peer_id(&identity.node_pk) {
        Ok(pid) => println!("network_peer_id  : {pid}  (Noise_PQ XX — set in genesis-manifest)"),
        Err(e) => println!("network_peer_id  : <output error: {e}>"),
    }
    println!();
    println!("Secret keys (account_sk/node_sk/mlkem_sk) saved in identity.bin");
    println!("and are not printed. For backup use the mnemonic above.");

    Ok(())
}

fn parse_entropy_hex(s: &str) -> Result<[u8; 32], NodeError> {
    let clean: String = s.chars().filter(|c| !c.is_whitespace()).collect();
    if clean.len() != 64 {
        return Err(NodeError::InvalidEntropyHex);
    }
    let mut out = [0u8; 32];
    for i in 0..32 {
        let byte = u8::from_str_radix(&clean[i * 2..i * 2 + 2], 16)
            .map_err(|_| NodeError::InvalidEntropyHex)?;
        out[i] = byte;
    }
    // Энтропия, пришедшая снаружи, проходит те же проверки здоровья, что и своя:
    // вырожденный блок не становится личностью, каким бы путём он ни пришёл.
    mt_mnemonic::health_check(&out).map_err(|_| NodeError::InvalidEntropyHex)?;
    Ok(out)
}

fn hex_lower(bytes: &[u8]) -> String {
    let mut s = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        s.push_str(&format!("{b:02x}"));
    }
    s
}

// Фраза идёт на терминал оператора напрямую. При `montana-node init > install.log`
// стандартный поток уходит в файл, и корень личности оседает на диске открытым —
// там, где его никто больше не сотрёт.
fn emit_mnemonic(mnemonic: &str) {
    let grid = mnemonic_grid(mnemonic);

    #[cfg(unix)]
    {
        use std::io::Write;
        if let Ok(mut tty) = std::fs::OpenOptions::new().write(true).open("/dev/tty") {
            if tty.write_all(grid.as_bytes()).is_ok() && tty.flush().is_ok() {
                println!("  (24 words went to the operator terminal; they are not in this stream)");
                return;
            }
        }
    }

    print!("{grid}");
    println!("  WARNING: this output is not a terminal — the phrase is now inside this stream.");
    println!("  Treat the stream as secret and erase it once the words are copied down.");
}

fn mnemonic_grid(mnemonic: &str) -> String {
    let words: Vec<&str> = mnemonic.split(' ').collect();
    let mut out = String::with_capacity(words.len() * 18);
    for (i, w) in words.iter().enumerate() {
        out.push_str(&format!("  [{:>2}] {:<10}", i + 1, w));
        if (i + 1) % 4 == 0 {
            out.push('\n');
        }
    }
    if words.len() % 4 != 0 {
        out.push('\n');
    }
    out
}
