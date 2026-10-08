// How a message crosses a link. The messages travel between two acquainted machines inside the
// channel their handshake established, and what an observer sees of that exchange is what it sees
// of everything else on this wire: units of `cell_bytes`, sealed, one indistinguishable from
// another and from a cell carrying a delivery.

use crate::{cell_bytes, outer_plaintext_bytes, piece_bytes, WireError, LABEL_BYTES};
use mt_codec::size;
use mt_suite::aead::{self, SealingKey};
use zeroize::Zeroizing;

mt_codec::constants! {
    LINK_FRAMING:
    /// Where a piece stands in its message.
    pub const INDEX_BYTES: usize = 2, writes "message_index                     2 B   u16   the position of this piece in its message";
    /// How many pieces stand with it.
    pub const COUNT_BYTES: usize = 2, writes "message_count                     2 B   u16   the pieces the message holds";
    /// Which message of the set they carry. It rides here rather than being guessed from the bytes:
    /// the length that would have told one message from another does not survive the padding of the
    /// last piece, and it rides inside the seal, so an observer learns nothing of it.
    pub const KIND_BYTES: usize = 1, writes "message_kind                      1 B         which message of this section the pieces carry";
}

// The framing every piece carries before the bytes of the message. It is the sum of the three
// widths above and never a number of its own, so a row of the set that moves one of them moves this
// with it.
pub const FRAMING_BYTES: usize = INDEX_BYTES + COUNT_BYTES + KIND_BYTES;

// The pieces a message is cut into: the last one padded with zeros to the one width. The kind is
// written into every piece rather than into the first alone, so a reader that lost the first has
// lost the message and never a message it reads as something else.
pub fn pieces(kind: u8, message: &[u8]) -> Result<Vec<Vec<u8>>, WireError> {
    let width = piece_bytes()?;
    let count = message.len().div_ceil(width).max(1);
    if count > usize::from(u16::MAX) {
        return Err(WireError::WrongLength {
            expected: usize::from(u16::MAX),
            found: count,
        });
    }
    let mut out = Vec::with_capacity(count);
    for index in 0..count {
        let at = index * width;
        let end = message.len().min(at + width);
        let mut piece = vec![0u8; FRAMING_BYTES + width];
        piece[..2].copy_from_slice(&(index as u16).to_le_bytes());
        piece[2..4].copy_from_slice(&(count as u16).to_le_bytes());
        piece[4] = kind;
        if at < message.len() {
            piece[FRAMING_BYTES..FRAMING_BYTES + (end - at)].copy_from_slice(&message[at..end]);
        }
        out.push(piece);
    }
    Ok(out)
}

pub fn count_of(message: &[u8]) -> Result<usize, WireError> {
    Ok(message.len().div_ceil(piece_bytes()?).max(1))
}

// The count of pieces a reader accepts for one message: the largest message of this wire cut at
// the width one piece carries. It is derived and never pinned, so a row of the Decree that widens
// a message widens this with it.
pub fn pieces_max() -> Result<usize, WireError> {
    Ok(crate::message::largest_len()?
        .div_ceil(piece_bytes()?)
        .max(1))
}

// The position a piece names, the count it declares and the kind it carries. A reader takes the
// count from the first piece it opens and reads exactly that many units: without it a reader holds
// whatever a far side keeps sending, and a message that never completes is a machine's memory spent
// by a stranger. It takes the kind from the same place, because the length that would have told one
// message of the set from another does not survive the padding of the last piece.
pub fn declared(piece: &[u8]) -> Result<(usize, usize, u8), WireError> {
    let width = piece_bytes()?;
    if piece.len() != FRAMING_BYTES + width {
        return Err(WireError::WrongLength {
            expected: FRAMING_BYTES + width,
            found: piece.len(),
        });
    }
    Ok((
        usize::from(u16::from_le_bytes([piece[0], piece[1]])),
        usize::from(u16::from_le_bytes([piece[2], piece[3]])),
        piece[4],
    ))
}

