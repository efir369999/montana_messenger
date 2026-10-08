// LEFTOVER-ACK: an XCTestCase has no caller in the tree by construction -- XCTest finds
// every test* method by reflection and drives the class itself. The file is the test
// target, not an orphan.
//
//  MontanaTests.swift — the conformance suite: byte-exact known-answer tests from the set.
//

import XCTest
import CryptoKit
@testable import Montana
import MontanaBindings

final class MontanaTests: XCTestCase {

    // Identity birth: the zero-entropy phrase opens exactly the keys recorded in the core.
    // There is no identifier among them and cannot be: the set does not introduce one
    // ([I-17].2), so nothing is frozen here except the keys themselves — the one thing the
    // seed opens.
    func testSeedKeysFromPhraseKAT() throws {
        let phrase = Array(repeating: "abandon", count: 23).joined(separator: " ") + " art"
        // A failure must NAME the step where the chain stopped: «identity did not open» is a
        // complaint, not a diagnosis. The steps go in the same order as in the core.
        var entropy = [UInt8](repeating: 0, count: 32)
        XCTAssertEqual(phrase.withCString { mt_mnemonic_to_entropy($0, &entropy) }, 0, "phrase -> entropy")
        var master = [UInt8](repeating: 0, count: 64)
        XCTAssertEqual(phrase.withCString { mt_mnemonic_to_master_seed($0, &master) }, 0, "phrase -> master seed")
        var roleSeed = [UInt8](repeating: 0, count: 32)
        let role = Array("mt-account-key".utf8)
        XCTAssertEqual(mt_mldsa_seed_for_role(master, role, role.count, &roleSeed), 0, "root -> role seed")
        var pk = [UInt8](repeating: 0, count: 1952), sk = [UInt8](repeating: 0, count: 4032)
        XCTAssertEqual(mt_mldsa_keypair_from_seed(roleSeed, &pk, &sk), 0, "role seed -> keypair")

        let acc = try XCTUnwrap(MontanaSeedKeys.keys(from: phrase),
                                "the zero-entropy phrase must open the keys")
        XCTAssertEqual(acc.pubkey.count, 1952, "ML-DSA-65 public key")
        XCTAssertEqual(acc.seckey.count, 4032, "ML-DSA-65 secret key")
        let again = try XCTUnwrap(MontanaSeedKeys.keys(from: phrase))
        XCTAssertEqual(acc.pubkey, again.pubkey, "one phrase — the same keys, on any device")
        XCTAssertEqual(acc.seckey, again.seckey)
        let other = try XCTUnwrap(MontanaSeedKeys.keys(
            from: Array(repeating: "abandon", count: 23).joined(separator: " ") + " about"))
        XCTAssertNotEqual(acc.pubkey, other.pubkey, "a different phrase — different keys")
    }

    // The verification fingerprint stands on the correspondence secret: an outsider cannot
    // compute it, and a man in the middle who swapped the secret changes the number. The value
    // is stable and symmetric — both sides read the same.
    func testFingerprintStandsOnTheCorrespondenceSecret() throws {
        let s1 = Data(repeating: 0x41, count: 32)
        let s2 = Data(repeating: 0x42, count: 32)
        let fp = try XCTUnwrap(MTPipe.fingerprint(secret: s1))
        XCTAssertEqual(fp.count, 30, "thirty digits, six groups of five")
        XCTAssertTrue(fp.allSatisfy { $0.isNumber }, "digits only — they are read aloud")
        // The value is computed by an INDEPENDENT Python implementation of the Canon formula
        // (5200 repetitions of mt-safety, thirty bytes in six groups modulo 100000): a vector
        // the tree computes for itself proves only its agreement with itself.
        XCTAssertEqual(fp, "237630090224408202482973514653",
                       "the fingerprint must match the independent count by the set's formula")
        XCTAssertEqual(MTPipe.fingerprint(secret: s2), "600510040272855766213192827488")
        XCTAssertEqual(fp, MTPipe.fingerprint(secret: s1), "one correspondence — one number")
        XCTAssertNotEqual(fp, MTPipe.fingerprint(secret: s2), "a swapped secret changes the number")
        XCTAssertNil(MTPipe.fingerprint(secret: Data(repeating: 0x41, count: 31)))
    }

    // A letter does not name its sender: the envelope holds only its own number and the text,
    // and the conversation is taken from the pipe the letter arrived on.
    // The envelope on the wire carries EXACTLY the window tag and the sealed body. Neither the
    // letter id nor a single character of text exists in its bytes — they open only with the
    // pipe's secret. The check rejects an implementation that puts the mid or the text beside
    // the tag in the open.
    func testEnvelopeNamesNobody() throws {
        let secret = Data(repeating: 0x5A, count: 32)
        let mid = "abc123", text = "hello"
        var body = Data(mid.utf8); body.append(0); body.append(contentsOf: text.utf8)
        let sealed = try XCTUnwrap(MTPipe.sealBody(body, sharedSecret: secret))
        let tag = Data(repeating: 0x7E, count: MontanaP2PNode.letterTagBytes)

        var env = Data([MontanaP2PNode.letterFrame]); env.append(tag); env.append(sealed)
        let parsed = try XCTUnwrap(MontanaP2PNode.parseEnvelope(env))
        XCTAssertEqual(parsed.tag, tag, "the window tag passes the wire byte for byte")
        XCTAssertEqual(parsed.sealed, sealed, "the body passes the wire byte for byte")

        let opened = try XCTUnwrap(MontanaP2PNode.openBody(parsed.sealed, secret: secret))
        XCTAssertEqual(opened.mid, mid)
        XCTAssertEqual(opened.text, text)

        XCTAssertNil(env.range(of: Data(mid.utf8)), "the letter id is not in the envelope")
        XCTAssertNil(env.range(of: Data(text.utf8)), "the text is not in the envelope")
        XCTAssertNil(MontanaP2PNode.openBody(parsed.sealed, secret: Data(repeating: 0x5B, count: 32)),
                     "the body does not open with a stranger's secret")

        var blob = Data([0x00]); blob.append(contentsOf: "id".utf8)
        XCTAssertNil(MontanaP2PNode.parseEnvelope(blob), "an attachment frame is not a letter")
        XCTAssertNil(MontanaP2PNode.parseEnvelope(Data([MontanaP2PNode.letterFrame]) + tag),
                     "an envelope with no body is not a letter")
    }

    // history_key = HKDF-SHA-256(0x32, entropy_32, "mt-history-key", 32) from the seed (history_key_kat).
    func testHistoryKeyKAT() throws {
        XCTAssertTrue(MontanaVault.historyKeyKAT(),
                      "history_key(0x55x32) == e6a7dc51…578def — the history key is derived from the seed byte-exact")
    }

    // Binding vector: base64url without padding, 00 01 02 … 1f -> AAECAwQF…GBkaGxwdHh8.
    func testBase64UrlKAT() throws {
        let vector = "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8"
        let decoded = try XCTUnwrap(Data(base64urlNoPad: vector), "base64url decode of the stage-2 vector")
        XCTAssertEqual(decoded, Data((0..<32).map { UInt8($0) }),
                       "base64url(00 01 … 1f) without padding must decode to 32 bytes 0x00..0x1f")
    }


    // ── One composition, one window, one tolerance (SSOT of the labels) ──
    // The values below are computed by an INDEPENDENT implementation (python hashlib), not by this
    // tree: a vector a codebase computes for itself proves only that it agrees with itself.

    func testPipeAgreesWithCanon() throws {
        XCTAssertTrue(MTPipe.agreesWithCanon(),
                      "tag / step / relay-seal / owner-ref / holder must reproduce the frozen vectors of the set")
    }

    // mt-tag(0x44x32, 1000) — the independent computation gives 1d994670...d1b6, byte for byte.
    func testPipeTagAgainstIndependentOracle() throws {
        XCTAssertEqual(MTPipe.tag(sharedSecret: Data(repeating: 0x44, count: 32), window: 1000).montanaHexString,
                       "1d99467017fe1d0cc7c7ba29df6fd1b6",
                       "the tag of a pipe must equal the composition of the set over secret and window")
    }

