//
//  MontanaBubble.swift
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


// A message of ONLY emoji, up to three of them, renders like a sticker: large glyph, no
// bubble. Four and more = an ordinary text bubble (the author's word 27.08).
func characterIsEmoji(_ ch: Character) -> Bool {
    let sc = ch.unicodeScalars
    if sc.contains(where: { $0.properties.isEmojiPresentation }) { return true }     // 😀 🔥 👍 default-emoji
    if sc.count > 1 && sc.contains(where: { $0.properties.isEmoji }) { return true } // ❤️ 1️⃣ VS16 / keycap
    if sc.count >= 2 && sc.allSatisfy({ (0x1F1E6...0x1F1FF).contains($0.value) }) { return true } // 🇷🇺 flags
    return false
}
func isAllEmoji(_ s: String) -> Bool {
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    if t.isEmpty { return false }
    for ch in t where !ch.isWhitespace {
        if !characterIsEmoji(ch) { return false }
    }
    return true
}
// SSOT for the big-glyph render: a panel sticker, or a typed emoji-only message of <=3 glyphs.
func bigEmojiText(_ text: String) -> String? {
    if let st = stickerOf(text) { return st }
    if isControlMarker(text) { return nil }
    guard isAllEmoji(text) else { return nil }
    let glyphs = text.trimmingCharacters(in: .whitespacesAndNewlines).filter { !$0.isWhitespace }
    return glyphs.count <= 3 ? text : nil
}
let montanaStickers: [String] = ["😀","😂","🥰","😎","😍","🤩","😭","😤","🤔","👍","👎","🙏","👏","🔥","🎉","❤️","💔","💯","✅","🙌","🤝","👀","🥳","😉","😢","😱","🤯","💪","🌟","🤗"]

// Native bubble outline: a rounded rectangle with a small tail hooking out
// of the bottom corner on the sender's side (mine = right, peer = left). Messages in
// the middle of a group carry no tail — just the rounded rectangle.
/// The bubble is an octagon (the author's word 09.09): the same cut as the title plate,
/// bounded so a tall photo keeps its picture. The side of the feed says whose letter it is;
/// `mine` and `tail` stay for the callers, the geometry no longer depends on them.
struct BubbleShape: Shape {
    var mine: Bool
    var tail: Bool
    static let cut: CGFloat = 14
    func path(in rect: CGRect) -> Path {
        if MontanaSkin.isNative { return Path(roundedRect: rect, cornerRadius: 18) }
        return MontanaLongOctagon(maxCut: BubbleShape.cut).path(in: rect)
    }
}

/// THE ONE BUBBLE STYLE ([C-1], 25.09): the fill and the rim a letter wears -- mine and a correspondent's -- read from the
/// one stored style. The letter's bubble draws it, and so does anything that stands on a ground as a letter does: a post on
/// a wall (the author's word 25.09: «the wall in our style -- liquid glass and transparent bubbles»).
enum MTBubbleStyle {
    static var style: String { UserDefaults.standard.string(forKey: "bubbleStyle") ?? "montana" }
    // theme readers (custom style stores hex colors + doubles in UserDefaults)
    static func hex(_ k: String, _ d: String) -> Color { Color(montanaHexString: BT.hex(k, UserDefaults.standard.string(forKey: k) ?? d)) }
    static func dbl(_ k: String, _ d: Double) -> Double { UserDefaults.standard.object(forKey: k) == nil ? d : UserDefaults.standard.double(forKey: k) }
    @ViewBuilder static func fill(mine: Bool, own: Color) -> some View {
        let s = style
        if s == "custom" {
            let t = mine ? "cbMine" : "cbPeer"
            LinearGradient(colors: [hex(t+"Fill1", mine ? BT.mF1 : BT.pF1),
                                    hex(t+"Fill2", mine ? BT.mF2 : BT.pF2)],
                           startPoint: .top, endPoint: .bottom)
                .opacity(dbl(t+"Opacity", mine ? BT.mOp : BT.pOp))
        } else if s == "montana" {
            if MontanaSkin.isNative {
                MTLetterPlate(mine: mine)
            } else {
                // Muted black (the author's word 09.09): mine a shade deeper than theirs, both under one white rim.
                if mine { Color(white: 0.09) } else { Color(white: 0.13) }
            }
        } else {
            if mine { own } else { Color(white: 0.18) }
        }
    }
    @ViewBuilder static func outline(mine: Bool, _ shape: BubbleShape) -> some View {
        let s = style
        if s == "custom" {
            let t = mine ? "cbMine" : "cbPeer"
            shape.stroke(hex(t+"Outline", mine ? BT.mOl : BT.pOl)
                             .opacity(dbl(t+"OutlineOp", mine ? BT.mOlOp : BT.pOlOp)),
                         lineWidth: dbl(t+"OutlineW", mine ? BT.mOlW : BT.pOlW))
        } else if s == "montana", !MontanaSkin.isNative {
            shape.stroke(Color.white.opacity(0.35), lineWidth: 1)   // the thin white rim
        }
    }
    /// A correspondent's bubble standing on its own: the fill in the bubble's shape, under the bubble's rim.
    static func peerBubble() -> some View {
        let shape = BubbleShape(mine: false, tail: false)
        return fill(mine: false, own: .clear).clipShape(shape).overlay(outline(mine: false, shape))
    }
}

// THE SYSTEM'S OWN BUBBLES (the author's word 29.09: «the chat's bubbles as the system's -- no gradient, the system blue with
// white words, and the system grey with the same white»): mine the platform's blue, theirs the platform's grey, one flat colour
// each -- no gradient, no glass under it, no rim over it -- as the platform's own messages draw theirs; the words stay THE
// default's white (BT). The app is dark on every phone, so the grey resolves to its dark shade.
private struct MTLetterPlate: View {
    let mine: Bool
    var body: some View {
        BubbleShape(mine: mine, tail: false)
            .fill(mine ? MontanaOctagon.platformBlue : Color(uiColor: .systemGray5))
            .allowsHitTesting(false)
    }
}

// THE transfer board ([C-1]): the one owner of live transfer visibility (ring + status word),
// keyed by the media file name. The feed reconfigures cells only when a row's content
// fingerprint changes; a transfer tick is not content — the bubble observes this board from
// inside its own cell and redraws itself. Precedent 29.08: after the feed took ownership of
// its container, every progress ring froze at configure-time on BOTH sender and receiver —
// the frozen stages had been proven on the SwiftUI feed, and the container migration silently
// dropped live progress from the re-render contract.
final class MTTransferBoard: ObservableObject {
    static let shared = MTTransferBoard()
    @Published private(set) var progress: [String: Double] = [:]
    @Published private(set) var status: [String: String] = [:]
    func setProgress(_ key: String, _ v: Double?) {
        if let v { progress[key] = v } else { progress.removeValue(forKey: key) }
    }
    func setStatus(_ key: String, _ v: String?) {
        if let v { status[key] = v } else { status.removeValue(forKey: key) }
    }
}

/// THE SEAL OF A LETTER AND ITS GEMATRIA (the author's words 02.10: «right of the time put the gematria number of every
/// bubble», «so that the chat's feed becomes a feed of time with gematria marks»): one number, the same on both phones.
/// The seal is SHA-256 over the letter's one name and nothing else. The name («mid:t» + birth millisecond + «-» + uuid) is
/// minted once by the sender (ChatStore.mintMid), carries the moment of sending, rides in the sealed body byte for byte
/// (MTPipe body: mid, zero, words) and is the row's name on both sides. Nothing else is held alike by the two phones: no
/// field names the sender (an envelope names nobody; isFromMe is the opposite on the other side), the words change by an
/// edit the receiver may refuse or never get, a missed call is rewritten on arrival, the words of a long letter may never
/// come. A row without a wire name (restored from the archive) has no shared seal and wears
/// none. Computed once per name and kept: the feed redraws, a name never changes.
enum MTLetterSeal {
    static let domain = "montana-letter-seal"
    /// What a letter's stamp wears of its seal: the head of the seal and its gematria, counted together once.
    final class Mark { let head: String; let gematria: Int; init(_ h: String, _ g: Int) { head = h; gematria = g } }
    private static let kept: NSCache<NSString, Mark> = {
        let c = NSCache<NSString, Mark>()
        c.countLimit = 4096
        return c
    }()
    static func seal(_ mid: MID) -> String? {
        guard mid.hasPrefix("mid:") else { return nil }
        return MTBoard.digest(domain + "\n" + mid)
    }
    /// The letter's mark, or nil for a row with no wire name: the seal's first eight hex digits and its prime sum
    /// (MTBoard.gematria, the wall's own count).
    static func mark(_ m: Message) -> Mark? {
        let key = m.mid as NSString
        if let k = kept.object(forKey: key) { return k }
        guard let h = seal(m.mid) else { return nil }
        let k = Mark(String(h.prefix(8)), MTBoard.gematria(h))
        kept.setObject(k, forKey: key)
        return k
    }
}

/// THE RIBBON OF TIME (the author's words 02.10 18:29 and 19:24: the coin on, «the fabric of time unfolds in the chat with
/// the peer»): set by the conversation over its rows while its coin is on; every stamp then wears the head of its letter's
/// seal beside the gematria -- each bubble a link of the chain with its own seal.
private struct MTTimeRibbonKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues { var mtTimeRibbon: Bool { get { self[MTTimeRibbonKey.self] } set { self[MTTimeRibbonKey.self] = newValue } } }

struct MessageBubble: View, Equatable {
    @Environment(\.mtWindowSize) private var mtWin
    @Environment(\.mtTimeRibbon) private var ribbon
    let message: Message
    /// The one player, read and asked -- never watched whole (28.09): the bubble watches the player's face (VoicePlayer.Face),
    /// and only the playing bubble's wave watches its clock (MTAudioLive).
    let player: VoicePlayer
    @ObservedObject private var playFace = VoicePlayer.shared.face
    private let imgFrameBox = MTFrameBox()
    /// The picture's own frame in the plate's space (the author's word 22.09): a tap on the caption's words is
    /// not a tap on the picture — only the picture opens the picture.
    private let mediaPlateBox = MTFrameBox()
    var onTapImage: (CGRect?) -> Void = { _ in }   // the bubble's on-screen frame rides with the tap (fly-out source)
    var onTapVideo: () -> Void = {}
    var onTapNote: (String, CGRect?) -> Void = { _, _ in }   // the round note flies out of its bubble and opens over the feed (the author's word 15.09)
    private let noteFrameBox = MTFrameBox()
    var onTapDoc: () -> Void = {}
    var onTapPlace: (MTPlaceLetter) -> Void = { _ in }   // a place a letter carries opens its own page over everything
    var onTapMusic: (String) -> Void = { _ in }   // music starts on the full page
    var onTapChess: (String) -> Void = { _ in }
    /// The invitation waits for this phone's answer (MTChessSend.awaitsMe): its two buttons stand under it.
    var chessOpen = false
    var onChessDecline: (String) -> Void = { _ in }
    /// What the game this letter closes gave or took from this phone (MTChessCoins.net); nil where it holds no pot.
    var chessNet: Int? = nil
    /// The Accept under an invitation that waits for this phone: the one door of an acceptance from the chat (MTChessSend.join).
    var onChessAccept: (String) -> Void = { _ in }
    /// An invitation answered: the game's state in its words (accepted and played, declined, over); nil while it waits.
    var chessStatus: String? = nil
    var onTapWallPost: (MTWallCard) -> Void = { _ in }   // a post's card opens the wall the post stands on (30.09)
    var onTapCoin: () -> Void = {}   // a coin letter opens its own move (05.10)
    var onTapReply: (MID) -> Void = { _ in }
    var tail: Bool = true     // show the "tail" (on the last one in the group),
    var quoteAuthor: String? = nil   // the quoted letter's author name (heads the quote block)
    var voiceSender = ""             // who speaks in this voice message — the player's heading
    var onPlayVoice: (String) -> Void = { _ in }   // the chat starts it with the chat's voices behind it
    // UNIFIED media progress 0..1 (compression+send in one ring) — read LIVE off the board:
    // the cell is not reconfigured per tick, the bubble redraws itself ([C-1]).
    @ObservedObject private var transfers = MTTransferBoard.shared
    // The answers under this letter, read live — the row is not rebuilt for them.
    @ObservedObject private var reactionBoard = MTReactionBoard.shared
    /// The coins given on letters (MTCoinLedger): the coin total stands under the letter beside its answers (03.10).
    @ObservedObject private var coinBook = MTLocalCoinLedger.shared
    private var mediaFileKey: String {
        message.videoFile ?? message.imageFile ?? message.audioFile ?? message.docFile ?? ""
    }
    var mediaProgress: Double? { transfers.progress[mediaFileKey] }
    var mediaStatus: String? { transfers.status[mediaFileKey] }
    var onCancel: () -> Void = {}      // cancel the upload (cross button)
    @State private var scrubPos: Double? = nil   // finger on the track bar: live motion until release
    @State private var wave: [Float]? = nil      // the track's waveform (60 probes, MTWaveform cache)
    @State private var pendingPos: Double? = nil // a seek before playback: the position waits for ▶
    var onResend: () -> Void = {}      // resend on failure
    var onTapReaction: (String) -> Void = { _ in }   // my own answer, taken back where it is shown
    /// WHO ANSWERED (the author's word 20.09): the plate carries the face of the one who put it —
    /// the correspondent's face beside the peer's answer, one's own beside one's own. The faces are
    /// handed in as values (the bubble lives in the feed and in the menu window alike).
    var faces: MTReactionFaces? = nil
    // In the menu the text belongs to the finger: the person selects a piece of it and
    // works with it by the system's own hand. In the feed the same text is not selectable —
    // there the long press is the menu's, and two owners of one touch is a race.
    var textIsSelectable: Bool = false
    /// The status under the LAST own letter, in words (15.47, the author's word): «Delivered»,
    /// «Read», «Sent» — nil on every other row. Checkmarks left the bubble with it.
    var ladder: Bool = false          // the ladder line stands under this bubble (the last own letter on a wire)
    // ── A MEDIA GROUP (19.09) ──────────────────────────────────────────────────
    // Pictures and videos picked together stand on ONE plate: the tiles in the sender's order, cut
    // by MTMosaic; one caption under them (the one letter that carries words); one stamp. Every
    // letter keeps its own file, progress and status — the plate only draws them side by side, and
    // its one tap finds the tile under the finger.
    var members: [Message] = []
    var onTileTap: (Message) -> Void = { _ in }
    private let tileFrames = MTTileFrames()
    static let plateSpace = "mtBubblePlate"
    var isGroup: Bool { members.count > 1 }
    /// The one caption of the plate: the words of the single letter that carries any. Two letters
    /// with words is no caption — nothing is guessed.
    var groupCaption: String {
        let worded = members.filter { !$0.text.isEmpty }
        return worded.count == 1 ? worded[0].text : ""
    }
    /// The plate's one status: the stage of its slowest letter (MTLadder) -- the stamp, the line under the plate and the
    /// chat row read one rung.
    var groupStatus: DeliveryStatus { (MTLadder.lead(members) ?? message).deliveryStatus }
    var stampStatus: DeliveryStatus { isGroup ? groupStatus : message.deliveryStatus }
    var anyProgress: Bool {
        isGroup ? members.contains { transfers.progress[$0.imageFile ?? $0.videoFile ?? ""] != nil } : mediaProgress != nil
    }
    @AppStorage("bubbleColorIndex") private var bubbleColorIndex: Int = 0
    @State private var thumbTick = 0   // async video preview ready → redraw the bubble

    // Skip redrawing unchanged bubbles during typing/polling.
    // We compare only the visible fields; action closures and player don't affect the appearance.
    static func == (l: MessageBubble, r: MessageBubble) -> Bool {
        l.message.id == r.message.id
            && l.message.text == r.message.text
            && l.message.deliveryStatus == r.message.deliveryStatus
            && l.ladder == r.ladder
            && l.message.reactions == r.message.reactions
            && l.message.edited == r.message.edited
            && l.message.isRead == r.message.isRead
            && l.message.heard == r.message.heard
            && l.message.imageFile == r.message.imageFile
            && l.message.videoFile == r.message.videoFile
            && l.message.audioFile == r.message.audioFile
            && l.message.docFile == r.message.docFile
            && l.tail == r.tail
            && l.chessOpen == r.chessOpen && l.chessNet == r.chessNet && l.chessStatus == r.chessStatus
            && l.members.map(\.id) == r.members.map(\.id)
            && l.members.map(\.text) == r.members.map(\.text)
            && l.members.map(\.deliveryStatus) == r.members.map(\.deliveryStatus)
            && l.members.map { $0.imageFile ?? $0.videoFile } == r.members.map { $0.imageFile ?? $0.videoFile }
            && l.textIsSelectable == r.textIsSelectable
            // The face of a letter is drawn from the board, so equality asks the board as well —
            // otherwise a row could be called unchanged while what stands under it has changed.
            && MTReactionBoard.shared.shown(l.message).plates == MTReactionBoard.shared.shown(r.message).plates
            && MTReactionBoard.shared.shown(l.message).mine == MTReactionBoard.shared.shown(r.message).mine
            && MTLocalCoinLedger.shared.coins(on: l.message.mid) == MTLocalCoinLedger.shared.coins(on: r.message.mid)
            && l.player.playingFile == r.player.playingFile
    }

