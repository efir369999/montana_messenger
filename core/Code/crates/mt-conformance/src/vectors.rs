// Binding test vectors from Montana spec — single source of truth for
// cross-implementation conformance.

#[derive(Debug, Clone)]
pub struct VectorEnvelope {
    pub name: &'static str,
    pub msg_type: u8,
    pub msg_version: u8,
    pub request_id: u64,
    pub payload: Vec<u8>,
    pub expected_bytes: Vec<u8>,
}

pub fn envelope_a1_ping_empty() -> VectorEnvelope {
    VectorEnvelope {
        name: "A1: Ping empty payload",
        msg_type: 0xF0,
        msg_version: 0x01,
        request_id: 0,
        payload: vec![],
        expected_bytes: vec![
            0xF0, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        ],
    }
}

pub fn envelope_a2_transfer_1024() -> VectorEnvelope {
    let mut expected = vec![
        0x01, 0x01, 0x2a, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00,
    ];
    expected.extend_from_slice(&vec![0xAB; 1024]);
    VectorEnvelope {
        name: "A2: Transfer 1024B payload, request_id=42",
        msg_type: 0x01,
        msg_version: 0x01,
        request_id: 42,
        payload: vec![0xAB; 1024],
        expected_bytes: expected,
    }
}

pub fn envelope_a3_fastsync_max_request_id() -> VectorEnvelope {
    VectorEnvelope {
        name: "A3: FastSyncResponse header-only, request_id=u64::MAX",
        msg_type: 0x41,
        msg_version: 0x01,
        request_id: u64::MAX,
        payload: vec![],
        expected_bytes: vec![
            0x41, 0x01, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00,
        ],
    }
}

pub fn all_envelope_vectors() -> Vec<VectorEnvelope> {
    vec![
        envelope_a1_ping_empty(),
        envelope_a2_transfer_1024(),
        envelope_a3_fastsync_max_request_id(),
    ]
}

#[derive(Debug, Clone)]
pub struct VectorIbtSeed {
    pub name: &'static str,
    pub seed_label: &'static [u8],
    pub seed: [u8; 32],
    pub pk_sha256: [u8; 32],
    pub proof_sha256: [u8; 32],
}

pub fn ibt_b1_online_proof() -> VectorIbtSeed {
    VectorIbtSeed {
        name: "B1: IBT online proof, server [0x42;32], window=1000",
        seed_label: b"vector-B1",
        seed: [
            0xf6, 0x40, 0x57, 0x69, 0xec, 0xbf, 0x3d, 0x1f, 0x5b, 0x65, 0x93, 0xc9, 0x71, 0xf1,
            0x41, 0x09, 0xef, 0x9d, 0x57, 0x62, 0x8b, 0xfc, 0x46, 0xb8, 0xf4, 0xd5, 0xc0, 0xb6,
            0x6d, 0x0f, 0xf1, 0xb9,
        ],
        pk_sha256: [
            0xee, 0x74, 0x16, 0x1e, 0xee, 0xdc, 0xf4, 0x61, 0x89, 0x73, 0x96, 0xbb, 0xe6, 0x55,
            0xbc, 0x9c, 0x35, 0x39, 0xf6, 0x15, 0xa3, 0xed, 0xce, 0xf9, 0xf8, 0x7a, 0x9e, 0x58,
            0x82, 0xb3, 0x00, 0xc2,
        ],
        proof_sha256: [
            0xac, 0x26, 0xa9, 0xca, 0x84, 0xa9, 0xae, 0xba, 0x3a, 0xaf, 0x2f, 0x3f, 0xc9, 0xba,
            0x2f, 0x0b, 0xe9, 0x0c, 0x6d, 0x98, 0xf6, 0x55, 0xad, 0xdb, 0x0f, 0x87, 0x5b, 0xca,
            0xad, 0xff, 0xef, 0xda,
        ],
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use mt_net::{decode_envelope, encode_envelope, MsgType, ProtocolMessage};

    #[test]
    fn envelope_vectors_byte_exact() {
        for v in all_envelope_vectors() {
            let m = ProtocolMessage::new(
                MsgType::from_u8(v.msg_type).unwrap(),
                v.request_id,
                v.payload.clone(),
            );
            let mut buf = Vec::new();
            encode_envelope(&m, &mut buf).unwrap();
            assert_eq!(buf, v.expected_bytes, "{} byte-exact mismatch", v.name);
            let dec = decode_envelope(&buf).unwrap();
            assert_eq!(dec.payload, v.payload, "{} payload roundtrip", v.name);
        }
    }
}
