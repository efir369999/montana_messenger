// What a device spends on links it did not choose. Two rules, one number of the Decree, and no
// constant of their own: the budget of a window belongs to whoever runs the device, and what the
// set fixes is that the budget is divided equally and that a full device answers nothing.
//
// The entries a device chose for itself stand outside the ceiling and are never released by the
// rule of idleness: they are its lifeline, standing at points derived from its own secret, and a
// stranger able to displace them would undo the ring of entries.

use crate::WireError;

// Whether a device holding `inbound` links it did not open answers one more. At the ceiling the
// answer is no, and the refusal a caller makes of it is silence: an answer saying "full" tells a
// stranger it found a device.
pub fn answers(inbound: u64) -> Result<bool, WireError> {
    let slots = mt_genesis::scalar("inbound_slots").ok_or(WireError::DecreeIncomplete)?;
    Ok(inbound < slots)
}

// The share of a window's budget one link is given. The division is equal across every link the
// device holds — the entries it chose among them — because a device feeding one link out of
// another's share is a device an adversary starves its neighbours through.
pub fn share(budget: u64) -> Result<u64, WireError> {
    let slots = mt_genesis::scalar("inbound_slots").ok_or(WireError::DecreeIncomplete)?;
    let entries = mt_genesis::scalar("outbound_connections").ok_or(WireError::DecreeIncomplete)?;
    let links = slots
        .checked_add(entries)
        .ok_or(WireError::DecreeIncomplete)?;
    if links == 0 {
        return Err(WireError::DecreeIncomplete);
    }
    Ok(budget / links)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_ceiling_and_the_share_are_the_frozen_answers() {
        // Canon, "What a device answers a stranger with".
        assert!(answers(0).unwrap());
        assert!(answers(95).unwrap());
        assert!(!answers(96).unwrap());
        assert_eq!(share(120).unwrap(), 1);
        assert_eq!(share(119).unwrap(), 0);
    }

    #[test]
    fn the_ceiling_holds_above_itself_and_the_share_divides_toward_zero() {
        // A count already past the ceiling answers nothing rather than wrapping into a yes.
        assert!(!answers(u64::MAX).unwrap());
        // The division truncates: a budget of two links and a half gives two, never three.
        assert_eq!(share(300).unwrap(), 2);
        assert_eq!(share(0).unwrap(), 0);
    }
}
