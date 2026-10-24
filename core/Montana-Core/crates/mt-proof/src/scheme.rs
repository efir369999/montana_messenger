// The scheme: what a prover writes and what a verifier checks, in the order the set states them.
// Nothing is decided here — the field, the extension, the blowup, the count of queries, the fold,
// the tail and the shape of a proof are the set's, and this is the machine that runs them.
//
// **What a proof hides, and by what.** Constraints hold on the live rows of a trace but the last,
// and boundaries name live rows; the rows after them — the free block — carry nothing of the
// statement, and the prover fills them with uniform randomness before it commits. What a query
// opens of a column, and what the two points outside the domain evaluate of it, are then linear
// forms over a polynomial of which more values are free than are ever opened, so they say nothing
// of the witness. A randomizer column of uniform values enters the deep composition with a weight
// of its own, so what a folding layer opens is uniform as well. The composition polynomial stands
// above the height by the free rows and is carried in two parts.

use crate::air::Description;
use crate::commit::{self, Tree};
use crate::ext::E;
use crate::ext::ELEMENT_BYTES;
use crate::field::F;
use crate::params::{
    Shape, COMPOSITION_PARTS, FOLD, FREE_ROWS, OOD_VALUES, QUERIES, ROW_VALUES, TAIL_DEGREE,
    TRACE_WIDTH_BOUND,
};
use crate::poly;
use crate::poseidon::Digest;
use crate::transcript::{self, Transcript};
use std::collections::BTreeMap;

// One rule of resolution for both sides: a literal is itself, a public value is the named limb,
// and a word is the pair of adjacent u32 limbs, low first. Hash words are canonical field
// elements (Canon, cells): reducing one would give distinct byte identifiers the same value.
// An absent limb, an oversized limb or a word at or above the modulus refuses.
pub fn resolve(value: crate::air::BoundaryValue, public: &[F]) -> Option<F> {
    Some(match value {
        crate::air::BoundaryValue::Literal(raw) => F::from_u64_reduced(raw),
        crate::air::BoundaryValue::Public(index) => *public.get(usize::from(index))?,
        crate::air::BoundaryValue::Word(index) => {
            let low = u32::try_from(public.get(usize::from(index))?.as_u64()).ok()?;
            let high = u32::try_from(public.get(usize::from(index) + 1)?.as_u64()).ok()?;
            F::try_from_u64(u64::from(low) | (u64::from(high) << 32))?
        }
    })
}

#[derive(Debug, PartialEq, Eq)]
pub enum ProveError {
    // What the prover built has no bytes to travel in, and the reason is the one the writing side
    // gives rather than a word standing for it.
    DoesNotFitTheShape(VerifyError),
    TraceOfAnotherShape,
    TraceDoesNotSatisfy,
    Shape,
    Domain,
    // The source of randomness the free block and the randomizer are drawn from did not answer. A
    // proof written without them would be a proof that discloses its witness, so none is written.
    Randomness,
    // The composition stands above what two parts carry. An honest trace never reaches this: the
    // degree of a constraint is bounded where a description becomes one.
    CompositionDegree,
}

#[derive(Debug, PartialEq, Eq)]
pub enum VerifyError {
    // The parts do not split as the shape says.
    Length,
    // The constraints at the point outside the domain do not give the composition there.
    Composition,
    // A leaf does not stand under the root it is offered against.
    Opening,
    // The deep composition at a query is not what the first folded layer opens there.
    DeepComposition,
    // A layer does not fold into the next.
    Folding,
    // The last layer is not of the degree the tail bounds.
    Tail,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Proof {
    pub trace_root: Digest,
    pub composition_root: Digest,
    pub layer_roots: Vec<Digest>,
    pub ood_values: Vec<E>,
    pub queries: Vec<Query>,
}

// What one query opens. The position it stands at is not among these: a position is drawn from
// the transcript, so a proof that carried one would carry a second record of a value the verifier
// already holds — and two records of one value are two values the day they disagree.
//
// A row is the slots of the bound: the columns of the trace at their own index, zero above the
// width, and the randomizer at the slot past the bound.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Query {
    pub row: Vec<F>,
    pub trace_path: Vec<Digest>,
    pub composition: [E; COMPOSITION_PARTS],
    pub composition_path: Vec<Digest>,
    pub openings: Vec<[E; FOLD]>,
    pub paths: Vec<Vec<Digest>>,
}

// The slot of the randomizer in a row: the one past the bound on the width, so a circuit of the
// full width and the randomizer never share a slot.
pub const RANDOMIZER: usize = TRACE_WIDTH_BOUND;

// Where a value stands in the slot beside the roots. The slot is of the values of a row and not of
// a width, so its shape is one for every circuit; a slot above the width and below the randomizer
// stands at zero, and the verifier refuses anything else there.
fn at_the_point(slot: usize) -> usize {
    slot
}

fn one_row_on(slot: usize) -> usize {
    ROW_VALUES + slot
}

fn of_the_composition(part: usize) -> usize {
    one_row_on(ROW_VALUES) + part
}

// The slot a column of the prover's columns stands at: the columns of the trace at their own
// index, and the randomizer — the one column past the width — at its slot.
fn slot_of(column: usize, width: usize) -> usize {
    if column < width {
        column
    } else {
        RANDOMIZER
    }
}

// The polynomial that vanishes on every row, at a point of the extension.
fn vanishing(point: E, rows: usize) -> E {
    power_of_rows(point, rows).minus(E::ONE)
}

fn power_of_rows(point: E, rows: usize) -> E {
    let mut power = point;
    for _ in 0..rows.trailing_zeros() {
        power = power.square();
    }
    power
}

// The divisors a composition is taken over: what vanishes on the live rows but the last, and what
// vanishes at the row of every boundary. Two things are held here rather than recomputed at each
// point of the extended domain, and both are of the same kind — work that does not depend on the
// point.
//
// **The rows are named once.** Many boundaries stand at one row — every capacity a chain opens
// with, every element its padding closes with — and the root of a row is an exponentiation. Naming
// each row once turns a count of boundaries into a count of rows.
//
// **The inversions are taken together.** A point meets every divisor, and an inversion apiece is
// what carried the cost of proving: the prefix products, one inversion of the last, and the walk
// back give all of them for the price of one and three multiplications each.
struct Divisors {
    roots: Vec<F>,
    of_boundary: Vec<usize>,
    // The rows the constraints do not reach: the last live row, whose transition would read the
    // free block, and the free block itself. What vanishes on the rows the constraints do reach is
    // what vanishes on every row, divided by what vanishes on these.
    excluded: Vec<F>,
}

