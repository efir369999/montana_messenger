import Foundation
import CryptoKit

// Stage 2 (spec s.3 §13): ONE reachability-driven delivery engine.
//
// Consolidates the three legacy retry paths for guaranteed text into a single sealed queue: •
// scheduleDeliveryCheck (15s/30s ×2 timer) • awaitingSweep (90s ×6, foreground-driven) • outbox
// (0.5s→60s backoff, dequeue on wire-sent)
//
// Invariants: • Dequeue ONLY on a confirmed delivery receipt (confirmDelivered) — never on wire-sent. •
// Driven by peer reachability (.montanaPeerUp) first, enqueue, and a foreground/backstop tick. • Dedup
// by mid at the receiver makes a re-send over any road harmless. • The queue is sealed at rest
// (MontanaLocalVault / ChaCha20 under the device key). Retention: the carriage (carryDays, at least 30
// days — the author's word 07.10) is the ONE end of a queued letter. Attempts do not kill: a letter the
// node has not taken knocks on the ramp (1-2-4-8-16-20s) and then every twenty seconds for its whole
// carriage (20.09: no floor); a letter the node holds waits for its receipt on a sparse rhythm (5 min;
// also on every peerUp) until the receipt arrives or the carriage ends — then it leaves «sent», and
// only a letter no node ever took turns red (MTRefusal.neverLeft). No clock paints red.
//
// Concurrency model mirrors E2E: a private serial queue owns the read-modify-write of the pending list;
// UI/store mutations hop to the main actor. Callable from any context (no @MainActor on the API).
final class MontanaDeliveryEngine {
    static let shared = MontanaDeliveryEngine()
    weak var store: ChatStore?
    /// Reachability is the ONLY driver of catch-up delivery, and the queue itself listens to
    /// it. A second listener of the same event would be a second engine: one peer appearance —
    /// one move, and the move is here.
    private init() {
        NotificationCenter.default.addObserver(forName: .montanaPeerUp, object: nil, queue: nil) { note in
            guard let a = note.userInfo?["address"] as? String, !a.isEmpty else { return }
            MontanaDeliveryEngine.shared.onPeerUp(a)
            MontanaWakePush.fetchBoxKick()   // showed up at the node — collect everything waiting (delivery on appearance)
            // A CALL OUTRANKS AN INTRODUCTION. A peer appearance broadcasts the name and face to
            // EVERY known correspondent on the main queue — eight letters in a row, each with
            // its encryption. A measurement caught that volley in the very seconds a call was
            // waiting to be answered: the node channel dropped and rose again, «peer appeared»
            // fired for everyone, and the call went to the back of the line. While a call is
            // being assembled, introductions wait: their move is next.
            if !MontanaCall.isBusy {
                Task { @MainActor in E2E.shared.resendProfileOnReconnect(to: a) }   // name and face catch up by the same move
            }
        }
        // An incoming letter is part of DELIVERY, not of the screen, and the same queue listens
        // for it. It used to arrive, break the seal, find its pipe — and get posted as an event
        // NOBODY in this tree subscribed to: the receiver lived in the screen body and did not
        // survive the tree merge. Hence «sent, and nothing arrived»: the letter reached the
        // device and never entered the app, no receipt was born, the sender's queue never
        // settled and resent eight times. A screen can be replaced wholesale; delivery cannot —
        // so the receiver stands here.
        NotificationCenter.default.addObserver(forName: .montanaIncoming, object: nil, queue: .main) { note in
            guard let from = note.userInfo?["from"] as? String, !from.isEmpty,
                  let text = note.userInfo?["text"] as? String else { return }
            let mid = note.userInfo?["mid"] as? String ?? UUID().uuidString
            MontanaDeliveryEngine.shared.receive(from: from, mid: mid, text: text,
                                                 senderName: note.userInfo?["senderName"] as? String,
                                                 senderGlyph: note.userInfo?["senderGlyph"] as? String,
                                                 transport: note.userInfo?["transport"] as? String,
                                                 quoteText: note.userInfo?["quoteText"] as? String,
                                                 quoteMid: note.userInfo?["quoteMid"] as? String,
                                                 linkPreview: note.userInfo?["linkPreview"] as? String,
                                                 sentAt: note.userInfo?["sentAt"] as? Double)
        }
        // The wire said which transport the frame actually left by — the bubble's tag is refined
        // by fact, not by what it looked like when the letter was created.
        NotificationCenter.default.addObserver(forName: .montanaSent, object: nil, queue: .main) { note in
            guard let ref = note.userInfo?["address"] as? String,
                  let mid = note.userInfo?["mid"] as? String,
                  let tr = note.userInfo?["transport"] as? String else { return }
            MontanaDeliveryEngine.shared.store?.setTransport(chat: ref, mid: mid, transport: tr)
        }
    }

    /// THE MOMENT OF A LETTER, DECIDED IN ONE PLACE. The label a person reads and the place the row
    /// stands in tell one story ([C-1]), and both come from the letter's OWN moment, never from the
    /// moment this phone happened to pick it up. Two sources, in order: the birth millisecond in the
    /// letter's name, and — for a build whose names carry none — the moment the SENDER handed the
    /// letter to the node (the box keeps it). Only when neither is known does the arrival stand in,
    /// and then it is the honest best we have. Measured 01.09: two pictures sent at 17:49 from a
    /// build that stamps no name wore 18:47 — the minute this phone woke and collected them.
    static func letterMoment(mid: String, sentAt: Double?) -> Double {
        if let born = ChatStore.birthMs(fromMid: mid) { return born }
        if let sentAt, sentAt > 0 { return sentAt }
        return Date().timeIntervalSince1970
    }

    /// Letters that arrived before the history was read — replayed in arrival order the moment it is.
    @MainActor private var parkedInbound: [() -> Void] = []
    @MainActor func replayParkedInbound() {
        guard !parkedInbound.isEmpty else { return }
        let p = parkedInbound; parkedInbound = []
        MontanaTrace.mark("inbound_replay", "n=\(p.count) — the history is read, the parked letters land")
        for f in p { f() }
    }
    /// A letter arrived. One entrance for all transports: wire and radio bring it here, and from
    /// here it walks the same road as any message — through append, which parses the hidden
    /// marks itself and itself sends the receipt that settles the sender's queue.
    @MainActor
    func receive(from: String, mid: String, text: String, senderName: String? = nil, senderGlyph: String? = nil,
                 transport: String?,
                 quoteText: String? = nil, quoteMid: String? = nil, linkPreview: String? = nil,
                 sentAt: Double? = nil) {
        // A WORD OF THEIRS ENDS THE INTRODUCTION (26.09): every road lands here, so the proof is read here, before
        // the row lands and its receipt leaves -- a receipt to a peer still in the introduction waits for the pipe.
        // The queue turns at once from the knock at their point to the node and the wake.
        if MTPipeBook.firstContactDone(from) { drainAll() }
        guard let store else { MontanaTrace.mark("ui_drop", mid: mid, "store not attached"); return }
        // THE FEED ANSWERS ONLY ONCE IT IS READ (17.09, the critic): a letter drained from the box
        // before the history stood asked an empty feed «is this a copy?», was appended as new, marked
        // the chat unread and rang the badge — and the merge kept that unread over the read one (T1
        // 06:37:28Z: five copies of read letters, at every launch of the day). Until the history is
        // read the letter waits here, in arrival order, and lands the moment it is; nothing is judged
        // on emptiness. One door for the box, the live channel and the extension's handoff.
        if !store.historyLoaded {
            parkedInbound.append { [weak self] in
                self?.receive(from: from, mid: mid, text: text, senderName: senderName, senderGlyph: senderGlyph,
                              transport: transport, quoteText: quoteText, quoteMid: quoteMid, linkPreview: linkPreview, sentAt: sentAt)
            }
            MontanaTrace.markFolded("inbound_parked", "history not read yet n=\(parkedInbound.count)", window: 10)
            return
        }
        // A BLOCKED PERSON REACHES NOTHING — asked at the door the bytes come through, before the
        // copy check, the receipt, the name, the row and the banner (measured 15.09 13:10: the
        // feed refused the row, and this door had already rung the banner and repeated the receipt).
        if store.refuses(from) {
            // A letter (not a passing control word) is buried under the feed's tombstone: a resend
            // after an unblock meets it and is never shown — the reference delivers it never.
            if !isControlMarker(text) { store.deletedMids.insert("mid:" + mid) }
            MontanaTrace.markFolded("rx_blocked", "door peer=\(String(from.prefix(10)))", window: 60, key: "door:" + from)
            return
        }
        let sid = "mid:\(mid)"
        // A control letter that already spoke is not heard twice (the box repeats; 15.09 13:38).
        // Call and draft words carry a fresh name on every copy and pass; the rest are named once.
        // A ROW LETTER IS NEVER A CONTROL WORD HERE (1638): media, voice and stickers dedup by the
        // row's presence below, not by the once-applied ledger — the ledger kept the NAME of a media
        // letter after its row was gone, and the same letter re-sent was refused forever («control
        // letter already applied», T2 20:13:11Z).
        if isControlMarker(text), !text.hasPrefix(callSignalMark), !text.hasPrefix(draftSignalMark), !text.hasPrefix(ringMark),
           !text.hasPrefix(mediaMark), !text.hasPrefix(voiceMark), !text.hasPrefix(stickerMark),
           store.controlSeen(sid) {
            MontanaTrace.mark("rx_dup", mid: mid, "control letter already applied")
            return
        }
        // A copy of the same letter over another transport is not a second letter.
        if store.messages[from]?.contains(where: { $0.msgId == sid }) == true {
            if let qt = quoteText, !qt.isEmpty { store.enrichQuote(from, sid: sid, qt: qt, qm: quoteMid) }
            if let lp = linkPreview, !lp.isEmpty { store.enrichLinkPreview(from, sid: sid, lp: lp) }
            // A copy is not a second letter, but it is not silence either. The sender waits
            // for «I have it» and resends forever without it: measured 24.08 — the letter LAY
            // in the first phone's feed while the seventeenth resent it forty-three times in
            // two and a half minutes, then marked a delivered letter «Retry». So the answer
            // «have it» repeats as many times as it is asked — through the ONE receipt door,
            // which itself refuses to speak for a media file it cannot see on disk yet
            // (precedent 26.08: this road once receipted a still-downloading video, and the
            // sender swept the chunks from under the receiver).
            // THE SAME LETTER WITH NEW CARGO REFILLS ITS ROW (1638, the author's invariant: what stands
            // in the sender's chat stands in the receiver's): a media row without its file takes the
            // copy's manifest — the sender re-uploaded under the same name — and the assembly road
            // receipts when the file is whole. Nothing is erased, nothing is doubled.
            if text.hasPrefix(mediaMark), let row = store.messages[from]?.first(where: { $0.msgId == sid }),
               let f = row.videoFile ?? row.imageFile ?? row.audioFile ?? row.docFile, !MontanaMediaStore.exists(f) {
                MontanaTrace.mark("rx_refill", mid: mid, "the row stands without its file — the copy's cargo is taken")
                store.reconstructMedia(from, body: String(text.dropFirst(mediaMark.count)), isFromMe: false,
                                       time: row.time, msgId: sid, senderRef: row.senderRef, transport: transport)
                return
            }
            // THE LINE NAMES WHAT THE DOOR DID (23.09): it said «receipt repeated» while the door,
            // answering once per process life, sent nothing — five letters of iPhone 15 knocked 43
            // times at T1, every copy written as answered. The door answers every ask now, one answer
            // in flight per letter, and this line carries the door's own word.
            if MTRowLetter.changesRow(text) { MTHeldLetters.note(mid) }
            Task { await MainActor.run {
                let answer = store.sendDeliveryReceipt(from, msgId: sid, isFromMe: false, text: text)
                MontanaTrace.mark("rx_dup", mid: mid, "copy — the row already exists, receipt \(answer.rawValue)")
            } }
            return
        }
        // THE SENDER'S NAME FROM THE ENVELOPE lands only now — past the copy check, and never
        // from a call word: a ring or a signal names its caller inside the call machine alone
        // (onCallerIdentity), where a refused word — an echo of one's own — names nobody.
        if !text.hasPrefix(ringMark), !text.hasPrefix(callSignalMark) {
            // The envelope's word is a WITNESS of the person's name at the moment the letter was sealed
            // (21.09): it enters the book with that moment, and a letter that slept in the box cannot
            // rename a person back past a fresher word.
            if let sn = senderName, !sn.isEmpty, sn.count <= 64 { store.setPeerName(ref: from, name: sn, at: ChatStore.birthMs(fromMid: mid) ?? sentAt ?? 0, source: "envelope") }
            // The envelope's glyph is buried unread: the face is derived from the name ([C-1], 20.09).
        }
        // A missed-call marker letter is an ORDINARY feed row with call styling: the same
        // sender mid, the same durable feed dedup, the same receipt as any letter (SSOT; the
        // author's word 22.08: the two sides' chats may not diverge). The old side road
        // (logCall past the feed) had neither mid dedup nor a receipt — the sender resent
        // forever, and every relaunch begot a duplicate row.
        var text = text
        var missedSeed: String? = nil
        var missedVideo = false
        if text.hasPrefix(missedCallMark) {
            let (seed, video) = MontanaMissedCall.letter(text)
            // «Seen» means dead OR alive: the letter races the ring itself (measured 09.09
            // 11:47: the caller gave up before the callee's ring even arrived, the letter
            // landed mid-ring) — a call this device is showing needs no letter about it.
            if !seed.isEmpty, MontanaCall.isDeadSeed(seed) || MontanaMissedCall.state(seed) == "alive" {
                // The call was seen alive — the row already lies in the feed. The letter is
                // dropped, but the RECEIPT goes out: without it the sender keeps the letter
                // queued and resends forever.
                MontanaTrace.mark("missed_letter", mid: mid, "dup-seed — receipt without a row")
                // The letter is one road too many for a call this phone has already served — and it
                // may have left a banner behind it (an older sender still sends it loud, and the
                // extension's silence shows the node's «New message»). The banner goes with the row.
                MontanaCall.sweepCallBanners(mids: [mid, "mid:" + mid])
                Task { await MainActor.run { store.sendDeliveryReceipt(from, msgId: sid, isFromMe: false, text: "call") } }
                return
            }
            MontanaCall.burySeed(seed)
            missedSeed = seed; missedVideo = video
            let payload: [String: Any] = ["v": video, "inc": true, "dur": 0, "miss": true]
            if let d = try? JSONSerialization.data(withJSONObject: payload),
               let j = String(data: d, encoding: .utf8) { text = callMark + j }
            MontanaTrace.mark("missed_letter", mid: mid, "row from=\(String(from.prefix(10)))")
        }
        // Whether the letter landed in the feed is answered by the FEED itself, and its answer
        // is the only one ([C-1]). createdAt = the SENDER'S TIME from the letter name (ordered
        // by typing, not by receipt); an old letter without a time in its name — moment of
        // receipt, as before.
        let born = Self.letterMoment(mid: sid, sentAt: sentAt)
        // The label the person reads says WHEN IT WAS SENT — the same birth the row is
        // sorted by. The arrival moment used to stand here: a letter that slept in the node
        // box wore 7:56 while standing above a 7:31 call it preceded (T1, 29.08).
        var row = Message(text: text, isFromMe: false, time: hhmm(at: born),
                          replyText: (quoteText?.isEmpty == false) ? quoteText : nil,
                          deliveryStatus: .delivered, msgId: sid,
                          createdAt: born,
                          replyToId: store.localId(forMid: quoteMid, chat: from),
                          transport: transport)
        row.linkPreview = linkPreview
        var landed = false
        // THE LANDING NAMES THE WORD IT LANDS (23.09: T3 on 1915 held 194 ms inside a landing and named no part of it):
        // ONE step, «rx:» and the word's own kind by the one classifier of the diary (the critic 24.09: a step nested
        // under «rx:append» wrote a second line, and its bare kind — «receipt», «draft» — read as append's own steps);
        // append names its branches inside it.
        MontanaMainProbe.step("rx:" + MontanaNotify.kind(for: text)) { landed = store.append(from, row) }
        // A service signal does not land in the feed — the feed itself discards it; so the
        // journal calls it handled, not «placed». One line for both cases sent people hunting
        // for a bubble that does not exist. THE FEED'S OWN ANSWER DECIDES (the critic 24.09): a sticker
        // wears a service mark and lands as a row, and the mark alone called it a signal.
        if landed {
            MontanaTrace.mark("ui_append", mid: mid, "kind=\(MontanaNotify.kind(for: text)) from=\(String(from.prefix(10)))")
            MTHeldLetters.note(mid)
        } else {
            // A VOLLEY OF SERVICE WORDS IS A COUNT (29.09: 396 such lines in sixteen minutes of one phone's trace).
            let kind = MontanaNotify.kind(for: text)
            MontanaTrace.markFolded("ui_signal", "kind=\(kind) from=\(String(from.prefix(10)))", window: 2, key: kind)
        }
        // A conversation enters the list by the same event that always created it — but ONLY by
        // a letter. An unconditional declaration used to stand here, quarrelling with the line
        // above: the feed said «this is not a message» and kept nothing, while the list created
        // a row that same instant. The list won, and a person got a conversation out of nowhere —
        // empty, with an unread badge nothing could clear. Card introductions ended exactly
        // there: the peer opened the just-created chat, a read receipt left it, and the receipt
        // begot the phantom.
        if landed {
            NotificationCenter.default.post(name: .montanaInbound, object: nil,
                                            userInfo: ["address": from, "text": text])
            // A letter landing in the OPEN chat is read the moment it lands — the receipt
            // must not wait for a re-entry. Same single road as entering the chat (markRead,
            // [C-1]): the receipt used to be born only by onAppear, so two people sitting in
            // one conversation never gave each other the blue checkmarks (measured 26.08:
            // receipts appear in the trace only at entry moments).
            if ChatStore.openConvNow == from, MTForeground.active { store.markRead(from) }   // under a locked phone it waits for the return (23.09)
        }
        // The banner comes AFTER the letter is already in the conversation. Service marks are
        // sifted inside. Only the judge with the shown-banner ledger decides «has it already
        // rung» ([C-1], P-26): the NSE writes every shown banner there, present() dedups by it.
        // The old shortcut «push ⇒ the NSE already rang» was a LIE for silent pushes: a recalled
        // loud one (replaced at Apple) and a repeat under the same name (node: one mid — one
        // ring) arrive in the background, the NSE is not invoked — and the letter stayed with
        // no ring AT ALL (precedent 24.08: the repeat arrived silently).
        if let ms = missedSeed {
            // A missed call has ONE banner road ([C-1]): the seed notebook, not the letter ledger —
            // the extension, the letter and the ring itself all answer to the same seed.
            MontanaTrace.mark("notify_skip", mid: mid, "why=missed-call-one-banner seed=\(String(ms.prefix(8)))")
            if landed { MontanaCallWiring.postMissedCallBanner(peer: from, video: missedVideo, seed: ms) }
        } else if text.hasPrefix(mediaMark), text.contains("\"mref\"") {
            // The bubble comes FIRST (the author's invariant): a blob-manifest letter has
            // no bubble until its manifest is fetched — the banner rings when the bubble
            // lands (the media branch presents it), never before.
            MontanaTrace.mark("notify_skip", mid: mid, "why=banner-after-bubble")
        } else {
            MontanaNotify.present(from: from, chat: from, text: text, mid: mid)
        }
        // The name (or callsign) goes to the other side by the same road and at once: a
        // conversation born nameless used to stay that way until the screen was first opened.
        // And the face with it (15.17): the first letter of a new correspondence used to be
        // answered by a name alone, and the picture waited for a screen nobody had opened yet.
        E2E.shared.sendNameIfNeeded(to: from)
        E2E.shared.sendAvatarIfNeeded(to: from)
        E2E.shared.sendAboutIfNeeded(to: from)   // the bio and the link by the same occasion (24.09)
    }

