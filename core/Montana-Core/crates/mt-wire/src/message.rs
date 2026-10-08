// The messages of the wire. Cells carry deliveries; these carry everything else that crosses
// between two machines. Each has one length or one length rule, each is refused in silence when
// malformed, and none names anybody.

use crate::{cell_bytes, erasure, WireError, LABEL_BYTES};
use mt_state::Layout;

// A point is of the width of a tag, and a right to collect is of the width of a hash.
pub const POINT_BYTES: usize = LABEL_BYTES;
mt_codec::constants! {
    COLLECTION_WIDTHS:
    pub const RIGHT_BYTES: usize = 32, writes "right                            32 B         collect_right for this window";
}

// Which message of this section the pieces of a link carry. The set names the vocabulary and its
// numbers; what a reader does with a byte outside it is end the link, because a machine that
// guessed would answer a stranger's bytes as something it is not — and two implementations guessing
// in two orders would answer differently on one message, which is the fork this whole layer exists
// against.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Kind {
    Deposit,
    Collect,
    CollectPublic,
    CollectAnswer,
    WakeInline,
    WakeHandle,
    HeadQuery,
    HeadAnswer,
    StateQuery,
    StateAnswer,
    SlotQuery,
    SlotAnswer,
}

impl Kind {
    pub fn of(byte: u8) -> Option<Self> {
        match byte {
            1 => Some(Self::Deposit),
            2 => Some(Self::Collect),
            3 => Some(Self::CollectPublic),
            4 => Some(Self::CollectAnswer),
            5 => Some(Self::WakeInline),
            6 => Some(Self::WakeHandle),
            7 => Some(Self::HeadQuery),
            8 => Some(Self::HeadAnswer),
            9 => Some(Self::StateQuery),
            10 => Some(Self::StateAnswer),
            11 => Some(Self::SlotQuery),
            12 => Some(Self::SlotAnswer),
            _ => None,
        }
    }

    pub fn byte(self) -> u8 {
        match self {
            Self::Deposit => 1,
            Self::Collect => 2,
            Self::CollectPublic => 3,
            Self::CollectAnswer => 4,
            Self::WakeInline => 5,
            Self::WakeHandle => 6,
            Self::HeadQuery => 7,
            Self::HeadAnswer => 8,
            Self::StateQuery => 9,
            Self::StateAnswer => 10,
            Self::SlotQuery => 11,
            Self::SlotAnswer => 12,
        }
    }

    // Every kind of the vocabulary, in the order the set writes them. What it is for is the test
    // that no two carry one number and that the reading and the writing of a kind are one map.
    pub const ALL: [Kind; 12] = [
        Kind::Deposit,
        Kind::Collect,
        Kind::CollectPublic,
        Kind::CollectAnswer,
        Kind::WakeInline,
        Kind::WakeHandle,
        Kind::HeadQuery,
        Kind::HeadAnswer,
        Kind::StateQuery,
        Kind::StateAnswer,
        Kind::SlotQuery,
        Kind::SlotAnswer,
    ];
}

fn width(expected: usize, found: usize) -> WireError {
    WireError::WrongLength { expected, found }
}

// A deposit places one cell at a point.
pub fn deposit_len() -> Result<usize, WireError> {
    Ok(POINT_BYTES + cell_bytes()?)
}

pub fn encode_deposit(point: &[u8; POINT_BYTES], cell: &[u8]) -> Result<Vec<u8>, WireError> {
    let expected = cell_bytes()?;
    if cell.len() != expected {
        return Err(width(expected, cell.len()));
    }
    let mut out = Vec::with_capacity(deposit_len()?);
    out.extend_from_slice(point);
    out.extend_from_slice(cell);
    Ok(out)
}

pub fn parse_deposit(bytes: &[u8]) -> Result<([u8; POINT_BYTES], Vec<u8>), WireError> {
    let expected = deposit_len()?;
    if bytes.len() != expected {
        return Err(width(expected, bytes.len()));
    }
    let mut point = [0u8; POINT_BYTES];
    point.copy_from_slice(&bytes[..POINT_BYTES]);
    Ok((point, bytes[POINT_BYTES..].to_vec()))
}

