// How an object of consensus reaches the point it stands at, and how a reader takes it back.
//
// **A cell that stands at a point takes both its keys from that point.** A letter takes them of a
// secret two correspondents derive; an object of consensus takes them of the point, which every
// machine computes from the window, the chain, the round and the index without asking anybody. The
// cell therefore keeps the one shape every cell has — a label, a nonce, and bytes indistinguishable
// from noise — so an observer of the wire tells a beacon from a letter by nothing.
//
// **An object larger than a cell travels as a delivery.** It is cut into blocks of `chunk_bytes`,
// grouped by `erasure_group` with a quarter of each group parity, and every block rides one cell.
// Nothing here chooses those counts: they follow from the widths the Decree fixes.

use crate::{cell, erasure, WireError, LABEL_BYTES};
use mt_derive::delivery::{delivery_id, point_pipe_key, point_step_key};

// The cells an object stands at a point as. The identifier of the delivery is taken over the point
// and the body, so two objects at one point are two deliveries and a reader tells them apart
// without asking; each block carries the count of blocks, so a reader knows when it holds them all.
pub fn cells_of(
    point: &[u8; LABEL_BYTES],
    window: u64,
    object: &[u8],
) -> Result<Vec<Vec<u8>>, WireError> {
    let step = point_step_key(point, window);
    let pipe = point_pipe_key(point, window);
    let held = delivery_id(
        point,
        &mt_codec::hash_of_one(mt_codec::domain::MT_DELIVERY, object),
    );
    let blocks = erasure::cut(object)?;
    let coded = erasure::groups(&blocks)?;
    let total = coded.iter().map(Vec::len).sum::<usize>();
    let count = u16::try_from(total).map_err(|_| WireError::WrongLength {
        expected: usize::from(u16::MAX),
        found: total,
    })?;
    let mut out = Vec::with_capacity(total);
    let mut at: u16 = 0;
    for group in coded {
        for block in group {
            let delivery = cell::Delivery {
                delivery_id: held,
                block_index: at,
                block_count: count,
                chunk: block,
            };
            let inner = cell::seal_pipe(&pipe, &delivery)?;
            // The commitment a publication is for is the point itself: what stands at a point is
            // for whoever collects from it, and there is no machine to name.
            let mut target = [0u8; 32];
            target[..LABEL_BYTES].copy_from_slice(point);
            let routing = cell::Routing::new(target, inner)?;
            out.push(cell::seal_cell(&step, point, &routing)?.as_bytes().to_vec());
            at += 1;
        }
    }
    Ok(out)
}

// Which delivery one cell belongs to, and how many blocks that delivery declares. Both keys of a
// cell standing at a point come of the point, which every machine computes, so a holder may read
// this of what arrives without any right of its own.
//
// **It is what lets a point refuse a delivery whole rather than its tail.** A holder that took the
// first cells of a delivery and refused the rest would hold a body with a hole in it, and a body
// with a hole reads back as nothing: a point at its bound would stop answering with anything whole
// exactly when the round it carries matters most.
pub fn delivery_of(
    point: &[u8; LABEL_BYTES],
    window: u64,
    cell: &[u8],
) -> Option<([u8; mt_derive::delivery::POINT_BYTES], u16)> {
    let step = point_step_key(point, window);
    let pipe = point_pipe_key(point, window);
    let parsed = cell::Cell::parse(cell).ok()?;
    let routing = cell::open_cell(&step, &parsed).ok()?;
    let delivery = cell::open_pipe(&pipe, &routing.inner).ok()?;
    Some((delivery.delivery_id, delivery.block_count))
}

// One delivery arriving at a point: the identifier it names itself by, the count of blocks it
// declares, and the blocks of it that have come. Two objects at one point are two of these, and the
// identifier is what keeps the blocks of one out of the blocks of the other.
struct Arriving {
    id: [u8; mt_derive::delivery::POINT_BYTES],
    declared: usize,
    blocks: Vec<Option<Vec<u8>>>,
}

