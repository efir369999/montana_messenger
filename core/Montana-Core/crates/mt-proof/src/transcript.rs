// The transcript, from which every challenge of a proof is drawn. What it exists for is that a
// prover cannot aim at a query it has not yet committed to: every challenge stands after the
// commitment it must not depend on, and the running value carries everything before it.
//
// The drawing of a challenge is one rule for every challenge of a proof: the transcript is hashed
// with a counter, the digest reads as four unsigned eight-byte little-endian words, a word at or
// above the modulus is passed over, and what is taken is the words that stand below it in order.

use crate::ext::E;
use crate::field::F;
use mt_codec::domain;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Transcript {
    running: [u8; 32],
}

impl Transcript {
    // The opening value: the artifact the proof is accepted under and the object it proves, so a
    // proof is bound to both and to nothing else.
    pub fn opening(air_hash: &[u8; 32], public_inputs: &[u8]) -> Transcript {
        let mut preimage = Vec::with_capacity(32 + public_inputs.len());
        preimage.extend_from_slice(air_hash);
        preimage.extend_from_slice(public_inputs);
        Transcript {
            running: crate::poseidon::hash_bytes(domain::MT_PROOF_TRANSCRIPT, &preimage).bytes(),
        }
    }

    // Everything a prover commits to enters here, and every challenge after it stands on it.
    pub fn absorb(&mut self, bytes: &[u8]) {
        let mut preimage = Vec::with_capacity(32 + bytes.len());
        preimage.extend_from_slice(&self.running);
        preimage.extend_from_slice(bytes);
        self.running = crate::poseidon::hash_bytes(domain::MT_PROOF_TRANSCRIPT, &preimage).bytes();
    }

    pub fn value(&self) -> [u8; 32] {
        self.running
    }

    // The words a digest of the transcript yields, in order, passing over any that stands at or
    // above the modulus: a word taken modulo the prime would make some elements likelier than
    // others, and a challenge that is not uniform is a challenge an adversary aims at.
    fn words(&self, counter: u64) -> Vec<F> {
        let mut preimage = Vec::with_capacity(40);
        preimage.extend_from_slice(&self.running);
        preimage.extend_from_slice(&counter.to_le_bytes());
        let digest = crate::poseidon::hash_bytes(domain::MT_PROOF_TRANSCRIPT, &preimage).bytes();
        let mut out = Vec::with_capacity(4);
        for at in 0..4 {
            let mut eight = [0u8; 8];
            eight.copy_from_slice(&digest[at * 8..at * 8 + 8]);
            if let Some(value) = F::try_from_u64(u64::from_le_bytes(eight)) {
                out.push(value);
            }
        }
        out
    }

    // A challenge of the field the elements of a proof are drawn in: the next three words that
    // stand below the modulus, least significant coefficient first.
    pub fn challenge(&self, counter: &mut u64) -> E {
        let mut taken = Vec::with_capacity(3);
        while taken.len() < 3 {
            for word in self.words(*counter) {
                taken.push(word);
                if taken.len() == 3 {
                    break;
                }
            }
            *counter += 1;
        }
        E::of(taken[0], taken[1], taken[2])
    }

    pub fn challenges(&self, counter: &mut u64, count: usize) -> Vec<E> {
        (0..count).map(|_| self.challenge(counter)).collect()
    }

    // A position rather than an element: one word, taken modulo the size of the domain, and a
    // repeat redrawn — the set states both, and a proof whose queries repeat opens fewer places
    // than its count claims.
    pub fn positions(
        &self,
        seed_domain_counter: &mut u64,
        count: usize,
        domain: usize,
    ) -> Vec<usize> {
        let mut out: Vec<usize> = Vec::with_capacity(count);
        while out.len() < count {
            for word in self.words(*seed_domain_counter) {
                let position = (word.as_u64() % domain as u64) as usize;
                if !out.contains(&position) {
                    out.push(position);
                }
                if out.len() == count {
                    break;
                }
            }
            *seed_domain_counter += 1;
        }
        out
    }
}

// The seed the positions of a proof are drawn from: its own domain, so a position and an element
// never come out of one preimage.
pub fn query_seed(transcript: &Transcript) -> Transcript {
    Transcript {
        running: crate::poseidon::hash_bytes(domain::MT_PROOF_QUERY, &transcript.value()).bytes(),
    }
}

