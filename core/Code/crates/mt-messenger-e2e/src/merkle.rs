//! Stage 2 (second front) — archive integrity anchor (Merkle root over HistoryBlocks).
//! leaf = SHA-256("mt-msg-leaf" ‖ 0x00 ‖ H(HistoryBlock)); node = SHA-256("mt-msg-node" ‖ 0x00 ‖ left ‖ right).
//! ArchiveRoot: N=0 → not anchored (None); N=1 → leaf_0 (no node); N≥2 → tree, odd level duplicates the last node.
//! Canonical leaf order is (writer_tag, block_seq) — established by the caller (reconcile, Stage 4); this module
//! folds an already-ordered leaf sequence, byte-exact and independent of receive order.
//! app_id = SHA-256("mt-app" ‖ 0x00 ‖ "montana-messenger").

use mt_codec::domain::{APP, MSG_MSG_LEAF, MSG_MSG_NODE};
use sha2::{Digest, Sha256};

pub const APP_NAME: &[u8] = b"montana-messenger";

/// leaf = SHA-256("mt-msg-leaf" ‖ 0x00 ‖ H(HistoryBlock)). Input is H(HistoryBlock) = SHA-256(open block).
pub fn leaf(block_hash: &[u8; 32]) -> [u8; 32] {
    let mut h = Sha256::new();
    h.update(MSG_MSG_LEAF);
    h.update([0x00]);
    h.update(block_hash);
    h.finalize().into()
}

/// node = SHA-256("mt-msg-node" ‖ 0x00 ‖ left ‖ right).
pub fn node(left: &[u8; 32], right: &[u8; 32]) -> [u8; 32] {
    let mut h = Sha256::new();
    h.update(MSG_MSG_NODE);
    h.update([0x00]);
    h.update(left);
    h.update(right);
    h.finalize().into()
}

/// Fold an ordered leaf sequence into the Merkle root. N=0 → None; N=1 → leaves[0]; N≥2 → binary tree,
/// odd level duplicates the last node before pairing (CVE-2012-2459 class: rearranges/duplicates only the
/// holder's own leaves, no foreign-content injection — low severity for a personal archive, spec §114).
pub fn merkle_root(leaves: &[[u8; 32]]) -> Option<[u8; 32]> {
    if leaves.is_empty() {
        return None;
    }
    if leaves.len() == 1 {
        return Some(leaves[0]);
    }
    let mut level: Vec<[u8; 32]> = leaves.to_vec();
    while level.len() > 1 {
        let mut next = Vec::with_capacity((level.len() + 1) / 2);
        let mut i = 0;
        while i < level.len() {
            let l = level[i];
            let r = if i + 1 < level.len() {
                level[i + 1]
            } else {
                level[i] // odd → duplicate the last node
            };
            next.push(node(&l, &r));
            i += 2;
        }
        level = next;
    }
    Some(level[0])
}

/// ArchiveRoot over HistoryBlock hashes in canonical (writer_tag, block_seq) order.
/// Maps each H(HistoryBlock) to its domain-separated leaf, then folds. None when N=0 (archive not anchored).
pub fn archive_root(block_hashes_ordered: &[[u8; 32]]) -> Option<[u8; 32]> {
    if block_hashes_ordered.is_empty() {
        return None;
    }
    let leaves: Vec<[u8; 32]> = block_hashes_ordered.iter().map(leaf).collect();
    merkle_root(&leaves)
}

/// app_id = SHA-256("mt-app" ‖ 0x00 ‖ "montana-messenger"). Binds the Anchor to this application.
pub fn app_id() -> [u8; 32] {
    let mut h = Sha256::new();
    h.update(APP);
    h.update([0x00]);
    h.update(APP_NAME);
    h.finalize().into()
}

/// Stage 7 — MerklePath for partial verification: a recovered thread (Stage 6) is checked against the
/// sub-tree of its leaves, not the whole root. Layout: leaf_index u64 LE ‖ path_len 1 ‖ siblings[32×len]
/// (bottom-up). Sibling side is derived from leaf_index (even → sibling right, odd → sibling left); an odd
/// level duplicates the last node (identical to `archive_root`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MerklePath {
    pub leaf_index: u64,
    pub siblings: Vec<[u8; 32]>,
}