// Every object standing at a point, in the order the first cell of each arrived. What does not open
// under the keys of that point is not of this point and is passed over in silence; what opens is
// placed by the index it carries, under the delivery it names, and every group of the code is
// reconstructed from the cells of it that arrived.
//
// **A point holds as many objects as were put there, and a reader takes back all of them.** A
// beacon and the attestations answering it stand at the round points of one round, so a reader that
// took back the first delivery and stopped would read the beacon and never the answers to it — and
// on a point carrying one object that reader agrees with this one, which is why the vector below
// carries two.
//
// **A body is the data blocks of its groups in order, and never the cells in order.** A quarter of
// every group is parity, so a reader that concatenated the cells as they came would splice the
// parity of one group between the data of it and the data of the next. On a body small enough to
// stand in one group the two readings agree, which is exactly why the test below carries a body of
// several — a vector that agrees with a wrong implementation measures nothing.
pub fn objects_of(
    point: &[u8; LABEL_BYTES],
    window: u64,
    cells: &[Vec<u8>],
) -> Result<Vec<Vec<u8>>, WireError> {
    let step = point_step_key(point, window);
    let pipe = point_pipe_key(point, window);
    let width = erasure::group()?;
    // One entry per delivery seen, in the order each was first seen.
    let mut held: Vec<Arriving> = Vec::new();
    for bytes in cells {
        let Ok(parsed) = cell::Cell::parse(bytes) else {
            continue;
        };
        let Ok(routing) = cell::open_cell(&step, &parsed) else {
            continue;
        };
        let Ok(delivery) = cell::open_pipe(&pipe, &routing.inner) else {
            continue;
        };
        let declared = usize::from(delivery.block_count);
        if declared == 0 || declared % width != 0 {
            continue;
        }
        let at = match held
            .iter()
            .position(|one| one.id == delivery.delivery_id && one.declared == declared)
        {
            Some(at) => at,
            None => {
                held.push(Arriving {
                    id: delivery.delivery_id,
                    declared,
                    blocks: vec![None; declared],
                });
                held.len() - 1
            }
        };
        let index = usize::from(delivery.block_index);
        if index >= declared || held[at].blocks[index].is_some() {
            continue;
        }
        held[at].blocks[index] = Some(delivery.chunk.clone());
    }
    let mut out = Vec::with_capacity(held.len());
    for Arriving { blocks, .. } in held {
        let mut body = Vec::new();
        let mut whole = true;
        for group in blocks.chunks(width) {
            let present: Vec<(usize, Vec<u8>)> = group
                .iter()
                .enumerate()
                .filter_map(|(at, block)| block.clone().map(|chunk| (at, chunk)))
                .collect();
            // A group short of what the code needs is a delivery that did not arrive, and a body
            // with a hole in it is not a shorter body: it is left out rather than answered short.
            let Ok(data) = erasure::reconstruct(&present) else {
                whole = false;
                break;
            };
            for block in data {
                body.extend_from_slice(&block);
            }
        }
        if whole {
            out.push(body);
        }
    }
    Ok(out)
}