    /// The ledger's name in the settings store, named once: SeedScope names it as this device's own.
    static let pendingKey = "mt.delivery.pending"
    private var key: String { Self.pendingKey }
    // The retry budget is unchanged IN TIME (about two and a half minutes of app run), but
    // dealt differently: all eight used to stand twenty seconds apart, so a letter that missed
    // a route in the first instant lay exactly twenty seconds — and that read as «slow to
    // arrive» on a live network. Now the first tries go after one second, two, four, eight,
    // sixteen, and only then — every twenty.
    private let fastTries = 12                   // the bell's ramp (bellDue) — not a floor on the knock
    private let sparse: Double = 300             // the node holds the letter: only the receipt is awaited, once in five minutes
    /// THE CARRIAGE OF A LETTER (the author's words 07.10.2026 18:4x MSK: «let it hang on my device as sent for at least 30 days
    /// locally if the node did not send at once»): this phone carries a letter thirty days, re-boxing it on the node (the box keeps a
    /// letter a day from its last ring) for a receiver that sleeps, is switched off or sits in a seat not in use.
    static let carryDays: Double = 30
    private let carry: Double = MontanaDeliveryEngine.carryDays * 86_400   // the only end — and never a red one for a letter the node took
    /// NO FLOOR BEFORE THE NODE TAKES IT (the author's word 20.09: nothing waits): a letter the
    /// node has not accepted knocks every twenty seconds for its whole term — the five-minute
    /// rhythm belongs only to a letter already on the node, where the knock is a receipt check.
    private func backoff(_ tries: Int, nodeAck: Bool) -> Double {
        if nodeAck { return sparse }
        return min(20, pow(2, Double(max(0, tries - 1))))
    }
    private let q = DispatchQueue(label: "montana.delivery")
    private var tick: Task<Void, Never>?
    private var cargoChecked: [String: Double] = [:]   // letter mid -> last sender-side cargo check
    private var lastMirror: Double = 0                 // the mirror law runs at most once in 5s
    private var forceBell: Set<String> = []            // mids whose next attempt knocks past the bell's ramp (door alive)
    private var lastRoadBack: [String: Double] = [:]   // each road that comes back drains at most once in 30 s (drainOnDoorAlive)

    /// What waits in the queue. One queue for every kind of outgoing data: a letter, a picture of
    /// a person, a piece of content, a profile. A second queue for one concern is the violation
    /// itself, not the work — the moment one reaches for the second place is the finding.
    /// The record and its store live in MTOutbox (MTNodeWire.swift, 18.09): the landing door
    /// reads the very same records, and one type in two targets is one type ([C-1]).
    typealias Kind = MTOutbox.Kind
    typealias Item = MTOutbox.Item