    // Every label of the tree counts time by ONE window and accepts ONE tolerance.
    func testOneWindowAndOneTolerance() throws {
        let at = Date(timeIntervalSince1970: 1_700_000_042)
        XCTAssertEqual(MTPipe.window(at), 1_700_000_042 / 60, "the window is seconds divided by the one length")
        XCTAssertEqual(MontanaLocalTag.window(at), MTPipe.window(at), "an announce counts the same window")
        XCTAssertEqual(MontanaRendezvous.window(at), MTPipe.window(at), "a rendezvous counts the same window")
        XCTAssertEqual(MTPipe.windows(at: at), [MTPipe.window(at) - 1, MTPipe.window(at), MTPipe.window(at) + 1],
                       "the tolerance is the neighbouring windows, stated once")
    }

    // A correspondence stands on the secret its first letter established, and this device files it
    // under a name of its own making: the same secret gives the same name on both devices of one
    // person, and a different secret gives a name that joins to nothing.
    func testPipeReferenceIsOfTheSecretAndNotOfARef() throws {
        let a = Data(repeating: 0x21, count: 32)
        let b = Data(repeating: 0x22, count: 32)
        let ra = try XCTUnwrap(MTPipeBook.reference(of: a))
        XCTAssertEqual(ra, MTPipeBook.reference(of: a), "the same secret files under the same name")
        XCTAssertNotEqual(ra, MTPipeBook.reference(of: b), "two correspondences do not share a name")
        XCTAssertEqual(ra.count, 32, "sixteen bytes in hex")
        XCTAssertNil(MTPipeBook.reference(of: Data(repeating: 0x21, count: 31)), "a short secret is refused")
    }

    // A letter is recognised by the tag of its pipe, and the correspondence is read off the match —
    // so nothing on the wire has to name the sender.
    func testTagOfAPipeIdentifiesTheCorrespondenceWithoutNamingAnyone() throws {
        let secret = Data(repeating: 0x33, count: 32)
        let ref = try XCTUnwrap(MTPipeBook.establish(secret: secret))
        let at = Date(timeIntervalSince1970: 1_700_000_042)
        let tag = try XCTUnwrap(MTPipeBook.tag(for: ref, window: MTPipe.window(at)))
        XCTAssertEqual(MTPipeBook.match(tag, at: at), ref, "the tag of this window resolves to this correspondence")
        XCTAssertNil(MTPipeBook.match(Data(repeating: 0xEE, count: 16), at: at),
                     "a tag of nobody's pipe resolves to nothing")
        let far = Date(timeIntervalSince1970: 1_700_000_042 + 600)
        XCTAssertNil(MTPipeBook.match(tag, at: far),
                     "a tag of one window does not answer in a distant one — two windows do not join")
    }

    // An invitation carries a NAME and never a key or an address: the key has one place, the slot
    // of that name, and a link that copied it would pin a holder who may no longer hold the name.
    func testInvitationCarriesANameAndNothingElse() throws {
        XCTAssertEqual(MontanaFirstContact.name(inInvitation: "montana://alice"), "alice")
        XCTAssertEqual(MontanaFirstContact.name(inInvitation: "  montana://Alice  "), "alice",
                       "a name is normalized as the set normalizes it")
        XCTAssertNil(MontanaFirstContact.name(inInvitation: "montana://who/what"),
                     "the invite carries the name and nothing that leads anywhere else")
        XCTAssertNil(MontanaFirstContact.name(inInvitation: "hello"), "plain text is refused")
        // The name's web link (24.09): the written form, and what a messenger or a hand does to it on the way.
        XCTAssertEqual(MontanaFirstContact.name(inInvitation: "https://pzr.me/alice"), "alice")
        XCTAssertEqual(MontanaFirstContact.name(inInvitation: "HTTPS://PZR.ME/Alice/"), "alice", "case and a closing slash are not the name")
        XCTAssertEqual(MontanaFirstContact.name(inInvitation: "pzr.me/alice?utm=x"), "alice", "a lost scheme and a query are not the name")
        XCTAssertEqual(MontanaFirstContact.name(inInvitation: "https://www.pzr.me/alice#top"), "alice")
        XCTAssertNil(MontanaFirstContact.name(inInvitation: "https://pzr.me/alice/more"), "a second segment is not a name")
        XCTAssertNil(MontanaFirstContact.name(inInvitation: "https://pzr.me/"), "an empty name is not a name")
        XCTAssertNil(MontanaFirstContact.name(inInvitation: "https://montana.quest/alice"), "another domain is not the name's link")
        XCTAssertNil(MontanaFirstContact.name(inInvitation: "https://pzr.meadow/alice"), "a domain that only begins alike is refused")
        // serialize(name_reveal) for «alice», blind 0xDD, root 0xCC — the digest the node's test_names.py freezes too.
        // Catches a reveal without its length byte, a padding before the name, a blind and a root swapped.
        let rv = MontanaNames.reveal(name: "alice", blind: Data(repeating: 0xDD, count: 32), root: Data(repeating: 0xCC, count: 1184))
        XCTAssertEqual(rv?.count, 1249)
        XCTAssertEqual(rv.map { Data(SHA256.hash(data: $0)).montanaHexString },
                       "b678ed125e3a466aac31dfa9153c2f33fa52427df173c188abbf66a7af9224ba", "the reveal drifted from the node's")
        XCTAssertEqual(MontanaFirstContact.slot(inInvitation: "montana://alice"),
                       MontanaNames.slot(normalized: "alice"),
                       "an invitation resolves to the slot the plane of names is asked at")
    }

    // base64url without padding writes and reads in one place — a round trip has to hold.
    func testBase64UrlRoundTrip() throws {
        let d = Data((0..<200).map { UInt8($0 % 251) })
        let text = d.base64urlNoPad
        XCTAssertFalse(text.contains("="), "no padding")
        XCTAssertFalse(text.contains("+") || text.contains("/"), "url alphabet")
        XCTAssertEqual(Data(base64urlNoPad: text), d, "what is written is what is read")
    }

    // The address of a node is computed in one place — and it equals the composition of the set.
    func testOverlayEndpointSinglePlace() throws {
        let pub = [UInt8](repeating: 0x77, count: 1952)
        XCTAssertEqual(MontanaOverlayKey.tag(fromAuthPub: pub),
                       MTPipe.domained("mt-overlay", [Data(pub)]),
                       "the address of a node must come from the one composition, not from a hand-written copy")
    }
}

// -- A phantom is impossible BY CONSTRUCTION: the point names its card, the key must confirm --
//
// The disease: ML-KEM on a wrong key does NOT refuse (implicit rejection, FIPS 203) — it
// returns deterministic garbage from which a conversation reference is honestly derived. Two
// laws remove not the phantom but the very possibility of creating one.
final class MontanaPhantomImpossibleTests: XCTestCase {

    // LAW A. Delivery points are keyed under ONE root: the card is known before any
    // cryptography. Rejects an implementation where points are a bare set and the card must
    // be guessed by trial.
    func testTheDeliveryPointNamesTheCard() throws {
        let master = Data(repeating: 0x42, count: 64)
        let a = try XCTUnwrap(MontanaFirstContact.contactPair(masterSeed: master, slot: Data([1])))
        let b = try XCTUnwrap(MontanaFirstContact.contactPair(masterSeed: master, slot: Data([2])))
        let w = MTPipe.window()
        let pa = try XCTUnwrap(MontanaFirstContact.knock(at: a.root, window: w))
        let pb = try XCTUnwrap(MontanaFirstContact.knock(at: b.root, window: w))
        XCTAssertNotEqual(pa, pb, "two cards — two different points")

        // The point → root mapping exists and is unambiguous: the set of points derives from it.
        let points: [Data: Data] = [pa: a.root, pb: b.root]
        XCTAssertEqual(points[pa], a.root, "a point names its own card, not a neighbour's")
        XCTAssertEqual(Set(points.keys).count, 2, "the set of points derives from the mapping")
    }

