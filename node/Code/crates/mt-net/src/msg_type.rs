use crate::error::NetError;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum MsgType {
    Transfer = 0x01,
    ChangeKey = 0x03,
    Anchor = 0x04,
    NodeRegistration = 0x10,
    BundledConfirmation = 0x20,
    SshaReveal = 0x21,
    Proposal = 0x22,
    FastSyncRequest = 0x40,
    FastSyncResponse = 0x41,
    FastSyncError = 0x42,
    PeerListRequest = 0x50,
    PeerListResponse = 0x51,
    BatchLookupRequest = 0x60,
    BatchLookupResponse = 0x61,
    BatchLookupError = 0x62,
    RangeSubscribeRequest = 0x63,
    RangeSubscribeResponse = 0x64,
    RangeSubscribeError = 0x65,
    Ping = 0xF0,
    Pong = 0xF1,
    Bye = 0xFF,
}

impl MsgType {
    pub fn as_u8(self) -> u8 {
        self as u8
    }

    pub fn from_u8(b: u8) -> Result<MsgType, NetError> {
        match b {
            0x01 => Ok(MsgType::Transfer),
            0x03 => Ok(MsgType::ChangeKey),
            0x04 => Ok(MsgType::Anchor),
            0x10 => Ok(MsgType::NodeRegistration),
            0x20 => Ok(MsgType::BundledConfirmation),
            0x21 => Ok(MsgType::SshaReveal),
            0x22 => Ok(MsgType::Proposal),
            0x40 => Ok(MsgType::FastSyncRequest),
            0x41 => Ok(MsgType::FastSyncResponse),
            0x42 => Ok(MsgType::FastSyncError),
            0x50 => Ok(MsgType::PeerListRequest),
            0x51 => Ok(MsgType::PeerListResponse),
            0x60 => Ok(MsgType::BatchLookupRequest),
            0x61 => Ok(MsgType::BatchLookupResponse),
            0x62 => Ok(MsgType::BatchLookupError),
            0x63 => Ok(MsgType::RangeSubscribeRequest),
            0x64 => Ok(MsgType::RangeSubscribeResponse),
            0x65 => Ok(MsgType::RangeSubscribeError),
            0xF0 => Ok(MsgType::Ping),
            0xF1 => Ok(MsgType::Pong),
            0xFF => Ok(MsgType::Bye),
            other => Err(NetError::InvalidMsgType(other)),
        }
    }

    pub fn is_request(self) -> bool {
        matches!(
            self,
            MsgType::FastSyncRequest
                | MsgType::PeerListRequest
                | MsgType::BatchLookupRequest
                | MsgType::RangeSubscribeRequest
                | MsgType::Ping
        )
    }

    pub fn is_response(self) -> bool {
        matches!(
            self,
            MsgType::FastSyncResponse
                | MsgType::FastSyncError
                | MsgType::PeerListResponse
                | MsgType::BatchLookupResponse
                | MsgType::BatchLookupError
                | MsgType::RangeSubscribeResponse
                | MsgType::RangeSubscribeError
                | MsgType::Pong
        )
    }
}
