use std::fs;
use std::io;
use std::path::{Path, PathBuf};

use mt_codec::domain;
use mt_crypto::{
    keypair_from_seed, keypair_from_seed_mlkem, sha256_raw, CryptoError, MlkemPublicKey,
    MlkemSecretKey, PublicKey, SecretKey, SuiteId, MLKEM_PUBLIC_KEY_SIZE, MLKEM_SECRET_KEY_SIZE,
    PUBLIC_KEY_SIZE, SECRET_KEY_SIZE,
};
use mt_mnemonic::{
    ed25519_seed_for_role, entropy_to_mnemonic, mldsa_seed_for_role, mlkem_seed_for_role,
    mnemonic_to_master_seed, MnemonicError, ED25519_SEED_LEN, MASTER_SEED_LEN,
};
use mt_state::{derive_account_id, derive_node_id, AccountId, NodeId};
use zeroize::Zeroize;

// Identity file format magic — production-grade naming per [C-12].
// "montana1" = ASCII «montana» + версия 1; 8 байт fixed.
// Не использовать префикс "mt-" — он зарезервирован за domain registry
// (mt-codec::domain, 32 separator) и file format magic не относится к
// consensus hash compositions.
pub const IDENTITY_MAGIC: &[u8; 8] = b"montana1";
pub const IDENTITY_VERSION: u8 = 1;
// spec, раздел "Identity persistence modes" — Mode B (ephemeral, без master_seed)
pub const IDENTITY_VERSION_V2: u8 = 2;

const OFFSET_MAGIC: usize = 0;
const OFFSET_VERSION: usize = 8;
const OFFSET_SUITE: usize = 9;
const OFFSET_MASTER_SEED: usize = 11;
const OFFSET_ACCOUNT_PK: usize = OFFSET_MASTER_SEED + MASTER_SEED_LEN;
const OFFSET_ACCOUNT_SK: usize = OFFSET_ACCOUNT_PK + PUBLIC_KEY_SIZE;
const OFFSET_NODE_PK: usize = OFFSET_ACCOUNT_SK + SECRET_KEY_SIZE;
const OFFSET_NODE_SK: usize = OFFSET_NODE_PK + PUBLIC_KEY_SIZE;
const OFFSET_MLKEM_PK: usize = OFFSET_NODE_SK + SECRET_KEY_SIZE;
const OFFSET_MLKEM_SK: usize = OFFSET_MLKEM_PK + MLKEM_PUBLIC_KEY_SIZE;

pub const IDENTITY_FILE_SIZE: usize = OFFSET_MLKEM_SK + MLKEM_SECRET_KEY_SIZE;

// Права на файл личности живут здесь и только здесь: печать, запись и проверка
// читают одно значение, поэтому расходиться им не в чем.
pub const IDENTITY_FILE_MODE: u32 = 0o600;

// V2 layout (Mode B — ephemeral) без master_seed; libp2p Ed25519 secret хранится
// напрямую (т.к. derive из master_seed невозможен — он zeroized).
// magic[8] || version[1] || suite[2] || account_pk || account_sk || node_pk || node_sk
// || mlkem_pk || mlkem_sk || libp2p_secret[32]
const OFFSET_V2_ACCOUNT_PK: usize = OFFSET_MASTER_SEED;
const OFFSET_V2_ACCOUNT_SK: usize = OFFSET_V2_ACCOUNT_PK + PUBLIC_KEY_SIZE;
const OFFSET_V2_NODE_PK: usize = OFFSET_V2_ACCOUNT_SK + SECRET_KEY_SIZE;
const OFFSET_V2_NODE_SK: usize = OFFSET_V2_NODE_PK + PUBLIC_KEY_SIZE;
const OFFSET_V2_MLKEM_PK: usize = OFFSET_V2_NODE_SK + SECRET_KEY_SIZE;
const OFFSET_V2_MLKEM_SK: usize = OFFSET_V2_MLKEM_PK + MLKEM_PUBLIC_KEY_SIZE;
const OFFSET_V2_LIBP2P_SK: usize = OFFSET_V2_MLKEM_SK + MLKEM_SECRET_KEY_SIZE;
pub const IDENTITY_FILE_SIZE_V2: usize = OFFSET_V2_LIBP2P_SK + ED25519_SEED_LEN;

