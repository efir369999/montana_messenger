// THE KOTLIN SIDE OF tools/author_canon_check.sh: the author field's self-check (AuthorCanon) on chosen days, over a mirror of the code
// Wire signs a letter with (Pipes.kt: authorTag, withAuthor, authorHolds, itemKey, itemKeys -- the iOS formula, MTNodeWire 99-125 and
// MTPipeKey.itemKey), so the check must agree whatever day it runs on; and a letter signed from 29.10 must carry its field and be read
// back as the person's own. No check reads this computer's clock.
import quest.montana.app.AuthorCanon
import java.security.MessageDigest
import java.util.Base64
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

private var ok = 0
private var bad = 0
private fun check(what: String, good: Boolean) { if (good) ok++ else { bad++; println("FAIL $what") } }

private const val ANCHOR = 20754L
private fun sha(vararg parts: ByteArray): ByteArray = MessageDigest.getInstance("SHA-256").run { parts.forEach { update(it) }; digest() }
private fun hmac(key: ByteArray, data: ByteArray): ByteArray = Mac.getInstance("HmacSHA256").run { init(SecretKeySpec(key, "HmacSHA256")); doFinal(data) }
private fun root(secret: ByteArray) = sha("mt-conv-root".toByteArray() + byteArrayOf(0), secret)
private fun itemKey(secret: ByteArray, day: Long) = if (day > ANCHOR) root(secret) else secret
private fun authorTag(key: ByteArray, secret: ByteArray, mid: String, text: String): String =
    Base64.getEncoder().encodeToString(hmac(key, "mt-letter-author".toByteArray() + byteArrayOf(0) + secret + mid.toByteArray() + byteArrayOf(0) +
        text.toByteArray()).copyOf(16))
private fun withAuthor(body: ByteArray, key: ByteArray?, secret: ByteArray, mid: String, text: String, day: Long): ByteArray {
    if (key == null || key.size != 32) return body
    var b = body
    if (b.isNotEmpty() && b.last() != 0.toByte()) b += byteArrayOf(0)
    var closed = b.count { it == 0.toByte() }
    while (closed < 7) { b += byteArrayOf(0); closed++ }
    if (closed != 7) return body
    b += authorTag(key, itemKey(secret, day), mid, text).toByteArray() + byteArrayOf(0)
    return if (b.size <= 2048) b else body
}
private fun authorHolds(tag: String, key: ByteArray?, secret: ByteArray, mid: String, text: String): Boolean {
    if (key == null || key.size != 32 || tag.isEmpty()) return false
    val got = runCatching { Base64.getDecoder().decode(tag) }.getOrNull()?.takeIf { it.size == 16 } ?: return false
    return listOf(root(secret), secret).any { k -> MessageDigest.isEqual(got, Base64.getDecoder().decode(authorTag(key, k, mid, text))) }
}

fun main() {
    for (today in listOf(20700L, ANCHOR, ANCHOR + 1, ANCHOR + 3, ANCHOR + 4, ANCHOR + 6, ANCHOR + 7, ANCHOR + 46, ANCHOR + 36_605))
        check("the author field's self-check agrees when run on day $today", AuthorCanon.agrees(today, ::authorTag, ::withAuthor, ::authorHolds) { sha(it) })
    val person = ByteArray(32) { 0x33 }
    val secret = ByteArray(32) { it.toByte() }
    for (d in listOf(ANCHOR, ANCHOR + 1, ANCHOR + 4, ANCHOR + 6)) {
        val signed = withAuthor("m1".toByteArray() + byteArrayOf(0) + "hello".toByteArray() + byteArrayOf(0), person, secret, "m1", "hello", d)
        val field = String(signed, Charsets.UTF_8).split('\u0000').getOrNull(7).orEmpty()
        check("a letter signed on $d carries its author field, and the person's other device reads it as the person's own",
            field.isNotEmpty() && authorHolds(field, person, secret, "m1", "hello"))
    }
    println("author_canon: ok=$ok bad=$bad")
    if (bad != 0) System.exit(1)
}