impl Divisors {
    // **A row is looked up and never searched for.** Naming each row once is what turns a count of
    // boundaries into a count of rows, and a walk over the rows already named to find each one
    // turns that saving back into a product: a description binding every cell of a public input
    // carries tens of thousands of boundaries over thousands of rows, and the walk alone is their
    // product. The map costs one entry per distinct row and answers in the same order every build,
    // since what is ordered is the order the boundaries stand in and never the map.
    fn of(description: &Description, row_generator: F, shape: Shape) -> Divisors {
        let mut at_row: BTreeMap<u64, usize> = BTreeMap::new();
        let mut roots: Vec<F> = Vec::new();
        let mut of_boundary = Vec::with_capacity(description.boundaries.len());
        for boundary in &description.boundaries {
            let at = *at_row.entry(boundary.row).or_insert_with(|| {
                roots.push(row_generator.pow(boundary.row));
                roots.len() - 1
            });
            of_boundary.push(at);
        }
        let excluded = (shape.live_rows() - 1..shape.rows())
            .map(|row| row_generator.pow(row as u64))
            .collect();
        Divisors {
            roots,
            of_boundary,
            excluded,
        }
    }

    // What vanishes on the rows the constraints reach, at a point: what vanishes on every row,
    // divided by what vanishes on the rows they do not.
    fn live_vanishing(&self, point: E, rows: usize) -> Option<E> {
        let mut excluded = E::ONE;
        for root in &self.excluded {
            excluded = excluded.times(point.minus(E::from_base(*root)));
        }
        Some(vanishing(point, rows).times(excluded.inverse()?))
    }

    fn at(&self, point: E, rows: usize) -> Option<Vec<E>> {
        let mut values = Vec::with_capacity(self.roots.len() + 1);
        values.push(self.live_vanishing(point, rows)?);
        for root in &self.roots {
            values.push(point.minus(E::from_base(*root)));
        }
        let mut prefix = Vec::with_capacity(values.len());
        let mut running = E::ONE;
        for value in &values {
            prefix.push(running);
            running = running.times(*value);
        }
        let mut inverse = running.inverse()?;
        let mut out = vec![E::ZERO; values.len()];
        for at in (0..values.len()).rev() {
            out[at] = inverse.times(prefix[at]);
            inverse = inverse.times(values[at]);
        }
        Some(out)
    }

    // What vanishes on the excluded rows, at every point of the extended domain. Multiplying the
    // numerator of the constraints by it and dividing by what vanishes on every row is dividing
    // by what vanishes on the live rows but the last.
    fn excluded_over_the_domain(&self, points: &[F]) -> Vec<F> {
        points
            .iter()
            .map(|point| {
                let mut product = F::ONE;
                for root in &self.excluded {
                    product = product.times(point.minus(*root));
                }
                product
            })
            .collect()
    }
}

// On H = <g> of size n, the Lagrange basis at r is
// L_r(X) = (X^n - 1) / ((n / r) * (X - r)). Thus every boundary quotient
// beta * (T_c(X) - v) / (X - r) is exactly
// (T_c(X) * A_c(X) - B(X)) / (X^n - 1), where the samples on H are
// A_c(r) += beta * n/r and B(r) += beta * v * n/r.
//
// Interpolating these samples once avoids walking every boundary at every
// extended point. This changes no weights, constraints, transcript or proof
// bytes. The verifier and the prover's out-of-domain check retain the direct
// quotient sum, so they do not depend on this evaluation algorithm.
fn boundary_numerators(
    description: &Description,
    weights: &[E],
    public: &[F],
    extended: &[Vec<F>],
    shape: Shape,
) -> Result<Vec<E>, ProveError> {
    let rows = shape.rows();
    let mut out = vec![E::ZERO; shape.domain()];
    if description.boundaries.is_empty() {
        return Ok(out);
    }
    let generator = poly::root_of_unity(shape.rows_log2())
        .map_err(|_| ProveError::Domain)?
        .inverse()
        .ok_or(ProveError::Domain)?;
    let mut derivatives = Vec::with_capacity(rows);
    let mut derivative = F::from_u64_reduced(rows as u64);
    for _ in 0..rows {
        derivatives.push(derivative);
        derivative = derivative.times(generator);
    }
    let mut columns: BTreeMap<usize, Vec<usize>> = BTreeMap::new();
    for (at, boundary) in description.boundaries.iter().enumerate() {
        columns
            .entry(usize::from(boundary.column))
            .or_default()
            .push(at);
    }
    let mut constant = vec![E::ZERO; rows];
    for (column, boundaries) in columns {
        let trace = extended.get(column).ok_or(ProveError::Domain)?;
        let mut samples = vec![E::ZERO; rows];
        for at in boundaries {
            let boundary = &description.boundaries[at];
            let row = usize::try_from(boundary.row).map_err(|_| ProveError::Domain)?;
            let scale = *derivatives.get(row).ok_or(ProveError::Domain)?;
            let weight = weights
                .get(description.constraints.len() + at)
                .ok_or(ProveError::Domain)?
                .mul_base(scale);
            let held = resolve(boundary.value, public).ok_or(ProveError::Domain)?;
            samples[row] = samples[row].plus(weight);
            constant[row] = constant[row].minus(weight.mul_base(held));
        }
        add_boundary_polynomial(&samples, Some(trace), shape, &mut out)?;
    }
    add_boundary_polynomial(&constant, None, shape, &mut out)?;
    Ok(out)
}

// Only one component and one boundary column are extended at a time. Keeping
// all boundary columns over the extended domain would multiply peak memory by
// the width of the trace, defeating the space bound of the prover.
fn add_boundary_polynomial(
    samples: &[E],
    trace: Option<&[F]>,
    shape: Shape,
    out: &mut [E],
) -> Result<(), ProveError> {
    if out.len() != shape.domain() || trace.is_some_and(|v| v.len() != out.len()) {
        return Err(ProveError::Domain);
    }
    for component in 0..E::ZERO.coefficients().len() {
        let values: Vec<F> = samples
            .iter()
            .map(|e| e.coefficients()[component])
            .collect();
        let coefficients = poly::interpolate(&values).map_err(|_| ProveError::Domain)?;
        let extended =
            poly::evaluate_over_coset(&coefficients, shape.domain_log2(), poly::coset_shift())
                .map_err(|_| ProveError::Domain)?;
        for (at, value) in extended.into_iter().enumerate() {
            let value = trace.map_or(value, |column| value.times(column[at]));
            let mut held = out[at].coefficients();
            held[component] = held[component].plus(value);
            out[at] = E::of(held[0], held[1], held[2]);
        }
    }
    Ok(())
}

fn evaluate_at_ext(coefficients: &[F], point: E) -> E {
    let mut out = E::ZERO;
    for coefficient in coefficients.iter().rev() {
        out = out.times(point).plus(E::from_base(*coefficient));
    }
    out
}

fn evaluate_ext_coefficients(coefficients: &[E], point: E) -> E {
    let mut out = E::ZERO;
    for coefficient in coefficients.iter().rev() {
        out = out.times(point).plus(*coefficient);
    }
    out
}

