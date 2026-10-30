package quest.montana.app

/**
 * The Montana core (Rust) — the one source of every derivation. Nothing here is
 * computed in Kotlin: the same words open the same keys on iOS and on Android because both
 * call the same code.
 *
 * Every function is a door of native/montana-jni: the same composition of the core's crates as
 * its iOS twin in mt-bindings/src/ffi_c.rs, proven equal by that crate's tests. There is no door
 * that turns entropy handed in by the app into a phrase: a person is born by the core alone.
 */
object MtBindings {
    init { System.loadLibrary("montana") }

    @JvmStatic external fun nativeAbiVersion(): Int
    @JvmStatic external fun nativeGenerateMnemonic(): String?
    @JvmStatic external fun nativeMnemonicToMasterSeed(mnemonic: String): ByteArray?
    @JvmStatic external fun nativeMnemonicToEntropy(mnemonic: String): ByteArray?
    /** 24 words → pk[1952] ‖ sk[4032]: the iOS door mt_seed_keys. */
    @JvmStatic external fun nativeSeedKeys(mnemonic: String): ByteArray?

    /** master_seed[64] + role → 32 bytes: the core's mt_mldsa_seed_for_role. */
    @JvmStatic external fun nativeRoleSeed(master: ByteArray, role: String): ByteArray?

    /** Bytes drawn by the core from its own sources (mt_random_fast), 1..4096; null when the core refuses. */
    @JvmStatic external fun nativeRandom(len: Int): ByteArray?
    /** entropy[32] → history_key[32] (mt_history_key). */
    @JvmStatic external fun nativeHistoryKey(entropy: ByteArray): ByteArray?
    /** Which conversation a sealed history block belongs to, 32 bytes, or null (mt_archive_peek_conv). */
    @JvmStatic external fun nativeArchivePeekConv(hk: ByteArray, owner: ByteArray, sealed: ByteArray): ByteArray?
    /** A sealed block filed into <base>/Chats/<chat>: 1 appended, 0 already held, <0 refused (mt_archive_ingest). */
    @JvmStatic external fun nativeArchiveIngest(base: String, chat: String, hk: ByteArray, owner: ByteArray, sealed: ByteArray): Int

    /** seed[64] → a card's key, pk[1184] ‖ sk[2400] (mt_mlkem_keypair_from_seed). */
    @JvmStatic external fun nativeMlkemKeypair(seed: ByteArray): ByteArray?
    /** key[32], nonce[12], input → nonce ‖ sealed, the node's blob (mt_e2e_seal_blob). */
    @JvmStatic external fun nativeSealBlob(key: ByteArray, nonce: ByteArray, input: ByteArray): ByteArray?
    /** key[32], a sealed blob → its bytes, or null when the key is not its key (mt_e2e_open_blob). */
    @JvmStatic external fun nativeOpenBlob(key: ByteArray, sealed: ByteArray): ByteArray?
    /** sk[2400], ct[1088] → ss[32], implicit rejection: a foreign ct yields garbage, never null (mt_mlkem_decaps). */
    @JvmStatic external fun nativeMlkemDecaps(sk: ByteArray, ct: ByteArray): ByteArray?
    /** pk[1184] → ct[1088] ‖ ss[32]: the scanner's one encapsulation to a card's key (mt_mlkem_encaps). */
    @JvmStatic external fun nativeMlkemEncaps(pk: ByteArray): ByteArray?
    /** ss, contact root, ct → the first letter's secret[32] (mt_name_first_secret). */
    @JvmStatic external fun nativeFirstSecret(ss: ByteArray, root: ByteArray, ct: ByteArray): ByteArray?
    /** root[1184], window → the point of first contact[16] a first letter knocks at in that window (mt_name_first_tag). */
    @JvmStatic external fun nativeFirstTag(root: ByteArray, window: Long): ByteArray?
    /** The plane of names, the Canon's derivations in the core (mt-names; iOS mt_name_*): normalize, the slot of a normalized name
     *  (null for anything that does not normalize to itself), the chain's far end, the whole chain (129 × 32, link 0 the anchor),
     *  the commitment, one link's proof, the seed of the name's contact key. */
    @JvmStatic external fun nativeNameNormalize(raw: String): String?
    @JvmStatic external fun nativeNameSlot(normalized: String): ByteArray?
    @JvmStatic external fun nativeNameOwn(master: ByteArray, slot: ByteArray): ByteArray?
    @JvmStatic external fun nativeNameChain(own: ByteArray): ByteArray?
    @JvmStatic external fun nativeNameCommit(slot: ByteArray, blind: ByteArray, tip: ByteArray): ByteArray?
    @JvmStatic external fun nativeNameVerifyLink(prev: ByteArray, link: ByteArray): Boolean
    @JvmStatic external fun nativeNameContactSeed(master: ByteArray, slot: ByteArray): ByteArray?
    // The archive of letters (iOS MontanaArchive over mt_archive_*): the media branch, the writer, the log, the twin's export, the
    // reading road and the sealed Media folder — each the core's own, the same composition as the iOS door.
    @JvmStatic external fun nativeMediaKey(entropy: ByteArray): ByteArray?
    @JvmStatic external fun nativeWriterTag(device: ByteArray): ByteArray?
    /** One letter onto the chat's log under the history key: 0, or below zero refused (mt_archive_append). */
    @JvmStatic external fun nativeArchiveAppend(base: String, chat: String, hk: ByteArray, owner: ByteArray, device: ByteArray, conv: ByteArray, dir: Int, sendTime: Long, content: ByteArray): Int
    /** writer_tag[4] ‖ block_seq u64 LE of a sealed block, off its nonce (mt_archive_block_id). */
    @JvmStatic external fun nativeArchiveBlockId(sealed: ByteArray): ByteArray?
    /** This writer's blocks of one chat from a number on, (u32 LE ‖ sealed)×N (mt_archive_export). */
    @JvmStatic external fun nativeArchiveExport(base: String, chat: String, writerTag: ByteArray, fromSeq: Long): ByteArray?
    /** A sealed block opened: block_seq u64 LE ‖ count u32 LE ‖ (conv[32] ‖ dir ‖ at u64 LE ‖ len u32 LE ‖ content)×count (mt_archive_open_block). */
    @JvmStatic external fun nativeArchiveOpenBlock(hk: ByteArray, owner: ByteArray, sealed: ByteArray): ByteArray?
    @JvmStatic external fun nativeArchivePutMedia(base: String, chat: String, blobId: String, mk: ByteArray, owner: ByteArray, data: ByteArray): Boolean
    @JvmStatic external fun nativeArchiveGetMedia(base: String, chat: String, blobId: String, mk: ByteArray, owner: ByteArray): ByteArray?