    // One shared indicator on the bubble: a ring with % for the whole path (video: 0…30% compression, 30…100% upload).
    /// The compact progress pill: the ring, the status or the percent, the cancel cross. On a plate
    /// it stands top-left over the dim (mediaProgressOverlay); under the orb and the round note it
    /// stands in the line beneath, bottom-left, where the voice's duration stands (the author's word
    /// 21.09) — the circle itself is never dimmed or squared.
    @ViewBuilder func progressPill(_ p: Double) -> some View {
        HStack(spacing: 7) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.35), lineWidth: 2)
                Circle().trim(from: 0, to: CGFloat(max(0, min(1, p))))
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.3), value: p)
            }
            .frame(width: 18, height: 18)
            Text(mediaStatus ?? "\(Int(p * 100))%")
                .font(.system(size: 11, weight: .semibold)).foregroundColor(.white)
            Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundColor(.white)
                .frame(width: 20, height: 20).background(Color.black.opacity(0.55), in: MontanaLongOctagon())
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Color.black.opacity(0.6), in: MontanaLongOctagon())
        // THE PILL STAYS INSIDE THE SCREEN (the author's word 22.09: «the loading field went off the
        // left edge»). Under the orb it stands in a half-width slot with its own size, and a status
        // in words -- «In queue», «Sending» -- is far wider than the orb: the pill grew outward and
        // walked off the edge. Its words are held to one line and its whole width to the plate's own
        // ceiling, which no screen of ours is narrower than.
        .lineLimit(1)
        .frame(maxWidth: MessageBubble.plateCeiling, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
    @ViewBuilder var mediaProgressOverlay: some View {
        if let p = mediaProgress {
            VStack {
                HStack {
                    // compact banner TOP-LEFT: indicator + status + cancel (no central ring)
                    progressPill(p)
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.black.opacity(0.2))
        }
    }

    // Media send failure → red tappable "resend" banner.
    @ViewBuilder var failedResendBadge: some View {
        if message.isMine && stampStatus == .failed && !anyProgress,
           message.msgId != nil || message.videoFile != nil || message.imageFile != nil
               || message.audioFile != nil || message.docFile != nil {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.arrow.circlepath").font(.system(size: 11, weight: .bold))
                Text("Retry").font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Color.red, in: MontanaLongOctagon())
            .fixedSize()
        }
    }
// The bubble and the retry button are one row, not an overlay: the letter stays readable
// whole, and the button lives beside it without stealing its corner.
struct MTResendBeside<Badge: View>: ViewModifier {
    let badge: Badge
    func body(content: Content) -> some View {
        HStack(alignment: .center, spacing: 6) {
            badge
            content
        }
    }
}
/// The same row manner, on the other side: the save circle stands to the RIGHT of their bubble.
/// THE MIDDLE OF THE MEDIA (the author's word 20.09, item 21): the save circle stands level with
/// the picture, not with the whole bubble and its caption. The platform's own way: a custom
/// vertical alignment — the media plate names its centre as this guide, and the guide carries up
/// through the stacks to the row; a bubble that names none (text, a file) answers with its centre.
struct MTSaveBeside<Badge: View>: ViewModifier {
    let badge: Badge
    func body(content: Content) -> some View {
        HStack(alignment: .mtMediaMiddle, spacing: 6) {
            content
            badge.alignmentGuide(.mtMediaMiddle) { $0[VerticalAlignment.center] }
        }
    }
}

    // color of my messages — chosen by the user from the palette
    var myColor: Color {
        bubblePalette[min(max(bubbleColorIndex, 0), bubblePalette.count - 1)]
    }

    // Native bubble shape — fully rounded, with a little tail hooking
    // out of the bottom corner on the sender's side (last message in a group).
    var bubbleShape: BubbleShape { BubbleShape(mine: message.isMine, tail: tail) }

    // ── THE MESSAGE GESTURE SSOT (hook) ───────────────────────────────────────
    // EXACTLY ONE gesture node — the bubble root (body below): long-press = menu,
    // tap = primaryTap(). primaryTap is the ONE primary-action function for ANY
    // message type with any payload: transfer running → cancel; failure → retry;
    // photo/video/file → open; voice → play/pause; text with a quote → to the
    // original; plain text → nothing. INSIDE bubbles the content only DRAWS; what is a
    // control (play, a reaction, save) is a Button — never a glyph with a tap on it, never a
    // gesture of ours. The hold belongs to the feed (a UIKit long press on the collection view
    // that cancels the touch when it begins); the tap is the letter's own, and it cannot fire on
    // a finger the hold has taken. A new message type = a new branch IN THIS FUNCTION, not a new
    // gesture.
    private func primaryTap(at point: CGPoint? = nil) {
        if isGroup {
            // The plate's tap is the tile's (19.09): a tile still riding is harmless, like a single
            // riding letter; any other tile takes the single picture's own road (onTileTap).
            guard let point, let m = members.first(where: { tileFrames.rect(for: $0.id).contains(point) }) else { return }
            if transfers.progress[m.imageFile ?? m.videoFile ?? ""] != nil {
                MontanaP2PTrace.mark("upload_tap", "ignored — the tile keeps riding")
                return
            }
            onTileTap(m)
            return
        }
        if mediaProgress != nil {
            // A tap on a riding letter is HARMLESS: four sends died
            // tonight to accidental touches while the bubble was being inspected (23.08
            // 01:49-01:57, status=5 seconds after start). Stopping is an explicit act —
            // delete the bubble; its transport dies with the row by construction.
            MontanaP2PTrace.mark("upload_tap", "ignored — the letter keeps riding")
            return
        }
        if message.isMine, message.deliveryStatus == .failed,
           message.msgId != nil || message.imageFile != nil || message.videoFile != nil
               || message.docFile != nil || message.audioFile != nil {
            onResend(); return   // any failed bubble: tap = resend (the author's invariant 24.08)
        }
        // A CAPTIONED PICTURE OPENS ONLY FROM THE PICTURE (the author's word 22.09): the finger on the
        // words under it is a finger on words — nothing opens; the frame is the picture's own, measured
        // in the plate's space as the tiles' are.
        if !message.text.isEmpty, message.imageFile != nil || message.videoFile != nil,
           let point, mediaPlateBox.rect != .zero, !mediaPlateBox.rect.contains(point) {
            MontanaP2PTrace.markFolded("media_tap", "on the caption — nothing opens", window: 10)
            return
        }
        // AN INVITATION THAT WAITS FOR MY ANSWER OPENS NOTHING (the author's word 06.10.2026 23:5x MSK): its two buttons decide.
        if let game = message.chessLetter?.game { if !chessOpen { onTapChess(game) }; return }
        if message.coinLetter != nil { onTapCoin(); return }   // a coin letter: its transaction (05.10)
        if let card = MTWallCard.of(message.text) { onTapWallPost(card); return }   // a post's card: its wall
        if message.imageFile != nil { onTapImage(imgFrameBox.rect == .zero ? nil : imgFrameBox.rect); return }
        if let v = message.videoFile, v.hasPrefix("vnote_") { onTapNote(v, noteFrameBox.rect == .zero ? nil : noteFrameBox.rect); return }   // the round note: its own window, never the player
        if message.videoFile != nil { onTapVideo(); return }
        if let df = message.docFile {
            if (mtIsAudioName(message.docName ?? "") || mtIsAudioName(df)),
               FileManager.default.fileExists(atPath: attachmentURL(df).path) {
                return   // music: the bubble is silent on tap — ONLY the button plays (the author's word)
            }
            // A MOVING PICTURE IS STOPPED OR PLAYED BY THE FINGER, NOT OPENED (the author's word 23.09): a tap on
            // a playing one stops it on its frame, a tap on a standing one plays three cycles. The state is the
            // book's (MTGifPlay), by the file, so no rebuild of this bubble can reset it.
            if MontanaGif.isGif(message.docName ?? df) || MontanaGif.isGif(df) {
                let playing = MTGifPlay.shared.toggle(attachmentURL(df))
                MontanaP2PTrace.markFolded("gif_tap", playing ? "playing three cycles" : "stopped", window: 10)
                return
            }
            onTapDoc(); return
        }
        if let af = message.audioFile { voiceToggle(af); return }   // THE WHOLE BUBBLE PLAYS THE VOICE (the author's word 28.09)
        if let place = placeLetter { onTapPlace(place); return }            // a place — its own page, the map over the whole screen
        if let rid = message.replyToId { onTapReply(rid); return }        // text with a quote — to the original
    }
    var body: some View {
        HStack {
            if message.isMine { Spacer(minLength: 38) }
            VStack(alignment: message.isMine ? .trailing : .leading, spacing: 3) {
                // THE FORWARD MARK — ONE place for every kind of letter (the author's word 16.09):
                // text, picture, video, voice, round note, file alike wear it above the bubble.
                if message.isForwarded {
                    Label("Forwarded", systemImage: "arrowshape.turn.up.right")
                        .font(.caption).foregroundColor(.gray)
                        .padding(.horizontal, 6)
                }
                bubbleUnderFinger
                    // The bubble's OWN window rect — the face, not the row: the flight lands on it,
                    // the reply swipe admits from its top line down (22.09), the menu stands on its top.
                    .background { if !textIsSelectable { MTBubbleFrameAnchor(id: message.id) } }
                    .frame(maxWidth: (mtWin.width > 0 ? mtWin.width : MTScene.size().width) * 0.80, alignment: message.isMine ? .trailing : .leading)
                if ladder {
                    // THE LADDER UNDER THE BUBBLE (the author's word 08.09): three dots along the
                    // bottom — sent, delivered, read — each lit the moment its rung is reached, and
                    // beside them the one word of the rung the letter stands on (MTDeliveryLine). A plate stands
                    // where its slowest letter stands (MTLadder, 29.09), never where its first one does.
                    let lead = isGroup ? (MTLadder.lead(members) ?? message) : message
                    MTDeliveryLine(status: lead.deliveryStatus, played: MTPlayed.of(lead)).padding(.trailing, 4)
                }
                let face = reactionBoard.shown(message)
                let shown = face.plates
                let mineNow = face.mine
                let peerNow = reactionBoard.peerOf(message)
                // ONE PLATE PER ANSWER, THE FACES ON IT: the same emoji from both sides is one plate
                // with two faces, never two plates (a ForEach over repeated names drew one twice).
                let plates = shown.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
                let coinsOn = coinBook.coins(on: message.mid)
                if !plates.isEmpty || coinsOn > 0 {
                    HStack(spacing: 4) {
                        // THE COINS ON THE LETTER (the author's word 03.10 13:40): the total given on it, on this phone's book.
                        if coinsOn > 0 {
                            HStack(spacing: 4) {
                                MTMintCoin(spinning: false, side: 16)
                                // USER-DATA: the number of coins given on this letter
                                Text(verbatim: MTCoinText.count(coinsOn)).font(.system(size: 15, weight: .semibold).monospacedDigit())
                            }
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(Color(white: 0.22))
                            .clipShape(MontanaLongOctagon())
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(Text("Coins"))
                        }
                        ForEach(plates, id: \.self) { r in
                            // WHOSE PLATE (the author's word 20.09, [C-1]): the peer's face stands only on
                            // the answer the peer is NAMED on. A plate nobody is named on — an answer
                            // stored before the names — wears no face and answers no tap; it was drawn as
                            // the peer's by count alone, and so one's own answer came back from a reload
                            // wearing the correspondent's face. A room with no correspondent (Saved
                            // Messages) has no peer to name — every plate there is one's own.
                            let theirs = !(faces?.solo ?? false) && peerNow == r
                            // MY OWN ANSWER IS TAKEN BACK WHERE IT IS SHOWN. A person who put it
                            // there looks for it there, not in a menu two gestures away. The
                            // peer's answer is not mine to remove, so it does not answer a tap.
                            Button { MTTouchClaim.claim(); if mineNow == r { onTapReaction(r) } } label: {
                                // The face on the left, the answer on the right, a little larger (the author's word 20.09).
                                HStack(spacing: 4) {
                                    if theirs, let f = faces {
                                        AvatarCircle(photoURL: f.peerPhoto, color: f.peerColor, initial: f.peerInitial, size: 18)
                                    }
                                    if mineNow == r {
                                        MTSelfFace(size: 18, initial: MontanaAvatar.initial(title: E2E.myDisplayName(), name: ""))
                                    }
                                    Text(r).font(.system(size: 16))
                                }
                                    .padding(.horizontal, 9).padding(.vertical, 4)
                                    .background(Color(white: mineNow == r ? 0.30 : 0.22))
                                    .clipShape(MontanaLongOctagon())
                                    // The platform's least target around a small plate: the touch shape
                                    // grows to 44 points, the row keeps the plate's own height.
                                    .padding(.vertical, 12).padding(.horizontal, 4)
                                    .contentShape(Rectangle())
                                    .padding(.vertical, -12).padding(.horizontal, -4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            if !message.isMine { Spacer(minLength: 38) }
        }
    }

    // WHO OWNS THE TOUCH — decided here, once. In the feed it is the menu: ONE long press on
    // the whole bubble, so text, photo, video and file answer identically, and the opening tap
    // is secondary. In the menu it is the text: the feed's gestures are not installed at all,
    // and the system's selection is left alone with the finger.
    private var bubbleUnderFinger: some View {
        Group {
            if textIsSelectable {
                bubble
            } else {
                bubble
                    // THE HOLD IS THE FEED'S (19.09): a UIKit long press on the feed opens the menu
                    // and cancels this touch by the platform's rule — so the tap below cannot fire on
                    // the same finger, and no flag is needed. The tap stays the letter's own, in the
                    // bubble's OWN coordinate space: the tiles' frames and the finger are measured in
                    // it, so the feed's flips and the window's transforms never enter the comparison.
                    // A Button inside the letter WINS over this tap (the reference fails its recogniser
                    // over a button): a child's gesture takes precedence, so play, a reaction and save
                    // never also open the letter.
                    .gesture(SpatialTapGesture(coordinateSpace: .named(MessageBubble.plateSpace)).onEnded { v in
                        primaryTap(at: v.location)
                    })
                    .coordinateSpace(name: MessageBubble.plateSpace)
            }
        }
        // The save circle stands OUTSIDE the gesture node (the author's word 11.09: «saving must not
        // open the picture»). The retry plate stays inside: it IS the root's tap.
        .modifier(MTSaveBeside(badge: saveBesideBadge))
    }

    // The words of a letter. In the feed they are drawn text and nothing more. In the menu the
    // system's own text view draws them, so a PART of them can be taken — knobs, magnifier, drag,
    // and the system's menu over what is chosen. SwiftUI's own selection was tried first and
    // named: it takes the whole block and offers one Copy, which is copying a letter, not
    // selecting text.
    @ViewBuilder private func words(_ s: String, _ font: UIFont) -> some View {
        if textIsSelectable {
            MTMessageText(text: MTRowLetter.words(s), font: font, color: UIColor(bubbleText))
        } else if !MTLinks.urls(in: s).isEmpty {   // the finder's own gate and its kept answer (MTLinks.urls, 28.09)
            // A LETTER THAT CARRIES A LINK IS DRAWN BY THE PLATFORM (the author's word 22.09): its own
            // text view finds the link — a bare host among other words too — and takes the touch only
            // where the link lies; everything else of the letter keeps the tap it had (MTLinkedText).
            MTLinkedText(text: MTRowLetter.words(s), font: font, color: UIColor(bubbleText),
                         linkColor: UIColor(MontanaNativeBubble.link(mine: message.isMine)))
        } else {
            Text(s).montanaTextScale()   // the letters follow the person's size; nothing else does
        }
    }

    @ObservedObject private var fold = MTFilterFold.shared   // the filter's fold, opened for the letter by the person's tap
    private static let burgundy = Color(red: 0.50, green: 0.0, blue: 0.13)
    /// THE GAME'S LETTER IN THE CHAT (the author's words 06.10.2026 23:2x MSK: «in the invitation, at once, the stake -- as chess and
    /// coins, beautifully -- and below two buttons: the blue system Accept and the red burgundy Decline the game at a stake»; «after
    /// the game show the coins' transfer or top-up»): the invitation says who plays which colour with the clock (29.09) and its
    /// stake under our coin; while it waits for this phone's answer the two buttons stand under it; the letter that closes a game
    /// wears what the game gave or took. A tap elsewhere opens the game.
    private func chessBubble(_ chess: MTChessLetter) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 10) {
                MTChessIcon().frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Chess").font(.headline)
                    Text(chess.kind == .invite ? MTRowLetter.chessSeat(mine: message.isFromMe, seconds: chess.seconds ?? 0)
                         : chess.end != nil ? (MTRowLetter.chessBanner(chess).map { String($0.drop { ch in ch == "♟" || ch == " " }) }
                                               ?? String(localized: "Open game", bundle: MTLanguage.bundle))
                         : String(localized: "Open game", bundle: MTLanguage.bundle)).font(.subheadline)
                }
                Spacer(minLength: 0)
            }
            if chess.kind == .invite, let stake = chess.stake, 0 < stake {
                HStack(spacing: 6) {
                    MTMintCoin(spinning: false, side: 22)
                    // USER-DATA: the invitation's stake, whole
                    Text(verbatim: MTCoinText.count(stake)).font(.title3.bold().monospacedDigit())
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("stake \(MTCoinText.count(stake))"))
            }
            if let chessNet, chessNet != 0 {
                HStack { MTCoinDelta(coins: chessNet); Spacer(minLength: 0) }
            }
            // THE ANSWER STANDS ON THE INVITATION (the author's word 06.10.2026 23:5x MSK: «decline records the decision, sends the
            // answer, and the bubble records it as declined too»): both phones read the same replay, so both bubbles say it.
            if chess.kind == .invite, let chessStatus {
                Text(chessStatus).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
            }
            if chessOpen {
                HStack(spacing: 8) {
                    Button { onChessAccept(chess.game) } label: { Text("Accept the game").lineLimit(1).frame(maxWidth: .infinity, minHeight: 44) }
                        .buttonStyle(.borderedProminent).tint(.blue)
                    Button { onChessDecline(chess.game) } label: { Text("Decline the game").lineLimit(1).frame(maxWidth: .infinity, minHeight: 44) }
                        .buttonStyle(.borderedProminent).tint(Self.burgundy)
                }
                .font(.subheadline.weight(.semibold))
            }
            metaLine(onMedia: false)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(bubbleFill).foregroundColor(bubbleText)
        .clipShape(bubbleShape).overlay { bubbleOutline }
    }
    @ViewBuilder var bubble: some View {
        // The author's invariant (24.08): if anything en route left the receiver's chat
        // different from the sender's, the sender sees a resend button — on ANY bubble
        // kind. One attachment point at the bubble root ([C-1]), not per-kind copies.
        Group {
            if isGroup {
                groupBubble()
            } else if !message.isMine, !fold.opened.contains(message.id), MontanaSafety.filterOn, MontanaContentFilter.flags(message.text) {
                // THE FILTER (Guideline 1.2): a letter carrying an objectionable word stands
                // folded — nothing of it is read by surprise; the person's own tap unfolds it.
                // THE FOLD IS A BUTTON (the author's word 24.09: «it must always show on the tap»). It was a
                // tap gesture of ours inside the letter -- the second tap node the gesture law above forbids
                // (15.09: two nodes fired on one tap); a control inside a letter is a Button, and a Button
                // wins over the letter's own tap. The opening is the letter's (MTFilterFold), not this drawing's.
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { MTFilterFold.shared.open(message.id) }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Hidden by the filter", systemImage: "eye.slash").font(.callout)
                        Text("Tap to show").font(.caption).foregroundColor(bubbleText.opacity(0.7))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(bubbleFill).foregroundColor(bubbleText)
                    .clipShape(bubbleShape).overlay { bubbleOutline }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else if let chess = message.chessLetter {
                chessBubble(chess)
            } else if let card = MTWallCard.of(message.text) {
                wallCardBubble(card)
            } else if MTMoneyFlowRow.of(message.text) {
                // THE MONEY FLOW BEGAN (MTMoneyFlowRow): the chess invitation's card, our coin turning once as the row appears.
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 10) {
                        MTMintCoin(side: 40, turn: 0)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Money flow has begun").font(.headline)
                            Text("Every letter mints a coin").font(.subheadline)
                        }
                    }
                    metaLine(onMedia: false)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(bubbleFill).foregroundColor(bubbleText)
                .clipShape(bubbleShape).overlay { bubbleOutline }
            } else if let secret = MTSecretLetter.parse(message.text) {
                // A SECRET SHARED FROM PASSWORDS (MTSecretLetter, the author's word 06.10.2026 17:4x MSK): the key and the title; the
                // receiver's tap takes it into their own Passwords after the device owner's check.
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 12) {
                        Image(systemName: "key.fill").font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            // USER-DATA: the title of the shared secret
                            Text(verbatim: secret.title).font(.headline).lineLimit(2)
                            Text(message.isMine ? "Shared from Passwords" : "Tap to save to Passwords").font(.subheadline)
                        }
                    }
                    metaLine(onMedia: false)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(bubbleFill).foregroundColor(bubbleText)
                .clipShape(bubbleShape).overlay { bubbleOutline }
                .contentShape(Rectangle())
                .onTapGesture { if !message.isMine { MTPasswordVault.shared.incoming = secret } }
            } else if let coin = message.coinLetter {
                // THE COIN LETTER'S BUBBLE (the author's word 03.10 13:52): our coin on its face, the number, and who it went to.
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 12) {
                        MTMintCoin(spinning: false, side: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            // THE COINS THAT LEFT OR CAME (the author's word 06.10.2026 23:2x MSK): mine went, a minus; theirs came, a
                            // plus; a red letter's coins are back, the count alone.
                            if message.isMine, stampStatus == .failed {
                                // USER-DATA: the number of coins the letter carries
                                Text(verbatim: MTCoinText.count(coin.c)).font(.title2.bold().monospacedDigit())
                            } else {
                                MTCoinDelta(coins: message.isMine ? -coin.c : coin.c)
                            }
                            // NOT DELIVERED, RETURNED (the author's word 05.10.2026 01:40 MSK, MTCoinSend.hold): a red coin letter's coins are back.
                            Text(message.isMine ? (stampStatus == .failed ? "Not delivered, coins returned" : "Coins sent") : "Coins received").font(.subheadline)
                        }
                    }
                    metaLine(onMedia: false)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(bubbleFill).foregroundColor(bubbleText)
                .clipShape(bubbleShape).overlay { bubbleOutline }
            } else if let rel = releaseInfoOf(message.text) {
                releaseBubble(rel)
            } else if let ci = callInfoOf(message.text) {
                callBubble(ci)
            } else if message.imageFile == nil, message.videoFile == nil, message.audioFile == nil, message.docFile == nil,
                      let em = bigEmojiText(message.text) {
                // A ROW THAT OWNS A FILE IS A MEDIA ROW, WHATEVER ITS WORDS (29.09): a video shared from the gallery under a
                // caption of one to three emoji was drawn as the big glyphs alone — the file lay whole on both phones, the
                // letter was receipted, and neither person saw the video (T1 and its sender, 13:21). The glyph branch
                // speaks only for a row without a file; a captioned picture or video keeps its plate, the caption under it.
                VStack(alignment: .trailing, spacing: 2) {
                    if quoted {
                        replyQuote
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(bubbleFill).foregroundColor(bubbleText)
                            .clipShape(bubbleShape).overlay { bubbleOutline }
                    }
                    Text(em).font(.system(size: MTStickerLook.glyph)).fixedSize()   // the one number a sticker is three of
                    metaLine(onMedia: true)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.black.opacity(0.45), in: MontanaLongOctagon())
                }
            } else if let af = message.audioFile {
                // The voice's look is the person's (Settings → Appearance → Voice message style, 17.09):
                // the orb, or the histogram — the very plate a music track wears, in the text bubble's colours.
                voiceCapsuleBubble(af)   // a capsule of our letters' glass, drawn once (the author's word 28.09)
            } else if let f = message.imageFile {
                // A PICTURE IS NOT DECODED IN A RENDER PASS (28.09) -- the law the video's poster has kept since 23.08,
                // one line below. The whole photograph used to be decoded right here, on the main thread, in the body of
                // the cell: measured on T1 under 1966, a chat opened with a single frame of 637 ms
                // (motion what=chat:open late_cells=637ms/group1+photo1+text2+voice1). What is already decoded draws the
                // first frame, the shape comes from the file's header (pictureAspect), and the picture itself is decoded
                // off the main thread -- the bubble redraws when it lands.
                let ready = docImageCached(f)
                let _ = thumbTick                   // dependency: redraw when the decoded picture lands
                let shape = ready?.size ?? pictureAspect(f)
                if ready != nil || shape != nil {
                    mediaBubble(picture: ready, aspect: shape ?? CGSize(width: 1, height: 1), isVideo: false, file: f)
                        // A PICTURE THE CACHE LET GO IS ASKED AGAIN (the author's word 03.10.2026 16:46 MSK: «photos on a black
                        // ground sometimes -- fix it at the root»). T1 03.10: the photo landed whole at 16:40:56, the app left the
                        // screen at 16:43:20 and every picture cache was emptied (MontanaCaches, caches=9); back at 16:45:30 the
                        // bubble was drawn again without its picture, and the ask below never ran again -- its key, the file and its
                        // presence, had not changed. The key now says whether the picture stands drawn: a bubble drawn without it
                        // asks again, whatever emptied the cache.
                        .task(id: "\(f)|\(fileOnDisk(f))|\(ready == nil)") {
                            // THE PICTURE IS ASKED UNTIL IT COMES (29.09, the iPhone 17 at 13:16Z: a picture just sent stood as a
                            // grey plate for the life of the process while the same file opened in the viewer). A refusal of the
                            // decoder at the row's birth is a moment, not a verdict: the ask repeats at a growing pause while the
                            // file lies here, and a plate still grey after six asks names itself in the diary.
                            var pause: UInt64 = 300_000_000
                            for turn in 0..<6 {
                                guard docImageCached(f) == nil else { return }
                                let got = await Task.detached(priority: .userInitiated) { docImage(f) }.value
                                if Task.isCancelled { return }
                                if got != nil { thumbTick += 1; return }
                                guard fileOnDisk(f) else { return }   // not here yet: its landing changes the key and asks anew
                                if turn == 5 { MontanaP2PTrace.mark("bubble_blank", "kind=img file=\(String(f.prefix(20))) -- the file lies here, six asks gave no picture"); return }
                                try? await Task.sleep(nanoseconds: pause)
                                pause = min(pause * 2, 5_000_000_000)
                            }
                        }
                } else if message.docName == MontanaCardPlate.stickerName { stickerPlaceholder }
                else { imagePlaceholder }
            } else if let vf = message.videoFile {
                if vf.hasPrefix("vnote_") { videoNoteBubble(vf) } else {
                    // The video's poster is fetched here and only here; the plate is the one every
                    // picture stands on (mediaBubble) — the kind of data never chooses the plate.
                    let thumb = videoThumbCached(vf)   // CACHE ONLY — no decoding in render (main)
                    let _ = thumbTick                   // dependency: redraw when the async poster is ready
                    mediaBubble(picture: thumb, aspect: thumb?.size ?? videoAspect(vf) ?? CGSize(width: 4, height: 3),
                                isVideo: true, file: vf)
                        // The key includes the fact of the file's presence: when the download finishes the
                        // key changes and the poster recomputes; once, it stayed empty and the plate fell to 4:3.
                        .task(id: "\(vf)|\(fileOnDisk(vf))") {
                            for _ in 0..<5 {
                                if await videoThumbAsync(vf) != nil { thumbTick += 1; return }
                                try? await Task.sleep(nanoseconds: 3_000_000_000)
                                if Task.isCancelled { return }
                            }
                        }
                }
            } else if let df = message.docFile {
                if mtIsAudioName(message.docName ?? "") || mtIsAudioName(df) {
                    audioBubble(df, voice: false)
                } else if MontanaGif.isGif(message.docName ?? df) || MontanaGif.isGif(df) {
                    gifBubble(df)
                } else {
                    docBubble(df)
                }
            } else if message.text.hasPrefix(MontanaCardPlate.mark) {
                cardBubble(String(message.text.dropFirst(MontanaCardPlate.mark.count)))
            } else if message.text.hasPrefix(MontanaWakePush.letterBlobMark) {
                if message.lost {
                    lostLetterBubble      // the words never came, and are asked for no more (25.09)
                } else {
                    pendingLetterBubble   // a reference, not words: the row is being healed
                }
            } else if let place = placeLetter {
                placeBubble(place)    // the words of a place, drawn as the place (the author's word 23.09)
            } else {
                textBubble
            }
        }
        // The retry button stands BESIDE the bubble, not on top: overlaid, it covered the
        // letter's corner and read as part of the text. One's own letter hugs the right, so
        // the button lands to its left — on the feed's side, not past the screen edge.
        .modifier(MTResendBeside(badge: failedResendBadge))
    }
    /// SAVE TO PHOTOS, BESIDE THE BUBBLE (the author's word 11.09): strictly to the right of the
    /// correspondent's photo or video, never on the picture, never on one's own letters. A PLATE
    /// (the author's word 20.09) wears the same circle and saves every picture and video on it at
    /// once — it stands as soon as all of them are on disk and none is still riding.
    @ViewBuilder var saveBesideBadge: some View {
        if !message.isMine, !anyProgress, !isGroup, message.text.hasPrefix(MontanaCardPlate.mark) {
            // A CARD'S WORDS GO TO THE CONTACTS (the author's word 28.09): beside a card the person was given — its photo or
            // its plate — the circle offers the platform's new-contact page filled from it; the photo saves from the viewer.
            MTCardContactBadge(lines: MontanaCardLine.lines(of: message.text))
        } else if !message.isMine, !anyProgress {
            let letters = isGroup ? members : [message]
            let files = letters.compactMap { m -> (file: String, video: Bool)? in
                guard m.docName != MontanaCardPlate.stickerName,
                      let f = m.imageFile ?? m.videoFile, !f.hasPrefix("vnote_") else { return nil }
                return (f, m.videoFile != nil)
            }
            if files.count == letters.count, files.allSatisfy({ fileOnDisk($0.file) }) {
                MTSaveMediaBadge(files: files)
            }
        }
    }

    /// The business card as a card (15.41, the author's word): the same plate the person wrote
    /// it on — the emblem in the corner, the first line as the name, the rest as the details.
    /// The letter itself stays plain text under the 📇 mark — every build reads it.
    func cardBubble(_ body: String) -> some View {
        return MontanaCardFace(lines: body.components(separatedBy: "\n"))
            .overlay(alignment: .bottomTrailing) {
                metaLine()
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.black.opacity(0.38), in: MontanaLongOctagon())
                    .padding(10)
            }
    }

    // call log row: type icon + direction + duration/missed
    /// THE WORD OF A NEW BUILD (the author's word 29.09): the Montana room's letter, drawn as the golden scroll (MTReleaseScroll).
    func releaseBubble(_ r: (build: Int, version: String, notes: [String], url: String)) -> some View {
        let title = String(localized: "New version", bundle: MTLanguage.bundle) + " " + (r.version.isEmpty ? "" : r.version + " ") + "(" + String(r.build) + ")"
        return MTReleaseScroll(title: title, notes: r.notes, url: r.url, build: r.build, shape: bubbleShape) { metaLine(onMedia: true) }
    }

    /// A POST ON A WALL OF THE PAIR (the author's word 30.09): the wall's glyph, the word for it and the post's first lines, in the
    /// chess invitation's shape; the tap opens the wall the post stands on (primaryTap).
    func wallCardBubble(_ c: MTWallCard) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: "text.below.photo").font(.system(size: 22)).frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Wall post").font(.headline)
                    // USER-DATA: the post's own words, as its writer wrote them
                    Text(verbatim: c.words).font(.subheadline).lineLimit(3).multilineTextAlignment(.leading)
                }
            }
            metaLine(onMedia: false)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(bubbleFill).foregroundColor(bubbleText)
        .clipShape(bubbleShape).overlay { bubbleOutline }
    }

    func callBubble(_ ci: (video: Bool, incoming: Bool, dur: Int, missed: Bool)) -> some View {
        let title = String(localized: ci.video ? "Video call" : "Voice call", bundle: MTLanguage.bundle)
        let arrow = ci.incoming ? "arrow.down.left" : "arrow.up.right"
        let sub: String = ci.missed ? String(localized: ci.incoming ? "Missed" : "No answer", bundle: MTLanguage.bundle)
            : (ci.dur > 0 ? String(format: "%d:%02d", ci.dur/60, ci.dur%60) : String(localized: "Connection failed", bundle: MTLanguage.bundle))
        let accent: Color = ci.missed ? .red : bubbleText
        return HStack(spacing: 10) {
            Image(systemName: ci.video ? "video.fill" : "phone.fill")
                .font(.system(size: 18)).foregroundColor(accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundColor(bubbleText)
                HStack(spacing: 4) {
                    Image(systemName: arrow).font(.system(size: 10)).foregroundColor(accent)
                    Text(LocalizedStringKey(sub)).font(.caption).foregroundColor(bubbleText.opacity(0.85))
                    Text("·").font(.caption).foregroundColor(bubbleText.opacity(0.65))
                    metaLine()
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(minHeight: MessageBubble.rowPlate)   // one height with the voice capsule (the author's word 28.09)
        .background(bubbleFill)
        .clipShape(bubbleShape)
        .overlay { bubbleOutline }
    }

    /// A VOICE MESSAGE IS A CAPSULE OF OUR LETTERS' GLASS (the author's words 28.09: «the voice bubbles super light, with no
    /// animation, strictly the size and the style of all our native bubbles, the least size», then his two pictures: «the same
    /// style, with live scrubbing», then «the bubble the size of the call bubble»): the letter's own fill, shape and rim -- the
    /// shape at the capsule's height is a capsule -- and in it the play glyph on a round of glass with a quiet sheen, the voice's
    /// still wave, its length; under it the two plates, the microphone with the length and the stamp. No orb, no Metal surface
    /// per letter, no motion: the glyph turns, and only the playing (or scrubbed) wave fills -- by the clock (MTAudioLive) or by
    /// the finger (MontanaScrubber, the app's one scrubber). THE WHOLE BUBBLE PLAYS (the author's word 28.09: «a tap anywhere on
    /// the bubble, a wide area, and it plays»): the root's tap (primaryTap), the round's button and the finger on the wave all go
    /// through voiceToggle -- one owner of start and pause; the finger on the wave starts the voice from where it landed.
    /// THE CAPSULE STANDS ON THE ONE-ROW PLATE (rowPlate), the call bubble's height, and inside it every measure is a share of
    /// his pictures' height (Media/Montana_Voice_Sender_Blue.png and Montana_Voice_Recipient_Glass.png, 351 px tall there): the
    /// round 254 px (0.72), the rim to the round 66 (0.19), the round to the wave 32 (0.09), the wave 189 tall (0.54) of 12-px
    /// bars at a 25-px pitch (2 points at 4), the wave to the time 50 (0.14), the time to the rim 89 (0.25).
    func voiceCapsuleBubble(_ file: String) -> some View {
        let mine = player.playingFile == file
        let onDisk = fileOnDisk(file)
        let length = message.audioDuration
        let width = MessageBubble.voiceWaveWidth(length, window: mtWin.width > 0 ? mtWin.width : MTScene.size().width)
        return VStack(alignment: message.isMine ? .trailing : .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 5) {
                voicePlayRound(file, mine: mine, onDisk: onDisk)
                if mine {
                    MTAudioLive { now in voiceLine(file, share: scrubPos ?? now, live: now, width: width,
                                                   length: player.duration > 0 ? player.duration : length, mine: true, onDisk: onDisk) }
                } else {
                    voiceLine(file, share: scrubPos ?? (pendingPos ?? 0), live: pendingPos ?? 0, width: width,
                              length: length, mine: false, onDisk: onDisk)
                }
            }
            .padding(.leading, 10).padding(.trailing, 14)
            .frame(minHeight: MessageBubble.rowPlate)
            .background(bubbleFill)
            .clipShape(bubbleShape)
            .overlay { bubbleOutline }
            HStack(spacing: 4) {
                if let p = mediaProgress {
                    progressPill(p)   // the tape on its way: its progress where its length will stand
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "mic.fill").font(.system(size: 10))
                        // USER-DATA: a duration.
                        Text(verbatim: fmtDuration(length)).monospacedDigit()
                    }
                    .modifier(MTVoicePill())
                }
                metaLine(onMedia: true).modifier(MTVoicePill())
            }
            .font(.caption2)
            .foregroundColor(.white)
        }
        .task(id: file + (onDisk ? "/on" : "/off")) {
            if onDisk, wave == nil { wave = await MTWaveform.samples(file) }
        }
    }
    /// One owner of the voice's start and pause: the round's button, the bubble's own tap (primaryTap) and the finger on the wave
    /// all call it. A place chosen by the finger (pendingPos) is where the voice starts.
    private func voiceToggle(_ file: String) {
        MTTouchClaim.claim()   // the play glyph keeps the keyboard (14.09)
        guard fileOnDisk(file) else { return }
        if player.playingFile == file && !player.paused { player.pause(); return }
        onPlayVoice(file)
        if let at = pendingPos { player.seek(to: at); pendingPos = nil }
    }
    /// The play glyph on a round of glass with a quiet sheen; the tape's ring while it rides.
    @ViewBuilder private func voicePlayRound(_ file: String, mine: Bool, onDisk: Bool) -> some View {
        if let p = mediaProgress {
            ZStack {
                Circle().stroke(bubbleText.opacity(0.25), lineWidth: 2)
                Circle().trim(from: 0, to: CGFloat(max(0, min(1, p))))
                    .stroke(bubbleText, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: MessageBubble.voiceRound, height: MessageBubble.voiceRound)
        } else {
            Button {
                voiceToggle(file)
            } label: {
                MTVoiceRound(side: MessageBubble.voiceRound, glyph: onDisk ? (mine && !player.paused ? "pause.fill" : "play.fill") : "arrow.down")
                    .frame(width: 44, height: 44)   // the finger's 44 points around the round (mt-touch-check)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(-2)   // the finger's room stays around the 40-point round; the capsule keeps the round's height
        }
    }
    /// The wave's width by the voice's length: the least a capsule holds (1.4 of the plate's height, as in the pictures), growing
    /// with the seconds to the room the window leaves -- a short voice is a short capsule, and no capsule stands past four fifths
    /// of the window (the round, the gaps, the time and the margins take 111 points of it).
    static func voiceWaveWidth(_ seconds: Double, window: CGFloat) -> CGFloat {
        let room = max(76, window * 0.8 - 111)
        return min(room, max(76, 60 + CGFloat(seconds) * 8))
    }
    /// The voice's line: its wave -- bright to the share played or chosen by the finger -- the finger's scrubber over it, and the
    /// time: the length at rest, the place while it plays or is held.
    private func voiceLine(_ file: String, share: Double, live: Double, width: CGFloat, length: Double, mine: Bool, onDisk: Bool) -> some View {
        let samples = wave ?? message.audioFile.flatMap(MTWaveform.cached) ?? []
        let bars = max(8, Int(width / 4))   // a 2-point bar at a 4-point pitch, the pictures' 12 px at 25
        let ink = message.isMine ? Color(red: 0.62, green: 0.87, blue: 1.0) : Color.white
        let moving = mine || scrubPos != nil || pendingPos != nil
        return HStack(spacing: 8) {
            MTVoiceWaveShape(samples: samples, bars: bars).fill(ink.opacity(moving ? 0.4 : 0.9))
                .overlay(alignment: .leading) {
                    if moving {
                        MTVoiceWaveShape(samples: samples, bars: bars).fill(ink)
                            .mask(alignment: .leading) { Rectangle().frame(width: width * CGFloat(max(0, min(1, share)))) }
                    }
                }
                .frame(width: width, height: 28)
                .overlay {
                    if onDisk {
                        MontanaScrubber(live: live, bare: true,
                                        onSeek: { at in if player.playingFile == file && !player.paused { player.seek(to: at) } else { pendingPos = at; voiceToggle(file) } },   // the finger's place starts the voice (28.09)
                                        onHold: { scrubPos = $0 })
                    }
                }
            // USER-DATA: a duration.
            Text(verbatim: fmtDuration(moving ? length * share : length))
                .font(.footnote).monospacedDigit()
                .foregroundColor(bubbleText.opacity(0.85))
                .lineLimit(1)
        }
    }

    // video message: frame preview (aspect as shot) + play button
    /// The round video note (the author's word 10.09): the clip plays back IN the window it was
    /// recorded in — the skin's shape (a circle under Native, an octagon under Geometric), the
    /// ring on its rim filling with the playback, a tap for play and pause, the seconds under it.
    /// Roundness is the file's name (vnote_): a build that does not know it draws a video.
    func videoNoteBubble(_ file: String) -> some View {
        let side: CGFloat = 220   // a plate of its own size, in any window (plateCeiling's law)
        // THE SECOND CIRCLE HAS ITS ROOM (the author's word 24.09: «the dual circles on the right and on the left must not
        // leave the screen — the chat's own side margin, as the media keep — and reckoned at once when the note is dual»).
        // The badge stands past the circle's square by the window's overhang (MontanaNoteWindow.overhang), and the bubble
        // used to keep only the circle's footprint: a left badge left the row's margin, a right one left the screen. The
        // bubble now takes that room on the badge's own sides, read from the note's name (vnote_D + its corner) — known
        // before any frame, so the first layout already holds the whole of it and nothing moves when it arrives.
        let corner = MontanaVideoNoteCamera.badgeCorner(file)
        let over: CGFloat = corner == nil ? 0 : (MontanaNoteWindow.overhang * side).rounded(.up)
        let badgeLeft = corner.map { $0 % 2 == 0 } ?? false
        let badgeTop = corner.map { $0 < 2 } ?? false
        return VStack(alignment: .trailing, spacing: 4 + (corner != nil && !badgeTop ? over : 0)) {
            MontanaNotePlayback(file: file, side: side, onDisk: fileOnDisk(file), thumbTick: thumbTick, frameBox: noteFrameBox)
            // Under the circle, one line as under the orb: the progress bottom-left while the note
            // rides (the author's word 21.09), the stamp at the right.
            HStack(spacing: 0) {
                if let p = mediaProgress { progressPill(p).fixedSize() }
                Spacer(minLength: 4)
                metaLine(onMedia: true).foregroundColor(.white)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.black.opacity(0.45), in: MontanaLongOctagon())
            }
            .frame(width: side)
        }
        .padding(.leading, badgeLeft ? over : 0)
        .padding(.trailing, corner != nil && !badgeLeft ? over : 0)
        .padding(.top, badgeTop ? over : 0)
        // The circle asks until it wears the note's own frame (MTNoteFrame.wear); the landing changes the key.
        .task(id: "\(file)|\(fileOnDisk(file))") { await MTNoteFrame.wear(file) { thumbTick += 1 } }
    }

    /// A MOVING PICTURE PLAYS WHERE IT LANDED (23.09). It rides the document road -- the only one
    /// that touches no byte of it -- but a document plate is not what a moving picture is: on both
    /// sides it stands in its own shape and plays by itself, the platform drawing every frame
    /// (ImageIO's animator over the file, MTGifView; nothing of ours ticks). A build that does not know
    /// this shows the file plate it always showed and can save the file ([P2P-COMPAT]).
    func gifBubble(_ file: String) -> some View {
        // NOTHING IS DECODED HERE (23.09): the body runs on every render of the feed, and decoding the
        // whole gif in it was the glitch and the 417 MB of 1901. The plate's shape is the file's own
        // header; the frames are the platform animator's, one at a time, while the bubble is on screen.
        let url: URL? = fileOnDisk(file) ? attachmentURL(file) : nil
        let shape = url.flatMap { MontanaGif.size(at: $0) }
        // A STICKER OF THE HOUSE IS A STICKER, NOT A PICTURE IN A BUBBLE: no fill, no rim, and the
        // one size every sticker of ours wears -- three single glyphs across (MTStickerLook).
        let bare = file.hasPrefix("stick_") || (message.docName ?? "").hasPrefix("stick_")
        let fit = bare ? MTStickerLook.box(shape ?? CGSize(width: 1, height: 1))
                       : mediaBox(shape ?? CGSize(width: 4, height: 3), ceiling: Self.gifCeiling)
        return VStack(spacing: 0) {
            ZStack {
                if let url {
                    // THREE CYCLES WHEN IT FIRST SHOWS, THEN ONLY ON A TAP; A TAP STOPS IT AT ANY MOMENT (the
                    // author's word 23.09) — the play is the book's, by the file (MTGifPlay).
                    MTGifPlayer(url: url)
                        .frame(width: fit.width, height: fit.height)
                } else {
                    Color(white: 0.2).frame(width: fit.width, height: fit.height)
                }
            }
            .frame(width: fit.width, height: fit.height).clipped()
            .alignmentGuide(.mtMediaMiddle) { $0[VerticalAlignment.center] }
            .background(GeometryReader { g -> Color in
                imgFrameBox.rect = g.frame(in: .global)
                mediaPlateBox.rect = g.frame(in: .named(MessageBubble.plateSpace))
                return Color.clear
            })
            .overlay { mediaProgressOverlay }
            .overlay(alignment: .bottomTrailing) {
                metaLine(onMedia: true)
                    .foregroundColor(.white)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.black.opacity(0.45), in: MontanaLongOctagon())
                    .padding(6)
            }
        }
        .frame(width: fit.width)
        .background { if !bare { bubbleFill } }
        .clipShape(bubbleShape)
        .overlay { if !bare { bubbleOutline } }
    }

    // file message: the file's face (MTFileIcon) + name + size; the transfer's ring stands over the face
    func docBubble(_ file: String) -> some View {
        HStack(spacing: 12) {
            MTFileIcon(file: file, name: message.docName ?? file, width: 60, height: 74)
                .overlay {
                    if let p = mediaProgress {
                        ZStack {
                            Circle().fill(Color.black.opacity(0.45)).frame(width: 36, height: 36)
                            Circle().stroke(Color.white.opacity(0.35), lineWidth: 3).frame(width: 30, height: 30)
                            Circle().trim(from: 0, to: CGFloat(max(0, min(1, p))))
                                .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .rotationEffect(.degrees(-90)).frame(width: 30, height: 30)
                        }
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(message.docName ?? "File").foregroundColor(bubbleText).lineLimit(1)
                HStack(spacing: 4) {
                    // A transfer in progress — the same visibility as video: percentages and a status word.
                    if let p = mediaProgress {
                        Text("\(Int(p * 100))%" + (mediaStatus.map { " · " + $0 } ?? ""))
                            .font(.caption2.weight(.semibold)).foregroundColor(bubbleText)
                    } else {
                        Text(fileSizeString(file)).font(.caption2).foregroundColor(bubbleText.opacity(0.7))
                    }
                    metaLine()
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: 250)
        .background(bubbleFill)
        .clipShape(bubbleShape)
        .overlay { bubbleOutline }
    }

    // voice message: play/pause button + waveform + duration
    /// A music file: the same player as voice, but with the track's name — so music is
    /// listened to by title, not guessed from a faceless document.
    /// ONE audio bubble for a voice message and a music file (the author's word 10.09): the
    /// same long plate, the play button, the real wave with the scrub, the times. Voice differs
    /// in three words only — its title, its glyph and the speed button instead of the size.
    func audioBubble(_ file: String, voice: Bool) -> some View {
        let mine = player.playingFile == file
        let isPlaying = mine && !player.paused
        let onDisk = FileManager.default.fileExists(atPath: attachmentURL(file).path)
        let total = mine ? player.duration : (voice ? message.audioDuration : (onDisk ? musicFileDuration(file) : 0))
        let trackName = voice ? String(localized: "Voice message", bundle: MTLanguage.bundle) : (message.docName ?? file)
        // The bubble's width — from the minimum to the track caption's width +30% (ceiling — a share of the window).
        let nameW = (trackName as NSString).size(withAttributes:
            [.font: UIFont.systemFont(ofSize: 15, weight: .semibold)]).width
        let bubbleW = max(252, min(nameW * 1.3 + 28, mtWin.width * 0.78))
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 12) {
                if let p = mediaProgress {
                    ZStack {
                        Circle().stroke(bubbleText.opacity(0.25), lineWidth: 3.5)
                        Circle().trim(from: 0, to: CGFloat(max(0, min(1, p))))
                            .stroke(bubbleText, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 0.3), value: p)
                    }
                    .frame(width: MontanaOctagon.height, height: MontanaOctagon.height)
                } else {
                    // The button is the ONLY start/pause point: its own tap, the bubble stays silent.
                    Button {
                        MTTouchClaim.claim()   // the play glyph keeps the keyboard (14.09)
                        guard onDisk else { return }
                        if mine && !player.paused { player.pause(); return }
                        if voice { player.toggle(file, voice: true) } else { onTapMusic(file) }
                        if let pp = pendingPos { player.seek(to: pp); pendingPos = nil }
                    } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(bubbleText)
                    }
                    .buttonStyle(.montanaOctagon(square: true))
                }
                Group {
                    // THE PLAYING BUBBLE ALONE WATCHES THE CLOCK (28.09): its wave fills by the player's ticks; every other bubble's
                    // wave stands still where the person left it, and is not drawn again at every tick of a sound elsewhere.
                    if mine {
                        MTAudioLive { now in waveColumn(file, fill: scrubPos ?? now, live: now, total: total, onDisk: onDisk, mine: true) }
                    } else {
                        waveColumn(file, fill: scrubPos ?? (pendingPos ?? 0), live: pendingPos ?? 0, total: total, onDisk: onDisk, mine: false)
                    }
                }
            }
            if !voice {
                Text(trackName)
                    .font(.subheadline.weight(.semibold)).foregroundColor(bubbleText)
                    .lineLimit(1).truncationMode(.middle)
            }
            // The bottom row: the note and size/percentage on the left; the time with the
            // checkmarks in the bottom-right corner, as on every bubble ([C-1]).
            HStack(spacing: 4) {
                Image(systemName: voice ? "mic.fill" : "music.note").font(.system(size: 10))
                    .foregroundColor(bubbleText.opacity(0.7))
                if let p = mediaProgress {
                    Text("\(Int(p * 100))%" + (mediaStatus.map { " · " + $0 } ?? ""))
                        .font(.system(size: 11, weight: .semibold)).foregroundColor(bubbleText)
                } else if voice {
                    // The voice speed, one tap around 1 → 1.5 → 2 (the author's word 10.09); music has none.
                    Button {
                        player.voiceRate = player.voiceRate >= 2 ? 1 : (player.voiceRate >= 1.5 ? 2 : 1.5)
                    } label: {
                        // USER-DATA: a multiplier, digits and ×.
                        Text(verbatim: player.voiceRate == 1 ? "1×" : (player.voiceRate == 2 ? "2×" : "1.5×"))
                            .font(.system(size: 11, weight: .bold)).foregroundColor(bubbleText)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(bubbleText.opacity(0.18), in: MontanaLongOctagon())
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(fileSizeString(file)).font(.system(size: 11))
                        .foregroundColor(bubbleText.opacity(0.7))
                }
                Spacer(minLength: 10)
                metaLine()
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(width: bubbleW, alignment: .leading)
        .background(bubbleFill)
        .clipShape(bubbleShape)
        .overlay { bubbleOutline }
    }

    /// The wave, its scrubber and the times under it at the share `fill` -- drawn still in a resting bubble, by the clock in the
    /// playing one (MTAudioLive); `live` is the scrubber's own place.
    @ViewBuilder private func waveColumn(_ file: String, fill: Double, live: Double, total: Double, onDisk: Bool, mine: Bool) -> some View {
                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            // The unplayed wave is a wave, not a line: half-bright, the same bars.
                            trackWave(width: g.size.width, color: bubbleText.opacity(0.5))
                            trackWave(width: g.size.width, color: bubbleText)
                                .mask(alignment: .leading) {
                                    Rectangle().frame(width: g.size.width * CGFloat(max(0, min(1, fill))))
                                }
                            // THE ONE SCRUBBER (the author's word 18.09: one slider in the app, everything
                            // else refers to it): the wave is the picture, the platform's slider — bare, no
                            // track and no thumb of its own — is the touch. The finger anywhere on the wave
                            // takes it; the lift asks the player once. Seeking does NOT touch the button:
                            // playing — move the position; not playing — the position waits for ▶.
                            if onDisk {
                                MontanaScrubber(live: live, bare: true,
                                                onSeek: { pos in if mine { player.seek(to: pos) } else { pendingPos = pos } },
                                                onHold: { scrubPos = $0 })
                            }
                        }
                        .frame(height: 26)
                    }
                    .frame(height: 26)
                    .task(id: file + (onDisk ? "|1" : "|0")) {
                        if onDisk, wave == nil { wave = await MTWaveform.samples(file) }
                    }
                    HStack {
                        Text(fmtDuration(total * fill))
                            .font(.caption2).foregroundColor(bubbleText.opacity(0.8))
                        Spacer(minLength: 12)
                        Text(fmtDuration(total))
                            .font(.caption2).foregroundColor(bubbleText.opacity(0.8))
                    }
                }
    }

    /// The track's wave: the file's real amplitudes as thin bars (native player style); while
    /// the shape is computed — an even quiet dotted line of the same geometry.
    func trackWave(width: CGFloat, color: Color) -> some View {
        let n = max(12, Int(width / 4))
        let src = wave ?? (message.audioFile ?? message.docFile).flatMap(MTWaveform.cached) ?? []
        return HStack(alignment: .center, spacing: 2) {
            ForEach(0..<n, id: \.self) { i in
                let amp: CGFloat = src.isEmpty ? 0.12
                    : CGFloat(src[min(src.count - 1, i * src.count / n)])
                Capsule().fill(color)
                    .frame(width: 2, height: max(3, 3 + amp * 19))
            }
        }
        .frame(width: width, height: 26, alignment: .leading)
    }

    // placeholder if the photo file is not found on disk
    /// A STICKER ON ITS WAY STANDS ON NOTHING (the author's word 22.09: «it loads as a photo on a
    /// white ground»). A picture that has not arrived gets the photo's grey plate with its glyph and
    /// its word; a sticker has no plate at all -- its ground is the chat's own -- so the place it
    /// will take is held empty, at the one sticker size, with only its progress over it.
    var stickerPlaceholder: some View {
        Color.clear
            .frame(width: MTStickerLook.side, height: MTStickerLook.side)
            .overlay { mediaProgressOverlay }
    }
    var imagePlaceholder: some View {
        ZStack {
            Color(white: 0.2)
            VStack(spacing: 6) {
                Image(systemName: "photo").font(.system(size: 38))
                Text("Photo").font(.caption)
            }.foregroundColor(.gray)
        }
        .frame(width: 230, height: 230)
        .clipShape(bubbleShape)
    }

    /// THE ONE CEILING OF A MEDIA PLATE (the author's word 20.09: «after a turn to landscape a
    /// picture with a caption comes back crooked»): the plate's width was a share of the window —
    /// a caption widened it to four fifths of whatever the window was — so the same letter had one
    /// shape upright and another on its side, and a cell laid out for one met the other. A plate is
    /// a thing of its own size: the picture's long side, the mosaic's width, the caption's reach
    /// all stop at this number, in any window, in any orientation. Nothing of the plate reads the
    /// window (mt-layout-check 14).
    static let plateCeiling: CGFloat = 300
    /// THE ONE-ROW PLATE (the author's word 28.09: «the voice bubble the size of the call bubble»): a call and a voice stand
    /// on one height, this number -- the call's two lines in the letters' own padding; the voice's round and wave are cut to
    /// it in the proportions of the author's two pictures (voiceCapsuleBubble). Both plates read this one number.
    static let rowPlate: CGFloat = 54
    /// The voice's round of glass: 0.72 of the plate, as in the pictures (254 of 351 px), in whole points.
    static let voiceRound: CGFloat = 40
    /// THE MOVING PICTURE'S CEILING IS THE DEVICE'S, NOT THE WINDOW'S (the author's word 23.09: «adapt
    /// the gifs to the screen so they look in harmony — on T3 they are too big»). 300 is four fifths of
    /// an iPhone XS's width: a photo may stand so, a moving picture that never stops is too loud at that
    /// size. Its ceiling is a share of the device's SHORT side — the same upright and on its side, so
    /// the plate still never changes shape with a turn (mt-layout-check 14) — read once for the run,
    /// and never above the plate's own ceiling: 225 on a 375-point phone, 257 on 428, 300 on a tablet.
    static let gifCeiling: CGFloat = {
        let screen = MTScene.size()
        let short = min(screen.width, screen.height)
        guard 1 < short else { return plateCeiling }
        return min(plateCeiling, round(short * 0.6))
    }()
    // Media bubble size from the original's aspect: long side up to the ceiling, short side min 130
    // (in proportion to a smaller ceiling, so a moving picture keeps the photo's own shape rules).
    func mediaBox(_ size: CGSize, ceiling: CGFloat = MessageBubble.plateCeiling) -> CGSize {
        let w = max(size.width, 1), h = max(size.height, 1)
        let maxLong: CGFloat = ceiling, minShort: CGFloat = round(130 * ceiling / Self.plateCeiling)
        var bw: CGFloat, bh: CGFloat
        if w >= h { bw = maxLong; bh = maxLong * h / w; if bh < minShort { bh = minShort } }
        else { bh = maxLong; bw = maxLong * w / h; if bw < minShort { bw = minShort } }
        return CGSize(width: round(bw), height: round(bh))
    }
    // Caption under the media — the TEXT BUBBLE's own model at the media's exact width:
    // the text wraps inside the plate, the stamp sits bottom-right with its line reserved.
    // The old plate pinned the text to the media width and THEN padded outside — 20pt wider
    // than the picture, chopped by the clip shape, and no stamp at all under a caption.
    @ViewBuilder func captionBar(width: CGFloat, text: String? = nil) -> some View {
        let caption = text ?? message.text
        if !caption.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                words(caption, MontanaTextSize.letterFont(.callout))
                    .foregroundColor(bubbleText).font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                timeRow.hidden()   // reserve the stamp's line, exactly like the text bubble
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .frame(width: width, alignment: .leading)
            .overlay(alignment: .bottomTrailing) {
                timeRow.padding(.horizontal, 10).padding(.bottom, 7)
            }
        }
    }
    /// The caption's own bubble width (the author's word 15.09): the text measured at the
    /// caption's font inside the bubble's ceiling, plus the caption's padding — the width the
    /// words would take in a text bubble of their own.
    func captionNaturalWidth(cap: CGFloat, text: String? = nil) -> CGFloat {
        let font = MontanaTextSize.letterFont(.callout)
        let r = ((text ?? message.text) as NSString).boundingRect(with: CGSize(width: cap - 20, height: .greatestFiniteMagnitude),
                                                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                        attributes: [.font: font], context: nil)
        return ceil(r.width) + 20
    }
    /// THE PLATE OF A MEDIA GROUP (19.09): the tiles at the frames the mosaic cut, one point apart,
    /// the plate's own shape around them; under them the one caption in the text bubble's manner;
    /// without a caption the stamp sits on the last tile's corner, as on a single picture.
    func groupBubble() -> some View {
        let plateW = Self.plateCeiling
        let cut = MTMosaic.layout(maxSize: CGSize(width: plateW, height: plateW * 4 / 3), sizes: members.map(MTMosaic.size(of:)))
        let caption = groupCaption
        // The plate is exactly the mosaic's width and the caption wraps inside it (the reference's
        // manner): the words never widen a plate of pictures.
        let width = cut.size.width
        return VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                ForEach(Array(members.enumerated()), id: \.element.id) { i, m in
                    if i < cut.tiles.count {
                        groupTile(m, frame: cut.tiles[i].rect, corners: MTMosaic.corners(cut.tiles[i].position))
                    }
                }
            }
            // The tiles are placed by offset from the container's top-left corner, so the container
            // must hold them at that corner: a centred frame slid the whole cluster by half the gap
            // between the plate and the largest tile (measured 1723, the author's screenshot).
            .frame(width: cut.size.width, height: cut.size.height, alignment: .topLeading)
            .alignmentGuide(.mtMediaMiddle) { $0[VerticalAlignment.center] }   // item 21: the circle stands level with the tiles
            .overlay(alignment: .bottomTrailing) {
                if caption.isEmpty {
                    metaLine(onMedia: true)
                        .foregroundColor(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.black.opacity(0.45), in: MontanaLongOctagon())
                        .padding(6)
                }
            }
            captionBar(width: width, text: caption)
        }
        .frame(width: width)
        .background(bubbleFill)
        .clipShape(bubbleShape)
        .overlay { bubbleOutline }
    }
    /// One tile of the plate: the picture, or the video's poster with its play (or download) sign;
    /// a tile without a picture yet stands grey; a riding tile wears its own small ring; a failed
    /// own tile wears the retry sign — the tap on it is the resend.
    @ViewBuilder func groupTile(_ m: Message, frame: CGRect, corners: RectangleCornerRadii) -> some View {
        let file = m.imageFile ?? m.videoFile ?? ""
        let isVideo = m.videoFile != nil
        let picture = MTLetterThumb.plate(file: file, isVideo: isVideo)
        ZStack {
            if let picture {
                Image(uiImage: picture).resizable().aspectRatio(contentMode: .fill)
            } else {
                Color(white: 0.2)
                Image(systemName: isVideo ? "video" : "photo").font(.system(size: 26)).foregroundColor(.gray)
            }
            if isVideo {
                Image(systemName: fileOnDisk(file) ? "play.circle.fill" : "arrow.down.circle.fill")
                    .font(.system(size: 34)).foregroundColor(.white.opacity(0.9))
            }
            if let p = transfers.progress[file] {
                // EVERY TILE C->IES ITS OWN PROGRESS, LIKE A SINGLE PLATE (the author's word 22.09):
                // the same ring and the same percent, fitted INSIDE the tile — never past its edges.
                // A tile narrower than the pill (the mosaic cuts small ones) wears the ring alone;
                // the percent joins it as soon as the tile has the room. The word (megabytes) and the
                // cancel cross belong to the single plate: a tile is too small for either, and a
                // cross inside one tile would read as «cancel the whole plate».
                Color.black.opacity(0.25)
                let ring: CGFloat = min(26, max(16, frame.width * 0.22))
                let showPercent = frame.width > 96 && frame.height > 68
                VStack(spacing: 3) {
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.35), lineWidth: 2)
                        Circle().trim(from: 0, to: CGFloat(max(0, min(1, p))))
                            .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 0.3), value: p)
                    }
                    .frame(width: ring, height: ring)
                    if showPercent {
                        Text(verbatim: "\(Int(p * 100))%")   // USER-DATA: a measured number, not a word
                            .font(.system(size: 11, weight: .semibold)).foregroundColor(.white)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
                .padding(4)
                .frame(maxWidth: frame.width, maxHeight: frame.height)
            } else if m.isMine, m.deliveryStatus == .failed {
                Image(systemName: "exclamationmark.arrow.circlepath")
                    .font(.system(size: 18, weight: .bold)).foregroundColor(.white)
                    .frame(width: 34, height: 34).background(Color.red, in: Circle())
            }
        }
        .frame(width: frame.width, height: frame.height)
        .clipShape(UnevenRoundedRectangle(cornerRadii: corners))
        .background(GeometryReader { g -> Color in
            tileFrames.set(m.id, g.frame(in: .named(MessageBubble.plateSpace))); return Color.clear
        })
        .offset(x: frame.minX, y: frame.minY)
    }

    // ONE PLATE FOR A PICTURE AND A VIDEO (the author's word 20.09: the kind of data never chooses
    // the behaviour; measured: a vertical video's caption stood in a 130-point column while the same
    // caption under a vertical photo widened the plate). The reference's model (the author's word
    // 15.09): the plate is as wide as the WIDEST of its contents — the picture fitted, or the
    // caption's own bubble — never the picture alone; a picture narrower than the plate (a portrait
    // under a long caption) keeps its fitted size in the middle and the sides are a mirrored blur of
    // the picture itself. A video is the same plate over its poster with the play (or download) sign
    // in the middle; a poster still on its way is a grey field of the video's own shape.
    func mediaBubble(picture: UIImage?, aspect: CGSize, isVideo: Bool, file: String) -> some View {
        // A sticker (the card) stands on its own: no fill, no rim — the plate is the picture.
        let sticker = !isVideo && message.docName == MontanaCardPlate.stickerName
        // A STICKER HAS ONE SIZE, NOT THE PICTURE'S (the author's word 22.09): three single glyphs
        // across, whatever the file's own pixels are.
        let fit = sticker ? MTStickerLook.box(aspect) : mediaBox(aspect)
        let cap = Self.plateCeiling
        // THE CARD'S PHOTO STANDS ALONE (the author's word 28.09): its words are already on it; they ride as the caption for
        // the contacts and for a build that does not know the mark, and are not drawn a second time under it.
        let card = !isVideo && message.text.hasPrefix(MontanaCardPlate.mark)
        let captionW = message.text.isEmpty || sticker || card ? 0 : captionNaturalWidth(cap: cap)
        let box = CGSize(width: min(cap, max(fit.width, captionW)), height: fit.height)
        let narrow = !sticker && fit.width < box.width - 1
        return VStack(spacing: 0) {
            ZStack {
                if let picture {
                    if narrow {
                        Image(uiImage: picture).resizable().aspectRatio(contentMode: .fill)
                            .frame(width: box.width, height: box.height).clipped()
                            .scaleEffect(x: -1, y: 1)
                            .blur(radius: 18)
                            .overlay(Color.black.opacity(0.22))
                    }
                    Image(uiImage: picture).resizable().aspectRatio(contentMode: sticker || narrow ? .fit : .fill)
                        .frame(width: narrow ? fit.width : box.width, height: box.height)
                } else {
                    Color(white: 0.2).frame(width: box.width, height: box.height)
                }
                // THE VIDEO PLAYS BY ITSELF, AS IN THE POSTS (the author's word 28.09): on the disk, the plate is the system player's
                // layer, without sound, round and round, while the letter stands on the screen (MTChatClip); a tap is the system's full
                // player. The file is not here yet — the download arrow: a play on nothing produced a crossed-out button.
                if isVideo {
                    if fileOnDisk(file) {
                        MTChatClip(file: file).frame(width: box.width, height: box.height)
                    } else {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 54)).foregroundColor(.white.opacity(0.9))
                    }
                }
            }
                .frame(width: box.width, height: box.height).clipped()
                .alignmentGuide(.mtMediaMiddle) { $0[VerticalAlignment.center] }   // the save circle stands level with the picture (item 21)
                .background(GeometryReader { g -> Color in
                    imgFrameBox.rect = g.frame(in: .global)
                    mediaPlateBox.rect = g.frame(in: .named(MessageBubble.plateSpace))   // the tap is measured in this space
                    return Color.clear
                })
                .overlay { mediaProgressOverlay }
                .overlay(alignment: .bottomTrailing) {
                    if message.text.isEmpty || card {
                        metaLine(onMedia: true)
                        .foregroundColor(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.black.opacity(0.45), in: MontanaLongOctagon())
                        .padding(6)
                    }
                }
            captionBar(width: box.width, text: card ? "" : nil)
        }
        .frame(width: box.width)
        .background { if !sticker { bubbleFill } }
        .clipShape(bubbleShape)
        .overlay { if !sticker { bubbleOutline } }
    }

    /// A row that holds a long-letter reference the words of which have not arrived yet: the
    /// placeholder every build shows for a letter in flight — never the raw reference.
    var pendingLetterBubble: some View {
        HStack(spacing: 8) {
            ProgressView().tint(bubbleText).scaleEffect(0.8)
            Text("New message").foregroundColor(bubbleText.opacity(0.8))
            metaLine()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(bubbleFill)
        .clipShape(bubbleShape)
        .overlay { bubbleOutline }
    }
    /// A LONG LETTER WHOSE WORDS NEVER CAME (the author's word 25.09: «do not try to fetch what is not there»): said once
    /// and for good — no wheel that turns for ever over a cargo every door has called gone.
    var lostLetterBubble: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.bubble").foregroundColor(bubbleText.opacity(0.8))
            Text("Message unavailable").foregroundColor(bubbleText.opacity(0.8))
            metaLine()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(bubbleFill)
        .clipShape(bubbleShape)
        .overlay { bubbleOutline }
    }

    /// THE PLACE A LETTER CARRIES (the author's word 23.09, the reference's own shape): the words
    /// «pin, name, link» every build sends are drawn here as the map with the pin on the spot and
    /// the time on it; a named place keeps its name and street under the map. A quoted letter stays
    /// words — the quote above must not vanish into a picture.
    var placeLetter: MTPlaceLetter? {
        message.replyText == nil ? MTPlaceLetter.parse(message.text) : nil
    }
    func placeBubble(_ place: MTPlaceLetter) -> some View {
        let side = CGSize(width: 260, height: place.name == nil ? 170 : 140)
        return VStack(alignment: .leading, spacing: 0) {
            MTPlaceMapPlate(place: place, size: side)
                .overlay(alignment: .bottomTrailing) {
                    if place.name == nil {
                        metaLine(onMedia: true)
                            .foregroundColor(.white)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Color.black.opacity(0.45), in: MontanaLongOctagon())
                            .padding(6)
                    }
                }
            if let name = place.name {
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    if let street = place.street {
                        Text(street).font(.footnote).opacity(0.7).lineLimit(1)
                    }
                    timeRow.frame(maxWidth: .infinity, alignment: .trailing)
                }
                .foregroundColor(bubbleText)
                .padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 5)
            }
        }
        .frame(width: side.width)
        .background(bubbleFill)
        .clipShape(bubbleShape)
        .overlay { bubbleOutline }
    }

    /// A reply carries a quote to draw (a forward's wire quote is the mark above, not a quote).
    private var quoted: Bool { message.replyText.map { $0 != Message.forwardedQuote } ?? false }
    /// THE QUOTE OF A REPLY, ONE DRAWING (the author's word 24.09: «a reply of one emoji does not show the quoted
    /// letter»): the text bubble and the big emoji both wear it. The big emoji stands on no plate of its own, so
    /// its quote takes the bubble's plate round itself.
    @ViewBuilder private var replyQuote: some View {
        if quoted, let reply = message.replyText {
            HStack(spacing: 6) {
                Rectangle()
                    .fill(message.isMine ? Color.white.opacity(0.6) : Color.accentColor)
                    .frame(width: 3, height: quoteAuthor == nil ? 16 : 32)
                VStack(alignment: .leading, spacing: 1) {
                    if let qa = quoteAuthor {
                        Text(qa)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(message.isMine ? .white : Color.accentColor)
                            .lineLimit(1)
                    }
                    Text(reply)
                        .font(.system(size: 12))
                        .foregroundColor(message.isMine ? Color.white.opacity(0.85) : .gray)
                        .lineLimit(1)
                }
            }
        }
    }

    // text message
    var textBubble: some View {
        // The bubble hugs the text; time/checkmarks — overlaid in the bottom-right corner.
        // An invisible copy of timeRow INSIDE reserves the width and the bottom line for the time,
        // so on short messages the time is not clipped, and on long ones there's no empty space.
        VStack(alignment: .leading, spacing: 2) {
            replyQuote
            words(message.text, MontanaTextSize.letterFont(.body))
                .fixedSize(horizontal: false, vertical: true)
            if let card = MTLinkPreview.parse(message.linkPreview) {
                linkCard(card)
            } else if message.isMine, MTLinkPreviewBuilder.enabled, message.deliveryStatus == .sending,
                      !MTLinkPreviewBuilder.webURLs(in: message.text).isEmpty {
                // THE ROOM IS HELD WHILE THE CARD IS BEING READ (the critic 22.09): the card lands a
                // second behind the letter, and the bubble used to jump to a new height under the eye.
                // A line and two grey bars of the card's own height stand there meanwhile.
                HStack(alignment: .top, spacing: 6) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(message.isMine ? Color.white.opacity(0.35) : Color.gray.opacity(0.4))
                        .frame(width: 3)
                    VStack(alignment: .leading, spacing: 5) {
                        RoundedRectangle(cornerRadius: 3).fill(bubbleText.opacity(0.18)).frame(width: 90, height: 9)
                        RoundedRectangle(cornerRadius: 3).fill(bubbleText.opacity(0.12)).frame(width: 150, height: 9)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            }
            timeRow.hidden()   // reserve space for the time (so it isn't clipped on short messages)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .overlay(alignment: .bottomTrailing) {
            timeRow.padding(.horizontal, 12).padding(.bottom, 6)
        }
        .background(bubbleFill)
        .foregroundColor(bubbleText)
        .clipShape(bubbleShape)
        .overlay { bubbleOutline }
    }
    // ── THE LINK CARD (the critic 22.09, the reference's own two shapes) ──
    // A small picture stands as a square beside the words; a big one lies across the card under them.
    // The card is a BUTTON, not a tap of ours: a button inside the letter wins over the letter's own
    // tap by the platform's rule, so the card opens from the first touch in a bubble that also carries
    // words. Its width is the bubble's content width — no ceiling of its own any more.
    func linkCard(_ card: MTLinkPreview) -> some View {
        let picture = linkCardImage(card)
        let wide = card.wide && picture != nil
        // THE CARD IS DRAWN BY THE REFERENCE OWN NUMBERS (the author word 22.09: not a byte of
        // difference). The font is fourteen seventeenths of the letter own size — semibold for the
        // site name and the page title, regular for the words — the lines breathe by nine hundredths
        // of it, the three blocks stand with NO gap between them, and the picture keeps six points.
        // The lines each block is allowed: two for the site, five for the title, twelve for the words.
        let base = MontanaTextSize.letterFont(.body).pointSize
        let f = floor(base * 14 / 17)
        let accent = MontanaNativeBubble.link(mine: message.isMine)
        // A picture drawn across the card keeps its own shape; a portrait one is held to four thirds
        // of the width so a single letter cannot take the whole screen.
        let ratio = max(0.75, min(3.0, CGFloat(card.w ?? 4) / CGFloat(max(card.h ?? 3, 1))))
        return Button {
            if let u = URL(string: card.u) { UIApplication.shared.open(u) }
        } label: {
            HStack(alignment: .top, spacing: 6) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(accent)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 0) {
                    // THE WORDS GO AROUND THE SMALL PICTURE, as the reference lays them (22.09): the
                    // first lines are short by the picture's square and its six points, and the lines
                    // below it run the card's full width. The cutout is the platform's own
                    // (NSTextContainer.exclusionPaths); the line counts, the spacing and the square
                    // are the reference's numbers.
                    ZStack(alignment: .topTrailing) {
                        MTLinkCardWords(blocks: cardBlocks(card, accent: accent),
                                        size: f,
                                        cutout: (picture != nil && !wide) ? CGSize(width: 60, height: 60) : nil)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let ui = picture, !wide {
                            Image(uiImage: ui)
                                .resizable().aspectRatio(contentMode: .fill)
                                .frame(width: 54, height: 54)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    if let ui = picture, wide {
                        Image(uiImage: ui)
                            .resizable()
                            .aspectRatio(ratio, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .padding(.top, 6)
                    }
                }
            }
            .padding(.top, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    /// The card's three blocks, in the reference's order and with its line counts: the site's own
    /// name in the accent, the page's title in bold, its words plain.
    func cardBlocks(_ card: MTLinkPreview, accent: Color) -> [MTLinkCardWords.Block] {
        var out: [MTLinkCardWords.Block] = []
        if let s = card.s, !s.isEmpty {
            out.append(.init(text: s, weight: .semibold, color: UIColor(accent), lines: 2))
        }
        if let t = card.t, !t.isEmpty {
            out.append(.init(text: t, weight: .semibold, color: UIColor(bubbleText), lines: 5))
        }
        if let d = card.d, !d.isEmpty {
            out.append(.init(text: d, weight: .regular, color: UIColor(bubbleText), lines: 12))
        }
        return out
    }
    func linkCardImage(_ card: MTLinkPreview) -> UIImage? {
        guard let b = card.i, let d = Data(base64Encoded: b) else { return nil }
        return UIImage(data: d)
    }

    // ── The single bubble style (SSOT) ──
    var bubbleStyle: String { MTBubbleStyle.style }
    // theme readers (custom style stores hex colors + doubles in UserDefaults)
    func thHex(_ k: String, _ d: String) -> Color { MTBubbleStyle.hex(k, d) }
    func thDbl(_ k: String, _ d: Double) -> Double { MTBubbleStyle.dbl(k, d) }
    @ViewBuilder var bubbleFill: some View { MTBubbleStyle.fill(mine: message.isMine, own: myColor) }
    var bubbleText: Color {
        if bubbleStyle == "custom" { return thHex((message.isMine ? "cbMine" : "cbPeer")+"Text", message.isMine ? BT.mTx : BT.pTx) }
        if bubbleStyle == "montana" {
            return message.isMine ? MontanaNativeBubble.mineText : MontanaNativeBubble.peerText
        }
        return .white
    }
    // SSOT outline: montana (fixed) or custom (theme). One place, used by every bubble type.
    @ViewBuilder var bubbleOutline: some View { MTBubbleStyle.outline(mine: message.isMine, bubbleShape) }

    // THE stamp ([C-1]): time (+«edited») + my delivery checks — the ONE line every bubble
    // kind shows. Geometry may place it differently (inside a text bubble, on a media
    // capsule, under a big glyph), but what it says and how it earns a checkmark has exactly
    // one source. onMedia = white lettering for stamps standing on pictures.
    func metaLine(onMedia: Bool = false) -> some View {
        let ink: Color = onMedia ? .white
            : (bubbleStyle == "montana" ? bubbleText.opacity(0.82)
                : (message.isMine ? Color.white.opacity(0.75) : .gray))
        return HStack(spacing: 3) {
            if message.edited {
                Text("edited").font(.system(size: 9))
                    .foregroundColor(onMedia ? .white.opacity(0.8)
                        : (message.isMine ? Color.white.opacity(0.6) : .gray))
            }
            Text(message.time)
                .font(.caption2)
                .foregroundColor(ink)
            // THE TIMECHAIN MARK RIGHT OF THE TIME (the author's word 02.10): the letter's gematria, in the time's own type
            // and ink, its digits of one width. Every stamp is this line, so the hidden copy that reserves the stamp's room
            // in a text bubble reserves the number too.
            if let k = MTLetterSeal.mark(message) {
                // USER-DATA: a number, the prime sum of the letter's seal
                Text(verbatim: "\u{00B7} " + String(k.gematria))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundColor(ink)
                if ribbon {
                    // USER-DATA: the head of the letter's seal, hex digits of one width
                    Text(verbatim: "\u{00B7} " + k.head)
                        .font(.caption2.monospaced())
                        .foregroundColor(ink)
                        .accessibilityHidden(true)   // eight hex digits read aloud are noise; the gematria stays spoken
                }
            }
            if message.isMine { checks }   // only the clock and the red mark remain (15.47)
        }
        .lineLimit(1)
        .fixedSize()   // a stamp is never wrapped or cut: it is a line of its own size, as the platform's own stamps are
    }
    var timeRow: some View { metaLine() }

    // status: the red mark alone (the author's word 08.09): the ladder under the LAST own
    // bubble already says «sending / sent / delivered / read»; a clock in the corner said it
    // a second time and, on a photo, a second time in the wrong place.
    @ViewBuilder var checks: some View {
        switch stampStatus {
        case .sending:
            EmptyView()   // the word under the last bubble carries the state; no second clock
        case .failed:
            MTFailedMark()
        case .sent, .delivered, .read:
            // No checkmarks in the bubble (15.47): the words «Sent / Delivered / Read» stand
            // under the last own letter instead — one place, one truth.
            EmptyView()
        }
    }
}

/// SAVE TO PHOTOS, ON THE PICTURE ITSELF (the author's word 11.09, the system messages' manner):
/// a circle with the tray arrow; a tap saves the file to the library, the circle shows the check
/// and goes; a file already saved shows no circle again. A tap inside the bubble, like the audio
/// play — not a second gesture on the root.
struct MTSaveMediaBadge: View {
    /// The files the circle saves: one on a single picture, all of them on a plate (20.09).
    let files: [(file: String, video: Bool)]
    @State private var phase: Int        // 0 offered, 1 saving, 2 saved (the green check stays)
    init(files: [(file: String, video: Bool)]) {
        self.files = files
        _phase = State(initialValue: files.allSatisfy({ MontanaSavedToPhotos.has($0.file) }) ? 2 : 0)
    }
    var body: some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.45))
            if phase == 1 { ProgressView().tint(.white) }
            else if phase == 2 { MTFloppyGlyph().frame(width: 18, height: 18) }   // saved: the green diskette
            else {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 17, weight: .semibold)).foregroundColor(.white)
            }
        }
        .frame(width: 40, height: 40)
        .contentShape(Circle())
        .onTapGesture {
            guard phase == 0 else { return }
            phase = 1
            Task { @MainActor in
                var ok = true
                for f in files where !MontanaSavedToPhotos.has(f.file) {   // a picture saved before is not saved twice
                    if !(await MontanaSavedToPhotos.save(f.file, video: f.video)) { ok = false }
                }
                withAnimation(.easeOut(duration: 0.2)) { phase = ok ? 2 : 0 }
            }
        }
    }
}