// The value of one constraint over values the caller supplies for every column at a point and at
// the point one row on. The same body serves the prover over the extended domain and the verifier
// at the point outside it, which is what makes the two agree by construction.
fn constraint_at(
    description: &Description,
    at: usize,
    here: &[E],
    next: &[E],
    periodic: &[E],
) -> E {
    let mut sum = E::ZERO;
    for term in &description.constraints[at].terms {
        let mut product = E::from_base(F::from_u64_reduced(term.coefficient));
        for factor in &term.factors {
            let column = usize::from(factor.column);
            let value = if column < here.len() {
                if factor.shift == 0 {
                    here[column]
                } else {
                    next[column]
                }
            } else {
                periodic[column - here.len()]
            };
            for _ in 0..factor.power {
                product = product.times(value);
            }
        }
        sum = sum.plus(product);
    }
    sum
}

// A periodic column is a polynomial of the trace, but not one that must be handled at the length
// of the trace: a column of period `p` repeated over `n` rows is `Q(x^(n/p))`, and `Q` carries `p`
// coefficients. Held that way a prover transforms `p` values rather than `n` and a verifier
// evaluates `p` coefficients rather than `n` — for a frame that is two thousand against a million,
// which is the difference between a selector a telephone can carry and one it cannot. Nothing of
// the meaning moves: the column takes the same value at every row it ever took.
struct Periodic {
    over_the_period: Vec<F>,
    repeats: u64,
}

impl Periodic {
    fn at(&self, point: E) -> E {
        let mut raised = E::ONE;
        let mut square = point;
        let mut left = self.repeats;
        while left > 0 {
            if left & 1 == 1 {
                raised = raised.times(square);
            }
            square = square.square();
            left >>= 1;
        }
        evaluate_at_ext(&self.over_the_period, raised)
    }

    // The values the column takes over the extended domain. The points of the domain raised to the
    // power of the repeats form a coset of their own — of the blowup times the period — and the
    // column over the whole domain is that one block read again and again, which is why a prover
    // holds a block and not a column the length of the extension.
    fn over_the_domain(&self) -> Result<Vec<F>, ProveError> {
        let block_log2 =
            self.over_the_period.len().trailing_zeros() + crate::params::BLOWUP.trailing_zeros();
        let shift = poly::coset_shift().pow(self.repeats);
        poly::evaluate_over_coset(&self.over_the_period, block_log2, shift)
            .map_err(|_| ProveError::Domain)
    }
}

fn periodic_polynomials(
    description: &Description,
    rows: usize,
) -> Result<Vec<Periodic>, ProveError> {
    let mut out = Vec::with_capacity(description.periodic.len());
    for column in &description.periodic {
        let period = 1usize << column.period_log2;
        if period > rows {
            return Err(ProveError::TraceOfAnotherShape);
        }
        let values: Vec<F> = column.values[..period]
            .iter()
            .map(|value| F::from_u64_reduced(*value))
            .collect();
        out.push(Periodic {
            over_the_period: poly::interpolate(&values).map_err(|_| ProveError::Domain)?,
            repeats: (rows / period) as u64,
        });
    }
    Ok(out)
}

// The four points that share a fourth power stand a quarter of the domain apart, so folding reads
// one leaf and writes one value.
fn fold_four(values: &[E; FOLD], point: F, eta: F, challenge: E) -> Result<E, ProveError> {
    // The inverse transform of size four over the four points, then the challenge in place of the
    // variable: the parts of the polynomial in the fourth power, recombined.
    let quarter = F::from_u64_reduced(FOLD as u64)
        .inverse()
        .ok_or(ProveError::Domain)?;
    let point_inverse = point.inverse().ok_or(ProveError::Domain)?;
    let mut out = E::ZERO;
    let mut challenge_power = E::ONE;
    let mut shift = F::ONE;
    for k in 0..FOLD {
        let step = eta.pow(((FOLD - k) % FOLD) as u64);
        let mut part = E::ZERO;
        let mut root = F::ONE;
        for value in values.iter() {
            part = part.plus(value.mul_base(root));
            root = root.times(step);
        }
        out = out.plus(
            part.mul_base(quarter)
                .mul_base(shift)
                .times(challenge_power),
        );
        challenge_power = challenge_power.times(challenge);
        shift = shift.times(point_inverse);
    }
    Ok(out)
}

fn layer_domains(shape: Shape) -> Result<Vec<(usize, F, F)>, ProveError> {
    // Size, generator and shift of every layer, the base domain first.
    let mut out = Vec::with_capacity(shape.layers() + 1);
    let mut size_log2 = shape.domain_log2();
    let mut generator = poly::root_of_unity(size_log2).map_err(|_| ProveError::Domain)?;
    let mut shift = poly::coset_shift();
    for _ in 0..=shape.layers() {
        out.push((1usize << size_log2, generator, shift));
        if size_log2 >= FOLD.trailing_zeros() {
            size_log2 -= FOLD.trailing_zeros();
        }
        generator = generator.pow(FOLD as u64);
        shift = shift.pow(FOLD as u64);
    }
    Ok(out)
}

// The tail: the last layer stands as its coefficients rather than as a tree, so its degree is
// bounded by how many of them there are and a verifier checks the bound by counting rather than by
// sampling. It is carried once and not per query, which is why the last layer opens no path.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Tail(pub Vec<E>);

impl Tail {
    fn leaf(&self) -> Digest {
        commit::leaf_of_elements(&self.0)
    }

    fn at(&self, point: F) -> E {
        let mut out = E::ZERO;
        for coefficient in self.0.iter().rev() {
            out = out.mul_base(point).plus(*coefficient);
        }
        out
    }
}

// Elements drawn uniformly from the field: eight bytes of the system's randomness apiece, taken
// again while they stand at or above the modulus, so no element is likelier than another.
fn random_elements(count: usize) -> Result<Vec<F>, ProveError> {
    let mut out = Vec::with_capacity(count);
    let mut block = vec![0u8; 8 * count.max(1)];
    while out.len() < count {
        getrandom::getrandom(&mut block).map_err(|_| ProveError::Randomness)?;
        for eight in block.as_chunks::<8>().0 {
            if let Some(value) = F::try_from_u64(u64::from_le_bytes(*eight)) {
                out.push(value);
                if out.len() == count {
                    break;
                }
            }
        }
    }
    Ok(out)
}

// The columns the prover commits to: the trace with its free block filled with uniform randomness,
// and the randomizer after them. The trace a circuit wrote is not touched — what is randomized is
// a copy, so the circuit's own view of its rows stands for the checks before this.
fn randomized_columns(trace: &[Vec<F>], shape: Shape) -> Result<Vec<Vec<F>>, ProveError> {
    let live = shape.live_rows();
    let rows = shape.rows();
    let mut columns = Vec::with_capacity(trace.len() + 1);
    for column in trace {
        let mut held = column.clone();
        let fresh = random_elements(rows - live)?;
        held[live..].copy_from_slice(&fresh);
        columns.push(held);
    }
    columns.push(random_elements(rows)?);
    Ok(columns)
}