// A collection from a pipe presents the right of the current window; a collection from the point
// of a channel presents nothing, because the right there is public.
pub fn collect_len() -> usize {
    POINT_BYTES + RIGHT_BYTES
}

pub fn collect_public_len() -> usize {
    POINT_BYTES + 2
}

// A collection from the point of a channel presents no right, because the right there is public:
// what it presents is the point and the count of cells of it the asker already holds.
//
// **The reading of a point takes more than one answer.** Several objects stand at one point — a
// beacon and the attestations answering it stand at the round points of one round — while
// `collect_answer_max` is the cells of the largest single object, so one answer cannot carry a
// round. Without the index an asker reads the first object standing at a point and never the rest,
// its runner gathers nothing, and no window closes.
pub fn encode_collect_public(point: &[u8; POINT_BYTES], after: u16) -> Vec<u8> {
    let mut out = Vec::with_capacity(collect_public_len());
    out.extend_from_slice(point);
    out.extend_from_slice(&after.to_le_bytes());
    out
}

pub fn parse_collect_public(bytes: &[u8]) -> Result<([u8; POINT_BYTES], u16), WireError> {
    if bytes.len() != collect_public_len() {
        return Err(width(collect_public_len(), bytes.len()));
    }
    let mut point = [0u8; POINT_BYTES];
    point.copy_from_slice(&bytes[..POINT_BYTES]);
    let after = u16::from_le_bytes([bytes[POINT_BYTES], bytes[POINT_BYTES + 1]]);
    Ok((point, after))
}

pub fn parse_collect(bytes: &[u8]) -> Result<([u8; POINT_BYTES], [u8; RIGHT_BYTES]), WireError> {
    if bytes.len() != collect_len() {
        return Err(width(collect_len(), bytes.len()));
    }
    let mut point = [0u8; POINT_BYTES];
    point.copy_from_slice(&bytes[..POINT_BYTES]);
    let mut right = [0u8; RIGHT_BYTES];
    right.copy_from_slice(&bytes[POINT_BYTES..]);
    Ok((point, right))
}

pub fn encode_collect(point: &[u8; POINT_BYTES], right: &[u8; RIGHT_BYTES]) -> Vec<u8> {
    let mut out = Vec::with_capacity(collect_len());
    out.extend_from_slice(point);
    out.extend_from_slice(right);
    out
}

// The cells of the largest object that stands at a point. It is computed from the widths the set
// fixes and never written: a heavy attestation cut into blocks of a chunk, grouped by the code.
// The cells one object of a given width stands at a point as: the blocks it cuts into, grouped by
// the code, every group carrying its parity.
pub fn cells_for(object: usize) -> Result<usize, WireError> {
    let blocks = object.div_ceil(crate::chunk_bytes()?);
    let groups = blocks.div_ceil(erasure::data()?);
    Ok(groups * erasure::group()?)
}

// The width a body comes back at: the data blocks of its groups, before the length of the object
// truncates it. Two objects of two kinds standing at one point are told apart by it, since a reader
// takes back bodies and not kinds.
pub fn body_len(object: usize) -> Result<usize, WireError> {
    let groups = cells_for(object)? / erasure::group()?;
    Ok(groups * erasure::data()? * crate::chunk_bytes()?)
}

// The largest is taken over the objects the set names as standing at a point, so a length that
// moves moves this bound with it. The named wrong implementation: pinning the bound to the one
// object that happened to be largest — the confirmation once was, and a bound pinned to it
// refused a frame whole the day the confirmation shrank.
pub fn collect_answer_max() -> Result<usize, WireError> {
    let widths = [
        mt_state::layout::Proposal::expected_len(),
        mt_state::layout::Frame::expected_len(),
        mt_state::layout::Confirmation::expected_len(),
        mt_state::layout::FoldNode::expected_len(),
        mt_state::layout::Candidacy::expected_len(),
        mt_state::layout::Beacon::expected_len(),
        mt_state::layout::LightAttestation::expected_len(),
    ];
    let mut widest = 0usize;
    for width in widths {
        let cells = cells_for(width)?;
        if cells > widest {
            widest = cells;
        }
    }
    Ok(widest)
}

