"""Vectors of the letter's author field, made outside the app from the iOS formula (MTNodeWire.swift 99-125, iOS 2229-2231):
    authorTag  = base64(HMAC-SHA-256(key, "mt-letter-author" || 0 || secret || mid || 0 || text)[0..16])  (standard base64, padded)
    withAuthor = the body with every field before the author closed (7: mid, text, name, glyph, quote, quoted mid, card),
                 then the tag and a closing 0 — the body unchanged when the key is not 32 bytes or it would outgrow 2048 bytes.
The Kotlin twin (Wire.authorTag / Wire.withAuthor, Pipes.kt) must reproduce these bytes.
    python -I -X utf8 tools/author_vectors.py"""
import base64
import hashlib
import hmac

FIELDS, ENVELOPE = 7, 2048


def author_tag(key, secret, mid, text):
    m = b"mt-letter-author\x00" + secret + mid.encode() + b"\x00" + text.encode()
    return base64.b64encode(hmac.new(key, m, hashlib.sha256).digest()[:16]).decode()


def with_author(body, key, secret, mid, text):
    if len(key) != 32:
        return body
    b = bytearray(body)
    if b and b[-1] != 0:
        b.append(0)
    closed = b.count(0)
    while closed < FIELDS:
        b.append(0)
        closed += 1
    if closed != FIELDS:
        return body
    b += author_tag(key, secret, mid, text).encode() + b"\x00"
    return bytes(b) if len(b) <= ENVELOPE else body


key, secret = bytes([0x61]) * 32, bytes([0x44]) * 32
mid, text = "t1792249000000-ABCD", "Привет, Montana 🌍"
head = mid.encode() + b"\x00" + text.encode() + b"\x00" + "Alice".encode() + b"\x00" + b"\x00"   # Android letterHead: 4 fields closed
print("authorTag              =", author_tag(key, secret, mid, text))
print("authorTag(text='')     =", author_tag(key, secret, mid, ""))
print("withAuthor(head) sha256 =", hashlib.sha256(with_author(head, key, secret, mid, text)).hexdigest())
print("withAuthor(head) len    =", len(with_author(head, key, secret, mid, text)))
card = head + b"\x00\x00" + b'{"u":"https://montana.quest","t":"Montana"}'   # the card as field 7, without its close
print("withAuthor(card) sha256 =", hashlib.sha256(with_author(card, key, secret, mid, text)).hexdigest())
# FROM 29.10.2026 (day 20755, past iOS MTPipeKey.walkAnchorDay 20754) A LETTER IS SIGNED OVER THE CONVERSATION'S ROOT (iOS 2311
# MTPipeKey.itemKey): root = SHA-256("mt-conv-root" || 0 || secret); the same field and framing over it. A self-check keeps each vector
# on its own day: the rows above on the anchor day, these from the day after.
root = hashlib.sha256(b"mt-conv-root\x00" + secret).digest()
print("root                   =", root.hex())
print("authorTag(root)        =", author_tag(key, root, mid, text))
print("withAuthor(head, root) sha256 =", hashlib.sha256(with_author(head, key, root, mid, text)).hexdigest())
print("withAuthor(head, root) len    =", len(with_author(head, key, root, mid, text)))
print("withAuthor(card, root) sha256 =", hashlib.sha256(with_author(card, key, root, mid, text)).hexdigest())