pub struct Identity {
    pub suite_id: SuiteId,
    /// В Mode A (recoverable) — реальный master_seed.
    /// В Mode B (ephemeral) — `[0u8; 64]` placeholder (master_seed уничтожен).
    pub master_seed: [u8; MASTER_SEED_LEN],
    /// `true` — Mode B, identity.bin будет писаться без master_seed (v2 layout).
    pub is_ephemeral: bool,
    pub mnemonic: String,
    pub account_pk: PublicKey,
    pub account_sk: SecretKey,
    pub node_pk: PublicKey,
    pub node_sk: SecretKey,
    pub mlkem_pk: MlkemPublicKey,
    pub mlkem_sk: MlkemSecretKey,
    /// libp2p Ed25519 transport secret (32 байта) — раздельная identity для
    /// network уровня (PeerId), independent от ML-DSA consensus identity.
    /// Mode A: derived из master_seed через ed25519_seed_for_role. Не хранится
    /// в файле (rederivable). Mode B: сохраняется напрямую в V2 layout.
    pub libp2p_secret: [u8; ED25519_SEED_LEN],
}

impl Identity {
    /// [I-16] admission A-1: Ed25519 — формальный аргумент SwarmBuilder libp2p,
    /// НЕ Montana-identity (та — ML-DSA-65 `derive_peer_id`, mt-net-transport).
    /// Построить libp2p Keypair из стораного secret (Ed25519).
    /// Используется для конструирования `libp2p::identity::Keypair` каждый
    /// раз on-demand — Keypair не хранится в struct, чтобы избежать
    /// drift между сериализованным состоянием и runtime-ом.
    pub fn libp2p_keypair(&self) -> libp2p::identity::Keypair {
        let mut bytes = self.libp2p_secret;
        libp2p::identity::Keypair::ed25519_from_bytes(&mut bytes)
            .expect("32-байтный Ed25519 seed всегда валиден")
    }

    /// PeerId узла на libp2p уровне (multiaddr `/p2p/<peer_id>`).
    pub fn libp2p_peer_id(&self) -> libp2p::PeerId {
        self.libp2p_keypair().public().to_peer_id()
    }
}

impl Drop for Identity {
    fn drop(&mut self) {
        // Транспортный секрет — zeroize при drop. master_seed Mode A — также.
        // ML-DSA / ML-KEM SK содержат собственный Drop через mt-crypto.
        self.libp2p_secret.zeroize();
        self.master_seed.zeroize();
    }
}

impl Identity {
    pub fn account_id(&self) -> AccountId {
        derive_account_id(self.suite_id as u16, self.account_pk.as_bytes())
    }

    pub fn node_id(&self) -> NodeId {
        derive_node_id(self.node_pk.as_bytes())
    }

    pub fn master_seed_fingerprint(&self) -> [u8; 8] {
        let h = sha256_raw(&self.master_seed);
        let mut out = [0u8; 8];
        out.copy_from_slice(&h[..8]);
        out
    }

    pub fn from_master_seed(master_seed: [u8; MASTER_SEED_LEN]) -> Result<Self, NodeError> {
        let acc_seed = mldsa_seed_for_role(&master_seed, domain::ACCOUNT_KEY);
        let node_seed = mldsa_seed_for_role(&master_seed, domain::NODE_KEY);
        let mlkem_seed = mlkem_seed_for_role(&master_seed, domain::APP_ENCRYPTION_KEY);
        let libp2p_secret = ed25519_seed_for_role(&master_seed, domain::LIBP2P_TRANSPORT_KEY);

        let (account_pk, account_sk) = keypair_from_seed(&acc_seed).map_err(NodeError::Crypto)?;
        let (node_pk, node_sk) = keypair_from_seed(&node_seed).map_err(NodeError::Crypto)?;
        let (mlkem_pk, mlkem_sk) =
            keypair_from_seed_mlkem(&mlkem_seed).map_err(NodeError::Crypto)?;

        Ok(Self {
            suite_id: SuiteId::Mldsa65,
            master_seed,
            is_ephemeral: false,
            mnemonic: String::new(),
            account_pk,
            account_sk,
            node_pk,
            node_sk,
            mlkem_pk,
            mlkem_sk,
            libp2p_secret,
        })
    }

    /// spec, раздел "Identity persistence modes" — Mode B.
    /// Derive все ключи + zeroize master_seed в RAM. Identity содержит
    /// master_seed=[0;64] placeholder и is_ephemeral=true. При save
    /// будет записан v2 layout без master_seed.
    pub fn from_master_seed_ephemeral(
        master_seed: [u8; MASTER_SEED_LEN],
    ) -> Result<Self, NodeError> {
        let mut id = Self::from_master_seed(master_seed)?;
        id.master_seed.zeroize();
        id.is_ephemeral = true;
        Ok(id)
    }