// What one point may hold. **A point of a round holds a round and the slots that round names.**
// The round's own part is what the machines admitted to the window may put there: each of them at
// most one beacon, since it runs at most one version of a chain, and one attestation for every
// version it sees, since it answers every valid version of a round and presents one round
// nullifier per beacon. The slots' part is the frames and the operations of the identity plane
// whose canonical slot names this round: their residues are derived and may coincide, so what
// bounds them is the window's own caps — `frames_per_window` frames and
// `max_openings_per_window` openings — and nothing finer is knowable at the door. The ceiling is
// the sum of the two parts; it reads the widths the Decree fixes and the count of machines the
// tree of the admitted carries, and names no constant of its own.
//
// The named wrong implementation, and the accident that hid it: a ceiling of the round's part
// alone stood for as long as one attestation outweighed one frame, and refused every frame whole
// the day the attestation shrank below it — the slots' part was always owed, and the sizes
// merely concealed the debt.
//
// **The square is the opening cohort's own shape and not a general cost.** Every admitted machine
// runs a version only where every one of them clears the draw, which is where a network begins and
// nowhere it stays: the retarget takes the threshold to where one machine in `committee_divisor`
// is drawn, and the versions of a round fall to a handful.
//
// It is not `collect_answer_max`: that is the bound of one **answer**, which is the cells of the
// largest single object, and a point held to it would refuse the first attestation answering a
// beacon.
pub fn point_ceiling(admitted: u64) -> Result<usize, WireError> {
    let beacon = cells_for(mt_state::layout::Beacon::expected_len())?;
    let answer = cells_for(mt_state::layout::Confirmation::expected_len())?;
    let held = usize::try_from(admitted).unwrap_or(usize::MAX).max(1);
    let of_round = beacon
        .saturating_add(answer.saturating_mul(held))
        .saturating_mul(held);
    let frames =
        mt_genesis::scalar("frames_per_window").ok_or(WireError::DecreeIncomplete)? as usize;
    let openings =
        mt_genesis::scalar("max_openings_per_window").ok_or(WireError::DecreeIncomplete)? as usize;
    let of_slots = cells_for(mt_state::layout::Frame::expected_len())?
        .saturating_mul(frames)
        .saturating_add(
            cells_for(mt_state::layout::Opening::expected_len())?.saturating_mul(openings),
        );
    Ok(of_round.saturating_add(of_slots))
}

// An answer of zero cells is the ordinary answer and is indistinguishable from any other.
pub fn encode_collect_answer(cells: &[Vec<u8>]) -> Result<Vec<u8>, WireError> {
    let bound = collect_answer_max()?;
    if cells.len() > bound {
        return Err(width(bound, cells.len()));
    }
    let one = cell_bytes()?;
    if cells.iter().any(|c| c.len() != one) {
        return Err(width(
            one,
            cells
                .iter()
                .map(Vec::len)
                .find(|l| *l != one)
                .unwrap_or(one),
        ));
    }
    let mut out = Vec::with_capacity(2 + cells.len() * one);
    out.extend_from_slice(&(cells.len() as u16).to_le_bytes());
    for cell in cells {
        out.extend_from_slice(cell);
    }
    Ok(out)
}

// An answer declaring more than the bound is refused before a cell of it is read.
pub fn parse_collect_answer(bytes: &[u8]) -> Result<Vec<Vec<u8>>, WireError> {
    if bytes.len() < 2 {
        return Err(width(2, bytes.len()));
    }
    let declared = usize::from(u16::from_le_bytes([bytes[0], bytes[1]]));
    let bound = collect_answer_max()?;
    if declared > bound {
        return Err(width(bound, declared));
    }
    let one = cell_bytes()?;
    let expected = 2 + declared * one;
    if bytes.len() != expected {
        return Err(width(expected, bytes.len()));
    }
    Ok((0..declared)
        .map(|index| bytes[2 + index * one..2 + (index + 1) * one].to_vec())
        .collect())
}