// A unit of a link, of the one length of this wire. It is sealed exactly as a cell is: the label
// of the step, a nonce drawn afresh, and the plaintext under the directional key of the handshake
// with the label as associated data.
// The nonce of a unit is drawn here and by nobody else: a caller handed the same one twice would
// seal two units under one key and one nonce, and two such units are two units an observer reads.
pub fn seal_unit(
    directional_key: &[u8; 32],
    step_label: &[u8; LABEL_BYTES],
    plaintext: &[u8],
) -> Result<Vec<u8>, WireError> {
    let nonce = crate::draw::nonce()?;
    let width = outer_plaintext_bytes()?;
    if plaintext.len() != width {
        return Err(WireError::WrongLength {
            expected: width,
            found: plaintext.len(),
        });
    }
    let key = SealingKey::new(*directional_key);
    let sealed = aead::seal(&key, &nonce, step_label, plaintext).map_err(|_| WireError::Sealing)?;
    let mut out = Vec::with_capacity(cell_bytes()?);
    out.extend_from_slice(step_label);
    out.extend_from_slice(&nonce);
    out.extend_from_slice(&sealed);
    if out.len() != cell_bytes()? {
        return Err(WireError::WrongLength {
            expected: cell_bytes()?,
            found: out.len(),
        });
    }
    Ok(out)
}

// What a unit carried is a piece of somebody's message: it comes back inside a wrapper that wipes
// itself, so a frame that held it does not leave it behind.
pub fn open_unit(directional_key: &[u8; 32], unit: &[u8]) -> Result<Zeroizing<Vec<u8>>, WireError> {
    let width = cell_bytes()?;
    if unit.len() != width {
        return Err(WireError::WrongLength {
            expected: width,
            found: unit.len(),
        });
    }
    let mut label = [0u8; LABEL_BYTES];
    label.copy_from_slice(&unit[..LABEL_BYTES]);
    let mut nonce = [0u8; size::AEAD_NONCE];
    nonce.copy_from_slice(&unit[LABEL_BYTES..LABEL_BYTES + size::AEAD_NONCE]);
    let key = SealingKey::new(*directional_key);
    aead::open(
        &key,
        &nonce,
        &label,
        &unit[LABEL_BYTES + size::AEAD_NONCE..],
    )
    .map(Zeroizing::new)
    .map_err(|_| WireError::Opening)
}