pub fn encode_path(p: &MerklePath) -> Option<Vec<u8>> {
    if p.siblings.len() > 255 {
        return None;
    }
    let mut o = Vec::with_capacity(9 + 32 * p.siblings.len());
    o.extend_from_slice(&p.leaf_index.to_le_bytes());
    o.push(p.siblings.len() as u8);
    for s in &p.siblings {
        o.extend_from_slice(s);
    }
    Some(o)
}

pub fn decode_path(buf: &[u8]) -> Option<MerklePath> {
    if buf.len() < 9 {
        return None;
    }
    let leaf_index = u64::from_le_bytes(buf[0..8].try_into().ok()?);
    let path_len = buf[8] as usize;
    if buf.len() != 9 + 32 * path_len {
        return None;
    }
    let mut siblings = Vec::with_capacity(path_len);
    for i in 0..path_len {
        let off = 9 + 32 * i;
        let mut s = [0u8; 32];
        s.copy_from_slice(&buf[off..off + 32]);
        siblings.push(s);
    }
    Some(MerklePath {
        leaf_index,
        siblings,
    })
}

/// Fold a leaf value with its siblings bottom-up: even index → node(cur, sib), odd → node(sib, cur).
fn fold_path(leaf: &[u8; 32], leaf_index: u64, siblings: &[[u8; 32]]) -> [u8; 32] {
    let mut cur = *leaf;
    let mut idx = leaf_index;
    for sib in siblings {
        cur = if idx & 1 == 0 {
            node(&cur, sib)
        } else {
            node(sib, &cur)
        };
        idx >>= 1;
    }
    cur
}

/// Verify a block against an anchor ArchiveRoot via its MerklePath: recompute the leaf from H(block),
/// fold, compare to root. A single-leaf archive (N=1, empty path) verifies leaf == root.
pub fn verify_path(block_hash: &[u8; 32], path: &MerklePath, root: &[u8; 32]) -> bool {
    &fold_path(&leaf(block_hash), path.leaf_index, &path.siblings) == root
}

