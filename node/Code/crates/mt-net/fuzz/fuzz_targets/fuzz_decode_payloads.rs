#![no_main]

use libfuzzer_sys::fuzz_target;
use mt_net::{
    BatchLookupError, Bye, FastSyncError, FastSyncRequest, FastSyncResponseChunk, PeerEntry,
    PeerListRequest, PeerListResponse, RangeSubscribeError, RangeSubscribeRequest,
};

fuzz_target!(|data: &[u8]| {
    let _ = FastSyncRequest::decode(data);
    let _ = FastSyncResponseChunk::decode(data);
    let _ = FastSyncError::decode(data);
    let _ = PeerListRequest::decode(data);
    let _ = PeerEntry::decode(data);
    let _ = PeerListResponse::decode(data);
    let _ = BatchLookupError::decode(data);
    let _ = RangeSubscribeRequest::decode(data);
    let _ = RangeSubscribeError::decode(data);
    let _ = Bye::decode(data);
});
