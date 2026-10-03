use std::fs;
use std::path::{Path, PathBuf};

use mt_crypto::Hash32;
use mt_genesis::ProtocolParams;

use crate::clock::meta_dir;
use crate::identity::{Identity, NodeError};

pub const NODE_STATE_FILE: &str = "node_state.bin";
const MAGIC: &[u8; 4] = b"mtns";
const VERSION: u8 = 1;
const SIZE: usize = 4 + 1 + 1 + 2 + 32 + 32 + 8 + 8 + 8 + 8 + 32;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(u8)]
pub enum NodePhase {
    Bootstrap = 0,
    CandidateSsha = 1,
    Registered = 2,
    Active = 3,
}

impl NodePhase {
    fn from_u8(v: u8) -> Result<Self, NodeError> {
        match v {
            0 => Ok(NodePhase::Bootstrap),
            1 => Ok(NodePhase::CandidateSsha),
            2 => Ok(NodePhase::Registered),
            3 => Ok(NodePhase::Active),
            other => Err(NodeError::InvalidArguments(format!(
                "неизвестный node_phase: {other}"
            ))),
        }
    }
}

pub struct NodeLifecycle {
    pub phase: NodePhase,
    pub candidate_seed: Hash32,
    pub candidate_endpoint: Hash32,
    pub candidate_progress: u64,
    pub target_chain_length: u64,
    pub w_start: u64,
    pub registration_window: u64,
    pub nodereg_hash: Hash32,
}

impl NodeLifecycle {
    // Genesis = пустое окно 0: нет baked bootstrap-узла. Каждый узел стартует
    // кандидатом и self-admit-ит себя через стандартный admission path:
    // phase = Bootstrap → CandidateSsha на первом окне → Registered (через
    // apply_noderegistrations_batch) → Active (через apply_selection_event на
    // ближайшем W % selection_interval == 0). При нулевом Active-наборе
    // selection_slots(0)=1 принимает первого кандидата сразу.
    pub fn fresh_for(_identity: &Identity, _params: &ProtocolParams) -> Self {
        Self::fresh_candidate()
    }

    fn fresh_candidate() -> Self {
        Self {
            phase: NodePhase::Bootstrap,
            candidate_seed: [0u8; 32],
            candidate_endpoint: [0u8; 32],
            candidate_progress: 0,
            target_chain_length: 0,
            w_start: 0,
            registration_window: 0,
            nodereg_hash: [0u8; 32],
        }
    }
}

pub fn lifecycle_path(data_dir: &Path) -> PathBuf {
    meta_dir(data_dir).join(NODE_STATE_FILE)
}

pub fn load_or_init_lifecycle(
    data_dir: &Path,
    identity: &Identity,
    params: &ProtocolParams,
) -> Result<NodeLifecycle, NodeError> {
    let path = lifecycle_path(data_dir);
    if !path.exists() {
        return Ok(NodeLifecycle::fresh_for(identity, params));
    }
    let bytes = fs::read(&path)?;
    if bytes.len() != SIZE {
        return Err(NodeError::CorruptedSize {
            expected: SIZE,
            actual: bytes.len(),
        });
    }
    if &bytes[0..4] != MAGIC.as_slice() {
        return Err(NodeError::InvalidMagic);
    }
    if bytes[4] != VERSION {
        return Err(NodeError::UnsupportedVersion(bytes[4]));
    }
    let phase = NodePhase::from_u8(bytes[5])?;
    let mut candidate_seed = [0u8; 32];
    candidate_seed.copy_from_slice(&bytes[8..40]);
    let mut candidate_endpoint = [0u8; 32];
    candidate_endpoint.copy_from_slice(&bytes[40..72]);
    let candidate_progress = u64::from_le_bytes(bytes[72..80].try_into().unwrap());
    let target_chain_length = u64::from_le_bytes(bytes[80..88].try_into().unwrap());
    let w_start = u64::from_le_bytes(bytes[88..96].try_into().unwrap());
    let registration_window = u64::from_le_bytes(bytes[96..104].try_into().unwrap());
    let mut nodereg_hash = [0u8; 32];
    nodereg_hash.copy_from_slice(&bytes[104..136]);
    Ok(NodeLifecycle {
        phase,
        candidate_seed,
        candidate_endpoint,
        candidate_progress,
        target_chain_length,
        w_start,
        registration_window,
        nodereg_hash,
    })
}

pub fn save_lifecycle(data_dir: &Path, state: &NodeLifecycle) -> Result<(), NodeError> {
    fs::create_dir_all(meta_dir(data_dir))?;
    let path = lifecycle_path(data_dir);
    let mut buf = vec![0u8; SIZE];
    buf[0..4].copy_from_slice(MAGIC);
    buf[4] = VERSION;
    buf[5] = state.phase as u8;
    buf[8..40].copy_from_slice(&state.candidate_seed);
    buf[40..72].copy_from_slice(&state.candidate_endpoint);
    buf[72..80].copy_from_slice(&state.candidate_progress.to_le_bytes());
    buf[80..88].copy_from_slice(&state.target_chain_length.to_le_bytes());
    buf[88..96].copy_from_slice(&state.w_start.to_le_bytes());
    buf[96..104].copy_from_slice(&state.registration_window.to_le_bytes());
    buf[104..136].copy_from_slice(&state.nodereg_hash);
    let tmp = path.with_extension("bin.tmp");
    fs::write(&tmp, &buf)?;
    fs::rename(&tmp, &path)?;
    Ok(())
}
