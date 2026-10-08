# Security Card — the Montana call (stage 12.11)

**Scope:** what protects a live call — voice, picture, screen — from the moment it is dialled to
the moment it ends. Written for a reader who must tell «encrypted» from «encrypted by what».

**Verified:** 2026-08-29 against the running client (build 1216) and both nodes.

---

## What carries what

```
identity of the two people    ML-DSA-65 signatures over the mesh envelope        [I-1]
session between the phones    ML-KEM-768 sealed box (Noise_PQ XX to the host)    [I-1]
call signalling               inside that session; the node forwards, never reads
media transport pair          DTLS-SRTP over ICE — ADMISSION ONLY                [I-16] A-3/A-4
media content                 SFrame, key derived from the call seed             [I-1]
call seed                     32 random bytes, born on the caller, delivered
                              inside the E2E envelope, never on the wire in clear
```

## The transport pair is admission, not protection

DTLS-SRTP is classical by its own standard, and Montana treats it as a ticket into the pipe, not
as the lock on the content. The three conditions of [I-16] hold:

1. **Compromise is a DoS class, never a breach.** Breaking the transport pair yields a dropped or
   redirected stream. It does not yield the conversation: every frame inside is sealed by SFrame
   with a key the transport never sees.
2. **The real security is post-quantum.** Identity, session and content stand on ML-DSA-65,
   ML-KEM-768 and SHA-256. The call seed rides the post-quantum envelope; the frame key is derived
   from it on both phones and never travels.
3. **Registered.** The pair is the standing A-3/A-4 admission of the registry — the WebRTC/QUIC
   transports named there — and carries no Montana secret of its own.

## When SFrame is on, and what happens when it is not

Both sides must be native and both must hold the seed: the callee enables it on receiving the
call key and answers, the caller on receiving that answer. If the key never arrives, SFrame is
enabled **nowhere** — never on one side only, because a half-enabled cryptor is a silent call.
Media then lives on DTLS-SRTP alone, and the journal says so in one word: the summary line of
every call carries `crypto=dtls-srtp` instead of `crypto=dtls-srtp+sframe-pq`. A person is never
told «encrypted» about a call that is only admitted.

## What the relay sees

A relay forwards ciphertext and knows two addresses and a byte count. It cannot read a frame, it
cannot become a party, and it is not trusted to be honest — it is raced against every other door,
and a node that stops carrying is simply outrun. What a relay does learn is that two addresses
spoke and for how long; closing that is the work of the mesh path, not of the relay.

## The one line that proves it

Every call writes exactly one summary to the node journal:

```
call_summary dir=out video=1 setup_ms=4291 talk_s=63 paths=relay relay_pct=100
             rtt_avg=161 breaks=0 restarts=0 ladder_min_step=0 lost_video=0
             in_kb=3134 out_kb=3676 crypto=dtls-srtp+sframe-pq end=hung-up
```

`crypto=` is the field this card exists for: it names what actually held the content, so no
reader has to assume.