    pub fn from_mnemonic_ephemeral(mnemonic: &str) -> Result<Self, NodeError> {
        let master_seed = mnemonic_to_master_seed(mnemonic).map_err(NodeError::Mnemonic)?;
        let mut id = Self::from_master_seed_ephemeral(master_seed)?;
        // Не сохраняем мнемонику в struct в Mode B — она для оператора-spec
        // не должна оставаться в RAM узла после derivation.
        id.mnemonic = String::new();
        Ok(id)
    }

    pub fn from_entropy_ephemeral(entropy: &[u8; 32]) -> Result<Self, NodeError> {
        let mnemonic = entropy_to_mnemonic(entropy);
        Self::from_mnemonic_ephemeral(&mnemonic)
    }

    pub fn from_entropy(entropy: &[u8; 32]) -> Result<Self, NodeError> {
        let mnemonic = entropy_to_mnemonic(entropy);
        let mut id = Self::from_mnemonic(&mnemonic)?;
        id.mnemonic = mnemonic;
        Ok(id)
    }

    pub fn from_mnemonic(mnemonic: &str) -> Result<Self, NodeError> {
        let master_seed = mnemonic_to_master_seed(mnemonic).map_err(NodeError::Mnemonic)?;
        let mut id = Self::from_master_seed(master_seed)?;
        id.mnemonic = mnemonic.to_string();
        Ok(id)
    }
}

#[derive(Debug)]
pub enum NodeError {
    Io(io::Error),
    Mnemonic(MnemonicError),
    Crypto(CryptoError),
    InvalidMagic,
    UnsupportedVersion(u8),
    UnsupportedSuite(u16),
    CorruptedSize { expected: usize, actual: usize },
    InvalidEntropyHex,
    IdentityAlreadyExists(PathBuf),
    InvalidArguments(String),
    Network(String),
}

impl std::fmt::Display for NodeError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            NodeError::Io(e) => write!(f, "ошибка ввода-вывода: {e}"),
            NodeError::Mnemonic(e) => write!(f, "ошибка мнемоники: {e:?}"),
            NodeError::Crypto(e) => write!(f, "ошибка криптографии: {e:?}"),
            NodeError::InvalidMagic => write!(
                f,
                "файл identity.bin не принадлежит montana-node (неверный magic)"
            ),
            NodeError::UnsupportedVersion(v) => write!(
                f,
                "версия формата identity.bin = {v} не поддерживается; ожидалась {IDENTITY_VERSION} или {IDENTITY_VERSION_V2}"
            ),
            NodeError::UnsupportedSuite(s) => write!(
                f,
                "криптонабор {s} не поддерживается; ожидался ML-DSA-65 (1)"
            ),
            NodeError::CorruptedSize { expected, actual } => write!(
                f,
                "размер identity.bin = {actual} байт, ожидался {expected}"
            ),
            NodeError::InvalidEntropyHex => write!(
                f,
                "значение --entropy должно быть 64 hex-символа (32 байта энтропии)"
            ),
            NodeError::IdentityAlreadyExists(p) => write!(
                f,
                "identity.bin уже существует ({}); используйте --force для перезаписи",
                p.display()
            ),
            NodeError::InvalidArguments(s) => write!(f, "неверные аргументы: {s}"),
            NodeError::Network(s) => write!(f, "ошибка сети: {s}"),
        }
    }
}

impl std::error::Error for NodeError {}

impl From<io::Error> for NodeError {
    fn from(e: io::Error) -> Self {
        NodeError::Io(e)
    }
}

pub fn default_data_dir() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| String::from("."));
    PathBuf::from(home)
        .join("Library")
        .join("Application Support")
        .join("Montana")
        .join("node")
}

pub fn identity_path(data_dir: &Path) -> PathBuf {
    data_dir.join("identity.bin")
}