    /// THE «ANNOUNCED» MARK — its key name is born HERE and nowhere else ([I-10]/[C-1]).
    ///
    /// The key name used to stand as four string literals in two files. The face's move from
    /// version two to three rewrote exactly the literal that SETS the mark — and left the three
    /// that clear it untouched. Clearing hit a key that no longer existed: a face was announced
    /// to a peer once in the mark's lifetime, and if that once never arrived, it never arrived
    /// again — not on the peer's appearance, not when the announcement expired, not when a
    /// removed picture returned. The failure was perfectly silent: deleting a missing key is a
    /// legal operation.
    ///
    /// A version in the key name means «previous marks are void, announce anew». It can now be
    /// changed in exactly one place, and the halves have nowhere left to diverge.
    enum Announced {
        private static var mine: String { MontanaSeed.twin ?? "" }
        // Version 2 / 4 / 2 (15.21): the mark's MEANING changed from «enqueued» to «receipted», and a
        // changed meaning lives under a new name — a promise written by an older build is not read
        // as a receipt (measured 07.09 09:10: «held=10 needy=0» on a phone whose faces never arrived).
        static func name(to ref: String) -> String { "sentNm2_" + mine + "_" + ref }
        static func face(to ref: String) -> String { "sentAv4_" + mine + "_" + ref }
        static func faceMissing(to ref: String) -> String { "sentAvNone2_" + mine + "_" + ref }
        /// The bio and the link the peer's screen holds of me, receipted (24.09). Its value is the tag of the words.
        static func about(to ref: String) -> String { "sentAb1_" + mine + "_" + ref }
        static func forgetAbout(to ref: String) {
            UserDefaults.standard.removeObject(forKey: about(to: ref))
        }
        /// One tag for my words about myself, on the sender's «is it announced», on the receipt's «now it is» and in
        /// the presence word's «what I hold of you» ([C-1]): the same digest as the name's; nothing said = «0».
        static func aboutTag(bio: String, link: String) -> String {
            (bio.isEmpty && link.isEmpty) ? "0" : wireTag(Data((bio + "\n" + link).utf8))
        }
        /// The tag of the words an «about» letter carries — read from the letter itself.
        static func aboutTag(ofWord text: String) -> String? {
            guard text.hasPrefix(aboutMark),
                  let d = String(text.dropFirst(aboutMark.count)).data(using: .utf8),
                  let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
            return aboutTag(bio: (o["b"] as? String) ?? "", link: (o["l"] as? String) ?? "")
        }
        /// My page's ground the peer's screen holds, receipted (25.09). Its value is the tag of the ground's content.
        static func ground(to ref: String) -> String { "sentPg1_" + mine + "_" + ref }
        static func forgetGround(to ref: String) {
            UserDefaults.standard.removeObject(forKey: ground(to: ref))
        }
        /// One tag for a page's ground, on the sender's «is it announced», on the receipt's «now it is», on the
        /// receiver's «what I hold» and in the presence word's «G» ([C-1]): the name's digest of the content; none = «0».
        static func groundTag(_ g: String) -> String { g.isEmpty ? "0" : wireTag(Data(g.utf8)) }
        /// The tag of the ground a «ground» letter carries — read from the letter itself.
        static func groundTag(ofWord text: String) -> String? {
            guard text.hasPrefix(groundMark),
                  let d = String(text.dropFirst(groundMark.count)).data(using: .utf8),
                  let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
            return groundTag((o["g"] as? String) ?? "")
        }
        /// Announce anew: both halves of the mark are cleared together, because the picture and
        /// its absence are two values of ONE fact — «what the peer's screen shows».
        static func forgetFace(to ref: String) {
            UserDefaults.standard.removeObject(forKey: face(to: ref))
            UserDefaults.standard.removeObject(forKey: faceMissing(to: ref))
        }
        static func forgetName(to ref: String) {
            UserDefaults.standard.removeObject(forKey: name(to: ref))
        }
        /// The tag of a face: the same bytes, the same eight-byte digest — computed HERE for the
        /// sender's «is it announced» and for the receipt's «now it is» ([C-1]).
        static func faceTag(_ img: Data) -> String {
            SHA256.hash(data: img).prefix(8).map { String(format: "%02x", $0) }.joined()
        }
        /// The tag of the face a «face» letter carries -- read from the letter itself; «no face» is «0».
        static func faceTag(ofWord text: String) -> String? {
            guard text.hasPrefix(avatarMark) else { return nil }
            let b64 = String(text.dropFirst(avatarMark.count))
            if b64.isEmpty { return "0" }
            return Data(base64Encoded: b64).map(faceTag)
        }
        /// One digest for the face and the name alike: the first four bytes of SHA-256 as a
        /// decimal number; nothing held = «0».
        static func wireTag(_ d: Data?) -> String {
            guard let d, !d.isEmpty else { return "0" }
            let h = Array(SHA256.hash(data: d).prefix(4))
            let n = (UInt32(h[0]) << 24) | (UInt32(h[1]) << 16) | (UInt32(h[2]) << 8) | UInt32(h[3])
            return String(n)
        }
        static func nameWireTag(_ s: String) -> String { wireTag(s.isEmpty ? nil : Data(s.utf8)) }
        /// «ANNOUNCED» MEANS «RECEIPTED» (15.21, the author's word 07.09: «make them work right by
        /// construction»). The mark used to be written at enqueue — a promise — and the promise
        /// stood on letters the engine later retired (unanswered pipe, an hour without receipt,
        /// no secret): the peer answered, and nothing announced the face again until it changed.
        /// Now the ONLY writer of the mark is the receipt of the very letter that carried the
        /// value; every other exit from the queue writes nothing, and the next occasion announces
        /// anew. A promise cannot outlive its letter because there is no promise.
        static func recordDelivered(text: String, to ref: String) {
            if text.hasPrefix(nameMark) {
                let nm = String(text.dropFirst(nameMark.count))
                UserDefaults.standard.set(nm, forKey: name(to: ref))
                MontanaTrace.mark("announced", "name to=\(String(ref.prefix(10)))")
            } else if text.hasPrefix(avatarMark) {
                let b64 = String(text.dropFirst(avatarMark.count))
                if b64.isEmpty {
                    UserDefaults.standard.removeObject(forKey: face(to: ref))
                    UserDefaults.standard.set("1", forKey: faceMissing(to: ref))
                    MontanaTrace.mark("announced", "no-face to=\(String(ref.prefix(10)))")
                } else if let d = Data(base64Encoded: b64) {
                    UserDefaults.standard.removeObject(forKey: faceMissing(to: ref))
                    UserDefaults.standard.set(faceTag(d), forKey: face(to: ref))
                    MontanaTrace.mark("announced", "face to=\(String(ref.prefix(10))) tag=\(faceTag(d))")
                }
            } else if let tag = aboutTag(ofWord: text) {
                UserDefaults.standard.set(tag, forKey: about(to: ref))
                MontanaTrace.mark("announced", "about to=\(String(ref.prefix(10))) tag=\(tag)")
            } else if let tag = groundTag(ofWord: text) {
                UserDefaults.standard.set(tag, forKey: ground(to: ref))
                MontanaTrace.mark("announced", "ground to=\(String(ref.prefix(10))) tag=\(tag)")
            }
        }
        /// The mark that falls with a retired state letter — each kind forgets its own ([C-1]).
        static func forget(kind: Kind, to ref: String) {
            switch kind {
            case .profile: forgetName(to: ref)
            case .picture: forgetFace(to: ref)
            case .about: forgetAbout(to: ref)
            case .ground: forgetGround(to: ref)
            case .letter, .piece: break
            }
        }
    }

    /// THE LETTERS OF YOURS I HOLD WHOLE, IN EVERY PRESENCE WORD (23.09, the author's word: the answer
    /// is cumulative and rides every word, as in TCP). A receipt is one letter on one road; one lost
    /// receipt left the sender knocking for a week by construction (23.09 13:06-15:17: five letters of
    /// iPhone 15 were resent up to 43 times while T1 held all five and spoke to it every twenty seconds
    /// — 146 «watch» and 121 «presence» words reached it). The receipt's truth has a second speaker now,
    /// on the road that works: every presence word names, after «K», the peer's letters this side holds
    /// whole — a letter that landed, a file assembled, a copy asked about — and the sender raises what
    /// it names through the one delivery door (markDelivered), exactly as a receipt would.
    ///
    /// Not a watermark: a letter is named by its birth, not by a place in a row, and «all up to X» would
    /// raise a letter born before X that never arrived. The word names each letter itself. The shape:
    /// «K» + «ms.n» joined by commas — the birth millisecond of the name «t…-…» and the uuid's first
    /// four hex digits read as a number. A name without a birth (an old build's bare uuid) is not named
    /// here: its receipt answers every copy.
    enum HeldLetters {
        static let capacity = 12   // the latest touched; a stuck letter is touched again by every copy
        private static let lock = NSLock()
        private static var recent: [String: [String]] = [:]   // peer to keys, the latest touched first
        /// The key a letter is named by, or nil for a name without a birth.
        static func key(_ mid: String) -> String? {
            guard mid.hasPrefix("t"), let dash = mid.firstIndex(of: "-") else { return nil }
            let ms = mid[mid.index(after: mid.startIndex)..<dash]
            guard !ms.isEmpty, ms.allSatisfy({ $0.isNumber }) else { return nil }
            let head = mid[mid.index(after: dash)...].prefix(4)
            guard head.count == 4, let n = Int(head, radix: 16) else { return nil }
            return String(ms) + "." + String(n)
        }
        /// The letter stands whole on this side — said by the one receipt door alone.
        static func note(peer: String, mid: String) {
            guard let k = key(mid) else { return }
            lock.lock(); defer { lock.unlock() }
            var list = recent[peer] ?? []
            list.removeAll { $0 == k }
            list.insert(k, at: 0)
            if capacity < list.count { list.removeLast(list.count - capacity) }
            recent[peer] = list
        }
        /// «K…» for this peer's presence word, or nothing when nothing of theirs stood whole in this life.
        static func tail(_ peer: String) -> String {
            lock.lock(); defer { lock.unlock() }
            guard let list = recent[peer], !list.isEmpty else { return "" }
            return "K" + list.joined(separator: ",")
        }
        /// The keys a peer's word names: the run after its «K», before the door's «@».
        static func named(in payload: Substring) -> Set<String> {
            let head = payload[..<(payload.firstIndex(of: "@") ?? payload.endIndex)]
            guard let k = head.firstIndex(of: "K") else { return [] }
            let run = head[head.index(after: k)...].prefix { $0.isNumber || $0 == "." || $0 == "," }
            return Set(run.split(separator: ",").map(String.init).filter { e in
                let p = e.split(separator: ".", omittingEmptySubsequences: false)
                return p.count == 2 && p.allSatisfy { !$0.isEmpty && $0.allSatisfy({ $0.isNumber }) }
            })
        }
    }

    /// Whether the queue still holds a letter of this name — the one record of «in flight».
    func queueHolds(mid: String) -> Bool { seen().contains { $0.mid == mid } }
    /// The queued letters to this peer that its presence word names as held whole (HeldLetters).
    func queuedMids(to ref: String, named: Set<String>) -> [String] {
        seen().filter { $0.to == ref }.compactMap { it in HeldLetters.key(it.mid).flatMap { named.contains($0) ? it.mid : nil } }
    }
    /// A state letter of this kind is already on its way to this peer: the queue is the one
    /// record of «in flight», so the sender asks it instead of keeping a second flag.
    func hasPendingState(kind: Kind, to ref: String) -> Bool {
        seen().contains { $0.to == ref && $0.kind == kind }
    }
    /// The tag a queued «about», «ground» or face letter to this peer carries: the same value waits, another replaces it.
    /// THE FACE OBEYS THE SAME LAW (30.09): it asked only whether ANY face was on its way, so a new face waited behind
    /// an old one still in flight -- up to the hour an unanswered letter stays -- and the peer saw the old face first.
    func pendingStateTag(kind: Kind, to ref: String) -> String? {
        guard let it = seen().last(where: { $0.to == ref && $0.kind == kind }) else { return nil }
        switch kind {
        case .about: return Announced.aboutTag(ofWord: it.text)
        case .ground: return Announced.groundTag(ofWord: it.text)
        case .picture: return Announced.faceTag(ofWord: it.text)
        default: return nil
        }
    }

    /// LAW S-1 «one state — one record». State does not pile up in the queue: a new name
    /// cancels the old one instead of standing beside it. Dedup used to go by letter id only,
    /// and every announcement added a record — one correspondence hoarded up to six, and all
    /// six left in a volley.
    static func foldingState(_ items: [Item], adding it: Item) -> [Item] {
        guard it.kind.isState else { return items + [it] }
        return items.filter { !($0.to == it.to && $0.kind == it.kind) } + [it]
    }
    /// The very state a letter carries already waits for this peer: the newest record of its kind says the same. «About»
    /// and «ground» are compared by their state's tag — their words carry a moment of their own — the rest by their words.
    static func sameStateWaits(_ items: [Item], to: String, kind: Kind, text: String) -> Bool {
        guard kind.isState, let w = items.last(where: { $0.to == to && $0.kind == kind }) else { return false }
        switch kind {
        case .about:
            if let a = Announced.aboutTag(ofWord: w.text), let b = Announced.aboutTag(ofWord: text) { return a == b }
        case .ground:
            if let a = Announced.groundTag(ofWord: w.text), let b = Announced.groundTag(ofWord: text) { return a == b }
        default:
            break
        }
        return w.text == text
    }

    /// LAW S-2 «state is announced to whoever ANSWERED». What makes a correspondence a peer is
    /// not my intention but proof that someone exists on the other end.
    ///
    /// At first I accepted the birth of a pipe as that proof — and a measurement refuted it:
    /// ten fresh dead introductions passed the filter and got eight tries each (run-up of
    /// 8-16-21-40 seconds, not one receipt). The birth of a pipe is my intention to meet,
    /// and it proves nothing about the other side.
    ///
    /// The proof already lay in the set, and there was no need to invent it again: the first
    /// letter's ciphertext is kept exactly until the answer and is cleared by the receipt. If
    /// it is gone — the other side answered (or the introduction was not mine to begin with,
    /// which is the same: their letter has already arrived).
    ///
    /// A perpetual motion machine used to spin here. Undelivered state gave up after an hour
    /// and CLEARED its «announced» flag; the missing flag begot the letter anew; an hour later
    /// it gave up again. Two hundred eleven dead introductions produced three hundred sixty
    /// letters, one and a half thousand frames and three hundred seventy node wakes on every
    /// launch — in twenty seconds.
    ///
    /// A person's words are NEVER touched by this law: a letter, a picture, a voice message,
    /// a tombstone and a receipt always ride and live their full term. What is cut off is
    /// exactly what the device says on its own behalf.
    static func statePointless(kind: Kind, answered: Bool, aliveAt: Double?,
                               now: Double, ttl: Double) -> Bool {
        guard kind.isState else { return false }
        guard answered else { return true }          // nobody has answered on that end yet
        guard let t = aliveAt else { return true }
        return now - t > ttl                        // answered once, but gone longer than a letter lives
    }

