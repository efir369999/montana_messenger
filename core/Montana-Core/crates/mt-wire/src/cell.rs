// The cell, and the two seals it carries. Its length is `cell_bytes` whatever it holds.
//
// The outer seal is one step wide: every hop opens it, rewrites the one slot its own label
// selects, and seals again under the key of the next step with a fresh nonce, so no two points on
// a path carry one byte in common. The inner seal is one pipe wide and no hop holds its key.

use crate::{
    cell_bytes, chunk_bytes, inner_bytes, inner_plaintext_bytes, outer_plaintext_bytes, path_max,
    WireError, LABEL_BYTES, SEAL_BYTES,
};
use mt_codec::size;
use mt_suite::aead::{self, SealingKey};
use zeroize::{Zeroize, Zeroizing};

// The delivery layer: what a delivery needs of itself, where only the two correspondents read it.
#[derive(Clone, PartialEq, Eq)]
pub struct Delivery {
    pub delivery_id: [u8; SEAL_BYTES],
    pub block_index: u16,
    pub block_count: u16,
    pub chunk: Vec<u8>,
}

// What these two hold is somebody's letter, so what they show of themselves is a fixed string. A
// derived Debug would print the letter into whatever a test, a log or a panic message goes to,
// which is the one place a letter must never reach.
impl core::fmt::Debug for Delivery {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        f.write_str("Delivery(<wiped on drop, never shown>)")
    }
}

impl core::fmt::Debug for Routing {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        f.write_str("Routing(<the pipe layer is nobody's to read>)")
    }
}

// What a delivery carries is the letter itself: it is wiped when it is dropped rather than left in
// memory the allocator hands to the next thing that asks.
impl Drop for Delivery {
    fn drop(&mut self) {
        self.chunk.zeroize();
        self.delivery_id.zeroize();
    }
}

impl Delivery {
    fn encode(&self) -> Result<Zeroizing<Vec<u8>>, WireError> {
        let width = chunk_bytes()?;
        if self.chunk.len() != width {
            return Err(WireError::WrongLength {
                expected: width,
                found: self.chunk.len(),
            });
        }
        let mut out = Zeroizing::new(Vec::with_capacity(inner_plaintext_bytes()?));
        out.extend_from_slice(&self.delivery_id);
        out.extend_from_slice(&self.block_index.to_le_bytes());
        out.extend_from_slice(&self.block_count.to_le_bytes());
        out.extend_from_slice(&self.chunk);
        Ok(out)
    }

    fn decode(bytes: &[u8]) -> Result<Self, WireError> {
        let width = inner_plaintext_bytes()?;
        if bytes.len() != width {
            return Err(WireError::WrongLength {
                expected: width,
                found: bytes.len(),
            });
        }
        let mut delivery_id = [0u8; SEAL_BYTES];
        delivery_id.copy_from_slice(&bytes[..SEAL_BYTES]);
        let at = SEAL_BYTES;
        let block_index = u16::from_le_bytes([bytes[at], bytes[at + 1]]);
        let block_count = u16::from_le_bytes([bytes[at + 2], bytes[at + 3]]);
        Ok(Self {
            delivery_id,
            block_index,
            block_count,
            chunk: bytes[at + 4..].to_vec(),
        })
    }
}

// The pipe layer as it stands inside a cell: a nonce drawn afresh and the sealed delivery.
// The door a machine seals a pipe layer with: the nonce is drawn here and by nobody else.
pub fn seal_pipe(pipe_key: &[u8; 32], delivery: &Delivery) -> Result<Vec<u8>, WireError> {
    seal_pipe_with_nonce(pipe_key, &crate::draw::nonce()?, delivery)
}

