#![cfg_attr(not(any(test, feature = "testing")), no_std)]

extern crate alloc;

pub mod dandelion;
pub mod envelope;
pub mod error;
pub mod framing;
pub mod ibt;
pub mod mesh;
pub mod msg_type;
pub mod nat;
pub mod payloads;
pub mod peers;
pub mod reachability;
pub mod store_forward;

pub use dandelion::{
    DandelionDecision, DandelionState, STEM_FLUFF_PROB_DEN, STEM_FLUFF_PROB_NUM, STEM_HARD_CAP_HOPS,
};
pub use envelope::{
    decode_envelope, encode_envelope, ProtocolMessage, ENVELOPE_HEADER_SIZE, MSG_VERSION_V1,
};
pub use error::NetError;
pub use framing::{
    decode_frame, decode_message_from_frames, encode_frame, encode_message_to_frames, Frame,
    FrameWindowState, FLAG_CONTINUATION, FLAG_DATA, FLAG_PADDING, FRAME_HEADER_SIZE,
    FRAME_PAYLOAD_CAP, FRAME_SIZE, MAX_BURST_FRAMES, MIN_PADDING_RATIO_DEN, MIN_PADDING_RATIO_NUM,
};
pub use ibt::{
    ibt_mesh_message, ibt_mesh_proof, ibt_mesh_verify_explicit, ibt_mesh_verify_with_window,
    ibt_online_message, ibt_online_proof, ibt_online_verify, IbtError, OnlineNonceTracker,
    DOMAIN_TUNNEL_MESH, DOMAIN_TUNNEL_ONLINE, MESH_NONCE_SIZE, MESH_STALENESS_BOUND_TAU1,
    ONLINE_NONCE_SIZE,
};
pub use mesh::{
    apply_mesh_frame, decode_mesh_frame, encode_mesh_frame, LocalMeshState, MeshFrame, MeshIntake,
    MeshRejectReason, MESH_BROADCAST_HINT, MESH_FLAG_CONTINUATION, MESH_HEADER_SIZE,
    MESH_RECIPIENT_HINT_SIZE,
};

pub use msg_type::MsgType;
pub use nat::{
    NatMethod, NatState, ReachabilityHint, UpnpMapping, UPNP_RENEW_INTERVAL_LOCAL_SECONDS,
};
pub use payloads::{
    BatchLookupError, Bye, FastSyncError, FastSyncRequest, FastSyncResponseChunk, IpAddrV,
    PeerEntry, PeerListRequest, PeerListResponse, RangeSubscribeError, RangeSubscribeRequest,
    TableId, BATCH_LOOKUP_ERROR_SIZE, BYE_SIZE, FASTSYNC_REQUEST_SIZE, PEER_ENTRY_SIZE,
    PEER_LIST_REQUEST_SIZE, RANGE_SUBSCRIBE_ERROR_SIZE,
};
pub use peers::{
    check_diversity, DiversityViolation, PeerRecord, PeerRole, PeerTable, MAX_PEER_RECORDS,
    PRUNING_IDLE_TAU1_MULTIPLIER, ROTATION_PER_TAU2,
};
pub use reachability::{
    RankedEntry, ReachabilityAdvert, ReachabilityMap, MAX_OBSERVATIONS_PER_VANTAGE, PROFILE_MAX,
    REACHABILITY_ADVERT_SIZE, REACHABILITY_QUORUM,
};
pub use store_forward::{
    apply_store_and_forward, decode_sf_envelope, encode_sf_envelope, LocalSfState, SfEnvelope,
    SfIntake, SfRejectReason, SF_HEADER_SIZE, SF_PER_SENDER_QUOTA_PER_TAU1, SF_RECIPIENT_HINT_SIZE,
    SF_SENDER_SIG_SIZE, SF_TOTAL_HARD_CAP_BYTES, SF_TTL_HARD_CAP_TAU1,
};