    // LAW B. A key confirmation cannot be presented without owning the true shared secret.
    // Rejects «accept = decrypt»: implicit-rejection garbage yields no confirmation — forging
    // one means finding a SHA-256 preimage.
    func testConfirmationCannotBeForgedByImplicitRejection() throws {
        let master = Data(repeating: 0x42, count: 64)
        let a = try XCTUnwrap(MontanaFirstContact.contactPair(masterSeed: master, slot: Data([1])))
        let b = try XCTUnwrap(MontanaFirstContact.contactPair(masterSeed: master, slot: Data([2])))
        let started = try XCTUnwrap(MontanaFirstContact.begin(toward: a.root))
        let conf = MontanaFirstContact.firstConfirm(secret: started.secret, ct: started.ciphertext)

        // One's own card arrives at the same secret and the same confirmation.
        let real = try XCTUnwrap(MontanaFirstContact.accept(ciphertext: started.ciphertext,
                                                            contactSecret: a.secret, contactRoot: a.root))
        XCTAssertTrue(MontanaFirstContact.sameConfirm(
            conf, MontanaFirstContact.firstConfirm(secret: real, ct: started.ciphertext)))

        // A stranger's card «decrypts» — and yields no confirmation.
        let garbage = try XCTUnwrap(MontanaFirstContact.accept(ciphertext: started.ciphertext,
                                                               contactSecret: b.secret, contactRoot: b.root),
                                    "implicit rejection: decryption with a wrong key does not refuse")
        XCTAssertNotEqual(garbage, started.secret)
        XCTAssertFalse(MontanaFirstContact.sameConfirm(
            conf, MontanaFirstContact.firstConfirm(secret: garbage, ct: started.ciphertext)),
            "garbage does not confirm — a phantom has nothing to grow from")

        // A corrupted ciphertext under one's own card does not confirm either.
        var bad = started.ciphertext; bad[7] ^= 0x01
        let badSecret = try XCTUnwrap(MontanaFirstContact.accept(ciphertext: bad,
                                                                 contactSecret: a.secret, contactRoot: a.root))
        XCTAssertFalse(MontanaFirstContact.sameConfirm(
            MontanaFirstContact.firstConfirm(secret: badSecret, ct: bad), conf))
    }

    // An empty confirmation is no confirmation: an old sender does not beget a pipe from a push.
    func testAnAbsentConfirmationNeverPasses() {
        XCTAssertFalse(MontanaFirstContact.sameConfirm("", ""), "empty does not match even itself")
        XCTAssertFalse(MontanaFirstContact.sameConfirm("", "abc"))
        XCTAssertFalse(MontanaFirstContact.sameConfirm("abc", ""))
    }
}

// -- The law of silence: a letter rings loud ⟺ there is something to show the person --
//
// Rejects a SECOND hand-written list of silent kinds: it fell behind on live typing, every
// keystroke left as a loud push with a fresh id, and the receiver got a second «Montana» banner.
final class MontanaSilenceLawTests: XCTestCase {

    func testALiveDraftRidesSilently() {
        XCTAssertTrue(isSilentLetter("\u{2063}mtdraft:{\"t\":\"pi\"}"),
                      "live typing is a signal, not a letter: it deserves no loud push")
    }

    func testControlLettersRideSilently() {
        XCTAssertTrue(isSilentLetter("\u{200B}\u{2063}r1"), "a read mark is silent")
        XCTAssertTrue(isSilentLetter("\u{200B}\u{2064}d1"), "a receipt is silent")
        XCTAssertTrue(isSilentLetter("\u{200B}\u{200B}NM:Name"), "a name is silent")
        XCTAssertTrue(isSilentLetter("\u{200B}\u{200B}AV:xxxx"), "a face is silent")
        XCTAssertTrue(isSilentLetter("\u{200B}\u{200B}TY:1"), "typing is silent")
    }

    // Rejects the law bent the other way: real letters must ring.
    func testRealLettersRingLoud() {
        XCTAssertFalse(isSilentLetter("hello"), "text rings")
        XCTAssertFalse(isSilentLetter("\u{200B}\u{200B}MD:{\"k\":\"img\"}"), "a photo rings")
        XCTAssertFalse(isSilentLetter("\u{200B}\u{200B}VC:xxx"), "voice rings")
        XCTAssertFalse(isSilentLetter("\u{2063}\u{2063}🔥"), "a sticker rings")
    }
}

// -- The meeting book: one link — one conversation, however many times it is tapped --
//
// Precedent 25.08: two taps of one link in one process begot a twin chat, and the trace could
// not name the branch. Every check here rejects a NAMED wrong implementation.
final class MontanaMeetBookTests: XCTestCase {

    private func makeBook(_ disk: NSMutableDictionary, healthy: @escaping () -> Bool) -> MontanaMeetBook {
        let b = MontanaMeetBook(name: "t", vaultKey: "k")
        b.persist = { k, d in if healthy() { disk[k] = d; return true }; return false }
        b.restore = { disk[$0] as? Data }
        return b
    }

    // Rejects «_ = setEncrypted»: a record the vault refused VANISHED silently, and a second
    // tap of the same link begot a twin. Process memory does not know how to refuse.
    func testARecordSurvivesARefusingVault() {
        let disk = NSMutableDictionary()
        var healthy = false
        let b = makeBook(disk) { healthy }
        b.put("link", "conv1")
        XCTAssertEqual(b.get("link"), "conv1", "the record lives in process memory while the vault refuses")
        XCTAssertEqual(disk.count, 0, "the vault really did refuse — this is not a test of luck")

        healthy = true
        b.drain()
        let reborn = makeBook(disk) { true }
        XCTAssertEqual(reborn.get("link"), "conv1", "the record reached the vault on recovery")
    }

    // Rejects the order «insert → filter»: the dead-record sweeper with a lagging view
    // (holds does not yet see the fresh pipe) ate the record born a moment ago.
    func testThePruneDoesNotEatTheFreshRecord() {
        let disk = NSMutableDictionary()
        let b = makeBook(disk) { true }
        b.put("root1", "fresh", pruneOld: { _ in false })
        XCTAssertEqual(b.get("root1"), "fresh", "the filter judges only the old; a fresh record is untouchable")
    }

    // Rejects dedup that depends on parsing: the meeting key is the link itself. One string —
    // one key; an unreadable invite does not rob the link of its key.
    func testTheMeetKeyIsTheLinkItself() {
        XCTAssertEqual(MontanaMeeting.meetKey("mt2abcdef"), MontanaMeeting.meetKey("mt2abcdef"),
                       "one link — one key")
        XCTAssertEqual(MontanaMeeting.meetKey("not-an-invitation"), "not-an-invitation",
                       "unreadable invite: the string itself becomes the key")
    }

    // THE PHANTOM CLASS, a live run of the cryptography. Rejects «accept = decrypt»: ML-KEM on
    // a wrong key does NOT refuse (implicit rejection, a property of the standard) — it
    // returns deterministic garbage, and without the seal one letter begets a phantom chat
    // with a secret nobody holds (precedent 25.08: 573b4987ea).
    func testAWrongCardYieldsGarbageAndTheSealRefusesIt() throws {
        let master = Data(repeating: 0x42, count: 64)
        let a = try XCTUnwrap(MontanaFirstContact.contactPair(masterSeed: master, slot: Data([1])))
        let b = try XCTUnwrap(MontanaFirstContact.contactPair(masterSeed: master, slot: Data([2])))

        let started = try XCTUnwrap(MontanaFirstContact.begin(toward: a.root), "the scanner writes to card A")
        let sealed = try XCTUnwrap(MTPipe.sealBody(Data("mid\u{0}hello".utf8), sharedSecret: started.secret))

        // Card B «opens» the stranger's letter — that is the disease…
        let garbage = MontanaFirstContact.accept(ciphertext: started.ciphertext,
                                                 contactSecret: b.secret, contactRoot: b.root)
        XCTAssertNotNil(garbage, "implicit rejection: decryption with a wrong key does NOT refuse — the disease's premise")
        XCTAssertNotEqual(garbage, started.secret, "…but the secret is garbage nobody holds")
        // …and the seal rejects garbage: proof instead of trusting decryption.
        XCTAssertNil(MTPipe.openBody(sealed, sharedSecret: try XCTUnwrap(garbage)),
                     "the body seal does not open with the garbage secret — a phantom is impossible")

        // One's own card A opens both the secret and the seal.
        let real = try XCTUnwrap(MontanaFirstContact.accept(ciphertext: started.ciphertext,
                                                            contactSecret: a.secret, contactRoot: a.root))
        XCTAssertEqual(real, started.secret, "one's own card arrives at the same secret")
        XCTAssertNotNil(MTPipe.openBody(sealed, sharedSecret: real), "and the seal opens")
    }