// The same, with the nonce stated. It exists for the frozen vectors of the set, which fix one, and
// a machine that called it would be choosing a value the set requires to be drawn.
pub fn seal_pipe_with_nonce(
    pipe_key: &[u8; 32],
    nonce: &[u8; size::AEAD_NONCE],
    delivery: &Delivery,
) -> Result<Vec<u8>, WireError> {
    let key = SealingKey::new(*pipe_key);
    let sealed =
        aead::seal(&key, nonce, &[], &delivery.encode()?).map_err(|_| WireError::Sealing)?;
    let mut out = Vec::with_capacity(inner_bytes()?);
    out.extend_from_slice(nonce);
    out.extend_from_slice(&sealed);
    Ok(out)
}

pub fn open_pipe(pipe_key: &[u8; 32], inner: &[u8]) -> Result<Delivery, WireError> {
    let width = inner_bytes()?;
    if inner.len() != width {
        return Err(WireError::WrongLength {
            expected: width,
            found: inner.len(),
        });
    }
    let mut nonce = [0u8; size::AEAD_NONCE];
    nonce.copy_from_slice(&inner[..size::AEAD_NONCE]);
    let key = SealingKey::new(*pipe_key);
    // What comes out of the seal is the letter itself; it is wiped when this frame ends, and what
    // the caller receives wipes itself on drop.
    let plain = Zeroizing::new(
        aead::open(&key, &nonce, &[], &inner[size::AEAD_NONCE..])
            .map_err(|_| WireError::Opening)?,
    );
    Delivery::decode(&plain)
}

// The routing layer: the commitment of the machine this cell is for, the array of seals, and the
// pipe layer no hop opens.
#[derive(Clone, PartialEq, Eq)]
pub struct Routing {
    pub target_commit: [u8; 32],
    pub seals: Vec<[u8; SEAL_BYTES]>,
    pub inner: Vec<u8>,
}

// The pipe layer a routing layer carries is somebody's letter, sealed; what a hop holds of it in
// the clear is nothing, and what this crate holds of the plaintext beside it is wiped on drop.
impl Drop for Routing {
    fn drop(&mut self) {
        self.inner.zeroize();
    }
}

impl Routing {
    // The one door for a routing layer a machine builds: the array of seals is drawn, full, so the
    // count of steps a cell has crossed is carried nowhere. A caller that filled it itself would be
    // free to fill it with zeros, and zeros are the count of steps, published.
    pub fn new(target_commit: [u8; 32], inner: Vec<u8>) -> Result<Self, WireError> {
        Ok(Self {
            target_commit,
            seals: crate::draw::seals()?,
            inner,
        })
    }

    fn encode(&self) -> Result<Zeroizing<Vec<u8>>, WireError> {
        let slots = path_max()?;
        if self.seals.len() != slots {
            return Err(WireError::WrongLength {
                expected: slots,
                found: self.seals.len(),
            });
        }
        let inner_width = inner_bytes()?;
        if self.inner.len() != inner_width {
            return Err(WireError::WrongLength {
                expected: inner_width,
                found: self.inner.len(),
            });
        }
        let mut out = Zeroizing::new(Vec::with_capacity(outer_plaintext_bytes()?));
        out.extend_from_slice(&self.target_commit);
        for seal in &self.seals {
            out.extend_from_slice(seal);
        }
        out.extend_from_slice(&self.inner);
        Ok(out)
    }

    fn decode(bytes: &[u8]) -> Result<Self, WireError> {
        let width = outer_plaintext_bytes()?;
        if bytes.len() != width {
            return Err(WireError::WrongLength {
                expected: width,
                found: bytes.len(),
            });
        }
        let slots = path_max()?;
        let mut target_commit = [0u8; 32];
        target_commit.copy_from_slice(&bytes[..32]);
        let mut seals = Vec::with_capacity(slots);
        for slot in 0..slots {
            let at = 32 + slot * SEAL_BYTES;
            let mut seal = [0u8; SEAL_BYTES];
            seal.copy_from_slice(&bytes[at..at + SEAL_BYTES]);
            seals.push(seal);
        }
        Ok(Self {
            target_commit,
            seals,
            inner: bytes[32 + slots * SEAL_BYTES..].to_vec(),
        })
    }
}