    /// «CANNOT READ» IS NOT «EMPTY» (18.09). A stored queue that does not open — a foreign seal
    /// after a device-key change, a blob a later build cannot decode — used to read as an empty
    /// queue, and the next write saved that emptiness over it: every unsent letter gone, no red
    /// mark, no line in the diary. The store is now judged on every read: bytes that exist and do
    /// not open raise a flag, the diary names it, and while the flag stands no write lands — the
    /// bytes stay for a build that can open them, and a letter enqueued meanwhile is named as
    /// refused rather than silently dropped. A read that opens clears the flag.
    private var storeUnreadable = false
    private var legacyChecked = false
    /// THE LEGACY STORE (before 1674): the app's own defaults under the device key. Moved into the
    /// shared store once, whole; bytes that do not open stay where they are for a build that can
    /// open them, and the shared store is written beside them — a letter enqueued today rides.
    private func migrateLegacy() -> [Item] {
        guard !legacyChecked else { return [] }
        legacyChecked = true
        guard let raw = UserDefaults.standard.data(forKey: key) else { return [] }
        if let d = MontanaLocalVault.getDecrypted(key), let items = try? JSONDecoder().decode([Item].self, from: d) {
            if MTOutbox.write(items) {
                UserDefaults.standard.removeObject(forKey: key)
                MontanaTrace.mark("queue_moved", "n=\(items.count) — the outgoing queue lives in the shared store now")
            } else {
                MontanaTrace.mark("queue_move_failed", "n=\(items.count) — the shared store refused the write; the old store stands")
                legacyChecked = false
            }
            return items
        }
        MontanaTrace.markFolded("queue_unreadable", "the legacy queue does not open bytes=\(raw.count) — left in place", window: 300)
        return []
    }
    /// THE LINE'S OWN COPY, THE DISK ONCE A TURN (03.10, the iPhone 15's diary: 1313 letters waiting, 84 letters a minute of
    /// one pair's minting, the person's new letter red for half an hour). The reading was kept in memory since 28.09, but
    /// every change -- a try counted, a receipt, a new letter -- sealed the whole queue and wrote its file again, so a drain
    /// of n letters wrote it n times on this one line and whatever came after waited behind n seals. The line keeps the copy
    /// it changes and the disk takes it once, after the line's turn; a copy of a forgotten person's era is never written back.
    private var held: [Item]?
    private var heldEra = -1
    private var flushQueued = false
    private var unwritten = 0
    /// What a reader off the line sees: the line's newest copy, handed over under a lock that guards one assignment.
    private let shown = NSLock()
    private var shownCopy: (era: Int, items: [Item])?
    private func load() -> [Item] {
        if let held, heldEra == MTOutbox.era { return held }
        let a = readItems()
        hold(storeUnreadable ? nil : a)
        return a
    }
    private func hold(_ a: [Item]?) {
        let era = MTOutbox.era
        held = a
        heldEra = era
        shown.lock(); shownCopy = a.map { (era, $0) }; shown.unlock()
    }
    /// The queue for a reader off the line (the screen, the profile's announcer): the line's newest copy, or the disk before
    /// the line has read it.
    private func seen() -> [Item] {
        shown.lock(); let s = shownCopy; shown.unlock()
        if let s, s.era == MTOutbox.era { return s.items }
        return readItems()
    }
    private func readItems() -> [Item] {
        guard MTOutbox.available else { return loadLegacy() }
        switch MTOutbox.read() {
        case .items(let items):
            storeUnreadable = false
            return items
        case .unreadable(let bytes):
            storeUnreadable = true
            MontanaTrace.markFolded("queue_unreadable", "the shared queue does not open bytes=\(bytes) — not overwriting", window: 300)
            return []
        case .empty:
            storeUnreadable = false
            return migrateLegacy()
        }
    }
    /// The old road, kept whole for a device whose profile grants no group container.
    private func loadLegacy() -> [Item] {
        let raw = UserDefaults.standard.data(forKey: key)
        if let d = MontanaLocalVault.getDecrypted(key) {
            if let items = try? JSONDecoder().decode([Item].self, from: d) {
                storeUnreadable = false
                return items
            }
            storeUnreadable = true
            MontanaTrace.markFolded("queue_unreadable", "the stored queue opened but does not decode bytes=\(d.count) — not overwriting", window: 300)
            return []
        }
        if raw != nil {
            storeUnreadable = true
            MontanaTrace.markFolded("queue_unreadable", "the stored queue does not open bytes=\(raw?.count ?? 0) — not overwriting", window: 300)
        } else {
            storeUnreadable = false
        }
        return []
    }
    private func save(_ a: [Item]) {
        guard !storeUnreadable else {
            MontanaTrace.markFolded("queue_save_refused", "the stored queue is unreadable — \(a.count) items not written over it", window: 60)
            return
        }
        hold(a)
        unwritten += 1
        guard !flushQueued else { return }
        flushQueued = true
        q.async { [self] in
            flushQueued = false
            guard let items = held else { return }
            guard heldEra == MTOutbox.era else { hold(nil); return }   // the person was forgotten: nothing of theirs goes back
            MontanaTrace.markFolded("queue_written", "items=\(items.count) changes=\(unwritten)", window: 60)
            unwritten = 0
            persist(items)
        }
    }
    private func persist(_ a: [Item]) {
        if MTOutbox.available {
            if !MTOutbox.write(a) { MontanaTrace.markFolded("queue_save_failed", "the shared store refused \(a.count) items", window: 60) }
            return
        }
        if let d = try? JSONEncoder().encode(a) { MontanaLocalVault.setEncrypted(key, d) }
    }
    /// THE LANDING DOOR'S WORD (18.09): the extension boxed these letters at a node while the app
    /// slept. The app marks them «sent» exactly as it marks its own node-ack — a letter to an
    /// unconfirmed pipe is left alone (nobody listens on its tag yet), a letter no longer queued
    /// was already receipted. Called on `q`.
    private func absorbExtensionKnocks(_ a: inout [Item]) {
        let knocks = MTOutbox.takeExtensionKnocks()
        guard !knocks.isEmpty else { return }
        var applied = 0
        for (mid, at) in knocks {
            guard let i = a.firstIndex(where: { $0.mid == mid }) else { continue }
            guard MTPipeBook.first(for: a[i].to) == nil else { continue }
            a[i].lastTry = max(a[i].lastTry, at)
            a[i].nodeAck = true
            applied += 1
            let chat = a[i].chat
            MontanaTrace.mark("nse_knock", mid: mid, "boxed by the landing door \(Int(Date().timeIntervalSince1970 - at))s ago — sent")
            Task { @MainActor in self.store?.markSentByNode(chat, mid: mid, why: "landing door") }
        }
        if applied > 0 { save(a) }
        MontanaLog.event("DELIVERY absorbed \(applied)/\(knocks.count) letters the extension boxed")
    }
    /// A COPY'S LETTERS STILL ON THEIR WAY JOIN THE QUEUE (23.09), each once by its name, on the queue's own
    /// line — a write from outside it would race the drain's read-and-write. Called when their pipes stand; a
    /// peer holds a letter once by its name, so one that did arrive before is only a receipt.
    func adoptRestored(_ items: [Item]) {
        guard !items.isEmpty else { return }
        q.async { [self] in
            var a = load()
            var have = Set(a.map { $0.mid })
            let fresh = items.filter { have.insert($0.mid).inserted }
            guard !fresh.isEmpty else { return }
            a.append(contentsOf: fresh)
            save(a)
            MontanaTrace.mark("queue_restored", "letters=\(fresh.count)")
            DispatchQueue.main.async { self.drainAll() }
        }
    }
    /// A long letter's blob reference, born once: the record learns it so a process without the
    /// blob road (the landing door) seals the reference instead of skipping the letter.
    private func noteWire(_ mid: String, _ link: String) {
        q.async { [self] in
            var a = load()
            guard let i = a.firstIndex(where: { $0.mid == mid }), a[i].wire != link else { return }
            a[i].wire = link; save(a)
        }
    }

    // Enqueue a guaranteed-delivery item (real user text). Dedup by mid; immediate first attempt.
    /// An EMPTY CONVERSATION is one where not a single human word was said — none sent, none
    /// received. Service letters (name, face, receipts, typing) do not count as words — the
    /// device writes them, not the person. One definition for two tasks: whom to announce the
    /// profile to and what to sweep out. It has no second home ([I-10]).
    func enqueue(to: String, chat: String, mid: String, text: String, silent: Bool,
                 kind: Kind = .letter, headless: Bool = false,
                 quoteText: String? = nil, quoteMid: String? = nil, linkPreview: String? = nil) {
        guard MontanaConv.holds(to) else {
            // A silent drop on the critical path is a phantom «sent»: the bubble looked fine
            // while the letter never entered the queue (the share-video manifest died exactly
            // here). The refusal is named, traced and shown on the bubble.
            MontanaLog.event("DELIVERY ✗ mid=\(mid.prefix(8)) dropped — no pipe for \(to.prefix(10))")
            MontanaTrace.mark("enqueue_drop", mid: mid, "no-pipe to=\(String(to.prefix(10)))")
            refuse(mid, chat: chat, .noRoad)
            return
        }
        q.async { [self] in
            var a = load()
            if let i = a.firstIndex(where: { $0.mid == mid }) {
                // ONE INTENT, ITS NEWEST SHAPE (18.09): compression renames the file and the send re-declares
                // the intent under the same letter name — the record follows, or a resume looks for a file
                // that no longer exists (measured 18.09 14:28: «the file is gone, the intent goes» on a video
                // whose .mov had become _mtc.mp4 two minutes earlier, and the video never left).
                if kind == .piece, a[i].kind == .piece, a[i].text != text {
                    a[i].text = text; save(a)
                    MontanaTrace.mark("piece_reshaped", mid: mid, "the intent follows the file")
                }
                return
            }
            // ONE STATE, ONE LETTER: a read mark says «read up to here» — a newer one for the
            // same correspondence makes the queued one meaningless, and forty-three of them
            // waiting their turn burnt the pair's ring budget (08.09, T3→T1). The last word stands.
            if text.hasPrefix(readReceiptMark) { a.removeAll { $0.to == to && $0.text.hasPrefix(readReceiptMark) } }
            // ONE PAGE OF A WALL ON ITS WAY TO ONE PERSON (the critic's N1): a newer page of mine makes the queued one
            // meaningless — the last page stands, as the last read mark does.
            if MTBoard.isPage(text) { a.removeAll { $0.to == to && MTBoard.isPage($0.text) } }
            // THE SAME STATE ALREADY ON ITS WAY IS NOT QUEUED AGAIN (25.09, the diary of T1: at one proof of a peer's build
            // four «about» letters and three 1.6 MB «ground» letters left within 60 ms). The senders ask the queue whether
            // their state waits, but they ask on their own thread while the queue writes on this line: every question before
            // the first write read an empty queue, and each new letter folded its twin away only after the twin had gone on
            // the wire. The answer is given here, where the record is written — whoever asked, whenever.
            if Self.sameStateWaits(a, to: to, kind: kind, text: text) {
                MontanaTrace.markFolded("state_twin", "kind=\(kind) — the same state already waits for this peer", window: 30)
                return
            }
            a = Self.foldingState(a, adding: Item(to: to, chat: chat, mid: mid, text: text,
                          silent: silent || isSilentLetter(text),
                          since: Date().timeIntervalSince1970, tries: 0, lastTry: 0,
                          headless: headless ? true : nil, kind: kind,
                          qt: quoteText, qm: quoteMid, lp: linkPreview))
            save(a)
            // THE REFUSAL IS SHOWN, NOT SWALLOWED: with the store unreadable the letter did not land
            // in the queue and will not ride; the bubble goes red with a retry, as on any break.
            if storeUnreadable {
                MontanaLog.event("DELIVERY ✗ mid=\(mid.prefix(8)) not queued — the stored queue is unreadable")
                MontanaTrace.mark("enqueue_drop", mid: mid, "store unreadable")
                refuse(mid, chat: chat, .notQueued)
                return
            }
            // A person's letter gets its own line; the service traffic that rides the same queue
            // (receipts, presence, profile) arrives in volleys and rides as a count — 247 lines in
            // an afternoon said one thing many times.
            if silent || isSilentLetter(text) {
                MontanaTrace.markFolded("enqueue_service", "queued=\(a.count)", window: 30)
            } else {
                MontanaLog.event("DELIVERY +mid=\(mid.prefix(8)) queued=\(a.count)")
                MontanaNotify.suggest(chat)   // the chat a person writes to is offered in the share sheet (once a day)
                MTBoard.introduce(to: to)     // behind a letter of the person's own, the wall says it is read here (N2)
            }
            attempt(mid)   // attempt = sending as an envelope through the node, at t=0
        }
        startTick()
    }

    /// A letter already receipted and gone from the queue still gets the direct copy; a
    /// dead peer simply never sees the card.
    func attachPreview(to: String, chat: String, mid: String, text: String, lp: String,
                       quoteText: String? = nil, quoteMid: String? = nil) {
        q.async { [self] in
            var a = load()
            if let i = a.firstIndex(where: { $0.mid == mid }) { a[i].lp = lp; save(a) }
            // The same-mid copy carries the QUOTE as well, or an answer would arrive quoting nothing.
            _ = MontanaPhoneNode.shared.sendLetter(to: to, mid: mid, text: text,
                                              quoteText: quoteText, quoteMid: quoteMid, linkPreview: lp)
            MontanaTrace.mark("lp_attach", mid: mid, "bytes=\(lp.utf8.count)")
        }
    }

    // The store-budget gate that held new media until the peer's receipt is gone (the author's
    // word 20.09: no queue for media or for any data). The record here is a ledger, never a gate.