// The composition over the extended domain, split into the parts the shape carries: the
// coefficients below the height, and the coefficients from the height to the height plus the free
// rows. Anything above is a composition no honest trace produces, and it is refused rather than
// dropped.
struct SplitComposition {
    first: Vec<E>,
    second: Vec<E>,
    first_coefficients: Vec<E>,
    second_coefficients: Vec<E>,
}

fn split_composition(values: &[E], shape: Shape) -> Result<SplitComposition, ProveError> {
    let rows = shape.rows();
    let domain = shape.domain();
    if values.len() != domain {
        return Err(ProveError::Domain);
    }
    let shift_inverse = poly::coset_shift().inverse().ok_or(ProveError::Domain)?;
    let mut coordinates: Vec<Vec<F>> = Vec::with_capacity(3);
    for component in 0..3 {
        let samples: Vec<F> = values.iter().map(|e| e.coefficients()[component]).collect();
        let mut coefficients = poly::interpolate(&samples).map_err(|_| ProveError::Domain)?;
        let mut power = F::ONE;
        for coefficient in coefficients.iter_mut() {
            *coefficient = coefficient.times(power);
            power = power.times(shift_inverse);
        }
        if coefficients[rows + FREE_ROWS..]
            .iter()
            .any(|coefficient| !coefficient.is_zero())
        {
            return Err(ProveError::CompositionDegree);
        }
        coordinates.push(coefficients);
    }
    let gather = |from: usize, to: usize| -> Vec<E> {
        (from..to)
            .map(|k| E::of(coordinates[0][k], coordinates[1][k], coordinates[2][k]))
            .collect()
    };
    let first_coefficients = gather(0, rows);
    let second_coefficients = gather(rows, rows + FREE_ROWS);
    let over_the_domain = |coefficients: &[E]| -> Result<Vec<E>, ProveError> {
        let mut out = vec![E::ZERO; domain];
        for component in 0..3 {
            let base: Vec<F> = coefficients
                .iter()
                .map(|e| e.coefficients()[component])
                .collect();
            let evaluated =
                poly::evaluate_over_coset(&base, shape.domain_log2(), poly::coset_shift())
                    .map_err(|_| ProveError::Domain)?;
            for (at, value) in evaluated.into_iter().enumerate() {
                let mut held = out[at].coefficients();
                held[component] = value;
                out[at] = E::of(held[0], held[1], held[2]);
            }
        }
        Ok(out)
    };
    Ok(SplitComposition {
        first: over_the_domain(&first_coefficients)?,
        second: over_the_domain(&second_coefficients)?,
        first_coefficients,
        second_coefficients,
    })
}

// The slots of a row at one point of the extended domain: every column at its slot, zero above the
// width, the randomizer at its own.
fn row_at(columns: &[Vec<F>], width: usize, at: usize) -> Vec<F> {
    let mut row = vec![F::ZERO; ROW_VALUES];
    for (column, values) in columns.iter().enumerate() {
        row[slot_of(column, width)] = values[at];
    }
    row
}

// What a leaf of the tree of the trace is taken over: the columns of the trace and the randomizer,
// in that order, and nothing of the padding — a leaf over the padding would be a leaf over zeros
// every circuit shares.
fn committed_row(row: &[F], width: usize) -> Vec<F> {
    let mut held = row[..width].to_vec();
    held.push(row[RANDOMIZER]);
    held
}