/// THE DISKETTE — the sign of «saved» (the author's word 11.09). The symbol set has no diskette
/// (checked by name), so it is drawn once here: the body with the cut corner, the shutter on top,
/// the label below, in the ladder's green.
struct MTFloppyGlyph: View {
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack(alignment: .top) {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 0))
                    p.addLine(to: CGPoint(x: w * 0.82, y: 0))
                    p.addLine(to: CGPoint(x: w, y: h * 0.18))
                    p.addLine(to: CGPoint(x: w, y: h))
                    p.addLine(to: CGPoint(x: 0, y: h))
                    p.closeSubpath()
                }
                .fill(MTDeliveryDots.lit)
                VStack(spacing: 0) {
                    Rectangle().fill(Color.black.opacity(0.55)).frame(width: w * 0.50, height: h * 0.30)
                    Spacer(minLength: 0)
                    Rectangle().fill(Color.black.opacity(0.55)).frame(width: w * 0.64, height: h * 0.28)
                        .padding(.bottom, h * 0.10)
                }
                .frame(width: w, height: h)
            }
        }
    }
}
/// The notice label a screen in its own window draws (the story): one look for a passing word.
struct MontanaToastLabel: View {
    let text: String
    var body: some View {
        Text(LocalizedStringKey(text))
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 18).padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .transition(.opacity.combined(with: .scale(scale: 0.94)))
    }
}
/// THE RED MARK of a letter that did not go — the bubble's corner and the chat row wear the
/// same one ([C-1], the author's word 11.09).
struct MTFailedMark: View {
    var body: some View {
        Image(systemName: "exclamationmark.circle.fill")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.red)
    }
}