// The largest message this wire carries, derived from the widths the set fixes rather than pinned:
// an answer of `collect_answer_max` cells is the largest of them, and a proposal at its one length
// stands next. What it bounds is how many pieces a reader will hold for one message before it ends
// the link — a count above this is a far side asking a reader to hold what no message of this
// protocol holds.
pub fn largest_len() -> Result<usize, WireError> {
    let answer = 2 + collect_answer_max()? * cell_bytes()?;
    let held = [
        answer,
        head_answer_len(),
        deposit_len()?,
        collect_len(),
        collect_public_len(),
        wake_len(),
        head_query_len(),
        state_query_len(),
        slot_query_len(),
    ];
    Ok(held.into_iter().fold(0usize, usize::max))
}

// A wake carries a tag or a handle, and a window, and nothing else. The set names two layouts of
// this shape and they are of one width, because what parts them is what the sixteen bytes mean and
// never how they are written: a tag of a pipe, which the two correspondents derive, or a handle the
// holder drew beside that pipe, which resolves nowhere outside the machine that drew it. The two
// doors below say which is meant, so a caller cannot offer one where the other is read.
pub fn wake_len() -> usize {
    POINT_BYTES + 8
}

// The tag of the pipe the letter waits in.
pub fn encode_wake_inline(tag: &[u8; POINT_BYTES], window: u64) -> Vec<u8> {
    encode_wake(tag, window)
}

pub fn parse_wake_inline(bytes: &[u8]) -> Result<([u8; POINT_BYTES], u64), WireError> {
    parse_wake(bytes)
}

// An opaque value the holder drew beside that pipe, which names nothing anywhere else.
pub fn encode_wake_handle(handle: &[u8; POINT_BYTES], window: u64) -> Vec<u8> {
    encode_wake(handle, window)
}

pub fn parse_wake_handle(bytes: &[u8]) -> Result<([u8; POINT_BYTES], u64), WireError> {
    parse_wake(bytes)
}

pub fn encode_wake(handle: &[u8; POINT_BYTES], window: u64) -> Vec<u8> {
    let mut out = Vec::with_capacity(wake_len());
    out.extend_from_slice(handle);
    out.extend_from_slice(&window.to_le_bytes());
    out
}

pub fn parse_wake(bytes: &[u8]) -> Result<([u8; POINT_BYTES], u64), WireError> {
    if bytes.len() != wake_len() {
        return Err(width(wake_len(), bytes.len()));
    }
    let mut handle = [0u8; POINT_BYTES];
    handle.copy_from_slice(&bytes[..POINT_BYTES]);
    let mut window = [0u8; 8];
    window.copy_from_slice(&bytes[POINT_BYTES..]);
    Ok((handle, u64::from_le_bytes(window)))
}

// A head query names the network by the hash the asker computed itself, so an answerer of another
// network is told apart before a byte of its proposal is parsed.
pub fn head_query_len() -> usize {
    mt_codec::size::HASH
}

pub fn encode_head_query(genesis_state_hash: &[u8; mt_codec::size::HASH]) -> Vec<u8> {
    genesis_state_hash.to_vec()
}

pub fn parse_head_query(bytes: &[u8]) -> Result<[u8; mt_codec::size::HASH], WireError> {
    if bytes.len() != head_query_len() {
        return Err(width(head_query_len(), bytes.len()));
    }
    let mut held = [0u8; mt_codec::size::HASH];
    held.copy_from_slice(bytes);
    Ok(held)
}

// The newest proposal the answerer holds, and beside it the newest window whose proof it holds —
// the proofs may lag the head by the depth the Decree bounds, and a joining device steers by the
// proven height, not the head alone. One length for the whole answer: there is no shorter proposal
// and no longer one, so an answer of any other length is refused before a field of it is reached.
pub fn head_answer_len() -> usize {
    8 + <mt_state::layout::Proposal as mt_state::Layout>::expected_len()
}

pub fn encode_head_answer(proven: u64, proposal: &[u8]) -> Result<Vec<u8>, WireError> {
    if 8 + proposal.len() != head_answer_len() {
        return Err(width(head_answer_len(), 8 + proposal.len()));
    }
    let mut out = Vec::with_capacity(head_answer_len());
    out.extend_from_slice(&proven.to_le_bytes());
    out.extend_from_slice(proposal);
    Ok(out)
}