pub fn save_identity(
    data_dir: &Path,
    identity: &Identity,
    force: bool,
) -> Result<PathBuf, NodeError> {
    fs::create_dir_all(data_dir)?;
    let path = identity_path(data_dir);
    if path.exists() && !force {
        return Err(NodeError::IdentityAlreadyExists(path));
    }

    let buf = if identity.is_ephemeral {
        // Mode B (v2) — без master_seed; libp2p_secret хранится напрямую
        let mut b = vec![0u8; IDENTITY_FILE_SIZE_V2];
        b[OFFSET_MAGIC..OFFSET_MAGIC + 8].copy_from_slice(IDENTITY_MAGIC);
        b[OFFSET_VERSION] = IDENTITY_VERSION_V2;
        b[OFFSET_SUITE..OFFSET_SUITE + 2]
            .copy_from_slice(&(identity.suite_id as u16).to_le_bytes());
        b[OFFSET_V2_ACCOUNT_PK..OFFSET_V2_ACCOUNT_SK]
            .copy_from_slice(identity.account_pk.as_bytes());
        b[OFFSET_V2_ACCOUNT_SK..OFFSET_V2_NODE_PK].copy_from_slice(identity.account_sk.as_bytes());
        b[OFFSET_V2_NODE_PK..OFFSET_V2_NODE_SK].copy_from_slice(identity.node_pk.as_bytes());
        b[OFFSET_V2_NODE_SK..OFFSET_V2_MLKEM_PK].copy_from_slice(identity.node_sk.as_bytes());
        b[OFFSET_V2_MLKEM_PK..OFFSET_V2_MLKEM_SK].copy_from_slice(identity.mlkem_pk.as_bytes());
        b[OFFSET_V2_MLKEM_SK..OFFSET_V2_LIBP2P_SK].copy_from_slice(identity.mlkem_sk.as_bytes());
        b[OFFSET_V2_LIBP2P_SK..].copy_from_slice(&identity.libp2p_secret);
        b
    } else {
        // Mode A (v1) — с master_seed
        let mut b = vec![0u8; IDENTITY_FILE_SIZE];
        b[OFFSET_MAGIC..OFFSET_MAGIC + 8].copy_from_slice(IDENTITY_MAGIC);
        b[OFFSET_VERSION] = IDENTITY_VERSION;
        b[OFFSET_SUITE..OFFSET_SUITE + 2]
            .copy_from_slice(&(identity.suite_id as u16).to_le_bytes());
        b[OFFSET_MASTER_SEED..OFFSET_ACCOUNT_PK].copy_from_slice(&identity.master_seed);
        b[OFFSET_ACCOUNT_PK..OFFSET_ACCOUNT_SK].copy_from_slice(identity.account_pk.as_bytes());
        b[OFFSET_ACCOUNT_SK..OFFSET_NODE_PK].copy_from_slice(identity.account_sk.as_bytes());
        b[OFFSET_NODE_PK..OFFSET_NODE_SK].copy_from_slice(identity.node_pk.as_bytes());
        b[OFFSET_NODE_SK..OFFSET_MLKEM_PK].copy_from_slice(identity.node_sk.as_bytes());
        b[OFFSET_MLKEM_PK..OFFSET_MLKEM_SK].copy_from_slice(identity.mlkem_pk.as_bytes());
        b[OFFSET_MLKEM_SK..].copy_from_slice(identity.mlkem_sk.as_bytes());
        b
    };

    write_owner_only(&path, &buf)?;
    Ok(path)
}

#[cfg(unix)]
fn write_owner_only(path: &Path, bytes: &[u8]) -> io::Result<()> {
    use std::os::unix::fs::OpenOptionsExt;
    let mut f = fs::OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(IDENTITY_FILE_MODE)
        .open(path)?;
    io::Write::write_all(&mut f, bytes)?;
    f.sync_all()?;
    Ok(())
}

#[cfg(not(unix))]
fn write_owner_only(path: &Path, bytes: &[u8]) -> io::Result<()> {
    fs::write(path, bytes)
}

pub fn load_identity(data_dir: &Path) -> Result<Identity, NodeError> {
    let path = identity_path(data_dir);
    let bytes = fs::read(&path)?;
    if bytes.len() < OFFSET_MASTER_SEED {
        return Err(NodeError::CorruptedSize {
            expected: OFFSET_MASTER_SEED,
            actual: bytes.len(),
        });
    }
    if &bytes[OFFSET_MAGIC..OFFSET_MAGIC + 8] != IDENTITY_MAGIC.as_slice() {
        return Err(NodeError::InvalidMagic);
    }
    match bytes[OFFSET_VERSION] {
        IDENTITY_VERSION => load_identity_v1(&bytes),
        IDENTITY_VERSION_V2 => load_identity_v2(&bytes),
        other => Err(NodeError::UnsupportedVersion(other)),
    }
}

fn parse_suite(bytes: &[u8]) -> Result<SuiteId, NodeError> {
    let suite_raw = u16::from_le_bytes([bytes[OFFSET_SUITE], bytes[OFFSET_SUITE + 1]]);
    match suite_raw {
        0x0001 => Ok(SuiteId::Mldsa65),
        other => Err(NodeError::UnsupportedSuite(other)),
    }
}