    // Stage 8.2: the engine holds ONE background assertion while undelivered items exist and
    // the app leaves the foreground. Without it the drain cycle dies the moment the user
    // swipes away, and a letter that could be handed over in two seconds waits for the next
    // launch instead. Expiry is honest by construction: the queue is on disk, statuses stay
    // "queued", nothing turns red — the system just pauses the work (bg_expired in the trace).
    private var bgHold: MTSendAssertion?
    func backgroundHoldIfPending() {
        DispatchQueue.main.async { [self] in
            guard bgHold == nil else { return }
            q.async { [self] in
                guard !load().isEmpty else { return }
                DispatchQueue.main.async { [self] in
                    guard bgHold == nil else { return }
                    bgHold = MTSendAssertion("delivery-drain")
                    MontanaTrace.mark("bg_hold", "delivery-drain taken — queue not empty")
                }
            }
        }
    }
    func releaseBackgroundHold(_ why: String) {
        DispatchQueue.main.async { [self] in
            guard let h = bgHold else { return }
            h.end(); bgHold = nil
            MontanaTrace.mark("bg_hold", "delivery-drain released — \(why)")
        }
    }

    // A delivery receipt arrived — the ONLY dequeue condition for a guaranteed item. `by` names the
    // speaker in the diary: the receipt, or the peer's presence word naming the letter (HeldLetters).
    func confirmDelivered(mid: String, by: String = "receipt") {
        q.async { [self] in
            var a = load(); let n = a.count
            // The one number that says whether delivery was instant: queue -> receipt, end to end.
            let ms = a.first(where: { $0.mid == mid }).map { Int((Date().timeIntervalSince1970 - $0.since) * 1000) }
            let tries = a.first(where: { $0.mid == mid })?.tries ?? 0
            let due = a.first(where: { $0.mid == mid })?.to
            let wasTombstone = a.first(where: { $0.mid == mid }).map { isBurialWord($0.text) } == true   // a tombstone or a closing word
            let letterText = a.first(where: { $0.mid == mid })?.text ?? ""
            a.removeAll { $0.mid == mid }
            if a.count != n {
                save(a)
                if a.isEmpty { releaseBackgroundHold("queue empty") }
                // The other side answered, so they hold the secret: the ciphertext that opened the
                // correspondence has done its one job and is dropped. Keeping it would put a copy
                // of a spent value on the wire with every later letter.
                if let conv = due { MTPipeBook.forgetFirst(conv); MTPipeBook.touch(conv) }
                // A receipted name or face is now what the peer's screen shows — the mark is written here.
                if let conv = due { Announced.recordDelivered(text: letterText, to: conv) }
                // A receipted page of my wall is the version that visitor holds (the critic's N5).
                if let conv = due { MTBoard.delivered(text: letterText, to: conv) }
                // The tombstone is delivered — now the pipe can be buried for real.
                if wasTombstone, let conv = due { MTPipeBook.forget(conv) }
                // The letter is delivered — its media's shipping crate is of no use to anyone:
                // the peer has the file assembled, and the node blob lives out its own week.
                // Without this, the chunks lay as a SECOND copy beside the sealed archive until
                // the term itself passed.
                dropChunks(of: letterText)
                // A long letter is delivered — its blob on the store serves no one now (7.2b).
                if MontanaWakePush.takeLongRef(mid) {
                    let freed = MontanaWakePush.releaseLetter(mid)
                    if !freed.isEmpty { Task { await MontanaWakePush.dropBids(freed) } }
                }
                // The letter is delivered — its chunks on the node serve no one now. ONLY the
                // chunks no other living letter references are removed: one chunk carries
                // twenty broadcasts, and an early teardown would break the late addressees
                // exactly as it once did on the receiving side (stage 1). The sender keeps the
                // reference count — the node is blind. A media receipt means an ASSEMBLED FILE
                // (the assembly point sends it), so the cargo may leave the node: no one will
                // come for it again.
                let freed = MontanaWakePush.releaseLetter(mid)
                if !freed.isEmpty { Task { await MontanaWakePush.dropBids(freed) } }
                MontanaLog.event("DELIVERY ✓ mid=\(mid.prefix(8)) receipt — dequeued ms=\(ms ?? -1) tries=\(tries) freed=\(freed.count)")
                MontanaTrace.mark("delivered", mid: mid, "ms=\(ms ?? -1) tries=\(tries)" + (by == "receipt" ? "" : " by=\(by)"))
                // Delivered by the direct road — the node-box copy serves no one now (7.2c).
                Task { await MontanaWakePush.boxDel([mid]) }
                MTCompressResume.shared.cancel(letter: mid)
                MTEncodeRegistry.shared.cancel(letter: mid)
            }
        }
    }

    /// The call has ended — its invitation letter leaves the queue: guaranteed delivery of a
    /// real-time signal would ring a person after the hang-up.
    func cancelRing(to conv: String) {
        q.async { [self] in
            var a = load(); let n = a.count
            // The call has ended — its invitation leaves the node box too: a stale ring,
            // fetched by a receiver waking minutes later, would ring as a ghost (7.2c).
            let rings = a.filter { $0.to == conv && $0.text.hasPrefix(ringMark) }.map { $0.mid }
            if !rings.isEmpty { Task { await MontanaWakePush.boxDel(rings) } }
            a.removeAll { $0.to == conv && $0.text.hasPrefix(ringMark) }
            if a.count != n { save(a); MontanaTrace.mark("ring_cancel", "n=\(n - a.count) to=\(String(conv.prefix(10)))") }
        }
    }

    // Deleting a chat drops its pending sends (no resurrection after a network switch).
    func clearChat(_ conv: String) {
        MontanaWakePush.forgetPeer(conv)   // out of the circle: this side never wakes there again
        // This road does NOT bury the pipe. «Delete for me» keeps the channel alive — the
        // peer's letter resurrects the conversation, as in the server version. The pipe dies
        // only by the funeral cycle «delete for both» (markDying → tombstone receipt or term →
        // forget) and by full reset.
        q.async { [self] in
            var a = load(); let n = a.count
            // STAGE 7.2: «delete for both» removes the UNDELIVERED from the node store AT ONCE.
            // Every undelivered media letter's chunks are computable from the ledger
            // (releaseLetter) — they are removed right here, before the queue sweep; the node
            // is blind, removal goes by blob names. The manifest letter (330B) leaves the node
            // box — the node half — in the same move.
            for it in a where (it.to == conv || it.chat == conv)
                && (it.kind == .letter || it.kind == .piece) && !isBurialWord(it.text) {
                _ = MontanaWakePush.takeLongRef(it.mid)   // the tombstone forgets the long-letter reference too
                let bids = MontanaWakePush.releaseLetter(it.mid)
                if !bids.isEmpty {
                    MontanaTrace.mark("store_retract", "mid=\(String(it.mid.prefix(8))) bids=\(bids.count)")
                    Task { await MontanaWakePush.dropBids(bids) }
                }
            }
            // «Delete for both» sweeps the node box as well: the conversation's undelivered letters go (7.2c).
            let boxed = a.filter { ($0.to == conv || $0.chat == conv) && !isBurialWord($0.text) }.map { $0.mid }
            if !boxed.isEmpty { Task { await MontanaWakePush.boxDel(boxed) } }
            // The tombstone is the one letter that must OUTLIVE the chat's death.
            a.removeAll { ($0.to == conv || $0.chat == conv) && !isBurialWord($0.text) }
            if a.count != n { save(a); MontanaLog.event("DELIVERY cleared \(n - a.count) for deleted chat \(conv.prefix(10))") }
        }
    }

    // Peer became reachable over ANY transport — drain everything pending for it now.
    func onPeerUp(_ ref: String) {
        // The channel to this correspondence stood up — the other side proved it exists. That
        // is the sign of life: it revives a profile announcement silenced by law S-2.
        MTPipeBook.touch(ref)
        if ref == MontanaSeed.twin { MontanaArchive.replicate(to: ref) }   // own twin: hand over history
        q.async { [self] in
            let due = load().filter { $0.to == ref || $0.chat == ref }
            guard !due.isEmpty else { return }
            MontanaLog.event("DELIVERY drain \(due.count) → \(ref.prefix(10)) (peerUp)")
            for it in due { attempt(it.mid) }
        }
    }

    /// A DOOR CAME BACK TO LIFE — every loud letter no node has taken yet knocks NOW, past the bell's ramp (18.09).
    /// The ramp (tries 1, 3, 6, 10) protects the network from a storm while the doors are dead;
    /// the moment one answers, waiting for the next due try is the storm's price paid for nothing:
    /// measured 17.09, the network lived for twenty-five seconds inside a dead hour, and the one
    /// text letter in the queue missed it by a single try. Loud letters only: a silent service word
    /// rides its own rhythm and the node's per-pair budget. One drain per thirty seconds — a door
    /// that flaps drains once, not on every flap; the node boxes an over-budget knock without a
    /// ring, so a volley here cannot rest the door.
    /// A LETTER THE NODE ALREADY HOLDS IS NOT DRAINED HERE (23.09): this drain is for letters that could not
    /// reach a node while the doors were dead. One the node boxed (nodeAck) waits for its receipt on the
    /// sparse rhythm, five minutes; the doors behind Cloudflare die and wake all day, and every wake used to
    /// re-send such a letter through both nodes and force its bell -- measured 23.09 on T1: one media letter
    /// the node held went out 103 times and forced 92 bells between 16:21 and 19:53.
    /// EVERY ROAD THAT COMES BACK KEEPS ITS OWN CLOCK (30.09). A door answering after silence, a node held again and the
    /// system's wake by a push are three different pieces of news, and one thirty-second clock for all three let one of them
    /// silence another: measured 29.09 on a tester's phone (build 1976), the push that launched the app at 13:18:01Z drained
    /// into four dead doors, the doors answered at 13:18:26Z and their drain was "throttled" -- the text letter written at
    /// 08:02Z missed the one living minute of that phone's day and left it at 21:19Z. The caller names the road: a "push:"
    /// or "node:" word is its own clock, a door host is the doors' clock; a road that flaps still drains once in 30 s.
    func drainOnDoorAlive(_ door: String) {
        q.async { [self] in
            let now = Date().timeIntervalSince1970
            let road = door.contains(":") ? String(door.prefix { $0 != ":" }) : "door"
            guard now - (lastRoadBack[road] ?? 0) > 30 else {
                MontanaTrace.markFolded("door_alive_drain", "throttled door=\(door)", window: 30, key: road)
                return
            }
            var a = load()
            absorbExtensionKnocks(&a)   // what the landing door already boxed is «sent» before the bells
            let loud = a.filter {
                $0.kind == .letter && !$0.silent && !isSilentLetter($0.text)
                    && !$0.text.hasPrefix(ringMark) && !$0.text.hasPrefix(convDelMark)
                    && $0.nodeAck != true   // the node holds it: only its receipt is awaited, on the sparse rhythm
            }
            guard !loud.isEmpty else { return }
            lastRoadBack[road] = now
            forceBell = Set(loud.map { $0.mid })
            MontanaLog.event("DELIVERY drain \(loud.count) loud (door alive \(door))")
            MontanaTrace.mark("door_alive_drain", "door=\(door) loud=\(loud.count)")
            for it in loud { attempt(it.mid) }
        }
    }