// A value the transcript absorbs where the set names a list of elements: the bytes of every one of
// them, in order, each in the form an element stands in on the wire.
pub fn bytes_of(elements: &[E]) -> Vec<u8> {
    let mut out = Vec::with_capacity(elements.len() * crate::ext::ELEMENT_BYTES);
    for element in elements {
        out.extend_from_slice(&element.to_bytes());
    }
    out
}

// What a digest is worth as a challenge: the count of words it yields, so the rule that passes
// over a word at or above the modulus is a rule about a chance and not about nothing.
pub fn words_of_a_digest() -> usize {
    32 / 8
}

#[cfg(test)]
mod tests {
    use super::*;

    fn transcript() -> Transcript {
        Transcript::opening(&[0x11u8; 32], b"the object this proof is bound to")
    }

    // A challenge stands on everything absorbed before it: what a prover commits to after drawing
    // one cannot move it, and what it commits to before moves every challenge after.
    #[test]
    fn a_challenge_stands_on_everything_the_transcript_has_taken() {
        let mut counter = 0u64;
        let before = transcript().challenge(&mut counter);

        let mut moved = transcript();
        moved.absorb(&[0x22u8; 32]);
        let mut counter = 0u64;
        let after = moved.challenge(&mut counter);
        assert_ne!(before, after);

        // And two transcripts that took the same things in the same order draw the same challenge.
        let mut one = transcript();
        let mut two = transcript();
        one.absorb(&[0x22u8; 32]);
        two.absorb(&[0x22u8; 32]);
        let (mut a, mut b) = (0u64, 0u64);
        assert_eq!(one.challenge(&mut a), two.challenge(&mut b));
        // The order of what was taken is part of the value.
        let mut three = transcript();
        three.absorb(&[0x33u8; 32]);
        three.absorb(&[0x22u8; 32]);
        let mut four = transcript();
        four.absorb(&[0x22u8; 32]);
        four.absorb(&[0x33u8; 32]);
        let (mut c, mut d) = (0u64, 0u64);
        assert_ne!(three.challenge(&mut c), four.challenge(&mut d));
    }

    // Every challenge of one transcript differs from the next: the counter advances, so a proof
    // that needed two coefficients never gets one value twice.
    #[test]
    fn one_transcript_yields_a_run_of_distinct_challenges() {
        let held = transcript();
        let mut counter = 0u64;
        let drawn = held.challenges(&mut counter, 16);
        let mut seen = drawn.clone();
        seen.sort_by_key(|e| e.coefficients().map(|c| c.as_u64()));
        seen.dedup();
        assert_eq!(seen.len(), drawn.len());
    }

    // A word at or above the modulus is passed over rather than folded: every coefficient of every
    // challenge stands below the prime, which is what makes the draw uniform over the field.
    #[test]
    fn every_coefficient_of_every_challenge_stands_below_the_modulus() {
        let held = transcript();
        let mut counter = 0u64;
        for element in held.challenges(&mut counter, 200) {
            for coefficient in element.coefficients() {
                assert!(coefficient.as_u64() < crate::field::P);
            }
        }
    }

    // The positions of a proof: as many as asked for, none repeated, every one inside the domain.
    #[test]
    fn the_positions_are_distinct_and_inside_the_domain() {
        let seed = query_seed(&transcript());
        let mut counter = 0u64;
        let domain = 1usize << 10;
        let positions = seed.positions(&mut counter, 48, domain);
        assert_eq!(positions.len(), 48);
        assert!(positions.iter().all(|p| *p < domain));
        let mut sorted = positions.clone();
        sorted.sort_unstable();
        sorted.dedup();
        assert_eq!(sorted.len(), positions.len());
    }

    // The seed of the positions takes a domain of its own: a position and an element never come
    // out of one preimage, so a prover that could aim at one could not thereby aim at the other.
    #[test]
    fn the_seed_of_the_positions_is_not_the_transcript_itself() {
        let held = transcript();
        assert_ne!(query_seed(&held).value(), held.value());
    }

    #[test]
    fn a_digest_yields_four_words() {
        assert_eq!(words_of_a_digest(), 4);
    }
}