fn load_identity_v1(bytes: &[u8]) -> Result<Identity, NodeError> {
    if bytes.len() != IDENTITY_FILE_SIZE {
        return Err(NodeError::CorruptedSize {
            expected: IDENTITY_FILE_SIZE,
            actual: bytes.len(),
        });
    }
    let suite_id = parse_suite(bytes)?;

    let mut master_seed = [0u8; MASTER_SEED_LEN];
    master_seed.copy_from_slice(&bytes[OFFSET_MASTER_SEED..OFFSET_ACCOUNT_PK]);

    let account_pk = PublicKey::from_slice(&bytes[OFFSET_ACCOUNT_PK..OFFSET_ACCOUNT_SK]).ok_or(
        NodeError::CorruptedSize {
            expected: PUBLIC_KEY_SIZE,
            actual: OFFSET_ACCOUNT_SK - OFFSET_ACCOUNT_PK,
        },
    )?;
    let account_sk = SecretKey::from_slice(&bytes[OFFSET_ACCOUNT_SK..OFFSET_NODE_PK]).ok_or(
        NodeError::CorruptedSize {
            expected: SECRET_KEY_SIZE,
            actual: OFFSET_NODE_PK - OFFSET_ACCOUNT_SK,
        },
    )?;
    let node_pk = PublicKey::from_slice(&bytes[OFFSET_NODE_PK..OFFSET_NODE_SK]).ok_or(
        NodeError::CorruptedSize {
            expected: PUBLIC_KEY_SIZE,
            actual: OFFSET_NODE_SK - OFFSET_NODE_PK,
        },
    )?;
    let node_sk = SecretKey::from_slice(&bytes[OFFSET_NODE_SK..OFFSET_MLKEM_PK]).ok_or(
        NodeError::CorruptedSize {
            expected: SECRET_KEY_SIZE,
            actual: OFFSET_MLKEM_PK - OFFSET_NODE_SK,
        },
    )?;
    let mlkem_pk = MlkemPublicKey::from_slice(&bytes[OFFSET_MLKEM_PK..OFFSET_MLKEM_SK]).ok_or(
        NodeError::CorruptedSize {
            expected: MLKEM_PUBLIC_KEY_SIZE,
            actual: OFFSET_MLKEM_SK - OFFSET_MLKEM_PK,
        },
    )?;
    let mlkem_sk =
        MlkemSecretKey::from_slice(&bytes[OFFSET_MLKEM_SK..]).ok_or(NodeError::CorruptedSize {
            expected: MLKEM_SECRET_KEY_SIZE,
            actual: bytes.len() - OFFSET_MLKEM_SK,
        })?;

    let libp2p_secret = ed25519_seed_for_role(&master_seed, domain::LIBP2P_TRANSPORT_KEY);

    Ok(Identity {
        suite_id,
        master_seed,
        is_ephemeral: false,
        mnemonic: String::new(),
        account_pk,
        account_sk,
        node_pk,
        node_sk,
        mlkem_pk,
        mlkem_sk,
        libp2p_secret,
    })
}

