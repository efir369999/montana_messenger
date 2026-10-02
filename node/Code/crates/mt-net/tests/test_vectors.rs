use mt_net::{
    decode_envelope, encode_envelope, MsgType, NetError, ProtocolMessage, ENVELOPE_HEADER_SIZE,
    MSG_VERSION_V1,
};

#[test]
fn vector_a1_envelope_ping_empty_payload() {
    let m = ProtocolMessage::new(MsgType::Ping, 0, vec![]);
    let mut got = Vec::new();
    encode_envelope(&m, &mut got).unwrap();
    let expected: Vec<u8> = vec![
        0xF0, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    ];
    assert_eq!(got, expected, "Vector A1 byte-exact mismatch");
    let decoded = decode_envelope(&expected).unwrap();
    assert_eq!(decoded, m);
}

#[test]
fn vector_a2_envelope_typical_transfer_1024b() {
    let payload: Vec<u8> = vec![0xAB; 1024];
    let m = ProtocolMessage::new(MsgType::Transfer, 42, payload.clone());
    let mut got = Vec::new();
    encode_envelope(&m, &mut got).unwrap();
    assert_eq!(got.len(), ENVELOPE_HEADER_SIZE + 1024);
    assert_eq!(got[0], 0x01);
    assert_eq!(got[1], MSG_VERSION_V1);
    assert_eq!(&got[2..10], &42u64.to_le_bytes());
    assert_eq!(&got[10..14], &1024u32.to_le_bytes());
    assert_eq!(&got[14..14 + 1024], &payload[..]);
    let decoded = decode_envelope(&got).unwrap();
    assert_eq!(decoded, m);
}

#[test]
fn vector_a3_envelope_header_only_max_request_id() {
    let m = ProtocolMessage::new(MsgType::FastSyncResponse, u64::MAX, vec![]);
    let mut got = Vec::new();
    encode_envelope(&m, &mut got).unwrap();
    assert_eq!(got.len(), ENVELOPE_HEADER_SIZE);
    assert_eq!(got[0], 0x41);
    assert_eq!(&got[2..10], &u64::MAX.to_le_bytes());
    assert_eq!(&got[10..14], &0u32.to_le_bytes());
    let decoded = decode_envelope(&got).unwrap();
    assert_eq!(decoded, m);
}

#[test]
fn all_18_msg_type_codes_round_trip() {
    let codes: &[(u8, MsgType)] = &[
        (0x01, MsgType::Transfer),
        (0x03, MsgType::ChangeKey),
        (0x04, MsgType::Anchor),
        (0x10, MsgType::NodeRegistration),
        (0x20, MsgType::BundledConfirmation),
        (0x21, MsgType::SshaReveal),
        (0x22, MsgType::Proposal),
        (0x40, MsgType::FastSyncRequest),
        (0x41, MsgType::FastSyncResponse),
        (0x42, MsgType::FastSyncError),
        (0x50, MsgType::PeerListRequest),
        (0x51, MsgType::PeerListResponse),
        (0x60, MsgType::BatchLookupRequest),
        (0x61, MsgType::BatchLookupResponse),
        (0x62, MsgType::BatchLookupError),
        (0x63, MsgType::RangeSubscribeRequest),
        (0x64, MsgType::RangeSubscribeResponse),
        (0x65, MsgType::RangeSubscribeError),
        (0xF0, MsgType::Ping),
        (0xF1, MsgType::Pong),
        (0xFF, MsgType::Bye),
    ];
    for &(byte, mt) in codes {
        assert_eq!(mt.as_u8(), byte, "as_u8 mismatch for {:?}", mt);
        assert_eq!(MsgType::from_u8(byte).unwrap(), mt);
        let m = ProtocolMessage::new(mt, byte as u64, vec![byte]);
        let mut buf = Vec::new();
        encode_envelope(&m, &mut buf).unwrap();
        let decoded = decode_envelope(&buf).unwrap();
        assert_eq!(decoded, m);
    }
}

#[test]
fn reserved_bytes_rejected() {
    for byte in [0x00u8, 0x02, 0x05, 0x06, 0x11, 0x23, 0x66, 0x99, 0xEE] {
        assert_eq!(MsgType::from_u8(byte), Err(NetError::InvalidMsgType(byte)));
    }
}

// Phase A.2 — payload KAT vectors (per spec section "Per-msg-type")

#[test]
fn vector_c_0x40_fastsync_request() {
    use mt_net::FastSyncRequest;
    let r = FastSyncRequest {
        anchor_window: 12345,
        resume_offset: 0,
    };
    let mut buf = Vec::new();
    r.encode(&mut buf);
    assert_eq!(buf.len(), 16);
    assert_eq!(&buf[0..8], &12345u64.to_le_bytes());
    assert_eq!(&buf[8..16], &0u64.to_le_bytes());
    assert_eq!(FastSyncRequest::decode(&buf).unwrap(), r);
}

