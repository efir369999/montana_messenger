//! Stage 9 — Content codec (plaintext of the 1-on-1 personal chat ratchet).
//! Binary, LE. Header 25 B (content_type 1 ‖ msg_id 16 ‖ sent_at 8 LE) ‖ body by type.
//! Parsing is invalid-safe: any violation → Reject/Ignore, NEVER panics (spec "Content Invariants").

pub const CONTENT_HEADER: usize = 25;
pub const MAX_PLAINTEXT: usize = 1_048_576;
pub const MAX_TEXT_LEN: usize = MAX_PLAINTEXT - 32 - 45;

pub const TYPE_TEXT: u8 = 0x01;
pub const TYPE_DELIVERY: u8 = 0x02;
pub const TYPE_READ: u8 = 0x03;
pub const TYPE_TYPING: u8 = 0x04;
pub const TYPE_MEDIA: u8 = 0x05;

#[derive(Debug, PartialEq, Eq)]
pub enum Content {
    Text {
        msg_id: [u8; 16],
        sent_at: u64,
        reply_to: [u8; 16],
        text: String,
    },
    DeliveryReceipt {
        msg_id: [u8; 16],
        sent_at: u64,
        target: [u8; 16],
    },
    ReadReceipt {
        msg_id: [u8; 16],
        sent_at: u64,
        target: [u8; 16],
    },
    Typing {
        msg_id: [u8; 16],
        sent_at: u64,
        start: bool,
    },
    /// Known type whose body is parsed by Stage 12 (media) — kept raw here.
    Media {
        msg_id: [u8; 16],
        sent_at: u64,
        body: Vec<u8>,
    },
}

#[derive(Debug, PartialEq, Eq)]
pub enum ParseOutcome {
    Ok(Content),
    /// Unknown content_type — forward-compat: ignore, not an error (spec invariant 2).
    Ignore,
    /// Length/format/UTF-8 violation — message is rejected, state is unchanged.
    Reject,
}

fn hdr(buf: &[u8]) -> ([u8; 16], u64) {
    let mut mid = [0u8; 16];
    mid.copy_from_slice(&buf[1..17]);
    let sent_at = u64::from_le_bytes(buf[17..25].try_into().unwrap());
    (mid, sent_at)
}

/// Parse Content. Never panics; returns Ok/Ignore/Reject.
pub fn parse(buf: &[u8]) -> ParseOutcome {
    if buf.len() < CONTENT_HEADER {
        return ParseOutcome::Reject; // invariant 1
    }
    let ct = buf[0];
    let (msg_id, sent_at) = hdr(buf);
    let body = &buf[CONTENT_HEADER..];
    match ct {
        TYPE_TEXT => {
            if body.len() < 20 {
                return ParseOutcome::Reject; // reply_to 16 + text_len 4
            }
            let mut reply_to = [0u8; 16];
            reply_to.copy_from_slice(&body[..16]);
            let text_len = u32::from_le_bytes(body[16..20].try_into().unwrap()) as usize;
            let text_bytes = &body[20..];
            if text_len != text_bytes.len() || text_len > MAX_TEXT_LEN {
                return ParseOutcome::Reject;
            }
            match core::str::from_utf8(text_bytes) {
                Ok(s) => ParseOutcome::Ok(Content::Text {
                    msg_id,
                    sent_at,
                    reply_to,
                    text: s.to_owned(),
                }),
                Err(_) => ParseOutcome::Reject,
            }
        },
        TYPE_DELIVERY | TYPE_READ => {
            if body.len() != 16 {
                return ParseOutcome::Reject;
            }
            let mut target = [0u8; 16];
            target.copy_from_slice(body);
            ParseOutcome::Ok(if ct == TYPE_DELIVERY {
                Content::DeliveryReceipt {
                    msg_id,
                    sent_at,
                    target,
                }
            } else {
                Content::ReadReceipt {
                    msg_id,
                    sent_at,
                    target,
                }
            })
        },
        TYPE_TYPING => {
            if body.len() != 1 || body[0] > 1 {
                return ParseOutcome::Reject;
            }
            ParseOutcome::Ok(Content::Typing {
                msg_id,
                sent_at,
                start: body[0] == 1,
            })
        },
        TYPE_MEDIA => ParseOutcome::Ok(Content::Media {
            msg_id,
            sent_at,
            body: body.to_vec(),
        }),
        _ => ParseOutcome::Ignore, // invariant 2
    }
}