/// Build the MerklePath for the block at `index` in the ordered set (same canonical order and odd-dup
/// rule as `archive_root`). None if index is out of range.
pub fn merkle_path(block_hashes_ordered: &[[u8; 32]], index: usize) -> Option<MerklePath> {
    let n = block_hashes_ordered.len();
    if index >= n {
        return None;
    }
    let mut level: Vec<[u8; 32]> = block_hashes_ordered.iter().map(leaf).collect();
    let mut idx = index;
    let mut siblings = Vec::new();
    while level.len() > 1 {
        let sib_idx = idx ^ 1;
        let sib = if sib_idx < level.len() {
            level[sib_idx]
        } else {
            level[idx] // odd level → last node duplicated
        };
        siblings.push(sib);
        let mut next = Vec::with_capacity((level.len() + 1) / 2);
        let mut i = 0;
        while i < level.len() {
            let l = level[i];
            let r = if i + 1 < level.len() {
                level[i + 1]
            } else {
                level[i]
            };
            next.push(node(&l, &r));
            i += 2;
        }
        level = next;
        idx >>= 1;
    }
    Some(MerklePath {
        leaf_index: index as u64,
        siblings,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hx(b: &[u8; 32]) -> String {
        hex::encode(b)
    }

    #[test]
    fn archive_root_kat() {
        // spec §120: leaf inputs aa×32 / bb×32 / cc×32 stand in for H(HistoryBlock).
        let aa = [0xaau8; 32];
        let bb = [0xbbu8; 32];
        let cc = [0xccu8; 32];

        assert_eq!(
            hx(&leaf(&aa)),
            "caa5110f7b25464a98c345857a247d0571bfed1820bc3678019338c3aa73092b"
        );
        assert_eq!(
            hx(&leaf(&bb)),
            "0af2793979a7f7bc99f56bf7af92be33648b16f722cfc42ec0b77bdb994b3564"
        );

        // N=1 → ArchiveRoot = leaf_0 (no node).
        assert_eq!(
            archive_root(&[aa]).map(|r| hx(&r)).as_deref(),
            Some("caa5110f7b25464a98c345857a247d0571bfed1820bc3678019338c3aa73092b")
        );
        // N=2 → node(leaf_0, leaf_1).
        assert_eq!(
            archive_root(&[aa, bb]).map(|r| hx(&r)).as_deref(),
            Some("019f464a61add3d9e9a8fe1d0777832ffcd3240798906304c45cad3b45a0b922")
        );
        // N=3 → odd level duplicates the last (cc) before pairing.
        assert_eq!(
            archive_root(&[aa, bb, cc]).map(|r| hx(&r)).as_deref(),
            Some("3e718f8a5cca3dcf7ac1f5309d125b66e34097e4fe8444e3e831fa690ed62ff0")
        );
    }

    #[test]
    fn archive_root_empty_not_anchored() {
        assert_eq!(archive_root(&[]), None);
    }

    #[test]
    fn app_id_kat() {
        assert_eq!(
            hx(&app_id()),
            "e1ed65fb90690467a6c2c84aec709930efb7ba9c9ba27c75631013c69f3fd2f5"
        );
    }

    #[test]
    fn order_matters_root_deterministic() {
        // ArchiveRoot depends on leaf order (canonical order is the caller's responsibility).
        let aa = [0xaau8; 32];
        let bb = [0xbbu8; 32];
        assert_ne!(archive_root(&[aa, bb]), archive_root(&[bb, aa]));
        // but identical input → identical root (determinism)
        assert_eq!(archive_root(&[aa, bb]), archive_root(&[aa, bb]));
    }

    #[test]
    fn merkle_path_kat() {
        // spec §274: N=2 tree (aa, bb). Path of leaf 0 = {index=0, siblings=[leaf_1]}; fold == root.
        let aa = [0xaau8; 32];
        let bb = [0xbbu8; 32];
        let root = archive_root(&[aa, bb]).unwrap();
        let path = merkle_path(&[aa, bb], 0).unwrap();
        assert_eq!(path.leaf_index, 0);
        assert_eq!(path.siblings, vec![leaf(&bb)]);
        assert!(verify_path(&aa, &path, &root));
        // path of leaf 1
        let path1 = merkle_path(&[aa, bb], 1).unwrap();
        assert!(verify_path(&bb, &path1, &root));
        // encode/decode roundtrip
        let enc = encode_path(&path).unwrap();
        assert_eq!(enc.len(), 9 + 32);
        assert_eq!(decode_path(&enc), Some(path));
    }

    #[test]
    fn merkle_path_odd_tree() {
        // N=3 (aa, bb, cc) — the duplicated last leaf (index 2) must verify.
        let aa = [0xaau8; 32];
        let bb = [0xbbu8; 32];
        let cc = [0xccu8; 32];
        let leaves = [aa, bb, cc];
        let root = archive_root(&leaves).unwrap();
        for (i, h) in leaves.iter().enumerate() {
            let path = merkle_path(&leaves, i).unwrap();
            assert!(
                verify_path(h, &path, &root),
                "leaf {i} must verify against root"
            );
        }
        // wrong block_hash does not verify
        let path0 = merkle_path(&leaves, 0).unwrap();
        assert!(!verify_path(&[0x00u8; 32], &path0, &root));
    }

    #[test]
    fn merkle_path_single_leaf() {
        // N=1: root = leaf_0, empty path verifies.
        let aa = [0xaau8; 32];
        let root = archive_root(&[aa]).unwrap();
        let path = merkle_path(&[aa], 0).unwrap();
        assert!(path.siblings.is_empty());
        assert!(verify_path(&aa, &path, &root));
    }

    #[test]
    fn merkle_path_out_of_range() {
        assert_eq!(merkle_path(&[[0xaau8; 32]], 1), None);
        assert!(decode_path(&[0u8; 8]).is_none());
    }
}