/// THE THREE DOTS OF THE LADDER — sent, delivered, read — each lit the moment its rung is reached
/// (DeliveryStatus.rung). ONE view ([C-1], the author's word 11.09): the bubble draws it under
/// the last own letter, the chat row draws it left of the hour when the last word was mine.
/// THE LADDER LINE (the author's word 11.09): the dots, the one word of the rung and — when asked —
/// the moment the rung was reached. Under the last own bubble it stands without the moment; over
/// the bubble menu, with it. One reading (DeliveryStatus.rung / .word, Message.statusMoment), one view.
struct MTDeliveryLine: View {
    let status: DeliveryStatus
    var at: Double? = nil
    /// A voice or a round note of mine: its third rung is its playing, not its reading (MTPlayed, 25.09).
    var played: MTPlayed? = nil
    var body: some View {
        HStack(spacing: 5) {
            MTDeliveryDots(status: status, rung: played?.rung(status))
            Text(LocalizedStringKey(played?.word(status) ?? status.word)).font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
            if let at { Text(Self.moment(at)).font(.system(size: 12)).foregroundColor(.white) }
        }
    }
    static func moment(_ at: Double) -> String {
        let d = Date(timeIntervalSince1970: at)
        let t = MTClock.time(d)
        return Calendar.current.isDateInToday(d) ? t : MTDayLabel.of(at) + " " + t
    }
}
/// A VOICE OR A ROUND NOTE OF MINE IS PLAYED, NOT READ (the author's word 25.09: «for voice messages write "Listened" instead of
/// "Read", only upon the voice's actual playing; for round notes a third status, "Viewed", only upon their playing»): its third
/// rung is the correspondent's own playing, told by their «played» word — the chat opened is no playing. A correspondent whose
/// build has never said «played» keeps the old ladder, «Read»: an older build never will say it.
struct MTPlayed {
    enum Kind { case voice, note }
    let kind: Kind
    let heard: Bool
    let proven: Bool
    /// peer: the conversation the letter stands in — the open one when not named (the bubble, its menu).
    static func of(_ m: Message, peer named: String? = nil) -> MTPlayed? {
        guard m.isFromMe else { return nil }
        let kind: Kind
        if m.audioFile != nil { kind = .voice }
        else if let v = m.videoFile, v.hasPrefix("vnote_") { kind = .note }
        else { return nil }
        let peer = named ?? (ChatStore.live?.openConv ?? "")
        return MTPlayed(kind: kind, heard: m.heard, proven: m.heard || (!peer.isEmpty && E2E.playedCapable(peer)))
    }
    /// The stage the row's dots stand on: the playing's rung in the ladder's own words (the chat list, the critic 25.09).
    func status(_ s: DeliveryStatus) -> DeliveryStatus {
        if heard { return .read }
        return proven && s == .read ? .delivered : s
    }
    func rung(_ s: DeliveryStatus) -> Int {
        if heard { return 3 }
        return proven && s == .read ? 2 : s.rung
    }
    func word(_ s: DeliveryStatus) -> String {
        if heard { return kind == .voice ? "Listened" : "Viewed" }
        return proven && s == .read ? DeliveryStatus.delivered.word : s.word
    }
}
struct MTDeliveryDots: View {
    static let lit = Color.green, dim = Color(white: 0.30)   // the ladder's two colours, named once
    let status: DeliveryStatus
    var rung: Int? = nil   // a playing's rung over the reading's (MTPlayed)
    var body: some View {
        let reached = rung ?? status.rung
        HStack(spacing: 5) {
            ForEach(1...3, id: \.self) { k in
                Circle().fill(reached >= k ? MTDeliveryDots.lit : MTDeliveryDots.dim)
                    .frame(width: 5, height: 5)
            }
        }
    }
}

