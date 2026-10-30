package quest.montana.app

/**
 * THE LETTER'S AUTHOR FIELD AGAINST ITS VECTORS, EACH ON ITS OWN DAY (tools/author_vectors.py, made outside the app from the iOS formula:
 * MTNodeWire.authorTag / withAuthor, MTPipeKey.itemKey). The field stands on the established secret up to the anchor day (28.10.2026,
 * 20754) and on the conversation's root from the day after, so every vector names its own day: the rows over the secret are read on the
 * anchor day, the rows over the root on the day after, never on the day the check runs. Beside them, a letter signed on `today` must
 * carry its field and be read back as the person's own -- what another device of the person does with it. The signing code is handed in
 * (the one this tree signs with), so the check holds that code on every day. Pure: tools/author_canon_check.sh runs it on chosen days.
 */
object AuthorCanon {
    /** iOS MTPipeKey.walkAnchorDay: the last day a letter is signed over the established secret. */
    const val ANCHOR_DAY = 20754L

    fun agrees(
        today: Long,
        tag: (key: ByteArray, secret: ByteArray, mid: String, text: String) -> String,
        sign: (body: ByteArray, key: ByteArray?, secret: ByteArray, mid: String, text: String, day: Long) -> ByteArray,
        holds: (tag: String, key: ByteArray?, secret: ByteArray, mid: String, text: String) -> Boolean,
        sha: (ByteArray) -> ByteArray,
    ): Boolean {
        fun hex(b: ByteArray) = b.joinToString("") { "%02x".format(it) }
        val key = ByteArray(32) { 0x61 }
        val secret = ByteArray(32) { 0x44 }
        val mid = "t1792249000000-ABCD"
        val text = "Привет, Montana 🌍"
        val head = mid.toByteArray() + byteArrayOf(0) + text.toByteArray() + byteArrayOf(0) + "Alice".toByteArray() + byteArrayOf(0, 0)
        val card = head + byteArrayOf(0, 0) + "{\"u\":\"https://montana.quest\",\"t\":\"Montana\"}".toByteArray()
        val overSecret = tag(key, secret, mid, text) == "WcOqZdlxhSpBEZYKgbjSSg=="
            && tag(key, secret, mid, "") == "AZIK29ezKo70HRREQwXbzA=="
            && sign(head, key, secret, mid, text, ANCHOR_DAY).let { it.size == 82 && hex(sha(it)) == "5fe43b371f456a08e30ffe5d736c866719e26f5702fcf4da3ca7145ca39b358d" }
            && hex(sha(sign(card, key, secret, mid, text, ANCHOR_DAY))) == "bd472907cb6fb8d2d13a4291f80f976fdb836658b4ecd1f3d9d53ad1ea112d9c"
        val overRoot = sign(head, key, secret, mid, text, ANCHOR_DAY + 1).let { it.size == 82 && hex(sha(it)) == "fcfc401b4569be8841c4ceba207a462d6e5d9de0b1c84cd0afd821a0d6ab4abc" }
            && hex(sha(sign(card, key, secret, mid, text, ANCHOR_DAY + 1))) == "544da6e56fe848b87327516bcc0389d3e6abc890f6afe4727b400ba8646b2673"
        val reads = holds("WcOqZdlxhSpBEZYKgbjSSg==", key, secret, mid, text) && holds("7guflqG5E43OLPFovkhhWg==", key, secret, mid, text)
            && !holds("WcOqZdlxhSpBEZYKgbjSSg==", key, secret, mid, "x") && !holds("7guflqG5E43OLPFovkhhWg==", key, secret, mid, "x")
        // a letter signed today carries its eighth field, and the person's other device reads it as the person's own
        val signed = sign(head, key, secret, mid, text, today)
        val field = String(signed, Charsets.UTF_8).split('\u0000').getOrNull(7).orEmpty()
        val signedToday = signed.size > head.size && field.isNotEmpty() && holds(field, key, secret, mid, text)
        return overSecret && overRoot && reads && signedToday
    }
}
