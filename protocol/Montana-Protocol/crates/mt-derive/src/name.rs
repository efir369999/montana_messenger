// The two spaces of slots: the space of names and the space of channels. The set states them in
// `docs/Montana Canon.md`, "The naming of a slot, a chain and a commitment", "The slot of a channel
// and its head" and "The contact key of a name".
//
// One written word resolves to two slots that share no byte and neither of which is computable from
// the other, because each space takes its own domain. What a space holds is a slot, never a person:
// nothing derived here joins two names of one holder.

use mt_codec::derive::hkdf_expand;
use mt_codec::{domain, hash, hash_of_one, size, Domain, Part};
use zeroize::Zeroizing;

#[derive(Debug, PartialEq, Eq)]
pub enum NameError {
    TooShort { length: usize },
    TooLong { length: usize },
    LeadingCharacter,
    Character { at: usize },
    BoundsUnknown,
}

// A name is normalized before anything is derived from it: lowercase ASCII, the letters a-z, the
// digits 0-9, the underscore and the hyphen, beginning with a letter, of a length within the bounds
// the Decree fixes. Its bytes are the normalized characters and nothing else — no padding, no
// terminator, no length prefix.
pub fn normalize(written: &str) -> Result<Zeroizing<Vec<u8>>, NameError> {
    let lowered = written.to_ascii_lowercase();
    let bytes = lowered.as_bytes();
    lawful(bytes)?;
    Ok(Zeroizing::new(bytes.to_vec()))
}

// The rule itself, in one place. A holder reaches it through `normalize`, which folds the case of
// what a person typed first; a reader of an object reaches it through `is_normalized`, over bytes
// that are already folded. Two places would be two rules the day one of them moved, and a reveal
// carrying a name one door refuses and the other admits is a name two implementations resolve to
// two slots.
fn lawful(bytes: &[u8]) -> Result<(), NameError> {
    let min = mt_genesis::scalar("name_min_length").ok_or(NameError::BoundsUnknown)? as usize;
    let max = mt_genesis::scalar("name_max_length").ok_or(NameError::BoundsUnknown)? as usize;
    if bytes.len() < min {
        return Err(NameError::TooShort {
            length: bytes.len(),
        });
    }
    if bytes.len() > max {
        return Err(NameError::TooLong {
            length: bytes.len(),
        });
    }
    if !bytes[0].is_ascii_lowercase() {
        return Err(NameError::LeadingCharacter);
    }
    for (at, byte) in bytes.iter().enumerate() {
        let admitted =
            byte.is_ascii_lowercase() || byte.is_ascii_digit() || *byte == b'_' || *byte == b'-';
        if !admitted {
            return Err(NameError::Character { at });
        }
    }
    Ok(())
}

// Whether bytes already folded are a name of this protocol. The door that reads an object off the
// wire asks this before a slot is derived from it, so a reveal carrying anything else is refused
// where it arrives rather than resolved to a slot nobody agreed to.
pub fn is_normalized(bytes: &[u8]) -> bool {
    lawful(bytes).is_ok()
}

fn slot_under(space: Domain, normalized: &[u8]) -> [u8; 32] {
    hash_of_one(space, normalized)
}

pub fn slot(normalized: &[u8]) -> [u8; 32] {
    slot_under(domain::MT_NAME_SLOT, normalized)
}

pub fn channel_slot(normalized: &[u8]) -> [u8; 32] {
    slot_under(domain::MT_CHANNEL_SLOT, normalized)
}

// The branch a chain of a name is built from, taken per slot: two names of one holder yield two
// chains that cannot be joined.
pub fn chain_branch(master_seed: &[u8], slot: &[u8; 32]) -> Zeroizing<Vec<u8>> {
    let mut info = Vec::with_capacity(domain::MT_NAME_OWN.as_str().len() + 1 + 32);
    info.extend_from_slice(domain::MT_NAME_OWN.as_str().as_bytes());
    info.push(0x00);
    info.extend_from_slice(slot);
    hkdf_expand(master_seed, &info, 32)
}

// The chain is built from its far end and spent from its near one. `link(n)` is the branch, and
// each step down is one hash; `link(0)` is the tip a commitment carries and the renewal numbered
// `r` publishes `link(r)`. Nobody computes `link(r + 1)` from `link(r)`, so only the holder
// continues the chain, and after `name_chain_length` renewals it is spent.
pub fn link_below(above: &[u8; 32]) -> [u8; 32] {
    hash(domain::MT_NAME_CHAIN, &[Part::of(above)])
}