pub fn prove(
    description: &Description,
    public_inputs: &[u8],
    trace: &[Vec<F>],
) -> Result<Vec<u8>, ProveError> {
    let air_hash = &description.identifier();
    let shape =
        Shape::of_rows_log2(u32::from(description.rows_log2)).map_err(|_| ProveError::Shape)?;
    let width = usize::from(description.trace_width);
    let rows = shape.rows();
    let domain = shape.domain();
    if width > TRACE_WIDTH_BOUND
        || trace.len() != width
        || trace.iter().any(|column| column.len() != rows)
    {
        return Err(ProveError::TraceOfAnotherShape);
    }
    let public = crate::poseidon::limbs_of(public_inputs);
    if !description.satisfied_by(trace, &public) {
        return Err(ProveError::TraceDoesNotSatisfy);
    }

    // The free block and the randomizer, drawn before anything is committed.
    let columns = randomized_columns(trace, shape)?;
    let coefficients: Vec<Vec<F>> = columns
        .iter()
        .map(|column| poly::interpolate(column).map_err(|_| ProveError::Domain))
        .collect::<Result<_, _>>()?;
    let extended: Vec<Vec<F>> = coefficients
        .iter()
        .map(|column| {
            poly::evaluate_over_coset(column, shape.domain_log2(), poly::coset_shift())
                .map_err(|_| ProveError::Domain)
        })
        .collect::<Result<_, _>>()?;
    let periodic = periodic_polynomials(description, rows)?;
    let periodic_extended: Vec<Vec<F>> = periodic
        .iter()
        .map(|column| column.over_the_domain())
        .collect::<Result<_, _>>()?;

    let trace_tree = Tree::of(
        (0..domain)
            .map(|at| commit::leaf(&committed_row(&row_at(&extended, width, at), width)))
            .collect(),
    );

    let mut transcript = Transcript::opening(air_hash, public_inputs);
    transcript.absorb(&trace_tree.root().bytes());
    let mut counter = 0u64;
    let weights = transcript.challenges(
        &mut counter,
        description.constraints.len() + description.boundaries.len(),
    );

    let points = domain_points(shape)?;
    let step = 1usize << crate::params::BLOWUP.trailing_zeros();
    let row_generator = poly::root_of_unity(shape.rows_log2()).map_err(|_| ProveError::Domain)?;
    let divisors = Divisors::of(description, row_generator, shape);
    let mut composition = boundary_numerators(description, &weights, &public, &extended, shape)?;
    // X^n repeats once per blowup on this coset. Its inverses are base-field
    // values; compute that short period once rather than invert at every point.
    let inverted_vanishing: Vec<F> = points
        .iter()
        .take(step)
        .map(|point| {
            point
                .pow(rows as u64)
                .minus(F::ONE)
                .inverse()
                .ok_or(ProveError::Domain)
        })
        .collect::<Result<_, _>>()?;
    // The constraints are divided by what vanishes on the live rows but the last: the numerator
    // takes what vanishes on the excluded rows and the whole is divided by what vanishes on all.
    let excluded = divisors.excluded_over_the_domain(&points);
    for (at, value) in composition.iter_mut().enumerate() {
        let here: Vec<E> = (0..width)
            .map(|column| E::from_base(extended[column][at]))
            .collect();
        let next: Vec<E> = (0..width)
            .map(|column| E::from_base(extended[column][(at + step) % domain]))
            .collect();
        let period: Vec<E> = periodic_extended
            .iter()
            .map(|column| E::from_base(column[at % column.len()]))
            .collect();
        let mut numerator = E::ZERO;
        for (constraint, weight) in weights
            .iter()
            .take(description.constraints.len())
            .enumerate()
        {
            numerator = numerator.plus(weight.times(constraint_at(
                description,
                constraint,
                &here,
                &next,
                &period,
            )));
        }
        *value = value
            .plus(numerator.mul_base(excluded[at]))
            .mul_base(inverted_vanishing[at % step]);
    }
    let split = split_composition(&composition, shape)?;

    let composition_tree = Tree::of(
        (0..domain)
            .map(|at| commit::leaf_of_elements(&[split.first[at], split.second[at]]))
            .collect(),
    );
    transcript.absorb(&composition_tree.root().bytes());
    let mut out_of_domain = transcript.challenge(&mut counter);
    while stands_in_the_base_field(out_of_domain) {
        out_of_domain = transcript.challenge(&mut counter);
    }
    let shifted = out_of_domain.mul_base(row_generator);

    let mut ood: Vec<E> = vec![E::ZERO; OOD_VALUES];
    for (column, coefficients) in coefficients.iter().enumerate() {
        let slot = slot_of(column, width);
        ood[at_the_point(slot)] = evaluate_at_ext(coefficients, out_of_domain);
        ood[one_row_on(slot)] = evaluate_at_ext(coefficients, shifted);
    }
    ood[of_the_composition(0)] =
        evaluate_ext_coefficients(&split.first_coefficients, out_of_domain);
    ood[of_the_composition(1)] =
        evaluate_ext_coefficients(&split.second_coefficients, out_of_domain);
    // The parts the prover opens are what the verifier will recompute from the constraints; a
    // disagreement here is a trace the arithmetic above did not fold, and nothing is written.
    let period_at: Vec<E> = periodic
        .iter()
        .map(|column| column.at(out_of_domain))
        .collect();
    let inverted = divisors.at(out_of_domain, rows).ok_or(ProveError::Domain)?;
    let direct = value_of_the_composition(
        description,
        &weights,
        &public,
        &ood[at_the_point(0)..at_the_point(width)],
        &ood[one_row_on(0)..one_row_on(width)],
        &period_at,
        &divisors,
        &inverted,
    )?;
    if direct != composition_of_the_parts(&ood, out_of_domain, rows) {
        return Err(ProveError::Domain);
    }
    transcript.absorb(&transcript::bytes_of(&ood));
    let deep = transcript.challenges(&mut counter, OOD_VALUES);

    let mut layer_values: Vec<Vec<E>> = Vec::with_capacity(shape.layers() + 1);
    let mut first_layer = Vec::with_capacity(domain);
    for (at, point) in points.iter().enumerate() {
        let here: Vec<E> = row_at(&extended, width, at)
            .into_iter()
            .map(E::from_base)
            .collect();
        first_layer.push(deep_at(
            &deep,
            &here,
            &[split.first[at], split.second[at]],
            &ood,
            E::from_base(*point),
            out_of_domain,
            shifted,
        )?);
    }
    layer_values.push(first_layer);

    let domains = layer_domains(shape)?;
    let mut trees: Vec<Tree> = Vec::with_capacity(shape.layers());
    for layer in 0..shape.layers() {
        let (size, generator, shift) = domains[layer];
        let quarter = size / FOLD;
        let values = &layer_values[layer];
        let tree = Tree::of(
            (0..quarter)
                .map(|j| {
                    let four: Vec<E> = (0..FOLD).map(|k| values[j + k * quarter]).collect();
                    commit::leaf_of_elements(&four)
                })
                .collect(),
        );
        transcript.absorb(&tree.root().bytes());
        let challenge = transcript.challenge(&mut counter);
        let eta = generator.pow(quarter as u64);
        let mut folded = Vec::with_capacity(quarter);
        for j in 0..quarter {
            let four: [E; FOLD] = std::array::from_fn(|k| values[j + k * quarter]);
            let point = shift.times(generator.pow(j as u64));
            folded.push(fold_four(&four, point, eta, challenge)?);
        }
        trees.push(tree);
        layer_values.push(folded);
    }

    let (tail_size, tail_generator, tail_shift) = domains[shape.layers()];
    let tail = Tail(coefficients_of_a_coset(
        &layer_values[shape.layers()],
        tail_size,
        tail_generator,
        tail_shift,
    )?);
    transcript.absorb(&tail.leaf().bytes());

    let mut drawn = 0u64;
    let draw = transcript::query_seed(&transcript);
    let positions = draw.positions(&mut drawn, QUERIES, domain);

    let mut queries = Vec::with_capacity(QUERIES);
    for position in positions {
        let row = row_at(&extended, width, position);
        let trace_path = trace_tree.path(position).map_err(|_| ProveError::Domain)?;
        let composition_path = composition_tree
            .path(position)
            .map_err(|_| ProveError::Domain)?;
        let mut openings = Vec::with_capacity(shape.layers());
        let mut paths = Vec::with_capacity(shape.layers());
        let mut at = position;
        for layer in 0..shape.layers() {
            let (size, _, _) = domains[layer];
            let quarter = size / FOLD;
            let j = at % quarter;
            let values = &layer_values[layer];
            openings.push(std::array::from_fn(|k| values[j + k * quarter]));
            paths.push(trees[layer].path(j).map_err(|_| ProveError::Domain)?);
            at = j;
        }
        queries.push(Query {
            row,
            trace_path,
            composition: [split.first[position], split.second[position]],
            composition_path,
            openings,
            paths,
        });
    }

    let proof = Proof {
        trace_root: trace_tree.root(),
        composition_root: composition_tree.root(),
        layer_roots: trees.iter().map(|tree| tree.root()).collect(),
        ood_values: ood,
        queries,
    };
    proof
        .encode(shape, &tail)
        .map_err(ProveError::DoesNotFitTheShape)
}

// The composition at the point outside the domain, read off its two parts: the first, and the
// second times the point raised to the height.
fn composition_of_the_parts(ood: &[E], point: E, rows: usize) -> E {
    ood[of_the_composition(0)].plus(power_of_rows(point, rows).times(ood[of_the_composition(1)]))
}

// A point of the base field may be a row of the trace or a point of the extension of it, and the
// point one row on lies in the base field exactly when this one does. One condition therefore
// covers both, and covers them strictly: the point is taken again while it is not of the
// extension proper.
fn stands_in_the_base_field(point: E) -> bool {
    let coefficients = point.coefficients();
    coefficients[1].is_zero() && coefficients[2].is_zero()
}

// The points of the extended domain, in the order the leaves stand in.
fn domain_points(shape: Shape) -> Result<Vec<F>, ProveError> {
    let generator = poly::root_of_unity(shape.domain_log2()).map_err(|_| ProveError::Domain)?;
    let shift = poly::coset_shift();
    let mut out = Vec::with_capacity(shape.domain());
    let mut power = shift;
    for _ in 0..shape.domain() {
        out.push(power);
        power = power.times(generator);
    }
    Ok(out)
}