// A message is assembled from the pieces its own count names, in the order of their indices. A
// piece whose index repeats or stands outside the count is discarded in silence, and a message
// whose pieces do not all arrive is not a message.
pub fn reassemble<P: AsRef<[u8]>>(pieces: &[P]) -> Result<Option<(u8, Vec<u8>)>, WireError> {
    let width = piece_bytes()?;
    let mut count: Option<usize> = None;
    let mut kind: Option<u8> = None;
    let mut held: Vec<Option<Vec<u8>>> = Vec::new();
    for piece in pieces {
        let piece = piece.as_ref();
        if piece.len() != FRAMING_BYTES + width {
            continue;
        }
        let index = usize::from(u16::from_le_bytes([piece[0], piece[1]]));
        let declared = usize::from(u16::from_le_bytes([piece[2], piece[3]]));
        let carried = piece[4];
        if declared == 0 {
            continue;
        }
        match count {
            None => {
                count = Some(declared);
                kind = Some(carried);
                held = vec![None; declared];
            }
            Some(held_count) if held_count != declared => continue,
            Some(_) => {}
        }
        // Every piece of one message carries one kind, and a piece carrying another is a piece of
        // another message: it is discarded in silence like one standing outside the count.
        if kind != Some(carried) {
            continue;
        }
        if index >= declared || held[index].is_some() {
            continue;
        }
        held[index] = Some(piece[FRAMING_BYTES..].to_vec());
    }
    let (Some(_), Some(kind)) = (count, kind) else {
        return Ok(None);
    };
    if held.iter().any(Option::is_none) {
        return Ok(None);
    }
    let mut out = Vec::with_capacity(held.len() * width);
    for piece in held.into_iter().flatten() {
        out.extend_from_slice(&piece);
    }
    Ok(Some((kind, out)))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_message_of_any_length_cuts_into_whole_units_and_comes_back() {
        let width = piece_bytes().expect("named");
        for length in [
            0usize,
            1,
            width - 1,
            width,
            width + 1,
            3 * width,
            3 * width + 7,
        ] {
            let message: Vec<u8> = (0..length).map(|i| (i % 251) as u8).collect();
            let pieces = pieces(crate::message::Kind::Deposit.byte(), &message).expect("cuts");
            assert_eq!(pieces.len(), count_of(&message).expect("named"));
            for piece in &pieces {
                assert_eq!(piece.len(), outer_plaintext_bytes().expect("named"));
            }
            let (kind, back) = reassemble(&pieces).expect("reassembles").expect("whole");
            assert_eq!(kind, crate::message::Kind::Deposit.byte());
            assert_eq!(&back[..length], &message[..]);
            // The padding of the last piece is zero and carries no length of the message.
            assert!(back[length..].iter().all(|b| *b == 0));
        }
    }

    #[test]
    fn a_piece_declares_the_count_a_reader_reads_and_the_bound_is_derived() {
        let message = vec![9u8; 5_000];
        let kind = crate::message::Kind::HeadAnswer.byte();
        let cut = pieces(kind, &message).expect("cuts");
        let (index, count, carried) = declared(&cut[0]).expect("a piece declares");
        assert_eq!(index, 0);
        assert_eq!(count, cut.len());
        assert_eq!(carried, kind, "every piece carries the kind of its message");
        let (index, count, carried) = declared(&cut[2]).expect("a piece declares");
        assert_eq!((index, count, carried), (2, cut.len(), kind));
        // A piece of another width is not a piece.
        assert!(declared(&cut[0][..10]).is_err());
        // The bound is the largest message of this wire, and every message stands under it.
        let bound = pieces_max().expect("named");
        assert!(count <= bound);
        assert_eq!(
            bound,
            crate::message::largest_len()
                .expect("named")
                .div_ceil(piece_bytes().expect("named"))
        );
    }

    #[test]
    fn a_piece_that_repeats_or_stands_outside_the_count_is_discarded_in_silence() {
        let message = vec![7u8; 2_000];
        let kind = crate::message::Kind::CollectAnswer.byte();
        let mut pieces = pieces(kind, &message).expect("cuts");
        let good = pieces.clone();
        pieces.push(good[0].clone());
        assert_eq!(
            reassemble(&pieces).expect("reassembles"),
            reassemble(&good).expect("reassembles")
        );
        let mut missing = good.clone();
        missing.pop();
        assert_eq!(reassemble(&missing).expect("reassembles"), None);
    }

    // The named wrong implementation: a reader that took the pieces of two messages for the pieces
    // of one, because their indices and counts happen to agree. What separates them is the kind
    // every piece carries, and a piece of another kind is discarded exactly as one standing outside
    // the count is.
    #[test]
    fn a_piece_of_another_kind_is_discarded_in_silence() {
        let message = vec![3u8; 2_000];
        let mine = pieces(crate::message::Kind::Deposit.byte(), &message).expect("cuts");
        let theirs = pieces(crate::message::Kind::HeadAnswer.byte(), &message).expect("cuts");
        let mut mixed = vec![mine[0].clone(), theirs[1].clone()];
        assert_eq!(reassemble(&mixed).expect("reassembles"), None);
        mixed.push(mine[1].clone());
        let (kind, back) = reassemble(&mixed).expect("reassembles").expect("whole");
        assert_eq!(kind, crate::message::Kind::Deposit.byte());
        assert_eq!(&back[..message.len()], &message[..]);
    }

    #[test]
    fn a_unit_of_the_wrong_length_is_discarded_in_silence() {
        let key = [0x11u8; 32];
        let label = [0x22u8; LABEL_BYTES];
        let plain = vec![0u8; outer_plaintext_bytes().expect("named")];
        let unit = seal_unit(&key, &label, &plain).expect("seals");
        // Two units of one plaintext under one key differ, because the nonce of each is drawn.
        assert_ne!(seal_unit(&key, &label, &plain).expect("seals"), unit);
        assert_eq!(unit.len(), cell_bytes().expect("named"));
        assert_eq!(open_unit(&key, &unit).expect("opens")[..], plain[..]);
        assert!(matches!(
            open_unit(&key, &unit[..unit.len() - 1]),
            Err(WireError::WrongLength { .. })
        ));
        let mut doctored = unit.clone();
        doctored[LABEL_BYTES + size::AEAD_NONCE] ^= 1;
        assert!(matches!(
            open_unit(&key, &doctored),
            Err(WireError::Opening)
        ));
        // The label is associated data: a unit whose label moved does not open.
        let mut relabelled = unit;
        relabelled[0] ^= 1;
        assert!(matches!(
            open_unit(&key, &relabelled),
            Err(WireError::Opening)
        ));
    }
}
