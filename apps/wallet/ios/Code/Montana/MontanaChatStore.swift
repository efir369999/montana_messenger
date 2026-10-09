//
//  MontanaChatStore.swift
//  Montana — a Montana messenger
//
//  Cut out of ContentView.swift whole, declaration by declaration (the author's word 10.09):
//  nothing here was renamed or rewritten; the file holds one screen and what only it reads.
//

import SwiftUI
import CryptoKit
import MontanaBindings
import PhotosUI
import UserNotifications
import UIKit
import Network
import AVKit
import MediaPlayer
import AVFoundation
import LocalAuthentication
import UniformTypeIdentifiers
import CoreImage
import QuickLook
import Photos
import CoreLocation
import ContactsUI
import Contacts



// Shared message storage for all chats (key — chat name)
struct ScheduledMsg: Codable, Identifiable {
    let id: UUID
    let chat: String
    let convRef: String?
    let text: String
    let fireAt: Double      // Unix time of the scheduled send
}

class ChatStore: ObservableObject {
    // ── STAGE 9: THE CHAT LIST IS STATE, NOT A FRAME (the author's word 24.08: «the app's
    // ordinary state, stored locally rather than drawn»). One persisted
    // record per conversation — preview of the LAST message and its time — written at the
    // single landing door and read synchronously before the first frame. The render reads
    // ONLY this record (SSOT-in-decisions): deriving the preview from the in-memory history
    // at render time was a second judge, and it showed the frozen creation-time text for
    // seconds while the history was still decrypting (precedent: notification tap showed
    // the FIRST message of the chat, then the list repainted).
    @Published var listState: [String: [String: String]] = [:]
    private var listStateLoaded = false
    func loadListStateOnce() {
        guard !listStateLoaded else { return }
        listStateLoaded = true
        // THE KEYCHAIN, NOT THE VAULT (stage 9, caught on the author's third cold run): the
        // vault opens with the device key, and on a TRUE cold start — the process born from
        // the notification tap — that key is nil for the first moments (the history reader
        // literally spins waiting for it). A record the frame cannot read is not state.
        // The keychain is readable from the first instant by BOTH processes and already
        // guards the same display class (the extension inbox holds full letter texts there).
        if let d = MontanaKeychain.get("chatListState"),
           let m = try? JSONDecoder().decode([String: [String: String]].self, from: d) { listState = m }
        // The extension's overlay rides on top: letters that landed while the app was dead
        // are already the newest truth for their conversations. Applied before the first
        // frame; the ordinary door re-writes the same records the moment the letters land.
        var overlayApplied = 0
        var pendingUnread: [String: Int] = [:]
        var stamps: [(conv: String, at: Int)] = []
        if let d = MontanaKeychain.get("chatListOverlay"),
           let ov = try? JSONDecoder().decode([String: [String: String]].self, from: d), !ov.isEmpty {
            for (conv, rec) in ov {
                // The door's letter is the newest: its words and time replace the record's, and a
                // known name never regresses (the door does not always carry it).
                var fresh = rec
                if fresh["n"] == nil, let n = listState[conv]?["n"], !n.isEmpty { fresh["n"] = n }
                listState[conv] = fresh; overlayApplied += 1
                if let u = Int(rec["u"] ?? ""), u > 0 { pendingUnread[conv] = u }
                // «atm» is the moment in milliseconds; «at» is the same moment in seconds, kept
                // for app builds that only know the older word.
                if let atm = Int(rec["atm"] ?? "") { stamps.append((conv, atm)) }
                else if let at = Int(rec["at"] ?? "") { stamps.append((conv, at)) }
            }
            persistListState()
        }
        // The landing door increments the ONE record itself ([C-1], the contract above
        // updateBadge). What it left here is used only to notice that letters are waiting —
        // never as a second slice of the number the row draws.
        if !pendingUnread.isEmpty {
            MontanaP2PTrace.mark("list_state", "landing door left \(pendingUnread.values.reduce(0, +)) letters")
        }
        // THE ORDER FOLLOWS THE NEWEST EVENT ON THE DEVICE, and while the app was dead the newest
        // events are exactly these. Applied before the first frame, so the list never shows
        // yesterday's order for the second it takes the drain to run.
        for (conv, at) in stamps {
            // The landing door speaks in the same unit the map is kept in, so its word needs no
            // translation and no ordering pass: each conversation simply carries the moment its
            // letter arrived. Older doors say it in seconds — one multiplication, under the
            // threshold no millisecond stamp can be below ([P2P-COMPAT]).
            noteOrder(conv, at: at < 100_000_000_000 ? at * 1000 : at)
        }
        MontanaP2PTrace.mark("list_state",
            "loaded n=\(listState.count) overlay=\(overlayApplied) bumped=\(stamps.count) pending_unread=\(pendingUnread.values.reduce(0, +))")
    }
    private func persistListState() {
        if let d = try? JSONEncoder().encode(listState) { MontanaKeychain.set("chatListState", d) }
    }
    /// A DELETED LETTER LEAVES NO PICTURE BEHIND (the critic's word 19.09): the row's small copy and
    /// the video's poster lie beside the media store under their own names, and a deletion that
    /// dropped only the cargo left the deleted photo drawable — and drawn, in the list row.
    func forgetPictures(of m: Message) {
        if let f = m.docFile { MTDocLink.forget(f) }
        if let f = m.imageFile { MontanaSmallPicture.forget(f); imageDecodeCache.removeObject(forKey: f as NSString) }
        if let f = m.videoFile {
            videoThumbCache.removeObject(forKey: f as NSString)
            try? FileManager.default.removeItem(at: posterURL(f))
            MTNoteFrame.forget(f)
            MontanaVideoMark.unmark(f)
        }
    }
    /// DELETE FOR ME — the one road ([C-1]): the chat's menu, the profile's menu and the
    /// selection bars all call this. The row goes, the tombstone stands (a repeat delivery is
    /// refused in append), the reception intent is dropped, the shipping crate thrown out.
    func deleteLocally(chat: String, _ m: Message) {
        // A COIN LETTER OF MINE ON ITS WAY KEEPS ITS ROW (the author's word «fix all points in order» 05.10.2026 21:4x MSK, the
        // coin audit's first point; MTCoinSend.travels): the row is the queue's one reason to carry the letter, and without it the
        // coins it took were gone for both sides.
        if coinTravels(m) {
            MontanaP2PTrace.mark("delete_refused", "a coin letter on its way keeps its row and its coins mid=\(String(m.mid.prefix(12)))")
            return
        }
        dropRows(chat) { $0.id == m.id }
        forgetPictures(of: m)
        MTRowJournal.drop(chat, mid: m.mid)
        if let sid = m.msgId, !sid.isEmpty {
            deletedMids.insert(sid)
            dropPendingMedia(sid)
        }
        if let body = m.text.hasPrefix(mediaMark) ? String(m.text.dropFirst(mediaMark.count)) : nil,
           let d = body.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
           let chunks = obj["chunks"] as? [[String: Any]] {
            MontanaBlobStore.drop(chunks.compactMap { $0["bid"] as? String })
        }
        save()
    }
    /// A coin letter of mine on its way (MTCoinSend.travels): the cheap marks first, the book only for a coin letter of mine.
    func coinTravels(_ m: Message) -> Bool {
        guard m.isFromMe, m.deliveryStatus == .sending || m.deliveryStatus == .sent, m.coinLetter != nil else { return false }
        // The book lives on the main actor; asked from another thread, the letter is held as travelling -- the deletion waits
        // and the coins stay whole, never the other way round.
        guard Thread.isMainThread else { return true }
        return MainActor.assumeIsolated { MTCoinSend.travels(m) }
    }
    /// Whether a conversation holds a coin letter of mine on its way: the chat's deletion waits for its road to end.
    func coinsTravel(_ chat: Chat) -> Bool {
        Set([chat.convRef, chat.name]).contains { key in (messages[key] ?? []).contains { m in coinTravels(m) } }
    }
    static func listPreview(_ m: Message) -> String {
        // The fold reaches the list row as well (Guideline 1.2): a folded letter's words do not
        // stand in the list beside the name.
        if !m.isFromMe, MontanaSafety.filterOn, MontanaContentFilter.flags(m.text) { return String(localized: "Hidden by the filter", bundle: MTLanguage.bundle) }
        if let ci = callInfoOf(m.text) {
            let icon = ci.video ? "📹" : "📞"
            if ci.missed { return icon + " " + String(localized: ci.incoming ? "Missed call" : "Unanswered call", bundle: MTLanguage.bundle) }
            return icon + " " + String(localized: ci.video ? "Video call" : "Voice call", bundle: MTLanguage.bundle)
        }
        if let r = releaseInfoOf(m.text) { return String(localized: "New version", bundle: MTLanguage.bundle) + " " + String(r.build) }
        if let mp = mediaPreview(m) { return mp }
        // Everything the parsed letter does not already answer goes to the ONE vocabulary both
        // doors share, so a row never gets two different words for the same letter.
        return MTRowLetter.preview(m.text)
    }
    /// THE ONE BIRTH POINT OF A ROW IN THE FEED (17.09): a row takes its place BY BIRTH, not at the
    /// end. The feed used to append and let the chat sort on display, so «the last row» meant two
    /// things — the last LANDED (the list record, the row's stage) and the newest BORN (the chat).
    /// Measured T1 04:43Z: two letters born before the person's reply landed seven minutes after
    /// it, sat at the end, and the list wore their words while the chat showed the reply last.
    /// Now every reader of `.last` sees the newest letter — the very one the chat draws at the bottom.
    /// Returns the row as placed — the journal and the archive keep that very row, not the caller's copy.
    @discardableResult
    func placeRow(_ chat: String, _ row: Message) -> Message {
        // A LETTER OF THEIRS BORN IN THE CHAT ON SCREEN IS READ AT BIRTH (the author's word 23.09): the count never meets
        // it. On screen means the app too: a letter landing under a locked phone with the chat left open is unread, as
        // the icon says, until the person is back in the chat (the conversation's return reads it).
        var row = row
        if !row.isFromMe, chat == openConv, MTForeground.active { row.isRead = true }
        var arr = messages[chat] ?? []
        if let last = arr.last, !ChatStore.before(row, last) { arr.append(row) }
        else { arr.insert(row, at: arr.firstIndex(where: { ChatStore.before(row, $0) }) ?? arr.count) }
        messages[chat] = arr
        return row
    }
    /// THE ONE WAY A ROW LEAVES THE FEED ([C-1], the author's word 19.09: Saved Messages wore a
    /// photo already deleted and words that were not its last). «Delete for me», the selection's
    /// delete, a call's log and a lost cargo each removed rows on their own, and the list record —
    /// written at a landing and at «delete for everyone» only — kept the deleted letter's words and
    /// thumbnail. Every removal passes here now, and the record follows the newest row that stands.
    func dropRows(_ chat: String, where gone: (Message) -> Bool) {
        guard var arr = messages[chat], arr.contains(where: gone) else { return }
        arr.removeAll(where: gone)
        messages[chat] = arr
        noteListState(chat, last: arr.max(by: ChatStore.before), force: true)   // the one step back in time
    }
    /// The landing door signs its record with the moment of arrival and never with a birth.
    static func isDoorRecord(_ r: [String: String]) -> Bool { r["b"] == nil && r["atm"] != nil }
    /// EVERY RECORD REBUILT FROM THE FEED by the one builder (the law: what stands last in the chat
    /// stands in the list). `keepDoorRecords` — at history load, while the box may still hold the
    /// door's letters, the door's records stand; once the box is drained (the overlay dies) the feed
    /// is the only truth and nothing is kept. An emptied chat's record goes.
    func reconcileListWithFeed(_ feed: [String: [Message]], keepDoorRecords: Bool) {
        guard historyLoaded else { return }   // a partial feed is no truth to mirror; the load's own pass follows
        var healed = listState; var changed = false
        for (chat, arr) in feed {
            if keepDoorRecords, let rec = healed[chat], Self.isDoorRecord(rec) { continue }
            guard let last = arr.max(by: ChatStore.before) else {
                if healed[chat] != nil { healed[chat] = nil; changed = true }
                continue
            }
            let full = listRecord(chat, last: last)
            if healed[chat] != full { healed[chat] = full; changed = true }
        }
        if changed { listState = healed; persistListState() }
    }
    /// THE LAST LETTER OF A CHAT, ONE DEFINITION ([C-1], the author's law 19.09: what stands last
    /// in the chat stands in the list): the newest by the feed's own order — birth, then id — the
    /// very row the chat draws at the bottom, not the array's end. A landing keeps the array in
    /// order (placeRow), but a merge, a share-extension letter or an old build's append could stand
    /// past its place, and the list then named a letter the chat did not show last.
    /// ASKED ONCE PER CHANGE OF THE LETTERS (the critic 23.09): a row of the list asks it for its words, its
    /// time and its stage, and the list passes on every change of the store — a presence word, a draft, a
    /// count — each pass walking every chat's whole history two and three times. The answer is kept until the
    /// letters change (messagesRev); the keeping is the main thread's alone, any other thread walks afresh.
    func lastLetter(_ chat: String) -> Message? {
        guard Thread.isMainThread else { return messages[chat]?.max(by: ChatStore.before) }
        if keptRev != messagesRev { lastKept.removeAll(keepingCapacity: true); keptRev = messagesRev }
        if let kept = lastKept[chat] { return kept }
        let last = messages[chat]?.max(by: ChatStore.before)
        lastKept.updateValue(last, forKey: chat)   // «none» is kept too: an empty chat is asked as often
        return last
    }
    private var lastKept: [String: Message?] = [:]
    private var keptRev = -1
    /// The ONE writer: called wherever the last message of a conversation changes —
    /// landing, deletion, history merge. nil last = the conversation emptied.
    /// Main-thread by convention (like bump/append around it), not by annotation.
    /// THE RECORD IS THE FEED'S MIRROR, WITH ONE EXCEPTION BY ORIGIN (the critic's word 19.09):
    /// only the LANDING DOOR's record — written from the box while the app slept, `atm` and no `b`
    /// (isDoorRecord) — may stand ahead of the feed, and only while its letter is still on its way.
    /// A record the app wrote itself (`b`) describes a letter the app already had: if the feed no
    /// longer holds it, the letter is gone, and the record follows the feed at once. Judging by
    /// TIME instead kept a deleted photo's record immortal — newer than everything that remained —
    /// through every start (T1 18.09 20:54Z–21:01Z, list_audit: the record's photo against the feed's words).
    func noteListState(_ chat: String, last m: Message?, force: Bool = false) {
        // A step of a chess game never writes the row (29.09): the record follows the newest letter that is one.
        let m = m.flatMap { $0.isChessStep ? messages[chat]?.last(where: { !$0.isChessStep }) : $0 }
        guard let m else {
            if listState[chat] != nil { listState[chat] = nil; persistListState() }
            return
        }
        // THE SAME LETTER LANDING TAKES THE DOOR'S PLACE (20.09): the door knows the kind but not the
        // file, and its record stood ahead of the very letter it announced — the row wore a plate
        // until the next relaunch rebuilt it. The door signs its record with the letter's name now.
        let sameLetter = listState[chat].flatMap { $0["id"] }.map { m.mid == $0 || m.mid == "mid:" + $0 } ?? false
        if !force, !sameLetter, let old = listState[chat], Self.isDoorRecord(old), let ob = Double(old["atm"] ?? ""), ob > m.createdAt * 1000 + 500 { return }
        let rec = listRecord(chat, last: m)
        if listState[chat] != rec { listState[chat] = rec; persistListState() }
    }
    /// THE ONE BUILDER OF A LIST RECORD ([C-1], the author's word 16.09: «from local memory, at
    /// once»): the words, the time, the thumbnail's kind and file, whose word it was, the known
    /// name. The landing door and the healing at history load used to write records of their own
    /// with only the words and the time — every cold start erased the thumbnails and the names
    /// the door had written the day before, and the list drew glyphs where the pictures had stood.
    func listRecord(_ chat: String, last m: Message) -> [String: String] {
        var rec = ["p": Self.listPreview(m), "t": m.time, "b": String(Int(m.createdAt * 1000))]   // b: the letter's birth, ms — the record's clock
        // The row's thumbnail (the author's word 15.09: the voice's orb and the note's poster stand
        // in the list as in the player bar) — from the record, never from the history (stage 9).
        if let k = Self.rowMediaKind(m) {
            rec["k"] = k
            if let f = Self.rowMediaFile(m) { rec["f"] = f }
        }
        // s: the stage of my last letter (of its plate, ladderLetter) — the row is born wearing it (rowStatus); the ladder's one
        // door keeps it (followStages).
        if m.isFromMe { rec["m"] = "1"; rec["s"] = ladderLetter(m, in: chat).deliveryStatus.rawValue }
        if let n = MTNameBook.known(chat), !n.isEmpty { rec["n"] = n }
        else if let n = listState[chat]?["n"], !n.isEmpty { rec["n"] = n }   // a known name never regresses
        // THE ANSWER OUTLIVES A REBUILD (20.09, measured T1 20:28:17→18: the row wore the reaction for
        // a second and a receipt's rebuild took it off). A reaction is the row's newest event until a
        // letter born AFTER it lands: a rebuild from a letter older than the answer keeps the answer
        // and the answered letter's words.
        if let old = listState[chat], answerStands(old, in: chat, over: m) {
            for k in ["r", "rm", "rat", "ra", "p", "k", "f", "m", "t"] { rec[k] = old[k] }
        }
        return rec
    }
    /// The record's answer (a reaction) is the row's newest event over this letter — PROVEN, never assumed by kind (the
    /// critic 24.09): the answered letter, named by the record (ra), stands in the feed, still wears the record's words,
    /// was born before the answer, and the answer came after this letter. A deleted, an edited or a vanished letter, or a
    /// letter born after the answer, leaves the record to the feed. ONE question for the record's builder and for the
    /// audit (23.09): the audit did not know the answer's rule and called a record that rightly wears the answered
    /// letter's words «ahead of the feed»; the rule that replaced it took every record with an answer off the check.
    func answerStands(_ rec: [String: String], in chat: String, over m: Message) -> Bool {
        guard let r = rec["r"], !r.isEmpty, let rat = Double(rec["rat"] ?? ""), m.createdAt * 1000 <= rat,
              let ra = rec["ra"], let answered = messages[chat]?.last(where: { $0.mid == ra }) else { return false }
        return answered.createdAt * 1000 <= rat && Self.listPreview(answered) == rec["p"]
    }

    /// THE REVISION OF THE LETTERS (the critic 22.09): one number that moves with every change of any
    /// letter, so a screen can keep what it derived from them and rebuild only when this moved.
    private(set) var messagesRev = 0
    @Published var messages: [String: [Message]] = [:] {
        didSet {
            messagesRev &+= 1
            callLogMemo = nil   // the call log is derived from here; the next reader builds it once
            musicMemo = nil     // and the music library, the same way
            mediaMemo = nil     // and the gallery's moments (25.09)
            if !loading { scheduleSave() }   // debounce: encode the whole history in the background (a batch of incoming doesn't freeze the UI)
        }
    }
    private var callLogMemo: [CallRecord]?
    private var musicMemo: (lent: Int, list: [MusicTrack], byFile: [String: MusicTrack])?
    private var mediaMemo: (stories: String, list: [MTMoment])?   // the gallery's moments, kept the same way (25.09)
    private var saveWork: DispatchWorkItem?
    /// The initial store read is running. Assigning each field triggers its own write back —
    /// on load that is nine writes in a row, each encrypting and putting a block into the
    /// shared settings store. Measured: building the correspondence store took 1.84 seconds
    /// on the main thread, and nearly all of it was writing what had just been read. We read —
    /// we do not write.
    private var loading = false
    /// The vault's light half is read: names, faces and stamps stand as the vault holds them. A word about what this phone
    /// holds of a peer is true only from here (E2E.faceTail, E2E.heldTail — 24.09).
    var lightRead: Bool { !loading }
    // pinned messages in each chat: chat name -> array of ids (as strings), up to 5
    @Published var pinned: [String: [String]] = [:] {
        didSet { if !loading { savePinned() } }
    }
    @Published var scheduled: [ScheduledMsg] = [] {
        didSet { if !loading { saveScheduled() } }
    }
    // chat order by recency (first — the most recent). For bumping a chat to the top.
    /// THE UNREAD COUNT HAS ONE OWNER, AND IT IS THIS RECORD. It lives in the shared keychain,
    /// so it is readable by BOTH processes and on the FAST road — before the first frame, with no
    /// vault to unlock and no history to decrypt. The app is its authoritative writer (a full
    /// rewrite on every recount); the landing door only increments it while the app is dead.
    ///
    /// Every previous closure of «stale unread flickers» patched a symptom while the number kept
    /// living in two places: this record and the row's own persisted `unread` field. A stored
    /// copy of a derived value always wins the first frame and always shows the past — so the
    /// row no longer reads its own field at all, and there is nothing stale left to draw
    /// (the author's word 29.08: «we closed this before and it came back»).
    @Published var unreadCounts: [String: Int] = ChatStore.loadUnreadCounts()

    static func loadUnreadCounts() -> [String: Int] {
        guard let d = MontanaKeychain.get("unreadCounts"),
              let m = try? JSONDecoder().decode([String: Int].self, from: d) else { return [:] }
        return m
    }
    /// What the row draws. One question, one answer, no second slice to add.
    func unread(for chat: String) -> Int { max(0, unreadCounts[chat] ?? 0) }
    /// The preview and the time a row shows, asked in ONE place: the row draws them and the
    /// container asks the very same question when deciding whether that row changed at all. Two
    /// copies of this rule would let a row change while the container believed it had not ([C-1]).
    func rowPreview(_ chat: Chat) -> String {
        if let p = listState[chat.name]?["p"], !p.isEmpty { return p }
        if let last = lastLetter(chat.name) { return ChatStore.listPreview(last) }
        return messages[chat.name] == nil ? chat.lastMessage : ""   // an emptied conversation says nothing (19.09)
    }
    /// THE ONE WORD FOR WHAT A LETTER CARRIES ([C-1], the author's word 16.09): every kind of
    /// media, named here and nowhere else — the row's thumbnail, the reply bar's, any other
    /// reads this word and draws MTLetterThumb; no screen takes the letter apart on its own.
    static func rowMediaKind(_ m: Message) -> String? {
        // A call's letter wears the menu's own glyph (the author's word 16.09): the handset, the camera.
        if let ci = callInfoOf(m.text) { return ci.video ? "vcall" : "acall" }
        if m.audioFile != nil { return "aud" }
        if let v = m.videoFile { return v.hasPrefix("vnote_") ? "vnote" : "vid" }
        if m.imageFile != nil { return "img" }
        if let d = m.docFile { return mtIsAudioName(m.docName ?? "") || mtIsAudioName(d) ? "music" : "doc" }
        // A letter with a web link wears the bar's own link glyph (the author's word 16.09).
        if !m.text.hasPrefix(mediaMark), MTLinkPreviewBuilder.firstWebURL(in: m.text) != nil { return "link" }
        return nil
    }
    /// The file the thumbnail is drawn from, for the word above.
    static func rowMediaFile(_ m: Message) -> String? { m.audioFile ?? m.videoFile ?? m.imageFile ?? m.docFile }
    /// What the row's thumbnail stands for: «aud» (the orb, mine or theirs) or «vnote» with the
    /// poster's file when the app's door has named it; nil — no thumbnail.
    func rowMedia(_ chat: Chat) -> (kind: String, file: String?, mine: Bool)? {
        guard let rec = listState[chat.name], let k = rec["k"], !k.isEmpty else { return nil }
        return (k, rec["f"], rec["m"] == "1")
    }
    /// The letter that carries a file (the bar's way back to its bubble, the author's word 15.09).
    func letterId(of file: String, in chat: String) -> MID? {
        messages[chat]?.last(where: { $0.audioFile == file || $0.videoFile == file })?.id
    }
    /// THE REACTION IN THE ROW, AS UNDER THE BUBBLE (the author's word 20.09: «the thumbnails in the
    /// chat list show the face and the answer as the plate does»): the newest event of a conversation
    /// may be an answer to a letter, and the row wears it the plate's way — the face of whoever
    /// answered, the answer, then the letter's words. Written by the two doors a reaction has (mine,
    /// theirs); the next letter's record replaces it (listRecord builds afresh).
    func rowReaction(_ chat: Chat) -> (emoji: String, mine: Bool)? {
        guard let rec = listState[chat.name], let r = rec["r"], !r.isEmpty else { return nil }
        return (r, rec["rm"] == "1")
    }
    /// `at` — the answer's own birth: the peer's word carries it (its sender's clock, as every letter's birth); mine is now.
    func noteReaction(_ chat: String, _ emoji: String?, mine: Bool, on m: Message, at: Double? = nil) {
        var rec = listState[chat] ?? listRecord(chat, last: lastLetter(chat) ?? m)   // the base speaks of the last letter; the answer's words follow
        if let e = emoji, !e.isEmpty {
            let born = at ?? Date().timeIntervalSince1970
            rec["r"] = e; rec["rm"] = mine ? "1" : nil
            rec["ra"] = m.mid                                      // the letter answered, by its one name
            rec["p"] = Self.listPreview(m)                       // the letter answered, in the row's words
            if let k = Self.rowMediaKind(m) { rec["k"] = k; rec["f"] = Self.rowMediaFile(m) } else { rec["k"] = nil; rec["f"] = nil }
            rec["m"] = m.isFromMe ? "1" : nil
            rec["t"] = MTClock.time(Date(timeIntervalSince1970: born))   // the answer's own moment, not its arrival
            // When: a letter born later replaces it, an older rebuild does not — the answer's birth, not the moment this
            // phone applied it (the critic 24.09: a letter born after the answer and drained in the same batch was taken
            // for an older one).
            rec["rat"] = String(Int(born * 1000))
        } else if rec["r"] != nil {
            rec["r"] = nil; rec["rm"] = nil; rec["rat"] = nil; rec["ra"] = nil   // the answer taken back: the words stay
        }
        if listState[chat] != rec { listState[chat] = rec; persistListState() }
    }
    func rowTime(_ chat: Chat) -> String {
        // WHEN, NOT THE CLOCK (the author's word 22.09): the last letter's moment as the list stamps it —
        // the time today, the weekday within the week, the day and the month past it (MTClock.listStamp).
        if let at = lastLetter(chat.name)?.createdAt, at > 0 { return MTClock.listStamp(Date(timeIntervalSince1970: at)) }
        // A ROW IS BORN WHOLE (the critic 23.09): before the letters are read, the record's own moment is
        // stamped the same way, so the first frame says what the warm list will say. The record's clock word
        // stood here and was replaced a third of a second later (T3 23.09 17:13: rows reconfigured at launch
        // for «time»; a reaction's record wore the answer's clock while the warm row wore the letter's day).
        if let rec = listState[chat.name], let at = Self.recordMoment(rec) { return MTClock.listStamp(Date(timeIntervalSince1970: at)) }
        if let t = listState[chat.name]?["t"], !t.isEmpty { return t }
        if let t = lastLetter(chat.name)?.time, !t.isEmpty { return t }
        return messages[chat.name] == nil ? chat.time : ""
    }
    /// A ROOM WITHOUT AN ADDRESS HAS NO WIRE (the author's word 11.09): Saved Messages is this
    /// device writing to itself. Nothing there is sent, waits, or fails — the one predicate every
    /// road asks. Measured on T1 11.09 10:26:56: two share-sheet attachments to Saved were born
    /// at the clock, no road settled them, and the cold-start sweep painted them red with a retry.
    static func isLocalRoom(_ chat: String) -> Bool { chat == savedMessagesKey || chat == montanaRoomKey || chat == meshRoomKey }
    /// The room of everyone on the mesh (29.09): no pipe; its words ride the radio (MTMeshRoom), its row stands first while the
    /// switch «Findable on the mesh» is on.
    static func isMeshRoom(_ chat: String) -> Bool { chat == meshRoomKey }
    /// The room where Montana itself speaks (29.09): no wire, the logo for a face, the crown beside the name.
    static func isMontanaRoom(_ chat: String) -> Bool { chat == montanaRoomKey }
    /// THE STAGE THE ROW SHOWS (the author's word 11.09): the last letter's own stage when the
    /// last word was mine; nil when it was theirs, and nil in a room without a wire.
    func rowStatus(_ chat: Chat) -> DeliveryStatus? {
        guard !Self.isLocalRoom(chat.name) else { return nil }
        if let last = lastLetter(chat.name) {
            guard last.isFromMe, !MTRowLetter.ownRow(last.text) else { return nil }   // a row of this phone's own (a group's event) rode nowhere
            // A letter of a plate wears the plate's stage (ladderLetter, 29.09). A voice or a round note climbs its third rung by
            // its playing, as under its bubble (MTPlayed, the critic 25.09).
            let lead = ladderLetter(last, in: chat.name)
            return MTPlayed.of(lead, peer: chat.name)?.status(lead.deliveryStatus) ?? lead.deliveryStatus
        }
        // Before the letters are read the record says it (the critic 23.09: T1 launched with seventeen rows
        // bare of their dots and dressed them 0.4 s later). A door's record is the peer's letter: no stage.
        return listState[chat.name]?["s"].flatMap(DeliveryStatus.init(rawValue:))
    }
    /// THE LETTER WHOSE STAGE A ROW WEARS (29.09, the author's word: «in the chat the status is read, and there three grey
    /// dots»): a letter on its own speaks for itself; a letter of a plate speaks for the plate — its slowest letter (MTLadder).
    /// The row read the plate's LAST letter and the plate its FIRST: seventeen minutes of grey dots in the list under
    /// «Read» in the chat (the iPhone 15, 19:47–20:04Z). The plate is gathered as the feed folds it: the letters of one pick's
    /// key, on one side, that fold into a plate (MTMosaic.folds); the letter asked about stands in it as given.
    func ladderLetter(_ m: Message, in chat: String) -> Message {
        guard let key = m.groupKey, MTMosaic.folds(m) else { return m }
        let plate = (messages[chat] ?? []).filter { $0.id != m.id && $0.groupKey == key && $0.isFromMe == m.isFromMe && MTMosaic.folds($0) }
        return MTLadder.lead(plate + [m]) ?? m
    }
    /// THE MOMENT A RECORD SPEAKS OF, in seconds — one reading for the cold row: the birth the app wrote
    /// (b, ms), the birth the door's letter carries in its name (id), the door's arrival (atm, ms; the older
    /// door's at, s). The birth first: it is the moment the warm row stamps once the letter lands.
    static func recordMoment(_ r: [String: String]) -> TimeInterval? {
        if let b = Double(r["b"] ?? ""), b > 0 { return b / 1000 }
        if let id = r["id"], let born = birthMs(fromMid: id), born > 0 { return born }
        if let a = Double(r["atm"] ?? ""), a > 0 { return a / 1000 }
        if let a = Double(r["at"] ?? ""), a > 0 { return a }
        return nil
    }
    /// WHERE A CONVERSATION STANDS IN THE LIST - a field of the record, not an outside array.
    ///
    /// The order used to be a separate array of names, written from several places and turned into
    /// a sort by linear search of a name's position on every frame; one of those writers assigned
    /// the array whole and erased the head another writer had already applied (patched once, at
    /// the symptom). Order is a property OF a conversation: the number of the newest event that
    /// happened to it on this device. Two conversations compare by one integer, so "reshuffle"
    /// has nowhere left to happen and a letter changes exactly one number.
    /// AND IT IS READ BEFORE THE FIRST FRAME. The order used to live behind the vault, which a
    /// true cold start cannot open for the first moments: every row was born with the same
    /// number, the list opened sorted by address, and a second later the real order arrived and
    /// the whole list rearranged itself in front of the person. It lives in the keychain now, for
    /// the same reason the name's cold mirror does — the first frame is already the right one.
    /// AND IT IS ONE KIND OF NUMBER, WRITTEN BY WHOEVER SEES THE EVENT FIRST. The number used
    /// to be a counter the app kept beside the map — a second fact that could fall behind it,
    /// and did: on a launch from a notification the counter started at zero while the map held
    /// large numbers, so the conversation the letter had just arrived in was stamped BELOW every
    /// other one and only climbed to the top when the vault opened and the counter caught up.
    /// That is the reordering seen after tapping a notification, and it existed because one fact
    /// had two representations — a counter here, a moment at the landing door.
    /// There is no counter now: the order of a conversation is the MOMENT of its newest event,
    /// in milliseconds, and both doors write the same kind of number into the same map.
    @Published private(set) var orderSeq: [String: Int] = ChatStore.loadOrderSeq()
    static func nowMs() -> Int { Int(Date().timeIntervalSince1970 * 1000) }

    static func loadOrderSeq() -> [String: Int] {
        if let d = MontanaKeychain.get("orderCold"),
           let m = try? JSONDecoder().decode([String: Int].self, from: d), !m.isEmpty {
            return m
        }
        // The former shapes, read once and never again: the map behind the vault, and before it
        // the array whose head was the freshest conversation.
        if let s = MontanaLocalVault.getString("orderSeq"),
           let m = try? JSONDecoder().decode([String: Int].self, from: Data(s.utf8)), !m.isEmpty {
            return m
        }
        let legacy = MontanaLocalVault.getStringArray("recentOrder") ?? []
        var m: [String: Int] = [:]
        for (i, name) in legacy.enumerated() { m[name] = legacy.count - i }
        return m
    }
    private func persistOrder(force: Bool = false) {
        guard force || !loading, let d = try? JSONEncoder().encode(orderSeq) else { return }
        MontanaKeychain.set("orderCold", d)
    }
    /// The one door the whole map goes through.
    func applyOrder(_ m: [String: Int]) {
        orderSeq = m
        persistOrder(force: true)
    }
    /// A SET THE FIRST FRAME CONSULTS LIVES WHERE THE FIRST FRAME CAN READ IT. Pinned, archived,
    /// erased, read, marked-unread and muted all decided what the list shows and in what order,
    /// and all of them lived only behind the vault, which a true cold start cannot open for the
    /// first moments. So the first picture was drawn without them and the second one with — a
    /// pinned conversation jumped to the top, an archived one vanished, in front of the person.
    /// The muted set already had this mirror for the extension; the other five now have it too.
    static func coldSet(_ key: String) -> Set<String> {
        guard let d = MontanaKeychain.get(key),
              let a = try? JSONDecoder().decode([String].self, from: d) else { return [] }
        return Set(a)
    }
    private func mirrorCold(_ key: String, _ set: Set<String>) {
        MontanaKeychain.set(key, (try? JSONEncoder().encode(Array(set))) ?? Data())
    }
    /// Where a row stands. One question, one answer, no second opinion to sort by.
    func order(of chat: String) -> Int { orderSeq[chat] ?? 0 }
    /// Conversations by freshness - for the screens that want names rather than rows.
    var recentNames: [String] {
        orderSeq.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map(\.key)
    }
    @Published var pinnedChats: Set<String> = ChatStore.coldSet("pinnedCold") {       // pinned chats (at the top of the list)
        didSet {
            mirrorCold("pinnedCold", pinnedChats)
            if !loading { MontanaLocalVault.setStringArray("pinnedChatsList", Array(pinnedChats)) }
        }
    }
    @Published var forcedUnread: Set<String> = ChatStore.coldSet("forcedUnreadCold") {      // manually marked «unread»
        didSet {
            mirrorCold("forcedUnreadCold", forcedUnread)
            if !loading { MontanaLocalVault.setStringArray("forcedUnread", Array(forcedUnread)); recalcBadge() }
        }
    }
    func togglePinChat(_ name: String) {
        if pinnedChats.contains(name) { pinnedChats.remove(name) }
        else if pinnedChats.count < 5 { pinnedChats.insert(name); bump(name) }   // maximum 5 pinned, the new one — to the very top
    }
    /// THE ROW'S MARK, BOTH WAYS (the author's word 23.09: «the number of unread for this chat, as on the icons,
    /// and in the menu the mark reset or assigned right»). Unread is the letters' own word (isRead, recalcBadge);
    /// the hand mark means «at least one» on a chat with nothing unread — the row's dot. The menu reads what
    /// stands: a chat with something unread is marked read (its letters become read; the peer hears nothing —
    /// one's own bookkeeping), a chat with nothing unread takes the hand mark.
    func hasUnread(_ name: String) -> Bool { unread(for: name) > 0 || forcedUnread.contains(name) }
    func toggleUnread(_ name: String) {
        if hasUnread(name) { markRead(name, tellPeer: false) } else { forcedUnread.insert(name) }
    }
    /// A letter of theirs landed unread: the row shows the number now, and the hand mark («at least one») yields.
    func handMarkYields(_ name: String) { if forcedUnread.contains(name) { forcedUnread.remove(name) } }
    /// The same, for a whole feed at once (the old verdict taken in, a copy laid): a hand mark stands only where
    /// nothing is unread. Returns how many marks yielded.
    @discardableResult
    func handMarksYield(to feed: [String: [Message]]) -> Int {
        let lettered = Set(feed.compactMap { k, v in v.contains(where: { !$0.isFromMe && !$0.isRead && callInfoOf($0.text) == nil }) ? k : nil })
        let yielded = forcedUnread.intersection(lettered)
        if !yielded.isEmpty { forcedUnread.subtract(yielded) }
        return yielded.count
    }
    // THE MISSED CALLS ARE COUNTED, NEVER STORED (the author's word 18.09): a number kept apart from
    // the call log came back from the dead — the zero written on opening the calls page did not
    // survive a swipe-kill three seconds later, and the cold start read the old one (T1 19:25:09).
    // Like the unread letters, the count is derived: the incoming missed rows of the log newer than
    // the moment the calls page was last seen; that moment lives in the sealed vault, as lastSeenMap.
    @Published private var callsSeenAtStamp: Double = 0
    private var callsSeenAtRead = false
    /// The stamp is read once the vault key exists — a sealed vault answers nothing, and «nothing»
    /// must not count every missed call of history as unseen.
    private func loadCallsSeenAt() {
        guard !callsSeenAtRead, MontanaDeviceKey.key != nil else { return }
        callsSeenAtRead = true
        if let s = MontanaLocalVault.getString("callsSeenAt"), let v = Double(s) { callsSeenAtStamp = v }
        else {
            // The first run of this construction: the past is seen — the retired counter stood at
            // what the person had already cleared, not at the whole history.
            callsSeenAtStamp = Date().timeIntervalSince1970
            MontanaLocalVault.setString("callsSeenAt", String(callsSeenAtStamp))
        }
    }
    var missedCallsUnseen: Int {
        guard callsSeenAtRead else { return 0 }
        return callRecords().filter { $0.incoming && $0.missed && $0.at > callsSeenAtStamp }.count
    }
    func clearMissedCallsBadge() {
        loadCallsSeenAt()
        guard missedCallsUnseen != 0 else { return }
        callsSeenAtStamp = Date().timeIntervalSince1970
        MontanaLocalVault.setString("callsSeenAt", String(callsSeenAtStamp))
        recalcBadge()
    }
    /// THE CONTACTS PAGE'S OWN PIN AND ARCHIVE (the author's word 17.09): the book's order and its
    /// archive, apart from the chats' — a person pinned here stands first here, archived here leaves
    /// this page only.
    @Published var pinnedContacts: Set<String> = Set(MontanaLocalVault.getStringArray("pinnedContacts") ?? []) {
        didSet { MontanaLocalVault.setStringArray("pinnedContacts", Array(pinnedContacts)) }
    }
    @Published var archivedContacts: Set<String> = Set(MontanaLocalVault.getStringArray("archivedContacts") ?? []) {
        didSet { MontanaLocalVault.setStringArray("archivedContacts", Array(archivedContacts)) }
    }
    func togglePinContact(_ ref: String) { if pinnedContacts.contains(ref) { pinnedContacts.remove(ref) } else { pinnedContacts.insert(ref) } }
    func toggleArchiveContact(_ ref: String) { if archivedContacts.contains(ref) { archivedContacts.remove(ref) } else { archivedContacts.insert(ref) } }

    // SINGLE SOURCE OF THE BADGE: dictionary chat -> number of unread MESSAGES. The app —
    // is the authoritative writer (overwrites entirely); NSE only increments the chat counter.
    /// WHAT HAS NOT CHANGED IS NOT WRITTEN (the critic 22.09). Every call sealed a fresh blob into the
    /// keychain twice and asked the system to set the icon's number again -- and the keychain is not a
    /// dictionary, it is a round trip to another process. Measured on the fleet in thirty hours:
    /// 11 042 calls, of which 10 645 (96 %) carried BYTE FOR BYTE what the previous one had already
    /// stored; one device alone made 1 870 of them in a day. The ledger is the same ledger, so the
    /// writes are the same writes: the count is compared first and the road is walked only when the
    /// number the person sees would differ.
    private static var badgeWritten: (counts: [String: Int], missed: Int)?
    /// THE MEMORY IS THE SESSION'S, NOT THE LEDGER'S. While the app sleeps the push extension adds to
    /// the shared mirror by itself, so what this process wrote last is no longer what the icon shows:
    /// the memory is dropped every time the app comes back to the front, and the first recount after
    /// that re-asserts the app's truth in full ([P2P-COMPAT]: the extension only ever adds).
    private static var badgeWatch: NSObjectProtocol?
    static func updateBadge(_ counts: [String: Int], missed: Int) {
        if badgeWatch == nil {
            badgeWatch = NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { _ in ChatStore.badgeWritten = nil }
        }
        if let w = badgeWritten, w.counts == counts, w.missed == missed { return }   // SILENT-OK: the icon already says this
        badgeWritten = (counts, missed)
        let total = counts.values.reduce(0, +) + missed
        MontanaP2PTrace.mark("badge_set", "total=\(total) chats=\(counts.count) missed=\(missed) src=app")
        MontanaKeychain.set("unreadCounts", (try? JSONEncoder().encode(counts)) ?? Data())
        // THE ICON BADGE COUNTS THE MISSED CALLS TOO (the author's word 18.09): the app is the
        // authoritative writer of the shared mirror, the extension only adds to it while the app
        // is dead — the same law as the unread ledger.
        MontanaKeychain.set("missedUnseen", Data(String(missed).utf8))
        DispatchQueue.main.async { UNUserNotificationCenter.current().setBadgeCount(total) }
    }
    // lastSeen: chat name is not stored in the UserDefaults key (graph leak) — a sealed map under device_key.
    // Clamp the untrusted peer sent_at (spec Stage 9 §Ordering): clamp into
    // [max time already received from this peer, local receive time + tolerance].
    // Own messages (multi-device echo) are not clamped. Returns ms.
    // UNIFIED message order across all devices: time (ms precision) → msgId (mid,
    // identical for sender and receiver) as tie-break. Deterministic: at equal time
    // both clients produce the SAME sequence (previously .sorted by createdAt alone, at equal
    // values, gave a different order on P1/P2).
    static func before(_ a: Message, _ b: Message) -> Bool {
        if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
        return a.id < b.id
    }

    // A LETTER'S BIRTH TIME RIDES IN ITS NAME. The receiver's order used to build on the
    // moment of RECEIPT (createdAt = Date() at receive) — an offline batch landed as APNs
    // handed it out, not as it was typed (precedent 00:52: sliced pieces arrived shuffled).
    // The name (mid) travels byte-for-byte and already carries the dedup — let it carry the
    // birth millisecond too: one field, two roles. Time is strictly monotonic on the device —
    // neighbouring letters cannot merge within a ms.
    private static var lastMidMs: Int64 = 0
    private static let midLock = NSLock()
    static func mintMid() -> (mid: String, ms: Int64) {
        midLock.lock()
        var ms = Int64(Date().timeIntervalSince1970 * 1000)
        if ms <= lastMidMs { ms = lastMidMs + 1 }
        lastMidMs = ms
        midLock.unlock()
        return ("t\(ms)-\(UUID().uuidString)", ms)
    }
    /// The birth millisecond from the letter's name, when it carries one (else nil — an old letter).
    static func birthMs(fromMid mid: String) -> Double? {
        let core = mid.hasPrefix("mid:") ? String(mid.dropFirst(4)) : mid
        guard core.hasPrefix("t"), let dash = core.firstIndex(of: "-"),
              let ms = Int64(core[core.index(after: core.startIndex)..<dash]) else { return nil }
        return Double(ms) / 1000.0
    }


    /// The whole map, for a caller that asks about many conversations at once: one opening of the
    /// seal instead of one per name.
    static func lastSeenAll() -> [String: Double] {
        guard let d = MontanaLocalVault.getDecrypted("lastSeenMap"),
              let m = try? JSONDecoder().decode([String: Double].self, from: d) else { return [:] }
        return m
    }
    /// Every letter of theirs read — one road for the opening, the menu's «read», a restore and a history landing late.
    static func allRead(_ arr: [Message]) -> [Message] {
        arr.map { m in
            guard !m.isFromMe, !m.isRead else { return m }
            var r = m; r.isRead = true; return r
        }
    }
    static let unreadByLetterKey = "unreadIsTheLetter"
    /// THE OLD RULE'S VERDICT, ONCE (23.09), for a history written before the letters carried their word: read if
    /// born no later than the chat's last opening (the sealed «last seen» map), or all of a chat the old «read» set
    /// held without a hand mark — so the first count under the letters' word is the last count under the old one.
    static func readByOldRule(_ feed: [String: [Message]], forced: Set<String>) -> [String: [Message]] {
        let seenAll = lastSeenAll()
        let held = Set(MontanaLocalVault.getStringArray("readChats") ?? []).union(coldSet("readChatsCold"))
        var out = feed
        for (chat, arr) in feed {
            let all = held.contains(chat) && !forced.contains(chat)
            let seen = seenAll[chat] ?? 0
            guard arr.contains(where: { !$0.isFromMe && !$0.isRead && (all || $0.createdAt <= seen) }) else { continue }
            out[chat] = arr.map { m in
                guard !m.isFromMe, !m.isRead, all || m.createdAt <= seen else { return m }
                var r = m; r.isRead = true; return r
            }
        }
        return out
    }
    static func setLastSeen(_ chat: String, _ t: Double) {
        var m: [String: Double] = [:]
        if let d = MontanaLocalVault.getDecrypted("lastSeenMap"),
           let mm = try? JSONDecoder().decode([String: Double].self, from: d) { m = mm }
        m[chat] = t
        if let d = try? JSONEncoder().encode(m) { MontanaLocalVault.setEncrypted("lastSeenMap", d) }
    }
    // Drafts (unsent text = content) — a sealed map under device_key, name not in the key.
    // ONE STORE (20.09): the sealed map and nothing else. The legacy per-chat key used to stand behind
    // it as a fallback — a second store that could hand back a text the person had already erased.
    static func draftsAll() -> [String: String] {
        if let d = MontanaLocalVault.getDecrypted("draftsMap"),
           let m = try? JSONDecoder().decode([String: String].self, from: d) { return m }
        return [:]
    }
    /// THE MAP ALREADY STANDS IN MEMORY (the critic 22.09): this opened the sealed block and decoded
    /// the whole map on every ask, and one of the askers is the conversation's own `init` — which the
    /// platform runs on EVERY pass of the page above it, mounted or not. The store holds the same map
    /// published (`drafts`, written by `setDraft` with the full snapshot), so the seal is opened only
    /// when there is no store to ask.
    static func draft(_ chat: String) -> String {
        if let live = ChatStore.live { return live.drafts[chat] ?? "" }
        return draftsAll()[chat] ?? ""
    }
    static func setDraft(_ chat: String, _ text: String) {
        var m = draftsAll()
        let v = text.isEmpty ? nil : text
        if m[chat] == v { return }   // SILENT-OK: the disk already says what the field says
        m[chat] = v
        if let d = try? JSONEncoder().encode(m), !MontanaLocalVault.setEncrypted("draftsMap", d) {
            MontanaP2PTrace.mark("vault_write_refused", "key=draftsMap chat=\(String(chat.prefix(10)))")   // named, not swallowed
        }
        let snapshot = m
        DispatchQueue.main.async {
            guard let s = ChatStore.live else { return }
            s.drafts = snapshot
            // Any chat but the one open on the screen shows its draft in the list at once; the open one tells the
            // list when it is left (openConv) -- not on every letter.
            if s.openConv != chat { s.showDraft(chat) }
        }
    }
    // The peer's unsent words, kept the same way our own are: one sealed map, no second store.
    // They are the most private thing in a chat, so they live under the device key and nowhere else.
    // The sent-draft mark lives beside the draft itself: one store per concept.
    static func setCkptSent(_ chat: String, _ v: String) { MontanaLocalVault.setString("ckpt_" + chat, v) }

    static func peerDraftsAll() -> [String: String] {
        if let d = MontanaLocalVault.getDecrypted("peerDraftsMap"),
           let m = try? JSONDecoder().decode([String: String].self, from: d) { return m }
        return [:]
    }
    static func savePeerDrafts(_ m: [String: String]) {
        if let d = try? JSONEncoder().encode(m.filter { !$0.value.isEmpty }) {
            MontanaLocalVault.setEncrypted("peerDraftsMap", d)
        }
    }

    // Per-chat flags (mute/block) — a sealed map, name not in the UserDefaults key.
    static func chatFlag(_ kind: String, _ chat: String) -> Bool {
        let key = kind + "FlagsMap"
        if let d = MontanaLocalVault.getDecrypted(key),
           let m = try? JSONDecoder().decode([String: Bool].self, from: d) { return m[chat] ?? false }
        return UserDefaults.standard.bool(forKey: "\(kind)_\(chat)")
    }
    static func setChatFlag(_ kind: String, _ chat: String, _ v: Bool) {
        let key = kind + "FlagsMap"
        var m: [String: Bool] = [:]
        if let d = MontanaLocalVault.getDecrypted(key),
           let mm = try? JSONDecoder().decode([String: Bool].self, from: d) { m = mm }
        m[chat] = v
        if let d = try? JSONEncoder().encode(m) { MontanaLocalVault.setEncrypted(key, d) }
    }
    // SC-05: one-time collapse of legacy per-chat keys (chat name in the key name) into sealed maps and delete.
    static func migrateLegacyPerChatKeys() {
        let ud = UserDefaults.standard
        guard !ud.bool(forKey: "legacyPerChatMigrated") else { return }
        for k in Array(ud.dictionaryRepresentation().keys) {
            if k.hasPrefix("lastSeen_") { setLastSeen(String(k.dropFirst(9)), ud.double(forKey: k)); ud.removeObject(forKey: k) }
            else if k.hasPrefix("draft_") { setDraft(String(k.dropFirst(6)), ud.string(forKey: k) ?? ""); ud.removeObject(forKey: k) }
            else if k.hasPrefix("mute_") { setChatFlag("mute", String(k.dropFirst(5)), ud.bool(forKey: k)); ud.removeObject(forKey: k) }
            else if k.hasPrefix("block_") { setChatFlag("block", String(k.dropFirst(6)), ud.bool(forKey: k)); ud.removeObject(forKey: k) }
        }
        ud.set(true, forKey: "legacyPerChatMigrated")
    }
    func recalcBadge() {
        // The record must not be recomputed from an empty history: at cold start the messages
        // are still being decrypted, and a recount here would erase the landing door's honest
        // increments and blink every badge to zero. The count is rewritten once the history it
        // is derived from actually exists.
        guard historyLoaded, inboxDrained else {
            MontanaP2PTrace.mark("badge_hold",
                "history=\(historyLoaded ? 1 : 0) drained=\(inboxDrained ? 1 : 0) — the record stands")
            return
        }
        // The badge does not outlive the conversation: a deleted conversation is out of the
        // count whatever trace it left in the unread set (precedent 22.08: «4» hung over an empty list).
        var counts: [String: Int] = [:]
        // THE RECOUNT NAMES ITS PARTS (the critic 24.09: the landing's «badge» stood 5–18 ms on T1, and in seven cases of
        // eight the icon's writes to the keychain stood inside it — the call letters' reading, suspected first, is under a
        // millisecond for three hundred of them). Each part is a step of its own; a slow landing's line carries them.
        MontanaMainProbe.step("badge:count") {
            // THE LETTER SAYS WHETHER IT WAS READ (the author's word 23.09: «the number of unread for this chat»). The
            // count used to be the letters born after the moment the chat was last OPENED, behind a «read» set that
            // the next landing cleared — so the letters read in the open chat came back unread with the first letter
            // after them (T1 23.09 06:26-06:39 MSK: eleven letters landed in the open chat, one more after a relaunch,
            // and the icon stood at 13 all morning). A letter is read when it stands in the open chat (placeRow,
            // markRead); the count is the letters of theirs that are not — and no sealed map is opened for it.
            for (chat, list) in messages where !deletedChats.contains(chat) {
                // A call letter is never unread (the author's word 17.09): a missed call counts on the
                // calls page alone; in the chat it lies as a read row.
                // A step of a chess game is never unread either (29.09): the board reads it, not the chat.
                let n = list.reduce(0) { $0 + ((!$1.isFromMe && !$1.isRead && callInfoOf($1.text) == nil && !$1.isChessStep) ? 1 : 0) }
                if n > 0 { counts[chat] = n }
            }
            for chat in forcedUnread where !deletedChats.contains(chat) && counts[chat] == nil {
                counts[chat] = 1   // the hand mark on a chat with nothing unread: «at least one», the row's dot
            }
        }
        // THE SAME COUNT IS NOT A CHANGE (the critic 22.09): this is published, and every write of it
        // rebuilt every page that reads the store -- the chats list among them -- while 96 % of the
        // recounts ended on the number already standing.
        if unreadCounts != counts { MontanaMainProbe.step("badge:publish") { unreadCounts = counts } }
        var missed = 0
        MontanaMainProbe.step("badge:calls") { loadCallsSeenAt(); missed = missedCallsUnseen }
        MontanaMainProbe.step("badge:write") { ChatStore.updateBadge(counts, missed: missed) }
    }

    /// THE BLOCKED PEOPLE (Guideline 1.2, the author's word 15.09): one set, mirrored to the
    /// keychain so the push extension refuses their letters too. A block used to be a flag the
    /// screen showed and nothing obeyed; now every road reads this set — the receive path
    /// drops the letter unreceipted, the extension shows no banner, the list names them.
    @Published var blockedChats: Set<String> = ChatStore.coldSet("blockedChats").union(ChatStore.legacyBlocked()) {
        didSet {
            MontanaLocalVault.setStringArray("blockedChats", Array(blockedChats))
            MontanaKeychain.set("blockedChats", (try? JSONEncoder().encode(Array(blockedChats))) ?? Data())   // the NSE refuses them too
        }
    }
    /// The block flags of older builds fold into the set once; the map itself stays untouched.
    static func legacyBlocked() -> Set<String> {
        guard let d = MontanaLocalVault.getDecrypted("blockFlagsMap"),
              let m = try? JSONDecoder().decode([String: Bool].self, from: d) else { return [] }
        return Set(m.filter { $0.value }.keys)
    }
    func isBlocked(_ name: String) -> Bool { blockedChats.contains(name) }
    /// THE ONE QUESTION EVERY INCOMING ROAD ASKS (Guideline 1.2, measured 15.09 13:10): the
    /// person's own block and the network's bar. The feed's door asked it and refused the row —
    /// while the network door had already rung the banner, the call lane had already assembled
    /// the call and the voip wake had already posted the ring. Now the question is asked where
    /// the bytes enter, and once.
    func refuses(_ peer: String) -> Bool { blockedChats.contains(peer) || MontanaSafety.barred.contains(peer) }
    /// The same question before the store exists (a cold voip wake): the keychain mirror the
    /// extension reads, so the app and the extension refuse by one record.
    static func refusesCold(_ peer: String) -> Bool { coldSet("blockedChats").contains(peer) || MontanaSafety.barred.contains(peer) }
    /// The question from anywhere: the live store when there is one, the mirror otherwise.
    static func refusesNow(_ peer: String) -> Bool { live?.refuses(peer) ?? refusesCold(peer) }
    /// EVERY NAME THIS DEVICE REFUSES, IN ONE COPY (28.09). The roads that walk the whole pipe book -- the wake
    /// registration above all -- asked the question once per pipe, and that road now runs off the main thread, where
    /// the store's own set has no business being read. The copy is taken where the store lives; the RULE stays here,
    /// with its one owner ([C-1]), and the copy travels.
    static func refusedNow() -> Set<String> {
        // NO HOP TO THE MAIN THREAD FOR AN ANSWER (the lock guard's rule, 1633's self-lock): asked where the store
        // lives, the live set answers; asked from anywhere else, the sealed mirror does -- the very copy the store
        // writes on every change and the extension already refuses by.
        let names = Thread.isMainThread ? (live?.blockedChats ?? coldSet("blockedChats")) : coldSet("blockedChats")
        return names.union(MontanaSafety.barred)
    }
    /// A CONTROL LETTER IS APPLIED ONCE (measured 15.09 13:38: the box handed the unblock's face
    /// back forty seconds after the block's «no face», and the face returned). A row dedups by
    /// its own presence in the feed; a control letter leaves no row, so it needs its own ledger —
    /// the last four thousand names, sealed, so a relaunch does not reopen the box's repeats.
    private var controlMidsSeen: Set<String> = Set(MontanaLocalVault.getStringArray("controlMids") ?? [])
    private var controlMidsOrder: [String] = MontanaLocalVault.getStringArray("controlMids") ?? []
    func controlSeen(_ sid: String) -> Bool {
        if controlMidsSeen.contains(sid) { return true }
        controlMidsSeen.insert(sid); controlMidsOrder.append(sid)
        if controlMidsOrder.count > 4000 {
            let n = controlMidsOrder.count - 4000
            controlMidsOrder.prefix(n).forEach { controlMidsSeen.remove($0) }
            controlMidsOrder.removeFirst(n)
        }
        MontanaLocalVault.setStringArray("controlMids", controlMidsOrder)
        return false
    }
    /// THE WORD'S OWN MOMENT (15.09): a presence word carries when it was spoken — «T» and the
    /// seconds, uppercase and digits, which every frozen build reads as nothing (they scan the tail
    /// for lowercase «h» and «f», [P2P-COMPAT]). The lane replays a word for sixty seconds and the
    /// node keeps the last one for a day: without its moment, an old «here» read as a live one.
    static func presenceMoment(_ text: String) -> Double? {
        // A DRAFT WORD SAYS ITS MOMENT IN «n», the node's milliseconds (24.09): a draft the lane replays or the node's
        // last word hands over stamps when it was said, not when this phone read it.
        if text.hasPrefix(draftSignalMark) {
            guard let d = Data(base64Encoded: String(text.dropFirst(draftSignalMark.count))),
                  let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let n = j["n"] as? Int, n > 1_600_000_000_000 else { return nil }
            return Double(n) / 1000
        }
        // The typing word says «T» and the seconds as the presence words do (24.09); a build before it says nothing.
        let mark = text.hasPrefix(appMark) ? appMark : (text.hasPrefix(watchMark) ? watchMark : (text.hasPrefix(typingMark) ? typingMark : nil))
        guard let mark else { return nil }
        let payload = text.dropFirst(mark.count)
        guard let t = payload.firstIndex(of: "T") else { return nil }
        let digits = payload[payload.index(after: t)...].prefix { $0.isNumber }
        guard let s = Double(digits), s > 1_600_000_000 else { return nil }
        // The millisecond after the dot (E2E.saidTail, 24.09); a word of an older build says whole seconds.
        let rest = payload[payload.index(after: t)...].dropFirst(digits.count)
        let frac = rest.dropFirst().prefix { $0.isNumber }
        if rest.first == ".", frac.count == 3, let f = Double(frac) { return s + f / 1000 }
        return s
    }
    /// A PEER'S CLOCK, READ FROM ITS WORDS (24.09, the noticed point 2 — the author's word «close it»): a build before 1925
    /// says «T» by the phone's own time, and a phone set behind had its live words read as history — never «online» past
    /// 45 s behind — or living short — «in chat» flickering at 25–45 s. A word's landing minus its moment is the speaker's
    /// clock offset plus the road, and the smallest over the peer's recent words is the clock. It is believed only when
    /// two landings at least ten seconds apart show it within the tolerance two node clocks may disagree by: the lane's
    /// replay lands all at once, and the same old word replayed later shows a larger gap, so neither teaches it. It is
    /// applied only past that tolerance — a build that says the node's time reads as it says, and my own clock set wrong
    /// shifts every peer alike, which this reads away too.
    /// ONLY A WORD NEAR THE CLOCK IT TEACHES IS SHIFTED (24.09, the critic's third pass): a peer that put a fast clock right
    /// left its old gaps as the minimum, and ten minutes of its right words read as history; two devices of one person
    /// with different clocks shifted each other's words. A word that says the node's time is read as said; a word is
    /// shifted only when its own gap stands above the minimum it confirms by no more than the tolerance and a slow road's
    /// lateness (roadLateS: without it, a clock set behind on a road of 0.1–5 s lost 27 of 60 live words to history).
    static let roadLateS: TimeInterval = 10
    private var peerGaps: [String: [(at: Double, gap: Double)]] = [:]
    func peerClockMoment(_ chat: String, said: Double) -> Double {
        let now = MontanaWakePush.nodeNow(), tol = MontanaWakePush.clockSlackS
        var g = (peerGaps[chat] ?? []).filter { now - $0.at < 600 }
        let gap = now - said
        g.append((now, gap))
        if g.count > 16 { g.removeFirst(g.count - 16) }
        peerGaps[chat] = g
        guard abs(gap) > tol, let lo = g.min(by: { $0.gap < $1.gap }), abs(lo.gap) > tol, gap - lo.gap <= tol + Self.roadLateS,
              g.contains(where: { abs($0.at - lo.at) >= 10 && abs($0.gap - lo.gap) <= tol }) else { return said }
        return said + lo.gap
    }
    /// State letters — a face, a name — are applied in the order they were SPOKEN, not received:
    /// the box hands letters over in its own order and more than once.
    private var stateAt: [String: Double] = [:]
    private func stateIsCurrent(_ key: String, at: Double) -> Bool {
        if at < (stateAt[key] ?? 0) { MontanaP2PTrace.mark("state_stale", "key=\(key.prefix(16)) — an older word, not applied"); return false }
        stateAt[key] = at; return true
    }
    func toggleBlocked(_ name: String) {
        if blockedChats.contains(name) { blockedChats.remove(name) } else { blockedChats.insert(name) }
        ChatStore.setChatFlag("block", name, blockedChats.contains(name))   // the flag map follows the set, for older readers of it
        let on = blockedChats.contains(name)
        MontanaP2PTrace.mark("block", "\(on ? "on" : "off") peer=\(String(name.prefix(10))) n=\(blockedChats.count)")
        // The blocked person is told nothing but «gone» — face taken back, seen long ago; the
        // unblocked one meets me anew (the author's word 15.09).
        if on { E2E.shared.announceBlocked(to: name); typingChats.remove(name); watchingChats.remove(name) }
        else { E2E.shared.announceUnblocked(to: name) }
        // The node's set follows registrable() by the one reconciling road: a block removes the
        // person's pairs (no push is born for them), an unblock posts them anew.
        MontanaWakePush.registerConvs()   // the call set follows the same list: its digest moves with it
    }
    @Published var mutedChats: Set<String> = ChatStore.coldSet("mutedChats") {
        didSet {
            MontanaLocalVault.setStringArray("mutedChats", Array(mutedChats))
            MontanaKeychain.set("mutedChats", (try? JSONEncoder().encode(Array(mutedChats))) ?? Data())   // NSE mutes the sound
        }
    }
    @Published var archivedNames: Set<String> = ChatStore.coldSet("archivedCold") {
        didSet {
            mirrorCold("archivedCold", archivedNames)
            if !loading { MontanaLocalVault.setStringArray("archivedNames", Array(archivedNames)) }
        }
    }
    func toggleMuteChat(_ name: String) {
        if mutedChats.contains(name) { mutedChats.remove(name) } else { mutedChats.insert(name) }
    }
    @Published var typingChats: Set<String> = []   // in which chats the peer is currently «typing…»
    /// The unsent words of every chat, the sealed map mirrored in memory: ChatStore.draft reads it (the checkpoint
    /// at leaving a chat speaks it), setDraft writes it on every letter. NOT PUBLISHED (the critic 24.09, T1 21:49 on
    /// 1916): a published map redrew the chats list under the open chat on every letter -- «chat_list apply changed=1
    /// field=draft,model» per keystroke, up to 14.6 ms of the screen's thread -- for a list nobody saw. The list draws
    /// `listDrafts`.
    var drafts: [String: String] = ChatStore.draftsAll()
    /// WHAT THE CHATS LIST SHOWS UNDER A NAME: every chat's draft at once, except the chat open on the screen, whose
    /// words the list learns when it is left (openConv) -- the list lies under it and draws nothing meanwhile, as the
    /// reference keeps a draft for the list when the chat is closed. One writer: showDraft.
    @Published private(set) var listDrafts: [String: String] = [:]
    func showDraft(_ chat: String) {
        let v = drafts[chat]
        if listDrafts[chat] != v { listDrafts[chat] = v }
    }
    private var seedEpoch = 0   // grows whenever the identity changes — invalidates background loads
    @Published var openConv: String? = nil {        // which chat is currently open (don't mark it unread)
        didSet {                                      // mirror for willPresent (push display gate)
            ChatStore.openConvNow = openConv
            if let was = oldValue, was != openConv { showDraft(was) }   // the list learns the words of the chat just left
            // THE ONE presence decision point. Enter, leave, switch A->B — every road that
            // changes which chat is on this screen passes through here, so the farewell and
            // the greeting can never disagree with the truth the unread counter already
            // trusts. They used to live in three view callbacks (onAppear task, a heartbeat
            // loop, onDisappear) — and onDisappear fires LATE on pop, so the farewell
            // sometimes never left (measured 26.08 21:52: exit, zero watch sends after it).
            if oldValue != openConv { E2E.shared.chatPresenceMoved(from: oldValue, to: openConv) }
        }
    }
    static var openConvNow: String?                  // read from willPresent (main thread)
    private var typingMarks: [String: UUID] = [:]
    // Every presence setter publishes ONLY on a real transition: signals repeat up to 8/s
    // while a draft streams, and each naive insert would re-render everything that watches
    // the store — the feed included. An untouched set is an untouched screen.
    /// «typing…» lives this long after a keystroke word (24.09: the number stood bare below).
    static let typingLife: TimeInterval = 5
    /// A keystroke word older than this is not typing now: the life, and the two seconds that two clocks read to the
    /// second may differ by.
    static let typingWordLife: TimeInterval = ChatStore.typingLife + 2
    /// THE LADDER MOVES ONLY BY A WORD SAID NOW, AND NEVER BACK (24.09, the author's word: «typing and last seen are
    /// sometimes wrong»). The lane keeps a word a minute and hands them all over the moment a chat opens (62CC699C
    /// 09:06:09.472Z: seven old words in one millisecond — three «typing», three «in chat»; «in chat» went off and on in
    /// five), and one word rides two roads that do not arrive in the order they left. A word older than its life is
    /// history: it stamps, it lights nothing and puts nothing out (a stale «1» used to put «in chat» out like a «0»). A word
    /// older than the last one that moved the ladder is the echo of a second road — ordered by the millisecond the word
    /// says (E2E.saidTail); a word of 1700-1921 says whole seconds, and inside one second its words keep the order they
    /// landed in, as before. The row holds only the moments the words said
    /// themselves («T» — the speaker's one clock): a build that says none (before 15.09, 1344 among them) is believed as
    /// before, in the order of arrival and outside the row — its moment is a carrier's (an arrival, an envelope's time),
    /// and one row read on two clocks would refuse a live word whenever the speaker's clock ran ahead.
    /// TWO ROWS (24.09, the critic's pass): «in the app» and «in my chat» are two facts. One row refused a chat's «left»
    /// that landed after an app's «here» said later (the echo of my beat), and «in chat» stood a whole life after the
    /// person had left. A chat word moves the chat row — and, arriving, the app row: being in the chat is being in the
    /// app; an app word moves the app row — and, leaving, the chat row: leaving the app is leaving the chat.
    enum LiveRow { case chat, app }
    private var liveAt: [String: Double] = [:]     // «c» or «a» + the chat: the moment of the last word that moved that row
    private var liveLeft: [String: Bool] = [:]     // the chat row's last word was a departure
    func liveWordMoves(_ chat: String, said: Double?, row: LiveRow, arrival: Bool, life: TimeInterval) -> Bool {
        guard let said else {                                                     // believed as before, outside the rows
            if row == .chat || !arrival { liveLeft[chat] = !arrival }
            return true
        }
        // «Now» by the node's clock, the one the speaker's moment is said by (E2E.saidTail); a moment from the future is
        // fresh.
        let now = MontanaWakePush.nodeNow()
        guard now - said <= life else { return false }   // SILENT-OK: history stamps, it lights nothing
        // THE ROW HOLDS THE MOMENT AS SAID (24.09, the second critic's pass): it held the moment pressed down to «now» — two
        // clocks in one row: a peer's clock a breath ahead, a «1» and its «0» inside that breath, and the slow copy of the
        // «1» outranked the pressed «0» — «in chat» for a life after the person had left. A held moment further ahead than
        // two node clocks can disagree (MontanaWakePush.clockSlackS) was said by a wrong clock — a phone set wrong, a build
        // that said its phone's time — and blocks nothing: the word after the correction is not refused until real time
        // passes the moment it left behind.
        let ck = "c" + chat, ak = "a" + chat
        func blocks(_ k: String) -> Bool {
            guard let held = liveAt[k] else { return false }
            return said < held && held - now <= MontanaWakePush.clockSlackS
        }
        switch row {
        case .chat:
            if blocks(ck) { return false }                                        // SILENT-OK: an older word on a second road
            liveAt[ck] = said; liveLeft[chat] = !arrival
            if arrival, !blocks(ak) { liveAt[ak] = said }
        case .app:
            if blocks(ak) { return false }                                        // SILENT-OK: an older word on a second road
            liveAt[ak] = said
            if !arrival, !blocks(ck) { liveAt[ck] = said; liveLeft[chat] = true }
        }
        return true
    }
    /// The last word that moved the ladder was a departure: a keystroke of the other road arriving after it is older than
    /// it, and is not typing (handleMeshDraft, 24.09).
    func peerLeftLive(_ chat: String) -> Bool { liveLeft[chat] == true }
    func peerTyping(_ chat: String) {
        if !typingChats.contains(chat) { typingChats.insert(chat) }
        let mark = UUID(); typingMarks[chat] = mark
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.typingLife) { [weak self] in
            guard let self, self.typingMarks[chat] == mark else { return }
            self.typingChats.remove(chat)
        }
        peerWatching(chat, open: true)   // typing proves the chat is on the peer's screen
    }
    // The presence ladder about the peer, most alive first: «typing…» > «watching» (they see
    // my draft) > «in chat» > «online» (in the app, another screen). Each word arrives as its
    // own beacon and lives ONE LIFE (presenceLife, below): two beats of the 20 s heartbeat and a
    // margin; a departure word ends it at once.
    @Published var watchingChats: Set<String> = []
    private var watchingMarks: [String: UUID] = [:]
    /// THE PEER IS IN MY CHAT — the fact the draft stream stands on. Not the three-second word
    /// above (that one paints the status line and must go dark in breaths): the stream used to
    /// stand on it too, and every lost heartbeat cut the stream — measured 05.09 02:08, the en
    /// phone heard one beat in five from the ru phone, and its words left only in the gaps
    /// when the word happened to be lit. The fact lives thirty seconds from the last beat and
    /// dies at once on the peer's farewell; a peer whose app died costs one presence life of
    /// words to nobody, and nothing else.
    /// ONE LIFE FOR A PRESENCE WORD: the beat is 20 s (P-109), so a word lives two beats and a
    /// margin — the status word and the fact the stream stands on read the same number.
    static let presenceLife: TimeInterval = 45
    private var peerInChatAt: [String: Date] = [:]
    func peerInChat(_ chat: String) -> Bool {
        Date().timeIntervalSince(peerInChatAt[chat] ?? .distantPast) < Self.presenceLife
    }
    /// THE WORD LIVES FROM ITS MOMENT, NOT FROM ITS LANDING (24.09, the second critic's pass): a copy that came late on a
    /// second road, or the node's replay of a peer's last word, lit «in chat» and «online» for a whole life from its
    /// landing — a person who had stopped beating stood «in chat» long past the forgiveness. A word that says its moment
    /// lives what is left of its life; one that says none lives a life from now, as before.
    static func wordAge(_ said: Double?) -> TimeInterval {
        guard let said else { return 0 }
        return min(presenceLife, max(0, MontanaWakePush.nodeNow() - said))
    }
    func peerWatching(_ chat: String, open: Bool, said: Double? = nil) {
        guard open else {
            peerInChatAt[chat] = nil
            if watchingChats.contains(chat) {
                watchingChats.remove(chat)
                MontanaP2PTrace.mark("presence_set", "chat-word=off key=\(String(chat.prefix(10)))")
            }
            watchingMarks[chat] = nil
            return
        }
        let age = Self.wordAge(said)
        peerInChatAt[chat] = Date().addingTimeInterval(-age)
        if !watchingChats.contains(chat) {
            watchingChats.insert(chat)
            MontanaP2PTrace.mark("presence_set", "chat-word=on key=\(String(chat.prefix(10)))")
        }
        let mark = UUID(); watchingMarks[chat] = mark
        // D-1: TTL follows the 20s keepalive — 45s forgives two lost beats; departure still
        // speaks instantly, so the word never outlives the person by more than that forgiveness.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.presenceLife - age) { [weak self] in
            guard let self, self.watchingMarks[chat] == mark else { return }
            self.watchingChats.remove(chat)
            MontanaP2PTrace.mark("presence_set", "chat-word=ttl-off key=\(String(chat.prefix(10)))")
        }
        peerAppOnline(chat, open: true, said: said)   // being in the chat is being in the app
    }
    @Published var appOnlineChats: Set<String> = []
    private var appOnlineMarks: [String: UUID] = [:]
    func peerAppOnline(_ chat: String, open: Bool, said: Double? = nil) {
        guard open else {
            if appOnlineChats.contains(chat) {
                appOnlineChats.remove(chat)
                MontanaP2PTrace.mark("presence_set", "app-word=off key=\(String(chat.prefix(10)))")
            }
            appOnlineMarks[chat] = nil
            peerWatching(chat, open: false)   // leaving the app is leaving the chat too
            return
        }
        if !appOnlineChats.contains(chat) {
            appOnlineChats.insert(chat)
            MontanaP2PTrace.mark("presence_set", "app-word=on key=\(String(chat.prefix(10)))")
        }
        let mark = UUID(); appOnlineMarks[chat] = mark
        // ONE LIFE FOR «ONLINE» TOO (the author's word 24.09: «last seen shows differently on different phones and
        // works unsteadily»). It lived three seconds -- the life of the old 1 s beat -- while the beat is 20 s
        // (P-109): lit for three seconds in every twenty, «seen a minute ago» for the other seventeen, and each phone
        // caught a different phase of it. The stamp is not written here: every word of the person stamps its own
        // moment where it lands (append), so the stamp keeps one clock -- the word's -- and never this phone's.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.presenceLife - Self.wordAge(said)) { [weak self] in
            guard let self, self.appOnlineMarks[chat] == mark else { return }
            self.appOnlineChats.remove(chat)
            MontanaP2PTrace.mark("presence_set", "app-word=ttl-off key=\(String(chat.prefix(10)))")
        }
    }
    // My own typing, per chat: the peer's «watching» word stands only while I actually type —
    // that is what tells the person their words are being read as they appear.
    @Published var myTypingChats: Set<String> = []
    private var myTypingMarks: [String: UUID] = [:]
    func myTyping(_ chat: String, active: Bool) {
        guard active else {
            if myTypingChats.contains(chat) { myTypingChats.remove(chat) }
            myTypingMarks[chat] = nil
            return
        }
        if !myTypingChats.contains(chat) { myTypingChats.insert(chat) }
        let mark = UUID(); myTypingMarks[chat] = mark
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self, self.myTypingMarks[chat] == mark else { return }
            self.myTypingChats.remove(chat)
        }
    }
    // dialogs deleted by the user — we don't restore them from the cloud
    // A conversation that exists but whose other side has not been vouched for yet. The chat is created
    // so the owner can look at who is writing — account, profile, how they arrived — and decide. Until
    // then it makes no sound and raises no banner, so an address someone was given cannot be used to
    // demand attention.
    // Refused references. Their envelopes are dropped on arrival, before anything is stored or shown.
    // THE DELETION MARK HAS ONE STORE (1640, [C-1]): the keychain mirror — written synchronously,
    // readable before the vault opens. The vault copy used to be a second store: its write refuses
    // without the device key (the first seconds of a cold start), and the load REPLACED the mirror
    // with that stale copy — a conversation deleted at both ends came back on the next launch as
    // an empty row (T1 20:28:46Z, deleted 20:28:37Z). The vault array is read once as a migration.
    @Published var deletedChats: Set<String> = ChatStore.coldSet("deletedCold") {
        didSet { mirrorCold("deletedCold", deletedChats) }
    }
    /// Conversations whose pipe the other side closed (24.09, pipeClosedMark): the history stays readable, the composer
    /// gives way to a note. The keychain mirror, like the deletion mark: the first frame reads it before the vault opens.
    @Published var closedChats: Set<String> = ChatStore.coldSet("closedCold") {
        didSet { mirrorCold("closedCold", closedChats) }
    }
    // Transfer visibility lives on MTTransferBoard — the ONE owner ([C-1]). The feed's cells
    // are reconfigured only on a content-fingerprint change, so the ring must update itself:
    // the bubble observes the board from inside its own cell (birth-point sovereignty — no
    // reconfigure patrol). These proxies serve the store's own logic reads.
    var uploadProgress: [String: Double] { MTTransferBoard.shared.progress }
    var uploadStatus: [String: String] { MTTransferBoard.shared.status }
    // ONE BIRTH POINT (the critic 22.09): a seat here is taken inside sendMediaToPeer alone. A second
    // birth (the transcode, for the cancel button) made the refusal of a living upload meet its own
    // encode after the rename — the setter is private, the guard tools/mt-owner-check.py stands behind it.
    private(set) var uploadTasks: [String: Task<Void, Never>] = [:]     // cancelable send tasks keyed by file name
    var historyLoaded = false {   // the queue mirror (M-1/M-2) waits for this: an empty chat map is not «no rows»
        didSet { if historyLoaded, !oldValue { Task { @MainActor in MontanaDeliveryEngine.shared.replayParkedInbound() } } }   // the parked letters land now (17.09)
    }
    /// Whether the extension's box has been looked into in this life of the app. Until it has,
    /// the app does not hold everything the landing door left, and a recount would subtract
    /// precisely those letters — the badge blinking down and back up (the author's word 29.08:
    /// «it redraws anyway»).
    var inboxDrained = false

    // ── THE MIRROR LAW (the author's invariant 24.08): sender's chat -> node -> receiver's
    // chat. The chat is the ONE source of truth for «what rides»; the queue is its shadow.
    // The reconciler asks for verdicts instead of reading rows itself: chat state lives on
    // the main actor, the queue on its own lane.
    enum RowVerdict { case alive, settled, absent }
    @MainActor
    func rowVerdicts(_ mids: [String]) -> [String: RowVerdict] {
        var out: [String: RowVerdict] = [:]
        let want = Set(mids.map { "mid:" + $0 })
        guard !want.isEmpty else { return out }   // SILENT-OK: nothing asked, nothing scanned
        for (_, list) in messages {
            for m in list where m.isFromMe {
                guard let sid = m.msgId, want.contains(sid) else { continue }
                let bare = String(sid.dropFirst(4))
                switch m.deliveryStatus {
                case .delivered, .read: out[bare] = .settled
                default: out[bare] = .alive
                }
            }
        }
        return out   // a mid with no row answers itself by absence
    }

    /// M-2: a clock with neither a queue item nor a living upload task is a lie — nothing
    /// will ever move it. Painted red with the resend button, not left to hang forever.
    @MainActor
    func paintOrphanSending(queueMids: Set<String>) {
        let edge = Date().timeIntervalSince1970 - 120
        for (chat, list) in messages {
            for (i, m) in list.enumerated() where m.isFromMe && m.deliveryStatus == .sending {
                if Self.isLocalRoom(chat) { advance(chat, i, to: .sent); continue }   // no wire: settled, never red
                guard let sid = m.msgId else { continue }
                let bare = sid.hasPrefix("mid:") ? String(sid.dropFirst(4)) : sid
                if queueMids.contains(bare) || MTGroup.shared.rides(bare, queued: queueMids) { continue }   // a group's row rides on its copies (MTGroup)
                if let f = m.videoFile ?? m.imageFile ?? m.audioFile ?? m.docFile,
                   uploadTasks[f] != nil || uploadProgress[f] != nil { continue }
                guard m.createdAt > 0, m.createdAt < edge else { continue }
                if putOut(chat, i, because: .nothingCarries) {
                    MontanaP2PTrace.mark("queue_mirror", "clock with no engine behind it — red + resend mid=\(String(bare.prefix(8)))")
                }
            }
        }
    }
    /// THE RED OF A CLOCK IS LIFTED ONCE (07.10, MTRefusal): an older build painted a letter red after thirty seconds of silence and
    /// kept carrying it -- T1's two letters and its coin to a second account of the same phone. A red row whose letter still rides
    /// in the queue is that paint and never a verdict: every word of red takes its letter out of the queue. At the first mirror after
    /// the history is read such a row goes back to the clock (its coins go out with it again, MTCoinSend.hold), and the node's word
    /// moves it on.
    @MainActor
    func liftClockRed(riding: Set<String>) {
        guard !clockRedLifted else { return }
        clockRedLifted = true
        for (chat, list) in messages {
            for (i, m) in list.enumerated() where m.isFromMe && m.deliveryStatus == .failed {
                guard let sid = m.msgId else { continue }
                let bare = sid.hasPrefix("mid:") ? String(sid.dropFirst(4)) : sid
                guard riding.contains(bare) else { continue }
                restartSend(chat, i)
                MontanaP2PTrace.mark("red_lifted", mid: bare, "a red of silence painted by an older build; the letter rides — back to the clock")
            }
        }
    }
    private var clockRedLifted = false
    func setUploadStatus(_ key: String, _ v: String?) {
        MTTransferBoard.shared.setStatus(key, v)
    }
    // CANCELLATION DOES NOT DESTROY — it stops. Cancellation used to delete the bubble, put
    // the letter's name among the tombstones and erase the files, all SILENTLY. And a tap on
    // a bubble during a transfer IS cancellation (primaryTap). Result: retry + a second touch
    // within the same half second = a message destroyed irreversibly by one touch, with no
    // confirmation and no journal trace (precedent 20.08 19:55 — «pressed retry and the video
    // slipped and got deleted»). Destruction is ONLY explicit deletion from the menu;
    // cancellation gives an honest break: red with a retry, bubble and file alive. The tails
    // (the queue intent, node chunks, temp files) are removed by the stopped task itself
    // through its failure paths — no second owner is needed here ([C-1]).
    @MainActor
    func cancelUpload(_ key: String, chat: String) {
        uploadTasks[key]?.cancel(); uploadTasks[key] = nil
        // The transcode lives in the encode registry, not here (22.09): the hand reaches it by the
        // letter's name, which the registry holds beside the file's.
        if let sid = messages[chat]?.first(where: {
            $0.videoFile == key || $0.imageFile == key || $0.audioFile == key || $0.docFile == key
        })?.msgId, sid.hasPrefix("mid:") {
            MTEncodeRegistry.shared.cancel(letter: String(sid.dropFirst(4)))
        }
        setUploadProgress(key, nil); setUploadStatus(key, nil)
        setMediaRefused(chat, file: key, because: .byHand)
        MontanaP2PTrace.mark("upload_cancel", "file=\(key) — stopped by hand; bubble and file alive, status red")
        objectWillChange.send()
    }
    /// The ONE receipt door ([C-1]). Called exactly when a letter ENDS UP IN THE CHAT:
    /// plain letters on placement, media and voice when their bubble appears — and on every copy
    /// of a letter that already stands: the sender asks again, and the answer repeats.
    ///
    /// The door verifies what the receipt STATES, so no caller — present or future — can state
    /// it falsely. For a media or voice letter the ladder defines ✓✓ as an ASSEMBLED FILE, and
    /// the door only speaks for a file it can see on disk. The duplicate-copy road used to
    /// answer «have it» for a bubble whose cargo was still downloading; the sender heard
    /// «assembled», swept the chunks off the node, and the receiver's fetch died mid-flight
    /// (precedent 26.08: 21 of 36 chunks gone, the video lost on both sides while the sender
    /// showed ✓✓). The refusal is silent to the sender: the assembly road sends the honest
    /// receipt the moment the file is written.
    ///
    /// EVERY ASK IS ANSWERED, ONE ANSWER IN FLIGHT (23.09, the author's word: as in TCP). The door
    /// answered a letter once per process life, on the premise that the receipt rides the one engine;
    /// but a silent letter leaves the queue on the node's word, and a receipt lost after that was
    /// never said again: five letters of iPhone 15 knocked 43 times at T1 for two hours, each copy
    /// written as a repeated receipt and answered by nothing. The receipt now rides under its letter's
    /// own name (receiptMid): the queue holds at most one per letter by construction, and every copy
    /// that comes after it settled asks for, and gets, a new one.
    /// `buried` — the letter met its tombstone: there is no file to assemble and never will be, the
    /// letter's road on this side is over, and the receipt states exactly that (21.09).
    @discardableResult
    func sendDeliveryReceipt(_ chat: String, msgId: String?, isFromMe: Bool, text: String, buried: Bool = false) -> ReceiptAnswer {
        guard !isFromMe, let rsid = msgId, rsid.hasPrefix("mid:"),
              MontanaConv.holds(chat), isDurableInbound(text) else { return .noLetter }
        let dmid = String(rsid.dropFirst(4))
        // THE ROW DECIDES WHETHER THIS IS MEDIA, NOT THE TEXT HANDED TO THE DOOR. The
        // duplicate-copy road passes the letter's RAW body, and a media manifest carries no media
        // mark at all — so the gate below stood blind exactly where it was needed. Measured 01.09:
        // the photo's second copy receipted at 23:26:15 with no file on disk, the sender swept the
        // cargo one second later, and the receiver hunted a manifest that no longer existed for
        // thirteen minutes. A row that owns a file IS a media letter, whatever the envelope says.
        let row = messages[chat]?.first(where: { $0.msgId == rsid })
        let rowFile = row.flatMap { $0.videoFile ?? $0.imageFile ?? $0.audioFile ?? $0.docFile }
        if !buried, text.hasPrefix(mediaMark) || text.hasPrefix(voiceMark) || rowFile != nil {
            let file = rowFile
            guard let file, MontanaMediaStore.exists(file) else {
                MontanaP2PTrace.mark("receipt_refused", mid: dmid,
                                     "media not assembled — the assembly road will receipt")
                return .notAssembled
            }
        }
        // A STATE WORD'S RECEIPT WAITS FOR THE DISK (26.09): the receipt tells the sender my screen holds their name, face,
        // bio or ground, and they never say it again; what the word changed lies in the defaults, which reach the disk
        // later. The promise leaves only after they have (MontanaLocalVault.commit).
        if Self.isStateWord(text) { MontanaLocalVault.commit() }
        MontanaDeliveryEngine.shared.enqueue(to: chat, chat: chat, mid: Self.receiptMid(dmid),
                                             text: deliveryReceiptMark + dmid, silent: true)
        // The receipt's second speaker: this letter now rides every presence word I say to its sender.
        if !buried { MontanaDeliveryEngine.HeldLetters.note(peer: chat, mid: dmid) }
        // The letter is on the person's screen this very moment: «read» follows «delivered»
        // without waiting for the chat to be reopened (15.47.2).
        if openConv == chat, MTForeground.active { sendReadMark(chat) }
        return .answered
    }
    /// A receipt rides under its letter's own name: the queue holds one per letter by construction,
    /// and a settled one leaves room for the next ask.
    static func receiptMid(_ dmid: String) -> String { "rcpt-" + dmid }
    /// A person's state word, as the wire names it: their name, face, bio and link, page ground. Each is kept in the
    /// defaults and each is receipted as held (the sender side's MTOutbox.Kind.isState, read here from the words).
    static func isStateWord(_ text: String) -> Bool {
        text.hasPrefix(nameMark) || text.hasPrefix(avatarMark) || text.hasPrefix(aboutMark) || text.hasPrefix(groundMark)
    }
    /// What the door did with an ask — the copy road writes exactly this in the diary.
    enum ReceiptAnswer: String {
        case answered = "answered"
        case notAssembled = "refused: the file is not assembled yet"
        case noLetter = "none: not a letter that stands in the chat"
    }

    /// Tie a media bubble to its letter's name. Without this link the receiver's receipt
    /// cannot find the message, and «delivered» for media is unreachable by construction.
    @MainActor
    func setMediaMid(_ chat: String, file: String, mid: String) {
        guard let i = messages[chat]?.firstIndex(where: {
            $0.videoFile == file || $0.imageFile == file || $0.audioFile == file || $0.docFile == file
        }) else { return }
        messages[chat]?[i].msgId = "mid:\(mid)"
        // A MEDIA BUBBLE PAYS WHEN IT IS NAMED (MTCoinSend.pay): it was born without its wire name.
        if let row = messages[chat]?[i] { MTCoinSend.pay(row, in: chat, store: self) }
    }

    // ── THE DELIVERY LADDER: ONE DOOR, ONE ORDER ([C-1]) ─────────────────────────────────
    // clock — the letter is ours, no proof;
    // ✓     — SENT: the node accepted the envelope (code 200) — the letter left the device;
    // ✓✓    — DELIVERED: the receiver has the message whole (for media — the ASSEMBLED FILE),
    //         the proof is their receipt;
    // ✓✓ blue — READ: the person opened it, the proof is the read mark.
    //
    // The order is one-way and cannot be broken BY CONSTRUCTION: there is no other road to
    // the deliveryStatus field in the tree, and this door lets only forward. Hence all of
    // today's breakages are impossible at once: «read» on the unsent, «delivered» on a
    // bubble with no file, a checkmark on the mere upload, bulk-painting the history.
    // «Not sent» is a SIDE state: only the clock and one checkmark descend into it (the
    // proven-delivered may not turn red), and any proof arriving later leads forward. The
    // road back is a single door — the human hand (retry).
    // RED HAS ITS OWN DOOR AND IT ASKS FOR A WORD (07.10, MTRefusal): putOut below, never this one —
    // a red asked of the ladder without a word is refused here, whoever asks.
    private static func rank(_ s: DeliveryStatus) -> Int { s.rung }

    @MainActor
    @discardableResult
    func advance(_ chat: String, _ i: Int, to next: DeliveryStatus) -> Bool {
        guard let list = messages[chat], i >= 0, i < list.count else { return false }
        let cur = list[i].deliveryStatus
        if next == .failed {
            return false
        } else if next == .read {
            // BLUE IS REACHABLE ONLY FROM DELIVERED — by construction, not by promise.
            // A single «only forward» condition used to stand here, and the bulk mark «the
            // peer opened the conversation» raised to blue EVERYTHING of one's own in a row —
            // including a letter the peer does not have at all. Precedent 20.08: the video
            // reached the second phone neither in the chat list nor in the conversation,
            // while the first showed «read». The bulk mark's comment ALREADY asserted this
            // rule — in words, while the door let it pass.
            // Reading what was never received is impossible; so is showing it.
            guard cur == .delivered else { return false }
            // A STEP OF A GAME I SENT STOPS AT «DELIVERED» (29.09): the board reads it, not the person, and the moment of
            // its delivery is where the correspondent's clock begins on my screen (MTChessAnchor) -- a read word arriving
            // later must not move that moment.
            if list[i].isFromMe, list[i].isChessStep { return false }
        } else {
            guard Self.rank(next) > Self.rank(cur) else { return false }  // only forward
        }
        return setRung(chat, i, next)
    }
    /// THE ONE DOOR INTO RED (07.10, MTRefusal): a row of mine turns red only by a word -- a keeper's refusal or a thing this
    /// phone cannot do -- never by a span of time. Only the clock and one checkmark descend into it; the word goes to the diary.
    @MainActor
    @discardableResult
    func putOut(_ chat: String, _ i: Int, because why: MTRefusal) -> Bool {
        guard let list = messages[chat], i >= 0, i < list.count else { return false }
        let cur = list[i].deliveryStatus
        guard !Self.isLocalRoom(chat) else { return false }             // no wire — nothing can fail
        guard cur == .sending || cur == .sent else { return false }   // the proven does not turn red
        let sid = list[i].msgId ?? ""
        MontanaP2PTrace.mark("send_red", mid: sid.hasPrefix("mid:") ? String(sid.dropFirst(4)) : sid, "why=\(why.rawValue) was=\(cur.rawValue)")
        return setRung(chat, i, .failed)
    }
    /// The rung written: the two doors above (advance, putOut) and nothing else write the ladder forward or into red.
    @MainActor
    private func setRung(_ chat: String, _ i: Int, _ next: DeliveryStatus) -> Bool {
        messages[chat]?[i].deliveryStatus = next
        messages[chat]?[i].statusAt = Date().timeIntervalSince1970   // the moment of the rung, written here only
        if next == .read { messages[chat]?[i].isRead = true }
        stageMoved.insert(chat)   // the row's record follows in the save's beat (followStages)
        if let row = messages[chat]?[i], row.isFromMe, row.coinLetter != nil { MTCoinSend.hold(row, in: chat) }   // its coins follow its rung (05.10)
        return true
    }
    /// THE ROW WEARS THE LADDER'S STAGE FROM ITS FIRST FRAME (the critic 23.09): the record carries the stage
    /// of my last letter (listRecord «s»), and the ladder's one door — this one, and the hand's road back —
    /// names the chats whose stage moved. The one writer rewrites their records in the beat the letters
    /// themselves are written (scheduleSave, save), so the record and the history on disk never disagree
    /// about a stage, and a storm of receipts costs one record, not one per receipt.
    private var stageMoved = Set<String>()
    private func followStages() {
        guard !stageMoved.isEmpty else { return }
        let moved = stageMoved; stageMoved.removeAll()
        for chat in moved {
            guard let last = lastLetter(chat) else { continue }
            if listState[chat]?["s"] != (last.isFromMe ? ladderLetter(last, in: chat).deliveryStatus.rawValue : nil) { noteListState(chat, last: last) }
        }
    }

    /// THE NODE TOOK THE LETTER — one rung for every letter (17.09, the critic): a media row earned
    /// «sent» only by a receipt while a text row earned it when the node took it, and three tracks
    /// stood at the clock as long as the peer slept though their cargo and letters were on the node.
    ///
    /// ONE OWNER OF «THE LETTER LEFT THIS DEVICE» (the critic 22.09), AND IT NEVER FAILS IN SILENCE.
    /// Two roads used to write this rung — this one and settleByMid(.sent) — and both returned
    /// silently when the row was not found or stood on another rung, so a bubble that kept saying
    /// «Sending…» left no word of why. Measured 22.09 on T3 (cellular, three videos in one plate):
    /// the node took all three cargoes (node_ack 15:09:26, 15:10:10, 15:10:12), the receiver was
    /// already downloading them — and not one «node_sent» line was written all day; the plate stood
    /// at the clock until the receipts came 78 and 85 seconds later. Every road now passes here and
    /// every refusal says what it saw.
    @MainActor
    func markSentByNode(_ chat: String, mid: String, why: String = "node") {
        if MTGroup.shared.copyHeld(mid, store: self) { return }   // the node holds a group's copy: the group's row moves (MTGroup)
        guard let i = messages[chat]?.firstIndex(where: { $0.isFromMe && $0.msgId == "mid:" + mid }) else {
            MontanaP2PTrace.markFolded("node_sent", "refused (\(why)) mid=\(mid.prefix(8)) — no row of mine under this name in \(String(chat.prefix(10)))", window: 60, key: mid)
            return
        }
        let cur = messages[chat]?[i].deliveryStatus ?? .sending
        guard cur == .sending else {
            if cur == .failed { MontanaP2PTrace.mark("node_sent", mid: mid, "refused (\(why)) — the row is red; a hand must resend") }
            return   // SILENT-OK: already sent, delivered or read — the rung is past, nothing to say
        }
        if advance(chat, i, to: .sent) {
            MontanaP2PTrace.mark("node_sent", mid: mid, "the node holds the cargo and the letter (\(why)) — one checkmark")
        }
    }
    /// The one road BACK is the human hand: «retry» pressed, and the letter rides again.
    @MainActor
    func restartSend(_ chat: String, _ i: Int) {
        guard let list = messages[chat], i >= 0, i < list.count,
              list[i].deliveryStatus == .failed else { return }
        messages[chat]?[i].deliveryStatus = .sending
        stageMoved.insert(chat)
        if let row = messages[chat]?[i], row.isFromMe, row.coinLetter != nil { MTCoinSend.hold(row, in: chat) }   // on its way again, its coins taken again (05.10)
    }

    /// How long an upload may stay silent before it is declared unsent. A 512 KiB chunk
    /// leaves in tenths of a second even on a weak network; forty-five seconds of silence is
    /// a break, not a slow channel.
    static let uploadSilenceLimit: TimeInterval = 45

    /// Sends stuck at the «clock» with no living task (the app removed, the connection lost
    /// mid-upload) are honestly moved to «not sent». The queued intent is what brings them back
    /// (18.09, the author's word: one behaviour for any data): the drain hands it here and the
    /// send walks the SAME road again under the same letter name — the very call a finger on the
    /// red mark makes (resendMedia). A living upload is nobody's resume: the task table is asked
    /// first. A file that is gone puts its intent out; a row that is gone leaves it to the mirror law.
    @MainActor
    func resumePieces(_ items: [MontanaDeliveryEngine.Item]) {
        guard historyLoaded else { return }
        for p in items {
            guard var f = MontanaDeliveryEngine.pieceFields(p.text) else { continue }
            // THE ROW IS THE TRUTH OF THE FILE NAME ([C-1]): the row's file outranks the intent's word of it
            // (rows of the older builds still wear a file that became _mtc.mp4 before 22.09).
            if let m = messages[p.chat]?.first(where: { $0.msgId == "mid:" + p.mid }),
               let rf = m.videoFile ?? m.imageFile ?? m.audioFile ?? m.docFile, rf != f.file {
                f = (f.kind, rf, (rf as NSString).pathExtension)
            }
            let url = attachmentURL(f.file)
            guard FileManager.default.fileExists(atPath: url.path) else {
                MontanaP2PTrace.mark("piece_resume", "refused mid=\(p.mid.prefix(8)) kind=\(f.kind) — the file is gone, the intent goes")
                MontanaDeliveryEngine.shared.dropPiece(p.mid)
                continue
            }
            if uploadTasks[f.file] != nil || uploadProgress[f.file] != nil {   // a living send is nobody's resume
                // A skip on the critical path speaks (22.09): a seat nobody freed used to hold a
                // letter for the life of the process with no word in the diary — twelve
                // «drainAll 1 pending» and not one line saying why.
                MontanaP2PTrace.markFolded("piece_resume", "skipped mid=\(p.mid.prefix(8)) — a living send holds \(f.file.prefix(24))", window: 60, key: p.mid)
                continue
            }
            guard let m = messages[p.chat]?.first(where: { $0.videoFile == f.file || $0.imageFile == f.file || $0.audioFile == f.file || $0.docFile == f.file }),
                  m.deliveryStatus == .sending || m.deliveryStatus == .failed else {
                MontanaP2PTrace.markFolded("piece_resume", "no row to resume mid=\(p.mid.prefix(8)) — the mirror law decides", window: 60, key: p.mid)
                continue
            }
            MontanaP2PTrace.mark("piece_resume", "mid=\(p.mid.prefix(8)) kind=\(f.kind) to=\(String(p.to.prefix(10))) by the drain, resume=\(p.tries)")
            setMediaStatus(p.chat, file: f.file, .sending)
            MontanaMediaSender(store: self).sendMediaOverE2E(fileName: f.file, kind: f.kind, docName: m.docName,
                                                            caption: m.text, peer: p.to, chatKey: p.chat)
        }
    }
    @MainActor
    func markStaleSendsFailed(coldStart: Bool) {
        // The sign of a LIVING media send is not time but the presence of an upload task.
        // None — there is nobody left to send: the app was removed, updated, or the
        // connection broke. There is nothing to wait for, and the clock must immediately
        // become a red mark with a retry button.
        // A two-minute threshold used to stand here, and the sweep itself hung only on
        // return-from-background — after an app removal (a build update mid-upload) the
        // message hung for hours, forever, and the person could do nothing with it
        // (precedent 20.08).
        // Text is untouched: it rides the single engine, which turns nothing red by time (MTRefusal)
        // — an upload task never opens for it by construction.
        var fixed = 0
        // The threshold is needed ONLY on return from background: there a send may be running
        // right now. On the process's first pass there is none — no uploads are in flight by
        // construction.
        // The file name is the key of the ring and the seat (22.09: it never changes past birth --
        // the rename at the compression boundary is gone). Precedent 20.08 16:43:30, when it still
        // changed: the sweep put out a running send 13 seconds after it began.
        let edge = Date().timeIntervalSince1970 - 120
        for (chat, list) in messages {
            for (i, m) in list.enumerated() where m.isFromMe && m.deliveryStatus != .sent && m.deliveryStatus != .read && m.deliveryStatus != .delivered {
                // A room without a wire: a clock or a red mark there is a lie of an older build —
                // settled, both at birth (below) and here for what was born before.
                if Self.isLocalRoom(chat) { advance(chat, i, to: .sent); continue }
                guard m.deliveryStatus == .sending,
                      let file = m.videoFile ?? m.imageFile ?? m.audioFile ?? m.docFile else { continue }
                // A send alive RIGHT NOW is nobody's corpse — on a cold start the only such send
                // is a resumed intent (the drain hands the queued intents to resumePieces).
                if uploadTasks[file] != nil || uploadProgress[file] != nil { continue }
                // A QUEUED INTENT IS NOT A CORPSE (18.09): the queue holds it and the drain will run it —
                // the clock is honest on a phone that holds no node.
                if let sid = m.msgId, MontanaDeliveryEngine.shared.queueHolds(mid: sid.hasPrefix("mid:") ? String(sid.dropFirst(4)) : sid) { continue }
                if !coldStart {
                    let born = m.createdAt > 0 ? m.createdAt : 0
                    guard born > 0, born < edge else { continue }
                }
                guard putOut(chat, i, because: .nothingCarries) else { continue }
                fixed += 1
                MontanaLog.event("TX stale -> failed chat=\(chat.prefix(10)) file=\(file) cold=\(coldStart)")
            }
        }
        if fixed > 0 { MontanaP2PTrace.mark("tx_stale", "stuck sends turned red: \(fixed) cold=\(coldStart ? 1 : 0)") }
    }

    /// A letter's identity lives ON THE BUBBLE and is taken from there — by the first send
    /// and by the retry. While the retry was a separate call with a special parameter, it had
    /// its OWN fate: its own letter name, its own chunks on the node, its own queue, and the
    /// receipt of one did not settle the other. There is no separate «retry road» any more —
    /// a retry is the same road walked a second time.
    @MainActor
    func letterMidFor(_ chat: String, file: String) -> String {
        if let i = messages[chat]?.firstIndex(where: {
            $0.videoFile == file || $0.imageFile == file || $0.audioFile == file || $0.docFile == file
        }), let id = messages[chat]?[i].msgId, id.hasPrefix("mid:") {
            return String(id.dropFirst(4))
        }
        // Named like every other letter: the name carries the birth millisecond, so both chats
        // order this letter by WHEN IT WAS WRITTEN, not by when each side happened to receive it.
        // A retry walks the same road under the same name — and therefore keeps the same place.
        let fresh = ChatStore.mintMid().mid
        setMediaMid(chat, file: file, mid: fresh)
        return fresh
    }

    @MainActor
    func setMediaStatus(_ chat: String, file: String, _ st: DeliveryStatus) {
        guard let i = messages[chat]?.firstIndex(where: {
            $0.videoFile == file || $0.imageFile == file || $0.audioFile == file || $0.docFile == file
        }) else { return }
        // THE MESH WALL'S MEDIA RIDE THE RADIO (29.09): every media road of a room without a wire ends here, settled «sent»; the
        // mesh wall's own row is handed to the room's radio first, and a file past the radio's measure stands «not sent».
        if st == .sent, Self.isMeshRoom(chat), let row = messages[chat]?[i], row.isFromMe, !MTMeshRoom.share(row) {
            putOut(chat, i, because: .pastTheRadio); return
        }
        if st == .sending { restartSend(chat, i) } else { advance(chat, i, to: st) }
    }
    /// A media row of mine refused by a word (MTRefusal) -- the media roads' one road into red.
    @MainActor
    func setMediaRefused(_ chat: String, file: String, because why: MTRefusal) {
        guard let i = messages[chat]?.firstIndex(where: {
            $0.videoFile == file || $0.imageFile == file || $0.audioFile == file || $0.docFile == file
        }) else { return }
        putOut(chat, i, because: why)
    }
    func setUploadProgress(_ key: String, _ v: Double?) {
        MTTransferBoard.shared.setProgress(key, v)
    }
    @Published var peerAvatars: [String: String] = [:] {   // peer address -> avatar file (via E2E)
        didSet {
            MTNameBook.published = peerAvatars   // the book's mirror is raised HERE, like the name's
            MTNameBook.mirrorColdPhotos(peerAvatars)   // and the cold one with it, so a launch opens with faces
            if !loading { if let d = try? JSONEncoder().encode(peerAvatars) { MontanaLocalVault.setEncrypted("peerAvatars", d) } }
        }
    }
    // 10-C.1 One stamp, two roles (one field, read two ways): the moment of the peer's last PROOF of
    // presence. Fed from exactly one funnel (peerAppOnline) plus letters by their own time;
    // read by the header when every live word has died — «last seen …».
    @Published var peerSeenAt: [String: Double] = [:] {
        didSet { if !loading { if let d = try? JSONEncoder().encode(peerSeenAt) { MontanaLocalVault.setEncrypted("peerSeenAt", d) } } }
    }
    /// THE ONE WRITER OF THE STAMP. A moment is never later than now: a peer whose clock ran ahead stamped the future,
    /// and «seen a minute ago» stood for as long as their clock was ahead (24.09).
    /// THE STAMP MOVES WITH A LINE (24.09, the noticed point 5): «last seen» could not be read back from the diary — the
    /// morning's answer was pieced together from receipts and sweep counts. When the stamp moves, the diary says from
    /// whom, by what word and at what moment (hh:mm:ss by the node's clock: the diary's scrubber hides a ten-digit
    /// epoch as an address), folded a minute per correspondent — a fold's tail carries its last move. `by` names the
    /// word; the node's last word (sweepPresence) is the one caller that names none.
    /// THE DIARY KNOWS NO MORE THAN THE SCREEN (24.09, the second critic's pass): a letter written at 03:12 and fetched at
    /// 08:00 put «03:12» into the diary for a peer whose exact moment the screen hides. Where the screen shows the coarse
    /// class (seenExact), the line says «hidden».
    func noteSeen(_ chat: String, at ts: Double, by: String = "node") {
        let ts = min(ts, MontanaWakePush.nodeNow())   // «now» by the node's clock, the words' own (24.09)
        guard ts > (peerSeenAt[chat] ?? 0) else { return }   // SILENT-OK: the stamp stands where a later word put it
        peerSeenAt[chat] = ts
        let at = seenExact(chat) ? Self.seenClock.string(from: Date(timeIntervalSince1970: ts)) + "Z" : "hidden"
        MontanaP2PTrace.markFolded("seen_set", "from=\(String(chat.prefix(10))) by=\(by) at=\(at)", window: 60, key: chat)
    }
    private static let seenClock: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; f.timeZone = TimeZone(identifier: "UTC"); f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    /// THE WORDS A PHONE SENDS BY ITSELF are never a proof that its person is there (the author's word 24.09: «last
    /// seen differs from phone to phone»): a receipt of delivery, a name or a face sent again on a reconnect, a card,
    /// a wake handle, a lost cargo, an endpoint, an exit door, a call's signalling (a call proves presence by its own
    /// road -- MontanaCall), and a word this build does not know. They leave a phone in the background with nobody at
    /// it, and every phone hears different ones: they stamped moments the person was never there, a different moment
    /// on every phone.
    static func machineWord(_ text: String) -> Bool {
        text.hasPrefix(deliveryReceiptMark) || text.hasPrefix(avatarMark) || text.hasPrefix(nameMark) || text.hasPrefix(aboutMark)
            || text.hasPrefix(groundMark) || text.hasPrefix(cardMark) || text.hasPrefix(wakeHandleMark) || text.hasPrefix(cargoLostMark)
            || text.hasPrefix(playedMark)
            || text.hasPrefix(punchEndpointMark) || text.hasPrefix(exitDoorMark) || text.hasPrefix(callSignalMark)
            || text.hasPrefix(MTBoard.mark) || text.hasPrefix(sameAskMark) || text.hasPrefix(sameYesMark) || text.hasPrefix(pipeClosedMark) || text.hasPrefix(MTGroup.mark) || text.hasPrefix(keepMark) || mtUnknownServiceWord(text)
    }
    /// «GONE» IS A STATE, NOT A STAMP (the author's word 15.09; measured 13:14–13:17: the lane
    /// forgot the word in sixty seconds, the sweep read it as a moment, and the next word of
    /// theirs raised the stamp above the floor). The person took their face back and stands
    /// «seen long ago» until a LATER presence word or face of theirs says they are here again.
    /// The moment travels with the state so that an older word swept from a node cannot undo it.
    @Published var peerGoneAt: [String: Double] = [:] {
        didSet { if !loading { if let d = try? JSONEncoder().encode(peerGoneAt) { MontanaLocalVault.setEncrypted("peerGoneAt", d) } } }
    }
    func peerGone(_ chat: String, at ts: Double) {
        guard ts >= (peerGoneAt[chat] ?? 0) else { return }
        peerGoneAt[chat] = ts
        peerAppOnline(chat, open: false)
        typingChats.remove(chat); watchingChats.remove(chat)
        applyIncomingAvatar(chat, payload: "", fromMe: false)
        MontanaP2PTrace.mark("presence_gone", "from=\(String(chat.prefix(10)))")
    }
    func peerBack(_ chat: String, at ts: Double) {
        guard let g = peerGoneAt[chat], ts > g else { return }
        peerGoneAt[chat] = nil
        MontanaP2PTrace.mark("presence_back", "from=\(String(chat.prefix(10)))")
    }
    /// The ONE presence line for every screen ([C-1]): the live ladder first, then the
    /// last-seen stamp; nil = nothing is known and nothing is claimed. Tier 2 = typing / watching,
    /// 1 = in chat / on a call / online, 0 = the stamp. Every live state carries a green dot.
    func presenceWord(_ key: String) -> (text: String, tier: Int, dot: Color?)? {
        if typingChats.contains(key) { return (String(localized: "typing…", bundle: MTLanguage.bundle), 2, .green) }
        if watchingChats.contains(key) && myTypingChats.contains(key) { return (String(localized: "watching", bundle: MTLanguage.bundle), 2, .green) }
        if watchingChats.contains(key) { return (String(localized: "in chat", bundle: MTLanguage.bundle), 1, .green) }
        // 15.7: a person on the line with me is present for as long as the call stands.
        if appOnlineChats.contains(key) { return (String(localized: "online", bundle: MTLanguage.bundle), 1, .green) }
        if let seen = peerGoneAt[key] != nil ? MontanaSeen.longAgo : peerSeenAt[key] {
            return ((seenExact(key) ? MontanaSeen.phrase(seen) : MontanaSeen.coarse(seen)), 0, .red)
        }
        return nil
    }
    /// Whether the exact moment of a peer's «last seen» may be known here: the person shares their own and the peer does
    /// not hide theirs. The screen and the diary ask here — the diary never knows more than the screen.
    func seenExact(_ key: String) -> Bool { MontanaPresencePrivacy.sharing && !MontanaPresencePrivacy.peerHidesExact(key) }
    @Published var peerNames: [String: String] = [:] {     // peer address -> self-declared name (via E2E, like the avatar)
        didSet {
            // The name book's mirror is raised HERE, not by everyone who writes a name: a
            // second place diverges from the first by construction — and it did, leaving the
            // resolver empty after a relaunch while the name already lay on disk.
            MTNameBook.declared = peerNames
            MTNameBook.mirrorColdAll(peerNames)   // the cold mirror follows the same one door (stage 9)
            if !loading { if let d = try? JSONEncoder().encode(peerNames) { MontanaLocalVault.setEncrypted("peerNames", d) } }
        }
    }
    /// The name a person declares about themselves. It lands in ONE book, and the list, the calls,
    /// the header and the page of that person all read it from there.
    func purgeNameArtefacts() {
        for (conv, declaredName) in peerNames {
            guard let n = MTNameBook.name(conv) else { continue }
            if n.contains(" ") || n == declaredName.lowercased() {
                MTNameBook.setName(conv: conv, nil)
                MontanaLog.event("NICK purge \(conv.prefix(10)) — was the name, not a nick")
            }
        }
    }

    /// The declared name enters through the book's one door with the moment it was spoken (21.09):
    /// `at` is the word's own moment — a card and a witness that knows no moment say 0.
    func setPeerName(ref: String, name: String, at: Double, source: String) {
        E2E.shared.sendNameIfNeeded(to: ref)   // reciprocity — like the avatar exchange (self-dedups by flag)
        guard MTNameBook.admitDeclared(conv: ref, name: name, at: at, source: source) else { return }
        guard peerNames[ref] != name else { return }
        peerNames[ref] = name   // @Published — chat list, calls and headers refresh themselves
        if archivable(ref), MontanaConv.holds(ref) {
            MontanaArchive.writeNameHead(convRef: ref, legacy: legacyFolderNames(ref), name: name)   // the name rides with the letters (15.10)
        }
        // The list record carries the name THIS DEVICE shows — the book's answer, my record first
        // (the author's word 18.09): the declared name alone stood here and put the peer's word
        // over my rename in the cold first frame.
        let shown = MTNameBook.known(ref) ?? name
        if var rec = listState[ref] { rec["n"] = shown; listState[ref] = rec; persistListState() }
        else if !shown.isEmpty { listState[ref] = ["n": shown]; persistListState() }
        // The nick book is NOT touched here: a name is a name and a nick is a nick. Writing the
        // name into the nick book lowercased it, leaked it into the contact card and showed it
        // as «@name» all over the client — the exact field mix-up this line used to create.
        // THE CONTACT CARD IS NOT TOUCHED EITHER (the author's word 18.09): a name the peer says
        // about themselves lives in ONE slot — peerNames — and writes nowhere else. It used to be
        // copied into the card's own name fields, and a peer renaming themselves rewrote what my
        // hand had written; the card belongs to my hand alone.
    }
    // SSOT name resolver: a manual contact rename wins, then the peer\'s self-declared name, then the short address form.
    func displayName(for ref: String) -> String { MTGroup.isSpeaker(ref) ? MTGroup.shared.speakerName(ref) : MontanaName.of(ref) }   // a group's speaker by the group's book (MTGroup)

    /// How this peer is named ON SCREEN — one question, one answer ([C-1]).
    ///
    /// `Chat.title` is not that answer and never was: it is built ONLY from manual-rename
    /// fields, which for a person are deliberately empty — renaming lives in the name book
    /// by address (see `updateChat`). Hence the chat list showed a neutral caption even when
    /// the name was known and lay in four places at once. `Chat.title` remains a STORAGE
    /// LABEL (the attachment folder, migration on rename) and deliberately does not depend on
    /// of how the peer named themselves: the folder may not migrate on someone else's decision.
    func title(for chat: Chat) -> String {
        guard !chat.isGroup, let conv = chat.convId, !conv.isEmpty else { return chat.title }
        // A PERSON'S NAME LIVES IN THE BOOK ALONE (20.09): the row's own name fields are a group's; a
        // leftover in them from an older road stood over the book in the list and not in the profile
        // — two answers to «who is this». The profile and the list ask the same question of the same
        // book, so they cannot differ.
        let t = MTNameBook.display(conv: conv)
        // The neutral caption is honest only when the name is truly unknown. On a cold start
        // the books are still loading — the LIST RECORD covers that window (stage 9): the row
        // must not flash «Correspondent» over a name that is already on disk.
        if t == String(localized: "Correspondent", bundle: MTLanguage.bundle) {
            if let n = listState[conv]?["n"].map(MTCrown.plain), !n.isEmpty { return n }
            // The stage-9 symptom itself is TRACED: if the neutral caption ever renders on a
            // tester's device, the diag stream shows it — once per conversation per session.
            if Self.nameGapMarked.insert(conv).inserted {
                MontanaP2PTrace.mark("name_gap", "neutral caption shown conv=\(String(conv.prefix(10)))")
            }
        }
        return t
    }
    private static var nameGapMarked = Set<String>()

    /// The letter or emoji in the circle — ONE derivation from the displayed name ([C-1], 20.09):
    /// the callsign's emoji stands first in the name, so the face follows the name at once.
    func initial(for chat: Chat) -> String {
        if ChatStore.isMontanaRoom(chat.name) { return "M" }   // under the logo, until it is decoded
        if ChatStore.isMeshRoom(chat.name) { return "📡" }   // the mesh wall: the antenna, never one's own face
        if ChatStore.isLocalRoom(chat.name) { return E2E.myFaceGlyph() }   // Saved Messages wears one's own face (the author's word 20.09)
        if chat.isGroup { return MontanaAvatar.initial(title: title(for: chat), name: chat.name) }
        return MTNameBook.face(chat.convId ?? chat.name, title: title(for: chat))
    }
    // Deleted «for everyone» (tombstone by msgId): receive/cloud pull do NOT resurrect them.
    var deletedMids: Set<String> = [] {
        didSet { if let d = try? JSONEncoder().encode(Array(deletedMids.suffix(4000))) { MontanaLocalVault.setEncrypted("deletedMids", d) } }
    }
    func deleteEverywhere(chat: String, msgId: String) {
        // The coin audit's first point (05.10.2026 21:4x MSK): a coin letter of mine on its way is not taken off the wire.
        if let row = messages[chat]?.first(where: { m in m.msgId == msgId }), coinTravels(row) {
            MontanaP2PTrace.mark("delete_refused", "everywhere: a coin letter on its way keeps its row and its coins mid=\(String(msgId.prefix(12)))")
            return
        }
        deletedMids.insert(msgId)
        MontanaP2PTrace.mark("row_removed", "deleteEverywhere mid=\(String(msgId.prefix(8)))")
        // The TRANSPORT of the row dies with the row. Deleting a bubble used to remove only
        // the ROW: the living encode task kept the encoder gate, the .piece intent kept the
        // queue, and every later video stood «In queue» behind an orphan (precedent 23.08).
        // Cancelling the upload task reaches the encode (cancellable by construction) and
        // frees the gate; dropPiece clears the intent, the resume and the segment dir.
        if let row = messages[chat]?.first(where: { $0.msgId == msgId }) {
            for f in [row.videoFile, row.imageFile, row.audioFile, row.docFile] {
                guard let f, !f.isEmpty else { continue }
                uploadTasks[f]?.cancel(); uploadTasks[f] = nil
                setUploadProgress(f, nil); setUploadStatus(f, nil)
            }
        }
        let bare = msgId.hasPrefix("mid:") ? String(msgId.dropFirst(4)) : msgId
        MontanaDeliveryEngine.shared.dropPiece(bare)
        // The queue is the chat's shadow (the author's rule 24.08): a deleted row takes its
        // LETTER out of the queue too — a dead manifest used to keep holding the conversation
        // gate invisibly, and the next media stood «In queue» behind a bubble that no longer
        // exists. Ledger released, remnants dropped from the node, gate freed.
        MontanaDeliveryEngine.shared.cargoGone(bare, chat: chat)
        dropRows(chat) { $0.msgId == msgId }
        MTRowJournal.drop(chat, mid: msgId)
    }

    /// The quoted letter's LOCAL row id: mids are shared between devices, row UUIDs are not.
    /// The pre-15.52.9 local UUID of every row that still carries one -> its one name.
    static func legacyNames(_ m: [String: [Message]]) -> [String: MID] {
        var out: [String: MID] = [:]
        for (_, arr) in m { for r in arr { if let l = r.legacyId { out[l] = r.mid } } }
        return out
    }
    func localId(forMid bare: String?, chat: String) -> MID? {
        guard let b = bare, !b.isEmpty else { return nil }
        return messages[chat]?.first(where: { $0.msgId == "mid:\(b)" })?.id
    }
    /// The envelope leg completes a bare mesh landing: the quote settles onto the existing row.
    func enrichQuote(_ chat: String, sid: String, qt: String, qm: String?) {
        guard let i = messages[chat]?.firstIndex(where: { $0.msgId == sid }),
              messages[chat]?[i].replyText == nil else { return }
        messages[chat]?[i].replyText = qt
        messages[chat]?[i].replyToId = localId(forMid: qm, chat: chat)
        MontanaP2PTrace.mark("quote_enriched", mid: String(sid.dropFirst(4)), "late quote settled")
    }

    /// A face of this correspondent stands: the one the screen draws (uniquePublishedPhoto). A name whose file is gone is no face,
    /// and neither is a face whose bytes another correspondent holds too -- its owner is asked for their own (04.10).
    func holdsFace(of ref: String) -> Bool { publishedFace(ref) != nil }
    /// THE FACE ITS OWNER SENT (the author's words 04.10.2026 03:54-03:57 MSK: «no avatars anywhere on T1 -- fix it at last»): the digest
    /// of the bytes a correspondent's own letter or own card on the node carried. Such a face is theirs whoever else wears the same
    /// picture -- two phones of one person, a picture two people chose -- so the screen draws it; a face no owner has sent shows only
    /// while no other correspondent holds its bytes (uniquePublishedPhoto).
    private var faceOwned: [String: String] = (UserDefaults.standard.dictionary(forKey: "peerFaceOwned") as? [String: String]) ?? [:]
    private func noteOwned(_ ref: String, _ data: Data?) {
        faceOwned[ref] = data.map { d in MontanaQueueKeys.sha256(d).map { String(format: "%02x", $0) }.joined() }
        UserDefaults.standard.set(faceOwned, forKey: "peerFaceOwned")
    }
    /// The published face the screen draws: the one its owner sent, or one no other correspondent shares.
    func publishedFace(_ ref: String) -> String? {
        if let f = peerAvatars[ref], let owned = faceOwned[ref], MTNameBook.digestOf(f) == owned { return f }
        return MTNameBook.uniquePublishedPhoto(ref, files: peerAvatars)
    }
    /// A FACE IS FETCHED FROM THE NODE, NOT WAITED FOR (the author's word 04.10.2026 03:57 MSK: «the ask reaches only the one whose chat is
    /// open -- an architectural hole»): a face asked in a presence word comes only when its owner's phone wakes. The owner keeps their face
    /// on the node beside their daily card (MontanaCard.uploadFace) and every correspondent holds that card's link (MTPeerLinks), so a
    /// correspondent this phone draws no face for is read from the node at once -- the owner's own bytes (MontanaCard.wearFace) -- once
    /// a life.
    func healFacesFromCards() {
        var asked = 0
        for c in storedChats() where !c.isGroup && !ChatStore.isLocalRoom(c.name) {
            let ref = c.convRef
            guard publishedFace(ref) == nil, !Self.faceFetched.contains(ref),
                  let link = MTPeerLinks.any(ref), let inv = MontanaCard.invite(inShort: link) else { continue }
            Self.faceFetched.insert(ref)
            asked += 1
            Task.detached(priority: .utility) { await MontanaCard.refaceFromCard(invite: inv, conv: ref) }
        }
        if 0 < asked { MontanaP2PTrace.mark("face_heal", "from_cards=\(asked)") }
    }
    private static var faceFetched = Set<String>()
    /// A FACE TWO CORRESPONDENTS SHARE PROVES NEITHER (04.10, T1: a restore laid one portrait on most of the book): such faces leave
    /// the book at its first read, and each owner is asked for their own (holdsFace) -- the screen drew none of them anyway. Only
    /// while the files can be read: a locked phone's unread file is no proof of a copy.
    func dropSharedFaces() {
        guard UIApplication.shared.isProtectedDataAvailable else { return }
        let shared = Set(peerAvatars.keys.filter { k in publishedFace(k) == nil })
        guard !shared.isEmpty else { return }
        peerAvatars = peerAvatars.filter { !shared.contains($0.key) }
        MTNameBook.forgetPictures()
        for ref in shared { mirrorFaceToShared(ref) }
        MontanaP2PTrace.mark("face_shared", "dropped=\(shared.count) kept=\(peerAvatars.count)")
    }
    /// `owned`: the bytes came from the correspondent themselves -- their letter or their card on the node (faceOwned).
    func setPeerAvatar(ref: String, data: Data, owned: Bool = false) {
        if owned { noteOwned(ref, data) }
        // A repeated delivery is not a new face.  Saving it under a new name used to remove the
        // visible file and publish a second list change, which made an unchanged portrait blink.
        if let old = peerAvatars[ref],
           let present = try? Data(contentsOf: avatarsDirURL().appendingPathComponent(old)),
           present == data { return }
        var saved = saveChatAvatar(data)
        if saved == nil { saved = saveChatAvatar(data) }   // one retry: a transient error must not eat a face
        guard let name = saved else { MontanaLog.event("AVATAR save FAILED for \(ref.prefix(10))"); return }
        // The previous file is removed: the name is new every time, and without the sweep the
        // disk collects one file per update of a correspondent's picture.
        let old = peerAvatars[ref]
        peerAvatars[ref] = name   // published — the list and the header update themselves
        MTNameBook.forgetPictures()   // the book must read the newly published file, not a cached old answer
        // Publish the new file before retiring the old one: every reader can resolve a face throughout
        // the replacement, rather than falling back to an initial in the gap between the two operations.
        if let old, old != name { try? FileManager.default.removeItem(at: avatarsDirURL().appendingPathComponent(old)) }
        // The share sheet reads a MIRROR, and the mirror learned a new face only at the next
        // activation — an old face hung in the sheet all day (the author's word 08.09).
        DispatchQueue.main.async { NotificationCenter.default.post(name: .montanaRemirror, object: nil) }
        // The face rides with the letters, sealed under the seed (15.10.4): a restore by the
        // same words wears it again instead of a drawn initial.
        if archivable(ref), MontanaConv.holds(ref) {
            MontanaArchive.putMedia(convRef: ref, legacy: legacyFolderNames(ref), blobId: MontanaArchive.faceBlob, data: data)
        }
        mirrorFaceToShared(ref)   // the small copy for the banner and the call screen — the one writer
    }
    // SSOT incoming-avatar apply — used by BOTH the E2E path and the mesh append() path,
    // so a peer's avatar renders identically no matter which transport delivered the manifest.
    // New format: manifest + blobs (download from the local store, mesh delivers the blobs);
    // legacy format: avatar bytes inline. Failure -> retry queue (next foreground).
    // Tag a message (by mid) with the transport it went/came over — drives the glyph next to the time.
    func setTransport(chat: String, mid: String, transport: String) {
        let sid = "mid:\(mid)"
        if let i = messages[chat]?.firstIndex(where: { $0.msgId == sid }) { messages[chat]?[i].transport = transport }
    }
    func applyIncomingAvatar(_ chat: String, payload: String, fromMe: Bool) {
        // SILENT-OK: one's own face returned as an echo — there is nobody to apply it to.
        guard !fromMe else { return }
        // THE NAME MODEL, whole ([C-1], the author's word 27.08): the letter carries the face
        // itself, application is synchronous, and the ONE queue's order is the order of truth —
        // no epochs, no clocks, no async downloads racing each other. Yesterday's shapes
        // (manifest JSON, rm-JSON) are BURIED unread: interpreting them is what kept erasing
        // fresh photos with twelve-minute-old burial letters.
        if payload.isEmpty {
            // «No face» is as much an answer as the face itself.
            if let old = peerAvatars[chat] {
                try? FileManager.default.removeItem(at: avatarsDirURL().appendingPathComponent(old))
                MTNameBook.forgetPictures()
            }
            peerAvatars[chat] = nil
            noteOwned(chat, nil)
            E2E.faceNone.insert(chat)   // the answer to an ask: none to show, asked no more in this life
            mirrorFaceToShared(chat)   // a face taken back — or the one my hand set, if any
            MontanaLog.event("AVATAR ← \(chat.prefix(10)) removed by peer")
            return
        }
        guard !payload.hasPrefix("{") else {
            MontanaLog.event("AVATAR ← \(chat.prefix(10)) legacy-format letter buried unread")
            return
        }
        guard let d = Data(base64Encoded: payload), !d.isEmpty else {
            MontanaLog.event("AVATAR ← \(chat.prefix(10)) unreadable payload buried")
            return
        }
        let face = MontanaSelfFace.isNormal(d) ? d : (MontanaSelfFace.normalize(d) ?? d)
        setPeerAvatar(ref: chat, data: face, owned: true)
        E2E.faceNone.remove(chat)
        peerBack(chat, at: Date().timeIntervalSince1970)
        MontanaLog.event("AVATAR ← \(chat.prefix(10)) received \(d.count)B stored \(face.count)B")
        E2E.shared.sendAvatarIfNeeded(to: chat)   // reciprocity — exactly like the name
    }
    // Backfill: mirror every known peer avatar into the shared keychain so the notification
    // extension renders the real photo. Avatars are exchanged once ("already sent"); a peer
    // received before the av_ keychain write existed would otherwise show only the drawn
    // initials circle in push banners.
    func syncPeerAvatarsToShared() {
        var refs = Set(peerAvatars.keys)
        for c in storedChats() where !c.isGroup && !ChatStore.isLocalRoom(c.name) { refs.insert(c.convRef) }
        for ref in refs { mirrorFaceToShared(ref) }
        MontanaLog.event("avatar sync -> shared keychain: \(refs.count)")
    }
    /// THE ONE FACE, MIRRORED FOR THE EXTENSIONS ([C-1], the author's word 20.09: «I set a photo for T3
    /// myself and the notification has none — a breach of ownership»). The banner, the missed-call
    /// card and the call screen read av_ by key from the keychain group, and the key used to hold only
    /// the photo the peer PUBLISHED — a picture set by my hand never reached it. One writer now: the
    /// face the app itself resolves (avatarFile: by hand, then published), written by every door that
    /// changes either — a face received, a face taken back, a picture set or cleared by hand.
    func mirrorFaceToShared(_ ref: String) {
        let key = "av_" + MontanaQueueKeys.sha256(Data(ref.utf8)).map { String(format: "%02x", $0) }.joined()
        let file = avatarFor(ref: ref)
        DispatchQueue.global(qos: .utility).async {
            guard let f = file, let url = mtMediaFileURL(f),
                  let data = try? Data(contentsOf: url), let ui = UIImage(data: data),
                  let jpeg = ui.avatarResized(128).jpegData(compressionQuality: 0.8) else {
                MontanaKeychain.set(key, Data()); return
            }
            MontanaKeychain.set(key, jpeg)
        }
    }
    /// The face of one person, resolved from the active seat alone.  A local choice wins; a
    /// published face must have image bytes unique to its reference.  An unknown owner is never
    /// guessed from a shared folder or a previous seat's mirror.
    func avatarFor(ref: String) -> String? {
        MTNameBook.uniqueManualPhoto(ref) ?? publishedFace(ref)
    }
    /// The chat form adds only the group exception; every person uses the one resolver above.
    func avatarFor(_ chat: Chat) -> String? {
        if chat.isGroup { return MTNameBook.avatarFile(for: chat.convRef, local: chat.photoURL) }
        return avatarFor(ref: chat.convRef)
    }
    /// THE VAULT'S LIGHT HALF — pins, order, the list's sets, names, faces, presence stamps, tombstones —
    /// read on the calling thread and merged on the main one. The launch runs it once off the main thread;
    /// a copy laid under the store runs it again (23.09) — one reader, so the two can never disagree.
    private func readVaultLight(_ after: @escaping () -> Void) {
        let pinnedMsgs = MontanaLocalVault.getDecrypted("pinnedMessages")
        let sched = MontanaLocalVault.getDecrypted("scheduledMsgs")
            .flatMap { try? JSONDecoder().decode([ScheduledMsg].self, from: $0) }
        let order = ChatStore.loadOrderSeq()
        let pinnedList = MontanaLocalVault.getStringArray("pinnedChatsList") ?? []
        let unread = MontanaLocalVault.getStringArray("forcedUnread") ?? []
        let muted = MontanaLocalVault.getStringArray("mutedChats") ?? []
        let archived = MontanaLocalVault.getStringArray("archivedNames") ?? []
        let removed = MontanaLocalVault.getStringArray("deletedChats") ?? []
        let avatars = MontanaLocalVault.getDecrypted("peerAvatars")
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }
        let names = MontanaLocalVault.getDecrypted("peerNames")
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }
        let seen = MontanaLocalVault.getDecrypted("peerSeenAt")
            .flatMap { try? JSONDecoder().decode([String: Double].self, from: $0) }
        let gone = MontanaLocalVault.getDecrypted("peerGoneAt")
            .flatMap { try? JSONDecoder().decode([String: Double].self, from: $0) }
        let dropped = MontanaLocalVault.getDecrypted("deletedMids")
            .flatMap { try? JSONDecoder().decode([String].self, from: $0) }
        MontanaP2PTrace.mark("store_read_end")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // MERGE, NOT CLOBBER (stage 9): letters land and names arrive from the very
            // first seconds — before this read completes. A plain assignment erased the
            // live inserts: the unread dot vanished the moment the load applied (the
            // author saw it «drop off» exactly when the row renamed — same instant).
            if let avatars { self.peerAvatars = avatars.merging(self.peerAvatars) { _, live in live } }
            self.dropSharedFaces()
            self.healFacesFromCards()
            if let names { self.peerNames = names.merging(self.peerNames) { _, live in live } }
            if let seen { self.peerSeenAt = seen.merging(self.peerSeenAt) { a, b in max(a, b) } }
            if let gone { self.peerGoneAt = gone.merging(self.peerGoneAt) { a, b in max(a, b) } }
            if let dropped { self.deletedMids = Set(dropped) }
            if let d = pinnedMsgs {
                if let p = try? JSONDecoder().decode([String: [String]].self, from: d) { self.pinned = p }
                else if let old = try? JSONDecoder().decode([String: String].self, from: d) { self.pinned = old.mapValues { [$0] } }
            }
            if let sched { self.scheduled = sched }
            // The head is what already happened in THIS life of the app (the landing door's
            // stamps applied before the first frame, plus letters landing right now); the
            // persisted order supplies only the tail it does not name. Assigning it whole
            // erased the head and the list reshuffled itself a second after opening.
            // The order the first frame was drawn with came from the mirror and is already
            // the true one; what the vault can add is only what the mirror never knew — the
            // conversations of a life before this shape. It adds, it does not overrule.
            var merged = order
            for (conv, seq) in self.orderSeq where seq > (merged[conv] ?? 0) { merged[conv] = seq }
            self.applyOrder(merged)
            let liveUnread = self.forcedUnread.subtracting(unread).count
            self.forcedUnread = Set(unread).union(self.forcedUnread)
            if liveUnread > 0 { MontanaP2PTrace.mark("state_merge", "live unread preserved n=\(liveUnread)") }
            self.pinnedChats = Set(pinnedList)
            self.mutedChats = Set(muted)
            self.archivedNames = Set(archived)
            // Migration only (1640): a tree that never wrote the mirror takes the vault's list once;
            // from then on the mirror is the one store and the vault is never consulted again.
            if !UserDefaults.standard.bool(forKey: "deletedChatsMirrorIsTruth") {
                self.deletedChats.formUnion(removed)
                UserDefaults.standard.set(true, forKey: "deletedChatsMirrorIsTruth")
            }
            after()
        }
    }
    /// A COPY WAS LAID UNDER THE STORE (23.09): the vault is read again by the launch's own road, and what
    /// the launch reads elsewhere follows — the blocked, the contacts' pins and archive, the conversations
    /// deleted at both ends, the moment the calls were seen. The copy was laid as a union, so this adds and
    /// lifts nothing that stood.
    func takeStored(feed: [String: [Message]]? = nil, outbox: Data? = nil) {
        // THE QUEUE WAITS FOR ITS CHANNELS: to the drain a letter whose pipe this device does not hold is a
        // ghost — buried, and taken off the node's box. The archive's heads bring the pipes back a moment
        // later (restoreFromArchive), and the letters join the queue there, in that same step.
        if let d = outbox, let items = try? JSONDecoder().decode([MTOutbox.Item].self, from: d), !items.isEmpty {
            restoredOutbox = (restoredOutbox ?? []) + items
        }
        readVaultLight { [weak self] in
            guard let self else { return }
            self.blockedChats.formUnion(MontanaLocalVault.getStringArray("blockedChats") ?? [])
            self.pinnedContacts.formUnion(MontanaLocalVault.getStringArray("pinnedContacts") ?? [])
            self.archivedContacts.formUnion(MontanaLocalVault.getStringArray("archivedContacts") ?? [])
            self.deletedChats.formUnion(ChatStore.coldSet("deletedCold"))
            self.controlMidsOrder = MontanaLocalVault.getStringArray("controlMids") ?? []
            self.controlMidsSeen = Set(self.controlMidsOrder)
            self.callsSeenAtRead = false
            self.loadCallsSeenAt()
            // The feed goes in AFTER the tombstones stand (the merge above laid them), and BEFORE the archive's
            // rebuild asks which conversations are occupied: a second later, on the ingest's own debounce.
            if let feed { self.takeRestoredFeed(feed) }
            self.remindAgain()
            self.syncPeerAvatarsToShared()
            // The list's rows came back by the card as a union even where no row of the feed did: the list reads them.
            NotificationCenter.default.post(name: .montanaChatsRestored, object: nil)
            MontanaP2PTrace.mark("store_reread", "copy laid feed=\(feed?.count ?? 0) queue=\(self.restoredOutbox?.count ?? 0)")
        }
    }
    /// Letters of a laid copy still on their way, held until their pipes stand (see takeStored).
    private var restoredOutbox: [MTOutbox.Item]?
    /// THE COPY CAME BEFORE THE STORE (the critic, 28.09): a copy taken back on the first screen -- from the person's node or
    /// from iCloud -- is laid while no store lives, and takeStored had nobody to speak to: the feed and the letters on their
    /// way fell through, and the history came back as the archive's transcript alone (every letter of mine «sent», pins and
    /// quotes detached). The feed goes to the disk the launch reads (the history file, as a snapshot), and the letters wait
    /// under this device's own key for the store's birth, where they join the queue once the pipes stand (afterPipes).
    static let pendingOutboxKey = "mt.restore.outbox"   // NOT-UI: this device's own, read once at the store's birth
    static func layBeforeBirth(feed: [String: [Message]]?, outbox: Data?) {
        if let feed, !feed.isEmpty {
            writeSnapshotNow(feed, sync: true)
            MontanaP2PTrace.mark("feed_restored", "before the store: chats=" + String(feed.count) + " rows=" + String(feed.values.reduce(0) { $0 + $1.count }))
        }
        if let outbox { UserDefaults.standard.set(outbox, forKey: pendingOutboxKey) }
    }

    /// A COPY'S FEED IS LAID BY THE LETTERS' OWN NAMES (the critic, 23.09: «restore on T3 and see no
    /// difference»). The archive's transcript names every letter anew and knows nothing of what became of it —
    /// the rung, the answers, the quote, the pin — so a restore that stood on it alone showed every letter of
    /// mine «sent», every pin and every quote gone, and a conversation that had one fresh letter before the
    /// restore got none of its history at all. The copy carries the feed itself: a conversation takes the rows
    /// it lacks, each in its place by birth; a row this device holds stays as it stands, a row the person
    /// deleted stays deleted, a conversation deleted at both ends takes nothing. The archive fills only what
    /// the feed does not hold.
    func takeRestoredFeed(_ copied: [String: [Message]]) {
        // A COPY SPEAKS OF ITS OWN ERA (the critic 23.09): a copy made before the letters carried their «read»
        // holds every letter of theirs unread, and laid as it is it would stand the whole history on the icon.
        // Such a copy — no letter of theirs read but the archive's — takes the old rule's verdict from its own
        // marks, the last-seen map and the read set laid a moment ago; a copy of this era keeps its letters' word.
        let ownWord = copied.values.contains { $0.contains { !$0.isFromMe && $0.isRead && !$0.mid.hasPrefix("arc:") } }
        let feed = ownWord ? copied : ChatStore.readByOldRule(copied, forced: forcedUnread)
        var merged = messages
        var added = 0, chats = 0
        for (chat, rows) in feed where !deletedChats.contains(chat) {
            var base = merged[chat] ?? []
            var have = Set(base.map { $0.mid })
            let before = base.count
            for r in rows where !deletedMids.contains(r.mid) && have.insert(r.mid).inserted {
                base.insert(r, at: base.firstIndex(where: { ChatStore.before(r, $0) }) ?? base.count)
            }
            guard base.count != before else { continue }
            merged[chat] = base
            added += base.count - before
            chats += 1
        }
        guard added > 0 else { MontanaP2PTrace.mark("feed_restored", "rows=0 chats=\(feed.count)"); return }
        messages = merged
        Self.writeSnapshotNow(merged)
        handMarksYield(to: merged)   // a hand mark laid by the copy yields where its letters stand unread
        for (chat, rows) in merged where feed[chat] != nil {
            if let last = rows.max(by: ChatStore.before) { noteOrder(chat, at: Int(last.createdAt * 1000)) }
        }
        recalcBadge()
        reconcileListWithFeed(merged, keepDoorRecords: false)
        MontanaP2PTrace.mark("feed_restored", "chats=\(chats) rows=\(added) read_word=\(ownWord ? "the letters'" : "the old rule's")")
        auditListAgainstFeed(stage: "restore")
    }
    /// A note to oneself at a chosen moment rings by the system's own alarm, and the system's alarms do not
    /// travel with a copy: every restored reminder still ahead is set again (23.09).
    private func remindAgain() {
        let now = Date().timeIntervalSince1970
        for s in scheduled where s.convRef == nil && s.fireAt > now {
            MontanaNotify.scheduleReminder(id: s.id, text: s.text, at: s.fireAt)
        }
    }
    /// THE CHANNELS STOOD UP FROM THE ARCHIVE'S HEADS. What new channels need is done here, because a restore happens
    /// with the screen open (the return to the person has its own road, AppDelegate.appBecameActive): the copy's letters join the queue (only now — before
    /// its pipe stands, a letter is a ghost to the drain), the wake subscriptions and the extension's mirrors
    /// take the new pipes, the node's box is asked for what waited there meanwhile, and the cards go up again.
    private func afterPipes(grew: Bool) {
        if let items = restoredOutbox {
            restoredOutbox = nil
            MontanaDeliveryEngine.shared.adoptRestored(items)
        }
        guard grew else { return }
        MontanaWakePush.registerConvs()
        MontanaWakePush.fetchBoxKick()
        MontanaCard.reuploadRdv()
        E2E.shared.remirrorChats()
        MontanaDeliveryEngine.shared.drainAll()
        MontanaP2PTrace.mark("pipes_restored", "pipes=\(MTPipeBook.count)")
    }
    /// The one live store — the door out reaches it to seal before it wipes (15.10.4).
    static weak var live: ChatStore?
    /// ONE STORE FOR EVERY WINDOW (24.09, the noticed point 7 — the author's word «close it»): each window's tabs made a
    /// store of their own, and the last one born took the delivery and the E2E core for itself (init): an earlier window
    /// on an iPad stood deaf — no letter, no presence, a greeting owed to a book another store read — while two stores
    /// wrote the one vault. A window takes the live store; the first window of a life makes it, and it leaves with the
    /// last window that holds it. An identity's change is the store's own (wipeLocal, the seed's epoch), as before.
    static func one() -> ChatStore { live ?? ChatStore() }
    init() {
        ChatStore.live = self
        // The letters a copy laid before this store was born wait under this device's key (layBeforeBirth); they join the
        // queue once the pipes stand (afterPipes), as the letters of a copy laid into a living store do.
        if let d = UserDefaults.standard.data(forKey: ChatStore.pendingOutboxKey) {
            UserDefaults.standard.removeObject(forKey: ChatStore.pendingOutboxKey)
            if let items = try? JSONDecoder().decode([MTOutbox.Item].self, from: d), !items.isEmpty { restoredOutbox = items }
        }
        listDrafts = drafts   // the list starts from the sealed map, read once
        MontanaArchive.warm()   // the archive keys derive in the background from the first second (15.18)
        MontanaP2PTrace.markOnce("store_init")   // measure: when the correspondence store began building
        // The store attaches to delivery HERE, not on the first send. While the link arose
        // from sending, a device that only listens had none at all — and the first letter
        // that reached it had nowhere to land.
        MontanaDeliveryEngine.shared.store = self
        // And to the E2E core — RIGHT HERE. The core NEVER had a store reference: the field
        // was declared and assigned nowhere, so persistHistory, recalcBadge,
        // remirrorShareStore, sealArchiveFolderNames, sweepBlobs, call journaling and peer
        // avatar reception silently did nothing. They were silent for ages: each holds a
        // `store?.` inside — a question with no answer. One assignment brings the whole
        // family to life ([C-1]: the store attaches where it attaches to delivery, not one
        // consumer at a time).
        E2E.shared.attach(store: self)
        // The store is ready — collect the letters the extension boxed while we were away.
        // A triple belt (at once, +0.7s, +2s): the keychain box is sometimes invisible to the
        // very first read after waking — the two-second «opened — empty» hole lived exactly
        // here; draining is idempotent, empty repeats are cheap and honestly write n=0.
        DispatchQueue.main.async { MontanaWakePush.drainInbox() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { MontanaWakePush.drainInbox() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { MontanaWakePush.drainInbox() }
        // The node box — on cold start, once the store has just attached: slightly after the
        // triple belt, so the pipe book has time to open (the vault is sometimes busy at launch).
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { MontanaWakePush.fetchBoxKick() }
        NotificationCenter.default.addObserver(forName: .montanaSeedForgotten, object: nil, queue: .main) { [weak self] _ in
            self?.wipeLocal()   // the identity changed -> clear memory (boundary — SeedScope)
        }
        // THE 24 WORDS OPEN THE ARCHIVE (15.10). A restored identity beside an empty feed is the
        // exact moment the sealed log on disk is worth reading: it was written under this seed.
        NotificationCenter.default.addObserver(forName: .montanaSeedOpened, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.messages.isEmpty else { return }
            let epoch = self.seedEpoch, acct = MontanaSeed.twin ?? ""
            DispatchQueue.global(qos: .userInitiated).async { self.restoreFromArchive(epoch: epoch, acct: acct, folders: nil) }
        }
        // A block the twin sent has been filed — it is read back into the feed by the same road.
        NotificationCenter.default.addObserver(forName: .montanaArchiveIngested, object: nil, queue: .main) { [weak self] note in
            guard let self, let folder = note.userInfo?["folder"] as? String else { return }
            self.ingestedFolders.insert(folder)
            self.ingestWork?.cancel()
            let w = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let folders = Array(self.ingestedFolders); self.ingestedFolders.removeAll()
                let epoch = self.seedEpoch, acct = MontanaSeed.twin ?? ""
                DispatchQueue.global(qos: .utility).async { self.restoreFromArchive(epoch: epoch, acct: acct, folders: folders) }
            }
            self.ingestWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: w)
        }
        ChatStore.migrateLegacyPerChatKeys()   // SC-05: collapse legacy lastSeen_/draft_/mute_/block_<name> into maps and delete

        // The store is READ in the background — not merely parsed there.
        //
        // Only parsing used to go background, while the block extraction itself — names,
        // images, erased marks and the whole history — ran here on the main thread. The
        // blocks live in the shared settings store, and extracting one unpacks the whole
        // store; on the phone that took 1.9 seconds between launch end and the tabs' arrival —
        // measured by marks, not assumed. The screen owes the history no waiting: it builds
        // at once, and content comes to it the way any letter does.
        //
        // AIR-CHECKED: loadAcct is the identity-change guard during the read; it is compared
        // with itself and leaves for the air by no road.
        // SILENT-OK: an unparsed block means there is nothing to restore; not a delivery path.
        let loadEpoch = seedEpoch
        let loadAcct = MontanaSeed.twin ?? ""
        loading = true
        // STAGE 9: the list RECORD is read synchronously on the main thread — same store and
        // same moment as chatsJSON (the proven first-frame path), kilobytes. Putting it into
        // the background read below would return it to «after the frame» — the exact disease
        // this state exists to cure (caught by the critic pass on this very edit).
        loadListStateOnce()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            MontanaP2PTrace.mark("store_read_begin")
            // THE VAULT IS WAITED FOR, NOT SKIPPED. On cold start the keychain is sometimes
            // busy and the key yields nil — the read used to walk on and silently apply
            // «empty» without a single retry: names and history «arrived» later by network
            // («Peer» before the green globe — precedents 02:46 and 03:0x), and the first
            // write with the key alive would have overwritten real data with blanks. Waiting
            // on a background thread holds nothing; writes stay locked by the loading flag
            // until the read has truly happened.
            var vaultWait = 0
            while MontanaDeviceKey.key == nil {
                vaultWait += 1
                if vaultWait % 8 == 1 { MontanaP2PTrace.mark("store_read_wait", "the vault is locked — waiting for the keychain (\(vaultWait))") }
                Thread.sleep(forTimeInterval: 0.25)
            }
            self?.readVaultLight { [weak self] in
                guard let self else { return }
                self.loading = false           // read — from this moment writes live again
                E2E.shared.bookRead()          // the greeting owed since the activation leaves now (24.09)
                // The record is NOT recounted here: the history is still being decrypted, and a
                // recount over an empty map would erase what the landing door honestly counted.
                // The recount happens where the history lands (see historyLoaded).
                self.syncPeerAvatarsToShared()   // NSE reads real photos from the shared keychain
            }
            // THE NAME AND FACE DO NOT WAIT FOR HISTORY. Decrypting the whole correspondence
            // takes seconds, and while it ran the screen showed a neutral caption instead of
            // the name and a letter instead of the face — the person saw «Peer» though the
            // name lay read one line above. The light applies at once, the heavy catches up.
            let journal = MTRowJournal.readAll()   // rows born and journaled that no written snapshot holds
            // THE FILE FIRST; the vault blob only as the old road's leftover — read once, rewritten as the
            // file on the next snapshot, removed after the file reads back (17.09, the critic).
            let history = (MTHistoryFile.read() ?? MontanaLocalVault.getDecrypted("chatMessages"))
                .flatMap { try? JSONDecoder().decode([String: [Message]].self, from: $0) }
                ?? (journal.isEmpty ? nil : [:])   // no snapshot yet but journaled rows: they ARE the history
            MontanaP2PTrace.mark("history_read_end")
            if history == nil {
                // A fresh identity has no saved history — «loaded» is still TRUE: an empty
                // chat map IS the truth here, and the mirror law must not stay blind forever.
                DispatchQueue.main.async { [weak self] in self?.historyLoaded = true }
            }
            // THE ARCHIVE IS RECONCILED ON EVERY COLD START (15.10) — AFTER the history stands
            // on screen, never before it: a restore applied ahead of the vault's own rows was
            // merged with them by msgId, which restored rows did not carry, and every letter
            // came back twice (T2, 06.09 08:52). The vault is a cache of the archive; a healthy
            // cache costs one read of the log, because rows go only into chats the feed lacks.
            if history == nil {
                DispatchQueue.main.async { [weak self] in self?.restoreFromArchive(epoch: loadEpoch, acct: loadAcct, folders: nil) }
            }
            if let m = history {
                DispatchQueue.main.async {
                    guard let self else { return }
                    // The identity changed while loading -> do NOT restore the old history.
                    guard self.seedEpoch == loadEpoch,
                          (MontanaSeed.twin ?? "") == loadAcct else { return }
                    MontanaMainProbe.crumb = "history-apply"
                    var merged = m
                    // ONE NAME, ONCE: rows written before 15.52.9 carried a local UUID beside the
                    // name; quotes and pins that pointed at that UUID are pointed at the name here,
                    // and the next write of the history knows no UUID at all.
                    // ONE NAME, ONE ROW. The row's identity IS the name now, and a feed container
                    // refuses two rows of one identity outright (a diffable snapshot with a repeated
                    // item is a crash, not a warning). A history written before the dedup by name
                    // may hold a letter twice under one name — the first stays, the copy goes, here
                    // and nowhere else ([C-1]: the one place a history enters the store).
                    var twins = 0
                    for (chat, arr) in merged {
                        var seen = Set<MID>(); var out: [Message] = []
                        for r in arr { if seen.insert(r.mid).inserted { out.append(r) } else { twins += 1 } }
                        if out.count != arr.count { merged[chat] = out }
                    }
                    if twins > 0 { MontanaP2PTrace.mark("history_names", "twin rows dropped=\(twins)") }
                    // A NOTE TO ONESELF NAMES ITS OWN ANSWER (20.09): in a room with no correspondent every
                    // plate is this person's, so a plate stored before the names is named here, once, at
                    // the one place a history enters the store — and a person holds one answer, so the
                    // last stands and older nameless ones go with it.
                    var named = 0, dropped = 0
                    for (chat, arr) in merged where ChatStore.isLocalRoom(chat) {
                        merged[chat] = arr.map { r in
                            var r = r
                            if r.myReact == nil, let last = r.reactions.last {
                                dropped += r.reactions.count - 1
                                r.reactions = [last]; r.myReact = last; named += 1
                            }
                            return r
                        }
                    }
                    if named > 0 { MontanaP2PTrace.mark("history_names", "own answers named=\(named) older dropped=\(dropped)") }
                    MTNameBook.sweepAccidentalPins()   // pins that only repeated the peer's own word go (20.09)
                    let oldNames = ChatStore.legacyNames(merged)
                    if !oldNames.isEmpty {
                        for (chat, arr) in merged {
                            merged[chat] = arr.map { r in
                                var r = r
                                if r.replyToId == nil, let l = r.legacyReplyTo, let n = oldNames[l] { r.replyToId = n }
                                return r
                            }
                        }
                        var pins = self.pinned
                        for (chat, ids) in pins { pins[chat] = ids.map { oldNames[$0] ?? $0 } }
                        if pins != self.pinned { self.pinned = pins }
                        MontanaP2PTrace.mark("history_names", "old rows renamed=\(oldNames.count)")
                    }
                    let ownName = E2E.myDisplayName()
                    for (chat, arr) in merged {   // apply any leaked incoming name, THEN drop the control bubble (no data loss)
                        if let leaked = arr.last(where: { !$0.isFromMe && $0.text.hasPrefix(nameMark) }) {
                            let nm = String(leaked.text.dropFirst(nameMark.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                            if !nm.isEmpty, nm.count <= 64 { DispatchQueue.main.async { self.setPeerName(ref: chat, name: nm, at: 0, source: "history") } }
                        } else if !ownName.isEmpty, chat != savedMessagesKey, self.peerNames[chat] == ownName {
                            // A PEER NAMED WITH MY OWN NAME BY NO WORD OF THEIRS is a contradiction by
                            // construction: the only door for a declared name is the peer's own letter or
                            // ring, and no such word stands in this history. Build 1480's echo of the
                            // caller's own ring wrote it (12.09). The name leaves — the book, the card and
                            // the list with it — and the next word of the peer names them again.
                            DispatchQueue.main.async {
                                self.setPeerName(ref: chat, name: "", at: Date().timeIntervalSince1970, source: "repair")
                                MontanaP2PTrace.mark("name_repair", "own name stood on \(String(chat.prefix(10))) — cleared")
                                E2E.shared.resendProfileOnReconnect(to: chat)   // my name goes again; the peer's comes back by reciprocity
                            }
                        }
                        // The same road for the wake handle: if WH: settled into history past
                        // the live handler — extract and remember it (otherwise there is
                        // nothing to wake with), then remove it from the feed.
                        if let wh = arr.last(where: { !$0.isFromMe && $0.text.hasPrefix(wakeHandleMark) }) {
                            MontanaWakePush.rememberPeer(chat, handle: String(wh.text.dropFirst(wakeHandleMark.count)))
                        }
                        merged[chat] = arr.filter { !$0.text.hasPrefix(nameMark) && !$0.text.hasPrefix(wakeHandleMark)
                            && !$0.text.hasPrefix(watchMark) && !$0.text.hasPrefix(appMark) }
                    }
                    for (chat, arr) in self.messages {
                        var base = merged[chat] ?? []
                        for msg in arr where !(msg.msgId != nil && base.contains { $0.msgId == msg.msgId }) {
                            base.insert(msg, at: base.firstIndex(where: { ChatStore.before(msg, $0) }) ?? base.count)   // by birth (17.09)
                        }
                        merged[chat] = base
                    }
                    // ONE-TIME HEALING of what builds 1345/1346 left behind (06.09): folders the
                    // reconcile could not name were filed as chats of their own beside the live
                    // ones (T1: nine hash-named chats, 1220 rows, a badge of 575), and a restore
                    // applied twice left every letter twice (T2). A hash-named chat whose folder
                    // belongs to a correspondence the feed already holds is dropped; rows without
                    // an identity are made unique by (second, text, direction).
                    var droppedChats = 0, droppedRows = 0
                    // Every chat keyed by a bare folder label is a leftover of builds 1345-1348 —
                    // a duplicate of a live chat or a transcript the reconcile re-creates under its
                    // arc: key from the folder that still stands. Nothing is lost: the archive holds it.
                    for key in Array(merged.keys) where MontanaArchive.isLabel(key) && !MontanaConv.holds(key) {
                        droppedRows += merged[key]?.count ?? 0; merged[key] = nil; droppedChats += 1
                        self.listState[key] = nil; self.orderSeq[key] = nil
                    }
                    for (chat, arr) in merged {
                        var seen = Set<String>(); var kept: [Message] = []; kept.reserveCapacity(arr.count)
                        for m in arr {
                            if m.msgId == nil {
                                let sig = "\(Int(m.createdAt))|\(m.isFromMe ? 1 : 0)|\(m.text)"
                                if seen.contains(sig) { droppedRows += 1; continue }
                                seen.insert(sig)
                            }
                            kept.append(m)
                        }
                        if kept.count != arr.count { merged[chat] = kept }
                    }
                    if droppedChats > 0 {
                        if var rows = self.chatsShelf() {
                            rows.removeAll { MontanaArchive.isLabel($0.name) && merged[$0.name] == nil }
                            self.saveStored(chats: rows)   // the shelves' one writer: every tab rereads what it wrote
                        }
                        self.persistListState(); self.persistOrder()
                    }
                    if droppedChats > 0 || droppedRows > 0 {
                        MontanaP2PTrace.mark("archive_heal", "chats=\(droppedChats) rows=\(droppedRows)")
                        Self.writeSnapshotNow(merged)
                        NotificationCenter.default.post(name: .montanaChatsRestored, object: nil)
                    }
                    // THE JOURNAL FILLS WHAT THE SNAPSHOT MISSED (16.09): a row born and journaled that
                    // never reached a written snapshot — the process died first (T1 18:25:54Z, killed by a
                    // reinstall seven seconds after a letter landed) — returns here, in its place by birth,
                    // unless the person has deleted it since (the tombstone set is written synchronously).
                    var fromJournal = 0
                    for (chat, rows) in journal where !self.deletedChats.contains(chat) {
                        var base = merged[chat] ?? []
                        for r in rows where !base.contains(where: { $0.mid == r.mid }) && !self.deletedMids.contains(r.mid) {
                            base.insert(r, at: base.firstIndex(where: { ChatStore.before(r, $0) }) ?? base.count)
                            fromJournal += 1
                        }
                        if base.count != (merged[chat] ?? []).count { merged[chat] = base }
                    }
                    if fromJournal > 0 {
                        MontanaP2PTrace.mark("journal_restore", "rows=\(fromJournal) — the snapshot had missed them")
                        MontanaDiagShip.shipOnFailure()
                    }
                    // THE LETTER CARRIES ITS OWN «READ» (the author's word 23.09): a history written before takes the old
                    // rule's verdict into its letters once, and a hand mark on a chat that has unread letters yields to
                    // the number. A chat read before this history landed (a banner's tap on a cold start) is read now.
                    let takesOldVerdict = !UserDefaults.standard.bool(forKey: ChatStore.unreadByLetterKey)
                    if takesOldVerdict {
                        merged = ChatStore.readByOldRule(merged, forced: self.forcedUnread)
                        let yielded = self.handMarksYield(to: merged)
                        MontanaP2PTrace.mark("unread_by_letter", "the old rule's verdict taken in: chats=\(merged.count) hand_marks_yielded=\(yielded)")
                    }
                    for chat in self.readBeforeLoad { if let arr = merged[chat] { merged[chat] = ChatStore.allRead(arr) } }
                    self.readBeforeLoad.removeAll()
                    self.messages = merged
                    // THE VERDICT IS ON DISK BEFORE ITS FLAG (the critic 23.09): a flag written first and a relaunch before
                    // the snapshot would read the old history as all unread. The verdict's own capture is written now, and
                    // the flag follows it on the same queue only when it landed; until then the next load takes it again.
                    if takesOldVerdict {
                        let gen = ChatStore.captureGen()
                        ChatStore.writeSnapshot(merged, gen: gen)
                        ChatStore.unreadVerdictStands(after: gen)
                    }
                    self.historyLoaded = true   // the mirror law may judge the queue only from here
                    MainActor.assumeIsolated { MTCoinSend.settle(self) }   // the book holds every coin letter the chats hold (04.10 23:57)
                    self.restoreFromArchive(epoch: loadEpoch, acct: loadAcct, folders: nil)
                    // The audit and the heads need the archive keys — the folder label is derived
                    // from them — and the keys derive off the main thread (15.18): both wait for
                    // the warm cache instead of deriving on the screen's thread.
                    MontanaArchive.whenReady { [weak self] in
                        guard let self, self.seedEpoch == loadEpoch else { return }
                        self.auditListAgainstFeed(stage: "load")
                        // Every live correspondence carries its head in the archive from here on
                        // (15.10): the address of the correspondent sealed beside its letters, so
                        // a restore — on this device or on the twin — answers, not only reads.
                        for chat in self.messages.keys where self.archivable(chat) && MontanaConv.holds(chat) {
                            let legacy = self.legacyFolderNames(chat)
                            MontanaArchive.writeHead(convRef: chat, legacy: legacy)
                            if let n = self.peerNames[chat] { MontanaArchive.writeNameHead(convRef: chat, legacy: legacy, name: n) }
                        }
                    }
                    // The history exists — NOW the record may be rewritten from it, and from here
                    // on the app is its authoritative writer again (the landing door's increments
                    // are folded into the same number, never added beside it).
                    self.recalcBadge()
                    // The list record heals from the merged truth — invisible to the person:
                    // the first frame already showed the record. Batched: ONE disk write,
                    // not one per conversation (200 encodes on main was the naive cost).
                    // THE LAW (the author's word 19.09): what stands last in the chat stands in the
                    // list — for every chat. With the history in hand every record is rebuilt from
                    // the chat's last letter; only the landing door's records stand, for their letters
                    // may still be in the box — the drain rebuilds those too (reconcileListWithFeed).
                    // The door's records stand only while its overlay lives — the box drained before
                    // this load finished leaves none to wait for.
                    self.reconcileListWithFeed(merged, keepDoorRecords: MontanaKeychain.get("chatListOverlay") != nil)
                    // The stale-send sweep happens EXACTLY HERE, with history already in hand.
                    // It used to hang on the screen's appearance and outran the load: the list
                    // was empty, nothing to fix, and there is no second pass — the message
                    // stayed at an eternal clock with no retry button (precedent 20.08 17:30,
                    // a relaunch mid-upload, 19 chunks of 23).
                    MontanaDeliveryEngine.shared.drainAll()   // the queued intents resume by the drain (18.09), with the history in hand
                    self.markStaleSendsFailed(coldStart: true)
                    MontanaMainProbe.crumb = ""
                }
            }
        }
        // THE MAIN LIE STOOD HERE: on history load EVERY own message was painted «read» —
        // including those stuck at the clock and those marked red. Relaunching the app was
        // enough for an unsent video to earn two blue checkmarks. Delivery state is read from
        // history and rewritten by nothing: the only proof remains the peer's receipt.
    }

    // bump the chat to the top (called on a new message)
    func bump(_ chat: String) { noteOrder(chat, at: Self.nowMs()) }
    /// The moment of a conversation's newest event, from whichever door saw it. Monotone by
    /// construction — a moment already known is never talked down — so applying the same landing
    /// twice, or the ordinary door repeating what the landing door already wrote, moves nothing.
    func noteOrder(_ chat: String, at ms: Int) {
        guard !chat.isEmpty, (orderSeq[chat] ?? 0) < ms else { return }
        orderSeq[chat] = ms
        persistOrder()
    }

    // Call log: creates the chat if missing, adds a call entry.
    func appendCallLog(peer pipe: String, video: Bool, incoming: Bool, dur: Int, missed: Bool) {
        let peer = MTSamePair.root(pipe)   // a call on a folded pipe leaves its row in the conversation (24.09)
        let payload: [String: Any] = ["v": video, "inc": incoming, "dur": dur, "miss": missed]
        guard let d = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: d, encoding: .utf8) else { return }
        // ONE ROW PER CALL (the author's word 17.09): the same call reported by two doors within a
        // minute and a half — the call lane and the missed-call letter — lands once.
        if let last = messages[peer]?.last, let li = callInfoOf(last.text),
           li.video == video, li.incoming == incoming, li.missed == missed,
           Date().timeIntervalSince1970 - last.createdAt < 90 {
            MontanaP2PTrace.mark("call_log", "dup peer=\(String(peer.prefix(10))) — the same call, once"); return
        }
        deletedChats.remove(peer)   // a call resurrects a deleted dialog
        let m = Message(text: callMark + json, isFromMe: !incoming, time: nowHHMM(),
                        deliveryStatus: incoming ? .delivered : .read)
        placeRow(peer, m)
        MTRowJournal.put(peer, m)
        bump(peer)
        Task { @MainActor in self.noteListState(peer, last: self.lastLetter(peer)) }   // the list record follows the newest (stage 9, 17.09)
        MontanaP2PTrace.mark("call_log", "append peer=\(String(peer.prefix(10))) n=\(messages[peer]?.count ?? 0)")
        // A CALL'S SECONDS MINT TO BOTH WHILE IT TALKS (the author's word 07.10.2026 18:5x MSK, MTCallMint): the caller no longer pays
        // the one called at its end (the word of 05.10) -- that payment would take back from the caller the seconds both are credited.
        // A missed call is the calls page's alone (the author's word 17.09): counted from the log
        // rows just placed, not the chat's unread mark — the icon follows at once.
        if incoming && missed { recalcBadge() }
    }

    /// A NEW BUILD'S WORD IN THE MONTANA ROOM (the author's word 29.09): one row per build, theirs and unread until the
    /// room is opened; the row carries the build, the version, what changed and the TestFlight link (releaseMark).
    @discardableResult
    func appendRelease(build: Int, version: String, notes: [String], l10n: [String: [String]], url: String) -> Bool {
        if let rows = messages[montanaRoomKey], rows.contains(where: { releaseInfoOf($0.text)?.build == build }) {
            MontanaP2PTrace.mark("release", "row stands build=\(build) — once"); return false
        }
        var payload: [String: Any] = ["b": build, "v": version, "n": notes, "u": url]
        if !l10n.isEmpty { payload["l"] = l10n }
        guard let d = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: d, encoding: .utf8) else { return false }
        deletedChats.remove(montanaRoomKey)
        let m = Message(text: releaseMark + json, isFromMe: false, time: nowHHMM(), deliveryStatus: .delivered)
        placeRow(montanaRoomKey, m)
        MTRowJournal.put(montanaRoomKey, m)
        bump(montanaRoomKey)
        Task { @MainActor in self.noteListState(montanaRoomKey, last: self.lastLetter(montanaRoomKey)) }
        recalcBadge()
        return true
    }

    /// A POST ON A WALL OF THE PAIR, IN THEIR CHAT (the author's word 30.09): the one birth of its row (MTWallCard). The writer's
    /// phone lays it when the post leaves for the wall's owner, the owner's when the post is taken onto the wall; mine says whose
    /// hand wrote it. ONCE PER POST: the post's own name is the key, so a word carried twice lays nothing the second time. Theirs
    /// is unread until the chat is opened, as a letter is.
    func appendWallPost(peer pipe: String, card: MTWallCard, mine: Bool) {
        let peer = MTSamePair.root(pipe)   // a post on a folded pipe leaves its row in the conversation, as a call does
        if messages[peer]?.contains(where: { MTWallCard.of($0.text)?.id == card.id }) == true {
            MontanaP2PTrace.mark("wall_card", "row stands -- once"); return
        }
        guard let row = card.row else { return }
        deletedChats.remove(peer)
        let m = Message(text: row, isFromMe: mine, time: nowHHMM(), deliveryStatus: mine ? .sent : .delivered)
        placeRow(peer, m)
        MTRowJournal.put(peer, m)
        bump(peer)
        Task { @MainActor in self.noteListState(peer, last: self.lastLetter(peer)) }
        if !mine { recalcBadge() }
        MontanaP2PTrace.mark("wall_card", "laid mine=\(mine ? 1 : 0) peer=\(String(peer.prefix(10)))")
    }
    /// THE MONEY FLOW BEGAN IN THIS CHAT (MTMoneyFlowRow): the one birth of its row, this phone's own and read; the coin switched
    /// on again within a minute lays nothing more.
    func appendMoneyFlow(peer pipe: String) {
        let peer = MTSamePair.root(pipe)
        if let last = messages[peer]?.last, MTMoneyFlowRow.of(last.text), Date().timeIntervalSince1970 - last.createdAt < 60 { return }
        deletedChats.remove(peer)
        let m = Message(text: MTMoneyFlowRow.mark, isFromMe: true, time: nowHHMM(), deliveryStatus: .read)
        placeRow(peer, m)
        MTRowJournal.put(peer, m)
        bump(peer)
        Task { @MainActor in self.noteListState(peer, last: self.lastLetter(peer)) }
        MontanaP2PTrace.mark("money_flow", "begun peer=\(String(peer.prefix(10)))")
    }
    /// A GROUP'S EVENT STANDS IN ITS FEED (MTGroupEvent, stage R -- the reference folder's service rows): this phone's own row,
    /// read, drawn in the middle of the feed; it rings nothing and is never sent.
    func appendGroupEvent(_ key: String, _ text: String) {
        let m = Message(text: text, isFromMe: true, time: nowHHMM(), deliveryStatus: .read)
        placeRow(key, m)
        MTRowJournal.put(key, m)
        bump(key)
        Task { @MainActor in self.noteListState(key, last: self.lastLetter(key)) }
        MontanaP2PTrace.mark("group_event", "laid")
    }
    /// The wall's owner refused the post (their word of the wall, «no»): its row leaves the writer's chat -- the chat does not
    /// say a post stands where its owner said it does not.
    func dropWallPost(peer pipe: String, id: String) {
        let peer = MTSamePair.root(pipe)
        guard let m = messages[peer]?.first(where: { MTWallCard.of($0.text)?.id == id }) else { return }
        deleteLocally(chat: peer, m)
        Task { @MainActor in self.noteListState(peer, last: self.lastLetter(peer)) }
        MontanaP2PTrace.mark("wall_card", "refused -- the row leaves")
    }

    /// A WORD OF THE MESH WALL ARRIVED (29.09): laid in the room under the name its sender spoke under, once per word, while this
    /// phone is on the mesh; theirs and unread until the room is opened, as every letter is.
    func appendMeshRoom(mid: String, from ref: String, text: String, at: Double) {
        guard MontanaP2PNode.meshDiscoverable, !text.isEmpty else { return }
        if messages[meshRoomKey]?.contains(where: { $0.msgId == mid }) == true { return }
        deletedChats.remove(meshRoomKey)
        let m = Message(text: text, isFromMe: false, time: nowHHMM(), deliveryStatus: .delivered, msgId: mid, senderRef: ref, createdAt: at)
        placeRow(meshRoomKey, m)
        MTRowJournal.put(meshRoomKey, m)
        bump(meshRoomKey)
        Task { @MainActor in self.noteListState(meshRoomKey, last: self.lastLetter(meshRoomKey)) }
        recalcBadge()
        MontanaP2PTrace.mark("mesh_room", "laid chars=\(text.count)")
    }

    /// THE CALL LOG, ONE BUILDER (the author's word 11.09): every call row of every conversation,
    /// newest first. The Calls tab and the settings page read this — never a copy of the walk.
    func callRecords() -> [CallRecord] {
        // One builder, built once per change of the history: the Calls tab read this on every
        // redraw, and every read walked every letter of every conversation on the main thread.
        if let memo = callLogMemo { return memo }
        var out: [CallRecord] = []
        for (peer, list) in messages {
            for m in list {
                if let ci = callInfoOf(m.text) {
                    out.append(CallRecord(mid: m.id, peer: peer, video: ci.video, incoming: ci.incoming,
                                          dur: ci.dur, missed: ci.missed, time: m.time, at: m.createdAt))
                }
            }
        }
        let log = out.sorted { $0.at > $1.at }
        callLogMemo = log
        return log
    }
    /// THE MUSIC LIBRARY, ONE BUILDER, BUILT ONCE PER CHANGE OF THE LETTERS OR OF THE LENT FOLDERS (the author's word
    /// 23.09: the music is a page under the bar now, and the page reads its tracks on every pass): the build walks every
    /// letter and asks the disk for every track's size, so it is kept until the letters change, as the call log is, or
    /// until a walk of the lent folders finds something new (MTMusicFolders, its revision). A track by its file, the same.
    func musicLibrary() -> [MusicTrack] { musicBuilt().list }
    func musicTrack(_ file: String) -> MusicTrack? { musicBuilt().byFile[file] }
    private func musicBuilt() -> (list: [MusicTrack], byFile: [String: MusicTrack]) {
        let lent = MTMusicFolders.tracks()
        if let memo = musicMemo, memo.lent == lent.rev { return (memo.list, memo.byFile) }
        let list = MontanaMusicLibrary.build(messages: messages, lent: lent.list, nameOf: { self.displayName(for: $0) })
        let byFile = Dictionary(list.map { ($0.file, $0) }, uniquingKeysWith: { a, _ in a })
        musicMemo = (lent.rev, list, byFile)
        return (list, byFile)
    }
    /// THE GALLERY'S MOMENTS, ONE BUILDER, BUILT ONCE PER CHANGE OF THE LETTERS OR OF MY STORIES (the author's word 25.09:
    /// the gallery is a page under the bar now, and it lagged at its opening). The chats page used to walk every letter of
    /// every conversation twice -- the videos, then the photos -- and ask the disk for every file, on every pass of its body
    /// while the gallery stood. The walk is kept now, as the call log and the music are, and moves with the letters' revision
    /// and with my stories' names; a file that lands later moves it too. Oldest first: the newest stands at the bottom, as the
    /// platform's photos stand; the feed reads the same list the other way. One file, one moment: a photo forwarded or saved
    /// lies in two letters under one name -- the newest letter stands.
    /// A letter's photo as a moment, when its file is on this phone: the one shape of a picture, for the gallery and for the one
    /// road a tapped picture takes (PhotoPresenter.present(_:among:)).
    func picture(_ m: Message, in chat: String) -> MTMoment? {
        guard let f = m.imageFile, fileOnDisk(f) else { return nil }
        return MTMoment(id: f, url: attachmentURL(f), caption: m.isFromMe ? E2E.myDisplayName() : displayName(for: chat),
                        own: false, at: m.createdAt, chat: chat, mid: m.id, photo: true)
    }
    /// The photos of one conversation on this phone, oldest first, one file once: what a tapped picture of it pages through.
    func pictures(in chat: String) -> [MTMoment] {
        var seen = Set<String>()
        return (messages[chat] ?? []).compactMap { m in picture(m, in: chat).flatMap { p in seen.insert(p.id).inserted ? p : nil } }
    }
    func mediaLibrary(stories: [StoryMedia]) -> [MTMoment] {
        let key = stories.map { $0.file }.joined(separator: "\n")
        if let memo = mediaMemo, memo.stories == key { return memo.list }
        let t0 = Date()
        var all: [MTMoment] = []
        for m in stories where m.type == "video" && FileManager.default.fileExists(atPath: storyFileURL(m.file).path) {
            all.append(MTMoment(id: m.file, url: storyFileURL(m.file),
                                             caption: String(localized: "Your Story", bundle: MTLanguage.bundle), own: true,
                                             at: m.created, chat: "", mid: nil))
        }
        for (chat, list) in messages {
            for m in list {
                if let f = m.videoFile, fileOnDisk(f) {
                    all.append(MTMoment(id: f, url: attachmentURL(f), caption: m.isFromMe ? E2E.myDisplayName() : displayName(for: chat),
                                                     own: false, at: m.createdAt, chat: chat, mid: m.id))
                } else if let p = picture(m, in: chat) {
                    all.append(p)
                }
            }
        }
        var seen = Set<String>()
        let list = Array(all.sorted { $0.at > $1.at }.filter { seen.insert($0.id).inserted }.reversed())
        mediaMemo = (key, list)
        MontanaP2PTrace.mark("gallery_lib", "moments=\(list.count) ms=\(Int(Date().timeIntervalSince(t0) * 1000))")
        return list
    }
    // Delete a single call-log entry: its letter in its own conversation (a letter's name is one within a conversation, 09.10).
    func deleteCallLog(_ r: CallRecord) {
        dropRows(r.peer) { $0.id == r.mid && callInfoOf($0.text) != nil }
        save()
    }
    // Clear ALL call-log entries in all dialogs.
    func clearAllCallLogs() {
        for peer in messages.keys { dropRows(peer) { callInfoOf($0.text) != nil } }
        save()
    }

    /// Chats read before the history landed — their letters are read the moment it does (the history apply).
    private var readBeforeLoad = Set<String>()
    // mark the chat as read (opened it) — hide the unread counter
    /// tellPeer: the read mark leaves only when the PERSON has the letters before their eyes —
    /// the chat opened on screen. The list's «mark as read» is bookkeeping of one's own badge and
    /// says nothing to the peer (15.47.2: it used to declare «read» for letters nobody read).
    func markRead(_ chat: String, tellPeer: Bool = true) {
        // EVERY LETTER OF THEIRS HERE IS READ NOW (the author's word 23.09): the count is the letters that are not, so
        // a chat read stays read whatever lands elsewhere. Before the history has landed its letters are not all
        // here — the chat is remembered and read when they land.
        if let arr = messages[chat], arr.contains(where: { !$0.isFromMe && !$0.isRead }) { messages[chat] = ChatStore.allRead(arr) }
        if !historyLoaded { readBeforeLoad.insert(chat) }
        if forcedUnread.contains(chat) { forcedUnread.remove(chat) }   // the hand mark goes with it (didSet recounts)
        // The record is what the eye reads, so it is cleared HERE, not on the next recount: a
        // badge that outlives the opening of its chat is the same lie, only shorter.
        if unreadCounts[chat] != nil {
            unreadCounts[chat] = nil
            ChatStore.updateBadge(unreadCounts, missed: missedCallsUnseen)
        }
        // remove delivered banners of this chat from Notification Center
        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { list in
            let ids = list.filter { ($0.request.content.userInfo["chat"] as? String) == chat }.map { $0.request.identifier }
            if !ids.isEmpty { center.removeDeliveredNotifications(withIdentifiers: ids) }
        }
        // tell the peer it's read (via a hidden receipt over E2E)
        // The receipt leaves only when there was something TO read. Opening a conversation
        // with zero incoming letters declared «I read your letters» at zero letters — a
        // falsehood about the person, and a signal besides: someone who did nothing learned
        // the moment another's phone opened the screen. That same letter came first in a
        // fresh introduction.
        if tellPeer { sendReadMark(chat) }
    }

    /// THE ONE EMITTER of the read mark ([C-1], 15.47.2): the chat is on screen and the app is
    /// active, there is something of theirs to read, and the person allows read receipts. Called
    /// on opening, on every letter that lands while the chat is open, and on the app coming back
    /// to the foreground with the chat open. Coalesced: one word per moment, not per letter.
    private var readMarkWork: DispatchWorkItem?
    func sendReadMark(_ chat: String) {
        // Every silent exit leaves a line: «read never came» used to be indistinguishable from
        // «read was never asked for» (08.09, both phones inside the chat, no word).
        guard messages[chat]?.contains(where: { !$0.isFromMe }) == true else { MontanaP2PTrace.mark("read_skip", "why=nothing-of-theirs"); return }
        guard MontanaConv.holds(chat) else { MontanaP2PTrace.mark("read_skip", "why=no-conversation"); return }
        guard !blockedChats.contains(chat) else { MontanaP2PTrace.mark("read_skip", "why=blocked"); return }   // a blocked person hears no word of mine
        guard (UserDefaults.standard.object(forKey: "readReceiptsEnabled") as? Bool ?? true) else { MontanaP2PTrace.mark("read_skip", "why=receipts-off"); return }
        readMarkWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.openConv == chat else { MontanaP2PTrace.mark("read_skip", "why=chat-closed"); return }
            guard MTForeground.active else { MontanaP2PTrace.mark("read_skip", "why=not-foreground"); return }
            // THE WORD NAMES WHAT IT COVERS: the birth millisecond of the newest letter of theirs
            // on this screen — minted by THEIR clock in the letter's own name, so the sender
            // compares it with its own minting and no clock of ours enters. A bare word meant
            // «everything delivered is read», and a word that outran its receipt by a second was
            // lost: read opens only from delivered, and the word was not sent again. Now the
            // sender keeps the mark and raises the letter when its receipt catches up.
            let upTo = (self.messages[chat] ?? []).compactMap { $0.isFromMe ? nil : $0.msgId.flatMap(ChatStore.birthMs(fromMid:)) }.max()
            let word = upTo.map { readReceiptMark + String(Int64($0 * 1000)) } ?? readReceiptMark   // COMPAT-LOCAL: the same prefix, old builds read it as the bare word
            MontanaDeliveryEngine.shared.enqueue(to: chat, chat: chat, mid: UUID().uuidString, text: word, silent: true)
            MontanaP2PTrace.mark("read_tx", "to=\(String(chat.prefix(10))) upto=\(upTo.map { MontanaP2PTrace.shortMs(Int64($0 * 1000)) } ?? "-")")
        }
        readMarkWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: w)
    }

    /// The peer's read watermark per conversation: the newest of my letters (by its birth
    /// millisecond) the peer has declared read. Kept so a receipt arriving AFTER the read word
    /// still raises its letter to read — the word is not repeated, the mark remembers it.
    static func peerReadUpTo(_ chat: String) -> Int64? {
        if let d = MontanaLocalVault.getDecrypted("peerReadMap"),
           let m = try? JSONDecoder().decode([String: Int64].self, from: d) { return m[chat] }
        return nil
    }
    static func notePeerRead(_ chat: String, upToMs: Int64) {
        var m: [String: Int64] = [:]
        if let d = MontanaLocalVault.getDecrypted("peerReadMap"),
           let mm = try? JSONDecoder().decode([String: Int64].self, from: d) { m = mm }
        if let have = m[chat], have >= upToMs { return }
        m[chat] = upToMs
        if let d = try? JSONEncoder().encode(m) { MontanaLocalVault.setEncrypted("peerReadMap", d) }
    }
    /// Display diagnostics (the 6.10 question, reproduced 23:37): on opening a conversation
    /// the journal names the feed's rows — the count and the tail (mid + kind). «The bubble
    /// landed, the author saw nothing» stops being an argument: either the row is absent
    /// (removal leaves traces) or it is there — and the defect is in drawing.
    func traceRows(_ key: String) {
        let a = messages[key] ?? []
        let tail = a.suffix(6).map { m -> String in
            let id = String((m.msgId ?? "-").prefix(8))
            let kind = m.text.hasPrefix(mediaMark) ? "media" : "text"
            return id + ":" + kind
        }.joined(separator: ",")
        MontanaP2PTrace.mark("chat_rows", "key=\(String(key.prefix(10))) n=\(a.count) tail=[\(tail)]")
    }

    /// THE HISTORY-WRITE CORE: a seal failure (an instant of busy keychain — no key) is NOT
    /// swallowed — five retries with a pause, the failure spoken aloud. Precedent 23:37→23:57:
    /// the video row
    /// landed in memory (n=4), the write failed silently, a relaunch ate the row — while the
    /// receipt had already left and the sender believed «delivered». The same class as the
    /// storage key (934).
    @discardableResult
    static func writeHistory(_ snapshot: [String: [Message]]) -> Bool {
        guard let d = try? JSONEncoder().encode(snapshot) else { return false }
        for attempt in 0..<5 {
            if MTHistoryFile.write(d) {
                MontanaP2PTrace.markFolded("history_write", "bytes=\(d.count)", window: 60)
                return true
            }
            MontanaP2PTrace.mark("history_write_refused", "try=\(attempt + 1)")
            Thread.sleep(forTimeInterval: 0.2)
        }
        return false
    }
    /// THE WRITTEN HISTORY IS READ BACK before the journal trusts it (17.09, the critic): the file is
    /// opened and decoded, and every chat's set of names must equal the snapshot's. A history that reads
    /// back differently is a lie spoken aloud — and the journal stays.
    static func historyReadsBack(_ snapshot: [String: [Message]]) -> Bool {
        guard let d = MTHistoryFile.read(),
              let back = try? JSONDecoder().decode([String: [Message]].self, from: d) else { return false }
        for (chat, rows) in snapshot where Set(rows.map { $0.mid }) != Set((back[chat] ?? []).map { $0.mid }) { return false }
        return true
    }

    // THE SNAPSHOT HAS ONE QUEUE AND A GENERATION (16.09). The whole-history write used to go to
    // the GLOBAL concurrent queue from three doors (the debounce, the archive heal, the restore):
    // two writes in flight, the elder capture finishing last and landing over the younger — a
    // second road to a lost row, with no kill needed. One serial queue keeps the order of arrival,
    // and the generation stamped at capture refuses an elder capture that arrives late (the
    // debounce holds its capture half a second before it queues). After the write the journal is
    // compacted against exactly what was written — never against what was captured later.
    private static let snapshotQueue = DispatchQueue(label: "montana.history.snapshot", qos: .utility)
    private static var snapshotGen = 0        // stamped on main at capture
    private static var snapshotWritten = 0    // touched on the snapshot queue only
    private static func captureGen() -> Int { snapshotGen += 1; return snapshotGen }
    /// The unread verdict's flag must not stand ahead of the history it speaks of: written on the snapshot queue
    /// behind that capture, and only if the capture reached the disk.
    private static func unreadVerdictStands(after gen: Int) {
        snapshotQueue.async { if gen <= snapshotWritten { UserDefaults.standard.set(true, forKey: ChatStore.unreadByLetterKey) } }
    }
    private static func writeSnapshot(_ snapshot: [String: [Message]], gen: Int, sync: Bool = false) {
        let work = {
            guard gen > snapshotWritten else {
                MontanaP2PTrace.mark("snapshot_stale", "gen=\(gen) written=\(snapshotWritten) — an elder capture, not written")
                return
            }
            if writeHistory(snapshot) {
                snapshotWritten = gen
                if historyReadsBack(snapshot) {
                    MTRowJournal.compact(against: snapshot)
                    // The blob of the old road (UserDefaults) leaves once the file holds the truth.
                    if UserDefaults.standard.object(forKey: "chatMessages") != nil { UserDefaults.standard.removeObject(forKey: "chatMessages") }
                } else {
                    MontanaP2PTrace.mark("history_write_lie", "the file reads back differently — the journal stays")
                    MontanaDiagShip.shipOnFailure()
                }
            }
        }
        if sync { snapshotQueue.sync(execute: work) } else { snapshotQueue.async(execute: work) }
    }
    /// A snapshot captured NOW, written in order on the one queue (main-thread caller).
    static func writeSnapshotNow(_ snapshot: [String: [Message]], sync: Bool = false) {
        writeSnapshot(snapshot, gen: captureGen(), sync: sync)
    }

    func save() {   // force save (going to background/termination)
        guard !retired else { return }   // a store that stepped down for a move writes nothing (retire)
        // While history is being READ there is nothing to save: a snapshot of empty feeds
        // written over the disk erases the correspondence whole. Folding the app in the first
        // seconds after launch is ordinary, and that sufficed.
        guard !loading else { MontanaP2PTrace.mark("save_skip", "history-not-read"); return }
        saveWork?.cancel(); saveWork = nil
        followStages()
        Self.writeSnapshotNow(messages, sync: true)
    }
    private func scheduleSave() {
        guard !loading, !retired else { return }   // SILENT-OK: history is still being read, or the store stepped down (retire)
        saveWork?.cancel()
        let snapshot = messages   // copy on main (copy-on-write — cheap)
        let gen = Self.captureGen()   // the generation is the CAPTURE's, not the moment the debounce fires
        let w = DispatchWorkItem { [weak self] in
            self?.followStages()   // the row's stage is written in the beat the letters are
            Self.writeSnapshot(snapshot, gen: gen)
        }
        saveWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: w)
    }
    /// THE STORE STEPS DOWN FOR A MOVE BETWEEN SEATS (the second identity checklist, 1.3): the feed reaches the disk now and
    /// in order, the half-second capture is taken back, and no capture after this line reaches the disk: a snapshot of this
    /// person written after the park would land over the next person's history. A background read of this person lands
    /// nowhere (the epoch). The screen that held the store leaves with the move; the next store is born from the disk.
    private var retired = false
    func retire() {
        save()
        saveWork?.cancel(); saveWork = nil
        retired = true
        seedEpoch += 1
        if ChatStore.live === self { ChatStore.live = nil }
        MontanaP2PTrace.mark("store_retired", "rows=" + String(messages.values.reduce(0) { a, b in a + b.count }))
    }
    // ── THE ARCHIVE → FEED ROAD (15.10) ─────────────────────────────────────────
    private var ingestedFolders = Set<String>()
    private var ingestWork: DispatchWorkItem?

    /// Called on main. Snapshots which chats already have rows, opens the sealed folders under
    /// the seed OFF the main thread, builds the rows there, and applies on main only if the
    /// identity that asked is still the one in front of the screen.
    func restoreFromArchive(epoch: Int, acct: String, folders: [String]?) {
        let occupied = Set(messages.filter { !$0.value.isEmpty }.keys)
        // THE ARCHIVE IS MEASURED AGAINST THE FEED (16.09): a letter the archive holds and the feed
        // does not is named with its count and its newest moment — measured here, never inserted (a
        // renamed file or an edited word reads as a gap too; the number says whether a letter was
        // lost, the hand decides what to do with it).
        let feedSigs: [String: Set<String>] = messages.mapValues { Set($0.compactMap { ChatStore.archiveSig($0) }) }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let pipesBefore = MTPipeBook.count
            let found = folders.map { MontanaArchive.restore(folders: $0) } ?? MontanaArchive.restoreAll()
            // The heads re-establish the pipes of a copy just taken back: the roads wake for them at once.
            let grew = pipesBefore < MTPipeBook.count
            DispatchQueue.main.async { self?.afterPipes(grew: grew) }
            guard !found.isEmpty else { return }
            var gapChats = 0, gapRows = 0
            for rc in found {
                guard let key = rc.ref, let have = feedSigs[key], !have.isEmpty else { continue }
                var seen = Set<String>(); var missing: [MontanaArchive.RestoredItem] = []
                for it in rc.items {
                    let sig = "\(Int(it.sentAt))|\(it.mine ? 1 : 0)|\(it.text)"
                    guard seen.insert(sig).inserted, !have.contains(sig) else { continue }
                    missing.append(it)
                }
                guard !missing.isEmpty else { continue }
                gapChats += 1; gapRows += missing.count
                let newest = missing.map { $0.sentAt }.max() ?? 0
                let media = missing.filter { $0.text.hasPrefix(mediaMark) }.count
                MontanaP2PTrace.mark("archive_gap", "chat=\(String(key.prefix(10))) feed=\(have.count) archive=\(rc.items.count) missing=\(missing.count) media=\(media) theirs=\(missing.filter { !$0.mine }.count) newest=\(hhmm(at: newest))")
            }
            if gapRows > 0 { MontanaP2PTrace.mark("archive_gap", "total chats=\(gapChats) rows=\(gapRows)") }
            // Rows go only into chats the feed does not hold: a chat that already has rows is
            // the truth (its edits, its deletions for everyone) and the archive must not
            // resurrect what the person removed. A twin's later blocks join a chat this way only
            // while it is still empty here — the incremental merge waits for tombstones.
            var built: [(MontanaArchive.RestoredChat, [Message])] = []
            for rc in found {
                let key = rc.ref ?? ("arc:" + rc.folder)
                guard !occupied.contains(key) else { continue }
                var seen = Set<String>(); var rows: [Message] = []; rows.reserveCapacity(rc.items.count)
                for it in rc.items {
                    let sig = "\(Int(it.sentAt))|\(it.mine ? 1 : 0)|\(it.text)"
                    guard !seen.contains(sig) else { continue }
                    seen.insert(sig)
                    // An identity of its own, so any later merge knows this row; read — the count reads
                    // this flag (T2, 06.09: a badge of 207 when it read a mark instead).
                    let mid = MTRestoredMid.archive + MontanaQueueKeys.sha256(Data(sig.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
                    if it.text.hasPrefix(mediaMark) {
                        // A media row: the file by its name in the correspondence store (it outlives
                        // the seed), the caption as the text. A record without a file name is not
                        // a row — nothing older wrote the mark into the archive.
                        guard let rec = try? JSONDecoder().decode(ArchivedMedia.self, from: Data(it.text.dropFirst(mediaMark.count).utf8)) else { continue }
                        rows.append(Message(text: rec.cap ?? "", isFromMe: it.mine, time: hhmm(at: it.sentAt), isRead: true,
                                            imageFile: rec.k == "img" ? rec.f : nil, videoFile: rec.k == "vid" ? rec.f : nil,
                                            audioFile: rec.k == "aud" ? rec.f : nil, audioDuration: rec.d ?? 0,
                                            docFile: rec.k == "doc" ? rec.f : nil, docName: rec.n,
                                            deliveryStatus: it.mine ? .sent : .read, msgId: mid, createdAt: it.sentAt))
                        continue
                    }
                    rows.append(Message(text: it.text, isFromMe: it.mine, time: hhmm(at: it.sentAt), isRead: true,
                                        deliveryStatus: it.mine ? .sent : .read, msgId: mid, createdAt: it.sentAt))
                }
                guard !rows.isEmpty else { continue }
                rows.sort { $0.createdAt < $1.createdAt }
                built.append((rc, rows))
            }
            guard !built.isEmpty else { return }
            DispatchQueue.main.async {
                guard let self, self.seedEpoch == epoch, (MontanaSeed.twin ?? "") == acct else { return }
                self.applyRestored(built)
            }
        }
    }

    /// On main, cheap: the rows are built already. A chat that gained rows meanwhile is skipped
    /// again (the snapshot is a moment old). A folder without a usable head is shown under
    /// «Recovered history» with the composer closed — the honest shape of an archive whose key
    /// this device no longer holds.
    @MainActor
    func applyRestored(_ built: [(MontanaArchive.RestoredChat, [Message])]) {
        MontanaMainProbe.crumb = "archive-apply"; defer { MontanaMainProbe.crumb = "" }
        // BOTH SHELVES ARE ASKED (the critic 24.09): a conversation standing in the archive keeps its row there — a
        // second, bare one on the standing shelf was a row twice (dup_rows) and hid nothing the archive did not.
        var rows = chatsShelf() ?? []
        let archivedKeys = Set(storedArchived().map { $0.convId ?? $0.name })
        var added = 0, rowsChanged = false, faces = 0, media = 0
        // A FACE THE ARCHIVE HOLDS FOR MORE THAN ONE CORRESPONDENT NAMES NONE OF THEM (04.10): a copy an older build sealed stays
        // out of the book, and its true owner is asked for it (holdsFace).
        var faceCount: [Data: Int] = [:]
        for (rc, _) in built { if let f = rc.face { faceCount[f, default: 0] += 1 } }
        for (rc, arr) in built {
            let key = rc.ref ?? ("arc:" + rc.folder)
            guard !deletedChats.contains(key), (messages[key] ?? []).isEmpty else { continue }
            messages[key] = ChatStore.allRead(arr)   // history is what the person has already seen (T2, 06.09: 207 unread)
            added += arr.count
            let status = rc.ref == nil ? "Recovered history" : ""
            if archivedKeys.contains(key) {
                // its row stands in the archive
            } else if let i = rows.firstIndex(where: { $0.convId == key || $0.name == key }) {
                // «Saved Messages» has no correspondent.  A stale row from an interrupted seat
                // move may still carry a foreign convId; repair it here, at the one archive
                // restore owner, rather than letting the composer mistake one's own notes for a
                // keyless transcript.
                if key == savedMessagesKey {
                    if rows[i].convId != nil || rows[i].status != "saved messages" {
                        rows[i].convId = nil
                        rows[i].status = "saved messages"
                        rowsChanged = true
                    }
                } else if rows[i].convId == nil {
                    rows[i].convId = key
                    rows[i].status = status
                    rowsChanged = true
                }
            } else {
                rows.insert(Chat(name: key, lastMessage: ChatStore.listPreview(arr[arr.count - 1]), time: arr[arr.count - 1].time,
                                 unread: 0, status: status, convId: key), at: 0)
                rowsChanged = true
            }
            if let n = rc.name, peerNames[key] != n {
                peerNames[key] = n
                MTNameBook.syncContact(conv: key, first: n, last: nil)
            }
            if let face = rc.face, faceCount[face] == 1, peerAvatars[key] == nil { setPeerAvatar(ref: key, data: face); faces += 1 }
            media += arr.filter { $0.imageFile ?? $0.videoFile ?? $0.audioFile ?? $0.docFile != nil }.count
            let last = arr.max(by: ChatStore.before) ?? arr[arr.count - 1]
            noteOrder(key, at: Int(last.createdAt * 1000))
            noteListState(key, last: last)
        }
        guard added > 0 || rowsChanged else { return }
        // THE SHELVES' ONE WRITER (the critic 24.09): the restored row was written past it and told only by
        // «restored», which the chats tab did not reread on — its stale copy wrote the row away at its next change
        // (T1: arc:d7f0fd without a row since 17.09).
        if rowsChanged { saveStored(chats: rows) }
        Self.writeSnapshotNow(messages)
        recalcBadge()
        NotificationCenter.default.post(name: .montanaChatsRestored, object: nil)
        MontanaP2PTrace.mark("archive_applied", "chats=\(built.count) rows=\(added) media=\(media) faces=\(faces) rows_changed=\(rowsChanged) keys=\(built.map { String(($0.0.ref ?? ("arc:" + $0.0.folder)).prefix(10)) }.joined(separator: ","))")
        auditListAgainstFeed(stage: "restore")
    }

    /// THE LIST IS THE FEED IS THE ARCHIVE — measured on every launch and after every restore,
    /// not believed (the author, 07.09). Three books, one truth: a row in the list without rows
    /// in the feed, a feed key without a row, two rows for one key, or a folder of the archive
    /// that no chat answers for — each is named with its count, and a disagreement is a failure
    /// line; the diary ships once for each kind of disagreement in a launch. Zero on every count is
    /// what «closed by construction» means.
    func auditListAgainstFeed(stage: String) {
        MontanaMainProbe.crumb = "list-audit"; defer { MontanaMainProbe.crumb = "" }
        // THE LIST IS BOTH ITS SHELVES (23.09): the rows standing and the rows in the archive — the store's own two
        // decodes; an archived conversation is no feed without a row. A SHELF THAT DOES NOT READ SAYS SO (err) and is
        // not counted as an empty one (the critic 24.09).
        let rowsRead = chatsShelf(), archivedRead = archivedShelf()
        let rows = rowsRead ?? [], archivedRows = archivedRead ?? []
        let keys = (rows + archivedRows).map { $0.convId ?? $0.name }
        var seen = Set<String>(), dupRows = 0
        for k in keys { if !seen.insert(k).inserted { dupRows += 1 } }
        let rowKeys = seen
        let feedKeys = Set(messages.filter { !$0.value.isEmpty }.keys)
        // A FEED WITHOUT A ROW IS A CONVERSATION THE PERSON CANNOT SEE (the critic 24.09), so the rows asked are the rows
        // shown: the saved ones, the ones the one builder derives from the feed — a live conversation, a recovered
        // transcript — and the archive's. T1's arc:d7f0fd, failing here since 17.09, was no archived conversation, as
        // this comment once said: its restored row had been written away by the chats tab's stale copy of the shelf,
        // and no builder derived it back. `derived` counts the conversations shown without a saved row.
        let shownKeys = Set(listRows(stored: rows).map { $0.convId ?? $0.name }).union(archivedRows.map { $0.convId ?? $0.name })
        let feedWithoutRow = feedKeys.filter { !shownKeys.contains($0) && $0 != savedMessagesKey && !deletedChats.contains($0) }
        let derived = feedKeys.filter { shownKeys.contains($0) && !rowKeys.contains($0) && $0 != savedMessagesKey }.count
        let groupKeys = Set((rows + archivedRows).filter { $0.isGroup }.map { $0.convId ?? $0.name })
        let rowWithoutFeed = rowKeys.filter { !feedKeys.contains($0) && !groupKeys.contains($0) }
        // A pipe reference and a folder label share one shape (32 hex): what makes a key a leftover
        // label is that no pipe answers for it (T1, 07.09: nine live chats counted as nine labels).
        // On either shelf (24.09): a leftover row is one wherever it stands — the archive is no hiding place.
        let held = rowKeys.filter { MontanaConv.holds($0) }
        let labelKeyed = rowKeys.filter { MontanaArchive.isLabel($0) && !MontanaConv.holds($0) && !closedChats.contains($0) }.count
        let folders = Set(MontanaArchive.conversations())
        // COMPAT-LOCAL: the archive row key never rides the wire — it names a restored folder on this device.
        let answered = Set(shownKeys.compactMap { k -> String? in Self.isTranscript(k) ? String(k.dropFirst(4)) : ((MontanaConv.holds(k) || closedChats.contains(k)) ? MontanaArchive.labelIfWarm(for: k) : nil) })
        let orphans = folders.subtracting(answered)
        // THE RECORD AND THE FEED AGREE ON THE LAST LETTER (16.09): a list row wearing the words of a
        // letter the feed does not hold is the very shape of a lost letter, and the counts of chats
        // above never saw it (T1 after 18:26Z: feed_no_row=0 with a phantom standing in the list).
        // NAMED, AND MEASURED AFTER THE DRAIN (17.09): the count stood at 1 on both phones at every
        // launch and named nothing — at «load» the drained letters had not reached the feed yet
        // (T2: drain at .286, audit at .292, bubbles at .571), so a benign moment and a lost letter
        // read alike. The chat and both words are written; at «drained» a disagreement is a failure.
        var recordAhead = 0
        var ahead: [String] = []
        for (chat, rec) in listState {
            guard let p = rec["p"], !p.isEmpty, let last = lastLetter(chat), !answerStands(rec, in: chat, over: last) else { continue }
            let feedWords = ChatStore.listPreview(last)
            if p != feedWords {
                recordAhead += 1
                ahead.append("\(String(chat.prefix(10)))[\(String(p.prefix(18)))≠\(String(feedWords.prefix(18)))]")
            }
        }
        let line = "stage=\(stage) rows=\(rowsRead == nil ? "err" : String(rows.count)) archived=\(archivedRead == nil ? "err" : String(archivedRows.count)) feed=\(feedKeys.count) folders=\(folders.count) held=\(held.count) dup_rows=\(dupRows) feed_no_row=\(feedWithoutRow.count) derived=\(derived) row_no_feed=\(rowWithoutFeed.count) label_keyed=\(labelKeyed) transcripts=\(shownKeys.filter { Self.isTranscript($0) }.count) orphan_folders=\(orphans.count) record_ahead=\(recordAhead) ahead=\(ahead.joined(separator: ",")) orphans=\(orphans.sorted().map { String($0.prefix(6)) }.joined(separator: ","))"
        var kinds = Set<String>()
        if dupRows > 0 { kinds.insert("dup") }
        if labelKeyed > 0 { kinds.insert("label") }
        if !feedWithoutRow.isEmpty { kinds.insert("feed") }
        if stage == "drained", recordAhead > 0 { kinds.insert("record") }
        if rowsRead == nil || archivedRead == nil { kinds.insert("shelf") }
        if !kinds.isEmpty {
            MontanaP2PTrace.mark("list_audit_fail", line + " kinds=\(kinds.sorted().joined(separator: ",")) feed_no_row=" + feedWithoutRow.map { String($0.prefix(10)) }.joined(separator: ","))
            // ONE SHIPMENT FOR EACH KIND IN A LAUNCH (the critic 24.09): a standing disagreement shipped the diary at
            // every drain of the box — a storm, and each copy said what the first had; the line above still stands.
            if !kinds.isSubset(of: auditShipped) { auditShipped.formUnion(kinds); MontanaDiagShip.shipOnFailure() }
        } else {
            MontanaP2PTrace.mark("list_audit", line)
        }
    }
    private var auditShipped = Set<String>()

    // Wipe ALL local history and chat metadata (a different seed takes over -> another identity's data is not shown).
    func wipeLocal() {
        seedEpoch += 1   // invalidate any background load of the previous account's history
        listState = [:]; MontanaKeychain.delete("chatListState"); MontanaKeychain.delete("chatListOverlay")   // the list record dies with the identity (stage 9)
        MTRowJournal.dropAll(); MTHistoryFile.drop()   // and the journal of rows and the history file with it
        MontanaKeychain.delete("orderCold")   // and so does the order it stood in
        for k in ["readChatsCold", "pinnedCold", "forcedUnreadCold", "archivedCold", "deletedCold", "closedCold", "mutedChats"] {
            MontanaKeychain.delete(k)         // ... and every set the first frame would have consulted
        }
        MTNameBook.wipeCold()   // and so does the cold name mirror
        messages = [:]; pinned = [:]; scheduled = []; applyOrder([:])
        pinnedChats = []; forcedUnread = []; mutedChats = []
        archivedNames = []; deletedChats = []; closedChats = []; peerAvatars = [:]; peerNames = [:]   // didSet of each -> UserDefaults is cleared
    }
    func savePinned() {
        if let d = try? JSONEncoder().encode(pinned) {
            MontanaLocalVault.setEncrypted("pinnedMessages", d)
        }
    }
    func saveScheduled() {
        if let d = try? JSONEncoder().encode(scheduled) {
MontanaLocalVault.setEncrypted("scheduledMsgs", d)
        }
    }
    // schedule sending text at a point in time
    func schedule(chat: String, convRef: String?, text: String, at fireAt: Double) {
        let s = ScheduledMsg(id: UUID(), chat: chat, convRef: convRef, text: text, fireAt: fireAt)
        scheduled.append(s)
        // A note to oneself at a chosen moment is a REMINDER (15.52): the system rings it even
        // with the app closed; the note lands in Saved Messages when the app next runs its clock.
        if convRef == nil { MontanaNotify.scheduleReminder(id: s.id, text: text, at: fireAt) }
    }
    // send all scheduled ones whose time has come
    @MainActor func fireDueScheduled() {
        let now = Date().timeIntervalSince1970
        let due = scheduled.filter { $0.fireAt <= now }
        guard !due.isEmpty else { return }
        scheduled.removeAll { $0.fireAt <= now }
        for s in due { _ = send(text: s.text, chat: s.chat, convRef: s.convRef) }
    }

    // pin/unpin messages in a chat (no limit — as many as you want)
    func pin(_ chat: String, _ id: MID) {
        var list = pinned[chat] ?? []
        let s = id
        guard !list.contains(s) else { return }   // already pinned
        list.append(s)                            // no limit on the count
        pinned[chat] = list
    }
    func unpin(_ chat: String, _ id: MID) {
        var list = pinned[chat] ?? []
        list.removeAll { $0 == id }
        pinned[chat] = list.isEmpty ? nil : list
    }
    // pinned messages of the chat in pin order (only those that actually exist)
    func pinnedMessages(_ chat: String) -> [Message] {
        guard let ids = pinned[chat], let msgs = messages[chat] else { return [] }
        return ids.compactMap { idStr in msgs.first { $0.id == idStr } }
    }
    func isPinned(_ chat: String, _ id: MID) -> Bool {
        pinned[chat]?.contains(id) ?? false
    }

    // change message text (editing)
    @MainActor
    /// Rows that still hold a long-letter REFERENCE instead of words (an older build wrote the
    /// raw reference when the blob was out of reach) are healed here: the blob is fetched now
    /// that every door serves every blob, and the words take the reference's place. Nothing
    /// else on the row changes. Called when a chat opens; a row that cannot be healed yet waits
    /// and is drawn as «New message», never as raw text. THE ONE ROAD, ITS HOUR AND ITS VERDICT
    /// (the author's word 25.09: «do not try to fetch what is not there, and do not ask again once
    /// it is known to be absent»): the heal asked every door at every opening of the chat, past the
    /// long letter's one road — measured on the iPhone 15 on 25.09: 134 openings, 323 «no such
    /// cargo» for three rows, a wheel turning for ever on each. The row takes that road now: its
    /// hour between questions, and the verdict that buries it — then the row says its words are
    /// gone and is never asked for again. A row older than the box's term is buried at its first
    /// refusal.
    func healUnresolvedRows(_ chat: String) {
        let refs = (messages[chat] ?? []).filter { $0.text.hasPrefix(MontanaWakePush.letterBlobMark) && !$0.lost }
        guard !refs.isEmpty else { return }
        MontanaP2PTrace.mark("lb_heal", "chat=\(String(chat.prefix(10))) rows=\(refs.count)")
        let conv = MontanaConv.holds(chat) ? chat : ""
        Task {
            for row in refs {
                let taken = await MontanaWakePush.takeLongLetter(conv: row.isFromMe ? "" : conv, mid: row.id, text: row.text,
                                                                 bornAt: row.createdAt)
                await MainActor.run {
                    guard let i = self.messages[chat]?.firstIndex(where: { $0.id == row.id }) else { return }
                    switch taken {
                    case .landed(let full):
                        self.messages[chat]?[i].text = full
                        if let m = self.messages[chat]?[i] { self.archiveRow(chat, m) }
                        MontanaP2PTrace.mark("lb_heal", "ok bytes=\(full.utf8.count)")
                    case .buried:
                        self.messages[chat]?[i].lost = true
                        MontanaP2PTrace.mark("lb_heal", mid: row.id, "buried — the row says its words are gone and asks no more")
                    case .waiting:
                        break
                    }
                }
            }
        }
    }

    /// A VOICE OR A ROUND NOTE OF THEIRS WAS PLAYED HERE (the author's word 25.09: «Listened instead of Read, only upon the
    /// voice's actual playing»; «Viewed» for a round note): the player started it — a tap, or the chat's next voice after the
    /// last — and its sender is told once, silently, by the one queue. Opening the chat plays nothing and says nothing.
    func notePlayed(file: String) {
        let order = (openConv.map { [$0] } ?? []) + messages.keys.filter { $0 != openConv }
        for chat in order {
            guard let i = messages[chat]?.firstIndex(where: { $0.audioFile == file || $0.videoFile == file }) else { continue }
            guard let m = messages[chat]?[i], !m.isFromMe, !m.heard else { return }
            messages[chat]?[i].heard = true
            guard MontanaConv.holds(chat) else { return }
            MontanaDeliveryEngine.shared.enqueue(to: chat, chat: chat, mid: UUID().uuidString, text: playedMark + m.mid, silent: true)
            MontanaP2PTrace.mark("played_tx", "kind=\(m.audioFile == nil ? "note" : "voice")")
            return
        }
    }
    /// The source of a forward, written on the local row only (15.51).
    func noteForwardSource(chat: String, id: MID, from: String) {
        guard let i = messages[chat]?.firstIndex(where: { $0.id == id }) else { return }
        messages[chat]?[i].fwdFrom = from
    }

    /// THE EDIT REACHES THE OTHER SCREEN (the author's word 13.09: edited on the first phone, unchanged
    /// on the second). The words changed on the editor's phone and nowhere else: two people read two
    /// different letters and neither screen said so. The edit now walks the ONE road every other word
    /// of a conversation walks — the letter's own wire name, the new words, a silent leg, the engine's
    /// guarantee and its retries. The feed itself is the persistence (messages saves on change); the
    /// sealed archive is append-only and serves the seed's return, where a living chat already wins.
    func editMessage(_ chat: String, id: MID, newText: String) {
        guard let i = messages[chat]?.firstIndex(where: { $0.id == id }),
              let row = messages[chat]?[i], row.text != newText else { return }   // nothing changed — the wire says nothing
        // A coin letter is never edited, and no edit becomes one (06.10): its coins were taken once, under its words.
        guard row.coinLetter == nil, MTCoinLetter.parse(newText) == nil else { return }
        messages[chat]?[i].text = newText
        messages[chat]?[i].edited = true
        if lastLetter(chat)?.id == id { noteListState(chat, last: lastLetter(chat)) }   // the list row follows the words
        // A letter of one's own, with a wire name, in a conversation with a wire: only that can be
        // edited on the other screen. A note to oneself has no second screen; a row restored from the
        // archive («arc:») was never a letter of this wire and has no name the peer would know.
        guard !Self.isLocalRoom(chat), row.isMine, let sid = row.msgId, sid.hasPrefix("mid:") else { return }
        let body: [String: String] = ["sid": String(sid.dropFirst(4)), "tx": newText]
        guard let d = try? JSONSerialization.data(withJSONObject: body),
              let js = String(data: d, encoding: .utf8) else { return }
        MontanaP2PTrace.mark("edit_tx", "mid=\(String(sid.dropFirst(4)).prefix(8)) len=\(newText.count)")
        // A group's edit rides the group's carrier to every phone of it (MTGroup.signal), never to an address it does not have.
        if MTGroup.isKey(chat) { Task { @MainActor in MTGroup.shared.signal(editMark + js, in: chat, store: self) }; return }
        MontanaDeliveryEngine.shared.enqueue(to: chat, chat: chat, mid: UUID().uuidString,
                                             text: editMark + js, silent: true)
    }

    /// THE PEER'S EDIT. Applied ONLY to a row that came FROM this peer: a word off the wire may never
    /// rewrite my own letters, or one side could put words into the other's mouth. Only the words of a
    /// text letter change — a picture, a voice, a call row and a service word are not letters whose
    /// words can be rewritten — and the new text is a person's text: within a bubble's length and
    /// carrying no service mark of its own. An edit for a letter still on the road is remembered and
    /// applied the moment it lands, so the race between the two words cannot lose the newer one.
    private var pendingEdits: [String: [String: String]] = [:]   // chat → wire name → new words
    @MainActor
    func applyEditFromPeer(_ chat: String, body: String) {
        guard let d = body.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let sid = obj["sid"] as? String, !sid.isEmpty, sid.count <= 128,
              let tx = obj["tx"] as? String, !tx.isEmpty, tx.count <= 4500,
              !isControlMarker(tx), !mtUnknownServiceWord(tx) else {
            MontanaP2PTrace.mark("edit_rx", "REFUSED — not a person's words")
            return
        }
        let rowId = sid.hasPrefix("mid:") ? sid : "mid:" + sid
        guard let i = messages[chat]?.firstIndex(where: { $0.msgId == rowId }), let row = messages[chat]?[i] else {
            var forChat = pendingEdits[chat] ?? [:]
            if forChat.count >= 32, let oldest = forChat.keys.first { forChat[oldest] = nil }   // a bound, not a memory
            forChat[rowId] = tx
            pendingEdits[chat] = forChat
            MontanaP2PTrace.mark("edit_rx", "held mid=\(String(sid.prefix(8))) — the letter has not landed yet")
            return
        }
        // A PICTURE'S OR A VIDEO'S CAPTION IS A PERSON'S WORDS (the author's word 19.09): it takes the
        // peer's edit like a text letter — never one's own letter, never a voice, a file or a call row.
        let captioned = !row.isMine && (row.imageFile != nil || row.videoFile != nil)
            && row.audioFile == nil && row.docFile == nil && !isControlMarker(row.text)
        if captioned {
            // the caption's road joins the text letter's below
        } else {
        guard !row.isMine, row.imageFile == nil, row.videoFile == nil,
              row.audioFile == nil, row.docFile == nil, !isControlMarker(row.text) else {
            MontanaP2PTrace.mark("edit_rx", "REFUSED mid=\(String(sid.prefix(8))) — not the peer's text letter")
            return
        }
        }
        guard row.text != tx else { return }   // the same words twice (two roads) — nothing to do
        messages[chat]?[i].text = tx
        messages[chat]?[i].edited = true
        if lastLetter(chat)?.id == row.id { noteListState(chat, last: lastLetter(chat)) }
        MontanaP2PTrace.mark("edit_rx", "applied mid=\(String(sid.prefix(8))) len=\(tx.count)")
    }
    /// The words held for a letter that had not landed — taken once, at its landing.
    private func takePendingEdit(_ chat: String, sid: String) -> String? {
        guard var forChat = pendingEdits[chat], let tx = forChat[sid] else { return nil }
        forChat[sid] = nil
        pendingEdits[chat] = forChat.isEmpty ? nil : forChat
        return tx
    }

    func seedIfNeeded(_ chat: String) {
        if messages[chat] == nil { messages[chat] = [] }
    }
    // Chat folder name = display name (title); on rename the folder migrates.
    // DETERMINISTIC for a single address: fallback — display form of the address, NOT the raw key
    // (otherwise text before the chat appears in the list and media after it land in DIFFERENT folders).
    // Self-healing: folders of historical names (raw address, etc.) are merged into the current one.
    private var folderChatsCache: (json: String, chats: [Chat])?   // decode cache (don't parse JSON on every message)
    /// The archive's folder names name nobody — neither living conversations nor those left of
    /// deleted ones. The conversation is gone — so its trace on this phone is gone too ([C-1]:
    /// one road for «delete for me» and «delete for both»). Everything goes: the sealed
    /// archive of letters and attachments, the files lying on disk under names from the feed,
    /// and its media's shipping chunks. Deletion used to erase the feed in memory and set a
    /// «deleted» mark while everything stayed on disk.
    func purgeLocalCopies(_ conv: String) {
        let msgs = messages[conv] ?? []
        var blobs: [String] = []
        var files: [String] = []
        for m in msgs {
            if let f = m.videoFile ?? m.imageFile ?? m.audioFile ?? m.docFile { files.append(f) }
            guard m.text.hasPrefix(mediaMark) else { continue }
            let body = String(m.text.dropFirst(mediaMark.count))
            guard let d = body.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let chunks = obj["chunks"] as? [[String: Any]] else { continue }
            blobs.append(contentsOf: chunks.compactMap { $0["bid"] as? String })
        }
        MontanaBlobStore.drop(blobs)
        // Forwarding puts the SAME file name into another conversation; there is no second
        // copy. An unchecked teardown carried the attachment out of the surviving
        // conversation: the bubble stayed empty forever.
        var elsewhere = Set<String>()
        for (other, msgs) in messages where other != conv {
            for m in msgs {
                for f in [m.videoFile, m.imageFile, m.audioFile, m.docFile] {
                    if let f, !f.isEmpty { elsewhere.insert(f) }
                }
            }
        }
        MontanaMediaStore.remove(files.filter { !elsewhere.contains($0) })
        for f in files {
            try? FileManager.default.removeItem(at: mediaTmpURL(f))
            try? FileManager.default.removeItem(at: docsURL().appendingPathComponent(f))
            try? FileManager.default.removeItem(at: posterURL(f))   // the pictures go with the file
            MTNoteFrame.forget(f)
            MontanaVideoMark.unmark(f)
            MontanaSmallPicture.forget(f)
        }
        MontanaArchive.deleteChatFolder(convRef: conv)
        MontanaP2PTrace.mark("chat_purge", "files=\(files.count) blobs=\(blobs.count)")
    }

    /// The conversation is gone from THIS device — one road for «I erased» and «the peer
    /// erased» ([C-1]).
    ///
    /// The receiver's branch erased the feed and set the mark but left the LIST ROW alone:
    /// the conversation stayed on screen, and the first service letter on it recreated the
    /// archive folder. The list is stored apart from the feed, so it is removed by the same
    /// motion, and the screen learns of it by announcement, not by guessing.
    func removeConversationLocally(_ conv: String) {
        // THE COINS OF A LETTER THAT CAN NO LONGER GO COME BACK FIRST (the author's word «fix all points in order» 05.10.2026 21:4x
        // MSK, the coin audit's first point): the correspondent's erasure reaches here unasked, and the queue and the node box of the
        // conversation go with it (clearChat) -- a coin letter of mine still holding its coins gives them back before its row goes.
        for m in (messages[conv] ?? []) where m.isFromMe && m.coinLetter != nil {
            let back = { MainActor.assumeIsolated { MTCoinSend.release(m, in: conv) } }   // the row's values ride along; the book moves on main
            if Thread.isMainThread { back() } else { DispatchQueue.main.async(execute: back) }
        }
        // «Delete for both» — AT THE ROOT: every mid of the conversation gets its tombstone AT
        // ONCE, and a letter returning by ANY repeat (the node store, the extension box, the
        // live channel, a repeated link tap) does not resurrect (precedent 934: a repeated tap
        // resurrected a deleted message). The extension box is purged of this conversation's
        // rows by the same motion. The node half — removing the undelivered from the node
        // store — is stage 7.
        for m in (messages[conv] ?? []) { if let mid = m.msgId { deletedMids.insert(mid) } }
        if let d = MontanaKeychain.get("nseInbox"),
           var arr = try? JSONDecoder().decode([[String: String]].self, from: d) {
            let before = arr.count
            arr.removeAll { $0["c"] == conv }
            if arr.count != before, let out = try? JSONEncoder().encode(arr) { MontanaKeychain.set("nseInbox", out) }
        }
        purgeLocalCopies(conv)
        MTRowJournal.dropChat(conv)
        messages[conv] = nil
        noteListState(conv, last: nil)   // the list record dies with the conversation, NOW (stage 9; 1640: no window)
        deletedChats.insert(conv)
        // The unread count dies with the conversation (didSet -> recalcBadge -> the icon).
        forcedUnread.remove(conv)
        MontanaDeliveryEngine.shared.clearChat(conv)
        closedChats.remove(conv)
        dropShelfRow(conv)
    }
    /// A conversation's row leaves the standing shelf — the shelves' one writer tells the tabs itself; with no row
    /// standing, the tabs are told directly.
    func dropShelfRow(_ conv: String) {
        if var arr = chatsShelf(), arr.contains(where: { $0.convRef == conv || $0.name == conv }) {
            arr.removeAll { $0.convRef == conv || $0.name == conv }
            saveStored(chats: arr)
        } else {
            NotificationCenter.default.post(name: .montanaChatsChanged, object: nil)
        }
    }

    /// THE PIPE CLOSED AT THE OTHER END (24.09, the author's word «do it»): the other side's sweep buried a pipe it holds
    /// no conversation for, and said so. A folded pipe simply dies; a meeting that never carried a word leaves no row; a
    /// conversation keeps its history, readable, its composer gives way to a note, and its folder's head says «closed» —
    /// no restore revives the pipe. The pipe dies as a tombstone receiver's does: the receipt leaves by its secret, and
    /// the next drain buries it.
    func peerClosedPipe(_ conv: String) {
        MTPipeBook.markDying(conv)
        if MTSamePair.merged(conv) != nil {
            MontanaP2PTrace.mark("pipe_closed", "folded conv=\(String(conv.prefix(10)))")
            return
        }
        guard !(messages[conv] ?? []).isEmpty else {
            messages[conv] = nil
            noteListState(conv, last: nil)
            MontanaArchive.deleteChatFolder(convRef: conv)
            dropShelfRow(conv)
            MontanaP2PTrace.mark("pipe_closed", "empty conv=\(String(conv.prefix(10)))")
            return
        }
        closedChats.insert(conv)
        MontanaArchive.closeHead(convRef: conv, legacy: legacyFolderNames(conv))
        MontanaP2PTrace.mark("pipe_closed", "kept conv=\(String(conv.prefix(10))) rows=\(messages[conv]?.count ?? 0)")
    }

    /// The attachment's chunk manifest by file name: what to assemble it from when no whole file exists.
    func mediaManifest(forFile name: String) -> (chunks: [[String: Any]], key: Data, size: Int)? {
        for (_, msgs) in messages {
            for m in msgs where (m.videoFile ?? m.imageFile ?? m.audioFile ?? m.docFile) == name
                && m.text.hasPrefix(mediaMark) {
                let body = String(m.text.dropFirst(mediaMark.count))
                guard let d = body.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                      let chunks = obj["chunks"] as? [[String: Any]],
                      let bk = (obj["bk"] as? String).flatMap({ Data(base64Encoded: $0) }),
                      let size = obj["sz"] as? Int else { continue }
                return (chunks, bk, size)
            }
        }
        return nil
    }

    /// A file no letter names is litter: the conversation erased, the message removed.
    func sweepMediaFiles() {
        // An empty history means «not read yet», not «nobody needs the files»: the disk read
        // comes second, seconds later, and a cleanup arriving earlier would carry off the
        // WHOLE PANTRY — no second copy exists anywhere. The refusal is spoken aloud.
        guard !loading, !messages.isEmpty else {
            MontanaP2PTrace.mark("media_sweep", "skip=history-not-read")
            return
        }
        var live = Set<String>()
        // THE BOOKS ARE ALIVE TOO (the author's word 22.09: «it did not survive a restart»). A set's
        // stickers and the moving pictures this phone keeps are named by NO letter, so the sweep --
        // which carries off whatever no letter names -- took them on the next launch and the panel
        // came back empty. Each book names its own files; nothing here knows their shape.
        live.formUnion(MontanaStickerBook.shared.allFiles)
        live.formUnion(MTBoard.shared.allFiles)   // the wall's kept files (24.09): named by no letter
        live.formUnion(MontanaGifBook.shared.allFiles)
        for (_, msgs) in messages {
            for m in msgs {
                for f in [m.videoFile, m.imageFile, m.audioFile, m.docFile] {
                    if let f, !f.isEmpty { live.insert(f) }
                }
            }
        }
        DispatchQueue.global(qos: .utility).async {
            // TWO THINGS ARE ALIVE BESIDES THE LETTERS (the critic 22.09). A file the composer
            // HOLDS — a picture pasted or picked and not sent yet — wears no letter's name and
            // was litter by definition. And a file JUST BORN on any road has not reached its
            // letter yet: the gap is milliseconds, but the living set above was taken on the main
            // actor while the folder is listed here, on another queue, later. Birth is read from
            // the disk itself, so the paste, the gallery, the camera, the forward's link and every
            // road written after this line are covered without one of them being named — the store's
            // doors stamp the arrival (MontanaMediaStore.stampArrival): a file moved, copied or linked in
            // would otherwise carry its source's birth, and a track poured from a folder looked years old.
            let holds = MontanaMediaStore.held
            // A FILE STILL BEING LAID (25.09, MTStreamLoader): «name.part» and its ledger «name.have» are the file's own while
            // its name is alive — a play's pieces are never carried off from under the player.
            let laying = Set(live.flatMap { [$0 + MTStreamLoader.partTail, $0 + MTStreamLoader.ledgerTail] })
            let orphans = MontanaMediaStore.names().subtracting(live).subtracting(holds).subtracting(laying)
                .filter { !MontanaMediaStore.newborn($0) }
            guard !orphans.isEmpty else { return }   // SILENT-OK: a cleanup, not delivery — nothing to report
            MontanaMediaStore.remove(Array(orphans))
            // THE CLEANUP NAMES WHAT IT CARRIED OFF. «dropped=1» was all the diary said while a
            // person's photograph was going; the loss was found by the author's eyes, not by any
            // judge. The names are random file ids — they tell nothing of the picture.
            let gone = orphans.sorted().prefix(4).map { String($0.prefix(16)) }.joined(separator: ",")
            MontanaP2PTrace.mark("media_sweep",
                                 "dropped=\(orphans.count) kept=\(live.count) held=\(holds.count) gone=\(gone)")
        }
    }

    /// A chunk is needed WHILE THE CARRIAGE RUNS — and not a minute longer.
    ///
    /// The sign «a letter references the chunk» kept the crate forever: 651 chunks of a
    /// three-hundred-megabyte track lay beside the sealed file of the same size. The sign
    /// «the file is not here yet» proved no better: on a phone with deleted conversations
    /// there are no files at all, and the same crate stayed forever — measured, 1332 chunks
    /// after a cleanup.
    ///
    /// The one honest sign: the carriage either runs or has ended. Running receptions are
    /// written on disk (pendingMediaJSON — the very intent that survives interruption), the
    /// sender's fresh slicing is covered by a quarter-hour window. Everything else is litter.
    func sweepBlobs() {
        var keep = Set<String>()
        // A big attachment is stored AS CHUNKS: it cannot be decrypted whole — three hundred
        // megabytes do not fit in memory. While no whole file exists in the archive, the
        // chunks ARE the archive and must not be touched (or there is nothing left to open
        // the attachment with — precedent: the 341 MB track).
        // The file is ready — the crate is not needed. The check used to go against the
        // sealed archive, but media is no longer written there at all: the sign was always
        // false, and chunks piled beside a file of the same size — the very «disk taken twice».
        for (_, msgs) in messages {
            for m in msgs where m.text.hasPrefix(mediaMark) {
                let file = (m.videoFile ?? m.imageFile ?? m.audioFile ?? m.docFile) ?? ""
                guard !file.isEmpty, !MontanaMediaStore.exists(file) else { continue }
                let body = String(m.text.dropFirst(mediaMark.count))
                guard let d = body.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                      let chunks = obj["chunks"] as? [[String: Any]] else { continue }
                for c in chunks { if let b = c["bid"] as? String { keep.insert(b) } }
            }
        }
        let inflight = (try? JSONSerialization.jsonObject(with: Data(pendingMediaJSON.utf8)) as? [[String: String]]) ?? []
        for it in inflight {
            guard let body = it["body"], let d = body.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let chunks = obj["chunks"] as? [[String: Any]] else { continue }
            for c in chunks { if let b = c["bid"] as? String { keep.insert(b) } }
        }
        // THE PIECES THE LANDING DOOR LAID (29.09): a letter still in the extension's inbox names its pieces too — they are the
        // shelf's purpose, not litter; the app applies the letter at its next drain and assembles from them without a door.
        if let d = MontanaKeychain.get("nseInbox"),
           let rows = try? JSONDecoder().decode([[String: String]].self, from: d) {
            for r in rows {
                guard let t = r["t"], t.hasPrefix(mediaMark), let bd = String(t.dropFirst(mediaMark.count)).data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: bd) as? [String: Any],
                      let chunks = obj["chunks"] as? [[String: Any]] else { continue }
                for c in chunks { if let b = c["bid"] as? String { keep.insert(b) } }
            }
        }
        DispatchQueue.global(qos: .utility).async { MontanaBlobStore.sweepUnreferenced(keep: keep) }
    }

    func sealArchiveFolderNames() {
        let arr = (try? JSONDecoder().decode([Chat].self,
                    from: Data((MontanaLocalVault.getString("chatsJSON") ?? "").utf8))) ?? []
        // A living conversation does not wait for a letter to migrate: its folder's old name
        // is read right now, not on the day the person writes into it.
        var shared = Set<String>()   // a caption several inherited at once belongs to none of them
        for c in arr where arr.filter({ $0.title == c.title }).count > 1 { shared.insert(c.title) }
        for c in arr {
            MontanaArchive.migrate(convRef: c.convRef, legacy: legacyFolderNames(c.convRef))   // the one resolver, on its queue
        }
        // Conversations a person erased are carried through on EVERY opening: the deletion
        // may not have finished (the phone was closed), and a catching-up big-file assembly
        // may resurrect the folder.
        for conv in deletedChats { MontanaArchive.deleteChatFolder(convRef: conv) }
        // The rest — folders of deleted conversations and the shared melting-pot word: the
        // name loses meaning, the data lies on.
        MontanaArchive.sealOrphanFolderNames(keeping: shared)   // the pass itself runs in its own turn
    }

    /// An erased conversation is NOT written to disk. A big file assembles for minutes, and a
    /// catching-up assembly used to resurrect the folder after the deletion: measured — the
    /// folder torn down at 22:16, and at 22:19 325 MB were written into it. One guard for
    /// every archive write ([C-1]).
    func archivable(_ conv: String) -> Bool { !deletedChats.contains(conv) }

    /// THE ONE ROAD FROM A ROW TO THE ARCHIVE ([C-1], 15.10.4). A letter goes as its text; a
    /// media row goes as the media mark plus a small record — kind, the file's name in the
    /// correspondence store, the document's name, the caption, the voice's length. Media rows
    /// were born in four places and archived in none: after «Forget this device» every photo,
    /// video, voice and file was gone from the restored chat, while its file still lay in the
    /// store. The file's name is what a restore needs to find it again without the network.
    /// What a row is in the archive — ONE builder for the write and for the audit against it ([C-1]).
    static func archivedText(_ m: Message) -> String? {
        guard let f = m.imageFile ?? m.videoFile ?? m.audioFile ?? m.docFile else { return m.text }
        let kind = m.imageFile != nil ? "img" : (m.videoFile != nil ? "vid" : (m.audioFile != nil ? "aud" : "doc"))
        let rec = ArchivedMedia(k: kind, f: f, n: m.docName, cap: m.text.isEmpty ? nil : m.text, d: m.audioDuration > 0 ? m.audioDuration : nil)
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        guard let d = try? enc.encode(rec), let s = String(data: d, encoding: .utf8) else { return nil }
        return mediaMark + s
    }
    /// The archive's own name of a row — the second, the direction, the words — what a restore keys by.
    static func archiveSig(_ m: Message) -> String? {
        guard m.createdAt > 0, let t = archivedText(m), !t.isEmpty else { return nil }
        return "\(Int(m.createdAt))|\(m.isFromMe ? 1 : 0)|\(t)"
    }
    func archiveRow(_ chat: String, _ m: Message) {
        guard archivable(chat), let text = Self.archivedText(m) else { return }
        let at = m.createdAt > 0 ? m.createdAt : Date().timeIntervalSince1970
        MontanaArchive.archive(convRef: chat, legacy: legacyFolderNames(chat), isFromMe: m.isFromMe, createdAt: at, text: text)
    }

    /// THE DOOR OUT SEALS EVERYTHING THE SEED CAN REOPEN (15.10.4, the author's word 07.09:
    /// «everything stored locally and restored exactly on leaving without deleting the app»).
    /// Every correspondence this device answers for: its secret, the correspondent's name, their
    /// face — into its folder, sealed under the seed, and flushed to disk BEFORE the seed and the
    /// book leave. Letters and media rows are already there by their birth. The mark names the
    /// counts, and `sealed=0` names the one case nothing could be sealed: no seed at hand.
    func sealForForget(then done: @escaping () -> Void) {
        guard MontanaSeed.mnemonic != nil else { MontanaP2PTrace.mark("forget_seal", "sealed=0 — no seed at hand"); done(); return }
        // The plan is read on main (the store's own books); the folders are resolved and the disk is
        // touched on the archive's queue — the key is never derived on the screen's thread.
        let plan: [(chat: String, legacy: [String], name: String?, face: String?)] = messages.keys
            .filter { archivable($0) && MontanaConv.holds($0) }
            // Only the face the screen draws is sealed (04.10): the raw book carried a copied portrait from folder to folder.
            .map { ($0, legacyFolderNames($0), peerNames[$0], publishedFace($0)) }
        var heads = 0, names = 0, faces = 0
        for p in plan {
            MontanaArchive.writeHead(convRef: p.chat, legacy: p.legacy); heads += 1
            if let n = p.name, !n.isEmpty { MontanaArchive.writeNameHead(convRef: p.chat, legacy: p.legacy, name: n); names += 1 }
            if let f = p.face, MontanaArchive.sealFace(convRef: p.chat, legacy: p.legacy, avatarFile: f) { faces += 1 }
        }
        MontanaArchive.whenWritten {
            MontanaP2PTrace.mark("forget_seal", "sealed=1 held=\(heads) names=\(names) faces=\(faces)")
            done()
        }
    }

    /// THE OLD NAMES OF A CONVERSATION'S FOLDER — and nothing else (22.09, the critic). The folder's
    /// label itself is the archive's to resolve, on its own queue, where the keys are born; the screen's
    /// thread only names what the folder used to be called: the row's name and a caption that belongs
    /// to exactly one conversation (the nameless share one word, and that word is nobody's). A recovered
    /// transcript («arc:») names no live conversation and has no old names.
    func legacyFolderNames(_ key: String) -> [String] {
        if key.hasPrefix("arc:") { return [] }
        let js = MontanaLocalVault.getString("chatsJSON") ?? ""
        let arr: [Chat]
        if let c = folderChatsCache, c.json == js { arr = c.chats }
        else {
            arr = (try? JSONDecoder().decode([Chat].self, from: Data(js.utf8))) ?? []
            folderChatsCache = (js, arr)
        }
        var legacy: [String] = []
        if let c = arr.first(where: { $0.convRef == key || $0.name == key }) {
            if c.name != key { legacy.append(c.name) }
            if !c.title.isEmpty, arr.filter({ $0.title == c.title }).count == 1 { legacy.append(c.title) }
        }
        return legacy
    }

    /// Whether the letter landed in the feed. The caller needs the answer: a service signal
    /// is handled here and does NOT become the feed, so it creates no correspondence either.
    /// While there was no answer, «bytes arrived» and «a conversation exists» passed for the
    /// same thing, and any receipt created a row without a single message inside.
    @discardableResult
    @MainActor
    func append(_ chat: String, _ m: Message) -> Bool {
        // A FOLDED PIPE FORWARDS (24.09, MTSamePair): a word still on its way over a pipe folded into a conversation lands
        // in that conversation — never as a second row of the same person — and a person blocked there stays blocked on
        // every pipe of theirs. The words that speak of the pipe itself are read on it; a letter of theirs into the folded
        // pipe says our answer may have been lost, and it is said again.
        let speaksFor = MTSamePair.root(chat)
        if speaksFor != chat, !MTSamePair.speaksOfPipe(m.text) {
            if refuses(speaksFor) { MontanaP2PTrace.mark("same_blocked", "folded pipe of a blocked person"); return false }
            if !m.isFromMe, !isControlMarker(m.text) { MTSamePair.remind(chat) }
            return append(speaksFor, m)
        }
        // A BLOCKED PERSON REACHES NOTHING (Guideline 1.2): not a row, not a receipt, not a
        // presence stamp — the letter is refused at the door and leaves no trace but this line.
        if !m.isFromMe, refuses(chat) {
            MontanaP2PTrace.markFolded("rx_blocked", "peer=\(String(chat.prefix(10)))", window: 60, key: chat)
            return false
        }
        // 15.7 — ANY WORD OF THE PEER IS PROOF OF PRESENCE: receipts, presence, drafts, addresses,
        // call signals — each is authenticated by the pipe, and the stamp used to read only letters
        // and the departure of the «online» word (measured 05.09: a nine-minute call showed «last
        // seen 3 s ago» at its start and never moved). Service words are live and stamp NOW; a
        // letter keeps its own time below (a box may hand it over hours later).
        // The word's OWN moment is the stamp (11.09): a word swept from the node hours later says
        // when the peer was there, not when this phone read it.
        // A presence word's own moment outranks the carrier's (15.09): the lane and the node's
        // last-word keep no moment, and a replayed «here» used to light «online».
        // The word's OWN moment, when it says one: the ladder orders by it alone (24.09). A peer's «T» is read on the peer's
        // clock (peerClockMoment); the draft word's «n» is the node's already.
        let saidAt = Self.presenceMoment(m.text).map { m.isFromMe || m.text.hasPrefix(draftSignalMark) ? $0 : peerClockMoment(chat, said: $0) }
        let wordAt = saidAt ?? (m.createdAt > 0 ? m.createdAt : Date().timeIntervalSince1970)
        let fresh = (saidAt != nil ? MontanaWakePush.nodeNow() : Date().timeIntervalSince1970) - wordAt <= Self.presenceLife   // the word's clock
        // EVERY BRANCH BEFORE THE DOORS NAMES ITS STEP (the critic 24.09): the slow landings of T1 and T3 stood in these
        // early branches, and the landing's line named nothing inside them (MontanaMainProbe.step, parts of «rx:…»).
        // Only the person's own words stamp their presence here (machineWord, 24.09); a letter stamps by its own time below.
        if !m.isFromMe, !MTGroup.isKey(chat), !Self.machineWord(m.text), isControlMarker(m.text) || m.text.hasPrefix(draftSignalMark) {
            MontanaMainProbe.step("seen") { noteSeen(chat, at: wordAt, by: MontanaNotify.kind(for: m.text)) }
        }
        // hidden «read» receipt — color our messages with blue ✓✓
        if m.text.hasPrefix(readReceiptMark) {
            if !m.isFromMe { MontanaMainProbe.step("read") { markMyMessagesRead(chat, upToMs: Int64(String(m.text.dropFirst(readReceiptMark.count)))) } }
            return false
        }
        // hidden «delivered» receipt — two gray ✓✓
        if m.text.hasPrefix(deliveryReceiptMark) {
            if !m.isFromMe { MontanaMainProbe.step("delivered") { markDelivered(chat, mid: String(m.text.dropFirst(deliveryReceiptMark.count))) } }
            return false
        }
        // THE TOMBSTONE COMES FIRST AMONG CONTENT. What is deleted «for everyone» resurrects
        // by NO repeat delivery (the extension box, the live channel, a node retry) and is
        // not receipted: the check used to stand AFTER the voice and media branches — a text
        // letter with a tombstone managed to send a receipt, and deleted media reassembled whole.
        if let sid = m.msgId, deletedMids.contains(sid) {
            MontanaP2PTrace.mark("rx_tombstone", "sid=\(String(sid.prefix(16))) — deleted for good, not resurrecting")
            // THE GRAVE ANSWERS (21.09, the critic): a buried letter is terminal on this side, and the
            // sender is told so by the one receipt door — a tombstone that kept silent left the sender
            // knocking for the letter's whole seven-day term (T1: one text resent 735 times with a
            // forced bell, the receiver woken by every knock, «retry» standing on the bubble for days).
            MontanaMainProbe.step("grave") { sendDeliveryReceipt(chat, msgId: m.msgId, isFromMe: m.isFromMe, text: m.text, buried: true) }
            return false
        }
        // A RECEIPT = «THE LETTER IS IN THE CHAT», not «the letter arrived». It used to leave
        // BEFORE the handlers, on the mere fact of the envelope's arrival — and that was the
        // very lie: a big video's manifest rides as its own parcel, the envelope arrived, the
        // receipt left, the parcel never opened, and the sender saw «delivered» on what the
        // receiver does not have at all (precedent 20.08). Media and voice are receipted by
        // THEIR OWN handlers — the moment the bubble appears. The rest of the durable kinds
        // land in the chat right here and are receipted right here.
        // THE MIRROR LAW ON RECEIPTS: a delivery receipt certifies exactly one thing —
        // «this row stands in my chat». Control letters never become rows, so receipting
        // them by envelope mid stamped ✓✓ onto whatever row shared the name (precedent
        // 24.08: a tombstone under a dead video's name). The funeral is the one exception:
        // its receipt settles the sender's queue and buries the dying pipe.
        // Row-landing exceptions: stickers ARE rows (big-glyph bubbles) despite the marker;
        // the funeral's receipt settles the sender's queue and buries the dying pipe.
        // THE RECEIPT LEAVES AFTER THE ROW IS ON DISK (16.09): it stands at the bottom of this
        // function, behind the journal write. Only the funeral's receipt stays here — it settles
        // the sender's queue for a word that never becomes a row.
        if m.text.hasPrefix(convDelMark) {
            sendDeliveryReceipt(chat, msgId: m.msgId, isFromMe: m.isFromMe, text: m.text)
        }
        // incoming voice message (audio inside the message) — restore the file and display
        if m.text.hasPrefix(voiceMark) {
            reconstructVoice(chat, body: String(m.text.dropFirst(voiceMark.count)),
                             isFromMe: m.isFromMe, time: m.time, msgId: m.msgId, senderRef: m.senderRef,
                             transport: m.transport)
            return true
        }
        // incoming media (photo/video/document inside the message) — restore the file and display
        if m.text.hasPrefix(mediaMark) {
            let mbody = String(m.text.dropFirst(mediaMark.count))
            // The big-manifest reference (mref) is unwrapped by reconstructMedia itself — one
            // road for reception and retry, with an intent and a trace on failure.
            reconstructMedia(chat, body: mbody,
                             isFromMe: m.isFromMe, time: m.time, msgId: m.msgId, senderRef: m.senderRef,
                             transport: m.transport)
            return true
        }
        // peer wiped the whole conversation for everyone.
        if m.text.hasPrefix(convDelMark) {
            if !m.isFromMe {
                removeConversationLocally(chat)   // erased at both — so here too: the feed, the disk, the list row
                // The pipe goes to the dying: the tombstone's receipt will still leave by its
                // secret, and the next launch finishes it off (dying with no tombstone queued).
                MTPipeBook.markDying(chat)
                MontanaLog.event("CONVDEL ← \(chat.prefix(10)) wiped by peer")
            }
            return false
        }
        // peer's call signal over the mesh (offer/answer/ice/end) — dispatch to MontanaCall, not a message.
        if m.text.hasPrefix(draftSignalMark) {
            if !m.isFromMe {
                var word: (active: Bool, reply: Bool)?
                MontanaMainProbe.step("live-draft") { word = E2E.shared.handleMeshDraft(from: chat, payload: String(m.text.dropFirst(draftSignalMark.count))) }
                // Only an ACTIVE draft proves presence (peerTyping refreshes it inside). The
                // exit checkpoint follows the farewell — presence stood here unconditionally, and
                // it relit the word 54ms after the farewell killed it (measured 26.08 22:20:30.748
                // off / .802 on): «in chat» then survived on the 45s TTL alone, which read as a
                // half-minute lag. The checkpoint is NOT always empty (24.09): it carries the words
                // standing in the field, and handleMeshDraft answers «active» for a keystroke alone —
                // a checkpoint (ck), a link, a bio or an ask lights neither «typing…» nor «in chat».
                if let d = word { if d.active { peerTyping(chat) } else { typingChats.remove(chat) } }
            }
            return false
        }
        // Live-chat presence beacon — never a message, only the word under the name.
        if m.text.hasPrefix(watchMark) {
            let payload = m.text.dropFirst(watchMark.count)
            let open = payload.hasPrefix("1")
            if !m.isFromMe { MontanaMainProbe.step("watch") {
                MontanaPresencePrivacy.notePeerHides(chat, payload.dropFirst(1).contains("h"), at: wordAt)
                if payload.dropFirst(1).contains("f") { E2E.shared.resendProfileOnReconnect(to: chat) }
                E2E.heardCapable(from: chat, payload: payload)   // what its build reads, from every word, late ones too (25.09)
                E2E.heardCoins(from: chat, payload: payload, at: wordAt)   // the balance the word tells (04.10)
                if fresh { E2E.shared.heardHeld(from: chat, payload: payload) }   // what of mine their screen holds (20.09)
                heardHeldLetters(chat, payload: payload)   // which of my letters they hold whole (23.09)
                if let at = payload.firstIndex(of: "@") {   // the door they ask — my words for them go there
                    MontanaWakePush.notePeerDoor(chat, host: String(payload[payload.index(after: at)...]))
                }
                // No line per received beat: presence_set (on/off/ttl-off) is the change, presence_capable the proof.
                E2E.notePresenceCapable(chat)   // [P2P-COMPAT] they spoke presence — the mesh road opens
                // An old word (swept from the node, replayed by the lane) is a stamp, never a live «in chat» — and never a
                // live «left» either (24.09): the ladder moves only by a word said now and never back (liveWordMoves).
                if liveWordMoves(chat, said: saidAt, row: .chat, arrival: open, life: Self.presenceLife) {
                    peerWatching(chat, open: open, said: saidAt)
                    if open { E2E.shared.presenceEcho(to: chat) }   // answer with my state — their entry reads instantly
                    else { typingChats.remove(chat) }               // left the chat = stopped typing, same instant
                }
            } }
            return false
        }
        // App-level presence beacon: the peer is in the app — this chat or another screen.
        if m.text.hasPrefix(appMark) {
            let payload = m.text.dropFirst(appMark.count)
            let open = payload.hasPrefix("1")
            if !m.isFromMe { MontanaMainProbe.step("presence") {
                MontanaPresencePrivacy.notePeerHides(chat, payload.dropFirst(1).contains("h"), at: wordAt)
                if payload.dropFirst(1).contains("f") { E2E.shared.resendProfileOnReconnect(to: chat) }
                E2E.heardCapable(from: chat, payload: payload)   // what its build reads, from every word, late ones too (25.09)
                E2E.heardCoins(from: chat, payload: payload, at: wordAt)   // the balance the word tells (04.10)
                if fresh { E2E.shared.heardHeld(from: chat, payload: payload) }   // what of mine their screen holds (20.09)
                heardHeldLetters(chat, payload: payload)   // which of my letters they hold whole (23.09)
                E2E.notePresenceCapable(chat)
                // «B» RIGHT AFTER THE DIGIT (24.09): the block word is «0B» and its moment, in every build that ever said it
                // (5f3db75d, 226f1783); a «B» anywhere in the tail read as «gone» the day a tag carried one.
                if payload.dropFirst(1).hasPrefix("B") {
                    // «GONE» (the author's word 15.09): the person took their face back and stands
                    // «seen long ago» — a state with its moment, undone only by a later word of theirs.
                    // GONE IS A DEPARTURE IN BOTH ROWS, AND A STATE HAS NO LIFE (24.09, the second critic's pass): the block
                    // word left before the rows, so a «1» said before it and landing after it lit «online» over «seen long
                    // ago» for a life, and a block said before a «here» that had already landed stood over a person who
                    // had come back. The block is ordered like every word, and is never too old to count.
                    if liveWordMoves(chat, said: saidAt, row: .app, arrival: false, life: .infinity) { peerGone(chat, at: wordAt) }
                    return
                }
                peerBack(chat, at: wordAt)   // a later presence word of theirs: they are here again
                // A word said now moves «online», never back (liveWordMoves, 24.09); every word stamps its moment above.
                if liveWordMoves(chat, said: saidAt, row: .app, arrival: open, life: Self.presenceLife) { peerAppOnline(chat, open: open, said: saidAt) }
            } }
            return false
        }
        // A CALL'S WORD AND A CALL LETTER ARE BURIED UNREAD (the author's word 09.10.2026 16:00 MSK: the wallet holds no calls).
        if m.text.hasPrefix(callSignalMark) || m.text.hasPrefix(ringMark) { return false }
        // The peer sent their external address — punch back AT ONCE and answer with ours if
        // we have not yet: a punch-through lives seconds, waiting for the next occasion is not an option.
        if m.text.hasPrefix(punchEndpointMark) {
            if !m.isFromMe {
                let ep = String(m.text.dropFirst(punchEndpointMark.count)).trimmingCharacters(in: .whitespaces)
                MontanaMainProbe.step("address") { MontanaNATService.shared.peerAnnounced(conv: chat, endpoint: ep) }
            }
            return false
        }
        // The door word of the VPN-nodes feature, removed by the author's word 30.09: an older build may still name its exit;
        // the word is buried unread, never shown.
        if m.text.hasPrefix(exitDoorMark) { return false }
        // The peer sent their wake handle for the notification server — kept at the pipe, never shown.
        if m.text.hasPrefix(wakeHandleMark) {
            if !m.isFromMe { MontanaMainProbe.step("wake-handle") { MontanaWakePush.rememberPeer(chat, handle: String(m.text.dropFirst(wakeHandleMark.count))) } }
            return false
        }
        // Anything incoming from the peer = the pipe works: hand them our handle by the same road (once per session).
        // EACH OF THE DOORS IS NAMED (23.09: «doors» held the main thread 108 ms in the median on T1 at every letter of
        // 1912, up to 246, and named nothing inside): the wake's registration, the reach, the address, the exit.
        if !m.isFromMe, !MTGroup.isKey(chat) { MontanaMainProbe.step("doors") {   // a group's feed has no pipe and no doors (MTGroup)
            MontanaMainProbe.step("wake") { MontanaWakePush.noteIncoming(from: chat) }
            // The pipe is alive — the right moment to name our external address: a
            // punch-through lives minutes, and it must be named while the peer is near, not asleep.
            var near = true
            MontanaMainProbe.step("reach") { near = MontanaP2PNode.shared.canReach(chat) }
            if !near { MontanaMainProbe.step("nat") { MontanaNATService.shared.announce(to: chat) } }
        } }
        // THE SET'S OWN WORD (22.09): a passport behind a sticker, a request for a set, a page of
        // one. Service by construction -- it never becomes a row, never rings, and a build that
        // does not know the token buries it unread ([P2P-COMPAT]).
        if m.text.hasPrefix(MontanaStickerWire.mark) {
            if !m.isFromMe { MontanaStickerWire.handle(m.text, from: chat, chat: chat, store: self) }
            return false
        }
        // THE WALL'S WORD (the author's word 24.09): a post for my wall, a visitor's mark, a page of a wall I asked
        // for. Service by construction; a build that does not know the token buries it unread ([P2P-COMPAT]).
        if MTBoard.handle(m.text, from: chat, isFromMe: m.isFromMe) { return false }
        // A GROUP'S WORD (the author's words 05.10.2026, MTGroup): an invitation or a letter of a group its owner carries over the
        // pipes. It lands in the group's own feed, never as a row of the pipe; a build that does not know the token buries it unread.
        if MTGroup.handle(m.text, from: chat, isFromMe: m.isFromMe, sid: m.msgId, store: self) { return false }
        // THE VPN WALL'S WORD («VW:») left with the VPN for its own app (the author's word 08.10.2026): this build does not know the
        // token, and the vocabulary gate below buries it unread ([P2P-COMPAT], mtUnknownServiceWord).
        // A LETTER CARRYING A SET'S LINK NAMES ITS GIVER (22.09): the link holds no address, so the
        // hand that passed it is remembered here -- that is whom the set is asked of.
        if !isControlMarker(m.text), m.text.contains("montana://pack/") {
            MontanaStickerWire.noteLink(in: m.text, peer: m.isFromMe ? MontanaP2PNode.myRef() : chat)
        }
        // peer's self-chosen display name over the mesh — same pipeline as the avatar (SSOT: setPeerName).
        if m.text.hasPrefix(nameMark) {
            if !m.isFromMe {
                let nm = String(m.text.dropFirst(nameMark.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !nm.isEmpty, nm.count <= 64, stateIsCurrent("name:" + chat, at: wordAt) {
                    setPeerName(ref: chat, name: nm, at: wordAt, source: "word")   // reciprocity lives inside (SSOT)
                    MontanaLog.event("NAME ← \(chat.prefix(10)) received (mesh)")
                }
                // The screen shows the name — the sender learns it by the receipt, the one writer
                // of their «announced» mark (15.21). [P2P-COMPAT]: a receipt is a word every build reads.
                sendDeliveryReceipt(chat, msgId: m.msgId, isFromMe: m.isFromMe, text: m.text)
            }
            return false
        }
        // THE PEER'S BIO AND LINK AS STATE (24.09) — the same road as the name: applied if it is the latest word, and
        // receipted either way, because the receipt is the sender's one proof that my screen holds their words.
        if m.text.hasPrefix(aboutMark) {
            if !m.isFromMe {
                if let d = String(m.text.dropFirst(aboutMark.count)).data(using: .utf8),
                   let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                    let at = (o["at"] as? Double) ?? wordAt
                    MTPeerAbout.note(chat, bio: (o["b"] as? String) ?? "", link: (o["l"] as? String) ?? "", at: at)
                    if let coins = o["c"] as? Int { MTCoinBoard.shared.note(chat, coins: coins, at: at) }   // the pair's balance (03.10)
                    if let own = o["o"] as? String { MTOwnWords.heard(own, from: chat) }   // the pair holds my words: no coin goes to it (06.10)
                }
                E2E.noteAboutCapable(chat)   // a build that speaks the word reads it
                sendDeliveryReceipt(chat, msgId: m.msgId, isFromMe: m.isFromMe, text: m.text)
            }
            return false
        }
        // THE PEER'S PAGE GROUND AS STATE (25.09) — the same road as the bio: applied if it is the latest word, and
        // receipted either way; the receipt is the sender's one proof that my screen holds their ground.
        if m.text.hasPrefix(groundMark) {
            if !m.isFromMe {
                if let d = String(m.text.dropFirst(groundMark.count)).data(using: .utf8),
                   let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                    MTPageGround.note(chat, g: (o["g"] as? String) ?? "", at: (o["at"] as? Double) ?? wordAt)
                }
                E2E.noteGroundCapable(chat)   // a build that speaks the word reads it
                sendDeliveryReceipt(chat, msgId: m.msgId, isFromMe: m.isFromMe, text: m.text)
            }
            return false
        }
        // peer's avatar over ANY transport — reconstructed as profile data, not as a message
        if m.text.hasPrefix(avatarMark) {
            if m.isFromMe || stateIsCurrent("face:" + chat, at: wordAt) {
                applyIncomingAvatar(chat, payload: String(m.text.dropFirst(avatarMark.count)), fromMe: m.isFromMe)
            }
            if !m.isFromMe { sendDeliveryReceipt(chat, msgId: m.msgId, isFromMe: m.isFromMe, text: m.text) }   // the face is on screen — receipted (15.21)
            return false
        }
        // The receiver says: your letter's cargo is no longer on the node. This is KNOWLEDGE
        // (the node answered, not stayed silent), so the letter honestly turns red with a
        // retry, and the records of its chunks are removed — otherwise the sender forever
        // sends a letter that has no cargo.
        if m.text.hasPrefix(cargoLostMark) {
            if !m.isFromMe {
                let lost = String(m.text.dropFirst(cargoLostMark.count))
                // The report may be STALE — about an old incarnation of the letter, while a
                // fresh resend already rides under the same name. It triggers an immediate
                // cargo verification; the node's store passes the sentence (red comes from
                // cargoGone only when the cargo is truly absent).
                MontanaP2PTrace.mark("cargo_lost", mid: lost, "receiver reported: cargo gone — verifying against the node now")
                MontanaDeliveryEngine.shared.verifyCargoNow(lost, chat: chat)
            }
            return false
        }
        // A VOICE OR A ROUND NOTE OF MINE WAS PLAYED THERE (25.09): the correspondent's own «played» — the only road to its
        // «Listened» or «Viewed»; the word itself proves their build says it.
        if m.text.hasPrefix(playedMark) {
            if !m.isFromMe {
                let played = String(m.text.dropFirst(playedMark.count))
                E2E.notePlayedCapable(chat)
                if let i = messages[chat]?.firstIndex(where: { $0.isFromMe && $0.mid == played }), messages[chat]?[i].heard == false {
                    messages[chat]?[i].heard = true
                    MontanaP2PTrace.mark("played_rx", mid: played, "their playing is here")
                }
            }
            return false
        }
        // «delete for everyone» from the peer — wipe the message by msgId
        if m.text.hasPrefix(deleteMark) {
            if !m.isFromMe {
                let sid = String(m.text.dropFirst(deleteMark.count))
                deleteEverywhere(chat: chat, msgId: sid)
                MontanaLog.event("DELETE ← \(sid.prefix(12)) removed by peer signal")
            }
            return false
        }
        // peer's reaction — apply to the right message, don't show it as a message
        if m.text.hasPrefix(reactionMark) {
            applyReactionFromControl(chat, body: String(m.text.dropFirst(reactionMark.count)), at: m.createdAt, mine: m.isFromMe)
            return false
        }
        // the peer changed the words of a letter already sent — the row's words change, never a new row
        if m.text.hasPrefix(editMark) {
            if !m.isFromMe { applyEditFromPeer(chat, body: String(m.text.dropFirst(editMark.count))) }
            return false
        }
        // the peer pinned (or unpinned) a letter for both — the same letter is pinned here, never a row
        if m.text.hasPrefix(pinMark) {
            if !m.isFromMe { applyPinFromControl(chat, body: String(m.text.dropFirst(pinMark.count))) }
            return false
        }
        // peer is typing — show the indicator, don't add it as a message
        if m.text.hasPrefix(typingMark) {
            // A typing word the lane replays is not typing now, nor one from before a departure (24.09): its own moment
            // decides, by the ladder's one rule; a word without one (every build before this one) is believed as before.
            if !m.isFromMe, liveWordMoves(chat, said: saidAt, row: .chat, arrival: true, life: Self.typingWordLife) { peerTyping(chat) }
            return false
        }
        // ONE PERSON, ONE CONVERSATION (24.09, MTSamePair): the scanner's question over a pipe just born from my card —
        // answered and folded when I share an older pipe with them, answered again when the fold is already made — and the
        // owner's answer to my own question.
        if m.text.hasPrefix(sameAskMark) {
            if !m.isFromMe { MontanaMainProbe.step("same") {
                sendDeliveryReceipt(chat, msgId: m.msgId, isFromMe: m.isFromMe, text: m.text)
                let q = MTSamePair.shared(ask: String(m.text.dropFirst(sameAskMark.count)), new: chat)
                MTSamePair.answer(q, new: chat)
                if let q { joinSamePerson(chat, q) }
            } }
            return false
        }
        if m.text.hasPrefix(sameYesMark) {
            if !m.isFromMe { MontanaMainProbe.step("same") {
                sendDeliveryReceipt(chat, msgId: m.msgId, isFromMe: m.isFromMe, text: m.text)
                MTSamePair.settle(chat)
                if let q = MTSamePair.proven(answer: String(m.text.dropFirst(sameYesMark.count)), new: chat) {
                    joinSamePerson(chat, q)
                } else {
                    MontanaP2PTrace.mark("same_none", "conv=\(String(chat.prefix(10)))")
                }
            } }
            return false
        }
        if m.text.hasPrefix(pipeClosedMark) {
            if !m.isFromMe { MontanaMainProbe.step("closed") {
                sendDeliveryReceipt(chat, msgId: m.msgId, isFromMe: m.isFromMe, text: m.text)
                peerClosedPipe(chat)
            } }
            return false
        }
        // [P2P-COMPAT] a service word THIS build does not know is buried unread with a trace:
        // a newer build's vocabulary must never render as a message here.
        // THE KEEPING OF A COPY (MTKeeping, 08.10): a question, a yes, a part, a keeper's «held», a release -- answered there,
        // receipted here, never a row.
        if m.text.hasPrefix(keepMark) {
            if !m.isFromMe { MontanaMainProbe.step("keep") {
                sendDeliveryReceipt(chat, msgId: m.msgId, isFromMe: m.isFromMe, text: m.text)
                MTKeeping.shared.heard(m.text, from: chat)
            } }
            return false
        }
        if mtUnknownServiceWord(m.text) {
            MontanaP2PTrace.mark("unknown_mark_buried", "chat=\(String(chat.prefix(10))) len=\(m.text.count)")
            return false
        }
        if deletedChats.contains(chat) { deletedChats.remove(chat) }   // a new message resurrects a deleted dialog
        // A LETTER ENDS THE DRAFT THAT BECAME IT — here, at the letter, not on a separate word
        // that must also arrive. The words are on screen as a letter now; a draft of them is a
        // ghost. The sender does send a clear, and it is welcome — but a state that must end on
        // an event is ended BY the event, or a lost word leaves the ghost standing for ever.
        typingChats.remove(chat)   // a real message arrived — clear «typing…»
        if !m.isFromMe { MontanaMainProbe.step("draft") {
            LiveDraftState.shared.applyLive(chat, "")
            // THE LETTER CLOSES THE WHOLE GENERATION OF THE DRAFT, not just the copy on screen.
            // Every word of that draft was said BEFORE the letter, so none of them may be applied
            // any more — not the one still on the road, not the one a second road repeats a
            // moment later. A ghost of words that already became a letter cannot be born.
            // THE LETTER'S LANDING IS STAMPED BY THE NODE'S CLOCK, NOT BY MY WORD COUNTER (24.09, the author's word): the
            // counter never steps back (P-95), and one that ran ahead before the node's first answer — a phone whose time
            // was changed between two lives, a first install on a clock set ahead — stamped every letter in the future,
            // and every live draft of theirs after each letter was refused for as long as the clock had been wrong. The
            // stamp is «now» by the node's clock, and never below a moment of theirs already held.
            LiveDraftState.shared.saidAt[chat] = max(LiveDraftState.shared.saidAt[chat] ?? 0, Int(MontanaWakePush.nodeNow() * 1000))
            var pd = ChatStore.peerDraftsAll(); pd[chat] = nil; ChatStore.savePeerDrafts(pd)
        } }
        if !m.isFromMe, !MTGroup.isKey(chat) { MontanaMainProbe.step("seen") { noteSeen(chat, at: m.createdAt > 0 ? m.createdAt : Date().timeIntervalSince1970, by: "letter") } }   // 10-C.1
        // THE LETTER LANDS ALREADY CARRYING ITS FINAL WORDS: an edit that outran its letter was held
        // and is applied here, before the row exists — so the feed, the list and the sealed archive
        // all take the same text, and no screen ever shows words their author has already replaced.
        var row = m
        if let sid = row.msgId, let tx = takePendingEdit(chat, sid: sid),
           !row.isFromMe, row.imageFile == nil, row.videoFile == nil,
           row.audioFile == nil, row.docFile == nil, !isControlMarker(row.text) {
            row.text = tx; row.edited = true
            MontanaP2PTrace.mark("edit_rx", "applied at landing mid=\(String(sid.dropFirst(4).prefix(8)))")
        }
        // A STEP OF A CHESS GAME LANDS READ (29.09): the board is its reader; the chat's count, its order and the hand
        // mark are not moved by it.
        let step = row.isChessStep
        if step, !row.isFromMe { row.isRead = true }
        var placed = row
        MontanaMainProbe.step("place") { placed = placeRow(chat, row) }
        // ...AND ITS LANDING STARTS THE CLOCK OF THE ONE WHO RECEIVED IT (29.09): the rung «read» is written through the
        // ladder's one door, and its moment is the moment this phone could begin to think (MTChessAnchor) -- a letter on the
        // road is nobody's thinking.
        if step, !row.isFromMe, let i = messages[chat]?.lastIndex(where: { $0.mid == placed.mid }), advance(chat, i, to: .read) {
            placed = messages[chat]?[i] ?? placed
        }
        // A COIN LETTER IS CREDITED ON ITS LANDING (the author's word 03.10 13:52), once, by its wire name -- the same name on
        // both phones, so a letter the lane, the box and the extension each bring is one credit (MTCoinLedger.receive). The credit
        // is on disk before the row (04.10 23:57): a process ended between the two leaves a credit and no row, and the sender's
        // repeat lands the row while the name keeps the credit one; the other order lost 123 000 coins on the iPhone 15 Pro Max.
        if !placed.isFromMe, !MTGroup.isKey(chat), let coin = placed.coinLetter, !placed.mid.isEmpty,
           MTCoinSend.credits(coin, mid: placed.mid, from: chat) {   // a letter that names itself, never a copy (06.10)
            MTCoinBook.ledger.receive(coin.c, from: chat, ref: placed.mid, on: nil)
        }
        // A CHOSEN PERSON'S LETTER IS PAID BY ITSELF (MTAutoReact, the author's word 06.10.2026 17:3x MSK) -- a turn after its landing,
        // so the letter stands before the reaction that rides on it.
        if !placed.isFromMe, !MTGroup.isKey(chat), MTAutoReact.rule(chat) != nil {
            let row = placed
            Task { @MainActor in MTAutoReact.landed(row, in: chat, store: self) }
        }
        // A BUBBLE OF MINE PAYS ITS READER (the author's words 05.10.2026 01:21-01:31 MSK, MTCoinSend.pay) -- a turn after its landing,
        // so its own letter is queued before the coin that rides on it.
        if placed.isFromMe { let row = placed; Task { @MainActor in MTCoinSend.pay(row, in: chat, store: self) } }
        // THE ROW IS ON DISK BEFORE ANYONE IS TOLD IT EXISTS (the journal, 16.09): the receipt, the
        // list record and the emptying of the landing box all stand behind this line.
        MontanaMainProbe.step("journal") { _ = MTRowJournal.put(chat, placed) }
        MontanaMainProbe.step("archive") { archiveRow(chat, placed) }
        // A CHESS LETTER SETTLES ITS GAME'S COINS (the author's word 03.10 22:35, MTChessCoins): mine and theirs alike, each once.
        if placed.chessLetter != nil { MTChessCoins.settle(chat: chat, rows: messages[chat] ?? []) }
        // A receipt certifies a ROW (P-41): the funeral and stickers are the named exceptions.
        if !isControlMarker(m.text) || m.text.hasPrefix(convDelMark) || m.text.hasPrefix(stickerMark) {
            MontanaMainProbe.step("receipt") { _ = sendDeliveryReceipt(chat, msgId: m.msgId, isFromMe: m.isFromMe, text: m.text) }
        }
        if !step { MontanaMainProbe.step("order") { bump(chat) } }   // a chat with a fresh message moves to the top of the list
        if !m.isFromMe && chat != openConv && !step { handMarkYields(chat) }   // the letter itself is the unread one (23.09)
        if !m.isFromMe { MontanaMainProbe.step("badge") { recalcBadge() } }   // both a NON-first message of the chat, and NSE rollback in an open chat
        MontanaMainProbe.step("list") { noteListState(chat, last: messages[chat]?.last) }   // the list record follows the landing (stage 9) — placeRow has just put the row in order, so the end is the newest (P-44)
        // The banner is NOT created here: MontanaNotify raises it from the single inbound funnel
        // (willPresent decides show/hide based on the open chat).
        return true
    }

    // peer has read — my sent messages become «read» (gold ✓✓)
    // peer has received — my sent ones become «delivered» (two gray ✓✓)
    @MainActor
    func markDelivered(_ chat: String, mid: String, by: String = "receipt") {
        MontanaDeliveryEngine.shared.confirmDelivered(mid: mid, by: by)   // receipt — the ONLY dequeue condition
        if MTGroup.shared.copyDelivered(mid, store: self) { return }   // a group's copy witnesses the group's row, never a row of the pipe (MTGroup)
        guard let i = messages[chat]?.firstIndex(where: { $0.isFromMe && $0.msgId == "mid:\(mid)" }) else {
            let again = { MainActor.assumeIsolated { MTCoinSend.arrived(mid, from: chat) } }   // a coin letter whose row is gone: its coins that came back are taken again (05.10)
            if Thread.isMainThread { again() } else { DispatchQueue.main.async(execute: again) }
            noteOrphanDelivered(mid, keep: true)
            MontanaP2PTrace.mark("receipt_orphan", mid: mid, "no row yet — kept for its birth")
            return
        }
        let st = messages[chat]?[i].deliveryStatus
        // .failed is accepted too: the red mark is set by term while the letter keeps riding —
        // a receipt arriving later must put it out, or honesty becomes a new lie.
        if st == .sent || st == .sending || st == .failed {
            advance(chat, i, to: .delivered)
            MontanaLog.event("DELIVERED mid=\(mid.prefix(8)) — receipt received, path complete")
            // The read word may have outrun this receipt: the peer named this letter as read
            // before its receipt landed. The mark remembers; the letter catches up here.
            if let u = Self.peerReadUpTo(chat), let b = ChatStore.birthMs(fromMid: mid), Int64(b * 1000) <= u,
               advance(chat, i, to: .read) {
                MontanaP2PTrace.mark("read_late", mid: mid, "receipt after the read word — raised by the mark")
            }
        }
    }

    /// THE PEER'S WORD NAMES MY LETTERS IT HOLDS WHOLE (23.09) — the receipt's second speaker, riding
    /// every presence word the peer already says (HeldLetters). A named letter is raised through the one
    /// delivery door, whether its row stands on the screen or it still waits in the queue. The word's
    /// age does not matter: a letter once held whole is delivered for good.
    @MainActor
    func heardHeldLetters(_ chat: String, payload: Substring) {
        let named = MontanaDeliveryEngine.HeldLetters.named(in: payload)
        guard !named.isEmpty else { return }
        var mids = Set<String>()
        for row in messages[chat] ?? [] where row.isFromMe {
            let st = row.deliveryStatus
            guard st == .sending || st == .sent || st == .failed, let sid = row.msgId, sid.hasPrefix("mid:") else { continue }
            let mid = String(sid.dropFirst(4))
            if let k = MontanaDeliveryEngine.HeldLetters.key(mid), named.contains(k) { mids.insert(mid) }
        }
        for mid in MontanaDeliveryEngine.shared.queuedMids(to: chat, named: named) { mids.insert(mid) }
        guard !mids.isEmpty else { return }
        for mid in mids { markDelivered(chat, mid: mid, by: "word") }
        MontanaP2PTrace.mark("held_rx", "from=\(String(chat.prefix(10))) named=\(named.count) raised=\(mids.count)")
    }

    @MainActor
    func markMyMessagesRead(_ chat: String, upToMs: Int64? = nil) {
        guard let list = messages[chat] else { return }
        if let u = upToMs { Self.notePeerRead(chat, upToMs: u) }
        // ONLY the delivered becomes read — the door (advance) lets nothing else pass; and only
        // what the word covers: a letter born after the peer's newest is not read by it. A bare
        // word (an older build) covers everything delivered, as it always did.
        var raised = 0
        for i in list.indices where list[i].isFromMe {
            if let u = upToMs, let b = list[i].msgId.flatMap(ChatStore.birthMs(fromMid:)), Int64(b * 1000) > u { continue }
            if advance(chat, i, to: .read) { raised += 1 }
        }
        MontanaP2PTrace.mark("read_rx", "from=\(String(chat.prefix(10))) upto=\(upToMs.map(MontanaP2PTrace.shortMs) ?? "-") raised=\(raised)")
    }

    // restore an incoming voice message: decode base64 into a .m4a file and add the message
    func reconstructVoice(_ pipe: String, body: String, isFromMe: Bool, time: String,
                          msgId: String?, senderRef: String?, transport: String? = nil) {
        let chat = MTSamePair.root(pipe)   // a late road over a folded pipe lands in the conversation (24.09)
        guard let d = body.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let b64 = obj["a"] as? String, let audio = Data(base64Encoded: b64),
              let name = saveToDocs(audio, ext: "m4a") else { return }
        if let sid = msgId, (messages[chat] ?? []).contains(where: { $0.msgId == sid }) { return }
        // The file already lies ready in the correspondence store (saveToDocs) — no second copy.
        let dur = (obj["d"] as? Double) ?? 0
        let row = Message(text: "", isFromMe: isFromMe, time: time.isEmpty ? nowHHMM() : time,
                          audioFile: name, audioDuration: dur, deliveryStatus: .delivered,
                          msgId: msgId, senderRef: senderRef, transport: transport)
        placeRow(chat, row)
        MTRowJournal.put(chat, row)   // on disk before the receipt below (16.09)
        archiveRow(chat, row)
        bump(chat)
        // The voice bubble exists — now and only now may the sender see «delivered».
        sendDeliveryReceipt(chat, msgId: msgId, isFromMe: isFromMe, text: voiceMark)
    }

    // restore incoming media: decode base64 into a file and add the message
    // ── DOWNLOAD-RESUME QUEUE: a manifest whose chunks didn't finish downloading is NOT discarded —
    // it is kept and retried when the app returns/a chat is opened (media arrives late, doesn't get lost).
    private var pendingMediaJSON: String {
        get { MontanaLocalVault.getString("pendingMediaJSON") ?? "[]" }
        set { MontanaLocalVault.setString("pendingMediaJSON", newValue) }
    }
    /// The intent to receive a file lives on disk, not in a live task. The task dies with the
    /// app going background and the channel breaking: measured — 341 MB, 651 chunks, 8
    /// downloaded, then silence; five consecutive send attempts started from zero and died
    /// the same way. A record written BEFORE reception starts makes the interruption
    /// harmless: on the next opening reception resumes from the chunk where it stopped — the
    /// already-downloaded ones lie in the store and are not pulled again.
    /// The reception intent's key: the letter id, and when there is none — the manifest's own
    /// fingerprint. An empty key broke all four dedups at once: an intent with sid="" did
    /// not fold, was not removed, downloaded into a fresh random file and added a NEW bubble
    /// on every activation — measured: nine bubbles of one photo across nine openings.
    private func mediaPendingKey(_ msgId: String?, body: String) -> String {
        if let sid = msgId, !sid.isEmpty { return sid }
        let h = SHA256.hash(data: Data(body.utf8)).map { String(format: "%02x", $0) }.joined()
        return "pm-" + String(h.prefix(24))
    }

    /// THE VERDICT «THE CARGO IS GONE» LIVES ON DISK, NOT IN A RUN (the author's word 22.09).
    /// Measured on T1 the same evening: a hundred and seventy-seven times every door answered «no
    /// cargo» for one letter, and the download was started NINETY-FOUR times over four hours for
    /// that same letter. The refusal itself was already written and correct — the road hears
    /// «lost», keeps the row, tells the sender once — but the knowledge of it was a Set in memory:
    /// every launch and every return to the foreground began the four hours again, and a person's
    /// cellular paid for it.
    ///
    /// The record of the receiving intent is the one place that already survives a launch, so the
    /// verdict goes there beside it. Three doors, and only three: the automatic road REFUSES while
    /// the mark stands; a HAND lifts it (retryOneMedia); and a fresh manifest — the sender's
    /// resend — lifts it by itself, where the try count is already reset ([C-1]).
    func markPendingCargoGone(_ msgId: String?, told: Bool) {
        guard let sid = msgId, !sid.isEmpty else { return }
        var arr = (try? JSONSerialization.jsonObject(with: Data(pendingMediaJSON.utf8)) as? [[String: String]]) ?? []
        guard let i = arr.firstIndex(where: { $0["sid"] == sid }) else { return }
        arr[i]["gone"] = "1"
        if told { arr[i]["told"] = "1" }
        if let d = try? JSONSerialization.data(withJSONObject: arr) {
            pendingMediaJSON = String(data: d, encoding: .utf8) ?? "[]"
        }
    }

    /// Whether this letter already heard its verdict, and whether its sender was already told.
    func pendingCargoState(_ sid: String) -> (gone: Bool, told: Bool) {
        guard !sid.isEmpty,
              let arr = try? JSONSerialization.jsonObject(with: Data(pendingMediaJSON.utf8)) as? [[String: String]],
              let r = arr.first(where: { $0["sid"] == sid }) else { return (false, false) }
        return (r["gone"] == "1", r["told"] == "1")
    }

    /// THE HAND LIFTS THE VERDICT, AND ONLY THE HAND ([C-1]): every tap on a letter whose file is
    /// missing enters here, so the mark is lifted in ONE place and the automatic road has nothing
    /// to argue with. Without this the tap would meet its own refusal and do nothing at all.
    ///
    /// No isolation of its own: it stands exactly where retryPendingMedia() stood, in the same
    /// taps, and touches what that one touches — so whatever compiled before compiles now.
    func retryOneMedia(_ msgId: String?) {
        if let sid = msgId, !sid.isEmpty {
            var arr = (try? JSONSerialization.jsonObject(with: Data(pendingMediaJSON.utf8)) as? [[String: String]]) ?? []
            if let i = arr.firstIndex(where: { $0["sid"] == sid }), arr[i]["gone"] == "1" {
                arr[i]["gone"] = nil
                arr[i]["tries"] = "0"
                if let d = try? JSONSerialization.data(withJSONObject: arr) {
                    pendingMediaJSON = String(data: d, encoding: .utf8) ?? "[]"
                }
                MontanaP2PTrace.mark("rx_media_gone", "lifted by hand sid=\(String(sid.prefix(14)))")
            }
        }
        retryPendingMedia()
    }

    func dropPendingMedia(_ msgId: String?) {
        guard let sid = msgId, !sid.isEmpty else { return }
        var arr = (try? JSONSerialization.jsonObject(with: Data(pendingMediaJSON.utf8)) as? [[String: String]]) ?? []
        let before = arr.count
        arr.removeAll { $0["sid"] == sid }
        if arr.count != before, let d = try? JSONSerialization.data(withJSONObject: arr) {
            pendingMediaJSON = String(data: d, encoding: .utf8) ?? "[]"
        }
    }


    func queuePendingMedia(_ chat: String, body: String, isFromMe: Bool, time: String,
                           msgId: String?, senderRef: String?, kind: String? = nil) {
        var arr = (try? JSONSerialization.jsonObject(with: Data(pendingMediaJSON.utf8)) as? [[String: String]]) ?? []
        let key = mediaPendingKey(msgId, body: body)
        if let i = arr.firstIndex(where: { $0["sid"] == key }) {
            // A re-upload: the same letter, a NEW manifest (sealing with a fresh nonce yields
            // new chunk names). The old manifest is dead — keeping it means forever chasing
            // vanished chunks. The try count starts over.
            if arr[i]["body"] != body {
                // A fresh manifest is the sender's resend: the verdict of the old one dies with it.
                arr[i]["body"] = body; arr[i]["tries"] = "0"; arr[i]["gone"] = nil; arr[i]["told"] = nil
                if let d = try? JSONSerialization.data(withJSONObject: arr) {
                    pendingMediaJSON = String(data: d, encoding: .utf8) ?? "[]"
                }
                MontanaP2PTrace.mark("rx_media_manifest", "fresh manifest accepted key=\(String(key.prefix(8)))")
            }
            return
        }
        var row = ["chat": chat, "body": body, "me": isFromMe ? "1" : "0",
                   "time": time, "sid": key, "sender": senderRef ?? ""]
        if let kind { row["kind"] = kind }
        arr.append(row)
        if let d = try? JSONSerialization.data(withJSONObject: arr) { pendingMediaJSON = String(data: d, encoding: .utf8) ?? "[]" }
    }
    // In-flight/failed media reassembly (by msgId): polling every 2s must NOT
    // restart the download of a broken manifest endlessly (an avalanche of network tasks).
    var reconstructInFlight = Set<String>()

    func retryPendingMedia() {
        // Legacy migration: the old avatar notebook (open UserDefaults, the decryption key in
        // plain text) moves into the shared sealed store and is erased for good.
        // The old avatar notebook is buried outright: pending faces are the chunk era's
        // corpses, and the inline road re-announces faces by itself (reciprocity + flags).
        UserDefaults.standard.removeObject(forKey: "pendingPeerAvatars")
        var arr = (try? JSONSerialization.jsonObject(with: Data(pendingMediaJSON.utf8)) as? [[String: String]]) ?? []
        guard !arr.isEmpty else { return }
        // Migrating the accumulated: records without a key get one from the body, duplicates
        // of one key fold into a single record. Without this the old list kept multiplying.
        var seenKeys = Set<String>()
        var squashed: [[String: String]] = []
        for var it in arr {
            let key = mediaPendingKey(it["sid"], body: it["body"] ?? "")
            it["sid"] = key
            if seenKeys.insert(key).inserted { squashed.append(it) }
        }
        if squashed.count != arr.count, let d = try? JSONSerialization.data(withJSONObject: squashed) {
            pendingMediaJSON = String(data: d, encoding: .utf8) ?? "[]"
            MontanaLog.event("[MEDIA] pending squashed: \(arr.count) -> \(squashed.count)")
        }
        arr = squashed
        // The intent list is about «finish after death», not «start anew over the running».
        // It is NO longer cleared here: only the assembled file removes an intent. And a
        // running reception is not restarted: a retry used to clear the «downloading» mark,
        // and one file downloaded in three hands — the first finished assembly erased the
        // chunks under the other two, which stalled for good (measured: three starts of one
        // file in 16 seconds, stuck at 85%).
        NSLog("[MEDIA] retry pending: \(arr.count)")
        // The try count lives in the record itself: the record survived the previous pass —
        // so that pass did not assemble the file. After the third failure the receiver ASKS
        // the sender to re-upload: the node's chunks may have expired or vanished, and the
        // master copy is the sender's. The plea comes at most once in ten minutes; after
        // fifty failures once in six hours, so a dead manifest does not hammer the node forever.
        let now = Date().timeIntervalSince1970
        var changed = false
        for i in arr.indices {
            let key = arr[i]["sid"] ?? ""
            if reconstructInFlight.contains(key) { continue }
            let tries = (Int(arr[i]["tries"] ?? "0") ?? 0) + 1
            arr[i]["tries"] = String(tries); changed = true
            // There is NO automatic re-upload plea and will not be (the author's decision
            // 20.08). It broke silently twice — on the letter-name prefix and on a dead
            // pipe — paid with a new observable in the air and decided for the person.
            // Instead: an honest refusal here and a word to the peer; the master copy is the
            // sender's, their retry is one tap.
            //
            // The conversation's pipe died (a re-introduction changed the key) — there is
            // NOBODY left to fetch the chunks from or ask. The intent is unfulfillable: put
            // it out honestly instead of asking into the void for the twenty-first time
            // (precedent 20.08: enqueue_drop no-pipe to=500cad3b05).
            let peer = arr[i]["chat"] ?? ""
            if !peer.isEmpty, !MontanaConv.holds(peer) {
                arr[i]["dead"] = "1"
                MontanaP2PTrace.mark("rx_media_dead", "the pipe is dead chat=\(String(peer.prefix(10))) tries=\(tries)")
                MontanaLog.event("RX-MEDIA unfulfillable: no pipe chat=\(peer.prefix(10)) — the intent is removed")
            }
        }
        // Unfulfillable intents leave the list: keeping them means walking in circles forever.
        let deadKeys = Set(arr.filter { $0["dead"] == "1" }.compactMap { $0["sid"] })
        if !deadKeys.isEmpty { arr.removeAll { $0["dead"] == "1" }; changed = true }
        if changed, let d = try? JSONSerialization.data(withJSONObject: arr) {
            pendingMediaJSON = String(data: d, encoding: .utf8) ?? "[]"
        }
        for it in arr {
            let key = it["sid"] ?? ""   // after the migration the key is never empty
            if reconstructInFlight.contains(key) {
                // The pass walks past a running download, and says so (29.09): a silent skip left «neither ends nor speaks».
                MontanaP2PTrace.markFolded("rx_media_wait", "sid=\(String(key.prefix(14))) — a download of this letter is running", window: 300, key: key)
                continue
            }
            // The doors already answered: this sweep walks past it until a hand or a resend.
            if it["gone"] == "1" { continue }   // SILENT-OK: the refusal spoke once, folded, at the start
            if (Int(it["tries"] ?? "0") ?? 0) > 50,
               now - (Double(it["askedAt"] ?? "0") ?? 0) < 21600 { continue }
            if it["kind"] == "avatar" {
                // Pending faces belong to the DEAD chunk era — the face rides inline now, in
                // queue order like the name; retrying an old manifest here is what kept
                // resurrecting yesterday. The entry is buried, not retried ([C-1]).
                dropPendingMedia(key)
                MontanaP2PTrace.mark("pending_face_buried", "key=\(String(key.prefix(14)))")
                continue
            }
            reconstructMedia(it["chat"] ?? "", body: it["body"] ?? "",
                             isFromMe: it["me"] == "1", time: it["time"] ?? "",
                             msgId: key.isEmpty ? nil : key,
                             senderRef: (it["sender"]?.isEmpty ?? true) ? nil : it["sender"],
                             restore: it["me"] == "1")
        }
    }

    // Restore missing local media files of the chat from the sealed vault (Montana/Chats/<label>/Media/).
    // tmp is ephemeral (cleaned by the OS) — the permanent copy lives only as ciphertext in the vault; we restore here on demand.
    /// Restoring open copies is no longer needed: display reads the sealed archive directly
    /// (MontanaMediaVault). Left empty so old callers do not resurrect a second copy.
    func restoreMediaFromVault(_ chat: String, folderKey: String) {
        _ = chat; _ = folderKey
    }

    /// A LETTER WHOSE FILE ALREADY LIES ON DISK IS NOT FETCHED AGAIN — and the question is asked by
    /// the letter's OWN NAME, before the manifest is asked for. The two questions further down
    /// (the row plus the file, the file by its computed name) both need the manifest first, and the
    /// manifest is exactly what stops existing: the sender removes the cargo the moment the assembly
    /// is receipted, and rightly so. Meanwhile the letter travels two roads and its second copy
    /// walks in AFTER the file is whole, finds «gone», queues a retry — and on the fourth such visit
    /// declares the cargo lost and REMOVES the assembled media from the feed. Measured 01.09 23:28:
    /// thirteen chunks fetched and the video assembled at 23:28:02, the cargo dropped at 23:28:03,
    /// the copy from the node box arrived at 23:28:07 and asked for what nobody was meant to come
    /// for again. The file on disk is the one truth about whether a letter still needs anything.
    private func letterAlreadyAssembled(_ chat: String, _ msgId: String?) -> Bool {
        guard let sid = msgId else { return false }
        let rowId = sid.hasPrefix("mid:") ? sid : "mid:" + sid
        guard let row = (messages[chat] ?? []).first(where: { $0.msgId == rowId }),
              let file = row.videoFile ?? row.imageFile ?? row.audioFile ?? row.docFile,
              MontanaMediaStore.exists(file) else { return false }
        return true
    }

    func reconstructMedia(_ pipe: String, body: String, isFromMe: Bool, time: String,
                          msgId: String?, senderRef: String?, restore: Bool = false, transport: String? = nil,
                          proven: Bool = false) {   // proven: the sheet's «200» — the node holds the letter, the row is born «sent»
        // A LATE ROAD OVER A FOLDED PIPE LANDS IN THE CONVERSATION (24.09, MTSamePair): a pending media retry or a big
        // manifest fetched after the fold carries the pipe it arrived by; its row belongs to the conversation.
        let chat = MTSamePair.root(pipe)
        if !restore, letterAlreadyAssembled(chat, msgId) {
            MontanaP2PTrace.mark("rx_media_done", mid: msgId, "the file of this letter is on disk — a second copy asks for nothing")
            return
        }
        guard let d = body.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
            MontanaLog.event("RX-MEDIA FAIL: the manifest did not parse (\(body.count) chars)")
            return
        }
        // A reference to a big manifest: download the blob and continue with the FULL body.
        // One road for reception and retry ([C-1]); a failed download writes a DURABLE intent
        // and retries. The old silent guard-return buried a receipted letter forever: the
        // notification exists, the receipt left, the chat is empty (73 MB video / 140 chunks,
        // the manifest blob failed to open on the first try).
        if let mref = obj["mref"] as? String, let mkB64 = obj["mk"] as? String,
           let mk = Data(base64Encoded: mkB64) {
            Task { [weak self] in
                guard let self else { return }
                var full: String? = nil
                var goneSeen = false
                var busySeen = false
                for attempt in 0..<3 {
                    switch await MontanaWakePush.askBlob(mref) {
                    case .found(let sealed):
                        if let plain = MontanaP2PDirect.open(key: [UInt8](mk), sealed),
                           let t = String(data: plain, encoding: .utf8) { full = t }
                    case .gone: goneSeen = true
                    case .busy: busySeen = true   // a living node refusing this moment — not «gone», waited for longer
                    case .unreachable: break
                    }
                    if full != nil { break }
                    if attempt < 2 { try? await Task.sleep(nanoseconds: busySeen ? 2_500_000_000 : 800_000_000) }
                }
                // A manifest the node calls GONE four visits in a row is gone forever — the
                // pending intent must reach a terminal, not circle «not yet» till the end of
                // time. Same road as lost chunks: nothing at the receiver, a silent word to
                // the sender ([C-1] — one closure for every way cargo dies).
                let goneKey = "mrefGone_" + String(mref.prefix(16))
                if full == nil, goneSeen {
                    let n = UserDefaults.standard.integer(forKey: goneKey) + 1
                    UserDefaults.standard.set(n, forKey: goneKey)
                    if n >= 4 {
                        UserDefaults.standard.removeObject(forKey: goneKey)
                        // Last gate before a bubble is erased: if the file is on disk the letter is
                        // whole, and «the manifest is gone» means only that the cargo was taken.
                        if await MainActor.run(body: { self.letterAlreadyAssembled(chat, msgId) }) {
                            MontanaP2PTrace.mark("rx_media_done", mid: msgId, "manifest gone, file whole — nothing was lost")
                            await MainActor.run {
                                if let sid = msgId { self.reconstructInFlight.remove(sid); self.dropPendingMedia(sid) }
                            }
                            return
                        }
                        // THE ROW STAYS (1638, the author's invariant): the receiver never erases a letter
                        // over its cargo — the bubble stands without its file, the sender is told, and the
                        // re-upload refills the same row (rx_refill).
                        MontanaP2PTrace.mark("cargo_lost", mid: msgId, "manifest blob gone x\(n) — the row stands, the sender is told")
                        await MainActor.run {
                            if let sid = msgId {
                                self.reconstructInFlight.remove(sid)
                                self.dropPendingMedia(sid)
                            }
                        }
                        if let sid = msgId, !isFromMe {
                            let bare = sid.hasPrefix("mid:") ? String(sid.dropFirst(4)) : sid
                            MontanaDeliveryEngine.shared.enqueue(to: chat, chat: chat, mid: UUID().uuidString,
                                                                 text: cargoLostMark + bare, silent: true)
                        }
                        return
                    }
                } else if full != nil {
                    UserDefaults.standard.removeObject(forKey: goneKey)
                }
                await MainActor.run {
                    if let full {
                        self.reconstructMedia(chat, body: full, isFromMe: isFromMe, time: time,
                                              msgId: msgId, senderRef: senderRef,
                                              restore: restore, transport: transport, proven: proven)
                        // The bubble is in the flat — NOW the banner may ring (unless the
                        // push side already rang it). The author's invariant: the message
                        // stands in the chat BEFORE its notification, always.
                        // The ring decision belongs to the ONE notebook judge (P-26), not to
                        // a transport guess: a background push never rang anything by itself.
                        if !isFromMe, let sid = msgId {
                            // The banner reads the LETTER's envelope — the same text the
                            // banner door always rendered as «Video». Handing it the full
                            // manifest leaked raw JSON into the notification (precedent
                            // 23.08 01:27).
                            MontanaNotify.present(from: senderRef ?? chat, chat: chat,
                                                  text: mediaMark + body, mid: sid)
                        }
                    } else {
                        // The old death verdict «no manifest on a live node» rested on the
                        // invariant «the manifest reaches the node BEFORE the letter». The
                        // background handoff broke that invariant: the letter ships while
                        // its chunks still ride the system session (trace 23.08 01:08:
                        // HANDOFF n=321 of 880, DEAD one second later, video never shown).
                        // Absence means «not yet»: the intent waits and returns.
                        MontanaP2PTrace.mark("manifest_blob", "PENDING id=\(String(mref.prefix(8))) — the manifest is still riding, coming back later")
                        self.queuePendingMedia(chat, body: body, isFromMe: isFromMe, time: time,
                                               msgId: msgId, senderRef: senderRef)
                    }
                }
            }
            return
        }
        guard let kind = obj["k"] as? String else {
            MontanaLog.event("RX-MEDIA FAIL: the manifest did not parse (\(body.count) chars)")
            return
        }
        // The letter's placeholder is set on the manifest's first arrival and survives
        // relaunch, so «the message already exists» used to mean «we no longer download the
        // file» — and a broken reception NEVER resumed. Refusal now only when the file
        // actually lies on disk.
        if let sid = msgId, (messages[chat] ?? []).contains(where: { $0.msgId == sid }),
           MontanaMediaStore.exists(mediaFileName(kind: kind, ext: (obj["e"] as? String) ?? "", seed: sid, round: (obj["r"] as? Bool) ?? false, badge: obj["rb"] as? String)) {
            MontanaP2PTrace.mark("rx_media_done", "sid=\(String(sid.prefix(16))) — the bubble and the file already exist")
            return
        }
        // A manifest of pieces. The message and the conversation appear AT ONCE; the file follows.
        if let chunks = obj["chunks"] as? [[String: Any]], let bkB64 = obj["bk"] as? String,
           let blobKey = Data(base64Encoded: bkB64), let size = obj["sz"] as? Int {
            if isFromMe && !restore { return }   // the sender already displayed it; on restore we reconstruct (the file is absent on the new device)
            let ext = (obj["e"] as? String) ?? ""
            let docName = obj["n"] as? String
            let caption = (obj["cap"] as? String) ?? ""

            // The file name is derived from the message identifier: a repeated download writes
            // into the same file and breeds no duplicates.
            let name = mediaFileName(kind: kind, ext: ext, seed: msgId ?? UUID().uuidString, round: (obj["r"] as? Bool) ?? false, badge: obj["rb"] as? String)
            MontanaLog.event("RX-MEDIA kind=\(kind) bytes=\(size) chunks=\(chunks.count) fromMe=\(isFromMe) restore=\(restore) sid=\(msgId ?? "-")")

            // The conversation and the bubble are made BEFORE the download. When a message
            // appeared only after the file assembled, a failed download meant no conversation at
            // all — delivery was already confirmed and dequeued, yet nothing was on screen.
            // Precedent: a 40 MB video, the notification arrived, the conversation did not.
            deletedChats.remove(chat)   // media revives a deleted conversation, as text and a call do
            // The preview from the manifest is filed for every attachment, not only video:
            // without it a photo is a black square until the download ends.
            if let th = obj["th"] as? String, let d = Data(base64Encoded: th) {
                MontanaMainProbe.step("media:poster") {
                    try? d.write(to: posterURL(name))
                    videoThumbCache.removeObject(forKey: name as NSString)
                    imageDecodeCache.removeObject(forKey: name as NSString)
                    MontanaSmallPicture.forget(name)
                }
            }
            // The wave the sender probed (16.09): the bars stand on the first frame, before the file.
            if let wv = obj["wv"] as? String, let d = Data(base64Encoded: wv), !d.isEmpty {   // COMPAT-LOCAL: a new key
                MontanaMainProbe.step("media:wave") { MTWaveform.remember(name, MTWaveform.unpack(d)) }
            }
            if !(messages[chat] ?? []).contains(where: { msgId != nil && $0.msgId == msgId }) {
                MontanaMainProbe.crumb = "media:placeholder"
                appendMediaPlaceholder(chat, kind: kind, name: name, docName: docName, caption: caption,
                                       isFromMe: isFromMe, time: time, msgId: msgId, senderRef: senderRef,
                                       transport: transport, proven: proven, forwarded: (obj["fw"] as? Bool) ?? false,
                                       audioDuration: (obj["du"] as? Double) ?? 0,   // the sender's word (18.09); an older letter says 0 and the file fills it
                                       groupKey: MTMediaGroup.read(obj)?.key,          // the media group (19.09): absent on an older letter
                                       groupIndex: MTMediaGroup.read(obj)?.index ?? 0, groupCount: MTMediaGroup.read(obj)?.count ?? 0)
            }
            // NO RECEIPT HERE. A bubble without a file is not a delivered message: it shows a
            // frame and a progress bar with nothing to watch. The sender saw two checkmarks
            // on a video the peer does not have (precedent 20.08 18:04). For media, delivery
            // = the ASSEMBLED FILE, and the receipt leaves from the assembly point, below.
            // The file is already on disk — there is nothing to fetch.
            if MontanaMediaStore.exists(name) {
                MontanaLog.event("RX-MEDIA skip: the file is already on disk")
                // A ROW BORN BESIDE A FILE THAT CAME FIRST (18.09): the chunks reached the disk ahead of
                // the manifest, and this exit used to leave the row unfilled — a voice with «0:00» under
                // the orb (T1 17:26). The one «file is ready» point runs here too.
                fillMedia(chat, name: name)
                return
            }
            // Automatic download is off for this kind of connection, so the attachment waits for
            // a tap. It is queued anyway, or there would be nothing to tap.
            if !restore, !MontanaNet.shared.autoDownloadAllowed {
                MontanaLog.event("RX-MEDIA skip: automatic download is off (cellular=\(MontanaNet.shared.isCellular))")
                queuePendingMedia(chat, body: body, isFromMe: isFromMe,
                                  time: time, msgId: msgId, senderRef: senderRef)
                return
            }
            if let sid = msgId {
                guard !reconstructInFlight.contains(sid) else {
                    MontanaLog.event("RX-MEDIA skip: already downloading sid=\(sid)")
                    return
                }
                // THE ONE CHOKE POINT OF A START, AND THE ONE PLACE THE VERDICT IS HEARD. Every
                // door already answered «no cargo» for this letter; asking them again changes
                // nothing but the person's traffic. It stands until a hand or a fresh manifest.
                if pendingCargoState(sid).gone {
                    MontanaP2PTrace.markFolded("rx_media_gone", "refused sid=\(String(sid.prefix(14))) — every door said gone; a hand or a resend lifts it",
                                               window: 600, key: sid)
                    return
                }
                reconstructInFlight.insert(sid)
            }
            MontanaLog.event("RX-MEDIA download START chunks=\(chunks.count)")
            // The intent goes to disk BEFORE the first byte: a break, background or app
            // removal stops being a loss. It is removed only on the assembled file.
            queuePendingMedia(chat, body: body, isFromMe: isFromMe, time: time,
                              msgId: msgId, senderRef: senderRef)
            // THE HOLD SPEAKS WHEN THE WINDOW CLOSES (29.09): the intent is on disk and the pieces brought stay in the store — the
            // next foreground finishes from there; said aloud, so a wait is never read as a loss (T1 13:26 waited unspoken).
            let hold = MTSendAssertion("rx-media")
            hold.onExpire = { MontanaLog.event("MEDIA waiting sid=\(String((msgId ?? "-").prefix(16))) why=background-window-expired") }
            // One's OWN share bubble is filled QUIETLY: the file rides back from the node
            // (the sheet's container is invisible to the app), but that is OUR plumbing, not
            // the person's transfer — a «Receiving…» ring on a message they SENT reads as a
            // broken send (the author's word 29.08). The poster from the manifest already
            // shapes the bubble; the file arrives silently, a tap retries if it lags.
            let quietFill = isFromMe && restore
            Task { [weak self] in
                defer { hold.end() }
                // Downloaded as a stream into a temporary file and handed over by mapping it:
                // receiving a video of any size costs the memory of receiving a picture.
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("rx_\(UUID().uuidString)")
                defer { try? FileManager.default.removeItem(at: tmp) }
                if !quietFill {
                    await MainActor.run { self?.setUploadProgress(name, 0.01); self?.setUploadStatus(name, "Receiving…") }
                }
                // Honest reception progress — like sending ([C-1]): network 0-85% by chunks
                // actually downloaded (with megabytes), assembly from the store 85-100%. The
                // whole network phase (minutes on hundreds of MB) used to sit at a blind «1%» —
                // reception felt stuck.
                let totalMB = Double(size) / 1_048_576.0
                let outcome = await MontanaWakePush.fetchChunks(chunks) { done, total in
                    guard !quietFill else { return }
                    Task { @MainActor in
                        let f = Double(done) / Double(max(1, total))
                        self?.setUploadProgress(name, 0.01 + 0.84 * f)
                        self?.setUploadStatus(name, String(format: "%.1f/%.1f MB", f * totalMB, totalMB))
                    }
                }
                // THE CARGO IS GONE AND WILL NOT COME — say it at once, not after twenty
                // seconds of retrying what the node already called absent; and tell the
                // sender, because until they know they keep resending a cargo-less letter.
                if case .lost = outcome {
                    // THE RECEIVER'S ROW STANDS (the author's word 21.09: «it must not vanish from
                    // the chat while it loads»). «Gone» at the receiver is a verdict of the roads,
                    // never knowledge: the cargo lies on one door, the receiver cannot tell that
                    // door from the five that never held it, and 16:30 on T1 the row was erased
                    // three times over a video the node held the whole time. The one who KNOWS is
                    // the sender, by /blob-have against the store (the refill road of 1638): the
                    // receiver keeps the row as «Not received» with a tap to retry, keeps the
                    // intent on disk and the chunks already fetched, and tells the sender once —
                    // a resend or the box's second copy lands on the standing row (rx_refill).
                    MontanaP2PTrace.mark("cargo_lost", mid: msgId, isFromMe ? "own share cargo gone — the row stays red" : "every door says gone — the row stands, the sender is told")
                    await MainActor.run {
                        self?.setUploadProgress(name, nil)
                        if let sid = msgId { self?.reconstructInFlight.remove(sid) }   // a hand may retry
                        if isFromMe {
                            // THE SENDER'S ROW STANDS (1638; 20.09, the critic): its own cargo gone from
                            // the node is a red row with a retry, never a vanished letter.
                            self?.setUploadStatus(name, nil)
                            if let sid = msgId { self?.dropPendingMedia(sid) }
                            self?.setMediaRefused(chat, file: name, because: .cargoGone)
                        } else {
                            self?.setUploadStatus(name, String(localized: "Not received", bundle: MTLanguage.bundle))
                        }
                    }
                    // THE VERDICT GOES TO DISK. Without this the next launch starts the four hours
                    // again: measured ninety-four starts of one letter in an evening, all of them
                    // into doors that had already said «no cargo» a hundred and seventy-seven times.
                    if !isFromMe {
                        let told = msgId.map { self?.pendingCargoState($0).told ?? false } ?? false
                        await MainActor.run { self?.markPendingCargoGone(msgId, told: true) }
                        if let sid = msgId, !told {
                            // ONCE per letter, and the «once» now survives a launch: every later
                            // retry of the standing row asks the doors again, not the sender again.
                            let bare = sid.hasPrefix("mid:") ? String(sid.dropFirst(4)) : sid
                            MontanaDeliveryEngine.shared.enqueue(to: chat, chat: chat, mid: UUID().uuidString,
                                                                 text: cargoLostMark + bare, silent: true)
                        }
                    }
                    return
                }
                guard await MontanaMedia.downloadToFile(manifest: chunks, blobKey: blobKey, totalSize: size, dest: tmp,
                                                        progress: { pr in if !quietFill { Task { @MainActor in self?.setUploadProgress(name, 0.85 + 0.15 * pr) } } }),
                      MontanaMediaStore.adopt(from: tmp, name: name) else {
                    NSLog("[MEDIA] reassemble FAIL — queued for re-fetch")
                    MontanaLog.event("E2E-BLOB rx FAIL bytes=\(size) chunks=\(chunks.count)")
                    await MainActor.run {
                        self?.setUploadProgress(name, nil)
                        // AN HONEST STATE AT THE RECEIVER. Everything used to be cleared here,
                        // and the person saw a tile with no file and not a word about what
                        // happened. Now the bubble says «not received», and a tap retries.
                        // One's OWN row says it too (20.09, the critic): a silent failure left a black
                        // square nobody could tell from «still loading».
                        self?.setUploadStatus(name, String(localized: "Not received", bundle: MTLanguage.bundle))
                        if let sid = msgId { self?.reconstructInFlight.remove(sid) }   // a retry is possible
                    }
                    return   // the intent is already on disk — the next pass continues from the same place
                }
                await MainActor.run { self?.mediaLanded(chat, name: name, msgId: msgId, isFromMe: isFromMe, docName: docName) }
                // The chunks are NOT removed: the blob is content-addressed and SHARED — a
                // letter retry (alive in the queue until the receipt) or a broadcast's second
                // addressee will fetch it again. Early teardown gave blob_dl FAIL at the
                // second consumer. The node cleans up by its own term (BOUND-OK: the mirror
                // node's TTL, not a third copy at the client).
            }
            return
        }
        // legacy: file base64 directly in the body (field "a")
        guard let b64 = obj["a"] as? String, let data = Data(base64Encoded: b64) else { return }
        appendMedia(chat, kind: kind, ext: (obj["e"] as? String) ?? "", data: data,
                    docName: obj["n"] as? String, isFromMe: isFromMe, time: time, msgId: msgId, senderRef: senderRef)
    }
    /// The peer's letter with exactly these words already stands in the feed (the newest twelve
    /// rows of theirs): a draft word repeating it is a ghost, not news.
    func peerLetterStands(_ chat: String, text: String) -> Bool {
        let want = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !want.isEmpty, let rows = messages[chat] else { return false }
        return rows.suffix(40).reversed().filter { !$0.isFromMe }.prefix(12)
            .contains { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) == want }
    }
    // A message's file name is derived deterministically: a repeated download writes the same file.
    func mediaFileName(kind: String, ext extIn: String, seed: String, round: Bool = false, badge: String? = nil) -> String {
        let ext = MTMediaFileSuffix.of(extIn, kind: kind)
        let h = SHA256.hash(data: Data(seed.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        // A round video note keeps its roundness in its name here too (the author's word 10.09):
        // the manifest's r flag becomes the vnote_ prefix the bubble reads; the dual note's badge
        // corner (rb) rides in after it — vnote_D + tl|tr|bl|br — so the window is drawn with it.
        let mark = badge.flatMap { MontanaVideoNoteCamera.cornerTags.contains($0) ? "D" + $0 : nil } ?? ""
        return (kind == "aud" ? "voice_" : (round && kind == "vid" ? "vnote_" + mark : "att_")) + h + "." + ext
    }

    // A bubble without its file: the conversation is visible at once and the content follows. A
    // file missing from disk is an ordinary state — history looks the same after a reinstall.
    func appendMediaPlaceholder(_ chat: String, kind: String, name: String, docName: String?,
                                caption: String, isFromMe: Bool, time: String,
                                msgId: String?, senderRef: String?, transport: String? = nil, proven: Bool = false,
                                forwarded: Bool = false, audioDuration: Double = 0,
                                groupKey: String? = nil, groupIndex: Int = 0, groupCount: Int = 0) {
        let t = time.isEmpty ? nowHHMM() : time
        // THE PLACE OF A MEDIA ROW IS ITS BIRTH, NOT ITS ARRIVAL. Text letters have ordered
        // themselves by the millisecond in their own name for a long time; media rows were still
        // ordered by the moment they landed — so a letter delayed (or re-sent after a loss) stood
        // in one place for the sender and in another for the receiver, and the two chats read
        // differently. [P2P-COMPAT] a name without a millisecond keeps the old behaviour exactly.
        let born = ChatStore.birthMs(fromMid: msgId ?? "") ?? Date().timeIntervalSince1970
        var msg: Message
        // What ARRIVED from another is delivered by definition. One's OWN is NEVER born
        // delivered: a bubble of one's own media used to appear with two checkmarks at once —
        // before any receipt and often before any send (the «Share» road and media retries
        // come here too). Exactly that gave «two checkmarks on a video the peer does not
        // have» (precedent 20.08).
        // An own row is born «sending»; a row the share sheet already lettered (proven: the node
        // answered 200) is born «sent» — the rung says what is known (the author's word 13.09).
        let bornStatus: DeliveryStatus = isFromMe ? ownBornStatus(mid: msgId, proven: proven) : .delivered
        switch kind {
        case "img": msg = Message(text: caption, isFromMe: isFromMe, time: t, imageFile: name,
                                  docName: docName,   // a sticker names itself here (15.42)
                                  deliveryStatus: bornStatus, msgId: msgId, senderRef: senderRef,
                                  createdAt: born, transport: transport)
        case "vid": msg = Message(text: caption, isFromMe: isFromMe, time: t, videoFile: name,
                                  deliveryStatus: bornStatus, msgId: msgId, senderRef: senderRef,
                                  createdAt: born, transport: transport)
        case "aud": msg = Message(text: "", isFromMe: isFromMe, time: t, audioFile: name, audioDuration: audioDuration,
                                  deliveryStatus: bornStatus, msgId: msgId, senderRef: senderRef,
                                  createdAt: born, transport: transport)
        default:    msg = Message(text: "", isFromMe: isFromMe, time: t, docFile: name,
                                  docName: docName ?? name,
                                  deliveryStatus: bornStatus, msgId: msgId, senderRef: senderRef,
                                  createdAt: born, transport: transport)
        }
        msg.forwarded = forwarded
        if let groupKey { msg.groupKey = groupKey; msg.groupIndex = groupIndex; msg.groupCount = groupCount }
        var placed = msg
        MontanaMainProbe.step("media:placeRow") { placed = placeRow(chat, msg) }
        MontanaMainProbe.step("media:journal") { _ = MTRowJournal.put(chat, placed) }   // on disk before the list record, the receipt and the share box empties (16.09)
        MontanaMainProbe.step("media:archive") { archiveRow(chat, placed) }
        MontanaMainProbe.step("media:bump") { bump(chat) }
        MontanaMainProbe.step("media:listState") { noteListState(chat, last: lastLetter(chat)) }   // the list record follows the newest (stage 9, 17.09) — Share-sent media left the old preview standing
        if !isFromMe && chat != openConv { MontanaMainProbe.step("media:unread") { handMarkYields(chat); recalcBadge() } }   // the letter is the unread one (23.09)
        // The trace is mandatory: «the receipt left but the person saw no bubble» is solved only by it.
        MontanaP2PTrace.mark("media_bubble", "chat=\(String(chat.prefix(10))) sid=\(String((msgId ?? "-").prefix(16))) n=\(messages[chat]?.count ?? 0)")
    }

    /// The file is accepted and already lies ready in the correspondence store — no second
    /// copy is made, open or sealed. Only the display caches are dropped here.
    /// THE FILE IS HERE, WHOLE — by the download, or by a play that ran to its end (25.09): one landing for both roads. The
    /// bar goes, the row is filled, a sticker is kept, the intent is fulfilled, and the letter is delivered once its row is on
    /// disk — a receipt speaks only for what survives a relaunch: not written, not delivered; the sender retries, the door
    /// dedups, the next attempt finishes the write (precedent 23:37: the receipt left, the row died with the process).
    func mediaLanded(_ chat: String, name: String, msgId: String?, isFromMe: Bool, docName: String?) {
        setUploadProgress(name, nil); setUploadStatus(name, nil)
        if let sid = msgId { reconstructInFlight.remove(sid) }
        MontanaLog.event("MEDIA landed name=\(name) sid=\(String((msgId ?? "-").prefix(16))) fromMe=\(isFromMe)")   // the daily diary names the whole file (29.09)
        fillMedia(chat, name: name)
        // A STICKER THAT ARRIVED IS KEPT (the author's word 22.09): the receiver's panel holds what was used in the
        // conversation, exactly as the sender's does. One copy per picture -- the book knows the sticker by its bytes.
        if docName == MontanaCardPlate.stickerName {
            MontanaStickerBook.shared.adopt(file: name)
            // The passport may have arrived before the picture: its quote settles here, through the one owner of a late quote.
            if let sid = msgId, let port = MontanaStickerBook.shared.passport(forLetter: sid), !port.quote.isEmpty {
                enrichQuote(chat, sid: sid, qt: port.quote, qm: port.quoteMid)
            }
        }
        dropPendingMedia(msgId)   // the file is assembled — the intent is fulfilled
        let persisted = ChatStore.writeHistory(messages)
        if persisted {
            sendDeliveryReceipt(chat, msgId: msgId, isFromMe: isFromMe, text: mediaMark)
        } else {
            MontanaP2PTrace.mark("receipt_held", "mid=\(String((msgId ?? "-").prefix(8))) — history not written")
        }
    }
    /// WHAT A PLAYER READS BEFORE THE FILE IS WHOLE (25.09): the letter's intent names the pieces and their key; the file is
    /// laid where the download would put it (the media store), and its landing is the download's own. A letter whose
    /// manifest still rides the node (mref) has no pieces in hand — nil, and the tap takes the download road.
    func stream(forFile name: String) -> (source: MTStreamSource, landed: () -> Void)? {
        guard let arr = try? JSONSerialization.jsonObject(with: Data(pendingMediaJSON.utf8)) as? [[String: String]] else { return nil }
        for r in arr {
            guard let body = r["body"], let chat = r["chat"], let sid = r["sid"],
                  let obj = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any],
                  let kind = obj["k"] as? String,
                  let chunks = obj["chunks"] as? [[String: Any]], let bk = obj["bk"] as? String,
                  let key = Data(base64Encoded: bk), let size = obj["sz"] as? Int, 0 < size else { continue }
            let ext = (obj["e"] as? String) ?? ""
            let file = mediaFileName(kind: kind, ext: ext, seed: sid, round: (obj["r"] as? Bool) ?? false, badge: obj["rb"] as? String)
            guard file == name else { continue }
            let pieces = chunks.compactMap { c -> MTBoardChunk? in
                guard let b = c["bid"] as? String, let cs = c["cs"] as? Int else { return nil }
                return MTBoardChunk(bid: b, cs: cs)
            }
            guard pieces.count == chunks.count, !pieces.isEmpty else { return nil }
            let mine = r["me"] == "1"
            let docName = obj["n"] as? String
            let src = MTStreamSource(name: name, ext: (name as NSString).pathExtension, size: size, key: key, chunks: pieces,
                                     folder: MontanaMediaStore.dir)
            return (src, { [weak self] in self?.mediaLanded(chat, name: name, msgId: sid, isFromMe: mine, docName: docName) })
        }
        return nil
    }
    func fillMedia(_ chat: String, name: String) {
        musicMemo = nil; mediaMemo = nil   // a file now whole may be a track the library skipped, or a moment the gallery skipped, while it was on its way (the critic 24.09)
        // The ONE «file is ready» point also owns the bar ([C-1]): a file on disk and a
        // progress ring may never coexist, whichever road filled the file.
        setUploadProgress(name, nil); setUploadStatus(name, nil)
        MontanaP2PTrace.mark("media_fill", "name=\(String(name.prefix(24)))")
        imageDecodeCache.removeObject(forKey: name as NSString)
        // The thumbnail is recomputed from the real file — it is sharper than the manifest's
        // poster. Simply clearing it would leave the bubble without frame dimensions until then.
        videoThumbCache.removeObject(forKey: name as NSString)
        Task.detached(priority: .utility) { _ = await videoThumbAsync(name) }
        // The duration: the sender's word stands (born with the row); a row without it — an older
        // letter — asks the file, the one fallback ([C-1]).
        if let i = (messages[chat] ?? []).firstIndex(where: { $0.audioFile == name }),
           !((messages[chat]?[i].audioDuration ?? 0) > 0) {
            let d = MontanaAudioDuration.of(attachmentURL(name))
            if d.isFinite, d > 0 { messages[chat]?[i].audioDuration = d }
            else { MontanaP2PTrace.mark("voice_duration", "the file names no duration name=\(String(name.prefix(16)))") }
        }
        objectWillChange.send()
    }

    /// A music file found on the web lands in Saved Messages as this device's own document
    /// (15.44); the library sees it at once. Returns the stored file name.
    func saveMusicFromWeb(_ data: Data, name: String) -> String? {
        let ext = (name as NSString).pathExtension.lowercased()
        return landOwnFile(ext: ext.isEmpty ? "mp3" : ext, docName: name) { MontanaMediaStore.put($0, data: data) }
    }
    /// A FILE OF ONE'S OWN LANDS IN SAVED MESSAGES BY ONE ROAD (the critic 24.09): the web's find and a folder's import
    /// alike — a letter's name (its birth), the store's door that puts the bytes (put or adopt, both born now), the row
    /// born «sent» (the room without a wire settles there, markStaleSendsFailed), the list record and the order with it.
    /// The web's road wrote its row «delivered», with no letter's name and no list record, and placed a row even over a
    /// write the disk refused. Returns the stored name; nil when the bytes were not put — and then no row is born.
    @discardableResult
    func landOwnFile(ext: String, docName: String, put: (String) -> Bool) -> String? {
        let mid = ChatStore.mintMid().mid
        let name = mediaFileName(kind: "doc", ext: ext.lowercased(), seed: "mid:" + mid)
        guard put(name) else {
            MontanaP2PTrace.mark("media_store_fail", "name=\(String(name.prefix(12))) own file refused by the disk")
            return nil
        }
        appendMediaPlaceholder(savedMessagesKey, kind: "doc", name: name, docName: docName, caption: "",
                               isFromMe: true, time: "", msgId: "mid:" + mid, senderRef: nil, proven: true)
        return name
    }

    func appendMedia(_ chat: String, kind: String, ext extIn: String, data: Data, docName: String?,
                     caption: String = "",
                     isFromMe: Bool, time: String, msgId: String?, senderRef: String?) {
        var ext = extIn
        if ext.isEmpty { ext = kind == "img" ? "jpg" : (kind == "vid" ? "mov" : (kind == "aud" ? "m4a" : "dat")) }
        let name = (kind == "aud" ? "voice_" : "att_") + UUID().uuidString + "." + ext
        if !MontanaMediaStore.put(name, data: data) {   // the disk is full — this cannot be kept silent
            MontanaLog.event("MEDIA ✗ store write failed \(name)")
            MontanaP2PTrace.mark("media_store_fail", "name=\(String(name.prefix(12)))")
        }
        let t = time.isEmpty ? nowHHMM() : time
        let msg: Message
        switch kind {
        case "img":
            msg = Message(text: caption, isFromMe: isFromMe, time: t, imageFile: name, docName: docName,
                          deliveryStatus: .delivered, msgId: msgId, senderRef: senderRef)
        case "vid":
            msg = Message(text: caption, isFromMe: isFromMe, time: t, videoFile: name,
                          deliveryStatus: .delivered, msgId: msgId, senderRef: senderRef)
        case "aud":
            let dur = MontanaAudioDuration.of(attachmentURL(name))
            msg = Message(text: "", isFromMe: isFromMe, time: t, audioFile: name, audioDuration: dur,
                          deliveryStatus: .delivered, msgId: msgId, senderRef: senderRef)
        default:
            msg = Message(text: "", isFromMe: isFromMe, time: t,
                          docFile: name, docName: docName ?? name,
                          deliveryStatus: .delivered, msgId: msgId, senderRef: senderRef)
        }
        placeRow(chat, msg)
        MTRowJournal.put(chat, msg)
        archiveRow(chat, msg)
        bump(chat)
    }

    // Shared container for the «Share» menu (app group).

    // Stage 12: E2E media send to an ARBITRARY peer. A single path for the chat
    // and for the «Share» menu — the file is split into chunk-blobs, the manifest goes into the ratchet.
    // statusChat/statusFile — an honest message status (sent / failed): silent failure on
    // the critical path is forbidden. progressBase/Span — the upload's contribution to the SINGLE progress bar
    // (video: compression 0…0.3, upload 0.3…1.0; everything else: 0…1.0).
    func sendMediaToPeer(peer: String, source: MediaSource, kind: String, ext: String,
                         docName: String? = nil, progressKey: String? = nil, caption: String = "",
                         statusChat: String? = nil, statusFile: String? = nil,
                         progressBase: Double = 0, progressSpan: Double = 1,
                         forceMid: String? = nil) {
        // A LIVING SEND OF THIS FILE IS NOBODY'S SECOND SEND (21.09, the critic): the road itself
        // refuses, not only the drain's resume — measured 17:36 on 1829: two sends of one note
        // ran side by side, every chunk went up twice over cellular.
        if let k = progressKey, uploadTasks[k] != nil {
            MontanaP2PTrace.mark("send_dup", "file \(k.prefix(24)) is uploading — the second send is refused")
            return
        }
        // Only a picture is read for its thumbnail; a video is never lifted into memory.
        // A video needs a thumbnail too: without one the recipient sees a black rectangle until
        // the download ends, and a tap opens a player on a file that does not exist — a crossed-out
        // button instead of a plain invitation to download.
        let thumb: String? = {
            switch (kind, source) {
            case ("img", .memory(let d)):
                return UIImage(data: d)?.mediaThumbnail()?.base64EncodedString()
            case ("img", .file(let u)):
                // A photo from the shelf (the share's resend) used to travel without its poster: the
                // receiver's row wore a plate until the file came (20.09).
                return UIImage(contentsOfFile: u.path)?.mediaThumbnail()?.base64EncodedString()
            case ("vid", .file(let u)):
                // SSOT: the manifest carries the poster born with the letter — the image
                // of the compressing bubble, the sending bubble and the receiver's bubble
                // is byte-identical. Generation from the compressed file is only the
                // fallback for letters that never had a poster.
                if let key = statusFile ?? progressKey,
                   let d = try? Data(contentsOf: posterURL(key)), !d.isEmpty {
                    return d.base64EncodedString()
                }
                return videoPosterImage(u)?.mediaThumbnail(maxDim: 320, maxBytes: 12_000)?.base64EncodedString()
            default: return nil
            }
        }()
        // The bubble frame is the SAME on both sides by construction: the manifest preview
        // (what the receiver renders) becomes the sender's poster too. Two sources — the
        // sender's locally-born frame and the receiver's manifest thumb — diverged in
        // aspect (precedent 23.08: horizontal at the sender, vertical at the receiver;
        // the author's invariant: both chats are mirrored absolutely, on any data).
        // A photo's poster is filed the same way (16.09): the row and the reply bar read a
        // small picture of one's own photo as of the peer's, never the whole photograph.
        if kind == "vid" || kind == "img", let t = thumb, let d = Data(base64Encoded: t), let img = UIImage(data: d) {
            for key in Set([progressKey, statusFile].compactMap { $0 }) {
                try? d.write(to: posterURL(key))
                videoThumbCache.setObject(img, forKey: key as NSString)
            }
        }
        let totalBytes = source.byteCount
        let totalMB = Double(totalBytes) / 1_048_576.0
        // The letter's name is known BEFORE the upload: the node-side chunk ledger runs under
        // it, chunks are removed under it — on delivery and on failure — and under it the
        // bubble earns its honest status.
        // A letter named here (no row forced its name) is still named like every letter:
        // with its birth millisecond, never a bare number (15.52.9 — one kind of name).
        let letterMid = forceMid ?? ChatStore.mintMid().mid
        // A GROUP'S MEDIA (MTGroup.carryMedia): no piece in the pipes' queue and no chunk ledger -- many receivers take the pieces,
        // so no single receipt releases them; the node's term does.
        let group = MTGroup.isKey(statusChat ?? peer)
        func report(_ pr: Double?) {
            guard let k = progressKey else { return }
            Task { @MainActor in
                self.setUploadProgress(k, pr.map { progressBase + $0 * progressSpan })
                if let pr { self.setUploadStatus(k, String(format: "%.1f/%.1f MB", pr * totalMB, totalMB)) }
            }
        }
        func finish(_ ok: Bool) {
            // A broken upload does NOT drop the intent (18.09): the record stays in the queue and the next
            // drain re-runs the send by itself. Only a hand (cancel, delete) drops it.
            Task { @MainActor in
                if let k = progressKey { self.setUploadProgress(k, nil); self.setUploadStatus(k, nil) }
                // Uploading chunks and queueing the letter is NOT YET a send. Only the
                // receiver's receipt sets the checkmark (markDelivered). What remains here is
                // either an honest refusal or the clock still waiting.
                // A BREAK IS NOT A VERDICT WHILE THE INTENT RIDES (07.10, MTRefusal): the queue holds it and the drain sends
                // again, so the row keeps its clock; red only when nothing carries it -- a group's media has no intent queued.
                if let c = statusChat, let f = statusFile, !ok, group || !MontanaDeliveryEngine.shared.queueHolds(mid: letterMid) {
                    self.setMediaRefused(c, file: f, because: .nothingCarries)
                }
            }
        }
        // THE SEND INTENT LANDS ON DISK BEFORE THE FIRST NETWORK BYTE — into the same single
        // outgoing queue as letters ([C-1]). No sixth store: durability, death by term,
        // honest red and reachability-driven draining already belong to that queue. Hence
        // honesty across process death: the record outlives it and becomes red with a retry,
        // not an eternal clock over a file the peer does not have.
        if let c = statusChat, let f = statusFile {
            Task { @MainActor in self.setMediaMid(c, file: f, mid: letterMid) }
        }
        if !group {
            MontanaDeliveryEngine.shared.enqueue(
                to: peer, chat: statusChat ?? peer, mid: letterMid,
                text: "{\"k\":\"\(kind)\",\"e\":\"\(ext)\",\"f\":\"\(statusFile ?? "")\"}",
                silent: false, kind: .piece)
        }
        let t = Task {
            let hold = MTSendAssertion("media-upload")
            // Stage 8.3: when the system window expires mid-upload, the remaining chunks are
            // handed to the background session and the flow finishes as a handoff, not a death.
            hold.onExpire = { MontanaWakePush.handOffFlag.raise(letterMid) }
            defer { hold.end(); MontanaWakePush.handOffFlag.clear(letterMid) }
            // NO GATE, NO SLOT (the author's word 20.09: nothing waits, no queue for media or for any
            // data). This send starts now and runs beside every other: no slot per correspondent (nine
            // photos used to walk one after another while the share sheet sent the same nine at once),
            // no store budget waiting on the peer's receipt (a second video to a sleeping peer stood
            // «Queued» until a hand deleted the first — 14.09: 43 s, 15.09: 100 s). The node store
            // bounds its cargo by its own term, not by receipts; the record below is a ledger for the red
            // mark and the resume after the process dies — never a gate.
            let _t0 = Date()
            MontanaLog.event("media START kind=\(kind) bytes=\(totalBytes)")
            // NO NODE HELD — NO ATTEMPT (18.09, the author's word: the bubble is local and instant,
            // the sending is later work). The chunks go to a node; without one the upload could only
            // burn its timeouts — measured 18.09 14:14: four puts of 4.3 s on an airplane phone whose
            // VPN tunnel kept the path «satisfied», a ring on the bubble for 28 s, then red. The
            // intent is on disk and in the queue, the row keeps its clock and wears no ring; the
            // drain re-runs this send the moment a node is held (the mesh state calls it).
            if !MontanaP2PNode.shared.p2pUp {
                if group { finish(false); return }   // no drain carries a group's media later: honest red, a hand sends it again
                MontanaP2PTrace.mark("media_wait", mid: letterMid, "no node held — the intent waits for the drain")
                // The ring and its word go with the attempt that is not made: a bubble waiting for a node
                // wears the clock, not «Compressing 100%» (T1 14:26, the author's word).
                if let k = progressKey { await MainActor.run { self.setUploadProgress(k, nil); self.setUploadStatus(k, nil) } }
                return   // the hold goes by its defer; the piece stays in the ledger for the drain
            }
            report(0.01)
            // ONE honest progress ([C-1]): preparation (slicing+sealing) 0-25%, network
            // 25-100% by chunks actually uploaded. 100% used to fill up on local slicing while
            // the upload ran blind — the file «hung ready» without reaching the network.
            // Assembling a manifest is shared with the share extension. Two implementations of
            // one protocol format drift by construction, and only the recipient sees it: a video
            // preview had already appeared in one of them alone.
            guard let ref = await MontanaMedia.buildManifest(
                source: source, kind: kind, ext: ext, docName: docName, caption: caption,
                thumb: thumb, round: (statusFile ?? "").hasPrefix("vnote_"),
                badge: MontanaVideoNoteCamera.badgeTag(statusFile ?? ""),
                // The row is the truth of «forwarded» ([C-1]): the manifest reads it, a resend included.
                forwarded: (statusChat.flatMap { messages[$0] } ?? []).contains { m in
                    m.isForwarded && (m.videoFile ?? m.imageFile ?? m.audioFile ?? m.docFile) == statusFile },
                letterMid: letterMid,
                waveform: statusFile.flatMap(MTWaveform.cached),   // the wave born with the row rides as it is
                duration: (statusChat.flatMap { messages[$0] } ?? []).first { $0.audioFile == statusFile }?.audioDuration,   // the recorder's word
                // The row is the truth of the group as well ([C-1], 19.09): a resend keeps its place in the plate.
                group: (statusChat.flatMap { messages[$0] } ?? []).first { m in
                    m.groupKey != nil && (m.videoFile ?? m.imageFile ?? m.audioFile ?? m.docFile) == statusFile
                }.flatMap { m in m.groupKey.map { (key: $0, index: m.groupIndex, count: m.groupCount) } },
                progress: { pr in report(pr * 0.25) }) else {
                if Task.isCancelled { MontanaDeliveryEngine.shared.dropPiece(letterMid); return }   // canceled by the user — status is already .failed
                NSLog("[MEDIA] upload FAIL")
                MontanaLog.event("upload FAIL kind=\(kind) bytes=\(totalBytes) ms=\(Int(Date().timeIntervalSince(_t0)*1000))")
                finish(false); return
            }
            if Task.isCancelled { MontanaDeliveryEngine.shared.dropPiece(letterMid); return }
            // The sender's own bubble draws the very bars the receiver will (16.09).
            if let f = statusFile, let wv = ref["wv"] as? String, let d = Data(base64Encoded: wv), !d.isEmpty {   // COMPAT-LOCAL: a new key
                MTWaveform.remember(f, MTWaveform.unpack(d))
            }
            let plannedBids = (ref["chunks"] as? [[String: Any]] ?? []).compactMap { $0["bid"] as? String }
            if !group { MontanaWakePush.noteChunks(letter: letterMid, bids: plannedBids) }
            let chunkCount = (ref["chunks"] as? [[String: Any]])?.count ?? 0
            MontanaLog.event("upload BLOBS kind=\(kind) bytes=\(totalBytes) chunks=\(chunkCount) ms=\(Int(Date().timeIntervalSince(_t0)*1000))")
            guard let json = try? JSONSerialization.data(withJSONObject: ref),
                  let body = String(data: json, encoding: .utf8) else { finish(false); return }
            // Stream the sealed chunks over the mesh FIRST (fire-and-forget, so they
            // are not blocked by the manifest send), then send the manifest — the peer then finds all
            // chunks already in its blob store and the media completes at once.
            // CHECKED: the manifest may overtake the blobs on a fast transport, and that costs a retry,
            // not the media: a manifest whose chunks are absent lands in queuePendingMedia and is re-fetched.
            // Waiting for every chunk before the manifest would slow every send to close a delay.
            // Chunks — to the accelerator node (sealed with the content key, the node is
            // blind); the manifest — as a letter through the wake envelope. A big manifest
            // itself rides as a blob: the envelope carries {mref, mk} (the manifest key inside
            // the E2E envelope, invisible to the node).
            // THE SILENCE WATCHDOG. An upload that stopped moving must fail honestly, not
            // hang as an eternal clock. Precedent 20.08: airplane mode mid-upload — 28 chunks
            // of 71 went, then NEITHER success NOR failure, the letter never queued, the
            // sender's clock stood forever. The watchdog watches not the whole upload's time
            // (a big video runs minutes) but the PAUSE between chunks: silent past the limit —
            // we give up honestly.
            let beat = MTBox<Date>(Date())
            let chunksOk = await withTaskGroup(of: Bool.self) { g -> Bool in
                g.addTask {
                    await MontanaWakePush.uploadChunks(ref, letter: letterMid) { done, total in
                        beat.value = Date()
                        report(0.25 + 0.75 * Double(done) / Double(max(1, total)))
                    }
                }
                g.addTask {
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 5_000_000_000)
                        if Task.isCancelled { break }
                        if Date().timeIntervalSince(beat.value) > Self.uploadSilenceLimit {
                            MontanaP2PTrace.mark("blob_up", "silent longer than \(Int(Self.uploadSilenceLimit))s — giving up honestly")
                            return false
                        }
                    }
                    return true
                }
                let first = await g.next() ?? false
                g.cancelAll()
                return first
            }
            guard chunksOk else {
                NSLog("[MEDIA] blob upload FAIL")
                MontanaLog.event("upload FAIL kind=\(kind) — not sent; the intent stays queued, the drain resumes it")
                // There will be no letter — so NOBODY will come for these chunks. We remove
                // them ourselves: the node cannot know; to it an unclaimed chunk looks like
                // one awaiting a sleeper. Precedent 20.08: an hour of tests left ~93 orphan chunks.
                let orphans = MontanaWakePush.releaseLetter(letterMid)
                if !orphans.isEmpty { await MontanaWakePush.dropBids(orphans) }
                // And the crate ON THE PHONE goes whole. A retry reassembles the file anew:
                // the seal takes a fresh nonce, the chunk names come out different, and the
                // old ones will NEVER be needed. Keeping them meant hoarding dead cargo until
                // the message itself was deleted (measured 20.08: 4 chunks on the phone from
                // exactly one broken send, 23 minus 19).
                MontanaBlobStore.drop(plannedBids)
                finish(false); return
            }
            // ONE decision point for manifest→letter ([C-1]): MontanaMedia.manifestLetter —
            // the same rule the Share sheet and the pending-share ingest ask. Only the blob
            // transport is ours here: the app leg knows the hand-off window.
            guard let composed = await MontanaMedia.manifestLetter(json, putBlob: { mbid, sealedManifest in
                if MontanaWakePush.handOffFlag.check(letterMid) {
                    MontanaBlobUpload.shared.enqueue(bid: mbid, sealed: sealedManifest); return true
                }
                if await MontanaWakePush.putBlob(mbid, data: sealedManifest) { return true }
                if MontanaWakePush.handOffFlag.check(letterMid) {
                    // The window died during this very request — hand it over, not bury it.
                    MontanaBlobUpload.shared.enqueue(bid: mbid, sealed: sealedManifest); return true
                }
                return false
            }) else {
                let orphans = MontanaWakePush.releaseLetter(letterMid)
                if !orphans.isEmpty { await MontanaWakePush.dropBids(orphans) }
                finish(false); return
            }
            if !group, let mbid = composed.manifestBid {
                MontanaWakePush.noteChunks(letter: letterMid, bids: [mbid])   // the manifest lies on the node too
            }
            let letter = composed.letter
            // The letter's name is stamped onto the BUBBLE itself: without it the receiver's
            // receipt cannot find the media message (settleByMid/markDelivered search by
            // name), and media could NEVER earn an honest checkmark — only a false one, by
            // the fact of upload. A re-upload rides UNDER THE SAME name: the receiver's
            // intent updates instead of a second bubble appearing.
            if group {
                let key = statusChat ?? peer
                let carried = await MainActor.run { MTGroup.shared.carryMedia(letter, mid: letterMid, in: key, store: self) }
                MontanaLog.event("upload END group carried=\(carried ? 1 : 0) chunks=\(chunkCount)")
                finish(carried)
                return
            }
            MontanaDeliveryEngine.shared.promotePiece(mid: letterMid, text: letter, to: peer, chat: statusChat ?? peer)
            MontanaLog.event("upload END queued chunks=\(chunkCount)")
            finish(true)
        }
        if let k = progressKey { uploadTasks[k] = t; Task { @MainActor in _ = await t.value; self.uploadTasks[k] = nil } }
    }

    // Mirror the chat list + base URL into the shared keychain so the extension
    // «Share» can show the chat picker and know the blob-storage address.
    // name = address to send to (convRef), title = display name.
    /// The share grid must not depend on the chats tab having been opened: the store reads the
    /// saved list itself and mirrors THE SAME ROWS the tab would draw, on every activation.
    func remirrorShareFromStore() { mirrorChatsToShare(listRows(stored: storedChats())) }

    /// The saved list (chatsJSON) as the vault holds it — the one decode of it; empty when none was saved.
    func storedChats() -> [Chat] { chatsShelf() ?? [] }
    /// A shelf as the vault holds it: [] when nothing was saved, nil when what was saved does not read — the audit
    /// tells the two apart (the critic 24.09: «archived=0» said «empty» and «unreadable» alike).
    func chatsShelf() -> [Chat]? { Self.shelf("chatsJSON") }
    func archivedShelf() -> [Chat]? { Self.shelf("archivedJSON") }
    private static func shelf(_ key: String) -> [Chat]? {
        let text = MontanaLocalVault.getString(key) ?? ""
        if text.isEmpty { return [] }
        return try? JSONDecoder().decode([Chat].self, from: Data(text.utf8))
    }
    /// THE LIST OF WHOM TO WRITE TO (the author's word 16.09): every screen that lists people —
    /// the forward picker, the new call, the contacts tab — shows the chats tab's rows in the
    /// chats tab's order, Saved Messages and pins included, through this one road ([C-1]). Three
    /// screens used to gather people each in its own way: the forward list had no Saved Messages,
    /// the calls list ran by another freshness, the contacts tab by the day a card was added.
    func listChats() -> [Chat] { ChatStore.listOrder(listRows(stored: storedChats()), pinned: pinnedChats) }
    /// The saved archive (archivedJSON) as the vault holds it — the one decode of it.
    func storedArchived() -> [Chat] { archivedShelf() ?? [] }
    /// THE SHELVES' ONE WRITER (the critic 24.09: the store and the chats tab each wrote both shelves whole, and a
    /// restored row written by one was written away by the other's stale copy). Every write of the list's two shelves
    /// passes here; `tell` — the tabs reread the vault (a tab writing its own fresh copy needs no telling).
    func saveStored(chats: [Chat]? = nil, archived: [Chat]? = nil, tell: Bool = true) {
        if let chats, let d = try? JSONEncoder().encode(chats), let str = String(data: d, encoding: .utf8) { MontanaLocalVault.setString("chatsJSON", str) }
        if let archived, let d = try? JSONEncoder().encode(archived), let str = String(data: d, encoding: .utf8) { MontanaLocalVault.setString("archivedJSON", str) }
        if tell { NotificationCenter.default.post(name: .montanaChatsChanged, object: nil) }   // the tabs reread the vault
    }
    /// ARCHIVE — THE ONE ROAD ([C-1], the author's word 16.09: the contacts tab archives as the
    /// chats tab does): the row leaves the saved list for the saved archive, the name joins
    /// archivedNames; every screen rereads the vault by the same signal.
    func archiveChat(_ chat: Chat) {
        var chats = storedChats(); var archived = storedArchived()
        if let i = chats.firstIndex(where: { $0.id == chat.id }) { archived.insert(chats.remove(at: i), at: 0) }
        else if !archived.contains(where: { $0.name == chat.name }) { archived.insert(chat, at: 0) }
        archivedNames.insert(chat.name)
        saveStored(chats: chats, archived: archived)
    }
    func unarchiveChat(_ chat: Chat) {
        var chats = storedChats(); var archived = storedArchived()
        // THE ROW COMES BACK WHOLE (the critic 24.09): the archived row's note, a group's photo and members return with
        // it; a bare row set up for the same conversation meanwhile gives way to it, never the other way round.
        let back = archived.first { $0.id == chat.id } ?? chat
        archived.removeAll { $0.id == chat.id }
        chats.removeAll { $0.name == back.name }
        chats.insert(back, at: 0)
        archivedNames.remove(chat.name)
        saveStored(chats: chats, archived: archived)
    }
    /// DELETE — THE ONE ROAD: for both sides the tombstone rides FIRST — over the pipe while it
    /// still lives; the chat is deleted after. The queue spares it; the pipe dies by its
    /// receipt or by term. (The reverse order killed the pipe before the holds check — the
    /// letter was never born. Measured: phone 1 handed it to transit at 18:57:22, phone 2
    /// received nothing since 18:55:48 and reconnected at 18:57:41.) Then the conversation is
    /// erased locally (removeConversationLocally — the saved list, the feed, the queue), the
    /// archive copy and the drafts go with it.
    func deleteChat(_ chat: Chat, forBoth: Bool) {
        // The room with no wire is not deleted (the author's word 17.09): the list always shows it.
        guard !Self.isLocalRoom(chat.name) else { MontanaP2PTrace.mark("delete_refused", "the local room stays"); return }
        // The coin audit's first point (05.10.2026 21:4x MSK): the chat waits while a coin letter of mine is on its way in it -- its
        // erasure would take the letter off the wire with its coins (MontanaDeleteChatSheet says so instead of offering it).
        guard !coinsTravel(chat) else { MontanaP2PTrace.mark("delete_refused", "a coin letter on its way in this chat"); return }
        let peer = chat.convRef
        if forBoth, MontanaConv.holds(peer) {
            MTPipeBook.markDying(peer)   // out of the registrations; the secret stays alive for the tombstone
            MontanaDeliveryEngine.shared.enqueue(to: peer, chat: peer, mid: UUID().uuidString, text: convDelMark, silent: true)
        }
        // Every pipe folded into the conversation dies with it (MTSamePair, 24.09): one person, one conversation, one funeral.
        if forBoth {
            for f in MTSamePair.folded(into: peer) where MontanaConv.holds(f) {
                MTPipeBook.markDying(f)
                MontanaDeliveryEngine.shared.enqueue(to: f, chat: f, mid: UUID().uuidString, text: convDelMark, silent: true)
            }
        }
        var archived = storedArchived()
        if archived.contains(where: { $0.id == chat.id }) { archived.removeAll { $0.id == chat.id }; saveStored(archived: archived) }
        removeConversationLocally(peer)
        LiveDraftState.purgeConversation(peer)
        LiveDraftState.purgeConversation(chat.name)   // drafts are keyed by the screen's chat name too
        MontanaNotify.forgetSuggestions(peer)          // the system no longer offers or remembers it
    }

    /// THE ONE BUILDER OF ROWS ([C-1], the author's word 11.09: «the share sheet is the chat list
    /// one to one, Saved Messages and pins included»). The tab draws these rows and the share
    /// mirror is written from these rows. A second builder stood in `remirrorShareFromStore`
    /// without `order` (deliberately absent from the stored form) — every row sorted as 0, by
    /// name, Saved Messages sunk to the S's — and it ran on every activation, over the tab's
    /// good mirror. `stored` is the saved list (chatsJSON); everything else is the store's own.
    func listRows(stored chats: [Chat]) -> [Chat] {
        // A LOCAL ROOM'S ROW IS THE RECORD'S, NEVER A STORED ROW WITH AN ADDRESS (03.10, T1 17:12:01Z «name_gap conv=Montana»
        // two seconds after the release banner): a stored row of the room carrying its key for an address was asked of the
        // name book, which knows no such person, and the room stood as «Correspondent» in the list and in its own head. The
        // room's row is built below from its record, by its key.
        var result = chats.filter { $0.convId != nil && !Self.isLocalRoom($0.name) && !deletedChats.contains($0.convId ?? "") }
        let known = Set(result.compactMap { $0.convId })
        // A RECOVERED TRANSCRIPT'S ROW IS THE FEED'S TOO (the critic 24.09): its row stood only on the saved shelf, and
        // once written away there the restored conversation was nowhere to be seen (T1: arc:d7f0fd, a week).
        for conv in messages.keys
        where (MontanaConv.holds(conv) || Self.isTranscript(conv) || closedChats.contains(conv)) && !known.contains(conv) && !deletedChats.contains(conv) {
            guard let msgs = messages[conv], !msgs.isEmpty else { continue }
            let last = msgs.max(by: ChatStore.before)
            result.append(Chat(name: conv, lastMessage: last?.text ?? "", time: last?.time ?? "",
                               unread: 0, status: Self.isTranscript(conv) ? "Recovered history" : "Montana address", convId: conv))
        }
        // THE ROWS THEMSELVES EXIST BEFORE THE VAULT OPENS. Both sources above — the saved list
        // and the decrypted history — are behind the device key, so the list was born empty,
        // then five rows, then six: three different pictures inside half a second, measured on
        // the author's phone (rows=0, rows=5, rows=6 within 130ms of each other). The record the
        // first frame CAN read already knows which conversations there are, and its own fields
        // are exactly what a row draws — the name, the preview, the time (stage 9).
        let seeded = Set(result.map { $0.name })
        for (conv, rec) in listState
        where (MontanaConv.holds(conv) || Self.isLocalRoom(conv) || Self.isTranscript(conv) || closedChats.contains(conv))
            && !seeded.contains(conv) && !deletedChats.contains(conv) {
            result.append(Chat(name: conv, lastMessage: rec["p"] ?? "", time: rec["t"] ?? "",
                               unread: 0,
                               status: conv == savedMessagesKey ? "saved messages" : (Self.isMontanaRoom(conv) ? "" : (Self.isTranscript(conv) ? "Recovered history" : "Montana address")),
                               convId: Self.isLocalRoom(conv) ? nil : conv))
        }
        // THE MESH WALL STANDS WHILE THIS PHONE IS ON THE MESH (the author's word 29.09): its row is there while the switch
        // «Findable on the mesh» is on, and gone while it is off -- its words stay on the phone; the order puts it first.
        result.removeAll { Self.isMeshRoom($0.name) }
        if MontanaP2PNode.meshDiscoverable {
            let last = lastLetter(meshRoomKey)
            result.insert(Chat(name: meshRoomKey, lastMessage: last?.text ?? "", time: last?.time ?? "", unread: 0, status: ""), at: 0)
        }
        // SAVED MESSAGES IS ALWAYS A ROW (the author's word 17.09): from the first launch, letters or
        // none, and no deletion mark of the past hides it — the room cannot be deleted (deleteChat).
        if !result.contains(where: { $0.name == savedMessagesKey }) {
            let last = lastLetter(savedMessagesKey)
            result.insert(Chat(name: savedMessagesKey, lastMessage: last?.text ?? "", time: last?.time ?? "",
                               unread: 0, status: "saved messages"), at: 0)
        }
        // Where the first picture's rows came from, said once per launch: the record the frame
        // can read, the saved list behind the vault, the decrypted history. A row that arrives
        // from the second or the third source arrives AFTER the first frame, and that is what
        // shows as a list building itself in stages.
        MontanaP2PTrace.markOnce("list_seed",
            "record=\(listState.count) stored=\(chats.count) history=\(messages.count) shown=\(result.count)")
        // The name a person declared for themselves is substituted by the ONE resolver at
        // display time (`ChatStore.title(for:)`), not by a list transform: an empty mapping
        // stood here — its body was removed while the comment's promise remained.
        //
        // ONE row per address, and every row leaves here carrying where it stands. Two rows with
        // one identity would be a list the renderer cannot tell apart, so a repeat is dropped and
        // said out loud: a list that quietly loses a row is worse than one that reports it.
        var seen = Set<String>()
        var out: [Chat] = []
        for row in result where !archivedNames.contains(row.name) {
            guard seen.insert(row.id).inserted else {
                MontanaP2PTrace.mark("chat_list", "duplicate row dropped id=\(row.id)")
                continue
            }
            var c = row
            c.order = order(of: c.name)
            out.append(c)
        }
        return out
    }

    /// A RECOVERED TRANSCRIPT: a conversation restored from the sealed archive whose key this device no longer holds,
    /// keyed «arc:» and its folder. COMPAT-LOCAL: the key never rides the wire — it names a restored folder here.
    static func isTranscript(_ key: String) -> Bool { key.hasPrefix("arc:") }

    /// THE ONE ORDER of the chat list ([C-1], the author's word 07.09: «the share sheet lives by
    /// the chat's rule»): pinned first, then the freshest, then by name. The list draws by it and
    /// the share mirror writes by it — no second sort anywhere.
    static func listOrder(_ chats: [Chat], pinned: Set<String>) -> [Chat] {
        chats.sorted { a, b in
            let ma = isMeshRoom(a.name), mb = isMeshRoom(b.name)   // the mesh wall stands above every row, pins too (29.09)
            if ma != mb { return ma }
            let pa = pinned.contains(a.name), pb = pinned.contains(b.name)
            if pa != pb { return pa }
            if a.order != b.order { return a.order > b.order }
            return a.name < b.name
        }
    }

    private var mirrorWork: DispatchWorkItem?
    func mirrorChatsToShare(_ unordered: [Chat]) {
        // The rows come in whatever order the caller holds them; the ORDER is the list's own
        // rule, applied here once, Saved Messages always first (the sheet's law).
        // Exactly the tab's order (the author's word 10.09): the same rule, no row moved ahead.
        let list = Self.listOrder(unordered, pinned: pinnedChats)
        // The share grid mirrors the RENDERED chat list ([C-1]): same rows, same order, the
        // same title and face the person just saw — Saved Messages included. A second filter
        // or a second resolver here drifts by construction: that is exactly how the sheet
        // once showed four copies of one correspondent and raw references as titles.
        // THE WORDS ARE READ ON MAIN, THE PICTURES ARE MADE OFF IT (15.16): forty thumbnails —
        // decode, resize, re-encode — and a keychain write stood on the main thread every time
        // the list was saved, the tab's first pass included. Coalesced: one mirror per half second.
        var seen = Set<String>()   // BOUND-OK: local to this one pass, dies with the call, ≤ list size
        let light: [(d: [String: String], face: String?)] = list
            .filter { seen.insert($0.convRef).inserted }   // one row per person
            .prefix(40)
            .map { c in
                let isSaved = c.name == savedMessagesKey
                let shown = isSaved ? String(localized: "Saved Messages", bundle: MTLanguage.bundle)
                                    : MontanaAvatar.spokenName(self.title(for: c))
                // A reference never becomes a title (N-1): the short form carries an ellipsis
                // or repeats the key — such a chat shows the neutral word instead.
                let title = (!isSaved && (shown.contains("…") || shown == c.convRef || shown.isEmpty))
                    ? String(localized: "Correspondent", bundle: MTLanguage.bundle) : shown
                let d: [String: String] = [
                    "name": c.convRef,
                    "title": title,
                    "by": isSaved ? "me" : MTNameBook.namedBy(c.convRef),   // who named them: the extension tells my word from their echo
                    "initial": self.initial(for: c),   // Saved Messages: one's own glyph, as everywhere
                    "colorHex": MontanaAvatar.colorHex(c.name),
                    // the row's block in the list's order, for a letter read while the app sleeps (MTShareOrder.raise)
                    "rank": Self.isMeshRoom(c.name) ? "0" : (pinnedChats.contains(c.name) ? "1" : "2")
                ]
                return (d, self.avatarFor(c))
            }
        MontanaP2PTrace.markChanged("share_mirror", "n=\(light.count) order=\(MTShareOrder.print(light.map { $0.d["name"] ?? "" }))", every: 900)
        // One's own face is taken here, on the main thread its one owner lives on (MontanaSelfFace), and rides into the work.
        let own = MontanaSelfFace.image
        mirrorWork?.cancel()
        let w = DispatchWorkItem {
            let payload: [[String: String]] = light.map { row in
                var d = row.d
                if let ref = row.face, let t = ChatStore.avatarThumbBase64(ref: ref) { d["thumb"] = t }   // real photo → thumbnail
                else if row.d["name"] == savedMessagesKey, let own,
                        let t = ChatStore.thumbBase64(own) { d["thumb"] = t }   // Saved Messages: one's own photo
                return d
            }
            if let d = try? JSONSerialization.data(withJSONObject: payload) { MontanaKeychain.set("shareChats", d) }
        }
        mirrorWork = w
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5, execute: w)
    }

    // Mini avatar thumbnail of the chat (only if a real photo exists) for the extension picker;
    // otherwise nil → the extension draws a circle with the initial (colorHex).
    private static func avatarThumbBase64(ref: String) -> String? {
        let src: UIImage? = UIImage(named: ref) ?? docImage(ref)
        guard let img = src else { return nil }
        return thumbBase64(img)
    }
    private static func thumbBase64(_ img: UIImage) -> String? {
        let side: CGFloat = 120
        let scale = min(1, side / max(img.size.width, img.size.height))
        let sz = CGSize(width: img.size.width * scale, height: img.size.height * scale)
        let small = UIGraphicsImageRenderer(size: sz).image { _ in img.draw(in: CGRect(origin: .zero, size: sz)) }
        var q: CGFloat = 0.7
        var data = small.jpegData(compressionQuality: q)
        while let dd = data, dd.count > 16000, q > 0.2 { q -= 0.15; data = small.jpegData(compressionQuality: q) }
        guard let out = data, out.count <= 16000 else { return nil }
        return out.base64EncodedString()
    }

    // Receiving from the «Share» menu: the extension already sealed and uploaded the blobs and
    // assembled the manifest. The host sends the manifest through the E2E ratchet and shows
    // a local echo (re-fetching the blob back — it is already in the local store, content-addressed).
    @MainActor
    private static let shareIngestLock = NSLock()
    func ingestPendingShares() {
        // Reading and deleting are one indivisible step. The pickup is called from two
        // activation sites; both used to read the list BEFORE the deletion and each processed
        // it — a double bubble.
        // READ, NOT TAKEN (16.09): the pending shares used to be read and deleted in one step, before a
        // single row was born — a process killed in the seconds after (T1 18:25:54Z: six tracks
        // re-created in memory, the reinstall seven seconds later) left the sender's chat without its
        // own letters while the sheet had already sent them. A share leaves the keychain only when its
        // rows are journaled; the double pickup from two activation sites is refused by the set of
        // shares this life already took.
        Self.shareIngestLock.lock()   // LOCK-OK: the pending-share record is read and the taken set marked as one step (two activation sites)
        let all = MontanaKeychain.get("pendingShare").flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [[String: Any]] } ?? []
        var fresh: [(key: String, item: [String: Any])] = []
        var waiting = 0
        for item in all {
            // IN THE SHEET'S HAND STILL (20.09, the critic): a record the sheet has not passed is not
            // ours — its flags are not final. A record older than the sheet's lease belongs to a dead
            // sheet and is taken as it lies (the shelf road, the resend). An older sheet wrote no owner.
            if (item["owner"] as? String) == "sheet",
               Date().timeIntervalSince1970 - ((item["born"] as? Double) ?? 0) < Self.sheetLease { waiting += 1; continue }
            let k = Self.shareKey(item); if Self.sharesTaken.insert(k).inserted { fresh.append((k, item)) }
        }
        Self.shareIngestLock.unlock()
        if 0 < waiting { MontanaP2PTrace.mark("share_wait", "rows=\(waiting) still in the sheet's hand") }
        guard !fresh.isEmpty else { return }
        MontanaP2PTrace.mark("share_ingest", "rows=\(fresh.count)")
        MontanaHandoff.sweep()
        for (shareKey, item) in fresh {
            let peer = (item["peer"] as? String) ?? ""    // address = messages key (chat.name = convRef)
            guard !peer.isEmpty else { Self.shareDrop(shareKey); continue }
            let caption = (item["caption"] as? String) ?? ""
            let items = (item["items"] as? [[String: Any]]) ?? []
            Task { @MainActor in
                // ONE sending path ([C-1]): everything a share produced goes through the same
                // delivery engine as a message typed in the chat — queue, retries, wake with a
                // banner, receipt. The extension has already uploaded the pieces to the node;
                // what travels here is the letter.
                var captionCarried = false
                for one in items {
                    let kind = (one["kind"] as? String) ?? ""
                    let itemMid = (one["mid"] as? String) ?? UUID().uuidString
                    let alreadySent = (one["sent"] as? Bool) ?? false
                    if kind == "text" {
                        guard let t = one["text"] as? String, !t.isEmpty else { continue }
                        // Saved Messages is this device writing to itself: the letter is local,
                        // no network leg exists for it — same as sending to Saved from a chat.
                        if peer != savedMessagesKey {
                            // The SAME mid the extension already rang with: the engine leg is
                            // the guarantee, the node dedups the banner, the receiver the letter.
                            MontanaDeliveryEngine.shared.enqueue(to: peer, chat: peer,
                                                                 mid: itemMid, text: t, silent: alreadySent)
                        }
                        // BORN AT THE RUNG THE SHEET PROVED (the author's word 13.09): the sheet's
                        // «200» means the node holds the letter — the row is «sent» from birth; the
                        // engine's silent leg is the guarantee, not a first send to wait for.
                        self.appendTextEcho(peer, t, mid: itemMid, proven: alreadySent)
                        continue
                    }
                    guard var manifest = one["manifest"] as? [String: Any] else { continue }
                    // The caption rides INSIDE the first media manifest — the recipient sees one
                    // bubble with a caption, exactly as when sent from the chat.
                    if !caption.isEmpty, !captionCarried {
                        manifest["cap"] = caption; captionCarried = true
                    }
                    guard let json = try? JSONSerialization.data(withJSONObject: manifest),
                          let body = String(data: json, encoding: .utf8) else { continue }
                    // THE HANDOFF SHELF (17.09): the sheet's bytes are already on this device. Moved into the
                    // media store under the name the manifest computes, so the road below finds the file on
                    // disk and downloads nothing (T1 21:56Z used to fetch its own 90 MB back over cellular).
                    let uploaded = (one["uploaded"] as? Bool) ?? true   // a record of an older sheet carries no flag: uploaded, or dropped before it
                    var handed: String? = nil
                    let mkind = (manifest["k"] as? String) ?? ""
                    let fileName = self.mediaFileName(kind: mkind, ext: (manifest["e"] as? String) ?? "", seed: "mid:" + itemMid,
                                                      round: (manifest["r"] as? Bool) ?? false, badge: manifest["rb"] as? String)
                    if let src = one["src"] as? String, !mkind.isEmpty {
                        let took = self.takeShelf(src: src, as: fileName)
                        if took != nil { handed = fileName }
                        MontanaP2PTrace.mark("share_handoff", mid: itemMid, took ?? "shelf file missing — the download road")
                    }
                    // THE BUBBLE FIRST — the sender's chat must hold the row before ANY network
                    // step; a letter compose that waits on the node must never hold it hostage
                    // (precedent 29.08: cold start + manifest upload → no bubble at all).
                    // THE SAME handler as for incoming media: the bubble and the conversation
                    // appear at once, the frame comes from the manifest preview, the file
                    // follows. The letter's mid IS the intent's name; the row's letter name is
                    // «mid:»-prefixed — receipts settle by it, the mirror law matches by it.
                    if uploaded || handed != nil {
                        self.reconstructMedia(peer, body: body, isFromMe: true, time: "",
                                              msgId: "mid:" + itemMid, senderRef: nil, restore: true,
                                              transport: MontanaP2PNode.shared.transport(to: peer)?.rawValue,
                                              proven: alreadySent && uploaded)   // born at the rung the sheet proved (13.09)
                    } else if !(self.messages[peer] ?? []).contains(where: { $0.msgId == "mid:" + itemMid }) {
                        // Nothing on the node and nothing on the shelf: the row is still born — red, honestly.
                        self.appendMediaPlaceholder(peer, kind: mkind, name: fileName, docName: manifest["n"] as? String,
                                                    caption: (manifest["cap"] as? String) ?? "", isFromMe: true, time: "",
                                                    msgId: "mid:" + itemMid, senderRef: nil,
                                                    transport: MontanaP2PNode.shared.transport(to: peer)?.rawValue, proven: false)
                    }
                    if let handed { self.fillMedia(peer, name: handed) }   // the file is whole: duration, caches, no ring
                    if peer != savedMessagesKey {
                        if !uploaded {
                            // THE SHEET COULD NOT UPLOAD (17.09, the critic): the pieces never reached the node and
                            // no letter left — the row already stands in the sender's chat; the app walks the chat's
                            // own media road from the shelf file under the same name (a new manifest, the upload,
                            // the letter, the receipt on this very row). No shelf file: the row is red at once.
                            if let handed, !mkind.isEmpty {
                                MontanaP2PTrace.mark("share_resend", mid: itemMid, "the sheet's upload failed — the app sends from the shelf")
                                self.sendMediaToPeer(peer: peer, source: .file(attachmentURL(handed)), kind: mkind,
                                                     ext: (manifest["e"] as? String) ?? "", docName: manifest["n"] as? String,
                                                     progressKey: handed, caption: (manifest["cap"] as? String) ?? "",
                                                     statusChat: peer, statusFile: handed, forceMid: itemMid)
                            } else {
                                MontanaP2PTrace.mark("share_lost", mid: itemMid, "no upload and no shelf file — the row is red")
                                self.setMediaRefused(peer, file: fileName, because: .fileUnreadable)
                            }
                            continue
                        }
                        // The letter is composed ONCE ([C-1]): the sheet already composed and
                        // sent it — the engine re-sends the SAME bytes (same mid, same mref) as
                        // the guarantee leg. Only a sheet killed before composing leaves the
                        // compose to us, through the same one owner.
                        let letter: String
                        if let l = one["letter"] as? String, !l.isEmpty { letter = l }
                        else {
                            letter = await MontanaMedia.manifestLetter(json, putBlob: {
                                await MontanaWakePush.putBlob($0, data: $1)
                            })?.letter ?? (mediaMark + body)
                        }
                        MontanaDeliveryEngine.shared.enqueue(to: peer, chat: peer,
                                                             mid: itemMid, text: letter, silent: alreadySent)
                    }
                }
                if !caption.isEmpty, !captionCarried {
                    let capMid = UUID().uuidString
                    if peer != savedMessagesKey {
                        MontanaDeliveryEngine.shared.enqueue(to: peer, chat: peer,
                                                             mid: capMid, text: caption, silent: false)
                    }
                    self.appendTextEcho(peer, caption, mid: capMid)
                }
                Self.shareDrop(shareKey)   // every row of this share is journaled — it leaves the keychain
            }
        }
    }
    private static var sharesTaken = Set<String>()   // under shareIngestLock: the shares this life took
    /// How long a record may stay in the sheet's hand before the app treats the sheet as dead.
    private static let sheetLease: Double = 120

    /// ONE SHELF, ONE TAKING (20.09, the critic): a share to N people lays ONE file on the shelf and names
    /// it in every row. The first row moves it into the store; every other row of the same share gets the
    /// same bytes under its own name — a hard link, the road a forward takes. The shelf used to be taken by
    /// the first row alone, and the rows behind it downloaded the sender's own picture back from the node
    /// (T1 17:43Z 19.09: one «on disk», three «shelf file missing»). Returns what happened, nil when nothing
    /// is there to take.
    private func takeShelf(src: String, as name: String) -> String? {
        let key = "handoffTaken"
        var taken = (UserDefaults.standard.dictionary(forKey: key) as? [String: String]) ?? [:]
        if let from = MontanaHandoff.url(src), FileManager.default.fileExists(atPath: from.path) {
            guard MontanaMediaStore.adopt(from: from, name: name) else { return nil }
            taken[src] = name
            if 64 < taken.count { taken = Dictionary(uniqueKeysWithValues: Array(taken).suffix(64)) }
            UserDefaults.standard.set(taken, forKey: key)
            return "on disk"
        }
        if let first = taken[src], MontanaMediaStore.clone(first, as: name) { return "linked to the first row's file" }
        return nil
    }

    /// RECEIPTS THAT FOUND NO ROW (17.09, the critic): a receipt may land before its own row is born — 13 ms
    /// on T1 05:46:14Z, the row coming back from the node's box after it. The name is kept (the newest 64);
    /// a row of one's own born later under it is born «delivered», not «sending» — and never turns red.
    private lazy var orphanDelivered: [String] =
        MontanaLocalVault.getDecrypted("orphanDelivered").flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
    private func noteOrphanDelivered(_ mid: String, keep: Bool) {
        orphanDelivered.removeAll { $0 == mid }
        if keep { orphanDelivered.append(mid); if orphanDelivered.count > 64 { orphanDelivered.removeFirst(orphanDelivered.count - 64) } }
        if let d = try? JSONEncoder().encode(orphanDelivered) { MontanaLocalVault.setEncrypted("orphanDelivered", d) }
    }
    /// The rung a row of one's own is born on: what the sheet proved, raised by a receipt already held.
    func ownBornStatus(mid: String?, proven: Bool) -> DeliveryStatus {
        let bare = mid.map { $0.hasPrefix("mid:") ? String($0.dropFirst(4)) : $0 } ?? ""
        if !bare.isEmpty, orphanDelivered.contains(bare) {
            noteOrphanDelivered(bare, keep: false)
            MontanaP2PTrace.mark("born_delivered", mid: bare, "its receipt had landed before the row")
            return .delivered
        }
        return proven ? .sent : .sending
    }
    private static func shareKey(_ item: [String: Any]) -> String {
        let mids = ((item["items"] as? [[String: Any]]) ?? []).compactMap { $0["mid"] as? String }
        let body = mids.isEmpty ? String((try? JSONSerialization.data(withJSONObject: item, options: [.sortedKeys]))?.hashValue ?? 0) : mids.joined(separator: ",")
        return ((item["peer"] as? String) ?? "") + "|" + body
    }
    /// The share leaves the keychain — after its rows are on disk ([C-1]: the one remover).
    private static func shareDrop(_ key: String) {
        shareIngestLock.lock(); defer { shareIngestLock.unlock() }   // LOCK-OK: read-modify-write of the pending-share record
        guard let d = MontanaKeychain.get("pendingShare"),
              var arr = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]] else { return }
        let before = arr.count
        arr.removeAll { shareKey($0) == key }
        guard arr.count != before else { return }
        if arr.isEmpty { MontanaKeychain.delete("pendingShare") }
        else if let out = try? JSONSerialization.data(withJSONObject: arr) { MontanaKeychain.set("pendingShare", out) }
    }

    // Local echo of text to the sender (chat key = peer address).
    @MainActor
    private func appendTextEcho(_ chat: String, _ text: String, mid: String, proven: Bool = false) {
        // The row carries the LETTER's name: receipts land on it, and the mirror law (M-1)
        // sees a living row behind the queue item. A nameless echo was invisible to both.
        // A share taken twice (a re-ingest after a kill mid-way) bears one row, not two.
        guard !(messages[chat] ?? []).contains(where: { $0.msgId == "mid:" + mid }) else { return }
        let msg = Message(text: text, isFromMe: true, time: nowHHMM(),
                          deliveryStatus: Self.isLocalRoom(chat) ? .sent : ownBornStatus(mid: "mid:" + mid, proven: proven),   // born at the clock, like every own letter — the ladder earns the checkmarks; no wire, or a node that already took it — born at «sent»
                          msgId: "mid:" + mid)
        placeRow(chat, msg)
        MTRowJournal.put(chat, msg)   // on disk before the share leaves its box (16.09)
        bump(chat)
        Task { @MainActor in self.noteListState(chat, last: self.lastLetter(chat)) }   // the list record follows the newest (stage 9, 17.09)
    }

    // apply an incoming reaction: find the message by msgId (or by text) and add/remove the emoji
    // ONE ROAD FOR EVERY KIND OF LETTER (the author's word 20.09): the answer names the letter by its
    // NAME (mid) — the same on both sides for a text, a picture, a video, a voice, a file, a forward.
    // The words are asked only for a letter that came nameless (an older build); a letter with a name
    // that is not here is lost aloud, never guessed by its words onto a twin.
    func applyReaction(_ chat: String, sid: String, txt: String, emoji: String, add: Bool, at: Double? = nil) {
        guard var list = messages[chat] else { MontanaP2PTrace.mark("react_rx", "lost — no chat sid=\(sid.prefix(12))"); return }
        var idx: Int? = nil
        var by = "name"
        if !sid.isEmpty { idx = list.firstIndex { $0.msgId == sid } }
        else if !txt.isEmpty { idx = list.lastIndex { $0.text == txt }; by = "words" }
        guard let i = idx else { MontanaP2PTrace.mark("react_rx", "lost — no row sid=\(sid.prefix(12)) by=\(by)"); return }
        MontanaP2PTrace.mark("react_rx", "\(emoji) \(add ? "add" : "del") by=\(by)")
        if add {
            if let old = list[i].peerReact, old != emoji,
               let k = list[i].reactions.firstIndex(of: old) { list[i].reactions.remove(at: k) }
            if list[i].peerReact != emoji { list[i].reactions.append(emoji) }
            list[i].peerReact = emoji
        } else {
            if let k = list[i].reactions.firstIndex(of: emoji) { list[i].reactions.remove(at: k) }
            if list[i].peerReact == emoji { list[i].peerReact = nil }
        }
        messages[chat] = list
        MTReactionBoard.shared.show(list[i])   // the face of the letter, in the same move
        noteReaction(chat, add ? emoji : nil, mine: false, on: list[i], at: at)   // the row wears the answer, at its own birth
    }
    /// THE PIN LANDS ON THE SAME LETTER (the author's word 22.09: both see it): the letter by its wire
    /// name, by its words as the fallback; pinned or unpinned here as the peer did; and the person is
    /// told by a banner of the app's own — unless the chat is open, where the pinned plate itself is the word.
    func applyPinFromControl(_ chat: String, body: String) {
        guard let d = body.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let op = obj["op"] as? String else { return }
        let sid = (obj["sid"] as? String) ?? "", txt = (obj["txt"] as? String) ?? ""
        guard let list = messages[chat] else { MontanaP2PTrace.mark("pin_rx", "lost — no chat sid=\(sid.prefix(12))"); return }
        var found: Message? = nil
        if !sid.isEmpty { found = list.first { $0.msgId == sid } }
        if found == nil, !txt.isEmpty { found = list.last { $0.text == txt } }
        guard let m = found else { MontanaP2PTrace.mark("pin_rx", "lost — no row sid=\(sid.prefix(12)) op=\(op)"); return }
        MontanaP2PTrace.mark("pin_rx", "\(op) by=\(sid.isEmpty ? "words" : "name")")
        if op == "pin" {
            pin(chat, m.id)
            if openConv != chat { MontanaNotify.presentPinned(from: chat, chat: chat, words: MTRowLetter.words(m.text), sid: sid) }
        } else {
            unpin(chat, m.id)
        }
    }
    /// `at` — the reaction word's own birth (its sender's clock), carried to the row's record.
    func applyReactionFromControl(_ chat: String, body: String, at: Double? = nil, mine: Bool = false) {
        guard let d = body.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let emoji = obj["e"] as? String, let op = obj["op"] as? String else { return }
        // COINS GIVEN ON A LETTER (the author's word 03.10 13:40): the reaction's own road, its own op -- credited, never an emoji.
        if op == "coin" {
            if !mine, let c = obj["c"] as? Int, let r = obj["r"] as? String, let sid = obj["sid"] as? String, !sid.isEmpty {
                let credit = { MainActor.assumeIsolated { MTCoinSend.reacted(c, ref: r, on: sid, from: chat) } }
                if Thread.isMainThread { credit() } else { DispatchQueue.main.async(execute: credit) }
            }
            return
        }
        applyReaction(chat, sid: (obj["sid"] as? String) ?? "", txt: (obj["txt"] as? String) ?? "",
                      emoji: emoji, add: op == "add", at: at)
    }


    // Sending a message THROUGH the network layer.
    // We show it on screen immediately with the «sending» status (the clock),
    // and the delivery engine carries it until the peer's receipt confirms it.
    /// THE STANDARD OF ONE TEXT BUBBLE (the author's word 11.09: «a standard of characters in one
    /// bubble, three times the old»): long input is cut into MESSAGES — a window of up to this many
    /// CHARACTERS, backing off to the last line break or period, each piece its own letter. It
    /// used to be 1500 bytes — the size of a piece that fits the wake envelope whole, which cut
    /// a Russian letter at 750 characters. A piece that does not fit the envelope rides the long-
    /// letter road that has been there since 15.37: the body as a sealed blob, the envelope with
    /// an invisible reference — both builds at Apple (1344, 1348) resolve it ([P2P-COMPAT]).
    static let sendPieceChars = 4500
    static func breakOutgoingText(_ text: String) -> [String] {
        guard text.count > sendPieceChars else { return [text] }
        var out: [String] = []
        var rest = Substring(text)
        while !rest.isEmpty {
            if rest.count <= sendPieceChars { out.append(String(rest)); break }
            var end = rest.startIndex
            var n = 0
            var cut: Substring.Index? = nil
            while end < rest.endIndex, n < sendPieceChars {
                let ch = rest[end]
                n += 1
                end = rest.index(after: end)
                if ch == "\n" || ch == "." { cut = end }
            }
            let sliceEnd = cut ?? end
            out.append(String(rest[rest.startIndex..<sliceEnd]).trimmingCharacters(in: .whitespacesAndNewlines))
            rest = rest[sliceEnd...]
        }
        return out.filter { !$0.isEmpty }
    }

    @MainActor
    @discardableResult
    /// `linkCard` — the card the person SAW above the field (the critic 22.09); `noLinkCard` — the
    /// person dropped it with the cross, and this letter rides with a bare link, reading nothing.
    func send(text: String, chat: String, convRef: String? = nil, replyText: String? = nil, replyToId: MID? = nil, replyWireMid: String? = nil, silent: Bool = false,
              linkCard: String? = nil, noLinkCard: Bool = false, minted given: (mid: String, ms: Int64)? = nil) -> Message {
        // A SERVICE REFERENCE IS NOT A LETTER ([P2P-COMPAT], 07.09 20:14): a row that still holds
        // a long-letter reference (written raw by an older build) was forwarded as text, and the
        // peer on the store build drew «LB:{…}» in a bubble. No road sends a reference as words.
        if text.hasPrefix(MontanaWakePush.letterBlobMark) {
            MontanaP2PTrace.mark("send_refused", "raw-reference chat=\(String(chat.prefix(10)))")
            return Message(text: "", isFromMe: true, time: nowHHMM(), senderRef: nil)
        }
        // A COIN LETTER LEAVES BY ITS ONE DOOR (the author's words 06.10.2026 12:3x-12:4x MSK: «close the double spends»): a text that
        // reads as a coin letter goes only when MTCoinSend.transfer sends it, its coins taken first. A copy pasted from a bubble or
        // typed would be credited by its reader with nothing taken here -- a coin printed.
        if text != MTCoinLetter.born, MTCoinLetter.parse(text) != nil {
            MontanaP2PTrace.mark("send_refused", "coin letter outside its door chat=\(String(chat.prefix(10)))")
            return Message(text: "", isFromMe: true, time: nowHHMM(), senderRef: nil)
        }
        // AN EMPTY ADDRESS IS NO ADDRESS (15.48, the author's word 08.09: «a retry mark on a letter
        // to Saved Messages»). Saved Messages has no correspondent; the chat handed «» instead of
        // nil, the letter was queued to nobody, the engine found no pipe for nobody and painted it
        // red. One rule here, for every caller: a letter without an address is local and sent.
        let convRef = (convRef?.isEmpty == true) ? nil : convRef
        // Slicing comes BEFORE everything else: the quoted reply rides with the first piece only.
        let pieces = Self.breakOutgoingText(text)
        if pieces.count > 1 {
            MontanaP2PTrace.mark("send_split", "pieces=\(pieces.count) chars=\(text.count) bytes=\(text.utf8.count)")
            var first: Message? = nil
            for (i, p) in pieces.enumerated() {
                let m = send(text: p, chat: chat, convRef: convRef,
                             replyText: i == 0 ? replyText : nil,
                             replyToId: i == 0 ? replyToId : nil,
                             replyWireMid: i == 0 ? replyWireMid : nil, silent: silent,
                             linkCard: i == 0 ? linkCard : nil,
                             noLinkCard: i == 0 ? noLinkCard : false)
                if first == nil { first = m }
            }
            return first ?? send(text: String(text.prefix(1)), chat: chat, convRef: convRef, silent: silent,
                                 linkCard: linkCard, noLinkCard: noLinkCard)
        }
        // A GROUP'S LETTER HAS ITS OWN CARRIER (MTGroup): one copy per receiver, each under a name of its own, the receipts folded
        // into the group's row -- never one letter to an address the group does not have.
        if MTGroup.isKey(chat) {
            return MTGroup.shared.send(text, in: chat, replyText: replyText, replyToId: replyToId, replyWireMid: replyWireMid, store: self)
        }
        let minted = given ?? Self.mintMid()
        let mid = minted.mid
        // If the peer is on the Wi-Fi mesh, the message is delivered directly (instant) — mark it
        // sent immediately instead of leaving a clock while an unreachable peer times out.
        let meshReady = MontanaP2PNode.shared.canReach(chat)
        let msg = Message(text: text, isFromMe: true, time: nowHHMM(),
                          replyText: replyText,
                          deliveryStatus: (convRef == nil || meshReady) ? .sent : .sending,
                          msgId: "mid:\(mid)",
                          senderRef: nil,
                          createdAt: Double(minted.ms) / 1000.0, replyToId: replyToId,
                          transport: MontanaP2PNode.shared.transport(to: convRef ?? chat)?.rawValue)
        append(chat, msg)
        if Self.isMeshRoom(chat) { MTMeshRoom.say(text) }   // the mesh wall's words ride the radio to everyone on the mesh (29.09)
        // history backup — at the sendText E2E checkpoint (single for all types), not here
        if let sid = convRef {
            // Stage 2 (spec s.3 §13): ONE reachability-driven delivery engine owns the send lifecycle —
            // first attempt, retry by reachability (.montanaP2PPeerUp) + backstop tick, dequeue ONLY on a
            // delivery receipt. Replaces the three legacy retry paths (scheduleDeliveryCheck/awaitingSweep/outbox).
            // The letter NEVER waits for anything — a preview card catches up behind it.
            // A PERSON'S LETTER RINGS (the author's word 04.10 23:46: «notifications come only when Montana is opened»). While both
            // stand in the chat the standing road carries every letter and the bell stays quiet (16.6.14); the bell wakes only the
            // one who is away. A quiet lane for every letter born while a coin was on anywhere left that one with no banner.
            MontanaDeliveryEngine.shared.enqueue(to: sid, chat: chat, mid: mid, text: text, silent: silent,
                                                 quoteText: replyText, quoteMid: replyWireMid)
        }
        // THE CARD HAS ONE OWNER FOR EVERY ROOM (the author's word 22.09: «in Saved Messages — nothing»).
        // It used to live INSIDE the branch that speaks to a correspondent, so a letter to oneself — a
        // room with no correspondent — never grew a card at all. The card belongs to the LETTER: it is
        // taken here for any room, and only the copy for the other side needs an address.
        MTLinkCards.shared.attend(store: self, chat: chat, mid: mid, text: text, sid: convRef,
                                  quoteText: replyText, quoteMid: replyWireMid,
                                  seen: linkCard, refused: noLinkCard)
        return msg
    }

    /// A letter in flight refused by a word (MTRefusal): the delivery engine's one road into red. The row goes red through putOut,
    /// and a group's copy turns its group's row (MTGroup.copyRefused).
    @MainActor
    func settleRefused(conv pipe: String, mid: String, because why: MTRefusal) {
        if MTGroup.shared.copyRefused(mid, store: self) { return }
        let conv = MTSamePair.root(pipe)
        guard let i = messages[conv]?.firstIndex(where: { $0.msgId == "mid:\(mid)" }) else { return }   // SILENT-OK: a letter without a bubble (settleByMid below)
        putOut(conv, i, because: why)
    }

    // One move, one implementation: a message still in flight settles into the given state.
    // Red is not among them: it asks for a word (settleRefused above).
    @MainActor
    func settleByMid(conv pipe: String, mid: String, _ status: DeliveryStatus) {
        if MTGroup.shared.copySettled(mid, store: self) { return }   // a group's copy settles the group's row (MTGroup)
        let conv = MTSamePair.root(pipe)   // a letter queued on a pipe since folded settles its row in the conversation (24.09)
        // SILENT-OK: letters without a bubble are ordinary and not a delivery path. Receipts,
        // the name, the avatar, the tombstone and live typing ride the same engine, but the
        // feed holds them nowhere by construction, and there is NOTHING to change state on.
        // Real delivery is visible to the person as the ladder on the bubble itself.
        guard let i = messages[conv]?.firstIndex(where: { $0.msgId == "mid:\(mid)" }) else { return }
        // BACK FROM RED GOES THROUGH THE ONE ROAD BACK (1635): the ladder only climbs, so a retry
        // that asked it for «sending» was refused and the bubble stayed red under the person's finger
        // (T1 19:49:12Z: four resend_tap lines, the engine knocking, the row never leaving red).
        if status == .sending { restartSend(conv, i) } else { advance(conv, i, to: status) }
    }

    /// A same-mid copy arrived carrying the link card — the row learns it (enrich, no duplicate).
    /// THE PICTURE CATCHES UP TOO (the critic 22.09): the envelope leg rides without the picture (the
    /// 2048 cap), so a letter that came by that road carried a faceless card forever — the mesh copy
    /// behind it now fills the picture in, and only the picture; nothing else of a standing card moves.
    @MainActor
    func enrichLinkPreview(_ chat: String, sid: String, lp: String) {
        guard let i = messages[chat]?.firstIndex(where: { $0.msgId == sid }) else { return }
        guard let standing = messages[chat]?[i].linkPreview else {
            messages[chat]?[i].linkPreview = lp
            return
        }
        guard let old = MTLinkPreview.parse(standing), old.i == nil,
              let fresh = MTLinkPreview.parse(lp), fresh.i != nil, fresh.u == old.u else { return }
        var filled = old
        filled.i = fresh.i; filled.w = fresh.w; filled.h = fresh.h; filled.p = fresh.p ?? old.p
        if let json = filled.json {
            messages[chat]?[i].linkPreview = json
            MontanaP2PTrace.mark("lp_picture", "the card learned its picture sid=\(String(sid.prefix(12)))")
        }
    }

    // Change the delivery status of a specific message (and set msgId).
    @MainActor
    func updateStatus(chat: String, id: MID, status: DeliveryStatus, msgId: String? = nil) {
        guard let i = messages[chat]?.firstIndex(where: { $0.id == id }) else { return }
        if status == .sending { restartSend(chat, i) } else { advance(chat, i, to: status) }
        if let s = msgId { messages[chat]?[i].msgId = s }
    }

    // ── NETWORK LAYER ──
    // Mesh messaging channel (E2E over the Wi-Fi-direct/BLE mesh). See makeChannel().
    var channel: MessagingChannel = makeChannel()

}

// ════════════════════════════════════════════════════════════
// DELIVERY LAYER (abstraction) — «a single-standard socket».
// The contract the screens and ChatStore speak: what they may ask of delivery.
// The one thing behind it is the mesh — this phone as a node among nodes.
// ════════════════════════════════════════════════════════════
protocol MessagingChannel {
    // who «I» am — the address computed out of the seed, asked of nobody
    // list of my dialogs
    func fetchChats() async throws -> [Chat]
    // history of a single chat
    func fetchMessages(chatId: String) async throws -> [Message]
    // send a message; the server returns it already with its serverId
    func send(text: String, chatId: String, mid: String, silent: Bool) async throws -> Message
    // «live wire»: calls onNew when a new message arrives
    func subscribe(chatId: String, onNew: @escaping (Message) -> Void)
}

// ════════════════════════════════════════════════════════════
// ACCOUNT — who «I» am. The answer is computed, not issued: the address comes out of the seed,
// and nobody hands it over. Two phones holding different seeds hold different references, and that
// is the whole of what separates «own» messages from «others'».
// ════════════════════════════════════════════════════════════
// SINGLE SOURCE OF TRUTH for what this app keeps and whose it is. Every value of the settings store is
// named HERE, once and in one class ([C-1]): the account's content (reset on a change of seed, carried by
// a copy), the person's settings (kept through a change of seed, carried by a copy), and this device's own
// (never carried, each for a reason named below). Switching an identity and forgetting one go only through
// SeedScope, and tools/mt-copy-scope-check.py refuses a commit that writes a key named nowhere — so a new
// value cannot slip past a copy unseen (the author, 23.09: «check that every setting reaches the copy too —
// the VPN, the telemetry, everything in the app»; 26 values of the person and every setting did not).
enum SeedScope {
    // Account content: conversations, profile, sync. Reset on account SWITCH.
    static let dataKeys = ["chatsJSON", "archivedJSON", "chatMessages", "pinnedMessages",
                           "mt.keep.owner",   // the keepers of my copy and its generation (MTKeeping): the person's own
        "scheduledMsgs", "recentOrder", "orderSeq", "readChats", "pinnedChatsList", "forcedUnread",
        "mutedChats", "archivedNames", "deletedChats", "peerAvatars", "peerNames", "peerSeenAt", "peerGoneAt",
        "userName", "userLastName", "userUsername", "userBio", "userBirthday", "profileBio", "profileLink", "peerAbout",
        "statusEmoji", "profileColorIndex", "bubbleColorIndex", "avatarData", "avatarGallery",
        "myStoryMedia", "viewedStories", "storiesSeededAt", "lastSeenMap", "draftsMap", "muteFlagsMap", "blockFlagsMap", "syncLast", "syncSeen", "syncUploaded",
        // THE PEOPLE AND WHAT THE PERSON SAID OF THEM, THE NAME AND THE STANDING LINK (23.09): none of these
        // reached a copy, and each outlived a change of seed — the book of contacts with its pins, names and
        // faces set by hand, the peers' nicknames and the moments they were spoken, the block list, the peers'
        // read marks, the verified conversations, the letters deleted for everyone, the name held in the
        // network with the blinding factor that alone opens its commitment, the permanent link and its cards,
        // the sticker set, the moving pictures kept and the clips liked.
        "mtContacts", "pinnedContacts", "archivedContacts", "manualNames", "manualPhotos", "peerUsernames",
        "declaredAt", "blockedChats", "peerReadMap", "callsSeenAt", "deletedMids", "mtVerifiedConversations",
        "mt.name", "rdvPermanent", "cardKeys", "rdvCards", "rdvCurrent", "rdvCurrentBorn",
        "montana.stickers.mine", "montana.stickers.packid", "montana.stickers.packs", "montana.stickers.passports",
        "montana.stickers.givers", "montana.stickers.ids", "montana.gifs.mine", "videoLikes",
        // WHAT THE RESTORE PASS FOUND STILL MISSING (the critic, 23.09, «restore on T3 and see no difference»): the
        // pictures already saved to the library (or every one wears its badge again), the handles a call-back
        // from the system's Recents resolves by, the control letters already applied (or the box's repeats
        // apply again), the daily links the correspondents handed over, the downloads waiting to resume, the
        // moving pictures that already played their cycles, and of every correspondence what the archive's
        // head does not carry: when it last lived, whether it is dying, a first letter still unanswered with
        // the point it knocks at, the contact root a name was met by.
        "savedToPhotos", "callHandleTokens", "controlMids", "peerRdvLinks", "peerRdvLinks.b", "pendingMediaJSON",
        "gifFirstRun", "pipeTouched", "pipeDying", "pipeFirstCiphertexts", "pipeFirstRoots", "pipeFirstMeta",
        "pipeNameRoots",
        // THE WALL (24.09): my own wall's posts with their peers and marks, and the posts whose files I keep; the
        // correspondents whose build speaks the wall and the version each was carried; the people the wall's two rules
        // name — references of this identity's correspondences, gone with it.
        MTBoard.mineKey, MTBoard.ownedKey, MTBoard.keptKey, MTBoard.capKey, MTBoard.sentKey,
        MTBoard.draftsKey, MTBoard.goingKey,   // a post being written and a post on its way (25.09): the person's own words
        MTBoard.viewedKey,   // the posts this identity named to their walls as seen, each once (06.10)
        MTBoardRule.allowKey, MTBoardRule.denyKey, MTBoardRule.sightAllowKey, MTBoardRule.sightDenyKey,
        // WHERE A LONG LISTEN STOPPED (26.09): the moment a long track or voice of this identity's letters stopped (MTPlayPlaces).
        "playPlaces",
        // THE PERSON'S OWN BUSINESS CARD (28.09): the name, the phone, the e-mail and the other ways to reach them, sealed.
        MontanaBusinessCard.vaultKey,
        // THE TRAINING GAME WITH THE PHONE'S OWN ENGINE (29.09): the person's moves and the engine's, as the game's letters.
        MTChessComputer.gameKey,
        // THE GROUPS AND CHANNELS (05.10): the ones this person owns or was invited to, with the pipes of their people.
        MTGroup.stateKey,
        // THE NUMBER CONFIRMED (06.10): the service's signed confirmation that this number belongs to this person's key
        // (MTPhoneProof) -- it names the key the seed gives, so a copy laid back by the same words holds it true.
        "phoneProof"]
    /// A conversation's own choices — its ground and the ground's softness — and what this device knows of a
    /// correspondent by their own word: whether they hide the exact moment they were seen, whether their build
    /// speaks presence, the link already sent to them. The key ends in the conversation's reference.
    /// The page's ground a correspondent sent (pgHeld., its tag and moment; the ground itself under chatWall.page.) and
    /// whether their build reads the ground's word (pgcap_) — 25.09.
    static let dataPrefixes = ["chatWall.", "chatWallBlur.", "phide_", "phideAt_", "pcap_", "abcap_", "linkSent.", "aboutSent.",
                               "pgHeld.", "pgcap_", "plcap_",
                               "aboutCoins.",   // the balance last told this correspondent and when (MTCoinBoard, 03.10)
                               "moneyFlow.",    // a chat's own Money Flow (MTMoneyFlow, 04.10)
                               "ownWords.",     // the pair holds my words, by its own word (MTOwnWords, 06.10)
                               "coinBinds.",    // the birth of the pair's first coin letter that names itself (MTCoinSend.credits, 06.10)
                               "autoReact."]    // the coins a chosen person's every new letter is paid (MTAutoReact, 06.10)
    /// The one store of this concept is the shared keychain ([C-1], 1640): the conversations deleted at both
    /// ends, and those closed at the other end (24.09). A copy carries each set and lays it back as a union — a copy
    /// adds a deletion or a closure, it never lifts one.
    static let keychainSets = ["deletedCold", "closedCold"]
    /// THE SHARED KEYCHAIN'S OWN, never in a copy: the mirrors the app writes again from its own store for the
    /// extensions and the first frame (names, faces, sets, settings, pipes, the list's record and order), the
    /// counts it recounts, this device's secrets and keys, its tokens and wake registrations, the diary's own
    /// identity and salt, what the extensions hand over in passing (an inbox drained at once, a share, a post
    /// for one's own wall, a banner shown, a knock), and the folders lent to the music page — a permission of this device alone.
    static let keychainStays = ["barredPeers", "blockedChats", "mutedChats", "namesCold", "photosCold",
        "photosManualCold", "peerUsernames", "orderCold", "readChatsCold", "pinnedCold", "forcedUnreadCold",
        "archivedCold", "notifPreview", "notifSender", "notifSound", "objectionableFilterOn", "shareChats",
        "nsePipeAlias", "nsePipeSecrets", "chatListState", "chatListOverlay", "missedUnseen", "unreadCounts", "nseUnread",
        "blobKeySeed", "mt.outbox.key", "mt_active_mnemonic", "mt_apple_id_seed", "mt_device_key", "mt_store_witness", "turnPass",
        "wakeBase", "wakeBases", "wakeElected", "wakeMyAddr", "wakeMyGlyph", "wakeMyName", "wakeOwnToken",
        "wakeVoipDigest", "wakeVoipToken", "diagId", "diagSalt", "nseDiag", "nseLog", "shareDiag",
        "nseInbox", "nseKnocked", "nseShownMids", "nseQuietIds", "nseRoomRang", "heldMids", "pendingShare", "pendingWall", "missedCallSeeds", "mt.longblob.wait", "musicFolders",
        "AppLanguage", "screen.key", "screen.diary",   // the screen broadcast's call key and its diary box: this device's, for one call
        "mt.seats",   // the book of the persons seated on this phone (MTSeats): a copy carries the person seated, never the shelf (29.09)
        "nseShelf",   // the keys the extension opens the shelf's letters with (MTShelfPost, 07.10): this device's view of its shelf, never a copy
        "mt.passwords"]   // the person's Passwords (MTPasswordVault, 06.10): this device's alone, no copy and no backup carries them
    /// The records of the persons on this phone's shelf, one per seat (MTSeats): the seed and the keychain items of a parked person.
    static let keychainStayPrefixes = ["av_", "mt.seat."]
    /// THE PERSON'S SETTINGS belong to whoever holds this phone rather than to one identity: a change of seed
    /// keeps them, and a copy carries them — the language, the notifications, what is downloaded, privacy,
    /// the look of every bubble and ground, the voice and the note, the network page. The VPN's own settings left with the VPN
    /// for its own app (08.10.2026): a copy carries none of them.
    static let settingKeys = [MTKeeping.mineKey, MTKeeping.othersKey, MTKeeping.budgetKey, MTKeeping.toldKey,   // the keeping of a copy (08.10)
                              "appLibraryIcons", "appLibraryPins", MTLibraryIconStyle.key, MTChessComputer.levelKey, "AppLanguage", "AppleLanguages", MTLetterMotion.bounceKey, MTLetterMotion.durationKey,
        "notifEnabled", "notifSound", "notifPreview", "notifSender", "notifLockName",
        "autoDownloadCellular", "autoDownloadWiFi",
        "presenceSharing", "readReceiptsEnabled", "liveTypingEnabled", "syncContactsToPhone", "linkPreviewsEnabled",
        "objectionableFilterOn", "termsAcceptedVersion", "barredPeers",
        "bubbleStyle", "cbMineFill1", "cbMineFill2", "cbMineOpacity", "cbMineText", "cbMineOutline", "cbMineOutlineOp", "cbMineOutlineW",
        "cbPeerFill1", "cbPeerFill2", "cbPeerOpacity", "cbPeerText", "cbPeerOutline", "cbPeerOutlineOp", "cbPeerOutlineW",
        "chatBg", "chatBgPhoto", "cbBgOn", "cbBgType", "cbBg1", "cbBg2", "cbBgPhoto",
        "keyboardLook", "montanaSkin.v2", "noteQuality", "composeOpen", "composeMediaMode",
        "voiceRate", "voiceOrb.look", "vnoteCorner", "miniTimeRemaining", "reactionUse",
        "cardKind", "lastMediaPane", "timePanelOpen",
        "mt.net.tab2", "exitReachability",
        "mt.backup.icloud", "mt.backup.icloud.replace", "mt.backup.plan", "mt.mesh.discoverable",
        "mt.apple.signin", "mt.home.node", "mt.home.node.on", "mt.home.node.pin",   // the Apple Account switch, the person's own node, its daily copies and the digest of its certificate (28.09)
        MTBoardRule.key, MTBoardRule.sightKey,
        MTCoinShow.key, MTCoinShow.toldKey,   // the owner shows or hides their coins, and the wallet has said what that does (04.10)
        MTPersonalRate.key]   // the person's earning, its period and currency: their own rate of the coin (04.10 19:19)
    /// THE MARKS OF MIGRATIONS ALREADY RUN over the data they describe: a copy carries them with that data, so a
    /// one-time sweep never runs a second time over what it already swept; a change of seed keeps them.
    static let markKeys = ["profilePurge805", "pinsWiped1782", "cardNamesRestored1784", "phoneNamesRestored1787",
        "cardNamesPurged", "legacyPerChatMigrated", "deletedChatsMirrorIsTruth", "queuePurged-2026-08-20", "bubbleTheme.gen",
        ChatStore.unreadByLetterKey]
    /// The look of each side's voice orb.
    static let settingPrefixes = ["voiceOrb.side."]
    /// THIS DEVICE'S OWN — never in a copy, each for a named reason:
    /// · the diary's identity, its watermarks and the probe of the network's mode: carried to another phone,
    ///   they would join two phones of one person under one name in data that leaves the phone, and
    ///   privacy here has no acceptable remainder;
    /// · the keys and identities of this machine and the ledgers of its archive engine: derived from the seed
    ///   or drawn for this device. The secret of every correspondence travels too, but not here: it lies in
    ///   the head of the correspondence's own archive folder, sealed under the seed, and a restore of the
    ///   archive re-establishes it (MTPipeBook.establish(secret:seal:false)) — a second road beside that one
    ///   would be a second owner of the one secret;
    /// · what the network taught this device — doors, nodes, the node's clock, endpoints, wake registrations, the delivery and
    ///   the box ledgers: the network teaches the next device again;
    /// · the peer's unsent words: they live under this device's key and nowhere else;
    /// · the dead calls' seeds, the tunnel's clock and the place its diary was carried to, the roads the tunnel judged
    ///   dead (a verdict of this network and this hour, not of the server), and the copy's own clock.
    static let deviceKeys = ["mt.keep.held",   // the parts this phone keeps for others (MTKeeping): never in this person's copy
                             MTKeeping.askedBackKey,   // the correspondences this phone asked to give back (MTKeeping): this device's own
                             "diagId", "diagHideRule", "diagWmTele", "diagWmTrace", "diagWmVpn", "diagGenTele", "diagGenTrace", "diagGenVpn",
        "mt.probe.at", "mt.probe.conf", "mt.probe.mode", "mt.probe.rot",
        "mt.probe.line",   // the line under the permitted list, with its hysteresis (30.09): this network's word, never a copy's
        "mt.release.told",   // the build the Montana room already told this phone of (29.09): this device's own
        "mt_device_key", "mt.install.marker", "mt_store_witness",
        "mt.doorbook", "mt.nodes", "mt.nodes.learned", "mt.nodes.machines", "mt.self.proven",
        "mt.notify.asked",
        MontanaDiagConsent.key,   // this device's yes to its diary leaving it (08.10.2026): each device answers for itself
        MTTopNet.unaskedKey,   // this device withdrew the top row of a person never asked (08.10.2026)
        MTTopNet.toldBeforeKey,   // whether an earlier build of this device had published the top row (08.10.2026)
        "mt.rooms.seen",   // the group rooms this phone knew and their people's room keys (07.10.2026): live minutes, never a copy's
        "pagesWall", "pagesWallRecent", "pagesWallBlur", MontanaWakePush.skewKey]
    /// What each node holds for this device's token -- the node's own word about this phone, whoever is seated on it: a person
    /// lifted into the seat finds the registration of the one before and registers what differs.
    static let devicePrefixes = [MontanaWakePush.regSetPrefix]
    /// THE PERSON ON THIS PHONE (the second identity checklist, 1.2): never in a copy, as before -- derived from the seed or
    /// learned for this person's correspondences on this device -- and parked with the person's seat, lifted with it
    /// (MTSeats). The keys of the correspondences and of this person's node, the archive's and the delivery's ledgers, what
    /// was announced to whom, the name of this person's record in the Apple Account (a second person publishes a record of
    /// their own and never writes over the first), the copies' clocks (a copy is named by its owner's proof, one per person).
    static let seatKeys = [
        "peerFaceOwned",   // the digests of the faces the correspondents themselves sent (ChatStore.faceOwned, 04.10): this person's
        "chatCoinSince",   // the moment this person's chat coin came on (MTChatMint): the person's, as the tally in Montana/Coins is (04.10)
        "coinBoard.told",   // the balances this person's correspondents told (MTCoinBoard, 03.10): learned for this person, told again
        "mt.account.keys", "mt.twin.ref", "mt.node.identity", "mt.node.kem", "pipeSecrets",
        "mt.history.folders", "mt.history.heads.form", "mt.history.nameheads", "mt.history.pushed",
        "mt.mesh.book", "p2pLearnedEndpoints", "rdvPermUpOk", "rdvUpOk", "rdvPermUpAt", "rdvUpAt", "pendingInvite",
        MontanaDeliveryEngine.pendingKey, "orphanDelivered", "handoffTaken",
        "longLetterRefs", "nodeChunkLedger", "nodeChunkOrphanSince", "wakeUnsentDrops",
        "pendingOpenChat", "pendingPeerAvatars", "peerDraftsMap",
        "callDeadSeeds", "mt.call.heldEpoch", MTBoard.pagesKey, MTBoard.firstKey,
        "mt.backup.icloud.at", "mt.backup.icloud.engine", "mt.home.node.at",
        "mt.apple.signin.id", "mt.restore.outbox", MTSamePair.mergedKey,
        MTGroup.copiesKey]   // the copies of the groups' words on their way (05.10): the person's own ledger of the queue
    static let seatPrefixes = ["ckpt_", "mrefGone_", "rdvFaceUp:", "sentAv4_", "sentAvNone2_", "sentNm2_", "sentAb1_", "sentPg1_"]
    /// THE PERSON'S OWN IN THE KEYCHAIN (the second identity checklist, 1.1): parked with the seat, lifted with it -- the two
    /// sets a copy carries, the outgoing queue's key and its knock ledger, the extension's box of this person's letters, and
    /// the mirrors the app writes from this person's store for the extensions and the first frame (another person's mirror
    /// opens nothing and names strangers). Each is named in keychainSets or keychainStays. The seed rides the seat's record.
    static let seatKeychain = ["deletedCold", "closedCold", "mt.outbox.key", "nseKnocked",
        "namesCold", "photosCold", "photosManualCold", "orderCold", "readChatsCold", "pinnedCold", "forcedUnreadCold", "archivedCold",
        "blockedChats", "mutedChats", "peerUsernames", "chatListState", "chatListOverlay", "missedUnseen", "unreadCounts", "nseUnread",
        "nsePipeAlias", "nsePipeSecrets", "shareChats", "wakeMyAddr", "wakeMyGlyph", "wakeMyName",
        "nseInbox", "nseShownMids", "nseRoomRang", "heldMids", "missedCallSeeds", "mt.longblob.wait",
        "mt.passwords"]   // the person's Passwords (MTPasswordVault, 06.10): parked with the seat, never shown to the next person
    /// THE PERSON'S FOLDERS: every folder a copy carries, each parked into the seat and lifted from it by one rename, and the
    /// person's folders a copy leaves on the phone: the files of the posts being written (the wall's load lets go of every
    /// file no draft of the person seated names, so a parked person's drafts would lose theirs). The copy's guard
    /// (tools/mt-copy-scope-check.py) holds every carried folder here and every other one named as staying.
    static let seatFolders = ["AS:Avatars", "AS:Wallpapers", "AS:Montana/Media", "AS:Montana/Pictures", "DOC:stories",
        "DOC:Montana/Chats", "AS:MontanaHistory", "AS:MontanaJournal", "GROUP:delivery", "AS:Montana/WallDrafts", "AS:Montana/Coins",
        "DOC:Montana/TimeChain"]
    // Per-chat keys of the era before the sealed maps (SC-05): collapsed once, forgotten with the person.
    static let legacyPrefixes = ["lastSeen_", "draft_", "mute_", "block_"]
    /// COLLECTIONS OF INDEPENDENT ENTRIES are laid back as a union: what this device holds stays, and the
    /// copy adds what it lacks — a restore never lifts a block, a contact, a name or a server that stands here.
    /// Every other value — a setting, the profile, one record such as the permanent link — is the copy's.
    static let unionKeys: Set<String> = ["readChats", "pinnedChatsList", "forcedUnread", "mutedChats", "archivedNames",
        "deletedChats", "peerAvatars", "peerNames", "peerSeenAt", "peerGoneAt", "lastSeenMap", "draftsMap",
        "muteFlagsMap", "blockFlagsMap", "pinnedMessages", "scheduledMsgs", "myStoryMedia", "viewedStories",
        "mtContacts", "pinnedContacts", "archivedContacts", "manualNames", "manualPhotos", "peerUsernames",
        "declaredAt", "blockedChats", "peerReadMap", "deletedMids", "mtVerifiedConversations", "cardKeys", "rdvCards",
        "montana.stickers.mine", "montana.stickers.packs", "montana.stickers.passports", "montana.stickers.givers",
        "montana.stickers.ids", "montana.gifs.mine", "videoLikes", "barredPeers", "reactionUse",
        "chatsJSON", "archivedJSON", "savedToPhotos", "callHandleTokens",
        "controlMids", "peerRdvLinks", "peerRdvLinks.b", "peerAbout", "pendingMediaJSON", "gifFirstRun", "pipeTouched",
        "pipeDying", "pipeFirstCiphertexts", "pipeFirstRoots", "pipeFirstMeta", "pipeNameRoots"]
    /// WHAT A RECORD IS KNOWN BY inside a list of records: the first of these fields it carries. A row of the
    /// chat list is its conversation, a contact its reference, a server its own id, a plan its link; two
    /// records known by one value are one record, and the device's own stands.
    static let unionKnownBy: [String: [String]] = ["chatsJSON": ["convId", "name"], "archivedJSON": ["convId", "name"],
        "mtContacts": ["address"], "myStoryMedia": ["file"],
        "scheduledMsgs": ["id"], "montana.stickers.packs": ["id"]]
    static let unionKnownByDefault = ["uid", "id", "mid", "ref", "url", "file"]

    /// WHAT A COPY TAKES FROM THE SETTINGS STORE: the account's content and the person's settings, by name
    /// and by prefix, read from THIS app's own domain and never through the system's — a language list the
    /// system keeps for every app would otherwise land on another phone as this app's own choice.
    static func carried() -> [String: Any] {
        let domain = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "") ?? [:]
        let names = Set(dataKeys + settingKeys + markKeys)
        let prefixes = dataPrefixes + settingPrefixes
        return domain.filter { names.contains($0.key) || prefixes.contains(where: $0.key.hasPrefix) }
    }

    /// THE STORE WAS REPLACED UNDER THE LIVING (23.09): a copy was laid, or the seed changed. Every owner that
    /// holds a stored value in memory lets it go and reads the store again — here, in one call, so no owner is
    /// forgotten on one road and remembered on the other. Without it the memory of the moment before writes
    /// itself back over what was just laid: a peer's next name word rewrote the whole name map from memory, a
    /// sticker added rewrote the shelf, a server added rewrote the VPN list. On the main thread: the owners
    /// are the screen's.
    static func reread(restored: Bool, feed: Any? = nil, outbox: Data? = nil) {
        forgetRetired()   // a copy made before the VPN left lays its values again: they leave at once (08.10.2026)
        MTNameBook.forgetStored()
        MTPipeBook.reread()
        MontanaCard.forgetHeld()
        MontanaStickerBook.shared.reread()
        MontanaGifBook.shared.reread()
        MTGifPlay.shared.reread()
        MontanaVoiceOrbStyle.shared.reread()
        VoicePlayer.shared.rereadRate()
        MTReactions.forgetOrder()
        MTGroup.shared.reread()
        MTWallpaper.Book.shared.rev += 1
        MontanaNotifyGate.mirrorSettings()
        MontanaSafety.mirror()
        guard restored else { return }
        if let live = ChatStore.live {
            live.takeStored(feed: feed as? [String: [Message]], outbox: outbox)
        } else {
            ChatStore.layBeforeBirth(feed: feed as? [String: [Message]], outbox: outbox)   // the copy came before the store (28.09)
        }
        // The language and the mesh switch act the moment they are set, by their owners' own roads: the
        // language picker's word to the screens, and the switch's own setter (the system asks its question
        // once, as it asked on the device the copy came from).
        NotificationCenter.default.post(name: .appLanguageChanged, object: nil)
        if MontanaP2PNode.meshDiscoverable { MontanaP2PNode.meshDiscoverable = true }
    }

    /// THE FEED AS IT STANDS, for a copy (the critic, 23.09): the history file and the rows the journal holds
    /// beyond it, merged by the letters' names as the launch merges them. Read from the files off the main
    /// thread, never from the living store; a deletion made after the last snapshot travels as its tombstone.
    static func feedNow() -> Data? {
        let journal = MTRowJournal.readAll()
        let stored = (MTHistoryFile.read() ?? MontanaLocalVault.getDecrypted("chatMessages"))
            .flatMap { try? JSONDecoder().decode([String: [Message]].self, from: $0) }
        guard var feed = stored ?? (journal.isEmpty ? nil : [:]) else { return nil }
        for (chat, rows) in journal {
            var base = feed[chat] ?? []
            var have = Set(base.map { $0.mid })
            for r in rows where have.insert(r.mid).inserted {
                base.insert(r, at: base.firstIndex(where: { ChatStore.before(r, $0) }) ?? base.count)
            }
            feed[chat] = base
        }
        return try? JSONEncoder().encode(feed)
    }
    /// The feed a copy carried, read into rows on the queue that takes the copy back — not on the screen's.
    static func decodeFeed(_ d: Data) -> Any? {
        try? JSONDecoder().decode([String: [Message]].self, from: d)
    }
    /// The letters still on their way, as the outgoing queue holds them.
    static func outboxNow() -> Data? {
        guard case .items(let items) = MTOutbox.read(), !items.isEmpty else { return nil }
        return try? JSONEncoder().encode(items)
    }
    // The identity of this device. Reset only when the device forgets the person.
    // LEGACY-FORGET: names of the era of the identifier. Nothing in this tree writes them; they are
    // listed so that a device carrying them from an older build forgets them too.
    static let legacyKeys = ["accountUserId", "accountAddress", "accountIdHex",   // LEGACY-FORGET: names of the identifier era — erased here, not stored
        "accountRef", "walletAddress", "lastLocalAccountId"]   // LEGACY-FORGET
    // Keys of the era of entry. Nothing writes them; they are listed so that a device which
    // carried them from an older build forgets them too, and for no other reason.
    static let legacyEntryKeys = ["sessionActive"]   // LEGACY-FORGET: nothing writes it; it is forgotten here
    // The boundary itself: the twin reference the seed last opened under. Leaves only when the
    // device forgets the person; a change of seed rewrites it.
    static let boundaryKeys = ["seedBoundary"]

    // The ONE place that crosses the account boundary. Called the moment a new account appears —
    // before the person can enter anything for it — so their own data is never taken for the
    // previous account's. Everything after that point belongs to the new account by construction.
    static func change(to boundary: String) {
        // What is compared here is the local reference of the twin correspondence — the one value
        // that changes when the seed does. There is no identifier of a person in this tree.
        guard !boundary.isEmpty else { return }
        let ud = UserDefaults.standard
        // The key moved with the vocabulary; a device that wrote it under the old name is read
        // once by that name, so the move is never mistaken for a change of seed.
        let last = ud.string(forKey: "seedBoundary") ?? ud.string(forKey: "lastLocalAccountId") ?? ""
        guard last != boundary else {
            if ud.object(forKey: "seedBoundary") == nil { ud.set(boundary, forKey: "seedBoundary"); ud.removeObject(forKey: "lastLocalAccountId") }
            return
        }
        MontanaTelemetry.shared.event("SEED boundary changed (wipe=\(last.isEmpty ? "no" : "yes"))")
        if !last.isEmpty { forgetContent() }
        ud.set(boundary, forKey: "seedBoundary")
        ud.removeObject(forKey: "lastLocalAccountId")
    }

    // A change of seed: the previous content leaves; the new seed is already in place.
    static func forgetContent() {
        let ud = UserDefaults.standard
        MontanaTelemetry.shared.event("PROFILE wiped by clearData (had a name: \((ud.string(forKey: "userName") ?? "").isEmpty ? "no" : "yes"))")
        for k in dataKeys { ud.removeObject(forKey: k) }
        for k in ud.dictionaryRepresentation().keys where (legacyPrefixes + dataPrefixes).contains(where: k.hasPrefix) { ud.removeObject(forKey: k) }
        MontanaCard.wipe()   // the card's records leave by their owner's door, in order after every write on its way (25.09)
        NotificationCenter.default.post(name: .montanaSeedForgotten, object: nil)   // store memory
        DispatchQueue.main.async { reread(restored: false) }   // and every other owner of a stored value
    }
    // The device forgets the person: content, identity and seed leave by one boundary, and the
    // next launch is a first launch. Nobody is told: this identity exists nowhere else.
    /// THE VPN'S OWN VALUES LEAVE WITH IT (the author's word 08.10.2026; the critic's N4): its servers, the plans with their links
    /// (a plan's link is a paid credential), the name the plans knew this device by, the payment's token, the wall's rule and the
    /// people it named, the tunnel's marks. Read by nothing since the VPN left for its own app, they stood on every upgraded phone
    /// and came back with every copy laid; they leave at every launch, after a copy is laid and with the identity, and no list of
    /// a copy names them.
    static let retiredKeys = ["mt.vpn.servers", "mt.vpn.plans", "mt.vpn.sel", "mt.vpn.hand", "mt.vpn.hwid", "mt.vpn.delays",
        "mt.vpn.manualPin", "mt.vpn.manualFolded", "mt.vpn.payToken", "mt.vpn.extCursor", "mt.vpn.installOff", "mt.vpn.dead",
        "mtVPNStartTicks", "mtVPNStartWall",   // RETIRED-VPN-KEY: the names of stored values, never a word on a screen
        "vpnwall.sent", "vpnwall.asked", "vpnwall.cap", "vpnWallMint.paid", "vpnWallSight", "vpnWallSightAllow", "vpnWallSightDeny"]
    static func forgetRetired() {
        let ud = UserDefaults.standard
        let held = retiredKeys.filter { ud.object(forKey: $0) != nil }
        for k in held { ud.removeObject(forKey: k) }
        if !held.isEmpty { MontanaP2PTrace.mark("retired_vpn", "forgot=\(held.count)") }
    }
    static func forget() {
        let ud = UserDefaults.standard
        forgetRetired()
        let present = (dataKeys + legacyKeys + legacyEntryKeys + boundaryKeys).filter { ud.object(forKey: $0) != nil }.count
        for k in dataKeys + legacyKeys + legacyEntryKeys + boundaryKeys { ud.removeObject(forKey: k) }
        for k in ud.dictionaryRepresentation().keys where (legacyPrefixes + dataPrefixes).contains(where: k.hasPrefix) { ud.removeObject(forKey: k) }
        MontanaCard.wipe()   // the card's records leave by their owner's door, in order after every write on its way (25.09)
        // Shared-keychain keys inherited from older builds: they are written nowhere any
        // more, but a device that lived through those builds still holds them — and forgets them here.
        // LEGACY-FORGET: names of the era of entry. Nothing in this tree writes them; they are
        // listed so that a device carrying them from an older build forgets them too.
        for k in ["unreadCounts", "mutedChats", "me_addr", "e2eKeys", "e2eSessions", "apiToken", "deviceId", "nseTexts"] { MontanaKeychain.set(k, Data()) }
        for k in ["e2eKeys", "e2eSessions", "accHistKey", "deviceIdStable", "serverAuthToken"] { E2EKeychain.delete(k) }
        MontanaAppleID.withdrawOwn()   // the account's record of this installation leaves with the seed; a twin's record stands (28.09)
        // OTHERS WAIT ON THIS PHONE'S SHELF (the second identity checklist, stage 6): their sealed values stand under the device
        // key, so the key stays; the person forgotten leaves by the classes instead: their own values on this phone (after the
        // record's withdrawal above: its name is one of them), their items of the keychain, their folders set aside on the
        // shelf, their seat out of the book.
        let seated = MTSeats.anyParked
        // The coin book of the person forgotten is on disk whole and set aside before anything of theirs leaves (the coin audit's
        // eighth point, MTCoinPlace.setAside); with other seats the seat's own road parks it (MTSeats.leaveForgotten).
        if !seated {
            let aside = { MainActor.assumeIsolated { MTLocalCoinLedger.shared.writeWhole(); MTCoinPlace.setAside() } }
            // MAIN-SAFE-SYNC: the main thread runs aside itself; only a caller off it waits, on main, which waits on nobody here.
            if Thread.isMainThread { aside() } else { DispatchQueue.main.sync(execute: aside) }
        }
        if seated {
            for k in ud.dictionaryRepresentation().keys where MTSeats.layerHolds(k) { ud.removeObject(forKey: k) }
            for k in seatKeychain { MontanaKeychain.delete(k) }
        }
        MontanaSeed.clear(); if !seated { MontanaDeviceKey.reset() }; E2E.forgetDeviceTag()
        MontanaSeed.forgetTwin(); MontanaSeed.forgetKeys()
        MontanaArchive.forgetKeys()   // the archive branch of the departed seed leaves with it
        MTPipeBook.forgetAll()        // and the pipes it answered for, before a new book could re-seal them
        MTOutbox.wipe()               // the shared outgoing queue and its key: nothing of the departed seed rides on
        MontanaQueueKeys.forgetMasterSeed()
        // What this MACHINE answered under goes too. It says nothing about the person by
        // construction, but a value that outlives an identity is a thread from the old one to the
        // new for anybody who was listening on the air.
        MontanaOverlayKey.forget(); MontanaNodeKem.forget()
        MontanaP2PNode.shared.forgetMyRef()
        MontanaNotify.forgetAllSuggestions()   // the system's suggestions of the departed person go with them
        MontanaP2PTrace.mark("seed_forgotten", "ud=\(present) sealed_dropped=1")
        DispatchQueue.main.async { UNUserNotificationCenter.current().setBadgeCount(0) }
        NotificationCenter.default.post(name: .montanaSeedForgotten, object: nil)
        // A STORE THAT OUTLIVED ITS PERSON IS NEVER THE NEXT PERSON'S (24.09, the critic's third pass): a task still
        // holding it (an upload, an archive's restore) kept it alive, and ChatStore.one() would hand it to the next
        // identity with what wipeLocal does not clear. The next window of this device makes a store of its own.
        if seated { MTSeats.leaveForgotten() }
        ChatStore.live = nil
        DispatchQueue.main.async {
            reread(restored: false)
            if !seated { MainActor.assumeIsolated { MTCoinBook.reread() } }   // the next seed starts from its own book, never the forgotten one's
        }
    }
}

// Nothing stands here any more. A person had a `userId` and an `address`, both of them public
// strings that meant «this person», both written into storage and compared on every row of the
// feed. The set forbids the quantity outright ([I-17].2), and the tree does not need it: a letter
// is mine because THIS device wrote it, not because a string inside it matches a string about me.

// Who this device is: whoever holds the seed. There is nothing to publish and nothing to compare.
// ════════════════════════════════════════════════════════════
// SERVER SETTINGS — address, token, and the «use server» toggle.
// They can be entered right in the app (the «Montana Server» screen in Settings)
// OR set in code once the keys arrive. Stored on the phone.
// ════════════════════════════════════════════════════════════
enum AppVersion {
    static var short: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—" }
    static var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—" }
    static var full: String { "v\(short) (\(build))" }
}


// ════════════════════════════════════════════════════════════
func makeChannel() -> MessagingChannel {
    MeshChannel()   // the only path: post-quantum end-to-end over the mesh
}

@MainActor
// Nothing is raised at start: a node of the mesh is what this app is, and it comes up with
// the app itself. What stood here brought a server layer to life and asked it who we were.

// ════════════════════════════════════════════════════════════
// AVATARVIEW — the user's avatar
// Shows the chosen photo, or if there is none — a gold circle with a letter.
// ════════════════════════════════════════════════════════════
/// THE MAIN THREAD IS MEASURED, NOT FELT (15.24, the author's word 07.09: «from Settings to Chats I
/// cannot scroll for nine seconds»). After a tab appears, a probe asks the main thread for twelve
/// seconds, ten times a second, how late it answers; the worst gap, when it happened and what the
/// thread was doing (the crumb the heavy blocks leave) go to the diary in one line. A bounded probe,
/// not a patrol: it ends by itself. The first drag after the tab appears is timed too.
enum MontanaMainProbe {
    // Written from the main thread only (the heavy blocks all run there); the probe reads it there too.
    nonisolated(unsafe) static var crumb = ""
    /// A NAMED STEP ON THE MAIN THREAD (22.09): T3 21:10:18 — the main thread stood 2989 ms inside a
    /// voice letter's landing (main_probe doing=-), and no step of that road had a name. Every step
    /// here sets the crumb the probe reports and, past 40 ms, writes its own line with its cost.
    /// A SLOW STEP NAMES ITS PARTS (the critic 23.09): a text letter's landing stood 65 ms on T3 and 86-146 ms on T1
    /// at every letter (what=rx:append), and the line named nothing inside it. A step run inside another reports its
    /// cost to the one around it, and the slow step's line carries its parts (a part under a millisecond is left out).
    nonisolated(unsafe) private static var parts: [String]?
    nonisolated static func step(_ what: String, _ f: () -> Void) {
        let was = crumb; crumb = what
        let outer = parts; parts = []
        let t0 = ProcessInfo.processInfo.systemUptime
        f()
        let ms = Int((ProcessInfo.processInfo.systemUptime - t0) * 1000)
        let inner = parts ?? []
        parts = outer
        if ms > 40 { MontanaP2PTrace.mark("main_slow", "what=\(what) ms=\(ms)" + (inner.isEmpty ? "" : " parts=" + inner.joined(separator: ","))) }
        if ms > 0 { parts?.append("\(what):\(ms)") }
        crumb = was
    }
    nonisolated(unsafe) static var appearAt: Date?
    nonisolated(unsafe) private static var running = false
    @MainActor static func run(_ what: String, seconds: Double = 12) {
        appearAt = Date()
        guard !running else { return }
        running = true
        Task { @MainActor in
            let t0 = Date(); var worst = 0.0, at = 0.0, late = 0; var doing = ""
            let resigns0 = MontanaTelemetry.shared.resigns
            while Date().timeIntervalSince(t0) < seconds {
                let s = Date()
                try? await Task.sleep(nanoseconds: 100_000_000)
                // A probe measures a thread that was supposed to answer. Asleep, the thread
                // legitimately does not — and the former probe wrote the nap down as a stall
                // (a «worst» of 3 867 866 ms measured 11.09: the phone slept with the probe half
                // done). The watchdog's rule holds here too: the interval lies wholly inside one
                // active stretch, or the reading is thrown away and says so.
                if MontanaTelemetry.shared.resigns != resigns0 {
                    running = false
                    MontanaP2PTrace.mark("main_probe", "\(what) interrupted=resign at=+\(String(format: "%.1f", s.timeIntervalSince(t0)))s late=\(late)")
                    return
                }
                let gap = Date().timeIntervalSince(s) - 0.1
                if gap > 0.25 { late += 1 }
                if gap > worst { worst = gap; at = s.timeIntervalSince(t0); doing = crumb }
            }
            running = false
            MontanaP2PTrace.mark("main_probe", "\(what) worst_ms=\(Int(worst * 1000)) at=+\(String(format: "%.1f", at))s late=\(late) doing=\(doing.isEmpty ? "-" : doing)")
        }
    }
    /// The first drag after the tab appeared: how long the person waited before the list moved.
    static func firstDrag() {
        guard let a = appearAt else { return }
        appearAt = nil; touchAt = nil
        MontanaP2PTrace.mark("chats_scroll", "first_drag_ms=\(Int(Date().timeIntervalSince(a) * 1000))")
    }
    /// The first touch that REACHED the list after the tab appeared. Touch arrived, drag did not =
    /// a gesture blocked inside; touch never arrived = something above the list took it; both
    /// late while the probe says the thread was free = the person's hand (15.25).
    nonisolated(unsafe) static var touchAt: Date?
    static func firstTouch() {
        guard let a = appearAt, touchAt == nil else { return }
        touchAt = Date()
        MontanaP2PTrace.mark("chats_touch", "first_touch_ms=\(Int(Date().timeIntervalSince(a) * 1000))")
    }
}

// ═══ THE JOURNAL OF ROWS (16.09, the author's word: a letter shown in the list and gone from the
// chat is forbidden by construction) ═══
// ONE store, two parts: the snapshot — the whole history sealed into the vault, written in the
// background — and this journal: one small sealed atomic file per row, written on the main thread
// the moment the row is born, BEFORE the receipt leaves, before the landing box is emptied, before
// the list record is written. Measured 16.09 (T1): a letter from the seventeenth landed in memory at
// 18:25:54.2Z, its receipt reached the sender at 18:25:55.1Z, the process was killed by a reinstall
// within seven seconds, the debounced whole-history write never landed — the list record (a
// synchronous keychain write) stood, the row was gone from everywhere, the sender held «delivered».
// The snapshot is a cache of this journal: a row the snapshot lacks at load is taken from here; a
// row a WRITTEN snapshot holds is compacted away. Tombstones are the store's own (deletedMids,
// written synchronously) plus the removal of the row's file.
/// THE HISTORY IS A FILE, WRITTEN ATOMICALLY, READ BACK BEFORE THE JOURNAL TRUSTS IT (17.09, the critic).
/// It lived in UserDefaults as one sealed blob: a write there cannot refuse, «true» was returned on faith,
/// the journal was compacted on that word — and a relaunch read a history without twelve journaled rows
/// (T1 05:46:12Z; the archive held them, the feed did not). A file write returns its error; an atomic
/// replace leaves the old file or the new one, never a torn one.
/// THE NAMES A RESTORE GIVES A LETTER (09.10): a letter laid back from the archive is named "arc:" and a hash of its second, side
/// and words (restoreFromArchive), one given back by a correspondent "given:" and the name they hold (MTKeeping.takeGiven). Neither
/// is the letter's wire name, the one name both phones hold: whatever the letter moved, it moved under that wire name, and a move
/// under a restored name moves nothing (MTCoinEntry.restoredName).
enum MTRestoredMid {
    static let archive = "arc:"   // NOT-UI: a restored row's name on this phone, never on the wire
    static let given = "given:"   // NOT-UI: a given-back row's name on this phone, never on the wire
    static func holds(_ name: String) -> Bool { name.hasPrefix(archive) || name.hasPrefix(given) }
}

enum MTHistoryFile {
    static let aad = Data("chatMessages".utf8)   // the AAD the vault blob wore — one seal, one key
    private static let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MontanaHistory", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var d = dir; var rv = URLResourceValues(); rv.isExcludedFromBackup = true
        try? d.setResourceValues(rv)
        return dir.appendingPathComponent("history.sealed")
    }()
    static func write(_ plain: Data) -> Bool {
        guard let sealed = MontanaLocalVault.seal(plain, aad) else { return false }
        return (try? sealed.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])) != nil
    }
    static func read() -> Data? {
        guard let sealed = try? Data(contentsOf: url) else { return nil }
        return MontanaLocalVault.open(sealed, aad)
    }
    static func drop() { try? FileManager.default.removeItem(at: url) }
}

enum MTRowJournal {
    private struct Entry: Codable { let chat: String; let row: Message }
    private static let root: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MontanaJournal", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var d = dir; var rv = URLResourceValues(); rv.isExcludedFromBackup = true
        try? d.setResourceValues(rv)
        return dir
    }()
    private static func dirName(_ chat: String) -> String {
        SHA256.hash(data: Data(chat.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()   // LOCAL-HASH-OK: a folder name on this device
    }
    private static func chatDir(_ chat: String) -> URL { root.appendingPathComponent(dirName(chat), isDirectory: true) }
    private static func fileName(_ mid: MID) -> String { MontanaArchive.sanitizeName(mid) }
    // THE COUNT IS UNDER A LOCK, NEVER BEHIND THE MAIN THREAD (1634): the compaction runs on the
    // snapshot queue, and the forced save on going to background waits on that queue FROM the main
    // thread — a compaction asking the main thread back was a deadlock, and the watchdog killed both
    // phones seven seconds after every background (T1/T2 19:44-19:46Z, «reclaimed in background»).
    private static let lock = NSLock()
    private static var pending = 0   // under lock: rows journaled and not yet compacted (0 = nothing to list)

    /// The row on disk, sealed, atomic — synchronous by design: the caller's next line may be the
    /// receipt. A refusal is spoken aloud; the row then lives in memory and the snapshot alone.
    @discardableResult
    static func put(_ chat: String, _ row: Message) -> Bool {
        let name = fileName(row.mid)
        guard let plain = try? JSONEncoder().encode(Entry(chat: chat, row: row)),
              let sealed = MontanaLocalVault.seal(plain, Data(("journal:" + name).utf8)) else {
            MontanaP2PTrace.mark("journal_refused", mid: row.mid, "no device key — the row lives in memory only")
            return false
        }
        let dir = chatDir(chat)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ok = (try? sealed.write(to: dir.appendingPathComponent(name + ".row"),
                                    options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])) != nil
        if ok { lock.lock(); pending += 1; lock.unlock() } else { MontanaP2PTrace.mark("journal_refused", mid: row.mid, "write failed") }
        return ok
    }
    static func drop(_ chat: String, mid: MID) {
        try? FileManager.default.removeItem(at: chatDir(chat).appendingPathComponent(fileName(mid) + ".row"))
    }
    static func dropChat(_ chat: String) { try? FileManager.default.removeItem(at: chatDir(chat)) }
    static func dropAll() {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// Every journaled row by chat — read once at load, off the main thread, before the snapshot.
    static func readAll() -> [String: [Message]] {
        var out: [String: [Message]] = [:]
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return out }
        var files = 0
        for d in dirs {
            guard let list = try? fm.contentsOfDirectory(at: d, includingPropertiesForKeys: nil) else { continue }
            for f in list where f.pathExtension == "row" {
                files += 1
                let name = f.deletingPathExtension().lastPathComponent
                guard let sealed = try? Data(contentsOf: f),
                      let plain = MontanaLocalVault.open(sealed, Data(("journal:" + name).utf8)),
                      let e = try? JSONDecoder().decode(Entry.self, from: plain) else {
                    MontanaP2PTrace.mark("journal_unreadable", "file=\(String(name.prefix(12)))")
                    continue
                }
                out[e.chat, default: []].append(e.row)
            }
        }
        if files > 0 { MontanaP2PTrace.mark("journal_read", "files=\(files) chats=\(out.count)") }
        lock.lock(); pending = max(pending, files); lock.unlock()
        return out
    }

    /// After a snapshot has been WRITTEN: the rows it holds need no journal; the rows it lacks stay.
    /// Runs on the snapshot queue, against exactly the snapshot that landed.
    static func compact(against snapshot: [String: [Message]]) {
        lock.lock(); let due = pending; lock.unlock()
        guard due > 0 else { return }
        let fm = FileManager.default
        var have: [String: Set<String>] = [:]
        for (chat, rows) in snapshot { have[dirName(chat)] = Set(rows.map { fileName($0.mid) }) }
        var kept = 0, gone = 0
        for d in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            let set = have[d.lastPathComponent] ?? []
            for f in (try? fm.contentsOfDirectory(at: d, includingPropertiesForKeys: nil)) ?? [] where f.pathExtension == "row" {
                if set.contains(f.deletingPathExtension().lastPathComponent) { try? fm.removeItem(at: f); gone += 1 } else { kept += 1 }
            }
            if ((try? fm.contentsOfDirectory(atPath: d.path)) ?? []).isEmpty { try? fm.removeItem(at: d) }
        }
        lock.lock(); pending = kept; lock.unlock()
        MontanaP2PTrace.markFolded("journal_compact", "gone=\(gone) kept=\(kept)", window: 60)
    }
}

/// ONE PERSON, ONE CONVERSATION (24.09, the author's word «do it»). Pipes cannot be linked to a person by design, and a new
/// meeting with someone already met gave birth to a second conversation beside the first (T3 23.09 19:17:23: both meeting
/// books missed, «meet_new»; T1 19:18:09 accepted — one person twice on each phone, and a hidden old chat came back by the
/// peer's letter). The fold is decided by the two phones alone: right after a meeting the one who met asks over the NEW
/// pipe — its freshest pipes, each tagged against the new secret, filled with noise to one fixed count — and the other
/// answers in one shape for «yes» and «no»: a proof only a holder of both secrets can make, or a tag nobody can check.
/// Nobody else can match a tag or forge a proof; the other learns nothing of the asker's other pipes, not even their
/// number; the node sees one silent letter each way of one size whatever the answer; an older build buries both words
/// unread and the meeting stays as it was. Both ends fold into the SAME conversation by construction: an established
/// pipe is proven before a newborn one; a newborn pipe of my own is proven when my question over it did not name the
/// pipe asked about — the other side cannot prove through it; and two pipes whose questions named each other are tied
/// by a rank both ends compute alike, so exactly one end proves. Modelled over random orders (24.09): every re-meeting
/// folds into the old conversation at both ends; two scans so simultaneous that neither question names the other pipe
/// stay two conversations, as before, and never a different survivor at each end. A folded pipe forwards into its
/// conversation until the orphan sweep buries it.
enum MTSamePair {
    static let slots = 32
    /// The question lives an hour in the queue: an older build buries it unread and never receipts it, and a week of
    /// knocks for nothing is not what a question is worth (MontanaDeliveryEngine.attempt).
    static let askLifeS: Double = 3600
    /// The words that speak of the pipe they came by, never of a conversation: a folded pipe reads them itself — the
    /// fold's own, the burials', and a call's: a call runs on the pipe it was placed on (its answer must go back there),
    /// while its row lands in the conversation (appendCallLog).
    static func speaksOfPipe(_ text: String) -> Bool {
        text.hasPrefix(sameAskMark) || text.hasPrefix(sameYesMark) || isBurialWord(text)
            || text.hasPrefix(callSignalMark) || text.hasPrefix(ringMark)
    }
    private static func hex(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }
    private static func tag(_ domain: String, _ older: Data, _ newer: Data) -> String {
        hex(MTPipe.domained(domain, [older, newer]).prefix(16))
    }
    private static func noise() -> String {
        var b = [UInt8](repeating: 0, count: 16)
        _ = mt_random_fast(&b, 16)
        return hex(Data(b))
    }
    /// A pipe's place in the one order both ends compute alike — the tie between two pipes born at one meeting.
    private static func rank(_ secret: Data) -> Data { MTPipe.domained("mt-same-rank", [secret]) }

    // -- this device's own questions still waiting for their answer, with the pipes each one named: a meeting's
    //    minutes, memory only --
    private static let lock = NSLock()
    private static var asked: [String: (at: Double, named: Set<String>)] = [:]
    private static var reminded: [String: Double] = [:]
    private static func waiting(_ conv: String) -> Set<String>? {
        lock.lock(); defer { lock.unlock() }
        guard let q = asked[conv], Date().timeIntervalSince1970 - q.at < askLifeS else { return nil }
        return q.named
    }
    static func settle(_ conv: String) { lock.lock(); asked[conv] = nil; lock.unlock() }

    /// The question: the silent first letter of a pipe just born at a meeting, carrying the pipe's ciphertext.
    static func ask(new conv: String) {
        guard let sn = MTPipeBook.secret(for: conv) else { return }
        let dying = Set(MTPipeBook.dyingAll())
        let named = Array(MTPipeBook.allByFreshness().filter { $0 != conv && !dying.contains($0) }.prefix(slots))
        var tags = named.compactMap { q in MTPipeBook.secret(for: q).map { tag("mt-same-ask", $0, sn) } }
        while tags.count < slots { tags.append(noise()) }
        tags.shuffle()
        guard let d = try? JSONSerialization.data(withJSONObject: ["t": tags]) else { return }
        lock.lock(); asked[conv] = (Date().timeIntervalSince1970, Set(named)); lock.unlock()
        MontanaDeliveryEngine.shared.enqueue(to: conv, chat: conv, mid: "same-" + UUID().uuidString,
                                             text: sameAskMark + d.base64EncodedString(), silent: true)
        MontanaP2PTrace.mark("same_ask", "conv=\(String(conv.prefix(10)))")
    }
    /// The answering side's choice: the pipe it shares with the one who asked, or none.
    static func shared(ask payload: String, new conv: String) -> String? {
        guard let sn = MTPipeBook.secret(for: conv), let d = Data(base64Encoded: payload),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let t = o["t"] as? [String] else { return nil }
        let heard = Set(t.prefix(slots))
        let dying = Set(MTPipeBook.dyingAll())
        let matches = MTPipeBook.allByFreshness().filter { q in
            q != conv && !dying.contains(q) && (MTPipeBook.secret(for: q).map { heard.contains(tag("mt-same-ask", $0, sn)) } ?? false)
        }
        if let q = matches.first(where: { waiting($0) == nil }) { return q }
        if let q = matches.first(where: { !(waiting($0)?.contains(conv) ?? false) }) { return q }
        let mine = rank(sn)
        return matches.first { q in MTPipeBook.secret(for: q).map { rank($0).lexicographicallyPrecedes(mine) } ?? false }
    }
    /// The answer, one shape for «yes» and «no»: the proof over the chosen pipe, or a tag nobody can check.
    static func answer(_ older: String?, new conv: String) {
        guard let sn = MTPipeBook.secret(for: conv) else { return }
        let p = older.flatMap { MTPipeBook.secret(for: $0) }.map { tag("mt-same-yes", $0, sn) } ?? noise()
        guard let d = try? JSONSerialization.data(withJSONObject: ["p": p]) else { return }
        MontanaDeliveryEngine.shared.enqueue(to: conv, chat: conv, mid: "same-" + UUID().uuidString,
                                             text: sameYesMark + d.base64EncodedString(), silent: true)
        MontanaP2PTrace.mark("same_answer", "conv=\(String(conv.prefix(10))) proof=\(older == nil ? 0 : 1)")
    }
    /// The asker's reading of the answer: the pipe the other side proved, or none.
    static func proven(answer payload: String, new conv: String) -> String? {
        guard let sn = MTPipeBook.secret(for: conv), let d = Data(base64Encoded: payload),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let p = o["p"] as? String else { return nil }
        return MTPipeBook.all().first { q in q != conv && (MTPipeBook.secret(for: q).map { tag("mt-same-yes", $0, sn) == p } ?? false) }
    }
    /// They wrote into a pipe folded here: the answer may have been lost on the way, so it is said again, once an hour at most.
    static func remind(_ folded: String) {
        let now = Date().timeIntervalSince1970
        lock.lock()
        let due = now - (reminded[folded] ?? 0) > 3600
        if due { reminded[folded] = now }
        lock.unlock()
        guard due else { return }   // SILENT-OK: said within the hour
        answer(merged(folded), new: folded)
    }

    // -- a folded pipe forwards into its conversation until it dies --
    static let mergedKey = "sameMerged"
    private static var kept: [String: String]?
    private static func book() -> [String: String] {
        lock.lock(); let k = kept; lock.unlock()
        if let k { return k }
        let read = MontanaLocalVault.getDecrypted(mergedKey).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        lock.lock(); if kept == nil { kept = read }; let now = kept ?? read; lock.unlock()
        return now
    }
    static func merged(_ conv: String) -> String? { book()[conv] }
    /// The conversation a pipe speaks for: itself, or the one it was folded into.
    static func root(_ conv: String) -> String {
        let b = book()
        var c = conv
        for _ in 0..<8 { guard let n = b[c], n != c else { return c }; c = n }
        return c
    }
    /// Every pipe folded into this conversation.
    static func folded(into conv: String) -> [String] { book().keys.filter { $0 != conv && root($0) == conv } }
    static func noteMerged(_ newer: String, into older: String) {
        var m = book()
        m[newer] = older
        m = m.filter { MTPipeBook.holds($0.key) }   // a folded pipe that died forwards nothing more
        lock.lock(); kept = m; lock.unlock()
        if let d = try? JSONEncoder().encode(m) { _ = MontanaLocalVault.setEncrypted(mergedKey, d) }
    }
}

extension ChatStore {
    /// Two pipes proven to be one person: whichever conversations they speak for become one.
    @MainActor
    func joinSamePerson(_ pipe: String, _ proven: String) {
        let a = MTSamePair.root(pipe), b = MTSamePair.root(proven)
        guard a != b else { MontanaP2PTrace.mark("same_one", "conv=\(String(pipe.prefix(10)))"); return }
        foldConversation(a, into: b)
    }
    /// THE FOLD (24.09, MTSamePair): the newer conversation's letters join the older one's feed, journal and archive, the
    /// newer row leaves, the older one comes back if it was hidden (unless the person is blocked there — the block follows
    /// the person), the meeting books open the older one, and the newer pipe forwards into it until it dies.
    @MainActor
    func foldConversation(_ newer: String, into older: String) {
        guard newer != older, !newer.isEmpty, !older.isEmpty,
              MTSamePair.merged(older) == nil, MTSamePair.merged(newer) == nil else { return }
        let moved = messages[newer] ?? []
        var feed = messages[older] ?? []
        let had = Set(feed.compactMap { $0.msgId })
        let add = moved.filter { m in m.msgId.map { !had.contains($0) } ?? true }
        if !add.isEmpty {
            feed.append(contentsOf: add)
            feed.sort(by: ChatStore.before)
            messages[older] = feed
            for m in add { _ = MTRowJournal.put(older, m); archiveRow(older, m) }
            // THE RECEIPT THAT CAME BEFORE THE FOLD (24.09): in the fold's minute the other side answers over the pipe it
            // already speaks for; the receipt found no row there and waited among the orphans — the moved row takes it
            // through the ladder's one door.
            for m in add where m.isFromMe {
                guard let sid = m.msgId else { continue }
                let bare = sid.hasPrefix("mid:") ? String(sid.dropFirst(4)) : sid
                guard orphanDelivered.contains(bare),
                      let i = messages[older]?.firstIndex(where: { $0.msgId == sid }) else { continue }
                noteOrphanDelivered(bare, keep: false)
                if advance(older, i, to: .delivered) { MontanaP2PTrace.mark("born_delivered", mid: bare, "its receipt had landed before the fold") }
            }
        }
        if let last = feed.max(by: ChatStore.before) {
            noteListState(older, last: last)
            noteOrder(older, at: Int(last.createdAt * 1000))
        }
        messages[newer] = nil
        noteListState(newer, last: nil)
        MTRowJournal.dropChat(newer)
        LiveDraftState.purgeConversation(newer)
        MontanaArchive.deleteChatFolder(convRef: newer)
        if let seen = peerSeenAt[newer] { noteSeen(older, at: seen, by: "fold") }
        pinnedChats.remove(newer)
        forcedUnread.remove(newer)
        if !refuses(older) { deletedChats.remove(older) }
        MTSamePair.noteMerged(newer, into: older)
        MontanaMeeting.repoint(from: newer, to: older)
        dropShelfRow(newer)
        recalcBadge()
        Self.writeSnapshotNow(messages)
        MontanaP2PTrace.mark("same_fold", "from=\(String(newer.prefix(10))) into=\(String(older.prefix(10))) rows=\(add.count)")
        if openConv == newer { NotificationCenter.default.post(name: .openChatRequest, object: nil, userInfo: ["address": older]) }
    }
}