/// THE STAGE OF A PLATE IS ITS SLOWEST LETTER ([C-1], the author's word 29.09: «in the chat the status is read, and there
/// three grey dots»). Pictures and videos picked together ride as separate letters, each on its own rung; the line under the
/// plate spoke its FIRST letter's rung and the chat row its LAST letter's, so one pick said two things at once. Measured on the
/// iPhone 15 (1990) 29.09: seven pictures and two videos of one pick at 19:47:02Z; the pictures were delivered at 19:47:22Z and
/// read at 20:02:50Z, the videos waited out the background and left at 20:03:32Z and 20:03:59Z, read at 20:04:07Z -- the plate
/// said «Delivered», then «Read», while the row stood at three grey dots for seventeen minutes. A plate stands where its
/// slowest letter stands: a letter that did not go makes it «Not sent», a letter still riding keeps it at the clock, and it
/// is «Read» only when every letter is. Of the letters on the lowest rung, the one that reached it last names the moment
/// (the menu's line). ONE reading for the plate's line, its stamp, the menu and the chat row (ChatStore.ladderLetter).
enum MTLadder {
    static func lead(_ letters: [Message]) -> Message? {
        letters.min { a, b in
            let ra = place(a), rb = place(b)
            return ra == rb ? b.statusMoment < a.statusMoment : ra < rb
        }
    }
    /// «Not sent» stands below the clock: the plate owes the person a retry before anything else.
    private static func place(_ m: Message) -> Int { m.deliveryStatus == .failed ? -1 : m.deliveryStatus.rung }
}

// wrapper: swipe a message to the right = reply
// Row mid-Y in the scroll's content space — maps a finger position to a message .
struct MsgRowMidYKey: PreferenceKey {
    static var defaultValue: [MID: CGFloat] = [:]
    static func reduce(value: inout [MID: CGFloat], nextValue: () -> [MID: CGFloat]) { value.merge(nextValue(), uniquingKeysWith: { $1 }) }
}

// Fast multi-select: a 2-finger pan on the message list (scroll stays on 1 finger).
// began = pick the message under the point, changed = extend the selection range, ended = stop.
// A 2-finger pan recognizer that only engages after a
// 5pt vertical move and bails out on a wide (>200pt) two-finger spread (pinch), so it fires
// reliably without hijacking normal scroll.
final class MTSelectionPan: UIPanGestureRecognizer {
    private let threshold: CGFloat = 5
    private var recognized: Bool? = nil
    private var initial: CGPoint = .zero
    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        self.minimumNumberOfTouches = 2; self.maximumNumberOfTouches = 2
    }
    override func reset() { super.reset(); recognized = nil }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        initial = touches.first?.location(in: view) ?? .zero
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        let loc = touches.first?.location(in: view) ?? .zero
        let dy = loc.y - initial.y
        let arr = Array(touches)
        if recognized == nil, arr.count == 2 {
            let a = arr[0].location(in: view), b = arr[1].location(in: view)
            if hypot(a.x - b.x, a.y - b.y) > 200 { state = .failed }
            if state != .failed, abs(dy) >= threshold { recognized = true }
        }
        if recognized == true { super.touchesMoved(touches, with: event) }
    }
}

struct TwoFingerSelectAttach: UIViewRepresentable {
    var onBegan: (CGFloat) -> Void
    var onChanged: (CGFloat) -> Void
    var onEnded: () -> Void
    func makeUIView(context: Context) -> UIView {
        let v = UIView(); v.isUserInteractionEnabled = false
        DispatchQueue.main.async { context.coordinator.attach(from: v) }
        return v
    }
    func updateUIView(_ v: UIView, context: Context) { context.coordinator.cb = (onBegan, onChanged, onEnded) }
    func makeCoordinator() -> Coord { Coord((onBegan, onChanged, onEnded)) }
    final class Coord: NSObject, UIGestureRecognizerDelegate {
        var cb: ((CGFloat) -> Void, (CGFloat) -> Void, () -> Void)
        weak var scroll: UIScrollView?
        init(_ cb: ((CGFloat) -> Void, (CGFloat) -> Void, () -> Void)) { self.cb = cb }
        func attach(from view: UIView, tries: Int = 12) {
            var sv: UIView? = view.superview
            while let s = sv, !(s is UIScrollView) { sv = s.superview }
            guard let scroll = sv as? UIScrollView else {
                if tries > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.attach(from: view, tries: tries - 1) } }
                return
            }
            self.scroll = scroll
            scroll.panGestureRecognizer.maximumNumberOfTouches = 1   // 1 finger scrolls, 2 fingers select
            let g = MTSelectionPan(target: self, action: #selector(pan(_:)))
            scroll.addGestureRecognizer(g)
        }
        @objc func pan(_ g: UIPanGestureRecognizer) {
            guard let sv = scroll else { return }
            let y = g.location(in: sv).y
            switch g.state {
            case .began: cb.0(y)
            case .changed: cb.1(y)
            case .ended, .cancelled, .failed: cb.2()
            default: break
            }
        }
    }
}