pub fn parse_head_answer(bytes: &[u8]) -> Result<(u64, Vec<u8>), WireError> {
    if bytes.len() != head_answer_len() {
        return Err(width(head_answer_len(), bytes.len()));
    }
    let mut proven = [0u8; 8];
    proven.copy_from_slice(&bytes[..8]);
    Ok((u64::from_le_bytes(proven), bytes[8..].to_vec()))
}

// The proof of a window is asked for by its height and answered with the object or with nothing,
// exactly as a point that holds nothing answers: an emptiness is an answer, never an error.
pub fn proof_query_len() -> usize {
    8
}

pub fn encode_proof_query(window: u64) -> Vec<u8> {
    window.to_le_bytes().to_vec()
}

pub fn parse_proof_query(bytes: &[u8]) -> Result<u64, WireError> {
    if bytes.len() != proof_query_len() {
        return Err(width(proof_query_len(), bytes.len()));
    }
    let mut held = [0u8; 8];
    held.copy_from_slice(bytes);
    Ok(u64::from_le_bytes(held))
}

pub fn proof_answer_len() -> usize {
    <mt_state::layout::WindowProof as mt_state::Layout>::expected_len()
}

pub fn encode_proof_answer(window_proof: Option<&[u8]>) -> Result<Vec<u8>, WireError> {
    match window_proof {
        None => Ok(Vec::new()),
        Some(bytes) if bytes.len() == proof_answer_len() => Ok(bytes.to_vec()),
        Some(bytes) => Err(width(proof_answer_len(), bytes.len())),
    }
}

pub fn parse_proof_answer(bytes: &[u8]) -> Result<Option<Vec<u8>>, WireError> {
    if bytes.is_empty() {
        return Ok(None);
    }
    if bytes.len() != proof_answer_len() {
        return Err(width(proof_answer_len(), bytes.len()));
    }
    Ok(Some(bytes.to_vec()))
}

// The roots a state query may ask against, in the order the set gives them.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum RootIndex {
    Notes,
    Nullifiers,
    Records,
    Machines,
    Operations,
}

impl RootIndex {
    pub fn of(byte: u8) -> Option<Self> {
        match byte {
            0 => Some(Self::Notes),
            1 => Some(Self::Nullifiers),
            2 => Some(Self::Records),
            3 => Some(Self::Machines),
            4 => Some(Self::Operations),
            _ => None,
        }
    }

    pub fn byte(self) -> u8 {
        match self {
            Self::Notes => 0,
            Self::Nullifiers => 1,
            Self::Records => 2,
            Self::Machines => 3,
            Self::Operations => 4,
        }
    }
}

pub fn state_query_len() -> usize {
    8 + 1 + 32
}

pub fn encode_state_query(window: u64, root: RootIndex, key: &[u8; 32]) -> Vec<u8> {
    let mut out = Vec::with_capacity(state_query_len());
    out.extend_from_slice(&window.to_le_bytes());
    out.push(root.byte());
    out.extend_from_slice(key);
    out
}

// A root index the set does not name is refused in silence, like every other malformed message.
pub fn parse_state_query(bytes: &[u8]) -> Result<(u64, RootIndex, [u8; 32]), WireError> {
    if bytes.len() != state_query_len() {
        return Err(width(state_query_len(), bytes.len()));
    }
    let mut window = [0u8; 8];
    window.copy_from_slice(&bytes[..8]);
    let root = RootIndex::of(bytes[8]).ok_or(WireError::Opening)?;
    let mut key = [0u8; 32];
    key.copy_from_slice(&bytes[9..]);
    Ok((u64::from_le_bytes(window), root, key))
}

// A slot query carries exactly one slot; a query carrying a set of slots is refused.
pub fn slot_query_len() -> usize {
    64
}

pub fn encode_slot_query(slot: &[u8; 32], reach_nullifier: &[u8; 32]) -> Vec<u8> {
    let mut out = Vec::with_capacity(slot_query_len());
    out.extend_from_slice(slot);
    out.extend_from_slice(reach_nullifier);
    out
}

pub fn parse_slot_query(bytes: &[u8]) -> Result<([u8; 32], [u8; 32]), WireError> {
    if bytes.len() != slot_query_len() {
        return Err(width(slot_query_len(), bytes.len()));
    }
    let mut slot = [0u8; 32];
    slot.copy_from_slice(&bytes[..32]);
    let mut reach = [0u8; 32];
    reach.copy_from_slice(&bytes[32..]);
    Ok((slot, reach))
}

