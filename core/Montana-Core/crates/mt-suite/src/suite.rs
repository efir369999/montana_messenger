// The suite table. The set states it in `docs/Montana Canon.md`, "The suite table": one row
// today, and a future suite enters through a protocol version upgrade and an explicit row
// there. Every object of the protocol carries a `suite_id`, and this is the one place that
// number is read as a scheme.

use mt_codec::size;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Scheme {
    MlDsa65,
}

impl Scheme {
    pub fn signature_size(self) -> usize {
        match self {
            Scheme::MlDsa65 => size::SIGNATURE,
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            Scheme::MlDsa65 => "ML-DSA-65",
        }
    }
}

// The rows of the table, in the order it states them.
pub const TABLE: &[(u16, Scheme)] = &[(1, Scheme::MlDsa65)];

// A suite the table does not hold is refused rather than guessed: an object naming one is an
// object of another protocol, and a default arm choosing a scheme for it would verify under a
// number nobody agreed to.
pub fn scheme(suite_id: u16) -> Option<Scheme> {
    TABLE
        .iter()
        .find(|(id, _)| *id == suite_id)
        .map(|(_, scheme)| *scheme)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_table_names_one_scheme_and_refuses_every_other_number() {
        assert_eq!(scheme(1), Some(Scheme::MlDsa65));
        assert_eq!(scheme(0), None);
        assert_eq!(scheme(2), None);
        assert_eq!(scheme(u16::MAX), None);
    }

    #[test]
    fn the_signature_of_the_one_row_is_the_width_the_set_states() {
        assert_eq!(Scheme::MlDsa65.signature_size(), size::SIGNATURE);
        let (public, secret) = crate::sign::keypair_from_seed(&[0x11u8; crate::sign::SEED_BYTES]);
        assert_eq!(public.as_bytes().len(), size::SIGNING_PUBLIC_KEY);
        let signature = crate::sign::sign(&secret, b"a message").expect("signs");
        assert_eq!(signature.as_bytes().len(), Scheme::MlDsa65.signature_size());
    }

    #[test]
    fn every_identifier_of_the_table_is_distinct() {
        let mut ids: Vec<u16> = TABLE.iter().map(|(id, _)| *id).collect();
        let before = ids.len();
        ids.sort_unstable();
        ids.dedup();
        assert_eq!(before, ids.len());
    }
}