// The one object a reader expects at a point, taken back at the width it expects. It is the walk
// above and no second one: a point carrying several answers with the first that is whole and long
// enough, and a caller that knows the width of what it seeks is told nothing of the rest.
pub fn object_of(
    point: &[u8; LABEL_BYTES],
    window: u64,
    cells: &[Vec<u8>],
    length: usize,
) -> Result<Option<Vec<u8>>, WireError> {
    for mut body in objects_of(point, window, cells)? {
        if body.len() >= length {
            body.truncate(length);
            return Ok(Some(body));
        }
    }
    Ok(None)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_object_of_consensus_stands_at_a_point_and_comes_back_whole() {
        let point = mt_derive::delivery::round_point(1_000, 0, 7, 0);
        let window = 1_000u64;
        // A body larger than a cell, so it travels as a delivery of several blocks.
        let object: Vec<u8> = (0..6_189usize).map(|i| (i % 251) as u8).collect();
        let cells = cells_of(&point, window, &object).expect("an object cuts into cells");
        let width = crate::cell_bytes().expect("the Decree names the width of a cell");
        assert!(cells.len() > 1, "an object of this size is several cells");
        for one in &cells {
            assert_eq!(one.len(), width, "a cell of a publication is a cell");
        }
        let back = object_of(&point, window, &cells, object.len())
            .expect("the cells open")
            .expect("the delivery is whole");
        assert_eq!(back, object, "what came back is not what stood there");
    }

    // The named wrong implementation this refuses: a reader taking the keys of another point, or
    // of the same point in another window. The keys of a public delivery are derived from what
    // carries the right to read, so neither opens — which is what keeps two deliveries at two
    // points from being one, and a point of a past window from answering in this one.
    #[test]
    fn cells_of_one_point_do_not_open_under_another() {
        let point = mt_derive::delivery::round_point(1_000, 0, 7, 0);
        let other = mt_derive::delivery::round_point(1_000, 0, 7, 1);
        let window = 1_000u64;
        let object = vec![0x5Au8; 2_000];
        let cells = cells_of(&point, window, &object).expect("cuts");
        assert_eq!(
            object_of(&other, window, &cells, object.len()).expect("opens nothing"),
            None
        );
        assert_eq!(
            object_of(&point, window + 1, &cells, object.len()).expect("opens nothing"),
            None
        );
    }

    // The named wrong implementation this refuses: a reader that concatenates the cells in the
    // order they came. A quarter of every group is parity, so such a reader splices the parity of
    // one group between the data of it and the data of the next — and on a body standing in one
    // group the two readings agree, which is why this body spans several.
    #[test]
    fn a_body_of_several_groups_comes_back_whole_and_the_parity_is_not_spliced_into_it() {
        let point = mt_derive::delivery::window_point(1_000, 0);
        let chunk = crate::chunk_bytes().expect("the Decree names the width of a block");
        let data = erasure::data().expect("the Decree names the data of a group");
        // Three groups' worth and a little over, so the last group is filled and the body is not a
        // whole number of blocks either.
        let object: Vec<u8> = (0..chunk * data * 3 + chunk / 2)
            .map(|i| (i % 251) as u8)
            .collect();
        let cells = cells_of(&point, 1_000, &object).expect("cuts");
        assert!(
            cells.len() > erasure::group().expect("named"),
            "a body of one group would not tell the two readings apart"
        );
        let back = object_of(&point, 1_000, &cells, object.len())
            .expect("the cells open")
            .expect("the delivery is whole");
        assert_eq!(back, object, "what came back is not what stood there");
    }

    // Two objects stand at one point and both come back. This is the shape of a round: a beacon
    // and the attestations answering it stand at the round points of one round, so a point carries
    // several deliveries and a reader takes back all of them.
    //
    // The named wrong implementation this refuses: a reader that takes the first delivery it opens
    // and stops. Such a reader agrees with this one on every point carrying a single object — which
    // is every vector above — and on a round it would read the beacon and never one answer to it,
    // so a runner would gather nothing and no window would ever close.
    #[test]
    fn two_objects_stand_at_one_point_and_a_reader_takes_back_both() {
        let point = mt_derive::delivery::round_point(1_000, 0, 7, 0);
        let window = 1_000u64;
        let beacon: Vec<u8> = (0..6_189usize).map(|i| (i % 251) as u8).collect();
        // Another object of another width, as an attestation is to a beacon.
        let answer: Vec<u8> = (0..20_000usize).map(|i| (i % 241) as u8).collect();
        let mut standing = cells_of(&point, window, &beacon).expect("a beacon cuts");
        standing.extend(cells_of(&point, window, &answer).expect("an answer cuts"));

        let taken = objects_of(&point, window, &standing).expect("the cells open");
        assert_eq!(
            taken.len(),
            2,
            "a point carrying two deliveries answered with fewer"
        );
        // Each comes back whole at its own width; the bodies are padded to whole blocks, so what a
        // reader compares is the object inside the body it asked the width of.
        let held: Vec<Vec<u8>> = taken
            .iter()
            .map(|body| body[..body.len().min(answer.len().max(beacon.len()))].to_vec())
            .collect();
        assert!(
            held.iter().any(|body| body.starts_with(&beacon)),
            "the beacon did not come back from a point that also carried an answer"
        );
        assert!(
            held.iter().any(|body| body.starts_with(&answer)),
            "the answer did not come back from a point that also carried a beacon"
        );

        // And the order of arrival is not the order of publication: cells interleave on a wire, and
        // a reader that placed blocks by arrival rather than by the delivery each names would mix
        // one body into the other.
        let mut mixed = Vec::new();
        let cut = cells_of(&point, window, &beacon).expect("cuts");
        let other = cells_of(&point, window, &answer).expect("cuts");
        let mut of_beacon = cut.into_iter();
        let mut of_answer = other.into_iter();
        loop {
            match (of_beacon.next(), of_answer.next()) {
                (None, None) => break,
                (one, two) => {
                    mixed.extend(one);
                    mixed.extend(two);
                }
            }
        }
        let interleaved = objects_of(&point, window, &mixed).expect("the cells open");
        assert_eq!(
            interleaved.len(),
            2,
            "interleaved deliveries did not both come back"
        );
        assert!(
            interleaved.iter().any(|body| body.starts_with(&beacon))
                && interleaved.iter().any(|body| body.starts_with(&answer)),
            "interleaving two deliveries mixed one body into the other"
        );
    }

    // What the parity is for: a group short of cells still answers, up to the count the code
    // carries. Past it nothing comes back — a body with a hole in it is not a shorter body.
    #[test]
    fn a_group_missing_up_to_its_parity_still_answers_and_past_it_answers_nothing() {
        let point = mt_derive::delivery::window_point(1_000, 0);
        let chunk = crate::chunk_bytes().expect("named");
        let data = erasure::data().expect("named");
        let parity = erasure::parity_count().expect("named");
        let object: Vec<u8> = (0..chunk * data * 2).map(|i| (i % 251) as u8).collect();
        let cells = cells_of(&point, 1_000, &object).expect("cuts");

        // The first group loses exactly its parity's worth and is reconstructed.
        let mut short = cells.clone();
        for _ in 0..parity {
            short.remove(0);
        }
        assert_eq!(
            object_of(&point, 1_000, &short, object.len())
                .expect("the cells open")
                .expect("the code carries the loss"),
            object
        );

        // One more, and the group is past what the code carries.
        let mut past = short;
        past.remove(0);
        assert_eq!(
            object_of(&point, 1_000, &past, object.len()).expect("opens what it holds"),
            None
        );
    }
}