// The composition at one point: every transition divided by what vanishes on the live rows but the
// last, every boundary divided by what vanishes at its row, each under its own weight. The divisors
// arrive inverted — the first of them the one of the rows the constraints reach, the rest those of
// the rows the boundaries stand at — so this body divides nowhere. Both parties use this direct sum
// at the point outside the domain; only the prover's domain sweep uses batching.
#[allow(clippy::too_many_arguments)]
fn value_of_the_composition(
    description: &Description,
    weights: &[E],
    public: &[F],
    here: &[E],
    next: &[E],
    periodic: &[E],
    divisors: &Divisors,
    inverted: &[E],
) -> Result<E, ProveError> {
    let mut sum = E::ZERO;
    let divisor = *inverted.first().ok_or(ProveError::Domain)?;
    for (at, weight) in weights
        .iter()
        .take(description.constraints.len())
        .enumerate()
    {
        let value = constraint_at(description, at, here, next, periodic);
        sum = sum.plus(weight.times(value).times(divisor));
    }
    for (at, boundary) in description.boundaries.iter().enumerate() {
        let column = usize::from(boundary.column);
        let held = resolve(boundary.value, public).ok_or(ProveError::Domain)?;
        let numerator = here[column].minus(E::from_base(held));
        let of_the_row = divisors.of_boundary.get(at).ok_or(ProveError::Domain)?;
        let denominator = *inverted.get(1 + of_the_row).ok_or(ProveError::Domain)?;
        sum = sum.plus(
            weights[description.constraints.len() + at]
                .times(numerator)
                .times(denominator),
        );
    }
    Ok(sum)
}

// The deep composition at one point: every slot of the row against its value at the point outside
// the domain and against its value one row on, and each part of the composition against its own —
// a difference divided by a difference, which is a polynomial exactly when the values offered are
// the true ones. The randomizer stands among the slots, so its uniform values enter the batch under
// weights of their own.
#[allow(clippy::too_many_arguments)]
fn deep_at(
    weights: &[E],
    here: &[E],
    composition: &[E; COMPOSITION_PARTS],
    ood: &[E],
    point: E,
    out_of_domain: E,
    shifted: E,
) -> Result<E, ProveError> {
    let first = point
        .minus(out_of_domain)
        .inverse()
        .ok_or(ProveError::Domain)?;
    let second = point.minus(shifted).inverse().ok_or(ProveError::Domain)?;
    let mut sum = E::ZERO;
    for (slot, value) in here.iter().enumerate() {
        sum = sum.plus(
            weights[at_the_point(slot)]
                .times(value.minus(ood[at_the_point(slot)]))
                .times(first),
        );
        sum = sum.plus(
            weights[one_row_on(slot)]
                .times(value.minus(ood[one_row_on(slot)]))
                .times(second),
        );
    }
    for (part, value) in composition.iter().enumerate() {
        sum = sum.plus(
            weights[of_the_composition(part)]
                .times(value.minus(ood[of_the_composition(part)]))
                .times(first),
        );
    }
    Ok(sum)
}

// The coefficients of the polynomial a layer stands for, read back from its values over a coset:
// three interpolations over the base field, one per coordinate of the extension, then the shift
// undone coefficient by coefficient.
fn coefficients_of_a_coset(
    values: &[E],
    size: usize,
    generator: F,
    shift: F,
) -> Result<Vec<E>, ProveError> {
    let inverse = generator.inverse().ok_or(ProveError::Domain)?;
    let count = F::from_u64_reduced(size as u64)
        .inverse()
        .ok_or(ProveError::Domain)?;
    let shift_inverse = shift.inverse().ok_or(ProveError::Domain)?;
    let mut out = vec![E::ZERO; size];
    for (k, slot) in out.iter_mut().enumerate() {
        let step = inverse.pow(k as u64);
        let mut sum = E::ZERO;
        let mut root = F::ONE;
        for value in values.iter() {
            sum = sum.plus(value.mul_base(root));
            root = root.times(step);
        }
        *slot = sum.mul_base(count).mul_base(shift_inverse.pow(k as u64));
    }
    while out.len() > crate::params::TAIL_DEGREE && out.last() == Some(&E::ZERO) {
        out.pop();
    }
    Ok(out)
}