// Growable UITextView whose keyboard can be replaced by a custom inputView (the emoji panel),
// so switching keyboard/panel is ONE system animation and the input field never moves.
final class MTGrowTextView: UITextView {
    private var _custom: UIView?
    var lastHeight: CGFloat = 0   // the height last answered to the layout — a change is one diary line
    /// THE ROOM THE KEYS MUST LEAVE FOR THE BAR, for the shape the person chose — written by the field
    /// on every update, READ only by `settleRoom()`.
    var restingBar: CGFloat?
    /// THE ONE PLACE THE KEYS' ROOM IS APPLIED (the author's word 23.09: «on unfolding the line and the
    /// buttons jump»). Measured on T1, 1900: the room was resized while the keys stood, the responder
    /// reloaded its input views, and the keyboard announced its frame FIRST with the old room — kb_settle
    /// from 311 to 353, the bar placed 42 points high — and 17 ms later with the new one, from 353 back
    /// to 311. A room changed under standing keys is a keyboard frame born of nothing, and it places the
    /// page twice. So the room is applied only where no keyboard frame is live: while the keys are down,
    /// and in the instant before they come up — where the platform measures the accessory anyway. A fold
    /// with the keys up changes the bar alone; the keys and their frame do not move.
    func settleRoom() {
        guard let rest = restingBar, let acc = inputAccessoryView as? MTKeyboardAccessorySpacer else { return }
        _ = acc.settle(to: rest)
    }
    /// A PASTE OF PICTURES (the author's word 10.09): the pasteboard holds images, not words — they
    /// become attachments above the field, not text in it. Words paste as before.
    var onPasteImages: (([UIImage]) -> Void)?
    override var inputView: UIView? { get { _custom } set { _custom = newValue } }
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)), UIPasteboard.general.hasImages { return true }
        return super.canPerformAction(action, withSender: sender)
    }
    /// A PASTE IS THE PASTE ACTION, NOT A COUNT (T1 21.09: the words flew to the start while typing).
    /// The paste was told from typing by how many characters appeared at once — and a suggested word,
    /// an autocorrection, a dictated phrase all appear at once too, so each of them was «a paste» and
    /// threw the field to its beginning. Now the action itself says it: the flag is raised here and
    /// read once by the delegate; nothing else can raise it.
    var pasting = false
    override func paste(_ sender: Any?) {
        let pb = UIPasteboard.general
        if pb.hasImages, let imgs = pb.images, !imgs.isEmpty, let onPasteImages {
            onPasteImages(imgs)
            return
        }
        pasting = true
        super.paste(sender)
    }
    /// THE CONTAINER THAT SHOWS THE WORDS HAS ONE WRITER — THIS LAYOUT (the author's word 22.09: «why
    /// does it wrap half a line when one letter does not fit»). The measure used to write this very
    /// container too, and the platform measures a representable at several widths before it lays it out:
    /// the last narrow probe stayed in the container, the view kept the width it already had, no layout
    /// followed — and the words went on wrapping at the probe's width while the plate was full width.
    /// Two writers of one value, the whole hole in the line. The height is measured on a stack of its
    /// own now (heightForWords), exactly as the reference measures on its own text storage and never
    /// touches the one that displays. Here, and only here, the container takes the view's real width.
    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width - textContainerInset.left - textContainerInset.right   // the words' width: the view's less its own insets
        if w > 1, textContainer.size.width != w {
            MontanaP2PTrace.mark("field_wrap", "from=\(Int(textContainer.size.width)) to=\(Int(w)) bounds=\(Int(bounds.width))")
            textContainer.size = CGSize(width: w, height: 1000000.0)
        }
    }
    /// THE MEASURE'S OWN STACK (the reference's measureInternal): its own storage, its own layout
    /// manager, its own container — so asking how tall the words are at ANY width can never change
    /// where the words on screen break.
    private let measureStorage = NSTextStorage()
    private let measureLayout = NSLayoutManager()
    private let measureContainer = NSTextContainer(size: CGSize(width: 100, height: 1000000.0))
    private var measureReady = false
    private func prepareMeasure() {
        guard !measureReady else { return }
        measureReady = true
        measureStorage.addLayoutManager(measureLayout)
        measureLayout.addTextContainer(measureContainer)
        measureContainer.lineFragmentPadding = 0
        measureContainer.widthTracksTextView = false
        measureContainer.heightTracksTextView = false
    }
    /// The height the words need at a given words-width, with the field's own insets. The one measure
    /// the field's sizeThatFits and its change gate share — and it moves nothing.
    func heightForWords(width w: CGFloat) -> CGFloat {
        prepareMeasure()
        let words = max(1, w)
        if measureContainer.size.width != words { measureContainer.size = CGSize(width: words, height: 1000000.0) }
        let f = font ?? MTInputField.font
        let want = NSAttributedString(string: text.isEmpty ? "A" : text, attributes: [.font: f])
        if measureStorage.string != want.string { measureStorage.setAttributedString(want) }
        measureLayout.ensureLayout(for: measureContainer)
        return measureLayout.usedRect(for: measureContainer).height + textContainerInset.top + textContainerInset.bottom
    }
    /// The height at the width the words REALLY have on screen — the container's own, one writer above.
    var fitHeight: CGFloat { heightForWords(width: textContainer.size.width) }
    // THE FIELD'S SCROLL, IN THE DIARY (21.09: the lines jerked on the lower lines): every change of the
    // offset and of the frame is a line — who moved the words is read there, not guessed.
    override var contentOffset: CGPoint {
        didSet {
            if abs(oldValue.y - contentOffset.y) > 0.5 {
                MontanaP2PTrace.mark("field_scroll", "from=\(Int(oldValue.y)) to=\(Int(contentOffset.y)) h=\(Int(bounds.height)) content=\(Int(contentSize.height)) tracking=\(isTracking ? 1 : 0)")
            }
        }
    }
    override var frame: CGRect {
        didSet {
            if oldValue.size != frame.size || oldValue.origin != frame.origin {
                MontanaP2PTrace.mark("field_frame", "y=\(Int(frame.origin.y)) h=\(Int(frame.height)) was_y=\(Int(oldValue.origin.y)) was_h=\(Int(oldValue.height))")
            }
        }
    }
}
/// THE FIELD ANSWERS THE LAYOUT ITSELF (the author's word 20.09: the platform's way). SwiftUI asks
/// a representable for its size through sizeThatFits with the width it will give it, inside the
/// layout pass — so the height is measured once, synchronously, from the one width that is real,
/// and there is no state, no binding and no asynchronous hop between the measure and the frame.
/// Before, the height travelled through a binding a frame late (build 527's class), three places
/// knew it (the model, the frame modifier, the measure), the width was learnt from layoutSubviews
/// and the measure ran from there, and the height was even written to disk with the draft — four
/// owners of a value that is a function of the text and the width. The model of the reference
/// stands: height = clamp(ceil(measured at the real width), one line, the ceiling); past the
/// ceiling the field scrolls inside.
/// THE ONE COMPOSE FIELD OUTSIDE THE CHAT (the author's word 22.09): the caption under a picture and the
/// reply to a page write in the chat's own field — the same plate, the same glass, the same tier, the
/// same gold send in the bottom-right corner — never a second field drawn by hand (the grey capsule with
/// a hand-made gold circle was the old style). The words' right room is the plain one-line inset (no
/// emoji key here). Not the chat's page: no accessory of the chat's, the platform's own keyboard
/// avoidance of the sheet moves it.
struct MTComposeRow: View {
    @Binding var text: String
    @Binding var focused: Bool
    var placeholder: LocalizedStringKey
    var onSend: () -> Void
    @State private var caret = 0
    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            MTInputField(text: $text, caret: $caret, focused: $focused, panel: nil,
                         cap: MTInputField.cap(room: MTScene.size().height / 2),
                         extraRight: MTInputField.inset.left - MTInputField.inset.right)
                .montanaFieldGlass(maxCut: 18)
                .overlay(alignment: .leading) {
                    if text.isEmpty {
                        Text(placeholder).font(.system(size: 17)).foregroundColor(.gray)
                            .padding(.leading, MTInputField.inset.left).allowsHitTesting(false)
                    }
                }
            Button(action: onSend) {
                Image(systemName: "arrow.up").font(.system(size: 20, weight: .bold)).foregroundColor(.black)
            }
            .buttonStyle(.montanaOctagon(prominent: true, square: true, bar: true, height: MontanaOctagon.composeHeight))
        }
        .padding(.horizontal).padding(.vertical, MTInputField.barPad)
        .environment(\.mtChatKeyboardGeometry, nil)
    }
}
/// THE COINS THAT MOVED, SIGNED (the author's word 06.10.2026 23:2x MSK: «show the coins' transfer or top-up in the chat, plainly
/// to the eye; fix the minuses and the pluses too»): what this phone's book lost or gained by a coin letter or a game's end -- the
/// minus on red, the plus on green, the count whole, white on its capsule so it reads on either side's bubble.
struct MTCoinDelta: View {
    let coins: Int
    var body: some View {
        // USER-DATA: a signed count of coins
        Text(verbatim: (coins < 0 ? "\u{2212}" : "+") + String(MTCoinText.count(coins).drop { ch in ch == "-" }))
            .font(.title3.bold().monospacedDigit()).foregroundStyle(.white)
            .lineLimit(1).minimumScaleFactor(0.6)
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background(coins < 0 ? Color.red : Color.green, in: Capsule())
    }
}