// Every link of a chain, from its far end down to the tip: index `k` of the answer is `link(k)`.
pub fn chain(branch: &[u8; 32]) -> Option<Vec<[u8; 32]>> {
    let length = mt_genesis::scalar("name_chain_length")? as usize;
    let mut links = vec![[0u8; 32]; length + 1];
    links[length] = *branch;
    for k in (0..length).rev() {
        links[k] = link_below(&links[k + 1]);
    }
    Some(links)
}

pub fn commit(slot: &[u8; 32], blind: &[u8; 32], tip: &[u8; 32]) -> [u8; 32] {
    hash(
        domain::MT_NAME_COMMIT,
        &[Part::of(slot), Part::of(blind), Part::of(tip)],
    )
}

// The seed the key of a channel is generated from, taken per slot: two channels of one holder
// answer to two keys that join by nothing, exactly as two names of one person do.
pub fn channel_seed(master_seed: &[u8], channel_slot: &[u8; 32]) -> Zeroizing<Vec<u8>> {
    let mut info = Vec::with_capacity(domain::MT_CHANNEL_KEY.as_str().len() + 1 + 32);
    info.extend_from_slice(domain::MT_CHANNEL_KEY.as_str().as_bytes());
    info.push(0x00);
    info.extend_from_slice(channel_slot);
    hkdf_expand(master_seed, &info, 32)
}

// The head of a publication, chaining to the head published before it. The first head of a channel
// carries its slot in that position, so a reader holding the slot verifies the chain forward and
// needs no other origin.
pub fn head(previous: &[u8; 32], body_root: &[u8; 32], window: u64) -> [u8; 32] {
    hash(
        domain::MT_CHANNEL_HEAD,
        &[
            Part::of(previous),
            Part::of(body_root),
            Part::of(&window.to_le_bytes()),
        ],
    )
}

// The seed the contact key of a name is generated from, taken per slot and sixty-four bytes wide.
// A record that claimed no name derives none, and none can be derived for it by anyone.
pub fn contact_seed(master_seed: &[u8], slot: &[u8; 32]) -> Zeroizing<Vec<u8>> {
    let mut info = Vec::with_capacity(domain::MT_NAME_CONTACT_KEY.as_str().len() + 1 + 32);
    info.extend_from_slice(domain::MT_NAME_CONTACT_KEY.as_str().as_bytes());
    info.push(0x00);
    info.extend_from_slice(slot);
    hkdf_expand(master_seed, &info, 64)
}

