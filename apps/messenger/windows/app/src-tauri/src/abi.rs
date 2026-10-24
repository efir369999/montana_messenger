//! The core's C ABI, as core/Code/crates/mt-bindings/src/ffi_c.rs declares it (ABI_VERSION 1) -- the same doors
//! iOS calls. Only the doors this app uses are named here; a test checks the ABI version the DLL answers with.

use std::ffi::c_void;
use std::os::raw::{c_char, c_int};

#[cfg(test)]
pub const ABI_VERSION: u32 = 1;
pub const MT_OK: c_int = 0;
pub const MT_MAX_MNEMONIC_BYTES: usize = 512;
pub const MT_MLDSA_PUBKEY_SIZE: usize = 1952;
pub const MT_MLDSA_SECKEY_SIZE: usize = 4032;
pub const MT_MLDSA_SIG_SIZE: usize = 3309;
pub const MT_MASTER_SEED_LEN: usize = 64;
pub const MT_MLDSA_SEED_LEN: usize = 32;
pub const MT_MLKEM_SEED_LEN: usize = 64;
pub const MT_MLKEM_PUBKEY_SIZE: usize = 1184;
pub const MT_MLKEM_SECKEY_SIZE: usize = 2400;
pub const MT_MLKEM_CT_SIZE: usize = 1088;
pub const MT_MLKEM_SS_SIZE: usize = 32;