// A proof of length zero is the ordinary answer for a leaf that does not exist.
pub fn encode_state_answer(proof: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(4 + proof.len());
    out.extend_from_slice(&(proof.len() as u32).to_le_bytes());
    out.extend_from_slice(proof);
    out
}

pub fn parse_state_answer(bytes: &[u8]) -> Result<Vec<u8>, WireError> {
    if bytes.len() < 4 {
        return Err(width(4, bytes.len()));
    }
    let declared = u32::from_le_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]) as usize;
    let expected = 4 + declared;
    if bytes.len() != expected {
        return Err(width(expected, bytes.len()));
    }
    Ok(bytes[4..].to_vec())
}

// A published length of zero is the ordinary answer for a slot that publishes nothing.
pub fn encode_slot_answer(published: &[u8]) -> Result<Vec<u8>, WireError> {
    if published.len() > usize::from(u16::MAX) {
        return Err(width(usize::from(u16::MAX), published.len()));
    }
    let mut out = Vec::with_capacity(2 + published.len());
    out.extend_from_slice(&(published.len() as u16).to_le_bytes());
    out.extend_from_slice(published);
    Ok(out)
}

pub fn parse_slot_answer(bytes: &[u8]) -> Result<Vec<u8>, WireError> {
    if bytes.len() < 2 {
        return Err(width(2, bytes.len()));
    }
    let declared = usize::from(u16::from_le_bytes([bytes[0], bytes[1]]));
    let expected = 2 + declared;
    if bytes.len() != expected {
        return Err(width(expected, bytes.len()));
    }
    Ok(bytes[2..].to_vec())
}

#[cfg(test)]
mod tests {
    use super::*;

    // **The lengths of the messages are not restated here.** The gate compares every one of them
    // against the set on every build, in both directions, so a literal beside them would be a
    // second place for one number — and this test held exactly that, and drifted the day the
    // public collection grew the index an asker names.
    //
    // What stands here is the one relation the gate does not read: the bound of one answer is the
    // cells of the largest single object that stands at a point, which is what the set says it is.
    #[test]
    fn the_bound_of_one_answer_is_the_cells_of_the_largest_object_at_a_point() {
        let bound = collect_answer_max().expect("the Decree names the widths");
        for width in [
            mt_state::layout::Proposal::expected_len(),
            mt_state::layout::Frame::expected_len(),
            mt_state::layout::Confirmation::expected_len(),
            mt_state::layout::FoldNode::expected_len(),
            mt_state::layout::Candidacy::expected_len(),
            mt_state::layout::Beacon::expected_len(),
            mt_state::layout::LightAttestation::expected_len(),
        ] {
            assert!(cells_for(width).expect("cells") <= bound);
        }
        // The named wrong implementation: the bound pinned to the confirmation, which was the
        // largest once — a frame is larger now, and a bound pinned there refuses it whole.
        assert!(
            bound > cells_for(mt_state::layout::Confirmation::expected_len()).expect("cells"),
            "the bound stands on the largest object, not on the one that used to be largest"
        );
        // And a round is more than one answer, which is why an asker names what it already holds.
        let round = point_ceiling(2).expect("the Decree names the widths");
        assert!(
            round > bound,
            "a round standing at a point would fit one answer, and the index would measure nothing"
        );
        // A point of a round holds the frames its slots name beside the round's own objects: the
        // ceiling admits a frame even where the admitted count is one, which is the door the
        // accident of sizes once held shut.
        let of_one = point_ceiling(1).expect("the Decree names the widths");
        assert!(of_one >= cells_for(mt_state::layout::Frame::expected_len()).expect("cells"));
    }