struct MTInputField: UIViewRepresentable {
    /// The page's keyboard geometry: its accessory (the bar's height) rides in this field's keyboard frame.
    @Environment(\.mtChatKeyboardGeometry) private var keyboardGeometry
    /// The keys' colour is the person's (Settings → Appearance → Keyboard, the author's word 21.09):
    /// the platform's own keyboardAppearance — system, dark or light.
    @AppStorage("keyboardLook") private var keyboardLook: String = "system"
    @Binding var text: String
    @Binding var caret: Int        // where the caret sits — the peer's bubble renders it at the same place
    @Binding var focused: Bool
    var panel: UIView?             // non-nil while the emoji panel replaces the keyboard
    var cap: CGFloat = .greatestFiniteMagnitude   // available-height cap from the layout; the field can NEVER overlap the feed by construction
    var onPasteImages: ([UIImage]) -> Void = { _ in }   // pictures pasted into the field go up as attachments
    var extraRight: CGFloat = 0                 // the words' extra room on the right once the plate runs under the send button
    /// THE BAR AT REST FOR THE CHOSEN SHAPE (23.09): the room the keys must leave above them. Nil where
    /// the field is not the chat's own (a caption, a reply) — no keyboard room is owned there.
    var restingBar: CGFloat? = nil
    // ═══ THE ONE OWNER OF THE COMPOSE TIER (the author's word 20.09: one function answers for the
    // message row, totally). Every number of the row lives here and nowhere else: the tier's height
    // (the field in one line and both buttons), the line of text, the font, the field's own insets,
    // the bar's breathing room, the ceiling. MontanaOctagon.composeHeight and the chat's cap READ
    // these; a second literal anywhere is a second owner (mt-owner-check).
    static let tier: CGFloat = 36                      // the row: the field in one line, «+», the microphone
    static let fontSize: CGFloat = 17
    static var font: UIFont { .systemFont(ofSize: fontSize) }
    static let minH: CGFloat = 21  // empty field = one line: max(minHeight, measured)
    static let barPad: CGFloat = 8                     // the bar's breathing room above and below the tier
    /// The ceiling for the room the chat has (the screen less the keyboard): the thirteen lines
    /// (the author's word 21.09) while two tiers of the feed stay in view, never below the tier —
    /// the insets live inside the field. The lower tier of buttons stands under the words and takes
    /// its own room out of the same budget (22.09), so the field can never reach the feed. That row
    /// is as tall as the finger's target, not as the plate inside it — the same number `restingBar`
    /// counts, and the one place both are written.
    static func cap(room: CGFloat) -> CGFloat { max(tier, min(maxH, room - (restingBar - 2 * barPad) - tier)) }
    /// THE WHOLE TIER IS THE FIELD (the author's word 20.09: the field answers the first touch, and the
    /// touch area is the tier). The room around the words — the tier's height less the line, the
    /// plus's side, the emoji key's side — is the text view's OWN inset (the platform's
    /// textContainerInset), not a padding outside it: a finger on any point of the octagon lands on
    /// the text view and raises the keyboard. Before, the text view was the 21-point line alone
    /// inside a 36-point octagon, and its edges answered nothing.
    static let inset = UIEdgeInsets(top: (tier - minH) / 2, left: 16, bottom: (tier - minH) / 2, right: 46)
    static let lines: CGFloat = 13   // the field grows to thirteen lines (the author's word 21.09), then scrolls inside
    /// THE ROOM BETWEEN THE TWO TIERS — the words above, the buttons below (the author's word 22.09).
    static let tierGap: CGFloat = 6
    /// THE LOWER TIER LAYS OUT AT THE TIER (23.09). Its plates are the tier (36), and each keeps the
    /// platform's least target (44) for the finger — but hung OUTSIDE the layout by the plate itself
    /// (ChatInputBar.fingerRoom), so the row the page lays out is 36, exactly as the mini player's
    /// row. Measured 1878 on T1, when the target was still the layout cell: the bar laid out at 102
    /// while this owner said 94 — the number and the layout must be the same thing, and now they are.
    static var buttonTier: CGFloat { tier }
    /// THE PERSON'S CHOICE OF SHAPE, as stored (the author's word 23.09) — one name for the key, so
    /// the page that owns it and every reader say the same word ([C-1]).
    static let shapeKey = "composeOpen"
    static var composeOpen: Bool { UserDefaults.standard.bool(forKey: shapeKey) }
    /// THE BAR AT REST, FOR THE SHAPE THE PERSON CHOSE (the author's word 23.09: «folded, the line
    /// sits on the keyboard; unfolding rises up and moves the mini player away; one owner, and all of
    /// them right against each other»). Folded: one tier and the bar's breathing above and below — the
    /// mini player's own measure. Open: the words, the room between, the buttons, and the breathing.
    /// The GROUND behind the bar is drawn to this height and no other (22.09: «at the third line some
    /// fill appears — it is not needed»), the keyboard's accessory is this number too, and the field's
    /// ceiling is measured from it. The shape has ONE writer — the finger; typing writes nothing here,
    /// so a wrapped word still feeds no keyboard frame (the loop of 1809 and 1878 stays closed).
    static func restingBar(open: Bool) -> CGFloat {
        open ? tier + tierGap + buttonTier + 2 * barPad : tier + 2 * barPad
    }
    static var restingBar: CGFloat { restingBar(open: composeOpen) }
    static let maxH: CGFloat = ceil(font.lineHeight * lines) + inset.top + inset.bottom   // the ceiling: the lines and the words' own insets
    func makeUIView(context: Context) -> MTGrowTextView {
        // THE FIELD IS BORN ONCE PER CHAT, AND THE DIARY SAYS SO (22.09). A birth here means the
        // platform found a DIFFERENT tree in this place and buried the old text view — the first
        // responder dies with it and the keys fall and rise. Whenever the keyboard is seen to jump,
        // this line and the «field_responder resign/become» pair beside it name the cause.
        MontanaP2PTrace.mark("field_born", "a new text view")
        let tv = MTGrowTextView()
        tv.delegate = context.coordinator
        tv.isScrollEnabled = true         // ALWAYS on: the system owns the offset;
        tv.alwaysBounceVertical = false   // content that fits cannot be dragged — behaves as a plain field
        // THE BAR BELONGS TO THE FINGER (the author's word 21.09: «if I need to scroll, I scroll with my
        // finger — why show it on typing»): the indicator is off, and only a drag turns it on, for the drag.
        tv.showsVerticalScrollIndicator = false
        tv.backgroundColor = .clear
        tv.font = Self.font
        tv.textColor = .white
        tv.tintColor = UIColor.white
        tv.textContainerInset = Self.inset
        tv.textContainer.lineFragmentPadding = 0
        tv.textContainer.widthTracksTextView = false      // container width is pinned explicitly in layoutSubviews
        tv.textContainer.lineBreakMode = .byCharWrapping  // a long unbroken word breaks by characters
        // Low horizontal priority so SwiftUI bounds the field to the container width, not the intrinsic
        // (text) width — otherwise bounds.width is huge and nothing wraps.
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tv.inputAccessoryView = keyboardGeometry?.accessory   // the bar's height in the keyboard's frame: the drag begins at the bar's top
        return tv
    }
    func updateUIView(_ tv: MTGrowTextView, context: Context) {
        context.coordinator.parent = self   // the delegate reads today's field, never the one it was born with
        tv.onPasteImages = onPasteImages
        var ins = Self.inset; ins.right += extraRight
        if tv.textContainerInset != ins { tv.textContainerInset = ins; tv.invalidateIntrinsicContentSize() }
        if let acc = keyboardGeometry?.accessory, tv.inputAccessoryView !== acc {
            tv.inputAccessoryView = acc
            if tv.isFirstResponder { tv.reloadInputViews() }
        }
        // THE SHAPE'S ROOM IS WRITTEN HERE AND APPLIED ONLY WHERE NO KEYBOARD FRAME IS LIVE (23.09):
        // never a reload under standing keys — that was the jump of 1900 (see MTGrowTextView.settleRoom).
        // THE KEYS LEAVE THE BAR'S ROOM ONLY UNDER A BAR THAT RIDES THEM (the author's word 02.10 19:17): at the top edge of
        // the turned feed no bar stands on the keys, the room above them is none, and the platform's interactive drag begins
        // at the keys' own top -- the same shape's number, zero where the bar is not on the keys (MTChatKeyboardGeometry.barOnKeys).
        tv.restingBar = keyboardGeometry?.barOnKeys == false ? restingBar.map { _ in 0 } : restingBar
        if !tv.isFirstResponder { tv.settleRoom() }
        let look: UIKeyboardAppearance = keyboardLook == "dark" ? .dark : (keyboardLook == "light" ? .light : .default)
        if tv.keyboardAppearance != look {
            tv.keyboardAppearance = look
            if tv.isFirstResponder { tv.reloadInputViews() }
        }
        if tv.text != text {
            tv.text = text
            let end = NSRange(location: (text as NSString).length, length: 0)
            tv.selectedRange = end                // caret travels WITH the text
            // A DRAFT OPENS AT ITS END (the author's word 21.09): the caret stands after the last word and the
            // last line is in view, so the writing goes on at once. (A paste still shows its beginning —
            // that is textViewDidChange's road, not this one.)
            tv.invalidateIntrinsicContentSize()
            DispatchQueue.main.async { tv.scrollRangeToVisible(end) }
        }
        if tv.inputView !== panel {
            tv.inputView = panel
            (panel as? MTInputPanelView)?.grew = false
            if tv.isFirstResponder { tv.reloadInputViews() }
        } else if let p = panel as? MTInputPanelView, p.grew {
            // THE PANEL'S HEIGHT CHANGED UNDER STANDING KEYS -- THE PAGE TURNED (24.09): the platform measures an input
            // view when it is put on and never again, so the field puts it on again at the height of this orientation.
            p.grew = false
            if tv.isFirstResponder { tv.reloadInputViews() }
        }
        // THE FLAG ASKS, THE PLATFORM ANSWERS, AND A STALE ASK IS DROPPED (the author's word 23.09: «on sharing a place the
        // keyboard is open on a page that does not need it»). The place page resigned the field while the tree was being
        // updated; the delegate's mirror read the flag of the field's birth there, wrote nothing, and the flag stayed up:
        // the next update raised the keys over the page (T1 19:13:12.610 down, 19:13:12.812 «become»). Every move of the
        // platform's own responder now counts a generation and is written back to the flag as it is, outside the update;
        // an ask made before such a move is dropped, and the one made after it reads the flag as it stands.
        let c = context.coordinator
        let asked = c.gen
        DispatchQueue.main.async {
            guard asked == c.gen else { return }
            if focused, !tv.isFirstResponder { MontanaP2PTrace.mark("field_responder", "become"); tv.becomeFirstResponder() }
            else if !focused, tv.isFirstResponder { MontanaP2PTrace.mark("field_responder", "resign"); tv.resignFirstResponder() }
        }
    }
    // The grow-field law: height = clamp(ceil(measured @ REAL width), minH, maxH); past maxH the field scrolls inside.
    // The width is the one SwiftUI proposes — the width the field will be given — never a guess.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView tv: MTGrowTextView, context: Context) -> CGSize? {
        guard let w = proposal.width, w.isFinite, w > 1 else { return nil }
        let cap = min(Self.maxH, max(Self.minH, self.cap))
        let wordsW = max(1, w - tv.textContainerInset.left - tv.textContainerInset.right)   // the words wrap inside the insets
        // THE MEASURE TOUCHES NOTHING THAT SHOWS (22.09): it asks the field's own measuring stack for
        // the height at this proposed width. Writing the shown container here left the words wrapping
        // at whatever width the platform last probed — half a line of hole, with the plate full width.
        let fit = tv.heightForWords(width: wordsW)
        // NOTHING WRITTEN HERE CAN BECOME UNREACHABLE (P-83). The field is either tall enough for
        // what it holds, or it is at its ceiling and travels. There is no third state, and the only
        // way one could appear is by turning travel off — so it is never turned off.
        let h = min(cap, max(Self.minH, ceil(fit)))
        // A PROBE IS NOT A GROWTH (the critic 24.09, T1 21:49:12-15 on 1916): the platform asks this size at more
        // than one width in one pass -- 288 and 396 on T1's bar -- and every letter measured two lines at the narrow
        // probe and one at the real width: two «growths» a letter, each telling the bar's node to lay itself out again,
        // while the field's frame never moved. Only the width the words really have on screen (the container's, whose
        // one writer is layoutSubviews) is a growth; a probe answers its height and moves nothing.
        if abs(wordsW - tv.textContainer.size.width) < 0.5, abs(tv.lastHeight - h) > 0.5 {
            MontanaP2PTrace.mark("field_grow", "from=\(Int(tv.lastHeight)) to=\(Int(h)) cap=\(Int(cap)) len=\(tv.text.count) words=\(Int(wordsW)) shown=\(Int(tv.textContainer.size.width))")
            tv.lastHeight = h
            // THE BAR'S NODE IS TOLD (the author's word 21.09: the field did not grow under a raised keyboard).
            // A keystroke re-lays the bar's own tree alone — by design, the page is not re-rendered — so the
            // node that holds this tree would keep the height the page gave it. The one event of growth asks
            // the page for the node's place again (invalidateIntrinsicContentSize → the node's sizeThatFits):
            // one road, keyboard up or down, one owner of the field's height — this measure.
            if let rider = keyboardGeometry?.rider {
                DispatchQueue.main.async { rider.invalidateIntrinsicContentSize() }
            }
        }
        return CGSize(width: w, height: h)
    }
    func makeCoordinator() -> Coord { Coord(self) }
    /// The field leaves the tree (its chat closed, or the platform rebuilt the tree): its end is not the person's.
    static func dismantleUIView(_ tv: MTGrowTextView, coordinator: Coord) { coordinator.gone = true }
    final class Coord: NSObject, UITextViewDelegate {
        var parent: MTInputField
        /// Counts every move of the platform's own responder (begin, end): an ask of the flag made before it is stale.
        var gen = 0
        /// The field left the tree: its successor keeps the ask, so its end writes nothing into the flag.
        var gone = false
        init(_ p: MTInputField) { parent = p }
        // A PASTE IS NOT TYPING. Typing adds a character and the eye follows the caret, so the
        // field rightly shows its end. A paste arrives whole, and the person wants to see what
        // arrived — from its beginning. Before, the field jumped to the end of the pasted text and
        // the start was unreachable. The two are told apart by how much appeared at once.
        func textViewDidChange(_ tv: UITextView) {
            let pasted = (tv as? MTGrowTextView)?.pasting ?? false
            (tv as? MTGrowTextView)?.pasting = false
            parent.text = tv.text
            pushCaret(tv)
            // A NEW LAYOUT ONLY WHEN THE HEIGHT CHANGES (21.09): at the ceiling a keystroke changes no height,
            // and a layout pass re-set the text view's frame under a live caret — the platform's own scroll
            // to the caret and the pass's re-scroll fought (the jerk on the lower lines). The height is
            // measured here first, by the same measure sizeThatFits uses; unchanged, nothing is asked.
            if let g = tv as? MTGrowTextView {
                let cap = min(MTInputField.maxH, max(MTInputField.minH, parent.cap))
                let want = min(cap, max(MTInputField.minH, ceil(g.fitHeight)))
                if abs(want - g.lastHeight) > 0.5 { tv.invalidateIntrinsicContentSize() }   // the layout asks sizeThatFits again for the new text
            } else {
                tv.invalidateIntrinsicContentSize()
            }
            if pasted {
                DispatchQueue.main.async { tv.setContentOffset(.zero, animated: false) }
            }
            // ONE SCROLLER (the author's word 21.09: the lines jerked up and down on the lower lines): the
            // platform itself keeps the caret in view as a character is typed; a second scrollRangeToVisible
            // a turn later (1816) pulled the same offset again with its own animation — the jerk. Gone.
        }
        func textViewDidChangeSelection(_ tv: UITextView) { pushCaret(tv) }
        // The indicator lives exactly as long as the finger's scroll: on at the drag's start, off when
        // the drag (and the glide it left) has ended. Typing, the caret's own travel, a paste — never.
        func scrollViewWillBeginDragging(_ sv: UIScrollView) { sv.showsVerticalScrollIndicator = true }
        func scrollViewDidEndDragging(_ sv: UIScrollView, willDecelerate d: Bool) { if !d { sv.showsVerticalScrollIndicator = false } }
        func scrollViewDidEndDecelerating(_ sv: UIScrollView) { sv.showsVerticalScrollIndicator = false }
        private func pushCaret(_ tv: UITextView) {
            let c = tv.selectedRange.location + tv.selectedRange.length
            guard parent.caret != c else { return }
            DispatchQueue.main.async { [parent] in parent.caret = c }   // async: never mutate state inside a view update
        }
        /// The instant before the keys come up: the room of the shape now chosen is applied here, so the
        /// keyboard's first announced frame already carries it — one placement, not two.
        func textViewShouldBeginEditing(_ tv: UITextView) -> Bool {
            (tv as? MTGrowTextView)?.settleRoom()
            return true
        }
        // The platform's own move is the truth: it is counted and written into the flag as it is -- never guarded by a
        // read of the flag (inside an update that read is a snapshot) and never inside the update.
        func textViewDidBeginEditing(_ tv: UITextView) {
            MontanaP2PTrace.mark("field_edit", "begin")
            gen += 1
            let flag = parent.$focused
            DispatchQueue.main.async { flag.wrappedValue = true }
        }
        func textViewDidEndEditing(_ tv: UITextView) {
            MontanaP2PTrace.mark("field_edit", "end")
            gen += 1
            let flag = parent.$focused
            DispatchQueue.main.async { [weak self] in
                guard self?.gone != true else { return }
                flag.wrappedValue = false
            }
        }
    }
}
/// WHERE THE PAGE OF CHOOSING OPENS: the tab the keyboard panel showed, and whether its search wakes (23.09).
struct MTPickerAsk: Equatable {
    var tab = 0
    var search = false
}
/// THE PLATFORM'S OWN SEARCH FIELD (UISearchTextField: its glass, its glyph, its clear key, its return key named
/// «search»), for the panel's two searches. Live, it types; still, it is its own picture for a touch to open the
/// page. Asked to wake, it takes the keys the moment it stands in a window — once.
struct MTPanelSearchField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var live = true
    var wake = false
    var onWoke: () -> Void = { }
    var onSubmit: () -> Void = { }
    /// The keys' colour is the person's, as on the message field (Settings → Appearance → Keyboard).
    @AppStorage("keyboardLook") private var keyboardLook: String = "system"

    func makeUIView(context: Context) -> MTPanelSearchTextField {
        let f = MTPanelSearchTextField()
        f.placeholder = placeholder
        f.returnKeyType = .search
        f.autocorrectionType = .no
        f.clearButtonMode = .whileEditing
        f.overrideUserInterfaceStyle = .dark   // the panel is dark on every phone; the field is the dark platform's own
        f.tintColor = UIColor.white     // the caret, as the message field's
        f.delegate = context.coordinator
        f.addTarget(context.coordinator, action: #selector(Coord.changed(_:)), for: .editingChanged)
        f.setContentHuggingPriority(.defaultLow, for: .horizontal)
        f.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return f
    }
    func updateUIView(_ f: MTPanelSearchTextField, context: Context) {
        context.coordinator.parent = self
        if f.text != text { f.text = text }
        if f.placeholder != placeholder { f.placeholder = placeholder }
        f.isUserInteractionEnabled = live
        let look: UIKeyboardAppearance = keyboardLook == "dark" ? .dark : (keyboardLook == "light" ? .light : .default)
        if f.keyboardAppearance != look { f.keyboardAppearance = look }
        if live, wake, !context.coordinator.woken {
            context.coordinator.woken = true
            f.onWoke = onWoke
            f.wakeWhenShown()
        }
    }
    func makeCoordinator() -> Coord { Coord(self) }
    final class Coord: NSObject, UITextFieldDelegate {
        var parent: MTPanelSearchField
        var woken = false
        init(_ p: MTPanelSearchField) { parent = p }
        @objc func changed(_ f: UITextField) { parent.text = f.text ?? "" }
        func textFieldShouldReturn(_ f: UITextField) -> Bool {
            parent.onSubmit()
            f.resignFirstResponder()   // the word is asked; the keys go down and the answer is in view
            return true
        }
    }
}
final class MTPanelSearchTextField: UISearchTextField {
    var onWoke: () -> Void = { }
    private var pending = false
    /// Takes the keys once it stands in a window: at once when it already does, else the moment it arrives.
    /// A page still sliding in may refuse the first ask — it is asked twice more, a third of a second apart.
    func wakeWhenShown(tries: Int = 3) {
        guard window != nil else { pending = true; return }
        if becomeFirstResponder() {
            MontanaP2PTrace.mark("picker_search", "awake")
            onWoke()
        } else if 1 < tries {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.33) { [weak self] in self?.wakeWhenShown(tries: tries - 1) }
        } else {
            MontanaP2PTrace.mark("picker_search", "refused — the field did not take the keys")
        }
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard pending, window != nil else { return }
        pending = false
        DispatchQueue.main.async { [weak self] in self?.wakeWhenShown() }
    }
}
// Self-contained emoji/sticker panel used as the field's inputView (its own state, fixed height).
struct EmojiInputPanel: View {
    var onEmoji: (String) -> Void
    var onSticker: (String) -> Void
    /// A sticker of this phone's own set leaves by its file name -- the picture road, not a glyph.
    var onStickerFile: (String) -> Void = { _ in }
    /// The set of this phone opens as a page of its own (22.09) -- the panel is an input view and
    /// presents nothing itself; the conversation opens the page.
    var onOpenSet: () -> Void = { }
    /// The settings glass of the panel: it opens the set's page, where the sets are kept (22.09).
    var onSettings: () -> Void = { }
    @ObservedObject private var book = MontanaStickerBook.shared
    @ObservedObject private var gifBook = MontanaGifBook.shared
    /// The panel drawn as a PAGE of its own: the arrow points the other way and closes it.
    var expanded = false
    /// The arrow asks for the page (or for its end, when this IS the page).
    var onExpand: () -> Void = { }
    /// THE PAGE OPENS WHERE THE KEYBOARD STOOD (23.09): the tab the panel showed, and, when the search line was
    /// touched, the search awake. The keyboard panel asks for the page through onLift with both.
    var startTab: Int = 0
    var focusSearch: Bool = false
    var onLift: (MTPickerAsk) -> Void = { _ in }
    @State private var gifQuery = ""
    @State private var gifPage = 1
    @State private var gifEnded = false
    @State private var gifAsking = false
    @State private var stickQuery = ""
    @State private var stickPacks: [MontanaGifSearch.Pack] = []
    @State private var stickInPack: [String: [MontanaGifSearch.Found]] = [:]
    @State private var packPage = 0
    @State private var packsEnded = false
    @State private var packEnded: Set<String> = []
    @State private var packAsking: String?
    @State private var stickEnded = false
    @State private var stickAsking = false
    @State private var stickFound: [MontanaGifSearch.Found] = []
    @State private var stickArt: [String: URL] = [:]
    @State private var gifFound: [MontanaGifSearch.Found] = []
    @State private var gifPreview: [String: URL] = [:]
    @State private var emojiQuery = ""
    /// A moving picture of the book leaves by its file name -- the conversation sends it.
    var onGifFile: (String) -> Void = { _ in }
    /// A moving picture of the house leaves AT THE TAP (the author's word 23.09: «first into the chat, then let it
    /// load»): the conversation stands the row at once and brings the full picture down behind it.
    var onGifFound: (MontanaGifSearch.Found) -> Void = { _ in }
    @State private var tab: Int?   // nil — the tab the panel was opened on (startTab)
    private var shownTab: Int { tab ?? startTab }
    @State private var searchWoke = false   // the search woke once on this page; a tab switched back does not wake it again
    @State private var scrollId: String? = "cat0"
    var body: some View {
        // THE SWITCH STANDS AT THE BOTTOM, where the thumb is and where the reference keeps it
        // (the author's word 22.09, his own screenshot) -- the platform's own segmented control.
        VStack(spacing: 0) {
            if shownTab == 0 { emoji } else if shownTab == 1 { stickers } else { gifs }
            // THE SWITCH IS THE EXAMPLE'S OWN (22.09): a glass pill with the three words and the
            // settings glass beside it, at the bottom, where the thumb is.
            MTPanelSwitch(tab: Binding(get: { shownTab }, set: { tab = $0 }), onSettings: onSettings)
                .padding(.top, 4)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // NO GROUND (the author's word 24.09): the chat's own ground shows through; the controls float on the glass.
    }
    /// THE GLYPHS, WITH THE SAME LINE AT THE TOP AS THE OTHER TWO TABS (the author's word 24.09: «the emoji tab has no
    /// such line with the arrow»): the search and the arrow, one owner for all three (searchLine). A word narrows the
    /// keys by the platform's own names of the glyphs (Unicode.Scalar.Properties.name: «grinning face», «red heart»);
    /// an emptied word brings the categories back. The category strip floats on the platform's glass, as the switch does.
    var emoji: some View {
        let cats = emojiCategories
        let q = emojiQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return VStack(spacing: 0) {
            searchLine(text: $emojiQuery, placeholder: String(localized: "Search emoji", bundle: MTLanguage.bundle), tabIndex: 0) { }
            if q.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(cats.indices, id: \.self) { ci in
                            Text(cats[ci].icon).font(.caption).foregroundColor(.gray.opacity(0.7))
                                .padding(.leading, 12).padding(.top, 8)
                            emojiGrid(cats[ci].emojis).id("cat\(ci)")
                        }
                    }.scrollTargetLayout().padding(.bottom, 8)
                }
                .scrollPosition(id: $scrollId, anchor: .top)
                HStack(spacing: 2) {
                    ForEach(cats.indices, id: \.self) { i in
                        let active = (scrollId ?? "cat0") == "cat\(i)"
                        Button { withAnimation { scrollId = "cat\(i)" } } label: {
                            Text(cats[i].icon).font(.system(size: 20))
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .background { if active { Capsule().fill(Color.white.opacity(0.16)) } }
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .mtGlassPill(corner: 22)
                .padding(.horizontal, 12).padding(.top, 6)
            } else {
                ScrollView {
                    emojiGrid(cats.flatMap(\.emojis).filter { Self.named($0, q) })
                        .padding(.top, 8).padding(.bottom, 8)
                }
            }
        }
    }
    /// One grid of keys for a category and for a word alike ([C-1]).
    private func emojiGrid(_ keys: [String]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 10) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, e in
                // A key is a Button on the platform's least target (19.09): the glyph's own
                // 34 points were short of it, and a tap on a text in a scroll waited on the scroll.
                Button { MontanaP2PTrace.markFolded("emoji_tap", "key", window: 30); onEmoji(e) } label: {
                    Text(e).font(.system(size: 28)).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }.padding(.horizontal, 10)
    }
    /// The platform's own name of a glyph holds the word: every scalar's name, joined («face with tears of joy»).
    private static func named(_ e: String, _ q: String) -> Bool {
        e.unicodeScalars.compactMap { $0.properties.name?.lowercased() }.joined(separator: " ").contains(q)
    }
    /// THE MOVING PICTURES (23.09, the author's word): the popular ones stand here the moment the
    /// tab opens -- nothing typed, nothing pressed. What this phone has already sent stands ahead
    /// of them, as the sticker strip does. The line above takes the typing where it stands: the
    /// author's own diary at 01:27 holds five searches made from it, so it is the line that is
    /// fixed, not replaced -- an emptied word brings the popular ones back.
    @ViewBuilder var gifs: some View {
        VStack(spacing: 0) {
            searchLine(text: $gifQuery, placeholder: String(localized: "Search GIFs", bundle: MTLanguage.bundle), tabIndex: 2) { runGifSearch(gifQuery) }

            if gifFound.isEmpty, gifBook.names.isEmpty {
                ContentUnavailableView("No moving pictures yet", systemImage: "rectangle.on.rectangle.angled")
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                        ForEach(gifBook.names, id: \.self) { n in
                            Button { onGifFile(n) } label: {
                                Color.white.opacity(0.06)
                                    .frame(height: 86)
                                    .overlay { MTGifLoop(url: MontanaMediaStore.url(n)) }
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) { gifBook.forget(n) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        ForEach(gifFound) { f in
                            Button { takeGif(f) } label: {
                                Color.white.opacity(0.06)
                                    .frame(height: 86)
                                    .overlay { MTGifLoop(url: gifPreview[f.id]) }
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .task { await loadGifPreview(f) }
                        }
                    }
                    .padding(.horizontal, 12).padding(.top, 10)
                    // THE FEED NEVER STOPS (the author's word 23.09: «scrolling down the gifs must keep loading them and
                    // never stop»). One asker of the next page: a line under the grid that asks whenever it stands on the
                    // screen and the list has grown or moved on — the platform's own laziness is the signal. The asking
                    // used to wait for a tile's own picture to load first, and a page of repeats ended the feed forever.
                    Color.clear.frame(height: 1)
                        .task(id: "\(gifFound.count)-\(gifPage)") { await moreGifs() }
                }
            }
            MTGiphyMark()
        }
        // THE POPULAR ARRIVE ON OPENING, ONCE PER OPENING: the node keeps its answer ten minutes,
        // so this costs the house nothing when the tab is opened again and again.
        .task {
            guard gifFound.isEmpty else { return }
            gifFound = await MontanaGifSearch.find()
            gifPage = 1
        }
        .onChange(of: gifQuery) { _, q in if q.isEmpty { runGifSearch("") } }   // the field's own clear brings the popular back
    }

    /// THE ARROW BESIDE THE LINE: one glyph, one meaning, both tabs ([C-1]). Up opens the choosing
    /// as a PAGE over the whole screen -- the field and its buttons are covered by it -- and down,
    /// on that page, gives the screen back to the conversation. A taller keyboard cannot do this:
    /// an input view is measured when it is put on, and it can never rise past the field's own row.
    private var liftArrow: some View {
        Button { if expanded { onExpand() } else { onLift(MTPickerAsk(tab: shownTab, search: false)) } } label: {
            Image(systemName: expanded ? "chevron.down" : "chevron.up")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 44, height: 44)
                .mtGlassPill(corner: 22)   // a floating glass of its own, as the settings glass (the author's word 24.09)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    /// THE SEARCH LINE OF BOTH TABS, ONE ([C-1]) — the platform's own search field (MTPanelSearchField). On the page it
    /// is live; on the keyboard panel it is the field's picture, and a touch opens the page on this tab with the
    /// field awake. A text field cannot hold the keys inside another field's keyboard: the panel IS the message
    /// field's input view, so the search taking the keys took the panel away with itself, and the message field
    /// took them back (measured T1 23.09 18:55:01Z: the message field's editing ended, 122 ms later it began
    /// again, twice; the search never typed a letter).
    @ViewBuilder private func searchLine(text: Binding<String>, placeholder: String, tabIndex: Int,
                                         submit: @escaping () -> Void) -> some View {
        HStack(spacing: 2) {
            if expanded {
                MTPanelSearchField(text: text, placeholder: placeholder,
                              wake: focusSearch && !searchWoke && tabIndex == startTab,
                              onWoke: { searchWoke = true }, onSubmit: submit)
                    .frame(height: 36)
            } else {
                Button { onLift(MTPickerAsk(tab: tabIndex, search: true)) } label: {
                    MTPanelSearchField(text: text, placeholder: placeholder, live: false)
                        .frame(height: 36)
                        .allowsHitTesting(false)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(placeholder)
            }
            liftArrow
        }
        .padding(.leading, 12).padding(.trailing, 4).padding(.top, 8)
    }

    /// A word narrows the popular ones; an emptied word brings them back. The word is asked of
    /// the node, which answers the same word out of its own ten-minute memory.
    private func runGifSearch(_ word: String) {
        Task {
            let rows = await MontanaGifSearch.find(word)
            await MainActor.run { gifFound = rows; gifPage = 1; gifEnded = rows.isEmpty }
        }
    }

    /// One page more of the same word, appended -- never a second list, never a duplicate.
    private func moreGifs() async {
        guard !gifEnded, !gifAsking else { return }
        gifAsking = true
        let rows = await MontanaGifSearch.find(gifQuery, offset: gifPage * 30)
        let known = Set(gifFound.map(\.id))
        let fresh = rows.filter { !known.contains($0.id) }
        gifFound.append(contentsOf: fresh)
        gifPage += 1
        gifEnded = rows.isEmpty   // the end is the house saying nothing; a page of repeats only moves the offset on
        gifAsking = false
    }

    private func loadGifPreview(_ f: MontanaGifSearch.Found) async {
        guard gifPreview[f.id] == nil else { return }
        if let u = await MontanaGifArt.art(of: f) { gifPreview[f.id] = u }
    }

    /// A moving picture chosen from the house stands in the chat AT THE TAP and leaves full (the author's word
    /// 23.09: «first into the chat, then let it load»). The tap used to bring the full picture down first — 0.4 to
    /// 1.8 MB through the node — and only then stand the row; the conversation now stands it at once.
    private func takeGif(_ f: MontanaGifSearch.Found) {
        onGifFound(f)
    }

    /// THE SET SPEAKS IN PICTURES, NOT IN WORDS (the rule of 22.09). What this phone made stands
    /// first, as miniatures of the stickers themselves -- no heading, no caption; a hold on one
    /// opens the platform's own menu to drop it from the set. The glyph keys keep their place
    /// below, divided by a line: nothing a person had is taken away. Under them stands what the
    /// house keeps on its sticker shelf: the popular ones arrive with the tab itself (the author's
    /// word 23.09 -- «let both the stickers and the gifs load on the touch, at once»), and the
    /// line at the top narrows them by a word.
    var stickers: some View {
        VStack(spacing: 0) {
            searchLine(text: $stickQuery, placeholder: String(localized: "Search stickers", bundle: MTLanguage.bundle), tabIndex: 1) { runStickSearch(stickQuery) }
            stickerBody
            MTGiphyMark()
        }
        .task {
            guard stickPacks.isEmpty else { return }
            stickPacks = await MontanaGifSearch.packs()
        }
        .onChange(of: stickQuery) { _, q in if q.isEmpty { runStickSearch("") } }   // the field's own clear brings the shelf back
    }

    /// A word narrows the house's shelf; an emptied word brings the popular ones back.
    private func runStickSearch(_ word: String) {
        Task {
            let rows = await MontanaGifSearch.find(word, kind: .sticker)
            await MainActor.run { stickFound = rows; stickEnded = rows.isEmpty }
        }
    }

    private func loadStickArt(_ f: MontanaGifSearch.Found) async {
        guard stickArt[f.id] == nil else { return }
        if let u = await MontanaGifArt.art(of: f) { stickArt[f.id] = u }
    }

    /// A sticker of the house leaves as the moving picture it is -- the document road, which
    /// touches no byte of it -- under a name that says «sticker», so both sides draw it bare and
    /// at a sticker's size. The full one is brought down only here, at the moment of the touch.
    private func takeStick(_ f: MontanaGifSearch.Found) {
        Task {
            // THE SAME TERM AS A PICTURE'S (23.09, the critic): the full sticker was waited for with no term, and a
            // door that trickled held the touch for as long as it liked; past the term the light one of the tile leaves.
            guard let d = await MontanaGifSearch.fetchFull(f) ?? MontanaGifArt.light(f) else {
                MontanaP2PTrace.mark("gif_send", "sticker: neither the full nor the light one is in hand — nothing leaves")
                return
            }
            let name = "stick_" + UUID().uuidString + ".gif"
            guard MontanaMediaStore.put(name, data: d) else { return }
            await MainActor.run { onGifFile(name) }
        }
    }

    var stickerBody: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // THE STRIP AT THE TOP IS WHAT THE HAND REACHES FOR (the author's word 22.09): every
                // sticker used -- sent from here or received here -- stands in it at once, newest
                // first, and no button for a «set» stands in its place.
                if !book.names.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(book.names.prefix(24), id: \.self) { n in
                                Button { onStickerFile(n) } label: {
                                    Group {
                                        if let ui = docImage(n) {
                                            Image(uiImage: ui).resizable().aspectRatio(contentMode: .fit)
                                        } else {
                                            Color.clear
                                        }
                                    }
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                    .frame(height: 54)
                    .padding(.top, 6)
                    Divider().overlay(Color.white.opacity(0.08))
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                        ForEach(book.names, id: \.self) { n in
                            Button { onStickerFile(n) } label: {
                                Group {
                                    if let ui = docImage(n) {
                                        Image(uiImage: ui).resizable().aspectRatio(contentMode: .fit)
                                    } else {
                                        Color.clear
                                    }
                                }
                                .frame(width: 72, height: 72)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) { book.forget(n) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                }
                .padding(.horizontal, 14).padding(.top, 14)
                // THE HOUSE'S SHELF STANDS IN SETS (the author's word 23.09), each under its own
                // name: a set is asked for its pictures when the eye reaches it, and the last set
                // of a page asks for the sets after it -- the platform's own laziness is the only
                // signal, nothing of ours measures a scroll.
                if stickQuery.isEmpty {
                    ForEach(stickPacks) { pack in
                        Divider().overlay(Color.white.opacity(0.1)).padding(.vertical, 12)
                        Text(verbatim: pack.title)   // USER-DATA: the set's own name, as its house wrote it
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.gray)
                            .padding(.horizontal, 16).padding(.bottom, 6)
                        houseGrid(stickInPack[pack.id] ?? [], more: { await morePack(pack.id) })
                            .task {
                                if stickInPack[pack.id] == nil {
                                    stickInPack[pack.id] = await MontanaGifSearch.inPack(pack.id)
                                }
                                if pack.id == stickPacks.last?.id { await morePacks() }
                            }
                    }
                } else if !stickFound.isEmpty {
                    Divider().overlay(Color.white.opacity(0.1)).padding(.vertical, 12)
                    houseGrid(stickFound, more: { await moreStickFound() })
                }
            }
        }
    }

    /// One shape for every shelf of the house -- a set's own pictures and a word's alike ([C-1]).
    /// The tile that stands eight from the end asks for what comes after it, so the shelf fills
    /// ahead of the finger and the scroll never reaches a floor (the author's word 23.09).
    private func houseGrid(_ rows: [MontanaGifSearch.Found], more: @escaping () async -> Void) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { at, f in
                Button { takeStick(f) } label: {
                    Color.clear
                        .frame(height: 78)
                        .overlay { MTGifLoop(url: stickArt[f.id], fill: false) }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .task {
                    await loadStickArt(f)
                    if rows.count - 8 <= at { await more() }
                }
            }
        }
        .padding(.horizontal, 14)
    }

    /// One page more inside a set, appended -- never a second list, never a duplicate.
    private func morePack(_ pack: String) async {
        guard packAsking != pack, let have = stickInPack[pack], !have.isEmpty,
              !packEnded.contains(pack) else { return }
        packAsking = pack
        let rows = await MontanaGifSearch.inPack(pack, offset: have.count)
        let known = Set(have.map(\.id))
        let fresh = rows.filter { !known.contains($0.id) }
        stickInPack[pack] = have + fresh
        if fresh.isEmpty { packEnded.insert(pack) }
        packAsking = nil
    }

    /// One page more of a word across the shelves, appended.
    private func moreStickFound() async {
        guard !stickEnded, !stickAsking else { return }
        stickAsking = true
        let rows = await MontanaGifSearch.find(stickQuery, kind: .sticker, offset: stickFound.count)
        let known = Set(stickFound.map(\.id))
        let fresh = rows.filter { !known.contains($0.id) }
        stickFound.append(contentsOf: fresh)
        stickEnded = fresh.isEmpty
        stickAsking = false
    }

    /// One page of sets more, appended.
    private func morePacks() async {
        guard !packsEnded else { return }
        let rows = await MontanaGifSearch.packs(offset: (packPage + 1) * 12)
        let known = Set(stickPacks.map(\.id))
        let fresh = rows.filter { !known.contains($0.id) }
        stickPacks.append(contentsOf: fresh)
        packPage += 1
        packsEnded = fresh.isEmpty
    }
}
/// THE PANEL HAS ONE HEIGHT AND ONE OWNER (the critic's finding 18.09: on a tester's iOS 18 the
/// field flew away from the panel by a screen's third; on the author's phone it did not). The panel
/// is the field's inputView, and UIKit sizes an input view by what the view itself declares. A
/// hosting view declares a size of its own, out of its SwiftUI content — one iOS honoured that
/// declaration and another ignored it: two births of one height, the bar rising by one number while
/// the panel drew another. The platform's own container for a custom input view is UIInputView with
/// allowsSelfSizing: its intrinsicContentSize IS the input view's height, on every iOS the same.
/// The hosting view is pinned inside it by constraints and can declare nothing outward.
/// THE PANEL HAS ONE HEIGHT AND ONE OWNER (the critic's finding 18.09: on a tester's iOS 18 the
/// field flew away from the panel by a screen's third; on the author's phone it did not). The panel
/// is the field's inputView, and UIKit sizes an input view by what the view itself declares. A
/// hosting view declares a size of its own, out of its SwiftUI content — one iOS honoured that
/// declaration and another ignored it: two births of one height, the bar rising by one number while
/// the panel drew another. The platform's own container for a custom input view is UIInputView with
/// allowsSelfSizing: its intrinsicContentSize IS the input view's height, on every iOS the same.
///
/// AND THE HEIGHT IS NOT RAISED HERE (23.09, the author: «the arrow does not work»). An input view
/// is measured by the system when it is put on; a height changed afterwards is not asked for again
/// unless the first responder is made to reload its input views — and even then the panel can never
/// pass the row of the field, which stands above it. Seeing the whole screen is therefore NOT a
/// taller keyboard but a PAGE of its own, and that is what the arrow opens now (MTPickerPage).
final class MTInputPanelView: UIInputView {
    var panelHeight: CGFloat = 0 { didSet { if oldValue != panelHeight { invalidateIntrinsicContentSize(); grew = true } } }
    /// The height changed while the panel may stand: the field puts it on again (reloadInputViews), the one way the
    /// platform measures an input view anew (24.09: the page turned, the panel kept the other orientation's height).
    var grew = false
    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: panelHeight) }
}
// Keeps ONE hosting controller for the panel, inside the ONE container that is the field's inputView.
final class EmojiPanelHolder: ObservableObject {
    private var host: UIHostingController<AnyView>?
    private var container: MTInputPanelView?
    func view(height: CGFloat, onEmoji: @escaping (String) -> Void, onSticker: @escaping (String) -> Void,
              onStickerFile: @escaping (String) -> Void = { _ in },
              onOpenSet: @escaping () -> Void = { },
              onGifFile: @escaping (String) -> Void = { _ in },
              onGifFound: @escaping (MontanaGifSearch.Found) -> Void = { _ in },
              onLift: @escaping (MTPickerAsk) -> Void = { _ in },
              onSettings: @escaping () -> Void = { }) -> UIView {
        if container == nil {
            let h = MontanaHost.make(EmojiInputPanel(onEmoji: onEmoji, onSticker: onSticker,
                                                     onStickerFile: onStickerFile, onOpenSet: onOpenSet,
                                                     onSettings: onSettings, onLift: onLift,
                                                     onGifFile: onGifFile, onGifFound: onGifFound))
            // NO GROUND OF ITS OWN (the author's word 24.09: «liquid glass, no background, floating buttons»): the panel is
            // clear, the chat's own ground shows through it, and every control stands on the platform's glass.
            h.view.backgroundColor = .clear
            let c = MTInputPanelView(frame: CGRect(x: 0, y: 0, width: MTScene.size().width, height: height), inputViewStyle: .default)
            c.allowsSelfSizing = true   // the platform's word: the input view's own intrinsic size is its height
            c.backgroundColor = .clear
            MTKeyboard.shared.panel = c   // the judge compares the keyboard's region with this view's height (24.09)
            h.view.translatesAutoresizingMaskIntoConstraints = false
            c.addSubview(h.view)
            NSLayoutConstraint.activate([
                h.view.topAnchor.constraint(equalTo: c.topAnchor),
                h.view.bottomAnchor.constraint(equalTo: c.bottomAnchor),
                h.view.leadingAnchor.constraint(equalTo: c.leadingAnchor),
                h.view.trailingAnchor.constraint(equalTo: c.trailingAnchor),
            ])
            host = h; container = c
        }
        container?.panelHeight = height
        return container!
    }
}