    /** seed[32] → a machine's answering identity, ML-DSA-65 pk[1952] ‖ sk[4032] (mt_mldsa_keypair_from_seed). */
    @JvmStatic external fun nativeMldsaKeypair(seed: ByteArray): ByteArray?
    /** sk[4032], msg → an ML-DSA-65 signature[3309] (mt_sign). */
    @JvmStatic external fun nativeSign(sk: ByteArray, msg: ByteArray): ByteArray?
    /** pk[1952], msg, sig[3309] → whether it is pk's signature of msg (mt_verify). */
    @JvmStatic external fun nativeVerify(pk: ByteArray, msg: ByteArray, sig: ByteArray): Boolean

    // The channel's handshake, Noise_PQ XX (mt_noise_*): the states between the messages stay in the core, Kotlin holds an
    // address and hands it back exactly once (every call consumes the state it is given, answer or refusal); a state
    // abandoned between messages is freed by nativeNoiseFree.
    /** Initiator: the responder's KEM pk[1184], a fresh seed[32] → msg1[2272]; out[0] — the state for msg2. */
    @JvmStatic external fun nativeNoiseInitiator1(kemPk: ByteArray, seed: ByteArray, out: LongArray): ByteArray?
    /** Initiator: msg2[6349] under the state of msg1 → the state for msg3, 0 when msg2 is refused. */
    @JvmStatic external fun nativeNoiseInitiator2(state: Long, msg2: ByteArray): Long
    /** Initiator: the state of msg2 → msg3[5261] ‖ sk_i_to_r[32] ‖ sk_r_to_i[32] ‖ channel_hash[32]. */
    @JvmStatic external fun nativeNoiseInitiator3(state: Long): ByteArray?
    /** Responder: its KEM sk[2400], a fresh seed[32], msg1[2272] → msg2[6349]; out[0] — the state for msg3. */
    @JvmStatic external fun nativeNoiseResponder1(kemSk: ByteArray, seed: ByteArray, msg1: ByteArray, out: LongArray): ByteArray?
    /** Responder: msg3[5261] under the state of msg2 → sk_i_to_r[32] ‖ sk_r_to_i[32] ‖ channel_hash[32]. */
    @JvmStatic external fun nativeNoiseResponder3(state: Long, msg3: ByteArray): ByteArray?
    /** A state abandoned between messages: kind 1 — after msg1, 2 — after msg2, 3 — the responder's. */
    @JvmStatic external fun nativeNoiseFree(kind: Int, state: Long)

    const val PUBKEY = 1952
    const val SECKEY = 4032
}