// A cell as it stands on the wire. Its one door compares the length, so nothing downstream reads a
// field out of something that is not a cell.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct Cell(Vec<u8>);

impl Cell {
    pub fn parse(bytes: &[u8]) -> Result<Self, WireError> {
        let width = cell_bytes()?;
        if bytes.len() != width {
            return Err(WireError::WrongLength {
                expected: width,
                found: bytes.len(),
            });
        }
        Ok(Self(bytes.to_vec()))
    }

    pub fn as_bytes(&self) -> &[u8] {
        &self.0
    }

    pub fn step_label(&self) -> [u8; LABEL_BYTES] {
        let mut label = [0u8; LABEL_BYTES];
        label.copy_from_slice(&self.0[..LABEL_BYTES]);
        label
    }
}

// The door a machine seals a cell with: the nonce is drawn here and by nobody else.
pub fn seal_cell(
    step_key: &[u8; 32],
    step_label: &[u8; LABEL_BYTES],
    routing: &Routing,
) -> Result<Cell, WireError> {
    seal_cell_with_nonce(step_key, step_label, &crate::draw::nonce()?, routing)
}

// The same, with the nonce stated, for the frozen vectors of the set and for nothing else.
pub fn seal_cell_with_nonce(
    step_key: &[u8; 32],
    step_label: &[u8; LABEL_BYTES],
    nonce: &[u8; size::AEAD_NONCE],
    routing: &Routing,
) -> Result<Cell, WireError> {
    let key = SealingKey::new(*step_key);
    let sealed =
        aead::seal(&key, nonce, step_label, &routing.encode()?).map_err(|_| WireError::Sealing)?;
    let mut out = Vec::with_capacity(cell_bytes()?);
    out.extend_from_slice(step_label);
    out.extend_from_slice(nonce);
    out.extend_from_slice(&sealed);
    Cell::parse(&out)
}

pub fn open_cell(step_key: &[u8; 32], cell: &Cell) -> Result<Routing, WireError> {
    let label = cell.step_label();
    let mut nonce = [0u8; size::AEAD_NONCE];
    nonce.copy_from_slice(&cell.0[LABEL_BYTES..LABEL_BYTES + size::AEAD_NONCE]);
    let key = SealingKey::new(*step_key);
    let plain = Zeroizing::new(
        aead::open(
            &key,
            &nonce,
            &label,
            &cell.0[LABEL_BYTES + size::AEAD_NONCE..],
        )
        .map_err(|_| WireError::Opening)?,
    );
    Routing::decode(&plain)
}

// One step of a path: the hop opens what it was handed, writes its own seal at the slot that seal
// selects, rewrites nothing else, and seals again under the key of the step it is handing to. The
// commitment of the machine the cell is for crosses unchanged, which is what lets the next hop
// forward toward it, and the pipe layer crosses unread — which is also what the seal stands on, so
// one owner leaves one mark however many hops of this path it holds.
pub fn carry(
    step_key_in: &[u8; 32],
    cell: &Cell,
    owner_secret: &[u8; 32],
    step_key_out: &[u8; 32],
    step_label_out: &[u8; LABEL_BYTES],
) -> Result<Cell, WireError> {
    // The nonce of the next step is drawn here and by nobody else: a hop that took one from its
    // caller could be handed the same one twice, and two cells sealed under one key and one nonce
    // are two cells an observer reads.
    let nonce_out = crate::draw::nonce()?;
    let mut routing = open_cell(step_key_in, cell)?;
    // The seal stands on the path and the slot stands on the seal: one owner on two hops of one
    // delivery leaves one mark at one place, which is the whole of what a count of owners reads.
    let path = mt_derive::tag::path_id(&routing.inner);
    let seal = mt_derive::tag::relay_seal(owner_secret, &path);
    let slot = mt_derive::tag::seal_slot(&seal).ok_or(WireError::DecreeIncomplete)?;
    routing.seals[slot as usize] = seal;
    seal_cell_with_nonce(step_key_out, step_label_out, &nonce_out, &routing)
}
