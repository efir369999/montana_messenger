use core::fmt;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NetError {
    InvalidMsgType(u8),
    UnsupportedVersion(u8),
    TruncatedHeader,
    TruncatedPayload,
    PayloadLengthMismatch,
    PayloadTooLarge,
    InvalidPayloadField,
    EntropyUnavailable,
}

impl fmt::Display for NetError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            NetError::InvalidMsgType(b) => write!(f, "invalid msg_type byte: 0x{:02X}", b),
            NetError::UnsupportedVersion(v) => write!(f, "unsupported msg_version: {}", v),
            NetError::TruncatedHeader => write!(f, "envelope header truncated (need 14 bytes)"),
            NetError::TruncatedPayload => write!(f, "envelope payload truncated"),
            NetError::PayloadLengthMismatch => write!(f, "payload size != payload_length field"),
            NetError::PayloadTooLarge => write!(f, "payload exceeds protocol max"),
            NetError::InvalidPayloadField => write!(f, "payload structural invariant violated"),
            NetError::EntropyUnavailable => write!(f, "OS CSPRNG (getrandom) unavailable"),
        }
    }
}