    // Foreground / launch backstop: attempt everything, (re)start the tick.
    func drainAll() {
        q.async { [self] in
            var a = load()
            absorbExtensionKnocks(&a)   // the landing door's word first: its knocks are this queue's knocks
            // A dying pipe with no tombstone queued — there is nothing left to bury it with
            // (delivered, or lost between launches): finish it off so it does not live forever.
            for d in MTPipeBook.dyingAll()
            where !a.contains(where: { $0.to == d && isBurialWord($0.text) }) {
                MTPipeBook.forget(d)
            }
            // QUEUE HYGIENE BY CONSTRUCTION (the author's word 27.08): the queue may hold
            // only what can still truthfully travel. Two classes die on every pass:
            //   1) letters to a BURIED pipe — the pipe took the correspondence with it, and a
            //      letter without a pipe is a ghost that retries forever;
            //   2) face letters in YESTERDAY's shapes (manifest/rm JSON) — a dead format is
            //      not delivered «best effort», it is buried, or it keeps erasing the present
            //      (measured 27.08: a 12-minute-old burial letter wiped the fresh photo).
            var swept = 0
            a.removeAll { it in
                let ghost = !MontanaConv.holds(it.to)
                let deadShape = it.text.hasPrefix(avatarMark)
                    && String(it.text.dropFirst(avatarMark.count)).hasPrefix("{")
                guard ghost || deadShape else { return false }
                _ = MontanaWakePush.takeLongRef(it.mid)
                let bids = MontanaWakePush.releaseLetter(it.mid)
                if !bids.isEmpty { Task { await MontanaWakePush.dropBids(bids) } }
                Task { await MontanaWakePush.boxDel([it.mid]) }
                swept += 1
                return true
            }
            if swept > 0 {
                save(a)
                MontanaTrace.mark("queue_hygiene", "buried=\(swept) left=\(a.count)")
            }
            reconcile(a)   // even with an empty queue: a clock nothing rides behind must go red
            guard !a.isEmpty else { return }
            MontanaTrace.markChanged("drain_all", "pending=\(a.count)", every: 900)   // a state: it speaks when it changes (23.09)
            // Draining is an alarm clock, not a drum: every letter keeps its own rhythm
            // (run-up 1-2-4-8-16-20s, then once in five minutes; peerUp drains by address and
            // at once). Every call used to hammer the WHOLE queue in a volley: dozens of
            // letters to dead correspondences knocked on every app open (74/min, 22:26).
            // The current rides instantly (tries=0 and a live peer), the stale — on schedule.
            let now = Date().timeIntervalSince1970
            // THE INTENT RIDES THE DRAIN (18.09): every drain — a peer up, a door alive, a wake, the
            // system's window, the launch — hands the queued intents back to the one media road, which
            // re-runs the same send under the same letter name. Once a minute per intent; a living
            // upload is never doubled (the store asks its task table first); the resumes are counted,
            // and an intent past its count is put out, red, as a letter past its term.
            var hand: [Item] = []
            var spent: [String] = []
            // Without a node the hand-off is pointless and must not be counted against the intent
            // (18.09): the send would return at its own gate, and a day without a node would spend the term.
            let nodeHeld = MontanaPhoneNode.shared.nodeUp
            if !nodeHeld, a.contains(where: { $0.kind == .piece }) {
                MontanaTrace.markFolded("piece_wait", "no node held — the intents wait", window: 120)
            }
            // AN INTENT DIES BY TERM ONLY, like a letter (20.09) — never by a count of resumes; and it
            // is handed back on the letters' own twenty-second rhythm, not once a minute (a living
            // upload is never doubled: the store asks its task table first).
            for i in a.indices where nodeHeld && a[i].kind == .piece && now - a[i].lastTry > 20 {
                if now - a[i].since > carry { spent.append(a[i].mid); continue }
                a[i].tries += 1; a[i].lastTry = now
                hand.append(a[i])
            }
            if !hand.isEmpty || !spent.isEmpty {
                for m in spent {
                    let chat = a.first(where: { $0.mid == m })?.chat ?? ""
                    MontanaTrace.mark("piece_spent", mid: m, "past its carriage, never uploaded — put out")
                    refuse(m, chat: chat, .neverLeft)
                }
                a.removeAll { spent.contains($0.mid) }
                save(a)
                if !hand.isEmpty {
                    let items = hand
                    Task { @MainActor in self.store?.resumePieces(items) }
                }
            }
            for it in a where it.tries == 0 || now - it.lastTry > backoff(it.tries, nodeAck: it.nodeAck == true) {
                attempt(it.mid)
            }
            // The cargo check rides the DRAIN, not the per-letter attempt rhythm: a letter
            // the node has accepted knocks once in five minutes, and «resend» must not wait
            // for that. Every undelivered media letter is verified here, once a minute each.
            for it in a where it.kind == .letter && it.text.hasPrefix(mediaMark) {
                checkCargo(it.mid, chat: it.chat, age: now - it.since, text: it.text)
            }
            let mids = Set(a.map { $0.mid })
            cargoChecked = cargoChecked.filter { mids.contains($0.key) }
        }
        startTick()
    }

    // The sender OWNS the cargo (9-D.0, the author's rule 24.08): while a media letter
    // waits undelivered, its chunks must still exist on the node — a wiped store shows
    // «resend» NOW, not after the receiver stumbles into the hole. Skipped while any
    // chunk still rides the background session (a handoff is not a loss). Once a minute.
    // ── THE MIRROR LAW (the author's invariant 24.08): «the sender's chat — the node — the
    // receiver's chat». One reconciler enforces the law instead of a patch per event:
    //   M-1  queue ⊆ chat   — an item whose row is gone dies with its whole tail;
    //   M-1a row delivered  — a raced-over item is dequeued silently;
    //   M-2  chat ⊆ queue   — a clock nothing rides behind goes red with resend;
    //   M-3  letter ⊆ cargo — checkCargo above, the network arm of the same law.
    // Whatever future event desynchronizes the stores, the next pass heals it.
    private func reconcile(_ items: [Item]) {
        let now = Date().timeIntervalSince1970
        guard now - lastMirror > 5 else { return }
        lastMirror = now
        // Only bubble-owning kinds face the chat law; service letters have no rows by
        // construction (receipts, profile, the conversation tombstone).
        let facing = items.filter {
            ($0.kind == .piece || $0.kind == .letter)
                && !isSilentLetter($0.text) && !$0.text.hasPrefix(convDelMark)
                && !$0.text.hasPrefix(ringMark) && !$0.text.hasPrefix(missedCallMark)
                && $0.headless != true
                && now - $0.since > 15   // newborn grace: the row may still be being laid
        }
        let queueMids = Set(items.map { $0.mid })
        let riding = Set(items.filter { $0.kind == .letter }.map { $0.mid })
        Task { @MainActor [weak self] in
            guard let self, let store = self.store, store.historyLoaded else { return }
            let verdicts = store.rowVerdicts(facing.map { $0.mid })
            store.liftClockRed(riding: riding)   // once: the reds of silence an older build painted on letters still riding
            store.paintOrphanSending(queueMids: queueMids)
            guard !facing.isEmpty else { return }
            self.q.async {
                var a = self.load(); let n = a.count
                for f in facing {
                    switch verdicts[f.mid] ?? .absent {
                    case .alive: continue
                    case .settled:
                        a.removeAll { $0.mid == f.mid }
                        // Same tail as the receipt road ([C-1]): the delivered letter's chunks
                        // and box copy are needed by nobody — without this they sat a week.
                        let freed = MontanaWakePush.releaseLetter(f.mid)
                        if !freed.isEmpty { Task { await MontanaWakePush.dropBids(freed) } }
                        Task { await MontanaWakePush.boxDel([f.mid]) }
                        MontanaTrace.mark("queue_mirror", mid: f.mid, "row delivered — the raced-over item dequeued with its tail")
                    case .absent:
                        let freed = MontanaWakePush.releaseLetter(f.mid)
                        if !freed.isEmpty { Task { await MontanaWakePush.dropBids(freed) } }
                        a.removeAll { $0.mid == f.mid }
                        MontanaTrace.mark("queue_mirror", mid: f.mid, "no row in the chat — the item dies with its tail")
                    }
                }
                if a.count != n { self.save(a) }
            }
        }
    }