    #[test]
    fn every_kind_carries_one_number_and_reads_back_to_itself() {
        let mut seen: Vec<u8> = Kind::ALL.iter().map(|k| k.byte()).collect();
        assert_eq!(seen.len(), 12);
        for kind in Kind::ALL {
            assert_eq!(Kind::of(kind.byte()), Some(kind));
        }
        seen.sort_unstable();
        seen.dedup();
        assert_eq!(seen.len(), 12, "two kinds carry one number");
        assert_eq!(seen.first(), Some(&1), "the vocabulary opens at one");
        assert_eq!(seen.last(), Some(&12), "the vocabulary ends at twelve");
        // Zero is no kind, and neither is anything past the vocabulary: a piece naming one ends the
        // link rather than being read as something it is not.
        assert_eq!(Kind::of(0), None);
        assert_eq!(Kind::of(13), None);
        assert_eq!(Kind::of(255), None);
    }

    #[test]
    fn the_largest_message_of_this_wire_is_the_answer_of_a_collection() {
        let largest = largest_len().expect("named");
        assert_eq!(
            largest,
            2 + collect_answer_max().expect("named") * cell_bytes().expect("named")
        );
        // And every other message of this wire stands under it.
        assert!(largest > head_answer_len());
        assert!(largest > deposit_len().expect("named"));
    }

    #[test]
    fn a_message_of_another_length_is_refused_before_it_is_parsed() {
        let point = [0x11u8; POINT_BYTES];
        let cell = vec![0x22u8; cell_bytes().expect("named")];
        let deposit = encode_deposit(&point, &cell).expect("encodes");
        assert_eq!(deposit.len(), deposit_len().expect("named"));
        assert_eq!(parse_deposit(&deposit), Ok((point, cell)));
        assert!(parse_deposit(&deposit[..deposit.len() - 1]).is_err());
        assert!(parse_wake(&[0u8; 23]).is_err());
        assert!(parse_slot_query(&[0u8; 63]).is_err());
        assert!(parse_state_query(&[0u8; 40]).is_err());
    }

    #[test]
    fn a_root_the_set_does_not_name_is_refused() {
        let mut query = encode_state_query(1000, RootIndex::Machines, &[0x33; 32]);
        assert_eq!(
            parse_state_query(&query),
            Ok((1000, RootIndex::Machines, [0x33; 32]))
        );
        query[8] = 5;
        assert!(parse_state_query(&query).is_err());
    }

    #[test]
    fn an_answer_declaring_more_cells_than_the_bound_is_refused_before_one_is_read() {
        let bound = collect_answer_max().expect("named");
        let mut bytes = vec![0u8; 2];
        bytes[..2].copy_from_slice(&((bound + 1) as u16).to_le_bytes());
        assert_eq!(
            parse_collect_answer(&bytes),
            Err(WireError::WrongLength {
                expected: bound,
                found: bound + 1
            })
        );
        // And an answer of zero cells is ordinary.
        let empty = encode_collect_answer(&[]).expect("encodes");
        assert_eq!(empty.len(), 2);
        assert_eq!(parse_collect_answer(&empty), Ok(Vec::new()));
    }

    #[test]
    fn an_answer_of_nothing_is_the_ordinary_answer_of_both_kinds() {
        assert_eq!(
            parse_state_answer(&encode_state_answer(&[])),
            Ok(Vec::new())
        );
        assert_eq!(
            parse_slot_answer(&encode_slot_answer(&[]).expect("encodes")),
            Ok(Vec::new())
        );
        let proof = vec![7u8; 100];
        assert_eq!(parse_state_answer(&encode_state_answer(&proof)), Ok(proof));
    }

    #[test]
    fn both_kinds_of_collection_round_trip_and_refuse_another_length() {
        let point = [0x11u8; POINT_BYTES];
        let right = [0x22u8; RIGHT_BYTES];
        let sealed = encode_collect(&point, &right);
        assert_eq!(sealed.len(), collect_len());
        assert_eq!(parse_collect(&sealed), Ok((point, right)));
        assert!(parse_collect(&sealed[..sealed.len() - 1]).is_err());
        let public = encode_collect_public(&point, 7);
        assert_eq!(public.len(), collect_public_len());
        assert_eq!(parse_collect_public(&public), Ok((point, 7)));
        // A collection of the old width names no index and is refused before it is read: an asker
        // that named none would be answered with the first object of a point for ever.
        assert!(parse_collect_public(&public[..POINT_BYTES]).is_err());
        assert!(parse_collect_public(&sealed).is_err());
    }
}