fn load_identity_v2(bytes: &[u8]) -> Result<Identity, NodeError> {
    if bytes.len() != IDENTITY_FILE_SIZE_V2 {
        return Err(NodeError::CorruptedSize {
            expected: IDENTITY_FILE_SIZE_V2,
            actual: bytes.len(),
        });
    }
    let suite_id = parse_suite(bytes)?;

    let account_pk = PublicKey::from_slice(&bytes[OFFSET_V2_ACCOUNT_PK..OFFSET_V2_ACCOUNT_SK])
        .ok_or(NodeError::CorruptedSize {
            expected: PUBLIC_KEY_SIZE,
            actual: OFFSET_V2_ACCOUNT_SK - OFFSET_V2_ACCOUNT_PK,
        })?;
    let account_sk = SecretKey::from_slice(&bytes[OFFSET_V2_ACCOUNT_SK..OFFSET_V2_NODE_PK]).ok_or(
        NodeError::CorruptedSize {
            expected: SECRET_KEY_SIZE,
            actual: OFFSET_V2_NODE_PK - OFFSET_V2_ACCOUNT_SK,
        },
    )?;
    let node_pk = PublicKey::from_slice(&bytes[OFFSET_V2_NODE_PK..OFFSET_V2_NODE_SK]).ok_or(
        NodeError::CorruptedSize {
            expected: PUBLIC_KEY_SIZE,
            actual: OFFSET_V2_NODE_SK - OFFSET_V2_NODE_PK,
        },
    )?;
    let node_sk = SecretKey::from_slice(&bytes[OFFSET_V2_NODE_SK..OFFSET_V2_MLKEM_PK]).ok_or(
        NodeError::CorruptedSize {
            expected: SECRET_KEY_SIZE,
            actual: OFFSET_V2_MLKEM_PK - OFFSET_V2_NODE_SK,
        },
    )?;
    let mlkem_pk = MlkemPublicKey::from_slice(&bytes[OFFSET_V2_MLKEM_PK..OFFSET_V2_MLKEM_SK])
        .ok_or(NodeError::CorruptedSize {
            expected: MLKEM_PUBLIC_KEY_SIZE,
            actual: OFFSET_V2_MLKEM_SK - OFFSET_V2_MLKEM_PK,
        })?;
    let mlkem_sk = MlkemSecretKey::from_slice(&bytes[OFFSET_V2_MLKEM_SK..OFFSET_V2_LIBP2P_SK])
        .ok_or(NodeError::CorruptedSize {
            expected: MLKEM_SECRET_KEY_SIZE,
            actual: OFFSET_V2_LIBP2P_SK - OFFSET_V2_MLKEM_SK,
        })?;
    let mut libp2p_secret = [0u8; ED25519_SEED_LEN];
    libp2p_secret.copy_from_slice(&bytes[OFFSET_V2_LIBP2P_SK..]);

    Ok(Identity {
        suite_id,
        master_seed: [0u8; MASTER_SEED_LEN],
        is_ephemeral: true,
        mnemonic: String::new(),
        account_pk,
        account_sk,
        node_pk,
        node_sk,
        mlkem_pk,
        mlkem_sk,
        libp2p_secret,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn deterministic_identity_from_zero_entropy() {
        let entropy = [0u8; 32];
        let a = Identity::from_entropy(&entropy).expect("identity 1");
        let b = Identity::from_entropy(&entropy).expect("identity 2");
        assert_eq!(a.master_seed, b.master_seed);
        assert_eq!(a.account_id(), b.account_id());
        assert_eq!(a.node_id(), b.node_id());
        assert_eq!(a.account_pk.as_bytes(), b.account_pk.as_bytes());
        assert_eq!(a.node_pk.as_bytes(), b.node_pk.as_bytes());
        assert_eq!(a.mlkem_pk.as_bytes(), b.mlkem_pk.as_bytes());
    }

    #[test]
    fn distinct_entropy_distinct_terminals() {
        let mut e2 = [0u8; 32];
        e2[31] = 1;
        let a = Identity::from_entropy(&[0u8; 32]).unwrap();
        let b = Identity::from_entropy(&e2).unwrap();
        assert_ne!(a.account_id(), b.account_id());
        assert_ne!(a.node_id(), b.node_id());
    }

    #[test]
    fn account_and_node_ids_differ_for_same_master() {
        let id = Identity::from_entropy(&[0u8; 32]).unwrap();
        assert_ne!(
            id.account_id(),
            id.node_id(),
            "разные роли HKDF должны давать разные seed → разные ключи → разные id"
        );
    }

    #[test]
    fn save_load_roundtrip_byte_exact() {
        let dir = tempdir();
        let original = Identity::from_entropy(&[7u8; 32]).unwrap();
        let path = save_identity(&dir, &original, false).expect("save");
        assert!(path.exists());
        let meta = fs::metadata(&path).unwrap();
        assert_eq!(meta.len() as usize, IDENTITY_FILE_SIZE);

        let loaded = load_identity(&dir).expect("load");
        assert_eq!(original.master_seed, loaded.master_seed);
        assert_eq!(original.account_id(), loaded.account_id());
        assert_eq!(original.node_id(), loaded.node_id());
        assert_eq!(original.account_pk.as_bytes(), loaded.account_pk.as_bytes());
        assert_eq!(original.account_sk.as_bytes(), loaded.account_sk.as_bytes());
        assert_eq!(original.node_sk.as_bytes(), loaded.node_sk.as_bytes());
        assert_eq!(original.mlkem_pk.as_bytes(), loaded.mlkem_pk.as_bytes());
        assert_eq!(original.mlkem_sk.as_bytes(), loaded.mlkem_sk.as_bytes());
    }

    #[test]
    fn save_refuses_overwrite_without_force() {
        let dir = tempdir();
        let id = Identity::from_entropy(&[0u8; 32]).unwrap();
        save_identity(&dir, &id, false).unwrap();
        let second = Identity::from_entropy(&[1u8; 32]).unwrap();
        let err = save_identity(&dir, &second, false).unwrap_err();
        matches!(err, NodeError::IdentityAlreadyExists(_));
    }

    #[test]
    fn save_force_overwrites() {
        let dir = tempdir();
        let id1 = Identity::from_entropy(&[0u8; 32]).unwrap();
        save_identity(&dir, &id1, false).unwrap();
        let id2 = Identity::from_entropy(&[1u8; 32]).unwrap();
        save_identity(&dir, &id2, true).expect("force overwrite");
        let loaded = load_identity(&dir).unwrap();
        assert_eq!(loaded.master_seed, id2.master_seed);
        assert_ne!(loaded.master_seed, id1.master_seed);
    }

    #[test]
    fn load_rejects_bad_magic() {
        let dir = tempdir();
        let id = Identity::from_entropy(&[0u8; 32]).unwrap();
        save_identity(&dir, &id, false).unwrap();
        let path = identity_path(&dir);
        let mut bytes = fs::read(&path).unwrap();
        bytes[0] = b'X';
        fs::write(&path, &bytes).unwrap();
        match load_identity(&dir) {
            Err(NodeError::InvalidMagic) => (),
            Err(other) => panic!("ожидался InvalidMagic, получили {other:?}"),
            Ok(_) => panic!("ожидалась ошибка InvalidMagic"),
        }
    }

    #[test]
    fn load_rejects_truncated_file() {
        let dir = tempdir();
        let id = Identity::from_entropy(&[0u8; 32]).unwrap();
        save_identity(&dir, &id, false).unwrap();
        let path = identity_path(&dir);
        let bytes = fs::read(&path).unwrap();
        fs::write(&path, &bytes[..bytes.len() - 100]).unwrap();
        match load_identity(&dir) {
            Err(NodeError::CorruptedSize { .. }) => (),
            Err(other) => panic!("ожидался CorruptedSize, получили {other:?}"),
            Ok(_) => panic!("ожидалась ошибка CorruptedSize"),
        }
    }

    #[test]
    #[cfg(unix)]
    fn saved_file_has_owner_only_permissions() {
        use std::os::unix::fs::PermissionsExt;
        let dir = tempdir();
        let id = Identity::from_entropy(&[0u8; 32]).unwrap();
        let path = save_identity(&dir, &id, false).unwrap();
        let mode = fs::metadata(&path).unwrap().permissions().mode() & 0o777;
        assert_eq!(
            mode, IDENTITY_FILE_MODE,
            "ожидался mode {IDENTITY_FILE_MODE:o}, получили {mode:o}"
        );
    }

    #[test]
    fn ephemeral_master_seed_is_zeroized() {
        // spec, раздел "Identity persistence modes" — Mode B
        let entropy = [42u8; 32];
        let id = Identity::from_entropy_ephemeral(&entropy).unwrap();
        assert!(id.is_ephemeral);
        assert_eq!(id.master_seed, [0u8; MASTER_SEED_LEN]);
        // derived keys остаются valid (signing capability сохраняется)
        assert!(!id.account_pk.as_bytes().is_empty());
    }

    #[test]
    fn ephemeral_save_load_roundtrip_v2() {
        let dir = tempdir();
        let original = Identity::from_entropy_ephemeral(&[7u8; 32]).unwrap();
        let path = save_identity(&dir, &original, false).expect("save v2");
        let meta = fs::metadata(&path).unwrap();
        assert_eq!(
            meta.len() as usize,
            IDENTITY_FILE_SIZE_V2,
            "v2 layout без master_seed"
        );

        let loaded = load_identity(&dir).expect("load v2");
        assert!(loaded.is_ephemeral);
        assert_eq!(loaded.master_seed, [0u8; MASTER_SEED_LEN]);
        // derived keys byte-exact
        assert_eq!(original.account_pk.as_bytes(), loaded.account_pk.as_bytes());
        assert_eq!(original.account_sk.as_bytes(), loaded.account_sk.as_bytes());
        assert_eq!(original.node_pk.as_bytes(), loaded.node_pk.as_bytes());
        assert_eq!(original.node_sk.as_bytes(), loaded.node_sk.as_bytes());
        assert_eq!(original.mlkem_pk.as_bytes(), loaded.mlkem_pk.as_bytes());
        assert_eq!(original.mlkem_sk.as_bytes(), loaded.mlkem_sk.as_bytes());
    }

    #[test]
    fn ephemeral_and_recoverable_produce_byte_identical_derived_keys() {
        // Тот же entropy → те же derived keys в обоих режимах
        let entropy = [99u8; 32];
        let recoverable = Identity::from_entropy(&entropy).unwrap();
        let ephemeral = Identity::from_entropy_ephemeral(&entropy).unwrap();
        assert_eq!(
            recoverable.account_pk.as_bytes(),
            ephemeral.account_pk.as_bytes()
        );
        assert_eq!(recoverable.node_pk.as_bytes(), ephemeral.node_pk.as_bytes());
        assert_eq!(
            recoverable.mlkem_pk.as_bytes(),
            ephemeral.mlkem_pk.as_bytes()
        );
    }

    #[test]
    fn v1_backwards_compat() {
        // V1 файл (с master_seed) продолжает корректно загружаться
        let dir = tempdir();
        let id = Identity::from_entropy(&[3u8; 32]).unwrap();
        save_identity(&dir, &id, false).unwrap();
        let path = identity_path(&dir);
        let meta = fs::metadata(&path).unwrap();
        assert_eq!(meta.len() as usize, IDENTITY_FILE_SIZE, "v1 layout");
        let loaded = load_identity(&dir).unwrap();
        assert!(!loaded.is_ephemeral);
        assert_eq!(loaded.master_seed, id.master_seed);
    }

    #[test]
    fn libp2p_secret_deterministic_from_master_seed() {
        let entropy = [0x55u8; 32];
        let a = Identity::from_entropy(&entropy).unwrap();
        let b = Identity::from_entropy(&entropy).unwrap();
        assert_eq!(a.libp2p_secret, b.libp2p_secret);
        assert_eq!(a.libp2p_peer_id(), b.libp2p_peer_id());
    }

    #[test]
    fn libp2p_secret_differs_from_node_seed_for_same_master() {
        // libp2p transport identity ≠ ML-DSA node consensus identity
        let id = Identity::from_entropy(&[0x77u8; 32]).unwrap();
        assert_ne!(&id.libp2p_secret[..], id.node_pk.as_bytes());
        assert_ne!(&id.libp2p_secret[..], id.account_pk.as_bytes());
    }

    #[test]
    fn libp2p_v1_save_load_rederives_secret() {
        // V1 не хранит libp2p_secret в файле — derive из master_seed при load
        let dir = tempdir();
        let original = Identity::from_entropy(&[0x88u8; 32]).unwrap();
        save_identity(&dir, &original, false).unwrap();
        let path = identity_path(&dir);
        let meta = fs::metadata(&path).unwrap();
        assert_eq!(
            meta.len() as usize,
            IDENTITY_FILE_SIZE,
            "V1 file size unchanged after libp2p addition (Ed25519 derivable from master_seed)"
        );
        let loaded = load_identity(&dir).unwrap();
        assert_eq!(original.libp2p_secret, loaded.libp2p_secret);
        assert_eq!(original.libp2p_peer_id(), loaded.libp2p_peer_id());
    }

    #[test]
    fn libp2p_v2_save_load_stores_secret() {
        // V2 ephemeral: libp2p_secret хранится напрямую (master_seed недоступен)
        let dir = tempdir();
        let original = Identity::from_entropy_ephemeral(&[0x99u8; 32]).unwrap();
        save_identity(&dir, &original, false).unwrap();
        let path = identity_path(&dir);
        let meta = fs::metadata(&path).unwrap();
        assert_eq!(
            meta.len() as usize,
            IDENTITY_FILE_SIZE_V2,
            "V2 file size = old + 32 байт Ed25519"
        );
        let loaded = load_identity(&dir).unwrap();
        assert!(loaded.is_ephemeral);
        assert_eq!(loaded.master_seed, [0u8; MASTER_SEED_LEN]);
        assert_eq!(original.libp2p_secret, loaded.libp2p_secret);
        assert_eq!(original.libp2p_peer_id(), loaded.libp2p_peer_id());
    }

    #[test]
    fn libp2p_v1_v2_produce_byte_identical_libp2p_secrets() {
        // тот же entropy → тот же libp2p_secret в обоих режимах
        let entropy = [0xaau8; 32];
        let v1 = Identity::from_entropy(&entropy).unwrap();
        let v2 = Identity::from_entropy_ephemeral(&entropy).unwrap();
        assert_eq!(v1.libp2p_secret, v2.libp2p_secret);
        assert_eq!(v1.libp2p_peer_id(), v2.libp2p_peer_id());
    }

    #[test]
    fn libp2p_keypair_constructs_valid_peer_id() {
        // Sanity: PeerId не [0;...] и стабилен между вызовами
        let id = Identity::from_entropy(&[0xbbu8; 32]).unwrap();
        let p1 = id.libp2p_peer_id();
        let p2 = id.libp2p_peer_id();
        assert_eq!(p1, p2);
        // PeerId — multihash; non-empty
        assert!(!p1.to_bytes().is_empty());
    }

    fn tempdir() -> PathBuf {
        let mut p = std::env::temp_dir();
        let nonce: u64 = {
            let mut buf = [0u8; 8];
            getrandom::getrandom(&mut buf).unwrap();
            u64::from_le_bytes(buf)
        };
        p.push(format!("montana-node-test-{nonce:016x}"));
        fs::create_dir_all(&p).unwrap();
        p
    }
}