// The six checks, in the order the set states them. The door takes bytes, because bytes are how a
// proof arrives — inside a proposal, a frame, a node of the fold, a candidacy — and a door that
// took a parsed object would leave the one path that exists in the world unchecked. It takes the
// description rather than an identifier of one, and computes the identifier itself: two arguments
// that must agree are one argument.
pub fn verify(
    description: &Description,
    public_inputs: &[u8],
    bytes: &[u8],
) -> Result<(), VerifyError> {
    let shape =
        Shape::of_rows_log2(u32::from(description.rows_log2)).map_err(|_| VerifyError::Length)?;
    let width = usize::from(description.trace_width);
    if width > TRACE_WIDTH_BOUND {
        return Err(VerifyError::Length);
    }
    let rows = shape.rows();
    let domain = shape.domain();

    // One: the parts split as the shape says; the slot beside the roots holds zero where a column
    // stands above the width and below the randomizer, and so does a row a query opens; and the
    // tail carries no more coefficients than the bound allows. A proof that wrote anything into
    // what the padding covers would carry two encodings of one claim, and an object taking its
    // name over its own bytes would then have two names.
    let (proof, tail) = Proof::decode(shape, bytes)?;
    for column in width..TRACE_WIDTH_BOUND {
        if !proof.ood_values[at_the_point(column)].is_zero()
            || !proof.ood_values[one_row_on(column)].is_zero()
        {
            return Err(VerifyError::Length);
        }
    }
    for query in &proof.queries {
        if query.row[width..TRACE_WIDTH_BOUND]
            .iter()
            .any(|value| !value.is_zero())
        {
            return Err(VerifyError::Length);
        }
    }

    let air_hash = description.identifier();
    let mut transcript = Transcript::opening(&air_hash, public_inputs);
    transcript.absorb(&proof.trace_root.bytes());
    let mut counter = 0u64;
    let weights = transcript.challenges(
        &mut counter,
        description.constraints.len() + description.boundaries.len(),
    );
    transcript.absorb(&proof.composition_root.bytes());
    let mut out_of_domain = transcript.challenge(&mut counter);
    while stands_in_the_base_field(out_of_domain) {
        out_of_domain = transcript.challenge(&mut counter);
    }
    let row_generator = poly::root_of_unity(shape.rows_log2()).map_err(|_| VerifyError::Length)?;
    let shifted = out_of_domain.mul_base(row_generator);

    // Two: the constraints at the point outside the domain give the composition claimed there,
    // read off its two parts.
    let periodic = periodic_polynomials(description, rows).map_err(|_| VerifyError::Composition)?;
    let period_at: Vec<E> = periodic
        .iter()
        .map(|column| column.at(out_of_domain))
        .collect();
    let public = crate::poseidon::limbs_of(public_inputs);
    let divisors = Divisors::of(description, row_generator, shape);
    let inverted = divisors
        .at(out_of_domain, rows)
        .ok_or(VerifyError::Composition)?;
    let recomputed = value_of_the_composition(
        description,
        &weights,
        &public,
        &proof.ood_values[at_the_point(0)..at_the_point(width)],
        &proof.ood_values[one_row_on(0)..one_row_on(width)],
        &period_at,
        &divisors,
        &inverted,
    )
    .map_err(|_| VerifyError::Composition)?;
    if recomputed != composition_of_the_parts(&proof.ood_values, out_of_domain, rows) {
        return Err(VerifyError::Composition);
    }

    transcript.absorb(&transcript::bytes_of(&proof.ood_values));
    let deep = transcript.challenges(&mut counter, OOD_VALUES);
    let domains = layer_domains(shape).map_err(|_| VerifyError::Length)?;
    let mut challenges = Vec::with_capacity(shape.layers());
    for root in &proof.layer_roots {
        transcript.absorb(&root.bytes());
        challenges.push(transcript.challenge(&mut counter));
    }
    transcript.absorb(&tail.leaf().bytes());

    let mut drawn = 0u64;
    let draw = transcript::query_seed(&transcript);
    let positions = draw.positions(&mut drawn, QUERIES, domain);
    let points = domain_points(shape).map_err(|_| VerifyError::Length)?;

    for (query, position) in proof.queries.iter().zip(positions) {
        // Three: every leaf stands under the root it is offered against, at the position the
        // transcript drew and not at one the proof named.
        commit::verify(
            &commit::leaf(&committed_row(&query.row, width)),
            position,
            domain,
            &query.trace_path,
            &proof.trace_root,
        )
        .map_err(|_| VerifyError::Opening)?;
        commit::verify(
            &commit::leaf_of_elements(&query.composition),
            position,
            domain,
            &query.composition_path,
            &proof.composition_root,
        )
        .map_err(|_| VerifyError::Opening)?;
        let mut at = position;
        for (layer, (size, _, _)) in domains.iter().take(shape.layers()).copied().enumerate() {
            let quarter = size / FOLD;
            let j = at % quarter;
            commit::verify(
                &commit::leaf_of_elements(&query.openings[layer]),
                j,
                quarter,
                &query.paths[layer],
                &proof.layer_roots[layer],
            )
            .map_err(|_| VerifyError::Opening)?;
            at = j;
        }

        // Four: the deep composition formed from the opened leaves and the values outside the
        // domain is what the first layer opens at this place.
        let here: Vec<E> = query.row.iter().map(|value| E::from_base(*value)).collect();
        let expected = deep_at(
            &deep,
            &here,
            &query.composition,
            &proof.ood_values,
            E::from_base(points[position]),
            out_of_domain,
            shifted,
        )
        .map_err(|_| VerifyError::DeepComposition)?;
        let quarter = domain / FOLD;
        if query.openings[0][position / quarter] != expected {
            return Err(VerifyError::DeepComposition);
        }

        // Five: every layer folds into the next, and the last folds into the tail.
        let mut at = position;
        for (layer, (size, generator, shift)) in
            domains.iter().take(shape.layers()).copied().enumerate()
        {
            let quarter = size / FOLD;
            let j = at % quarter;
            let point = shift.times(generator.pow(j as u64));
            let eta = generator.pow(quarter as u64);
            let folded = fold_four(&query.openings[layer], point, eta, challenges[layer])
                .map_err(|_| VerifyError::Folding)?;
            let (_, next_generator, next_shift) = domains[layer + 1];
            if layer + 1 == shape.layers() {
                // Six: the tail answers where the last fold lands, and it carries no more
                // coefficients than the bound allows — counted above, where the parts were split.
                let next_point = next_shift.times(next_generator.pow(j as u64));
                if tail.at(next_point) != folded {
                    return Err(VerifyError::Tail);
                }
            } else {
                let next_quarter = domains[layer + 1].0 / FOLD;
                if query.openings[layer + 1][j / next_quarter] != folded {
                    return Err(VerifyError::Folding);
                }
            }
            at = j;
        }
    }

    Ok(())
}

// The bytes of a proof: the order the set fixes, and the widths it fixes, so a proof of a narrow
// circuit is the same length as a proof of the widest one and the length discloses nothing about
// what was proven. Padding is written as zero and refused as anything else.
impl Proof {
    pub fn encode(&self, shape: Shape, tail: &Tail) -> Result<Vec<u8>, VerifyError> {
        let mut out = Vec::with_capacity(shape.proof_bytes());
        out.extend_from_slice(&self.trace_root.bytes());
        out.extend_from_slice(&self.composition_root.bytes());
        if self.layer_roots.len() != shape.layers() || self.ood_values.len() != OOD_VALUES {
            return Err(VerifyError::Length);
        }
        for root in &self.layer_roots {
            out.extend_from_slice(&root.bytes());
        }
        for value in &self.ood_values {
            out.extend_from_slice(&value.to_bytes());
        }
        if tail.0.len() > TAIL_DEGREE {
            return Err(VerifyError::Tail);
        }
        for at in 0..TAIL_DEGREE {
            let value = tail.0.get(at).copied().unwrap_or(E::ZERO);
            out.extend_from_slice(&value.to_bytes());
        }
        if self.queries.len() != QUERIES {
            return Err(VerifyError::Length);
        }
        for query in &self.queries {
            if query.row.len() != ROW_VALUES
                || query.trace_path.len() != shape.domain_log2() as usize
                || query.composition_path.len() != shape.domain_log2() as usize
                || query.openings.len() != shape.layers()
                || query.paths.len() != shape.layers()
            {
                return Err(VerifyError::Length);
            }
            for node in &query.trace_path {
                out.extend_from_slice(&node.bytes());
            }
            for value in &query.row {
                out.extend_from_slice(&value.as_u64().to_le_bytes());
            }
            for node in &query.composition_path {
                out.extend_from_slice(&node.bytes());
            }
            for part in &query.composition {
                out.extend_from_slice(&part.to_bytes());
            }
            for (layer, path) in query.paths.iter().enumerate() {
                if path.len() != shape.domain_log2() as usize - 2 - 2 * layer {
                    return Err(VerifyError::Length);
                }
                for node in path {
                    out.extend_from_slice(&node.bytes());
                }
            }
            for opening in &query.openings {
                for value in opening {
                    out.extend_from_slice(&value.to_bytes());
                }
            }
        }
        if out.len() != shape.proof_bytes() {
            return Err(VerifyError::Length);
        }
        Ok(out)
    }