    // A pipe's death sweeps the book without touching other records.
    func testForgettingOneConvLeavesTheOthers() {
        let disk = NSMutableDictionary()
        let b = makeBook(disk) { true }
        b.put("l1", "convA"); b.put("l2", "convB")
        b.removeValues { $0 == "convA" }
        XCTAssertNil(b.get("l1"), "the dead conversation left the book")
        XCTAssertEqual(b.get("l2"), "convB", "another's record is untouched")
    }
}

// -- Stage 10.1: a node and a door are different quantities, and the ledger tells them apart --
//
// The frozen rows stage on purpose the very case the item was written for: TWO doors to ONE
// machine. Every assertion here rejects a named wrong implementation, not «computes something».
/// THE STATE LAWS. Name and face are not a person's words but the device's announcement about
/// its owner. An announcement has no history (S-1: the new cancels the old) and no addressee
/// without a sign of life (S-2: nobody to announce to — nothing to carry). Every check below
/// is named together with the wrong implementation it rejects.
/// WHAT IS NEVER IN THE JOURNAL AT ALL. A correspondence name and a network address are one
/// class: both tie two observations to one person. At first I scrubbed them before shipping —
/// a patch: the trace still lay whole on the phone, and every scrubbing mistake became a leak.
/// Now they never enter the journal, and the check looks exactly where a line is born.
final class MontanaDiagScrubTests: XCTestCase {