// The secret every tag of a correspondence begun by a name stands on: the shared secret of the one
// encapsulation, the key it was made to, and the ciphertext that carried it. The contact root
// enters so two people writing to one name never land on one secret; the ciphertext enters so two
// letters from one stranger to one name do not either.
// The three parts are of the widths the set fixes, so nothing about where one ends and the next
// begins is left to a caller: a shared secret, an encapsulation key and a ciphertext of any other
// lengths are not this derivation.
pub fn first_contact_secret(
    shared: &[u8; 32],
    contact_root: &[u8; size::KEM_PUBLIC_KEY],
    ciphertext: &[u8; size::KEM_CIPHERTEXT],
) -> [u8; 32] {
    hash(
        domain::MT_NAME_FIRST,
        &[
            Part::of(shared),
            Part::of(contact_root),
            Part::of(ciphertext),
        ],
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hex(bytes: &[u8]) -> String {
        bytes.iter().map(|b| format!("{b:02x}")).collect()
    }

    fn alice() -> Zeroizing<Vec<u8>> {
        normalize("alice").expect("a lawful name")
    }

    #[test]
    fn a_name_its_chain_and_its_commitment_are_the_frozen_values() {
        // Canon, "A name: its slot, its chain and its commitment".
        let name = alice();
        let slot = slot(&name);
        assert_eq!(
            hex(&slot),
            "b5793a0d4f7f0737ebffb1374d24d3eed05efef5bd63eb1e4b03d81652c2575e"
        );
        let links = chain(&[0xEEu8; 32]).expect("the Decree names the length");
        assert_eq!(
            hex(&links[127]),
            "83be15d760052903e3b1a2d304f56861ad92b8fed97a0b08452c6eb029fe1b5a"
        );
        assert_eq!(
            hex(&links[0]),
            "b49373b194e6358022b8fbcbecb5beccdd4f0b275d1ccd53be130f76a1367a8e"
        );
        assert_eq!(
            hex(&commit(&slot, &[0xDDu8; 32], &links[0])),
            "929fccf5c511d3d1123707db473cf21732a9349bcb578ddea91ca08b2d9dae41"
        );
    }

    #[test]
    fn a_channel_its_slot_and_the_head_of_a_publication_are_the_frozen_values() {
        // Canon, "A channel: its slot, and the head of a publication".
        let name = alice();
        let slot = channel_slot(&name);
        assert_eq!(
            hex(&slot),
            "21d9d4d5dd4245cb6844bacd463f9ec4e8cf0058f5d2a4f1bd03ecad26d6610a"
        );
        assert_eq!(
            hex(&sha2::Sha256::digest(
                &channel_seed(&[0x11u8; 32], &slot)[..]
            )),
            "7225eb3ba9d07a5c3e54a25abff4a7f88a81849521b9615b0e8b438de016b17f"
        );
        assert_eq!(
            hex(&head(&[0xABu8; 32], &[0xCDu8; 32], 1000)),
            "1912f7e2e761cdada560fb0170ddeb54365a3f5548692932e83c320e101da0f2"
        );
        assert_eq!(
            hex(&head(&[0xABu8; 32], &[0xCDu8; 32], 1001)),
            "7cdd3fac87481f6bd9be451615c140bad8edbbf19df1e0ebe6dcf49597769682"
        );
    }

    #[test]
    fn one_written_word_resolves_to_two_unrelated_slots() {
        // What the two domains give is independence: neither slot is computable from the other,
        // and no rule of either space ever lands on the other's value. A count of differing bytes
        // is luck — these two agree at one position — and is asserted nowhere.
        let name = alice();
        assert_ne!(slot(&name), channel_slot(&name));
        for other in ["bobby", "carol", "dave1"] {
            let written = normalize(other).expect("lawful");
            assert_ne!(slot(&name), channel_slot(&written));
            assert_ne!(channel_slot(&name), slot(&written));
        }
    }

    #[test]
    fn a_chain_walks_one_way_only_and_is_spent_after_the_length_the_decree_fixes() {
        let length = mt_genesis::scalar("name_chain_length").expect("the Decree names it") as usize;
        let links = chain(&[0x01u8; 32]).expect("the Decree names the length");
        assert_eq!(links.len(), length + 1);
        // A renewal is verified by one hash against the value published before it.
        for k in 0..length {
            assert_eq!(link_below(&links[k + 1]), links[k]);
        }
        // And nobody computes the link above from the link below: every link is distinct.
        let mut seen = links.clone();
        seen.sort_unstable();
        seen.dedup();
        assert_eq!(seen.len(), links.len());
    }

    #[test]
    fn two_names_of_one_holder_yield_two_chains_that_cannot_be_joined() {
        let seed = [0x11u8; 32];
        let one = slot(&normalize("alice").expect("lawful"));
        let two = slot(&normalize("bobby").expect("lawful"));
        let a = chain_branch(&seed, &one);
        let b = chain_branch(&seed, &two);
        assert_ne!(a[..], b[..]);
        // And neither is the branch of the other space for the same word.
        let channel = channel_seed(&seed, &channel_slot(&normalize("alice").expect("lawful")));
        assert_ne!(a[..], channel[..]);
    }

    #[test]
    fn the_contact_seed_is_sixty_four_bytes_and_stands_apart_from_every_other_branch() {
        let seed = [0x11u8; 32];
        let slot = slot(&alice());
        let contact = contact_seed(&seed, &slot);
        assert_eq!(contact.len(), 64);
        assert_ne!(contact[..32], chain_branch(&seed, &slot)[..]);
    }

    #[test]
    fn a_name_outside_the_alphabet_the_bounds_or_the_leading_rule_is_refused() {
        assert_eq!(normalize("abc"), Err(NameError::TooShort { length: 3 }));
        assert_eq!(
            normalize(&"a".repeat(33)),
            Err(NameError::TooLong { length: 33 })
        );
        assert_eq!(normalize("1abcd"), Err(NameError::LeadingCharacter));
        assert_eq!(normalize("_abcd"), Err(NameError::LeadingCharacter));
        assert_eq!(normalize("abcd!"), Err(NameError::Character { at: 4 }));
        assert_eq!(normalize("ab cd"), Err(NameError::Character { at: 2 }));
        // Case carries nothing, and the lawful alphabet passes.
        assert_eq!(
            normalize("Alice_1-x").expect("lawful")[..],
            b"alice_1-x"[..]
        );
    }

    #[test]
    fn a_refused_name_yields_no_slot_because_none_is_derived_from_it() {
        // The refusal stands before a slot exists: two implementations therefore never resolve one
        // written name to two slots.
        assert!(normalize("ab").is_err());
        assert!(normalize("Ab-").is_err());
    }

    #[test]
    fn the_three_branches_from_a_stated_master_seed_are_the_frozen_values() {
        // Canon, "The branches of the two spaces, from a stated master seed": sixty-four
        // distinct bytes, no permutation of which is itself.
        let mut seed = [0u8; 64];
        for (i, b) in seed.iter_mut().enumerate() {
            *b = i as u8;
        }
        let name = alice();
        let slot = slot(&name);
        assert_eq!(
            hex(&sha2::Sha256::digest(&chain_branch(&seed, &slot)[..])),
            "bb8f878477dc5405cdf74c9079a0c2ba2c1dd55f0eda2de1598e5f120bdc4f5a"
        );
        assert_eq!(
            hex(&sha2::Sha256::digest(&contact_seed(&seed, &slot)[..])),
            "e76fe9dde36740c309209ea51a81f42d43a5b82160963af7c47fe4f5c34526be"
        );
        assert_eq!(
            hex(&sha2::Sha256::digest(
                &channel_seed(&seed, &channel_slot(&name))[..]
            )),
            "b97abd0f496b1b57f3fc76108256f16da8b8be11722610f549c26b3b104c2b0f"
        );
        // The named wrong implementations: the NUL omitted, the slot before the domain, the
        // seed read backwards. Each reproduces none of the three.
        let mut no_nul = Vec::new();
        no_nul.extend_from_slice(mt_codec::domain::MT_NAME_OWN.as_str().as_bytes());
        no_nul.extend_from_slice(&slot);
        let mut swapped = slot.to_vec();
        swapped.push(0x00);
        swapped.extend_from_slice(mt_codec::domain::MT_NAME_OWN.as_str().as_bytes());
        let mut reversed = seed;
        reversed.reverse();
        let straight = chain_branch(&seed, &slot);
        for wrong in [
            mt_codec::derive::hkdf_expand(&seed, &no_nul, 32),
            mt_codec::derive::hkdf_expand(&seed, &swapped, 32),
            chain_branch(&reversed, &slot),
        ] {
            assert_ne!(wrong[..], straight[..]);
        }
    }

    #[test]
    fn the_secret_of_first_contact_is_the_frozen_value_and_its_order_is_the_only_one() {
        // Canon, "The tag of first contact to a claimed name": ss, the key, the ciphertext.
        let ss = [0x05u8; 32];
        let root = [0xCCu8; size::KEM_PUBLIC_KEY];
        let ct = [0x03u8; size::KEM_CIPHERTEXT];
        assert_eq!(
            hex(&first_contact_secret(&ss, &root, &ct)),
            "437a425f0c5afe9af675a0767680f6e48be71b22e95fa14aac52cfa2d184a556"
        );
        // The named wrong implementation: the ciphertext written before the key. The widths keep
        // a caller from writing it at all, so what stands here is the hash it would produce.
        assert_ne!(
            mt_codec::hash(
                domain::MT_NAME_FIRST,
                &[Part::of(&ss), Part::of(&ct), Part::of(&root)]
            ),
            first_contact_secret(&ss, &root, &ct)
        );
    }

    use sha2::Digest;
}

#[cfg(test)]
mod lawful_tests {
    use super::*;

    #[test]
    fn the_two_doors_of_one_rule_answer_alike() {
        for written in ["alice", "bobby", "a-b_c9", "abcd"] {
            let held = normalize(written).expect("lawful");
            assert!(is_normalized(&held));
        }
        for written in [
            "abc",
            "1abcd",
            "_abcd",
            "abcd!",
            "ab cd",
            "",
            &"a".repeat(33),
        ] {
            assert!(normalize(written).is_err(), "{written:?}");
            assert!(!is_normalized(written.as_bytes()), "{written:?}");
        }
        // What the second door adds: bytes that were never typed. A name with a capital is not
        // normalized, though the first door would fold it.
        assert!(!is_normalized(b"Alice"));
        assert!(normalize("Alice").is_ok());
    }
}
