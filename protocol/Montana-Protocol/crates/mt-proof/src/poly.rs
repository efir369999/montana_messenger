// The domains a proof stands over and the walk between the two readings of a polynomial: its
// values on a domain and its coefficients. The transform is the radix-two one over the subgroup
// the prime carries, and the extension of a trace is that transform read on a coset — a coset so
// that no point of the extended domain is a point of the trace, and a division by the vanishing
// polynomial never divides by zero.

use crate::field::{F, P};

mt_codec::constants! {
    DOMAINS:
    /// A generator of the whole multiplicative group of the field, and therefore the shift every
    /// extended domain stands at: it lies in no subgroup, so no point of an extension is a point
    /// of the trace it extends. Seven generates the group, which the test below holds it to.
    const GENERATOR: u64 = 7, code "a generator of the group of the field, which the tests verify";
}

// The doublings the prime carries, read off the prime rather than written beside it: the set names
// the subgroup where it derives the modulus, and a number restated here would be that derivation
// held in a second place.
const TWO_ADICITY: u32 = (P - 1).trailing_zeros();

#[derive(Debug, PartialEq, Eq)]
pub enum DomainError {
    SizeOutsideTheSubgroup { size: usize },
}

// The root of unity of order two to the given power.
pub fn root_of_unity(order_log2: u32) -> Result<F, DomainError> {
    if order_log2 > TWO_ADICITY {
        return Err(DomainError::SizeOutsideTheSubgroup {
            size: 1usize << order_log2.min(63),
        });
    }
    let generator = F::from_u64_reduced(GENERATOR);
    let mut root = generator.pow((P - 1) >> TWO_ADICITY);
    for _ in 0..(TWO_ADICITY - order_log2) {
        root = root.square();
    }
    Ok(root)
}

pub fn domain_of(size_log2: u32) -> Result<Vec<F>, DomainError> {
    let root = root_of_unity(size_log2)?;
    let mut out = Vec::with_capacity(1usize << size_log2);
    let mut point = F::ONE;
    for _ in 0..(1usize << size_log2) {
        out.push(point);
        point = point.times(root);
    }
    Ok(out)
}

// The transform in place: values to coefficients when inverted, coefficients to values otherwise.
fn transform(values: &mut [F], inverse: bool) -> Result<(), DomainError> {
    let size = values.len();
    if !size.is_power_of_two() {
        return Err(DomainError::SizeOutsideTheSubgroup { size });
    }
    let size_log2 = size.trailing_zeros();
    let mut target = 0usize;
    for at in 1..size {
        let mut bit = size >> 1;
        while target & bit != 0 {
            target ^= bit;
            bit >>= 1;
        }
        target |= bit;
        if at < target {
            values.swap(at, target);
        }
    }
    let root = root_of_unity(size_log2)?;
    let root = if inverse {
        root.inverse()
            .ok_or(DomainError::SizeOutsideTheSubgroup { size })?
    } else {
        root
    };
    let mut width = 2usize;
    while width <= size {
        let step = root.pow((size / width) as u64);
        for block in values.chunks_mut(width) {
            let mut twiddle = F::ONE;
            for at in 0..width / 2 {
                let left = block[at];
                let right = block[at + width / 2].times(twiddle);
                block[at] = left.plus(right);
                block[at + width / 2] = left.minus(right);
                twiddle = twiddle.times(step);
            }
        }
        width <<= 1;
    }
    if inverse {
        let scale = F::from_u64_reduced(size as u64)
            .inverse()
            .ok_or(DomainError::SizeOutsideTheSubgroup { size })?;
        for value in values.iter_mut() {
            *value = value.times(scale);
        }
    }
    Ok(())
}

pub fn interpolate(values: &[F]) -> Result<Vec<F>, DomainError> {
    let mut held = values.to_vec();
    transform(&mut held, true)?;
    Ok(held)
}

pub fn evaluate_over_domain(coefficients: &[F], size_log2: u32) -> Result<Vec<F>, DomainError> {
    let size = 1usize << size_log2;
    if coefficients.len() > size {
        return Err(DomainError::SizeOutsideTheSubgroup { size });
    }
    let mut held = coefficients.to_vec();
    held.resize(size, F::ZERO);
    transform(&mut held, false)?;
    Ok(held)
}

// The values of a polynomial on a coset: the coefficients are scaled by the powers of the shift
// and then transformed, which is the same walk read at another place.
pub fn evaluate_over_coset(
    coefficients: &[F],
    size_log2: u32,
    shift: F,
) -> Result<Vec<F>, DomainError> {
    let mut held = coefficients.to_vec();
    let mut power = F::ONE;
    for coefficient in held.iter_mut() {
        *coefficient = coefficient.times(power);
        power = power.times(shift);
    }
    evaluate_over_domain(&held, size_log2)
}

pub fn evaluate_at(coefficients: &[F], point: F) -> F {
    let mut out = F::ZERO;
    for coefficient in coefficients.iter().rev() {
        out = out.times(point).plus(*coefficient);
    }
    out
}

// The shift every extended domain of this scheme stands at: the generator of the whole group,
// which lies in no subgroup of it, so no point of an extension is a point of a trace.
pub fn coset_shift() -> F {
    F::from_u64_reduced(GENERATOR)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_generator_generates_the_whole_group() {
        let generator = F::from_u64_reduced(GENERATOR);
        for factor in [2u64, 3, 5, 17, 257, 65_537] {
            assert_ne!(generator.pow((P - 1) / factor), F::ONE, "factor {factor}");
        }
    }

    #[test]
    fn a_root_of_unity_has_the_order_it_is_asked_for() {
        for order_log2 in [1u32, 2, 3, 8, 16, 20, 32] {
            let root = root_of_unity(order_log2).expect("inside the subgroup");
            assert_eq!(root.pow(1u64 << order_log2), F::ONE, "order {order_log2}");
            assert_ne!(root.pow(1u64 << (order_log2 - 1)), F::ONE);
        }
        assert!(root_of_unity(33).is_err());
    }

    #[test]
    fn the_two_readings_of_a_polynomial_walk_into_each_other() {
        let values: Vec<F> = (0..64u64).map(|v| F::from_u64_reduced(v * 7 + 3)).collect();
        let coefficients = interpolate(&values).expect("a power of two");
        let back = evaluate_over_domain(&coefficients, 6).expect("the same size");
        assert_eq!(values, back);
        let domain = domain_of(6).expect("a power of two");
        for (at, point) in domain.iter().enumerate() {
            assert_eq!(evaluate_at(&coefficients, *point), values[at]);
        }
    }

    #[test]
    fn a_coset_holds_no_point_of_the_domain_it_extends() {
        let trace = domain_of(3).expect("a power of two");
        let coefficients: Vec<F> = (0..8u64).map(F::from_u64_reduced).collect();
        let extended = evaluate_over_coset(&coefficients, 6, coset_shift()).expect("extends");
        assert_eq!(extended.len(), 64);
        let domain = domain_of(6).expect("a power of two");
        let shift = coset_shift();
        for point in &domain {
            assert!(!trace.contains(&shift.times(*point)));
        }
        for (at, point) in domain.iter().enumerate() {
            assert_eq!(
                evaluate_at(&coefficients, shift.times(*point)),
                extended[at]
            );
        }
    }

    #[test]
    fn a_size_that_is_not_a_power_of_two_is_refused() {
        let values: Vec<F> = (0..6u64).map(F::from_u64_reduced).collect();
        assert!(interpolate(&values).is_err());
    }
}