// Window geometry belongs to the mounted face. Reading the view also includes the current spring transform.
final class MTBubbleFrames {
    static let shared = MTBubbleFrames()
    private final class Face {
        weak var view: UIView?
        init(_ view: UIView) { self.view = view }
    }
    private var frames: [MID: Face] = [:]
    private let lock = NSLock()
    func set(_ id: MID, _ view: UIView) { lock.lock(); frames[id] = Face(view); lock.unlock() }
    func remove(_ id: MID, view: UIView) {
        lock.lock(); defer { lock.unlock() }
        if frames[id]?.view === view { frames.removeValue(forKey: id) }
    }
    func rect(_ id: MID) -> CGRect? {
        lock.lock(); let view = frames[id]?.view; lock.unlock()
        guard let view, view.window != nil, !view.bounds.isEmpty else { return nil }
        return view.convert(view.bounds, to: nil)
    }
}

struct MTBubbleFrameAnchor: UIViewRepresentable {
    let id: MID
    final class FaceView: UIView {
        var id: MID? {
            didSet {
                if let oldValue, oldValue != id { MTBubbleFrames.shared.remove(oldValue, view: self) }
                register()
            }
        }
        private func register() {
            guard let id else { return }
            if window != nil { MTBubbleFrames.shared.set(id, self) }
            else { MTBubbleFrames.shared.remove(id, view: self) }
        }
        override func didMoveToWindow() { super.didMoveToWindow(); register() }
        deinit { if let id { MTBubbleFrames.shared.remove(id, view: self) } }
    }
    func makeUIView(context: Context) -> FaceView {
        let view = FaceView()
        view.isUserInteractionEnabled = false
        view.id = id
        return view
    }
    func updateUIView(_ view: FaceView, context: Context) { if view.id != id { view.id = id } }
    static func dismantleUIView(_ view: FaceView, coordinator: ()) {
        if let id = view.id { MTBubbleFrames.shared.remove(id, view: view) }
        view.id = nil
    }
}
// The pull publisher: the UIKit recognizer reports, the row itself rides. The slide
// lives in the one layer this code gives birth to — nothing foreign can reset it.
final class MTSwipePull: ObservableObject {
    static let shared = MTSwipePull()
    struct V: Equatable { var id: MID?; var tx: CGFloat = 0; var progress: CGFloat = 0 }
    @Published var v = V(id: nil)
}
struct SwipeReplyRow<Content: View>: View {
    let id: MID
    let onReply: () -> Void
    let content: Content
    @ObservedObject private var pull = MTSwipePull.shared
    init(id: MID, onReply: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.id = id
        self.onReply = onReply
        self.content = content()
    }
    var body: some View {
        let active = pull.v.id == id
        let tx = active ? pull.v.tx : 0
        let progress = active ? pull.v.progress : 0
        content
            .overlay(alignment: .trailing) {
                if active {
                    ZStack {
                        MontanaLongOctagon().fill(.ultraThinMaterial).frame(width: 34, height: 34)
                        Image(systemName: "arrowshape.turn.up.backward.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .opacity(progress)
                    .scaleEffect(0.6 + 0.4 * progress)
                    .offset(x: 43)   // beyond the bubble's edge — it rides in with the slide
                }
            }
            .offset(x: -tx)   // the whole piece rides as one node, not part by part
    }
}
final class MTReplySwipe: UIPanGestureRecognizer {
    var admit: ((CGPoint) -> Bool)?   // the bubble's field decides at the touch's very beginning
    private var firstLocation: CGPoint = .zero
    private var validated = false
    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        maximumNumberOfTouches = 1
    }
    override func reset() { super.reset(); validated = false }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard let t = touches.first else { return }
        if let admit, !admit(t.location(in: nil)) { state = .failed; return }   // WINDOW space (measured)
        firstLocation = t.location(in: view)
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let t = touches.first else { return }
        let p = t.location(in: view)
        let dx = p.x - firstLocation.x, dy = p.y - firstLocation.y
        // Two-point validation — fast enough to win the race against the scroll's pan.
        if !validated {
            if dx > 0 { state = .failed }
            else if abs(dy) > 2, abs(dy) > abs(dx) * 2 { state = .failed }
            else if abs(dx) > 2, abs(dy) * 2 < abs(dx) { validated = true }
        }
        if validated { super.touchesMoved(touches, with: event) }
    }
}

extension VerticalAlignment {
    private enum MTMediaMiddle: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat { d[VerticalAlignment.center] }
    }
    static let mtMediaMiddle = VerticalAlignment(MTMediaMiddle.self)
}

/// The faces a reaction plate may wear: the correspondent's, as the chat's row draws it. Values,
/// not the store — the bubble is drawn in the feed and in the menu window alike.
struct MTReactionFaces: Equatable {
    /// A room with no correspondent — notes to oneself: no plate there can be anyone else's.
    var solo: Bool = false
    var peerPhoto: String?
    var peerColor: Color
    var peerInitial: String
}

/// THE CHOOSING AS A PAGE OF ITS OWN (the author's word 23.09: «the arrow must really open the
/// page of choosing to the whole screen and hide the field with its buttons»). A keyboard cannot
/// be this: an input view is measured by the system when it is put on, and it stands BELOW the
/// row of the field by construction -- it can never cover it. The page can, and it is the same
/// panel inside, so there is one choosing in the tree and not two designs ([C-1]).
///
/// The ground is the platform's own glass -- UIGlassEffect since iOS 26, the system's thin
/// material below that (MTGlassPill, the same one the switch stands on): nothing of ours is drawn
/// by hand, and the page reads as the platform's own sheet in our dark.
struct MTPickerPage: View {
    var onEmoji: (String) -> Void
    var onSticker: (String) -> Void
    var onStickerFile: (String) -> Void
    var onGifFile: (String) -> Void
    var onGifFound: (MontanaGifSearch.Found) -> Void = { _ in }
    var onOpenSet: () -> Void
    var onSettings: () -> Void
    var onClose: () -> Void
    /// The tab the keyboard showed and whether its search wakes (MTPickerAsk).
    var ask = MTPickerAsk()

    var body: some View {
        EmojiInputPanel(onEmoji: onEmoji, onSticker: onSticker,
                        onStickerFile: { onStickerFile($0); onClose() },
                        onOpenSet: onOpenSet,
                        onSettings: onSettings,
                        expanded: true,
                        onExpand: onClose,
                        startTab: ask.tab,
                        focusSearch: ask.search,
                        onGifFile: { onGifFile($0); onClose() },
                        onGifFound: { onGifFound($0); onClose() })
            .background {
                MTGlassPill(corner: 0).ignoresSafeArea()
            }
            .background(Color(white: 0.08).ignoresSafeArea())
    }
}

/// THE PLAYING TRACK'S CLOCK IN ITS OWN BUBBLE (28.09): the one view of a letter that watches the player's clock -- the wave's filled
/// share, the scrubber's place and the time under it, in the bubble whose file plays. Every other bubble draws a still wave.
struct MTAudioLive<Content: View>: View {
    @ObservedObject private var player = VoicePlayer.shared
    @ViewBuilder var content: (Double) -> Content
    var body: some View { content(player.progress) }
}

/// The voice's wave as one shape: thin rounded bars of the file's own amplitudes, a quiet even line while they are being read.
struct MTVoiceWaveShape: Shape {
    let samples: [Float]
    let bars: Int
    var bar: CGFloat = 2   // one bar's width
    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard bars != 0 else { return p }
        let step = rect.width / CGFloat(bars)
        for i in 0..<bars {
            let amp: CGFloat = samples.isEmpty ? 0.12 : CGFloat(samples[min(samples.count - 1, i * samples.count / bars)])
            let h = max(2, 2 + amp * (rect.height - 2))
            let h2 = max(bar, h)
            p.addPath(Path(roundedRect: CGRect(x: CGFloat(i) * step, y: (rect.height - h2) / 2, width: bar, height: h2), cornerRadius: bar / 2))
        }
        return p
    }
}

/// A plate under a voice's capsule (the author's pictures 28.09): the microphone with the length, the stamp -- a capsule of dim
/// glass with a thin rim, one line, at the stamp's own size (the pictures' fifth of the plate would be eleven points at the
/// call's height).
struct MTVoicePill: ViewModifier {
    func body(content: Content) -> some View {
        content
            .lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Color.black.opacity(0.38)))
            .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.5))
            .fixedSize()
    }
}

/// THE VOICE'S ROUND OF GLASS, ONE OWNER (the author's word 28.09: «in thumbnails, as a rule, the chat list applies the thumbnail
/// by its owner at once»): the glyph on the glass round with the quiet prism sheen and the thin rim. The capsule's round in the
/// feed and the letter's thumbnail in the chat list draw this one view at their own side -- the list drew the old orb, a Metal
/// surface per row, while the feed had long worn the round.
struct MTVoiceRound: View {
    var side: CGFloat
    var glyph = "play.fill"
    var body: some View {
        Image(systemName: glyph)
            .font(.system(size: side * 0.4, weight: .bold))
            .foregroundColor(.white)
            .frame(width: side, height: side)
            .background {
                ZStack {
                    MTGlassCirclePlate()
                    Circle().fill(AngularGradient(colors: [.cyan, .purple, .pink, .cyan], center: .center)).opacity(0.22)
                }
            }
            .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 0.5))
    }
}

/// A VIDEO IN A CHAT PLAYS BY ITSELF (the author's word 28.09: «the video in a chat must be live as in the posts, and open at once on
/// a tap»): the plate is the system player's layer -- without sound, round and round -- from the file on this phone, while the letter
/// stands on the screen; under its first frame the poster stands as before. It takes no touch: a tap is the letter's, and the letter
/// opens the system's full player with sound (VideoPresenter).
struct MTChatClip: View {
    let file: String
    @State private var url: URL?
    @State private var shown = false
    var body: some View {
        ZStack {
            if let url {
                MontanaClipPlayer(url: url, active: shown, paused: false, onProgress: { _ in }, muted: true)
            }
        }
        .allowsHitTesting(false)
        .onAppear { shown = true }
        .onDisappear { shown = false }
        .task(id: file) {
            guard url == nil else { return }
            if let plain = mtMediaFileURL(file) { url = plain; return }
            let name = file
            url = await Task.detached(priority: .utility) { MontanaMediaVault.playableURL(name) }.value
        }
    }
}

/// THE ROOM'S LETTER IS A GOLDEN SCROLL (the author's word 03.10 20:22: «fix the error and royally make the letter a scroll, in
/// the language of the phone, in our style, with the button like Continue with Montana on the login page»; «the golden scroll
/// of the epoch instead of the white»). The white capsule it replaces was the platform's prominent button under the chat's
/// white tint -- white on white, the word never seen. The plate is the room's own: deep gold under a gold rim, the app's icon
/// and the version at its head, the room's crowned name under them; two changes show and the chevron unrolls the rest in
/// place; the one act is the login page's door (MTDoorLabel on MTLoginDoorStyle) tinted gold. The changes come in the
/// phone's language (releaseInfoOf).
struct MTReleaseScroll<Meta: View>: View {
    let title: String
    let notes: [String]
    let url: String
    let build: Int
    let shape: BubbleShape
    @ViewBuilder let meta: () -> Meta
    @State private var open = false
    /// The changes a rolled scroll shows; one change more is shown whole -- a fold that hides one line hides nothing.
    static var rolled: Int { 2 }
    private var folds: Bool { notes.count > Self.rolled + 1 }

    var body: some View {
        let shown = folds && !open ? Array(notes.prefix(Self.rolled)) : notes
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(montanaRoomFace).resizable().scaledToFit()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    // USER-DATA: the build's version and number after the catalogue's word
                    Text(verbatim: title).font(.headline).foregroundColor(.white)
                    // USER-DATA: the room's name -- a name, not a word (montanaRoomTitle)
                    Text(verbatim: montanaRoomTitle).font(.footnote).foregroundColor(Color.white.opacity(0.68))
                }
            }
            Rectangle()
                .fill(LinearGradient(colors: [Color.accentColor.opacity(0), Color.accentColor.opacity(0.6), Color.accentColor.opacity(0)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
            VStack(alignment: .leading, spacing: 7) {
                ForEach(shown.indices, id: \.self) { i in
                    HStack(alignment: .top, spacing: 9) {
                        Circle().fill(Color.accentColor).frame(width: 5, height: 5).padding(.top, 7)
                        // USER-DATA: what changed, as the publishing road wrote it in this language
                        Text(verbatim: shown[i]).font(.subheadline).foregroundColor(Color.white.opacity(0.93))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if folds {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { open.toggle() }
                } label: {
                    Image(systemName: open ? "chevron.up" : "chevron.down")
                        .font(.footnote.weight(.semibold)).foregroundColor(Color.white.opacity(0.8))
                        .frame(minWidth: montanaTouchTarget, minHeight: montanaTouchTarget)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: open ? "Collapse" : "Expand", bundle: MTLanguage.bundle))
            }
            Button {
                MontanaP2PTrace.mark("release", "tap build=\(build)")
                if let u = URL(string: url) { UIApplication.shared.open(u) }
            } label: {
                MTDoorLabel(glyph: Image("Logo").resizable().scaledToFit(),
                            word: Text(String(localized: "Update", bundle: MTLanguage.bundle)))
            }
            .buttonStyle(MTLoginDoorStyle())
            HStack { Spacer(minLength: 0); meta() }
        }
        .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 9)
        .background(shape.fill(LinearGradient(colors: [Color(white: 0.22), Color(white: 0.09)],
                                              startPoint: .top, endPoint: .bottom)).opacity(0.92))
        .clipShape(shape)
        .overlay(shape.stroke(Color.accentColor, lineWidth: 1))
    }
}