#[test]
fn vector_c_0x42_fastsync_error() {
    use mt_net::FastSyncError;
    let e = FastSyncError {
        code: 0x01,
        message: b"anchor_window 12345 not retained".to_vec(),
    };
    let mut buf = Vec::new();
    e.encode(&mut buf);
    assert_eq!(buf[0], 0x01);
    assert_eq!(buf[1] as usize, e.message.len());
    assert_eq!(FastSyncError::decode(&buf).unwrap(), e);
}

#[test]
fn vector_c_0x50_peer_list_request() {
    use mt_net::PeerListRequest;
    let r = PeerListRequest { max_count: 64 };
    let mut buf = Vec::new();
    r.encode(&mut buf);
    assert_eq!(buf, vec![0x40, 0x00]);
    assert_eq!(PeerListRequest::decode(&buf).unwrap(), r);
}

#[test]
fn vector_c_0x51_peer_list_response_3_entries() {
    use mt_net::{IpAddrV, PeerEntry, PeerListResponse};
    let mut ip4_a = [0u8; 16];
    ip4_a[12..].copy_from_slice(&[10, 0, 0, 1]);
    let mut ip6 = [0u8; 16];
    ip6[0] = 0xfe;
    ip6[1] = 0x80;
    ip6[15] = 1;
    let mut ip4_b = [0u8; 16];
    ip4_b[12..].copy_from_slice(&[10, 0, 0, 2]);
    let resp = PeerListResponse {
        peers: vec![
            PeerEntry {
                ip_version: IpAddrV::V4,
                ip: ip4_a,
                port: 4242,
                node_id: [0xAA; 32],
                start_window: 100,
            },
            PeerEntry {
                ip_version: IpAddrV::V6,
                ip: ip6,
                port: 4242,
                node_id: [0xBB; 32],
                start_window: 200,
            },
            PeerEntry {
                ip_version: IpAddrV::V4,
                ip: ip4_b,
                port: 4243,
                node_id: [0xCC; 32],
                start_window: 300,
            },
        ],
    };
    let mut buf = Vec::new();
    resp.encode(&mut buf);
    let expected_len = 2 + 3 * 59;
    assert_eq!(buf.len(), expected_len);
    assert_eq!(&buf[0..2], &3u16.to_le_bytes());
    assert_eq!(PeerListResponse::decode(&buf).unwrap(), resp);
}

#[test]
fn vector_c_0x62_batch_lookup_error() {
    use mt_net::BatchLookupError;
    let e = BatchLookupError {
        query_type: 0x01,
        error_code: 0x01,
    };
    let mut buf = Vec::new();
    e.encode(&mut buf);
    assert_eq!(buf, vec![0x01, 0x01]);
    assert_eq!(BatchLookupError::decode(&buf).unwrap(), e);
}

#[test]
fn vector_c_0x63_range_subscribe_request_4_labels() {
    use mt_net::RangeSubscribeRequest;
    let r = RangeSubscribeRequest {
        labels: vec![[0xE0; 32], [0xE1; 32], [0xE2; 32], [0xE3; 32]],
    };
    let mut buf = Vec::new();
    r.encode(&mut buf);
    assert_eq!(buf.len(), 2 + 4 * 32);
    assert_eq!(&buf[0..2], &4u16.to_le_bytes());
    assert_eq!(RangeSubscribeRequest::decode(&buf).unwrap(), r);
}

#[test]
fn vector_c_0x65_range_subscribe_error() {
    use mt_net::RangeSubscribeError;
    let e = RangeSubscribeError { error_code: 0x02 };
    let mut buf = Vec::new();
    e.encode(&mut buf);
    assert_eq!(buf, vec![0x02]);
    assert_eq!(RangeSubscribeError::decode(&buf).unwrap(), e);
}

#[test]
fn vector_c_0xff_bye_normal_shutdown() {
    use mt_net::Bye;
    let bye = Bye { reason: 0x00 };
    let mut buf = Vec::new();
    bye.encode(&mut buf);
    assert_eq!(buf, vec![0x00]);
    assert_eq!(Bye::decode(&buf).unwrap(), bye);
}

#[test]
fn vector_c_0x41_fastsync_response_chunk() {
    use mt_net::{FastSyncResponseChunk, TableId};
    let chunk = FastSyncResponseChunk {
        chunk_index: 0,
        total_chunks: 1,
        table_id: TableId::Account,
        record_count: 1,
        anchor_window: 0,
        records: vec![0x55; 64],
    };
    let mut buf = Vec::new();
    chunk.encode(&mut buf);
    assert_eq!(&buf[0..4], &0u32.to_le_bytes());
    assert_eq!(&buf[4..8], &1u32.to_le_bytes());
    assert_eq!(buf[8], 0x01);
    assert_eq!(&buf[9..13], &1u32.to_le_bytes());
    assert_eq!(&buf[13..21], &0u64.to_le_bytes());
    assert_eq!(&buf[21..], &vec![0x55; 64][..]);
    assert_eq!(FastSyncResponseChunk::decode(&buf).unwrap(), chunk);
}