    /// The letter itself NAMES its cargo — the manifest ref or the inline chunk list. The
    /// ledger is only an accelerator: a letter whose ledger rows were released by an older
    /// build sat unverifiable forever and held the conversation gate (precedent 24.08).
    private static func bidsNamed(inLetter text: String) -> [String] {
        guard text.hasPrefix(mediaMark) else { return [] }
        let body = String(text.dropFirst(mediaMark.count))
        guard let d = body.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [] }
        if let mref = o["mref"] as? String { return [mref] }
        return (o["chunks"] as? [[String: Any]] ?? []).compactMap { $0["bid"] as? String }
    }

    private func checkCargo(_ m: String, chat: String, age: Double, text: String) {
        let now = Date().timeIntervalSince1970
        // Fresh letters verify once a minute; a letter waiting for a sleeping receiver for
        // hours slows to once in half an hour — the truth keeps, the network noise does not.
        // SILENT-OK: the early returns are the throttle and the «cannot judge» arm of a
        // periodic health check — nothing is being sent here, no outcome is owed to anyone;
        // the check simply comes back on the next tick.
        let interval: Double = age < 600 ? 60 : (age < 3600 ? 300 : 1800)
        guard now - (cargoChecked[m] ?? 0) > interval else { return }
        cargoChecked[m] = now
        Task { [weak self] in
            guard let self else { return }
            var bids = MontanaWakePush.bidsOf(letter: m)
            if bids.isEmpty { bids = Self.bidsNamed(inLetter: text) }
            guard !bids.isEmpty, !MontanaBlobUpload.anyPending(bids),
                  let have = await MontanaWakePush.blobsPresent(bids, everyStore: true) else { return }   // a verdict of loss needs every store (1638)
            if have.count < bids.count {
                MontanaTrace.mark("cargo_lost", mid: m,
                    "sender check: \(bids.count - have.count)/\(bids.count) chunks gone from the node — red if the letter still rides")
                self.cargoGone(m, chat: chat)
            }
        }
    }

    /// The engine's one road into red (MTRefusal): a word, never a span of time.
    private func refuse(_ mid: String, chat: String, _ why: MTRefusal) {
        Task { await MainActor.run { self.store?.settleRefused(conv: chat, mid: mid, because: why) } }
    }

    /// Cargo is gone — by the sender's own check OR the receiver's report. ONE closure for
    /// both roads ([C-1]): red bubble, ledger released, remnants dropped from the node, and
    /// the LETTER leaves the queue — a dead manifest held the conversation gate for new media.
    func cargoGone(_ m: String, chat: String) {
        q.async { [weak self] in
            guard let self else { return }
            // THE VERDICT FALLS ONLY ON A LETTER STILL RIDING — checked HERE, at the moment of
            // the verdict, not when the question was asked. The node is asked while the letter
            // rides and answers a second later; in that second the receipt may land and the
            // sender itself sweeps the delivered cargo from the node — so «gone» then describes
            // a closed letter, not a loss. Precedent 08.09 06:15: a music letter delivered after
            // eight hours went red 1.2 s later, and the receiver was told to erase it. The
            // receipt is the letter's terminal: after it no verdict road may write its name.
            guard self.load().contains(where: { $0.mid == m && $0.kind == .letter }) else {
                MontanaTrace.mark("cargo_check", mid: m, "stale — the letter settled while the node was asked; no verdict")
                return
            }
            self.cargoGoneNow(m, chat: chat)
        }
    }

    private func cargoGoneNow(_ m: String, chat: String) {
        Task { [weak self] in
            guard let self else { return }
            await MainActor.run { self.store?.settleRefused(conv: chat, mid: m, because: .cargoGone) }
            let freed = MontanaWakePush.releaseLetter(m)
            if !freed.isEmpty { await MontanaWakePush.dropBids(freed) }
            self.q.async {
                var a = self.load(); let n = a.count
                let to = a.first(where: { $0.mid == m && $0.kind == .letter })?.to
                // Only the LETTER dies: a live resend re-mints under the SAME letter name,
                // and a late cargo-check answer must not kill its fresh .piece intent.
                a.removeAll { $0.mid == m && $0.kind == .letter }
                if a.count != n { self.save(a) }
                // NO RETRACT, EVER (1638, the author's invariant: what stands in the sender's chat stands
                // in the receiver's). The dead cargo used to take the RECEIVER's row with it — a silent
                // tombstone wake — while the sender's own row stayed red: two chats diverged by the
                // sender's verdict, and the verdict itself was wrong (T1 20:10:27Z: five letters called
                // lost while T2 assembled all five). The letter stays at both ends; the sender re-uploads
                // under the same name, the receiver's row takes the new cargo (rx_refill). The box copy
                // stays for the receiver too — it names the letter; the cargo is asked for by the manifest.
                _ = to
            }
        }
    }

    /// The receiver's «cargo gone» word is a HINT, not a verdict: it may describe an old
    /// incarnation of the letter while a fresh resend already rides under the same name
    /// (precedent 24.08: a stale report killed a just-tapped resend). The node's store is
    /// the truth — verify NOW, with no throttle, and let the check pass the sentence.
    func verifyCargoNow(_ m: String, chat: String) {
        q.async { [self] in
            guard let it = load().first(where: { $0.mid == m && $0.kind == .letter }) else {
                // THE RECEIPT IS TERMINAL. A «cargo gone» word about a letter that no longer
                // rides describes an incarnation the receipt has outlived: the report may sit in
                // the node box for hours while a later fetch assembles the file and receipts it
                // (the same shape as the sender's own stale check, 08.09 06:15). The one lie a
                // receipt could once tell — receipting a copy whose cargo was still downloading
                // (26.08) — is closed at its source: the receiver receipts a media letter only
                // after the file is assembled and the history is written (sendDeliveryReceipt).
                // So the ladder's law stands whole: forward only, back only by the human hand.
                // What the receiver holds today is its own keeping, not this letter's delivery.
                // THE LINE CLAIMS NO RECEIPT IT CANNOT SEE (23.09, the critic): a face retired after its
                // hour or a letter replaced leaves the queue unreceipted too; the queue knows only that
                // no letter of this name rides.
                MontanaTrace.mark("cargo_check", mid: m, "no letter of this name rides here (receipted, retired or replaced) — the word is ignored")
                return
            }
            cargoChecked[m] = 0
            checkCargo(m, chat: it.chat, age: Date().timeIntervalSince1970 - it.since, text: it.text)
        }
    }

    // Called on `q`.
    private func attempt(_ mid: String) {
        var a = load()
        guard let i = a.firstIndex(where: { $0.mid == mid }) else { return }
        let it = a[i]
        let now = Date().timeIntervalSince1970
        let forced = forceBell.remove(mid) != nil   // a door-alive drain: this attempt knocks past the ramp
        // A call invitation is a real-time signal: it lives 45 seconds in the queue, not 7
        // days. Old RGs of past calls retried and rang people in the back (precedent 19:09).
        // A QUESTION ABOUT THE PAST LIVES AN HOUR (24.09, MTSamePair.askLifeS): an older owner buries it unread and never
        // receipts it — a week of knocks for nothing.
        // AN HOUR FROM THE PIPE'S ANSWER, NOT FROM THE QUESTION'S BIRTH (25.09, T3's diary: a pipe born from a shared card at
        // 02:42Z, the question sent at once, the other phone silent until past 04:00Z — the question dead at 03:42Z, and the
        // two conversations with one person never to fold). A pipe nobody has answered keeps its question — every attempt
        // only keeps the box's copy fresh for the phone that will come — and the hour runs once the pipe has been answered
        // (MTPipeBook.first is dropped at the answer): an older build's burial then costs an hour, as it did.
        if it.text.hasPrefix(sameAskMark), MTPipeBook.first(for: it.to) == nil, now - it.since > MTSamePair.askLifeS {
            a.remove(at: i); save(a)
            MontanaTrace.mark("same_ask_expired", "to=\(String(it.to.prefix(10)))")
            return
        }
        if it.text.hasPrefix(ringMark), now - it.since > 45 {
            a.remove(at: i); save(a)
            MontanaTrace.mark("ring_expired", "age=\(Int(now - it.since))s to=\(String(it.to.prefix(10)))")
            return
        }
        // A LETTER TO A BLOCKED PERSON DOES NOT KNOCK (18.09): blocking took the chat's rows but not its
        // queued letters — measured 18.09 08:42, a stuck letter to a blocked peer took every forced
        // bell for the whole hour. The queue may hold only what can still truthfully travel; the
        // tombstone alone still rides, a block is not a burial. One keychain read per attempt.
        if !isBurialWord(it.text), ChatStore.refusesCold(it.chat) {
            a.remove(at: i); save(a)
            _ = MontanaWakePush.takeLongRef(it.mid)
            let freed = MontanaWakePush.releaseLetter(it.mid)
            if !freed.isEmpty { Task { await MontanaWakePush.dropBids(freed) } }
            MontanaTrace.mark("blocked_drop", mid: it.mid, "a queued letter to a blocked peer put out")
            return
        }
        // A letter ends by its CARRIAGE only. Death by try-count killed a letter in ~2.5 minutes: a
        // receiver opening the app later had no way left to get it.
        // A TRANSFER LETTER AN OLDER BUILD QUEUED HAS NO END (the author's words 07.10.2026 18:4x MSK: «online or in cold storage,
        // what difference -- they must leave»): it rides until the receiver's receipt, and no clock hands it back.
        if now - it.since > carry, !mtRetiredLetter(it.text) {
            a.remove(at: i); save(a)
            let chat = it.chat, m = it.mid, tries = it.tries, age = Int(now - it.since)
            if isBurialWord(it.text) { MTPipeBook.forget(it.to) }   // the tombstone or the closing word expired — the pipe goes with it
            // THE END OF THE CARRIAGE IS NOT A VERDICT (the author's word 07.10: «not an error, I did send»). A letter the node
            // took was sent: it leaves the queue and its row stays «sent» -- the receiver simply did not come for it. Only a
            // letter no node ever took turns red: it never left this phone. Either way its chunks on the node become orphans
            // that instant, and the SENDER removes them — the node cannot know.
            if it.nodeAck == true {
                MontanaTrace.mark("carry_done", mid: m, "age=\(age)s tries=\(tries) — the node held it; the row stays sent")
            } else {
                MontanaTrace.mark("send_failed", mid: m, "age=\(age)s tries=\(tries) — no node ever took it")
                refuse(m, chat: chat, .neverLeft)
            }
            _ = MontanaWakePush.takeLongRef(m)   // the long-letter reference dies with the term
            let freed = MontanaWakePush.releaseLetter(m)
            if !freed.isEmpty { Task { await MontanaWakePush.dropBids(freed) } }
            MontanaLog.event("DELIVERY ✗ mid=\(m.prefix(8)) carriage over (tries=\(tries), age=\(age)s, node=\(it.nodeAck == true ? 1 : 0)) freed=\(freed.count)")
            return
        }
        // An UPLOAD INTENT lives in THIS queue, not a sixth store ([C-1]). It does not ride
        // the wire: until the chunks are up there is no letter yet and no receipt to wait for.
        // The record has one meaning — to survive the process's death. Uploads used to live as
        // one-shot tasks dying with the app: killed mid-upload, they left the person an eternal
        // clock and the node chunks nobody would come for (precedent 20.08 16:09, the phantom
        // send). The intent must NOT be driven by the tick: an upload runs for minutes with its
        // own progress and its own silence watchdog; a second motor on top of it means
        // duplicate sends. A retry comes only from a human hand or launch recovery.
        if it.kind == .piece { return }
        // Profile letters (name/avatar) do not live a week: their point is to catch a LIVE
        // peer. Undelivered to dead correspondences, they stormed the queue and the journal
        // (22:21: dozens of kind=name with wakepush 404 every few seconds, log rotation in two
        // minutes, live letters waiting in the tail). An hour undelivered — they retire
        // silently: the «sent» flag already stands, no re-issue until the name/face changes.
        // LAW S-2: there is nobody to announce to. The letter leaves the queue silently — it
        // is a service letter with no row in the conversation, the person knows nothing of it.
        // No correspondence is deleted: when the peer returns, the sign of life returns, and
        // the announcement rides on the next occasion.
        if Self.statePointless(kind: it.kind, answered: MTPipeBook.first(for: it.to) == nil,
                               aliveAt: MTPipeBook.aliveAt(it.to), now: now, ttl: carry) {
            a.remove(at: i); save(a)
            // THE FLAG FALLS WITH THE LETTER (15.19). «Sent» was written at enqueue and stood on a
            // letter that never left: a correspondence born from a link is unanswered for its first
            // minutes, the name and the face were retired here at once, and when the peer answered
            // nothing announced them again until they changed — T2 saw T1 without a face (07.09
            // 08:16 profile, 08:35 picture). Cleared here, the next occasion — the peer's first
            // letter, the chat opened — announces anew, by construction.
            Announced.forget(kind: it.kind, to: it.to)
            MontanaTrace.mark("state_pointless", mid: it.mid,
                                 "kind=\(it.kind.rawValue) to=\(String(it.to.prefix(10))) flag=cleared")
            return
        }
        if it.kind.isState, now - it.since > 3600 {
            a.remove(at: i); save(a)
            // The «delivered» flag is cleared along with retirement (A-2): otherwise a peer
            // returning later would not get the name/face until they changed — the peer's
            // appearance sets it anew.
            Announced.forget(kind: it.kind, to: it.to)
            MontanaTrace.mark("profile_expired", mid: it.mid, "kind=\(it.kind.rawValue) to=\(String(it.to.prefix(10)))")
            return
        }
        a[i].tries += 1; a[i].lastTry = now; save(a)
        let to = it.to, chat = it.chat, text = it.text, m = it.mid
        // A LOUD LETTER WAITING FOR ITS RECEIPT ASKS THE BOX on every attempt (15.46): the
        // receipt lies on the node when the push that announces it is cut — it used to wait
        // for the next push forever. The pickup is one, rationed inside (8 s).
        if !isSilentLetter(text) { MontanaWakePush.fetchBoxKick() }
        // The three-hop truth (the author's rule 24.08): once the NODE holds the letter, one checkmark stands — for days if the
        // receiver sleeps; that is not a failure. NO CLOCK PAINTS RED (the author's words 07.10.2026 18:4x MSK: «I don't want to
        // see an error if I in fact sent and the other one just did not read»). A letter the node has not taken keeps its clock
        // and keeps knocking for its whole carriage; red comes only with a word (MTRefusal) — real loss of the cargo still turns
        // red through the cargo check below. The ONE channel — the accelerator node (server model): the whole letter rides as an
        // E2E envelope inside the wake; node accepted (200) = handed over, the letter leaves the queue, the receiver's extension
        // stores it into the chat. Not 200 — retry within the letter's term.
        guard let secret = MTPipeBook.secret(for: to) else {
            MontanaLog.event("DELIVERY ✗ mid=\(m.prefix(8)) no pipe secret for \(to.prefix(10)) — dropped")
            a.remove(at: i); save(a)
            refuse(m, chat: chat, .noRoad)
            return
        }
        // The FIRST letter of an introduction (pipe unconfirmed): the peer has NO secret of
        // this pipe yet — physically cannot hold a subscription on its daily tag, a wake for
        // the first letter does not exist BY CONSTRUCTION. The only road is the live channel:
        // first-letter installs the pipe at the receiver, they register on the tag
        // (noteIncoming → registerConvs), and the queue settles with their receipt.
        if MTPipeBook.first(for: to) != nil {
            // A provenly dead knock (tombstone twice, or older than the seven-day horizon) is
            // not «skipped» but PUT OUT: the letter is honestly red, the queue clean — the dead
            // ahead of the living used to hold delivery for minutes (class 6.8).
            guard MontanaMeeting.firstKnockAllowed(conv: to) else {
                MontanaLog.event("DELIVERY ✗ mid=\(m.prefix(8)) first-contact dead for \(to.prefix(10)) — settled")
                a.remove(at: i); save(a)
                refuse(m, chat: chat, .cardSpent)
                return
            }
            MontanaMeeting.auditFirst(conv: to)
            // The live channel remains the letter's road; a DOORBELL by invitation is added
            // (F-2): a sleeping card owner would otherwise never learn of the first letter.
            // The node glues repeats by mid (48h), the client by minute: the ring is cheap.
            // An empty banner is forbidden: ONLY a letter the person will see as text rings.
            // Service letters (name, avatar, receipts) ride the live channel silently — as in pipes.
            if !isSilentLetter(text) {
                let inv = MontanaMeeting.invite(forConv: to)
                let fct = MTPipeBook.first(for: to)
                if let inv, let fct {
                    MontanaWakePush.wakeRdv(invite: inv, mid: m, text: text, ct: fct,
                                            conf: MontanaFirstContact.firstConfirm(secret: secret, ct: fct)) { [weak self] code in
                        // THE NODE'S WORD ON A FIRST LETTER REACHES THE QUEUE (07.10, T1 to a second account of the same phone): the
                        // doorbell boxes the letter under the card's key, and the node answers 200 the moment it is safe in the box --
                        // nineteen times in ten minutes the queue heard none of it. 200 is the node holding it: one checkmark, and
                        // the sparse rhythm of a letter that only waits for its receipt.
                        if code == 200 { self?.noteNodeAck(m) }
                    }
                } else {
                    // A mute miss of this condition already cost an evening of digging: the
                    // letter knocked 45 times without one doorbell, and the trace never said why.
                    MontanaTrace.mark("rdv_ring_skip", mid: m,
                        "invite=\(inv == nil ? 0 : 1) ct=\(fct == nil ? 0 : 1) to=\(String(to.prefix(10)))")
                }
            }
            _ = MontanaPhoneNode.shared.sendLetter(to: to, mid: m, text: text,
                                              quoteText: it.qt, quoteMid: it.qm, linkPreview: it.lp)
            return   // the letter stays queued until the receipt; every attempt repeats the channel
        }
        // THE NODE DELIVERS (the author's word 24.08): the LIVE WIRE is its first arm, and
        // it fires on EVERY attempt — the knock dedup below silences only the PUSH within a
        // window, never the wire. Before this, a retry inside the knock window was a no-op:
        // the wire leg lived in the wake completion and never ran, so a receiver who came
        // online between windows waited for nothing (precedent 24.08: both phones on, the
        // letter parked in the box, nobody handed it over). The receiver door dedups by mid.
        // A STATE LETTER WAITS FOR ITS RECEIPT LIKE A LOUD ONE (20.09): «in flight» is the queue's
        // record, and a name or a face settled on the node's word was out of the queue with no
        // mark written — every reciprocity found it neither receipted nor pending and sent it
        // again, once a second (the 09.09 storm, and again 18:26 today between T1 and T3). It
        // stays on the sparse rhythm until the peer's receipt or the hour's retirement.
        let settlesOnNode = it.silent && !it.kind.isState
        if !it.silent { _ = MontanaPhoneNode.shared.sendLetter(to: to, mid: m, text: text,
                                                                      quoteText: it.qt, quoteMid: it.qm, linkPreview: it.lp) }
        // 16.6.17 (F2) — THE BELL IS DOSED ON THE FAST RAMP. The wire and the node try on every
        // attempt (1-2-4-8-16-20 s); the bell — a wake, glued by the node per mid — rang on every
        // one of the twelve too, and an undelivered service word to an offline correspondent
        // rang eleven times in 156 s (measured 04.09 17:55, then 429 and a hold). It rings on the
        // first attempt, then the third, the sixth, the tenth, then on the sparse rhythm.
        let bellDue = forced || [0, 2, 5, 9].contains(it.tries) || it.tries + 1 >= fastTries
        if forced { MontanaTrace.mark("bell_forced", mid: m, "door alive — the ramp is skipped try=\(it.tries)") }
        if !bellDue {
            MontanaTrace.markFolded("bell_quiet", "ramp try=\(it.tries + 1) kind=\(MontanaNotify.kind(for: text)) to=\(String(to.prefix(10)))", window: 60, key: to)
            return
        }
        // A long text does not fit the envelope: such a letter used to not arrive AT ALL.
        // The full body rides as a blob, the envelope carries an invisible reference.
        if MontanaWakePush.sealLetterEnvelope(mid: m, text: text, secret: secret,
                                              quoteText: it.qt, quoteMid: it.qm, linkPreview: it.lp) == nil {
            // A repeat after «node accepted» is silent: the banner for this mid has already
            // rung; the envelope is carried in the background (the node holds the duplicate
            // guard too — this is the client half of the same truth).
            let sil = it.silent || it.nodeAck == true
            Task { [weak self] in
                guard let self else { return }
                guard let linkText = await MontanaWakePush.sealLongLetter(mid: m, text: text),
                      let env = MontanaWakePush.sealLetterEnvelope(mid: m, text: linkText, secret: secret,
                                                                   quoteText: it.qt, quoteMid: it.qm, linkPreview: it.lp) else {
                    MontanaLog.event("DELIVERY ✗ mid=\(m.prefix(8)) long-letter blob failed")
                    return   // stays queued — the next attempt will retry
                }
                self.noteWire(m, linkText)   // the landing door seals the reference, not a body it cannot upload
                MontanaWakePush.wake(to, mid: m, sealedEnvelopeB64: env,
                                     envelope: { MontanaWakePush.sealLetterEnvelope(mid: m, text: linkText, secret: secret,
                                                                                    quoteText: it.qt, quoteMid: it.qm, linkPreview: it.lp) },
                                     silent: sil, look: mtPushLook(for: text), slot: mtPushSlot(for: text)) { [weak self] code in
                    guard let self else { return }   // SILENT-OK: the engine died; the letter is in the persistent queue and will retry
                    if code == 200 {
                        // The node accepted the envelope — «sent», NOT «delivered»: a push is
                        // not guaranteed. Only a receipt dequeues; the letter moves to the
                        // sparse rhythm and waits. A silent SERVICE letter gets no receipt by
                        // construction (a receipt for a receipt is eternal correspondence): it
                        // settles here, on node acceptance; the extension box finishes delivery.
                        if settlesOnNode { self.dequeue(m) } else {
                            self.noteNodeAck(m)
                            // ONE CHECKMARK = SENT: the node accepted the envelope, the letter
                            // left the device. That is an honest fact of our own, and it goes
                            // no further: the second checkmark comes only from the receiver's
                            // receipt.
                            // noteNodeAck above already wrote the rung through its one owner.
                        }
                    } else if code == 404 {
                        MontanaTrace.mark("wakepush_tx", mid: m, "404 — the wire already fired this attempt")
                    }
                }
            }
            return
        }
        MontanaWakePush.wake(to, mid: m, sealedEnvelopeB64: nil,
            envelope: { MontanaWakePush.sealLetterEnvelope(mid: m, text: text, secret: secret,
                                                           quoteText: it.qt, quoteMid: it.qm, linkPreview: it.lp) },
            silent: it.silent || it.nodeAck == true, look: mtPushLook(for: text),
            slot: mtPushSlot(for: text)) { [weak self] code in
            guard let self else { return }   // SILENT-OK: the engine died; the letter is in the persistent queue and will retry
            if code == 200 {
                if settlesOnNode { self.dequeue(m) } else {
                    self.noteNodeAck(m)
                    // noteNodeAck above already wrote the rung through its one owner.
                }
            } else if code == 404 {
                _ = MontanaPhoneNode.shared.sendLetter(to: to, mid: m, text: text,
                                                  quoteText: it.qt, quoteMid: it.qm)
            }
        }
    }

    /// This letter's media chunks — off the disk. The manifest names them one by one, so there is nothing to guess.
    private func dropChunks(of text: String) {
        guard text.hasPrefix(mediaMark) else { return }
        let body = String(text.dropFirst(mediaMark.count))
        guard let d = body.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let chunks = obj["chunks"] as? [[String: Any]] else { return }
        MontanaBlobStore.drop(chunks.compactMap { $0["bid"] as? String })
    }

    /// A human tapped resend on a red bubble: reset the letter's clock and knock NOW.
    /// A letter the queue has given up on is re-enqueued under the SAME mid.
    func retryNow(mid: String, to: String, chat: String, text: String) {
        q.async { [self] in
            var a = load()
            if let i = a.firstIndex(where: { $0.mid == mid }) {
                a[i].since = Date().timeIntervalSince1970; a[i].tries = 0; a[i].lastTry = 0
                save(a)
                MontanaTrace.mark("resend_tap", mid: mid, "human retry — clock reset, knocking now")
            } else {
                MontanaTrace.mark("resend_tap", mid: mid, "human retry — letter re-enqueued")
                enqueue(to: to, chat: chat, mid: mid, text: text, silent: false)
            }
        }
        drainAll()
    }

    private func dequeue(_ mid: String) {
        q.async { [self] in
            var a = load()
            guard let i = a.firstIndex(where: { $0.mid == mid }) else { return }
            // THE NODE TAKING A LETTER IS NOT ITS DELIVERY (the author's word 20.09: T3 wore a face of
            // T1 nine days old). The mark used to be written here for a silent state letter — «the
            // peer's screen shows it» by the word of a postman who keeps the letter a day; a peer
            // that came a day later never saw it, and nothing announced the face again until it
            // changed. The mark has ONE meaning and two speakers of the same truth — the peer's
            // receipt of the letter (markDelivered) and the peer's own presence word naming what it
            // holds (heardHeld); a postman writes nothing. The 09.09 storm cannot return: a face is
            // sent only when the peer says it holds another, and never twice a minute.
            a.remove(at: i); save(a)
            // Service letters settle in volleys (a drain hands over dozens at once): the first
            // says the fact, the rest are a number.
            MontanaTrace.markFolded("silent_done", "node took it — dequeued", window: 30)
        }
    }

    /// The node accepted this letter's envelope: mark it and move to the sparse receipt-waiting rhythm.
    private func noteNodeAck(_ mid: String) {
        q.async { [self] in
            var a = load()
            guard let i = a.firstIndex(where: { $0.mid == mid }), a[i].nodeAck != true else { return }
            a[i].nodeAck = true; save(a)
            MontanaTrace.mark("node_ack", mid: mid, "queued — waiting for the receipt")
            // ONE RUNG FOR EVERY LETTER (17.09, the critic): the node holds the cargo and the letter — the
            // row earns «sent» here, as a text row does; «delivered» stays the receipt's alone.
            let chat = a[i].chat
            Task { @MainActor in self.store?.markSentByNode(chat, mid: mid, why: "node 200") }
        }
    }

    /// Cold start: remove from the node the chunks of letters the queue does not hold. The
    /// queue is the only list of living letters and it survives relaunch; whatever it lacks
    /// will never ride.
    func sweepNodeOrphansOnLaunch() {
        // The one-time age sweep of 20.08 (purgeStaleOnce) is gone (07.10, MTRefusal): it put out red every letter an hour old —
        // on a phone that had never run it, a restored queue went red at its first launch. No clock paints red.
        recoverInterruptedPieces()   // the order is mandatory: otherwise a dead upload's chunks count as alive
        q.async { [self] in
            let alive = Set(load().map { $0.mid })
            Task { await MontanaWakePush.sweepOrphanChunks(aliveLetters: alive) }
        }
    }

    /// THE INTENT SURVIVES ITS UPLOAD'S DEATH (18.09, the author's word: one behaviour for any data —
    /// a voice, a photo, a file ride like a text, and a red one leaves without a hand). The chunks of
    /// the dead run are orphans on the node and dead cargo on the phone — a resume reseals anew, so
    /// both go; the record stays in the queue, and the drain re-runs the same send under the same
    /// letter name once the history is in hand. It used to be the other way (20.08): the record left,
    /// the bubble went red, and only a finger brought it back — measured 18.09 13:54: a voice recorded
    /// on a fallen network waited for a hand while the text beside it rode the wake.
    func recoverInterruptedPieces() {
        q.async { [self] in
            let pieces = load().filter { $0.kind == .piece }
            guard !pieces.isEmpty else { return }
            for p in pieces {
                let freed = MontanaWakePush.releaseLetter(p.mid)
                if !freed.isEmpty { MontanaBlobStore.drop(freed); Task { await MontanaWakePush.dropBids(freed) } }
                MontanaLog.event("PIECE ↻ mid=\(p.mid.prefix(8)) the upload did not survive the launch — the drain resumes it, chunks freed=\(freed.count)")
            }
        }
    }
    /// The two shapes of an intent: the screen's {k, e: file} and the store's {k, e: ext, f: file}.
    static func pieceFields(_ text: String) -> (kind: String, file: String, ext: String)? {
        guard let d = text.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let kind = o["k"] as? String else { return nil }
        let file = (o["f"] as? String) ?? (o["e"] as? String) ?? ""
        let ext = (o["f"] as? String) != nil ? ((o["e"] as? String) ?? "") : (file as NSString).pathExtension
        return file.isEmpty ? nil : (kind, file, ext)
    }
    /// The upload has finished: the intent becomes a real letter under the SAME name. The
    /// receipt term starts HERE, not at the upload's start: a big video runs for minutes, and
    /// counting those minutes into the term would paint a working transfer red.
    func promotePiece(mid: String, text: String, to: String, chat: String) {
        q.async { [self] in
            var a = load()
            guard let i = a.firstIndex(where: { $0.mid == mid && $0.kind == .piece }) else {
                // The intent is missing for one of two reasons, and both must be spoken aloud.
                // (1) The queue rejected it before the upload (the pipe is dead) or the person
                //     cancelled — silence here would be a phantom send: chunks uploaded, no
                //     letter. Enqueue the letter the ordinary way: it either rides or honestly
                //     refuses red.
                // (2) SILENT-OK: a letter with this name is ALREADY queued — the promotion came
                //     a second time (a retry overlapped a finished upload). A second copy of
                //     the same letter means two bubbles at the peer; silence here IS the
                //     correct work, not a swallowed refusal.
                if !a.contains(where: { $0.mid == mid }) {
                    MontanaLog.event("PIECE ! mid=\(mid.prefix(8)) intent vanished before promotion — enqueuing the letter directly")
                    enqueue(to: to, chat: chat, mid: mid, text: text, silent: false)
                }
                return
            }
            a[i].kind = .letter; a[i].text = text
            a[i].since = Date().timeIntervalSince1970; a[i].tries = 0; a[i].lastTry = 0
            save(a)
            attempt(mid)
        }
    }

    /// The intent was removed for a reason already shown to the person (upload failure, manual cancel).
    func dropPiece(_ mid: String) {
        MTCompressResume.shared.cancel(letter: mid)   // the ghost resume dies with the letter
        MTEncodeRegistry.shared.cancel(letter: mid)   // and so does the LIVING encode task
        // AND THE CARGO DIES WITH THE LETTER. A cancelled letter used to leave its chunks on
        // the node until the week ran out: the node CANNOT tell an orphan from a living
        // letter's cargo by construction (the manifest is sealed and invisible to it), so only
        // the one who put them there may remove them. Measured 24.08: 2160 chunks and 1.1 GB
        // in one night of tests where nearly every send was cancelled by hand. A record with
        // no cost owner is exactly what the role forbids; the owner here is the sender, and
        // this is the sender's hand.
        let freed = MontanaWakePush.releaseLetter(mid)
        if !freed.isEmpty {
            MontanaTrace.mark("blob_drop", mid: mid, "letter removed by hand — chunks freed n=\(freed.count)")
            Task { await MontanaWakePush.dropBids(freed) }
        }
        q.async { [self] in
            var a = load(); let n = a.count
            a.removeAll { $0.mid == mid && $0.kind == .piece }
            if a.count != n { save(a) }
        }
    }

    // Backstop tick: retries due items when no reachability event fires (long-lived link, no PeerUp).
    private func startTick() {
        q.async { [self] in
            guard tick == nil else { return }
            tick = Task { [weak self] in
                while let self, !Task.isCancelled {
                    // The pickup step is one second: it only LOOKS at what is due, and «due»
                    // is decided by each letter's own term. A twenty-second step made the
                    // minimum delay twenty seconds no matter how short a letter's term was.
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    self.q.async {
                        let a = self.load()
                        if a.isEmpty { self.tick?.cancel(); self.tick = nil; return }
                        let now = Date().timeIntervalSince1970
                        for it in a where now - it.lastTry > self.backoff(it.tries, nodeAck: it.nodeAck == true) { self.attempt(it.mid) }
                        // The cargo check rides the TICK too: with the app sitting open, drainAll
                        // never re-runs, and a node-side wipe would stay invisible until the next
                        // launch. The per-letter throttle inside checkCargo keeps this to 1/min.
                        for it in a where it.kind == .letter && it.text.hasPrefix(mediaMark) {
                            self.checkCargo(it.mid, chat: it.chat, age: now - it.since, text: it.text)
                        }
                        self.reconcile(a)   // M-1/M-2: the queue is the chat's shadow, every 5s
                    }
                }
            }
        }
    }
}
