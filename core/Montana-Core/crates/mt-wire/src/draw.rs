// What this wire requires to be drawn, drawn in one place. Two rules of the set stand on it and
// neither can be met by a caller who invents its own filler:
//
// **A nonce is drawn afresh for every cell and every unit.** A nonce repeated under one key
// destroys the confidentiality of both things sealed under it, and an implementation that derives
// one from a counter or from the content is defective. A crate that asked its caller for a nonce
// and offered no way to make one would be inviting exactly that.
//
// **The seal array is full at every step.** Unused slots carry values drawn like any secret, so
// the count of steps a cell has crossed is carried nowhere and readable by no one. An array left
// at a value nobody drew — zeros, most naturally — announces at every hop how far the cell has
// come, which is the one thing the array exists to hide.

use crate::{WireError, LABEL_BYTES, SEAL_BYTES};
use mt_codec::size;
use std::sync::Mutex;

// The block this crate last drew. The set applies a continuous test to the draw a person is born
// from, and the reason holds here with more force: a generator that answers the same bytes twice
// hands out the same nonce twice, and two things sealed under one key and one nonce are two things
// an observer reads. A generator that stopped looks exactly like one that did not, until this.
static LAST: Mutex<Option<Vec<u8>>> = Mutex::new(None);

// The rule itself, apart from the generator that feeds it: a block equal to the one drawn before it
// is the generator standing still, and nothing this crate seals may stand on it.
fn stands_still(drawn: &[u8], last: Option<&[u8]>) -> bool {
    last == Some(drawn)
}

fn bytes(into: &mut [u8]) -> Result<(), WireError> {
    getrandom::getrandom(into).map_err(|_| WireError::Undrawn)?;
    let mut last = LAST.lock().map_err(|_| WireError::Undrawn)?;
    if stands_still(into, last.as_deref()) {
        return Err(WireError::Undrawn);
    }
    *last = Some(into.to_vec());
    Ok(())
}

pub fn nonce() -> Result<[u8; size::AEAD_NONCE], WireError> {
    let mut out = [0u8; size::AEAD_NONCE];
    bytes(&mut out)?;
    Ok(out)
}

pub fn seal() -> Result<[u8; SEAL_BYTES], WireError> {
    let mut out = [0u8; SEAL_BYTES];
    bytes(&mut out)?;
    Ok(out)
}

// The label of a unit that travels before a channel exists: the four flights of a handshake occupy
// whole units, and the label position of such a unit carries a value drawn like any secret.
pub fn label() -> Result<[u8; LABEL_BYTES], WireError> {
    let mut out = [0u8; LABEL_BYTES];
    bytes(&mut out)?;
    Ok(out)
}

// A block of any width this tree needs drawn — the seed one handshake's encapsulation keypair is
// generated from, and whatever later asks for one. It goes through the same door as a nonce and a
// seal rather than beside it, so the continuous test that catches a generator standing still
// catches it here too: a machine drawing the same seed twice would open two handshakes an observer
// joins, which is the same defect a repeated nonce is and is caught by the same rule.
pub fn block<const N: usize>() -> Result<zeroize::Zeroizing<[u8; N]>, WireError> {
    let mut out = zeroize::Zeroizing::new([0u8; N]);
    bytes(&mut out[..])?;
    Ok(out)
}

// A filling of any width this wire needs drawn: the padding that carries a flight of a handshake
// up to the one width of a unit. It goes through the same door as a nonce and a seal for the reason
// the seal array does — a filling nobody drew is a value an observer reads off the wire, and a tail
// of zeros where every other unit carries a seal and a tag tells a handshake from everything after
// it by one comparison. What the set concedes of a flight is that an observer learns what it is
// from its own bytes; it need not learn it from the shape of the padding as well.
pub fn filling(width: usize) -> Result<Vec<u8>, WireError> {
    let mut out = vec![0u8; width];
    if width > 0 {
        bytes(&mut out)?;
    }
    Ok(out)
}

// A full array of drawn seals, one per possible step.
pub fn seals() -> Result<Vec<[u8; SEAL_BYTES]>, WireError> {
    let slots = crate::path_max()?;
    let mut out = Vec::with_capacity(slots);
    for _ in 0..slots {
        out.push(seal()?);
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn what_is_drawn_differs_between_two_draws_and_within_one_array() {
        assert_ne!(nonce().expect("drawn"), nonce().expect("drawn"));
        assert_ne!(label().expect("drawn"), label().expect("drawn"));
        let array = seals().expect("drawn");
        assert_eq!(array.len(), crate::path_max().expect("named"));
        // No slot stands at a value nobody drew, and no two of them agree: an array a hop could
        // read as "untouched" is the count of steps crossed, published.
        assert!(array.iter().all(|seal| *seal != [0u8; SEAL_BYTES]));
        let mut seen = array.clone();
        seen.sort_unstable();
        seen.dedup();
        assert_eq!(seen.len(), array.len());
    }

    #[test]
    fn a_filling_is_drawn_and_no_two_of_them_agree() {
        let first = filling(28).expect("drawn");
        let second = filling(28).expect("drawn");
        assert_eq!(first.len(), 28);
        assert_ne!(first, second);
        // The named wrong implementation: a tail of zeros, which tells a unit carrying a flight
        // from a sealed one by one comparison.
        assert_ne!(first, vec![0u8; 28]);
        assert!(filling(0).expect("drawn").is_empty());
    }

    #[test]
    fn a_generator_that_stands_still_is_refused_rather_than_trusted() {
        // The rule, put to a hand rather than to luck: a healthy generator cannot be made to repeat
        // on demand, so what a test can hold is the comparison the door makes.
        assert!(stands_still(&[1, 2, 3], Some(&[1, 2, 3])));
        assert!(!stands_still(&[1, 2, 3], Some(&[1, 2, 4])));
        assert!(!stands_still(&[1, 2, 3], None));
        // And the door records what it drew, so the next draw is compared against it.
        let mut block = [0u8; 12];
        bytes(&mut block).expect("a healthy generator answers");
        let held = LAST.lock().expect("the record is readable");
        assert_eq!(held.as_deref(), Some(&block[..]));
    }
}