    pub fn decode(shape: Shape, bytes: &[u8]) -> Result<(Proof, Tail), VerifyError> {
        if bytes.len() != shape.proof_bytes() {
            return Err(VerifyError::Length);
        }
        let mut at = 0usize;
        // A root and a node of a path arrive as thirty-two bytes, and thirty-two bytes are not a
        // digest until every limb of them is an element. What is refused here is what no prover can
        // write and only a sender can: bytes the arithmetic of this permutation has no meaning for.
        let root = |at: &mut usize| -> Result<Digest, VerifyError> {
            let mut out = [0u8; 32];
            out.copy_from_slice(&bytes[*at..*at + 32]);
            *at += 32;
            Digest::of_bytes(&out).ok_or(VerifyError::Length)
        };
        let trace_root = root(&mut at)?;
        let composition_root = root(&mut at)?;
        let mut layer_roots = Vec::with_capacity(shape.layers());
        for _ in 0..shape.layers() {
            layer_roots.push(root(&mut at)?);
        }
        let element = |at: &mut usize| -> Result<E, VerifyError> {
            let mut raw = [0u8; ELEMENT_BYTES];
            raw.copy_from_slice(&bytes[*at..*at + ELEMENT_BYTES]);
            *at += ELEMENT_BYTES;
            E::from_bytes(&raw).ok_or(VerifyError::Length)
        };
        let mut ood_values = Vec::with_capacity(OOD_VALUES);
        for _ in 0..OOD_VALUES {
            ood_values.push(element(&mut at)?);
        }
        let mut tail = Vec::with_capacity(TAIL_DEGREE);
        for _ in 0..TAIL_DEGREE {
            tail.push(element(&mut at)?);
        }
        let mut queries = Vec::with_capacity(QUERIES);
        for _ in 0..QUERIES {
            let mut trace_path = Vec::with_capacity(shape.domain_log2() as usize);
            for _ in 0..shape.domain_log2() {
                trace_path.push(root(&mut at)?);
            }
            let mut row = Vec::with_capacity(ROW_VALUES);
            for _ in 0..ROW_VALUES {
                let mut raw = [0u8; 8];
                raw.copy_from_slice(&bytes[at..at + 8]);
                at += 8;
                row.push(F::try_from_u64(u64::from_le_bytes(raw)).ok_or(VerifyError::Length)?);
            }
            let mut composition_path = Vec::with_capacity(shape.domain_log2() as usize);
            for _ in 0..shape.domain_log2() {
                composition_path.push(root(&mut at)?);
            }
            let mut composition = [E::ZERO; COMPOSITION_PARTS];
            for part in composition.iter_mut() {
                *part = element(&mut at)?;
            }
            let mut paths = Vec::with_capacity(shape.layers());
            for layer in 0..shape.layers() {
                let levels = shape.domain_log2() as usize - 2 - 2 * layer;
                let mut path = Vec::with_capacity(levels);
                for _ in 0..levels {
                    path.push(root(&mut at)?);
                }
                paths.push(path);
            }
            let mut openings = Vec::with_capacity(shape.layers());
            for _ in 0..shape.layers() {
                let mut four = [E::ZERO; FOLD];
                for slot in four.iter_mut() {
                    *slot = element(&mut at)?;
                }
                openings.push(four);
            }
            queries.push(Query {
                row,
                trace_path,
                composition,
                composition_path,
                openings,
                paths,
            });
        }
        Ok((
            Proof {
                trace_root,
                composition_root,
                layer_roots,
                ood_values,
                queries,
            },
            Tail(tail),
        ))
    }
}

#[cfg(test)]
mod boundary_batching_tests {
    use super::*;
    use crate::air::{Boundary, BoundaryValue};

    #[test]
    fn batching_matches_the_direct_quotients_at_every_coset_point() {
        let shape = Shape::of_rows_log2(8).expect("a complete folding shape");
        let public = [F::from_u64_reduced(17), F::from_u64_reduced(3)];
        let extended: Vec<Vec<F>> = (0..2)
            .map(|column| {
                let coefficients: Vec<F> = (0..shape.rows())
                    .map(|i| F::from_u64_reduced((i * i + column * 11 + 1) as u64))
                    .collect();
                poly::evaluate_over_coset(&coefficients, shape.domain_log2(), poly::coset_shift())
                    .expect("the trace extends")
            })
            .collect();
        let generator = poly::root_of_unity(shape.rows_log2()).expect("the row generator");
        let points = domain_points(shape).expect("the extended domain");
        // Empty, sparse and dense boundaries; first/last live rows and both columns.
        // The trace need not satisfy them: these must be equal as rational
        // expressions even for a false statement, not only for an honest trace.
        let live = shape.live_rows();
        for stride in [0, live - 1, 1] {
            let mut description = Description {
                trace_width: 2,
                rows_log2: shape.rows_log2() as u8,
                periodic: vec![],
                constraints: vec![],
                boundaries: vec![],
            };
            if stride != 0 {
                for row in (0..live).step_by(stride) {
                    for column in 0..2 {
                        description.boundaries.push(Boundary {
                            row: row as u64,
                            column,
                            value: match row % 3 {
                                0 => BoundaryValue::Literal(7),
                                1 => BoundaryValue::Public(0),
                                _ => BoundaryValue::Word(0),
                            },
                        });
                    }
                }
                // Duplicate boundaries must add, not replace each other.
                description
                    .boundaries
                    .push(description.boundaries[0].clone());
            }
            let weights: Vec<E> = (0..description.boundaries.len())
                .map(|at| {
                    E::of(
                        F::from_u64_reduced(at as u64 + 1),
                        F::from_u64_reduced(at as u64 * 13 + 2),
                        F::from_u64_reduced(at as u64 * 3 + 5),
                    )
                })
                .collect();
            let batched = boundary_numerators(&description, &weights, &public, &extended, shape)
                .expect("the boundary samples extend");
            let divisors = Divisors::of(&description, generator, shape);
            for (at, point) in points.iter().enumerate() {
                let here: Vec<E> = extended
                    .iter()
                    .map(|column| E::from_base(column[at]))
                    .collect();
                let inverted = divisors
                    .at(E::from_base(*point), shape.rows())
                    .expect("off H");
                let direct = value_of_the_composition(
                    &description,
                    &weights,
                    &public,
                    &here,
                    &[],
                    &[],
                    &divisors,
                    &inverted,
                )
                .expect("the direct boundary sum");
                // The batched numerator is divided by what vanishes on every row, which the
                // boundaries are taken over; the constraints alone take the live rows.
                let over_every_row = vanishing(E::from_base(*point), shape.rows())
                    .inverse()
                    .expect("off H");
                assert_eq!(
                    batched[at].times(over_every_row),
                    direct,
                    "stride {stride}, point {at}"
                );
            }
        }
    }

    // What the free block and the randomizer are drawn from answers afresh every time, and every
    // element it yields stands in the field.
    #[test]
    fn the_free_block_and_the_randomizer_are_drawn_afresh() {
        let rows = random_elements(16).expect("the system answers");
        let again = random_elements(16).expect("the system answers");
        assert_ne!(rows, again);
        assert!(rows.iter().all(|value| value.as_u64() < crate::field::P));
    }
}