extern "C" {
    pub fn mt_abi_version() -> u32;
    pub fn mt_entropy_sources(out: *mut u8, capacity: usize, out_len: *mut usize) -> c_int;
    pub fn mt_entropy_min_live() -> c_int;
    pub fn mt_generate_mnemonic(out_mnemonic_utf8: *mut u8, out_capacity: usize, out_len: *mut usize) -> c_int;
    pub fn mt_mnemonic_to_master_seed(mnemonic_utf8: *const c_char, out_master_seed: *mut u8) -> c_int;
    pub fn mt_mldsa_seed_for_role(master_seed: *const u8, role: *const u8, role_len: usize, out_seed: *mut u8) -> c_int;
    pub fn mt_random_fast(out: *mut u8, len: usize) -> c_int;
    pub fn mt_mldsa_keypair_from_seed(seed: *const u8, out_pubkey: *mut u8, out_seckey: *mut u8) -> c_int;
    pub fn mt_sign(seckey: *const u8, msg: *const u8, msg_len: usize, out_sig: *mut u8) -> c_int;
    pub fn mt_verify(pubkey: *const u8, msg: *const u8, msg_len: usize, sig: *const u8) -> c_int;
    pub fn mt_mlkem_keypair_from_seed(seed: *const u8, out_pubkey: *mut u8, out_seckey: *mut u8) -> c_int;
    pub fn mt_mlkem_encaps(pubkey: *const u8, out_ct: *mut u8, out_ss: *mut u8) -> c_int;
    pub fn mt_mlkem_decaps(seckey: *const u8, ct: *const u8, out_ss: *mut u8) -> c_int;
    pub fn mt_name_first_secret(ss: *const u8, ss_len: usize, root: *const u8, root_len: usize, ct: *const u8, ct_len: usize, out32: *mut u8) -> c_int;
    pub fn mt_e2e_seal_blob(key: *const u8, nonce: *const u8, input: *const u8, input_len: usize, out_ptr: *mut *mut u8, out_len: *mut usize) -> c_int;
    pub fn mt_e2e_open_blob(key: *const u8, sealed: *const u8, len: usize, out_ptr: *mut *mut u8, out_len: *mut usize) -> c_int;
    pub fn mt_e2e_free(ptr: *mut u8, len: usize);
    pub fn mt_e2e_blob_id(sealed_blob: *const u8, len: usize, out32: *mut u8) -> c_int;
    pub fn mt_e2e_pad_len(n: usize) -> usize;
    pub fn mt_mnemonic_to_entropy(mnemonic_utf8: *const c_char, out_entropy: *mut u8) -> c_int;
    pub fn mt_history_key(entropy: *const u8, out: *mut u8) -> c_int;
    pub fn mt_media_key(entropy: *const u8, out: *mut u8) -> c_int;
    pub fn mt_archive_append(base_path: *const c_char, chat_name: *const c_char, hk: *const u8, account_id: *const u8, device_id: *const u8,
                             conv_id: *const u8, dir: u8, send_time: u64, content: *const u8, content_len: usize) -> i32;
    pub fn mt_archive_ingest(base_path: *const c_char, chat_name: *const c_char, hk: *const u8, account_id: *const u8,
                             sealed: *const u8, sealed_len: usize) -> i32;
    pub fn mt_writer_tag(device_id: *const u8, out: *mut u8) -> c_int;
    // a file sealed under the media key into <base>/Chats/<chat>/Media/<blob> (iOS MontanaArchive.putMedia / getMedia)
    pub fn mt_archive_put_media(base_path: *const c_char, chat_name: *const c_char, blob_id_hex: *const c_char, mk: *const u8,
                                account_id: *const u8, blob: *const u8, blob_len: usize) -> c_int;
    pub fn mt_archive_get_media(base_path: *const c_char, chat_name: *const c_char, blob_id_hex: *const c_char, mk: *const u8,
                                account_id: *const u8, out: *mut u8, out_cap: usize) -> isize;
    pub fn mt_archive_open_block(hk: *const u8, account_id: *const u8, sealed: *const u8, sealed_len: usize, out: *mut u8, out_cap: usize) -> isize;
    pub fn mt_archive_block_id(sealed: *const u8, sealed_len: usize, out_writer_tag: *mut u8, out_block_seq: *mut u64) -> c_int;
    pub fn mt_archive_export(base_path: *const c_char, chat_name: *const c_char, writer_tag: *const u8, from_seq: u64, out: *mut u8, out_cap: usize) -> isize;
    pub fn mt_archive_peek_conv(hk: *const u8, account_id: *const u8, sealed: *const u8, sealed_len: usize, out: *mut u8) -> c_int;
    pub fn mt_seed_keys(mnemonic_utf8: *const c_char, out_pubkey: *mut u8, out_seckey: *mut u8) -> c_int;
    // Noise_PQ XX (spec s.3 section 5.0): msg1 2272, msg2 6349, msg3 5261; the session's two keys and its transcript hash, 32 each.
    // A state handed to the next step is consumed there and nulled; one abandoned between steps goes to its free.
    pub fn mt_noise_initiator_msg1(responder_kem_pk: *const u8, node_id_seed: *const u8, out_msg1: *mut u8, out_state: *mut *mut c_void) -> c_int;
    pub fn mt_noise_initiator_msg2(state: *mut *mut c_void, msg2: *const u8, out_state2: *mut *mut c_void) -> c_int;
    pub fn mt_noise_initiator_msg3(state2: *mut *mut c_void, out_msg3: *mut u8, out_sk_i_to_r: *mut u8, out_sk_r_to_i: *mut u8,
                                   out_channel_hash: *mut u8) -> c_int;
    pub fn mt_noise_responder_msg1(responder_kem_sk: *const u8, node_id_seed: *const u8, msg1: *const u8, out_msg2: *mut u8,
                                   out_state: *mut *mut c_void) -> c_int;
    pub fn mt_noise_responder_msg3(state: *mut *mut c_void, msg3: *const u8, out_sk_i_to_r: *mut u8, out_sk_r_to_i: *mut u8,
                                   out_channel_hash: *mut u8) -> c_int;
    pub fn mt_noise_state_free_initiator1(state: *mut c_void);
    pub fn mt_noise_state_free_initiator2(state: *mut c_void);
    pub fn mt_noise_state_free_responder(state: *mut c_void);
    // a first letter's tag (iOS MTPipeBook.outgoingTag): the header's door, not called here
    #[allow(dead_code)]
    pub fn mt_name_first_tag(contact_root: *const u8, root_len: usize, window: u64, out16: *mut u8) -> c_int;
}