fn header_bytes(out: &mut Vec<u8>, ct: u8, msg_id: &[u8; 16], sent_at: u64) {
    out.push(ct);
    out.extend_from_slice(msg_id);
    out.extend_from_slice(&sent_at.to_le_bytes());
}

pub fn encode_text(msg_id: &[u8; 16], sent_at: u64, reply_to: &[u8; 16], text: &[u8]) -> Vec<u8> {
    let mut o = Vec::with_capacity(CONTENT_HEADER + 20 + text.len());
    header_bytes(&mut o, TYPE_TEXT, msg_id, sent_at);
    o.extend_from_slice(reply_to);
    o.extend_from_slice(&(text.len() as u32).to_le_bytes());
    o.extend_from_slice(text);
    o
}

pub fn encode_receipt(ct: u8, msg_id: &[u8; 16], sent_at: u64, target: &[u8; 16]) -> Vec<u8> {
    let mut o = Vec::with_capacity(CONTENT_HEADER + 16);
    header_bytes(&mut o, ct, msg_id, sent_at);
    o.extend_from_slice(target);
    o
}

pub fn encode_typing(msg_id: &[u8; 16], sent_at: u64, start: bool) -> Vec<u8> {
    let mut o = Vec::with_capacity(CONTENT_HEADER + 1);
    header_bytes(&mut o, TYPE_TYPING, msg_id, sent_at);
    o.push(if start { 1 } else { 0 });
    o
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn content_codec_spec_kat() {
        assert_eq!(
            hex::encode(encode_text(&[0x11; 16], 1000, &[0u8; 16], b"hi")),
            "0111111111111111111111111111111111e80300000000000000000000000000000000000000000000020000006869"
        );
        assert_eq!(
            hex::encode(encode_receipt(
                TYPE_DELIVERY,
                &[0x22; 16],
                2000,
                &[0x11; 16]
            )),
            "0222222222222222222222222222222222d00700000000000011111111111111111111111111111111"
        );
        assert_eq!(
            hex::encode(encode_typing(&[0x33; 16], 3000, true)),
            "0433333333333333333333333333333333b80b00000000000001"
        );
    }

    #[test]
    fn roundtrip_and_invariants() {
        // text roundtrip
        let e = encode_text(&[0x11; 16], 1000, &[0u8; 16], b"hi");
        assert_eq!(
            parse(&e),
            ParseOutcome::Ok(Content::Text {
                msg_id: [0x11; 16],
                sent_at: 1000,
                reply_to: [0u8; 16],
                text: "hi".to_owned()
            })
        );
        // shorter than header → Reject
        assert_eq!(parse(&[0u8; 10]), ParseOutcome::Reject);
        // unknown type → Ignore (forward-compat)
        let mut unknown = vec![0x7f];
        unknown.extend_from_slice(&[0u8; 24]);
        assert_eq!(parse(&unknown), ParseOutcome::Ignore);
        // typing with invalid state → Reject
        assert_eq!(
            parse(&encode_typing(&[0x33; 16], 3000, true)[..],),
            ParseOutcome::Ok(Content::Typing {
                msg_id: [0x33; 16],
                sent_at: 3000,
                start: true
            })
        );
        let mut bad_typing = encode_typing(&[0x33; 16], 3000, true);
        *bad_typing.last_mut().unwrap() = 0x05;
        assert_eq!(parse(&bad_typing), ParseOutcome::Reject);
        // receipt of wrong length → Reject
        let mut bad_rcpt = encode_receipt(TYPE_READ, &[0x22; 16], 2000, &[0x11; 16]);
        bad_rcpt.push(0x00);
        assert_eq!(parse(&bad_rcpt), ParseOutcome::Reject);
        // text_len does not match the remainder → Reject
        let mut bad_text = encode_text(&[0x11; 16], 1000, &[0u8; 16], b"hi");
        bad_text.pop(); // remove 1 byte of text
        assert_eq!(parse(&bad_text), ParseOutcome::Reject);
        // invalid UTF-8 → Reject
        let bad_utf8 = encode_text(&[0x11; 16], 1000, &[0u8; 16], &[0xff, 0xfe]);
        assert_eq!(parse(&bad_utf8), ParseOutcome::Reject);
    }
}