    /// Catches the implementation that scrubs only hex names and lets endpoints through —
    /// exactly the one that stood before this check.
    func testNoEndpointEverReachesTheJournal() {
        let lines = [
            "of_send|-|to=192.0.2.5:8447 ports=21",
            "net|-|ext=192.168.1.98:8447 lan=10.64.231.32",
            "node_open|-|at=192.0.2.2:443 connect_ms=606",
            "path_up|-|at=2a00:1450:4010:c07::8b port=443",
            "send|-|to=d6d868515b kind=name",
        ]
        for line in lines {
            let out = MontanaLog.hide(line)
            XCTAssertFalse(out.range(of: #"\b\d{1,3}(?:\.\d{1,3}){3}\b"#, options: .regularExpression) != nil,
                           "an IPv4 address entered the journal: \(out)")
            XCTAssertFalse(out.range(of: #"\b(?:[0-9a-fA-F]{1,4}:){2,7}[0-9a-fA-F]{1,4}\b"#, options: .regularExpression) != nil,
                           "an IPv6 address entered the journal: \(out)")
            XCTAssertFalse(out.range(of: "[0-9a-f]{10,}", options: .regularExpression) != nil,
                           "a correspondence name entered the journal: \(out)")
        }
    }

    /// The author's rule 26.08: an address leaves only the FACT of its family. Rejects both wrong
    /// implementations at once — the one that keeps a per-address tag (two observations of one
    /// address still link), and the one that erases the family too (v4-vs-v6 is the first question
    /// of every connectivity bug and it costs nothing to keep).
    func testAnEndpointLeavesOnlyItsFamilyFact() {
        XCTAssertEqual(MontanaLog.hide("to=192.0.2.5"), "to=[ip4]")
        XCTAssertEqual(MontanaLog.hide("to=192.0.2.2"), "to=[ip4]",
                       "different endpoints leave the SAME fact — nothing to link")
        XCTAssertEqual(MontanaLog.hide("at=2a00:1450:4010:c07::8b"), "at=[ip6]",
                       "the compressed form leaked a ::8b tail before this fix")
        XCTAssertEqual(MontanaLog.hide("if=fe80::1"), "if=[ip6]")
        XCTAssertEqual(MontanaLog.hide("lo=::1"), "lo=[ip6]")
        XCTAssertEqual(MontanaLog.hide("ext=192.168.1.98:8447"), "ext=[ip4]:8447",
                       "the port stays: it is a door number, not a person")
    }

    /// A correspondent name keeps its per-device tag: without one, two peers on one device are
    /// indistinguishable and the journal stops being readable. The tag is salted per device, so
    /// it links to nobody outside it; cross-device stitching rides the letter id.
    func testACorrespondentKeepsItsPerDeviceTag() {
        let a = MontanaLog.hide("to=d6d868515bcafe")
        let b = MontanaLog.hide("from=d6d868515bcafe")
        let c = MontanaLog.hide("to=72a12facb6dead")
        XCTAssertEqual(a.replacingOccurrences(of: "to=", with: ""),
                       b.replacingOccurrences(of: "from=", with: ""), "one name — one tag")
        XCTAssertNotEqual(a, c.replacingOccurrences(of: "to=", with: "to="), "different names — different tags")
        XCTAssertTrue(a.hasPrefix("to=a:"), "the tag keeps its shape: \(a)")
    }

    /// Catches the implementation that also ate what MUST stay readable: counts, durations, codes.
    func testNumbersThatSayNothingAboutAPersonSurvive() {
        let out = MontanaLog.hide("wakepush_reg|-|code=200 pairs=128 ms=15")
        XCTAssertEqual(out, "wakepush_reg|-|code=200 pairs=128 ms=15", "counters and codes are untouched")
    }
}

/// A CRASH SHIPS FIRST. The one event diagnostics exists for used to ship worst of all: after
/// a crash a person is in no hurry to reopen the app, and the record lay in their phone for
/// weeks.
final class MontanaCrashUrgencyTests: XCTestCase {

    private let launch = "2026-08-26T00:00:00Z === launch v1043 iOS 26.6 iPhone14,3 ===\n"

    /// Catches the implementation that looks for a crash in the WHOLE file: an ancient crash
    /// would rush the shipment ahead of the queue on every launch until the journal's end.
    func testOnlyThePreviousRunCounts() {
        let old = launch + "=== CRASH signal 11\n" + launch + "of_send ok\n" + launch
        XCTAssertFalse(MontanaDiagShip.crashedInLastRun(old),
                       "a crash two runs ago is no longer urgent")
        let fresh = launch + "of_send ok\n" + launch + "=== CRASH signal 11\n" + launch
        XCTAssertTrue(MontanaDiagShip.crashedInLastRun(fresh),
                      "a crash of the previous run ships first")
    }

    /// Catches the implementation that deems ANY launch urgent — the delay would be gone
    /// entirely, and launch would again share its busiest second with the shipment.
    func testAQuietRunKeepsTheMinuteOfGrace() {
        XCTAssertFalse(MontanaDiagShip.crashedInLastRun(launch + "of_send ok\nsend ok\n" + launch),
                       "a quiet run keeps the delay")
        XCTAssertFalse(MontanaDiagShip.crashedInLastRun("of_send ok\n"),
                       "the first launch after install is not a crash")
        XCTAssertFalse(MontanaDiagShip.crashedInLastRun(""), "an empty tail is not a crash")
    }

    /// A hung thread is the same thing to a person as a crash: the app stopped answering.
    func testAFrozenThreadIsAsUrgentAsACrash() {
        let hung = launch + "HANG main-thread stalled 12.4s\n" + launch
        XCTAssertTrue(MontanaDiagShip.crashedInLastRun(hung), "a hang ships first too")
    }
}

/// AN ERROR CALLS FOR THE JOURNAL — AND ONLY AN ERROR. Precedent 26.08: the node lost httpx and
/// answered 502 to every push for half an hour while the report waited its quarter of an hour.
/// Every test below names the wrong implementation it rejects.
final class MontanaFailureShipTests: XCTestCase {

    /// Rejects the implementation that has no list of errors — the one that lived before this fix.
    func testEveryFailureCallsForTheJournal() {
        XCTAssertTrue(MontanaP2PTrace.isFailure("enqueue_drop", "no-pipe to=ab"), "a letter refused")
        XCTAssertTrue(MontanaP2PTrace.isFailure("send_failed", "age=604800s"), "a letter dead of age")
        XCTAssertTrue(MontanaP2PTrace.isFailure("send_red", "age=30s tries=4"), "the retry mark lit up")
        XCTAssertTrue(MontanaP2PTrace.isFailure("dial_failed", "to=ab"), "a call that did not reach")
        XCTAssertTrue(MontanaP2PTrace.isFailure("call_ice", "failed ms=8000"), "a call that fell apart")
        XCTAssertTrue(MontanaP2PTrace.isFailure("call_ice", "disconnected ms=120"), "a call that broke off")
        XCTAssertTrue(MontanaP2PTrace.isFailure("wakepush_tx", "code=502 carry=1"), "the node is broken — 5xx")
        XCTAssertTrue(MontanaP2PTrace.isFailure("wakepush_reg", "code=500"), "on registration too")
    }

    /// Rejects the implementation that treats ROUTINE as an error: an empty box, an ordinary
    /// send, a healthy call. It would turn every minute of life into an urgent report — a storm.
    func testRoutineIsNotAFailure() {
        XCTAssertFalse(MontanaP2PTrace.isFailure("wakepush_tx", "code=404 carry=1"), "an empty box is routine")
        XCTAssertFalse(MontanaP2PTrace.isFailure("wakepush_reg", "code=200 pairs=128"), "registration passed")
        XCTAssertFalse(MontanaP2PTrace.isFailure("send", "dir=out kind=text"), "an ordinary send")
        XCTAssertFalse(MontanaP2PTrace.isFailure("call_ice", "connected ms=740"), "the call assembled")
        XCTAssertFalse(MontanaP2PTrace.isFailure("state_pointless", "kind=profile"), "law S-2 is not an error")
    }

    /// THE MOST IMPORTANT ONE. Rejects the implementation where shipping calls for itself: a failed
    /// shipment would mint a mark, the mark a new shipment, and so around until the battery dies.
    func testTheJournalNeverCallsForItself() {
        XCTAssertFalse(MontanaP2PTrace.isFailure("diag_ship", "refused=no-answer lines=64"),
                       "a failed shipment never calls for a shipment")
        XCTAssertFalse(MontanaP2PTrace.isFailure("diag_ship", "code=502 lines=64"),
                       "even a 5xx: it is the same node breakdown, already reported by the wakepush mark")
    }
}

final class MontanaStateLawTests: XCTestCase {

    private typealias E = MontanaDeliveryEngine
    private func item(_ to: String, _ kind: E.Kind, mid: String, since: Double = 0) -> E.Item {
        E.Item(to: to, chat: to, mid: mid, text: "x", silent: true, since: since, tries: 0, lastTry: 0,
               headless: nil, kind: kind)
    }

    /// Catches the implementation that PLACES a new announcement beside the old one (dedup by
    /// letter id only) — the very one that hoarded six names per correspondence.
    func testOneStatePerPairReplacesThePrevious() {
        var q: [E.Item] = []
        q = E.foldingState(q, adding: item("alice", .profile, mid: "n1"))
        q = E.foldingState(q, adding: item("alice", .profile, mid: "n2"))
        q = E.foldingState(q, adding: item("alice", .profile, mid: "n3"))
        XCTAssertEqual(q.count, 1, "a name announcement does not pile up")
        XCTAssertEqual(q.first?.mid, "n3", "the queue holds the LAST name, not the first")
    }

    /// Catches the implementation that folded state by CORRESPONDENCE alone, forgetting the
    /// kind: a name may not displace a face, nor a face a name. And the one that folded by
    /// kind, forgetting the addressee.
    func testFoldingSeparatesKindAndPeer() {
        var q: [E.Item] = []
        q = E.foldingState(q, adding: item("alice", .profile, mid: "n1"))
        q = E.foldingState(q, adding: item("alice", .picture, mid: "p1"))
        q = E.foldingState(q, adding: item("bob", .profile, mid: "n2"))
        XCTAssertEqual(q.count, 3, "name and face are different announcements; Alice and Bob are different addressees")
        q = E.foldingState(q, adding: item("alice", .profile, mid: "n9"))
        XCTAssertEqual(q.map(\.mid).sorted(), ["n2", "n9", "p1"], "exactly one announcement was replaced")
    }

    /// THE MOST IMPORTANT. Catches the implementation that extended folding to a PERSON'S
    /// WORD: two letters in a row to one person are two letters, and the second does not
    /// cancel the first. A precedent of this class already cost a live correspondence,
    /// swept away by a cleanup.
    func testHumanLettersNeverFoldEachOther() {
        var q: [E.Item] = []
        q = E.foldingState(q, adding: item("alice", .letter, mid: "m1"))
        q = E.foldingState(q, adding: item("alice", .letter, mid: "m2"))
        q = E.foldingState(q, adding: item("alice", .piece, mid: "u1"))
        q = E.foldingState(q, adding: item("alice", .piece, mid: "u2"))
        XCTAssertEqual(q.map(\.mid), ["m1", "m2", "u1", "u2"], "not one human word is lost")
    }

    /// Catches the implementation for which the MERE EXISTENCE of a correspondence counts as
    /// a sign of life: a silent introduction has no sign at all, and there is nothing to
    /// announce to it.
    func testStateWithoutAnySignOfLifeGoesNowhere() {
        let now: Double = 1_000_000
        let ttl: Double = 7 * 24 * 3600
        XCTAssertTrue(E.statePointless(kind: .profile, answered: true, aliveAt: nil, now: now, ttl: ttl),
                      "a correspondence without a single sign of freshness is not a peer")
        XCTAssertTrue(E.statePointless(kind: .picture, answered: true, aliveAt: now - ttl - 1, now: now, ttl: ttl),
                      "answered once but gone longer than a letter lives — nowhere to carry")
        XCTAssertFalse(E.statePointless(kind: .profile, answered: true, aliveAt: now - ttl + 1, now: now, ttl: ttl),
                       "answered and present — the announcement rides")
    }

    /// THE THIRD MOST IMPORTANT. Catches the implementation that accepts the BIRTH OF A PIPE
    /// as proof. That was my first version of the law, and a measurement refuted it: ten
    /// fresh dead introductions passed the filter and got eight tries each, not one receipt.
    /// An intention to meet proves nothing about the other side.
    func testBirthOfThePipeProvesNothingAboutTheOtherSide() {
        let now: Double = 1_000_000
        let ttl: Double = 7 * 24 * 3600
        XCTAssertTrue(E.statePointless(kind: .profile, answered: false, aliveAt: now, now: now, ttl: ttl),
                      "the pipe was born this second, but nobody answered — nobody to announce to")
        XCTAssertTrue(E.statePointless(kind: .picture, answered: false, aliveAt: now - 60, now: now, ttl: ttl),
                      "and one born an hour ago — the same")
        XCTAssertFalse(E.statePointless(kind: .letter, answered: false, aliveAt: nil, now: now, ttl: ttl),
                       "but a person's word rides into an unanswered correspondence — introductions begin with nothing else")
    }

    /// THE SECOND MOST IMPORTANT. Catches the implementation that extended law S-2 to a
    /// person's word: a letter, voice, picture and tombstone ride into ANY correspondence and
    /// live their full term however long it has been silent. What is cut off is exactly what
    /// the device says on its own behalf.
    func testHumanLettersRideEvenIntoSilence() {
        let now: Double = 1_000_000
        let ttl: Double = 7 * 24 * 3600
        for k: E.Kind in [.letter, .piece] {
            XCTAssertFalse(E.statePointless(kind: k, answered: false, aliveAt: nil, now: now, ttl: ttl),
                           "\(k.rawValue): a person's word is not cancelled by the peer's silence")
            XCTAssertFalse(E.statePointless(kind: k, answered: false, aliveAt: 0, now: now, ttl: ttl),
                           "\(k.rawValue): years of silence do not cancel it either")
        }
    }

    /// Catches the implementation that measures the LETTER'S AGE instead of the sign of
    /// life's: a fresh announcement must not ride into a dead correspondence; a stale one
    /// into a living one must.
    func testTheAgeMeasuredIsOfTheSignNotOfTheLetter() {
        let now: Double = 1_000_000
        let ttl: Double = 7 * 24 * 3600
        XCTAssertTrue(E.statePointless(kind: .profile, answered: true, aliveAt: 0, now: now, ttl: ttl),
                      "the freshest announcement does not ride into a vanished correspondence")
        XCTAssertFalse(E.statePointless(kind: .profile, answered: true, aliveAt: now - 60, now: now, ttl: ttl),
                       "an announcement rides into a living correspondence regardless of its own age")
    }

    /// Catches the implementation whose SETTING and CLEARING halves of the «announced» mark
    /// diverged. Exactly that happened: the face moved to key version three while clearing
    /// stayed on two — in three places at once. The failure was silent, because deleting a
    /// missing key is legal.
    func testForgettingHitsExactlyTheKeyThatWasSet() {
        let peer = "peer-under-test"
        let d = UserDefaults.standard
        d.set("face-fingerprint", forKey: E.Announced.face(to: peer))
        d.set("1", forKey: E.Announced.faceMissing(to: peer))
        d.set("some-name", forKey: E.Announced.name(to: peer))

        E.Announced.forgetFace(to: peer)
        XCTAssertNil(d.string(forKey: E.Announced.face(to: peer)), "clearing hits the same key as setting")
        XCTAssertNil(d.string(forKey: E.Announced.faceMissing(to: peer)), "the picture and its absence are two values of one fact")
        XCTAssertEqual(d.string(forKey: E.Announced.name(to: peer)), "some-name", "the face does not touch the name")

        E.Announced.forgetName(to: peer)
        XCTAssertNil(d.string(forKey: E.Announced.name(to: peer)), "the name is cleared by its own half")
        for k in [E.Announced.face(to: peer), E.Announced.faceMissing(to: peer), E.Announced.name(to: peer)] {
            d.removeObject(forKey: k)
        }
    }

    /// The mark belongs to the PAIR «my identity — the peer»: it differs per peer, otherwise
    /// announcing to one would count as announcing to all.
    func testTheMarkBelongsToThePair() {
        XCTAssertNotEqual(E.Announced.face(to: "alice"), E.Announced.face(to: "bob"))
        XCTAssertNotEqual(E.Announced.name(to: "alice"), E.Announced.face(to: "alice"))
        XCTAssertNotEqual(E.Announced.face(to: "alice"), E.Announced.faceMissing(to: "alice"))
    }

    /// Letter kinds split exactly in two, and the split is the only one ([I-10]): the device
    /// announces state, the person speaks words.
    func testKindsSplitInTwo() {
        XCTAssertTrue(E.Kind.profile.isState); XCTAssertTrue(E.Kind.picture.isState)
        XCTAssertFalse(E.Kind.letter.isState); XCTAssertFalse(E.Kind.piece.isState)
    }
}

final class MontanaPathRegistryTests: XCTestCase {

    private let moscow = Data(repeating: 0x11, count: 32)
    private let amsterdam = Data(repeating: 0x22, count: 32)
    private let neighbour = Data(repeating: 0x33, count: 32)

    private func rows() -> [MontanaP2PDirect.LiveChannel] {
        [
            .init(overlay: moscow, ref: "", ip: "door-a.example", port: 443,
                  pathKey: "door-a.example:443", door: true, ms: 107),
            .init(overlay: moscow, ref: "", ip: "door-b.example", port: 443,
                  pathKey: "wss/door-b.example:443", door: true, ms: 2167),
            .init(overlay: amsterdam, ref: "", ip: "door-c.example", port: 443,
                  pathKey: "door-c.example:443", door: true, ms: 320),
            .init(overlay: neighbour, ref: "mt1neighbour", ip: "192.168.1.5", port: 51000,
                  pathKey: "192.168.1.5:51000", door: false, ms: 4),
        ]
    }

    private var doors: Set<String> {
        ["door-a.example:443", "wss/door-b.example:443", "door-c.example:443"]
    }

    // Rejects the implementation that keys the ledger by IDENTITY: there two doors to the
    // Moscow machine write into one cell and give two paths instead of three.
    func testTwoDoorsToOneMachineAreTwoPaths() {
        XCTAssertEqual(MontanaP2PDirect.doorsHeld(rows()).count, 3,
                       "two doors to one machine are two different paths, not one")
    }

    // Rejects the implementation that counts doors as NODES: it would yield three nodes instead of two.
    func testTwoDoorsToOneMachineAreOneNode() {
        XCTAssertEqual(MontanaP2PDirect.nodesHeld(rows(), doors: doors).count, 2,
                       "behind three doors stand two machines")
    }

    // The item's main assertion. Rejects the implementation where a break erases the whole
    // node record: there, after one Moscow door goes down, one machine would remain instead
    // of two.
    func testDroppingOneDoorKeepsTheNodeAlive() {
        var live = rows()
        live.removeFirst()
        XCTAssertEqual(MontanaP2PDirect.nodesHeld(live, doors: doors).count, 2,
                       "a node lives while at least one path to it lives")
        XCTAssertEqual(MontanaP2PDirect.doorsHeld(live).count, 2,
                       "a break puts out exactly its own path and nobody else's")
    }

    // Rejects the implementation where an incoming guest counts as a door: its port is
    // ephemeral, it never was a door, and a dial that believed it would skip the real one.
    func testAnIncomingGuestIsNotADoor() {
        XCTAssertFalse(MontanaP2PDirect.doorsHeld(rows()).contains("192.168.1.5:51000"),
                       "an incoming connection is not a path we hold")
    }

    // Rejects the implementation where the named door depends on dictionary key order: the
    // trace would be unreproducible, two identical runs printing different lines.
    func testTheNamedDoorIsChosenByEndpointAndIsStable() {
        let named = MontanaP2PDirect.peersHeld(rows()).first { $0.overlay == moscow }?.pathKey
        XCTAssertEqual(named, "door-a.example:443", "which door is named is decided by the door's address")
        XCTAssertEqual(MontanaP2PDirect.peersHeld(rows()).count, 3, "one row per identity")
    }

    // One machine — one channel. Of two doors to Moscow the SLOW one is declared extra, and
    // only it. Rejects the implementation that folds by order of appearance (it would close
    // the fast one) and the one that touches Amsterdam's only door.
    func testTheSlowerDoorToTheSameMachineIsFolded() {
        let folded = MontanaP2PDirect.foldedDoors(rows()).map { $0.pathKey }
        XCTAssertEqual(folded, ["wss/door-b.example:443"], "the extra path is the slow one, and it is alone")
    }

    // The dial happens ONCE. Rejects the implementation that knocks on every door always:
    // knowing both doors lead to Moscow, the phone knocks only on the fast one and on Amsterdam.
    func testAKnownSlowerDoorIsNotKnockedWhileTheFastOneStands() {
        let all = [MontanaNodes.Node(host: "door-a.example", port: 443),
                   MontanaNodes.Node(host: "door-b.example", port: 443, dress: .websocket(path: "/ws")),
                   MontanaNodes.Node(host: "door-c.example", port: 443)]
        let book: [String: (overlay: Data, ms: Int)] = [
            "door-a.example:443": (moscow, 107),
            "wss/door-b.example:443": (moscow, 2167),
            "door-c.example:443": (amsterdam, 320)]
        let knock = MontanaNodes.doorsToKnock(all: all, held: [], book: book, failed: []).map { $0.label }
        XCTAssertEqual(knock.sorted(), ["door-a.example:443", "door-c.example:443"],
                       "a slow door to an already known machine is not knocked")

        // The fast one failed — the slow one must get its turn, or the node is lost entirely.
        let after = MontanaNodes.doorsToKnock(all: all, held: [], book: book,
                                              failed: ["door-a.example:443"]).map { $0.label }
        XCTAssertTrue(after.contains("wss/door-b.example:443"),
                      "the fast one's failure opens the road to the slow one")
    }

    // A door nothing is known about is always knocked — otherwise a new door is never learned.
    func testAnUnknownDoorIsAlwaysKnocked() {
        let fresh = MontanaNodes.Node(host: "new.example", port: 443)
        let knock = MontanaNodes.doorsToKnock(all: [fresh], held: [], book: [:], failed: []).map { $0.label }
        XCTAssertEqual(knock, ["new.example:443"], "an unknown door must be dialled")
    }

    // A folded door is ALIVE. Rejects the implementation with two words for three states:
    // there a door that answered and was closed by us as slow is called «not answering» — the
    // screen reports a refusal where none exists, and the person reads «node lost» while
    // looking at a healthy node.
    func testAFoldedDoorIsNotCalledSilent() {
        let api = MontanaNodes.Node(host: "door-a.example", port: 443)
        let cdn = MontanaNodes.Node(host: "door-b.example", port: 443, dress: .websocket(path: "/ws"))
        let dead = MontanaNodes.Node(host: "door-c.example", port: 443)
        let book: [String: (overlay: Data, ms: Int)] = [
            "door-a.example:443": (moscow, 80),
            "wss/door-b.example:443": (moscow, 2254)]
        let held: Set<String> = ["door-a.example:443"]
        let heldNodes: Set<Data> = [moscow]
        XCTAssertEqual(MontanaNodes.state(of: api, held: held, book: book, heldNodes: heldNodes), .open)
        XCTAssertEqual(MontanaNodes.state(of: cdn, held: held, book: book, heldNodes: heldNodes), .sameMachine,
                       "a door to an already held machine is alive, not silent")
        XCTAssertEqual(MontanaNodes.state(of: dead, held: held, book: book, heldNodes: heldNodes), .silent,
                       "a door nothing is known about and not held is indeed silent")
    }

    // A door is a name, a port AND the wire's dress: bare and behind a delivery network on
    // one name are different paths. Rejects the «name+port» key that would fold them into one.
    func testTheDoorKeyCarriesTheDress() {
        XCTAssertNotEqual(MontanaNodes.Node(host: "d.example", port: 443, dress: .raw).label,
                          MontanaNodes.Node(host: "d.example", port: 443, dress: .websocket(path: "/ws")).label,
                          "the wire's dress is part of a door's identity")
    }
}

// ── Stage 4 (§5.4): NAT-traversal frame codecs — deterministic unit tests ──
final class MontanaNATTests: XCTestCase {
    // LOCAL-RANDOM-OK: an input drawn for a test, inside the test target; no quantity of the protocol stands on it
    private func rid() -> Data { Data((0..<32).map { _ in UInt8.random(in: 0...255) }) }   // LOCAL-RANDOM-OK: test input

    func testPunchPacketRoundtripAndMagic() {
        let src = rid()
        var nonce = Data(count: 16); for i in 0..<16 { nonce[i] = UInt8(i) }
        let pkt = MontanaPunchPacket(srcOverlay: src, nonce: nonce)
        let back = MontanaPunchPacket.decode(pkt.encode())
        XCTAssertEqual(back?.srcOverlay, src)
        XCTAssertEqual(back?.nonce, nonce)
        XCTAssertNil(MontanaPunchPacket.decode(Data([0,1,2,3]) + src + nonce), "a wrong magic is refused")
    }

    func testPunchInfoRoundtrip() {
        let peer = rid()
        let ep = MontanaEndpoint(kind: .directV6, endpoint: "[2a00::9]:41234")
        let back = MontanaNATMsg.decodePunchInfo(MontanaNATMsg.encodePunchInfo(peer: peer, ep: ep))
        XCTAssertEqual(back?.peer, peer)
        XCTAssertEqual(back?.ep.endpoint, "[2a00::9]:41234")
        XCTAssertEqual(back?.ep.kind, .directV6)
    }

    func testRelayRoundtrip() {
        let dst = rid(); let frame = Data((0..<50).map { UInt8($0) })
        let back = MontanaNATMsg.decodeRelay(MontanaNATMsg.encodeRelay(dst: dst, frame: frame))
        XCTAssertEqual(back?.dst, dst)
        XCTAssertEqual(back?.frame, frame)
    }

    func testAddrParseV4AndV6() {
        let v4 = MontanaEndpointParse.hostPort("192.0.2.1:8444")
        XCTAssertNotNil(v4); XCTAssertEqual(v4?.port.rawValue, 8444)
        let v6 = MontanaEndpointParse.hostPort("[2a00:1450:4010::200e]:443")
        XCTAssertNotNil(v6); XCTAssertEqual(v6?.port.rawValue, 443)
        XCTAssertNil(MontanaEndpointParse.hostPort("garbage"))
    }
}

// ── The mesh room, the overlay book and the copy's key. The VPN's own tests left with the VPN for its own app, Montana VPN
// (the author's word 08.10.2026): they live in that fork beside the code they prove. ──
final class MontanaNetworkTests: XCTestCase {
    // THE MESH WALL'S WORD (29.09): the cell's body reads back whole; the name and the words are cut at a letter's edge, never
    // inside one; a body of another version or of empty words is no word; the row names its writer from its own ref. The
    // permutation: the moment's four bytes are big-endian -- a reader that took them little-endian reads another moment -- and
    // two words differing only in the run are two writers.
    func testMeshRoomWordReadsBack() throws {
        let run = Data([1, 2, 3, 4, 5, 6, 7, 8])
        let w = MTMeshRoom.Word(run: run, at: 0x01020304, name: "Анна", text: "привет всем 👋")   // CYRILLIC-DATA-OK: a person's own words
        let body = MTMeshRoom.encode(w)
        XCTAssertEqual(body[body.startIndex], MTMeshRoom.version)
        XCTAssertEqual(Array(body[9..<13]), [1, 2, 3, 4])
        XCTAssertEqual(MTMeshRoom.decode(body), w)
        var other = body; other[other.startIndex] = 2
        XCTAssertNil(MTMeshRoom.decode(other))
        XCTAssertNil(MTMeshRoom.decode(MTMeshRoom.encode(MTMeshRoom.Word(run: run, at: 1, name: "A", text: "   "))))
        XCTAssertNil(MTMeshRoom.decode(Data([1, 2, 3])))
        let long = String(repeating: "я", count: 700)   // CYRILLIC-DATA-OK: two bytes a letter
        let cut = MTMeshRoom.cut(long, MTMeshRoom.wordBytes)
        XCTAssertEqual(cut.utf8.count, MTMeshRoom.wordBytes); XCTAssertEqual(cut.count, MTMeshRoom.wordBytes / 2)
        XCTAssertEqual(MTMeshRoom.cut("ab👋", 5), "ab")   // the four-byte letter does not fit whole: it is left out, never split
        let ref = MTMeshRoom.ref(of: w)
        XCTAssertEqual(MTMeshRoom.name(of: ref), "Анна")   // CYRILLIC-DATA-OK
        XCTAssertNil(MTMeshRoom.name(of: "a:peer"))
        XCTAssertEqual(MTMeshRoom.name(of: "mesh:0102:a:b"), "a:b")   // a name may hold the separator
        XCTAssertNotEqual(MTMeshRoom.ref(of: MTMeshRoom.Word(run: Data(repeating: 9, count: 8), at: 1, name: "Анна", text: "x")), ref)   // CYRILLIC-DATA-OK
        // THE CELL'S TAIL (the critic, 29.09): a long word ending in a full stop reads back whole from a cell nobody passed on,
        // and from one a hop sealed -- the hop's seal and count are taken off by the mesh (MontanaBLEMesh.body), the zero by
        // the room. Rejects the cell without its zero count: its last byte, a full stop, would be read as a count of 46 seals.
        let long2 = MTMeshRoom.Word(run: run, at: 7, name: "A", text: String(repeating: "word ", count: 150) + "end.")
        let bare = MTMeshRoom.cell(long2)
        XCTAssertEqual(bare.last, 0)
        XCTAssertEqual(MTMeshRoom.word(ofBody: MontanaBLEMesh.body(of: bare)), long2)
        var hopped = MontanaBLEMesh.body(of: bare); hopped.append(Data(repeating: 7, count: 16)); hopped.append(1)
        XCTAssertEqual(MTMeshRoom.word(ofBody: MontanaBLEMesh.body(of: hopped)), long2)
        XCTAssertNil(MTMeshRoom.word(ofBody: MTMeshRoom.encode(long2)))
        // A word's name is its content: the same word under another cell id is one row; another moment is another word.
        XCTAssertEqual(MTMeshRoom.mid(of: long2), MTMeshRoom.mid(of: MTMeshRoom.decode(MTMeshRoom.encode(long2))!))
        XCTAssertNotEqual(MTMeshRoom.mid(of: long2), MTMeshRoom.mid(of: MTMeshRoom.Word(run: run, at: 8, name: "A", text: long2.text)))
    }

    // THE MESH WALL'S ITEMS (29.09): the item's word reads back whole, bare and through a hop's seal; a size past the radio's
    // measure and pieces that do not match the size are no word; the pieces laid in their order are the item's bytes again,
    // and in another order are not; a piece past its count, a piece past its size and an ask past forty are refused or cut.
    // Rejects a reader that took the size little-endian (another size, another count of pieces) and one that joined pieces
    // by arrival rather than by index.
    func testMeshRoomItemsReadBack() throws {
        let run = Data([9, 8, 7, 6, 5, 4, 3, 2])
        let data = Data((0 ..< 2500).map { UInt8($0 % 251) })
        let m = MTMeshRoom.Media(kind: "aud", item: Data(repeating: 0xAB, count: 16), size: data.count, pieces: MTMeshRoom.pieceCount(data.count),
                                 sha: Data(repeating: 1, count: 32), ext: "m4a", fileName: "", durMs: 4200)
        let w = MTMeshRoom.Word(run: run, at: 0x0A0B0C0D, name: "Мира", text: "подпись")   // CYRILLIC-DATA-OK: a person's own words
        let cell = MTMeshRoom.mediaCell(w, m)
        XCTAssertEqual(cell.last, 0); XCTAssertEqual(cell.first, MTMeshRoom.mediaVersion)
        let back = try XCTUnwrap(MTMeshRoom.media(ofBody: MontanaBLEMesh.body(of: cell)))
        XCTAssertEqual(back.0, w); XCTAssertEqual(back.1, m); XCTAssertEqual(back.1.pieces, 3)
        var hopped = MontanaBLEMesh.body(of: cell); hopped.append(Data(repeating: 5, count: 16)); hopped.append(1)
        XCTAssertEqual(MTMeshRoom.media(ofBody: MontanaBLEMesh.body(of: hopped))?.1, m)
        XCTAssertNil(MTMeshRoom.word(ofBody: MontanaBLEMesh.body(of: cell)))   // the word reader of version 1 does not take it
        let big = MTMeshRoom.Media(kind: "vid", item: m.item, size: MTMeshRoom.itemMax + 1, pieces: MTMeshRoom.pieceCount(MTMeshRoom.itemMax + 1),
                                   sha: m.sha, ext: "mov", fileName: "", durMs: 0)
        XCTAssertNil(MTMeshRoom.media(ofBody: MTMeshRoom.mediaCell(w, big)))
        let wrong = MTMeshRoom.Media(kind: "aud", item: m.item, size: data.count, pieces: 4, sha: m.sha, ext: "m4a", fileName: "", durMs: 0)
        XCTAssertNil(MTMeshRoom.media(ofBody: MTMeshRoom.mediaCell(w, wrong)))
        // The pieces: each reads back, and laid by index they are the item's bytes again.
        var joined = Data()
        for i in 0 ..< m.pieces {
            let c = MTMeshRoom.pieceCell(item: m.item, index: i, count: m.pieces, bytes: MTMeshRoom.bytesOfPiece(data, i))
            let p = try XCTUnwrap(MTMeshRoom.piece(ofBody: MontanaBLEMesh.body(of: c)))
            XCTAssertEqual(p.item, m.item); XCTAssertEqual(p.index, i); XCTAssertEqual(p.count, m.pieces)
            joined.append(p.bytes)
        }
        XCTAssertEqual(joined, data)
        XCTAssertNotEqual(MTMeshRoom.bytesOfPiece(data, 1) + MTMeshRoom.bytesOfPiece(data, 0) + MTMeshRoom.bytesOfPiece(data, 2), data)
        XCTAssertEqual(MTMeshRoom.bytesOfPiece(data, 2).count, 2500 - 2 * MTMeshRoom.pieceBytes)
        XCTAssertNil(MTMeshRoom.piece(ofBody: MTMeshRoom.pieceCell(item: m.item, index: 3, count: 3, bytes: Data([1]))))
        XCTAssertNil(MTMeshRoom.piece(ofBody: MTMeshRoom.pieceCell(item: m.item, index: 0, count: 1, bytes: Data(count: MTMeshRoom.pieceBytes + 1))))
        XCTAssertNil(MTMeshRoom.piece(ofBody: MTMeshRoom.pieceCell(item: m.item, index: 0, count: MTMeshRoom.piecesMax + 1, bytes: Data([1]))))
        // The ask: read back, cut at forty.
        let a = try XCTUnwrap(MTMeshRoom.ask(ofBody: MTMeshRoom.askCell(item: m.item, missing: [2, 0, 1])))
        XCTAssertEqual(a.item, m.item); XCTAssertEqual(a.missing, [2, 0, 1])
        XCTAssertEqual(MTMeshRoom.ask(ofBody: MTMeshRoom.askCell(item: m.item, missing: Array(0 ..< 100)))?.missing.count, 40)
        XCTAssertNil(MTMeshRoom.ask(ofBody: MTMeshRoom.askCell(item: m.item, missing: [])))
    }

    func testAddrSplitV4AndV6() {
        let a = MontanaEndpointParse.split("192.168.1.7:8443")
        XCTAssertEqual(a?.ip, "192.168.1.7"); XCTAssertEqual(a?.port, 8443)
        let b = MontanaEndpointParse.split("[2a00:1450:4010:c07::71]:52001")
        XCTAssertEqual(b?.ip, "2a00:1450:4010:c07::71"); XCTAssertEqual(b?.port, 52001)
        XCTAssertNil(MontanaEndpointParse.split("192.168.1.7"))
        XCTAssertNil(MontanaEndpointParse.split("2a00:1450::71"))     // bare v6, no port -> not an endpoint
        XCTAssertNil(MontanaEndpointParse.split(""))
    }

    // ── SSOT address book: one store binds peerRef, overlay and endpoints ──

    func testOverlayBookBindsAndOrdersEndpoints() {
        let book = MontanaOverlayBook.shared
        let peerRef = "mtTESTBOOK000000000000000001"
        var ov = Data(count: 32); ov[0] = 0xAB; ov[31] = 0xCD
        book.bind(ref: peerRef, overlay: ov)
        XCTAssertEqual(book.overlay(forRef: peerRef), ov)
        XCTAssertEqual(book.ref(forOverlay: ov), peerRef)

        book.learn(ref: peerRef, ip: "192.168.1.50", port: 9001, source: "bonjour")   // LAN-scoped
        book.learn(ref: peerRef, ip: "2a02:6b8::1", port: 9002, source: "dht")        // globally routable
        let eps = book.endpoints(ref: peerRef)
        XCTAssertEqual(eps.count, 2)
        XCTAssertTrue(eps[0].isGlobal, "a globally routable endpoint must be dialled before a LAN one")
        XCTAssertEqual(eps[0].hostPort, "[2a02:6b8::1]:9002")
        XCTAssertEqual(eps[1].hostPort, "192.168.1.50:9001")

        book.learn(ref: peerRef, ip: "192.168.1.50", port: 9001, source: "wire")      // refresh, not duplicate
        XCTAssertEqual(book.endpoints(ref: peerRef).count, 2)
        XCTAssertNil(book.overlay(forRef: "mtNOSUCHPEER"))
    }

    func testOverlayBookRejectsLoopbackAndEmpty() {
        let book = MontanaOverlayBook.shared
        let peerRef = "mtTESTBOOK000000000000000002"
        book.learn(ref: peerRef, ip: "127.0.0.1", port: 9000, source: "wire")
        book.learn(ref: peerRef, ip: "", port: 9000, source: "wire")
        book.learn(ref: peerRef, ip: "10.0.0.2", port: 0, source: "wire")
        XCTAssertTrue(book.endpoints(ref: peerRef).isEmpty)
    }

    // ------------------------------------------------------------------------------------------
    // THE CARRIER'S WRAP (RFC 1928 s 7), against an oracle outside this codebase. The endpoint is the
    // MIP's own binding vector -- 203.0.113.7:51820 -- whose address and port bytes the MIP s 12 writes
    // as "cb007107 ca6c"; the same bytes were recomputed by hand from the standard's text before this
    // test was written. A vector computed by the code it checks certifies nothing (Pass 25).
    //
    // What these two vectors REFUSE: an implementation that writes the port in little-endian order (it
    // would produce 6c ca and fail the first assertion), one that forgets the reserved pair or the
    // fragment byte (the frame shifts and the address reads as 00 00 01 cb), and one that assembles
    // fragments instead of dropping them (the second assertion would return a value instead of nothing).
    // The key that seals a copy is a value a SECOND implementation must reproduce, or two clients
    // write copies neither of them can open. The vector was computed outside this code (RFC 5869
    // HKDF-SHA-256) over a root of 0x55 bytes — not a palindrome of zeros, so a root read from the
    // wrong end fails here instead of passing over zeros.
    func testBackupKeyKAT() {
        XCTAssertTrue(MontanaBackup.keyKAT(), "the container key drifted from the frozen vector")
        XCTAssertTrue(MTRetiredRow.tokenKAT(), "the retired row's token drifted from the table's frozen vector")
    }
}
