use std::path::{Path, PathBuf};

use crate::identity::{
    default_data_dir, save_identity, Identity, NodeError, IDENTITY_FILE_MODE, IDENTITY_FILE_SIZE,
};

pub struct InitArgs {
    pub data_dir: Option<PathBuf>,
    pub mnemonic: Option<String>,
    pub entropy_hex: Option<String>,
    pub force: bool,
    pub recovery_file: Option<PathBuf>,
}

pub fn run(args: InitArgs) -> Result<(), NodeError> {
    let data_dir = args.data_dir.unwrap_or_else(default_data_dir);

    let identity = match (args.mnemonic.as_deref(), args.entropy_hex.as_deref()) {
        (Some(_), Some(_)) => {
            return Err(NodeError::InvalidArguments(
                "specify either --mnemonic or --entropy, not both".into(),
            ))
        },
        (Some(m), None) => Identity::from_mnemonic(m.trim())
            .map_err(|_| NodeError::InvalidArguments("invalid recovery phrase".into()))?,
        (None, Some(hex)) => {
            let entropy = parse_entropy_hex(hex)?;
            Identity::from_entropy(&entropy)?
        },
        (None, None) => {
            // One source of the root for the whole protocol — the core; the node does not take
            // randomness itself, just like the phone.
            let entropy = mt_mnemonic::generate_entropy()
                .map_err(|e| NodeError::InvalidArguments(format!("entropy: {e}")))?;
            Identity::from_entropy(&entropy)?
        },
    };

    let path = crate::identity::identity_path(&data_dir);
    if path.exists() && !args.force {
        return Err(NodeError::IdentityAlreadyExists(path));
    }
    std::fs::create_dir_all(&data_dir)?;
    let recovery = args
        .recovery_file
        .unwrap_or_else(|| data_dir.join("mnemonic.txt"));
    // Preserve recovery before changing identity.bin, including a forced replacement.
    // A failure leaves the private artifact for inspection; it never enables overwrite.
    write_recovery(&recovery, &identity.mnemonic)?;
    save_identity(&data_dir, &identity, args.force)?;

    println!("identity initialized; recovery phrase saved to the private recovery file");
    println!("file size: {IDENTITY_FILE_SIZE} bytes; identity mode: {IDENTITY_FILE_MODE:o}");

    Ok(())
}

fn parse_entropy_hex(s: &str) -> Result<[u8; 32], NodeError> {
    let clean: String = s.chars().filter(|c| !c.is_whitespace()).collect();
    if clean.len() != 64 || !clean.is_ascii() {
        return Err(NodeError::InvalidEntropyHex);
    }
    let mut out = [0u8; 32];
    for i in 0..32 {
        let byte = u8::from_str_radix(&clean[i * 2..i * 2 + 2], 16)
            .map_err(|_| NodeError::InvalidEntropyHex)?;
        out[i] = byte;
    }
    // Entropy that arrives from outside passes the same health checks as our own:
    // a degenerate block does not become an identity, whatever path it came by.
    mt_mnemonic::health_check(&out).map_err(|_| NodeError::InvalidEntropyHex)?;
    Ok(out)
}

#[cfg(unix)]
fn write_recovery(path: &Path, mnemonic: &str) -> Result<(), NodeError> {
    use std::io::Write;
    use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};

    let mut file = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o400)
        .open(path)?;
    file.set_permissions(std::fs::Permissions::from_mode(0o400))?;
    file.write_all(mnemonic.as_bytes())?;
    file.write_all(b"\n")?;
    file.sync_all()?;
    let parent = path
        .parent()
        .filter(|p| !p.as_os_str().is_empty())
        .unwrap_or(Path::new("."));
    std::fs::File::open(parent)?.sync_all()?;
    Ok(())
}

#[cfg(not(unix))]
fn write_recovery(_path: &Path, _mnemonic: &str) -> Result<(), NodeError> {
    Err(NodeError::InvalidArguments(
        "private recovery output requires an owner-only filesystem implementation on this platform"
            .into(),
    ))
}
