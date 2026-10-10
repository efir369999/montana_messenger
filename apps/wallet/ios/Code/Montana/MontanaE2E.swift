//
//  MontanaE2E.swift
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



#Preview {
    ProfileView().environment(UIState())
}


// ════════════════════════════════════════════════════════════════════════════
// MONTANA E2E — post-quantum end-to-end encryption (ML-KEM-768 + ML-DSA-65 + PQXDH + KEM
// ratchet + ChaCha20-Poly1305), multi-device. The engine is the core (mt-bindings): every
// implementation reproduces the same bytes, and what carries them sees only opaque ciphertext.
// ════════════════════════════════════════════════════════════════════════════
import CryptoKit

/// 15.11: the daily links our correspondents handed us, each with the moment it was born. A
/// link is shown only while its day runs; after that the row disappears rather than hand a
/// friend a code that answers «spent».
enum MTPeerLinks {
    private static let key = "peerRdvLinks"
    private static func born() -> [String: Double] {
        (MontanaLocalVault.getDecrypted(key + ".b").flatMap { try? JSONDecoder().decode([String: Double].self, from: $0) }) ?? [:]
    }
    private static func links() -> [String: String] {
        (MontanaLocalVault.getDecrypted(key).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }) ?? [:]
    }
    static func note(_ conv: String, link: String, born at: TimeInterval) {
        var l = links(); l[conv] = link
        var b = born(); b[conv] = at
        if let d = try? JSONEncoder().encode(l) { _ = MontanaLocalVault.setEncrypted(key, d) }
        if let d = try? JSONEncoder().encode(b) { _ = MontanaLocalVault.setEncrypted(key + ".b", d) }
        MontanaP2PTrace.mark("link_rx", "from=\(String(conv.prefix(10)))")
        DispatchQueue.main.async { NotificationCenter.default.post(name: .montanaPeerLinkArrived, object: nil, userInfo: ["conv": conv]) }
    }
    /// The last link they handed, whatever its day: the face their card wears on the node outlives the card's day.
    static func any(_ conv: String) -> String? { links()[conv] }
    /// The link, while its day runs.
    static func fresh(_ conv: String) -> String? {
        guard let link = links()[conv], let at = born()[conv] else { return nil }
        return Date().timeIntervalSince1970 - at < MontanaCard.cardLifetimeSeconds ? link : nil
    }
}

/// THE PERSON'S OWN WORDS ABOUT THEMSELVES (the author's word 24.09: «in the profile add a Bio, so a person can fill
/// their profile, and a Link, clickable»). Mine are the person's own settings (profileBio, profileLink); theirs come
/// by the daily link's road -- the draft word with two keys more -- and are kept sealed here, the latest word winning.
/// Only the web is ever opened from a link: a scheme other than https or http is not kept.
enum MTPeerAbout {
    struct About: Codable, Equatable { var bio: String; var link: String; var at: Double }
    static let bioLimit = 140
    static let linkLimit = 256
    private static let key = "peerAbout"
    /// What leaves of a bio: trimmed and held to the limit — one rule for the wire and for «My profile».
    static func said(_ s: String) -> String { String(s.trimmingCharacters(in: .whitespacesAndNewlines).prefix(bioLimit)) }
    /// Mine are the person's own in their app, Montana first, then Business (MTWalletPerson): the wallet keeps no words of its own.
    static var myBio: String { said(MTWalletPerson.bio) }
    /// A link as a page shows it: the site and the path, without the scheme the phone adds.
    static func shown(_ u: URL) -> String {
        var s = u.absoluteString
        for p in ["https://", "http://"] where s.lowercased().hasPrefix(p) { s = String(s.dropFirst(p.count)) }
        if s.hasSuffix("/") { s = String(s.dropLast()) }
        return s
    }
    static var myLink: String { url(MTWalletPerson.link)?.absoluteString ?? "" }
    /// A link as a person types it: «site.org» wears https; nothing but the web is a link here.
    static func url(_ s: String) -> URL? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.count <= linkLimit else { return nil }
        let full = t.contains("://") ? t : "https://" + t
        guard let u = URL(string: full), let scheme = u.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = u.host, host.contains(".") else { return nil }
        return u
    }
    private static func all() -> [String: About] {
        (MontanaLocalVault.getDecrypted(key).flatMap { try? JSONDecoder().decode([String: About].self, from: $0) }) ?? [:]
    }
    static func of(_ conv: String) -> About? { all()[conv] }
    /// The tag of this peer's words on my screen, spoken in every presence word (heldTail). Kept in memory: the
    /// words change only by note(), and the vault is read once, never under the lock ([C-1] with the sender's tag).
    private static let tagLock = NSLock()
    private static var tags: [String: String]?
    static func heldTag(_ conv: String) -> String {
        tagLock.lock(); let kept = tags; tagLock.unlock()
        if let kept { return kept[conv] ?? "0" }
        let read = all().mapValues { MontanaDeliveryEngine.Announced.aboutTag(bio: $0.bio, link: $0.link) }
        tagLock.lock(); if tags == nil { tags = read }; let now = tags ?? read; tagLock.unlock()
        return now[conv] ?? "0"
    }
    static func note(_ conv: String, bio: String, link: String, at: Double) {
        var a = all()
        if let held = a[conv], held.at > at { return }   // an older word changes nothing
        let kept = About(bio: String(bio.prefix(bioLimit)), link: url(link)?.absoluteString ?? "", at: at)
        a[conv] = kept
        if let d = try? JSONEncoder().encode(a) { _ = MontanaLocalVault.setEncrypted(key, d) }
        let tag = MontanaDeliveryEngine.Announced.aboutTag(bio: kept.bio, link: kept.link)
        tagLock.lock(); tags?[conv] = tag; tagLock.unlock()
        MontanaP2PTrace.mark("about_rx", "from=\(String(conv.prefix(10))) bio=\(bio.isEmpty ? 0 : 1) link=\(link.isEmpty ? 0 : 1)")
        DispatchQueue.main.async { NotificationCenter.default.post(name: .montanaPeerAboutArrived, object: nil, userInfo: ["conv": conv]) }
    }
}
extension Notification.Name { static let montanaPeerAboutArrived = Notification.Name("montanaPeerAboutArrived") }

/// THE ONE OWNER OF THE MODAL STACK (25.09). Ten places presented and dismissed by hand -- the photo host, the system
/// share sheet over it, the player, the wall's composer, the alerts -- each finding the topmost controller and giving the
/// platform's transition machine its own order, with no regard for a move in flight or a child still standing, and not one
/// of them left a line in the diary. The 15 Pro Max, 20:27:23-20:33:13Z: the share sheet raised over the photo took every
/// touch for six minutes across four returns to the screen while the main thread beat, until the app was swept away -- and
/// the diary could not say what stood on the screen. Every modal now rises and falls through this door alone:
///   - a rise waits for the move in flight and is given then, never dropped and never doubled;
///   - a fall lets the child go first, then the one asked, and waits for a move in flight too;
///   - a rise the platform has not finished after the longest honest rise (stuckAfter) is named and let go: a presentation
///     standing unfinished keeps the finger out of the whole app;
///   - A SYSTEM SHEET BELONGS TO ITS MOMENT: when the app leaves the screen the owner lets its sheet go, so a return never
///     finds the app under a sheet that stopped answering;
///   - every rise, show, fall, wait and let-go is a line of the diary and of the telemetry, and at every return to the
///     screen the stack is named whole -- whoever raised it, SwiftUI's sheets included.
enum MTTop {
    static var controller: UIViewController? {
        guard let root = rootController else { return nil }
        var top = root
        while let p = top.presentedViewController { top = p }
        return top
    }
    private static var rootController: UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return nil }
        return scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
    }
    /// The stack as it stands: its depth and its controllers, the lowest first, each with its move in flight.
    static func stack() -> (depth: Int, names: String) {
        var names: [String] = []; var t = rootController
        while let p = t?.presentedViewController {
            names.append(name(p) + (p.isBeingPresented ? "+rising" : "") + (p.isBeingDismissed ? "+falling" : ""))
            t = p
        }
        return (names.count, names.isEmpty ? "-" : names.joined(separator: ","))
    }
    static func depth() -> Int { stack().depth }
    /// The platform is moving a modal on or off the stack: no new order until it settles.
    private static func inFlight(_ top: UIViewController) -> Bool {
        if top.isBeingPresented || top.isBeingDismissed || top.transitionCoordinator != nil { return true }
        if let c = top.presentedViewController, c.isBeingPresented || c.isBeingDismissed { return true }
        return false
    }
    private static func name(_ vc: UIViewController) -> String { String(String(describing: type(of: vc)).prefix(28)) }

    /// A rise the platform has not finished yet, held weakly: a controller let go by anyone is no longer watched.
    private final class Rise {
        weak var vc: UIViewController?
        let kind: String
        let at = Date()
        init(_ vc: UIViewController, _ kind: String) { self.vc = vc; self.kind = kind }
    }
    private static var rises: [Rise] = []
    /// The longest honest rise -- a system sheet's first view from a cold service -- with room to spare.
    private static let stuckAfter: TimeInterval = 4
    /// The system sheet the owner raised: it lives while the app is on the screen.
    private static weak var sheet: UIViewController?

    static func present(_ vc: UIViewController, animated: Bool = true, kind: String, completion: (() -> Void)? = nil) {
        present(vc, animated: animated, kind: kind, waited: 0, completion: completion)
    }
    private static func present(_ vc: UIViewController, animated: Bool, kind: String, waited: Int, completion: (() -> Void)?) {
        guard let top = controller else { MontanaP2PTrace.mark("modal", "refused kind=\(kind) -- no controller"); return }
        if inFlight(top) {
            // The move in flight ends, and the order is given then. A move that never ends is named, not waited for forever.
            guard waited < 40 else {
                MontanaP2PTrace.mark("modal", "dropped kind=\(kind) over=\(name(top)) -- the stack never settled")
                MontanaLog.event("MODAL dropped kind=\(kind) -- the stack never settled")
                return
            }
            if waited == 0 { MontanaP2PTrace.mark("modal", "waits kind=\(kind) over=\(name(top)) depth=\(depth())") }
            let again = { present(vc, animated: animated, kind: kind, waited: waited + 1, completion: completion) }
            if let co = top.transitionCoordinator { co.animate(alongsideTransition: nil) { _ in again() } }
            else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { again() } }
            return
        }
        let d = depth()
        MontanaP2PTrace.mark("modal", "open kind=\(kind) over=\(name(top)) depth=\(d)")
        MontanaLog.event("MODAL open kind=\(kind) depth=\(d)")
        let rise = Rise(vc, kind)
        rises.append(rise)
        if kind == "share" { sheet = vc }
        top.present(vc, animated: animated) {
            rises.removeAll { $0 === rise || $0.vc == nil }
            MontanaP2PTrace.mark("modal", "shown kind=\(kind) ms=\(Int(Date().timeIntervalSince(rise.at) * 1000))")
            completion?()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + stuckAfter) { unstick(rise, why: "rise") }
    }
    /// A RISE THAT NEVER FINISHES HOLDS THE WHOLE SCREEN: past the longest honest rise it is named and let go.
    private static func unstick(_ rise: Rise, why: String) {
        guard rises.contains(where: { $0 === rise }) else { return }
        rises.removeAll { $0 === rise || $0.vc == nil }
        guard let v = rise.vc else { return }
        let ms = Int(Date().timeIntervalSince(rise.at) * 1000)
        MontanaP2PTrace.mark("modal", "stuck kind=\(rise.kind) ms=\(ms) why=\(why) rising=\(v.isBeingPresented ? 1 : 0) -- let go")
        MontanaLog.event("MODAL stuck kind=\(rise.kind) ms=\(ms) why=\(why) -- let go")
        dismiss(v, animated: false, kind: rise.kind + "-stuck")
    }
    /// The one to go falls after its child, and after the move in flight: the platform is never told to drop a host
    /// under a live sheet, nor to drop what it is still raising.
    static func dismiss(_ vc: UIViewController, animated: Bool = true, kind: String, completion: (() -> Void)? = nil) {
        if vc.isBeingPresented || vc.isBeingDismissed, let co = vc.transitionCoordinator {
            MontanaP2PTrace.mark("modal", "close waits kind=\(kind) -- the move in flight ends first")
            co.animate(alongsideTransition: nil) { _ in dismiss(vc, animated: animated, kind: kind, completion: completion) }
            return
        }
        if let child = vc.presentedViewController {
            MontanaP2PTrace.mark("modal", "child first kind=\(kind) child=\(name(child))")
            child.dismiss(animated: false) { dismiss(vc, animated: animated, kind: kind, completion: completion) }
            return
        }
        MontanaP2PTrace.mark("modal", "close kind=\(kind) depth=\(depth())")
        MontanaLog.event("MODAL close kind=\(kind) depth=\(depth())")
        vc.dismiss(animated: animated, completion: completion)
    }

    /// The owner listens to the screen's own moments, once, from the launch.
    private static var watching = false
    static func watch() {
        guard !watching else { return }
        watching = true
        let c = NotificationCenter.default
        c.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            guard let s = sheet else { return }
            MontanaP2PTrace.mark("modal", "sheet let go -- the app left the screen")
            MontanaLog.event("MODAL sheet let go -- the app left the screen")
            dismiss(s, animated: false, kind: "share-left")
        }
        c.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            let st = stack()
            if 0 < st.depth { MontanaP2PTrace.mark("modal", "stack depth=\(st.depth) [\(st.names)]") }
            for r in rises where Date().timeIntervalSince(r.at) > stuckAfter { unstick(r, why: "return") }
        }
    }
}

/// THE ONE BIRTH OF A SYSTEM SHARE SHEET (25.09): every «Share» of the app -- a row, a menu, the photo, the player, the
/// invitation, the code -- raises it here and nowhere else, so the owner of the stack holds each one: its rise, its end and
/// its moment. The sheet's own end is the one word the app has about a system sheet: the deed chosen, done or cancelled.
enum MTShare {
    /// A LINK GOES AS A LINK (the author's word 07.10.2026 00:1x MSK: «Share gives one link that opens in the browser, not a text
    /// that turned into a file»): words and a link handed as texts are laid down as a file by the receiving apps; a web address
    /// goes to the sheet as the one URL. Nil -- the string is no web address, and its words go as they are.
    static func web(_ s: String) -> URL? {
        guard let u = URL(string: s.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = u.scheme?.lowercased(), scheme == "https" || scheme == "http", u.host != nil else { return nil }
        return u
    }
    static func present(_ items: [Any], from source: UIView? = nil) {
        let av = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let pop = av.popoverPresentationController {
            if let source { pop.sourceView = source; pop.sourceRect = source.bounds }
            else if let v = MTTop.controller?.view {
                pop.sourceView = v; pop.sourceRect = CGRect(x: v.bounds.midX, y: v.bounds.midY, width: 0, height: 0)
                pop.permittedArrowDirections = []
            }
        }
        av.completionWithItemsHandler = { activity, completed, _, error in
            MontanaP2PTrace.mark("modal", "sheet done activity=\(activity.map { String($0.rawValue.suffix(24)) } ?? "-") completed=\(completed ? 1 : 0) error=\(error == nil ? 0 : 1)")
            MontanaLog.event("MODAL sheet done completed=\(completed ? 1 : 0)")
        }
        MTTop.present(av, kind: "share")
    }
}

extension Notification.Name {
    static let montanaInbound = Notification.Name("montanaInbound")
    static let montanaChatsRestored = Notification.Name("montanaChatsRestored")     // the feed was rebuilt from the sealed archive
    static let montanaArchiveIngested = Notification.Name("montanaArchiveIngested") // a twin's block was filed; userInfo["folder"]
}
extension Notification.Name { static let montanaCardSpent = Notification.Name("montanaCardSpent") }
/// A first letter came through one of my cards (userInfo «inv»: the invitation it came by) — the page showing that card closes.
extension Notification.Name { static let montanaCardMet = Notification.Name("montanaCardMet") }
extension Notification.Name { static let montanaSeedForgotten = Notification.Name("montanaSeedForgotten") }
extension Notification.Name { static let peerAvatarUpdated = Notification.Name("peerAvatarUpdated") }
extension Notification.Name { static let chatMetaUpdated = Notification.Name("chatMetaUpdated") }
extension Notification.Name { static let appLanguageChanged = Notification.Name("appLanguageChanged") }
/// The audio mode is a REQUEST to the system, and it may refuse: busy with a call, preempted
/// by another app, no route available. The refusal used to be thrown into `try?`, and the
/// person heard silence without one line about the cause. The refusal is named; what to do
/// is the caller's decision.
@discardableResult
func mtAudioTry(_ what: String, _ body: () throws -> Void) -> Bool {
    do { try body(); return true }
    catch {
        E2ELog.write("audio: \(what) — the system refused: \(error.localizedDescription)")
        return false
    }
}

enum E2ELog {
    static func write(_ s: String) {
        NSLog("[e2e] %@", s)   // system log only; we don't write an e2e.log file into the user's folder
    }
}

final class E2E {
    static let shared = E2E()
    // the SOLE owner of the crypto state (sessions/keys/ratchet) — a serial
    // queue: PQ primitives (PBKDF2 2^20, ML-KEM decaps, ML-DSA verify, ratchet) and writing to
    // Keychain NEVER happens on the main thread; main receives only finished results.
    // A mark on the queue that lets the code recognise "I am already on this queue". Without it a
    // second synchronous entry from inside the queue is an immediate deadlock and the death of the
    // process. Precedent: receiving a video downloaded all seventy-eight pieces, after which the
    // key invalidation was called from the ingest that was already running on that queue.
    private static let ingestQueueKey = DispatchSpecificKey<Void>()
    let ingestQueue: DispatchQueue = {
        let q = DispatchQueue(label: "montana.e2e.ingest", qos: .userInitiated)
        q.setSpecific(key: E2E.ingestQueueKey, value: ())
        return q
    }()

    // The one way to touch the state of the queue: it decides for itself whether a hop is needed.
    private let accLock = NSLock()
    private var keys: E2EKeyState?
    private var sessions: [String: E2ESession] = [:]
    private weak var store: ChatStore?
    private var wsGen = 0
    private var pollGen = 0
    private var lastConnectAt = Date.distantPast
    private var reauthing = false
    private var accCache: (mnemonic: String, keys: (accSeed: Data, accPub: Data, accSk: Data, appPub: Data, appSk: Data))?   // account keys are cached by the active seed (derivation is expensive: PBKDF2 2^20)
    // zeroize discipline: when the app is locked the secret cache is cleared (lifetime
    // limited to the active unlocked session). Unlock -> re-derivation from the seed.
    func clearSecretCache() { accLock.lock(); accCache = nil; accLock.unlock(); ingestQueue.async { self.keys = nil } }   // also clear the key bundle (spkSk/otk); it will be re-read from keychain
    private var recvAttempts: [String: Int] = [:]
    private var pendingLink: (ephPriv: String, nonce: String)?   // a new device is waiting for a grant
    var onKeyLinked: (() -> Void)?
    private var outByDevice: [String: [(mid: String, text: String, conv: String)]] = [:]   // the last outgoing messages per device — for resending on session reset
    private var lastRekeyHandled: [String: Date] = [:]
    private var started = false

    private var twinRef: String { MontanaSeed.twin ?? "" }

    // ── storage ──
    var currentDeviceId: String? { E2E.deviceTag() }
    private static let deviceTagLock = NSLock()
    private static var deviceTagCache: String?
    // The tag of THIS device under THIS identity — computed, never stored and never issued.
    // It exists for one reason: two devices of one seed must not write history under the same
    // nonce. Deriving it from the seed rather than from the platform keeps it out of the class
    // this tree forbids — a long-lived identifier of its own. Nothing is stored, so there is
    // nothing to carry over or to steal; it dies with the identity, because the secret under it
    // leaves with the seed; and two identities on one phone never share it. The platform value
    // enters under the hash and never leaves it.
    private static let appWriter = "quest.montana.wallet"   // NOT-UI: this app's own name under the device tag, never shown
    static func deviceTag() -> String {
        deviceTagLock.lock(); defer { deviceTagLock.unlock() }
        if let c = deviceTagCache { return c }
        E2EKeychain.delete("deviceIdStable")   // LEGACY-FORGET: the stored identifier of older builds
        guard let mnemonic = MontanaSeed.mnemonic,
              let secret = MontanaSeedKeys.entropyFrom(mnemonic: mnemonic),
              let idfv = UIDevice.current.identifierForVendor?.uuidString, !idfv.isEmpty
        else { return "ios-pending" }   // no identity yet, or the platform value is momentarily absent
        // The secret under the tag is the entropy of the phrase, not the master seed stretched
        // out of it. They are one secret in two shapes and the tag keeps every property either
        // gives it; what differs is the price. Measured: phrase -> entropy 1.26 ms,
        // phrase -> master seed 7.5 s, because the second stretches by 2^20 iterations. Paid on
        // the first archive write of a launch, on whichever thread got there first, it was the
        // freeze on opening the app — a stretch that exists to slow down a guesser has no
        // business standing between a person and their own screen.
        // ONE PHONE, TWO APPS, TWO WRITERS (09.10.2026): the platform's vendor value is one for every app of one maker on a phone,
        // so this app and the messenger of the same words were one writer -- one writer_tag under one history_key, each counting
        // its blocks from zero: the same nonce over two different blocks (the core's archive: nonce = block_seq and writer_tag),
        // the second app's blocks dropped as already held, and the two apps' light copies one device's, the poorer standing in
        // for the richer (T1 09.10: this app's restore laid one copy, without the name, the face or the page's ground the
        // messenger holds). The spec's device_id is per install: this app's own name enters under the hash.
        var m = Data("mt-device-tag".utf8); m.append(0); m.append(secret); m.append(Data(idfv.utf8)); m.append(0); m.append(Data(Self.appWriter.utf8))
        let id = "ios-" + Array(SHA256.hash(data: m)).prefix(6).map { String(format: "%02x", $0) }.joined()
        deviceTagCache = id
        return id
    }
    // One-time session reset on scheme/account change: fixes desync (stale session) after
    // reinstalls/key resets/seed-phrase changes. After a reset the first message carries the init handshake.
    // Self-test: build a handshake from OUR OWN bundle and process it ourselves — are the local keys intact?
    // ── network ──
    // the number of woken devices. 0 → the subscriber has no devices → offline (instantly).
    // Call cancellation outside the ratchet: instantly dismisses the ringing CallKit on the peer.
    func sendLinkGrant(to offer: LinkOffer) async -> Bool { false }   // device linking over mesh is a separate mechanism
    // ── Mesh call signalling: a CallSigMsg batch rides as a control-marker text over the
    // Wi-Fi-direct/BLE mesh — same pipeline as receipts/name/avatar. Media (WebRTC) uses LAN host
    // candidates; cross-network hole-punch is a separate mesh mechanism.
    // ── The peer's live draft ───────────────────────────────────────────────────────────────
    //
    // Words a person has not yet sent are the most private thing in a conversation: they live
    // on exactly two screens and nowhere else, never enter the queue (a second-old draft is
    // of no use to anyone) and go dark the moment the screen stops being visible or screen
    // recording starts.
    //
    // The observable is closed by construction: the draft goes ONLY over the direct channel
    // and never through a relay hop. Otherwise the forwarder would see frequent small frames —
    // the typing rhythm, an observable an ordinary letter does not have. Over the direct
    // channel that rhythm is visible only to the peer, who reads the words themselves anyway.
    // LIVE CHAT LIVES ONLY IN THE MONEY FLOW, AND ALWAYS THERE (the author's word 03.10: «only in the Money Flow game,
    // out of the ordinary chats»). The coin's own key is the one gate of BOTH what I say and what I show: the flow off, I
    // neither speak my words nor show theirs; theirs off, they speak nothing to me. No new wire word: each side keeps its
    // own coin -- and since 04.10 each CHAT keeps its own (MTMoneyFlow): the flow of one pair opens no other.
    /// A chat's coin was turned: off — whatever of mine stands on that peer's screen is ended, and whatever of theirs stands on
    /// mine is dropped; the words themselves stop by the gates. The other chats are not touched.
    func liveTypingSwitched(on: Bool, peer: String) {
        MontanaP2PTrace.mark("live_switch", on ? "on" : "off")
        guard !on else { return }
        if let text = E2E.saidText[peer], !text.isEmpty { sendDraftWord(to: peer, text: "", caret: 0, replyMid: "") }
        DispatchQueue.main.async { LiveDraftState.shared.dropLive(peer) }
    }

    // Live chat rides TWO roads at once. The mesh wire is instant while it lives — and on
    // cellular it dies in silence (carrier NAT, DPI, a receiver holding no channel), which is
    // exactly how the typing bubble vanished: an instant signal has no box by construction,
    // so a frame that finds no live holder at the door simply ends (measured 26.08 21:07:57 —
    // fourteen drafts on the wire, zero received). The node signal lane is the road that is
    // always there: blind E2E envelopes, held open only while the chat is on the screen.
    // Snapshots are idempotent, so a duplicate from the second road costs the receiver nothing.
    private static var nodeDraftAt: [String: Date] = [:]

    // SILENT-OK: the live draft is undeliverable by construction — it shows while both
    // screens live. Refusal here is a normal state, not a lost letter.
    /// ONE WRITER OF A DRAFT WORD. Everything the peer's draft is ever told — a snapshot while the
    /// person types, the durable checkpoint, and the word that ends it — is said here and nowhere
    /// else, so the shape on the wire and the choice of roads cannot differ by path ([C-1]).
    ///
    /// A word that ENDS the draft is not a word like the others: it carries nothing that could
    /// leak, there is exactly one of it per draft, and it is the only one whose loss leaves a
    /// ghost. It passes every gate and takes both roads unrationed. The words that carry the
    /// person's letters pass the gates and the ration, as they must.
    private static var saidText: [String: String] = [:]
    /// `carrying` rides extra keys on the word (15.11: the daily link); such a word is spoken even
    /// when the text already stands on the wire, because it is the keys that are news.
    private func sendDraftWord(to peer: String, text: String, caret: Int, replyMid: String, carrying: [String: Any] = [:], durable: Bool = false, checkpoint: Bool = false) {
        // AN EMPTY WORD IS THE ENDING — wherever it is spoken from. One rule in one place, so no
        // caller can send an emptiness that behaves like a snapshot and dies in a gate.
        let ending = text.isEmpty
        if silenced(peer) { return }   // SILENT-OK: a blocked person hears no word of mine
        if !ending {
            guard MTMoneyFlow.isOn(peer), MTScreenCapture.shared.streamAllowed else { return }   // SILENT-OK: live display is not delivery
        }
        // THE DEBT OF A STANDING WORD. The ending is owed to whoever still holds a word of mine on
        // their screen — never to my belief about their presence, which expires on its own and used
        // to swallow the ending with it. The one place that knows the debt is the last word I said.
        // Unknown (a fresh run after a crash) is not «nothing stands»: the first emptying speaks.
        // A carrying word repeats the text already standing on the wire (the caller passes it),
        // so the debt rule below is not bypassed but simply not in question: nothing changes on
        // the peer's screen, only the keys are news.
        if carrying.isEmpty {
            guard E2E.saidText[peer] != text else { return }   // SILENT-OK: the wire already says exactly this — live display, not delivery
        }
        E2E.saidText[peer] = text
        MontanaP2PTrace.mark("draft_tx", "\(ending ? "end" : "word len=\(text.count)")\(carrying.isEmpty ? "" : " carrying") to=\(String(peer.prefix(10)))")
        var body: [String: Any] = ["t": text, "c": caret, "n": E2E.draftStamp()]
        for (k, v) in carrying { body[k] = v }        // [P2P-COMPAT] unknown JSON keys are invisible to old readers
        // «ck»: the words stood when the chat closed or slept — a checkpoint, not a keystroke (24.09). [P2P-COMPAT] an
        // unknown JSON key is invisible to old readers; a reader of this build freezes the bubble and lights no «typing…».
        if checkpoint { body["ck"] = 1 }
        if !replyMid.isEmpty { body["rm"] = replyMid }   // [P2P-COMPAT] an unknown JSON key is invisible to old readers
        let doors = MontanaWakePush.signalDoors().joined(separator: ",")
        if !doors.isEmpty { body["d"] = doors }           // «these doors are alive for me» — the peer picks the first we share
        guard let d = try? JSONSerialization.data(withJSONObject: body) else { return }
        let sig = draftSignalMark + d.base64EncodedString()
        if durable {
            // The ONE builder, a second road (P-92): a word that must survive the peer's sleep —
            // the daily link — rides the delivery queue as a silent letter instead of the live lanes.
            MontanaDeliveryEngine.shared.enqueue(to: peer, chat: peer, mid: UUID().uuidString, text: sig, silent: true)
            return
        }
        _ = MontanaP2PNode.shared.sendP2P(to: peer, mid: UUID().uuidString, text: sig)
        let now = Date()
        if ending || now.timeIntervalSince(E2E.nodeDraftAt[peer] ?? .distantPast) >= 0.25 {   // 4/s fits the node's rate window
            E2E.nodeDraftAt[peer] = now
            MontanaWakePush.postChatSignal(peer, text: sig)
        }
    }

    func sendDraft(to peer: String, text: String, caret: Int = -1, replyMid: String = "") {
        sendDraftWord(to: peer, text: text, caret: caret, replyMid: replyMid)
    }

    /// 15.11: OUR DAILY LINK TO A CORRESPONDENT, so they can introduce us to a friend the way
    /// they share their own code. Spoken when a chat is opened, at most once per correspondence
    /// per six hours (the link lives a day). It rides the draft word, the one service word whose
    /// readers ignore keys they do not know, with an empty text and a fresh stamp.
    private static var linkSaidAt: [String: Date] = [:]
    /// «Hand me your link» (the author's word 15.09: share contact must work on any profile): a
    /// draft word with one extra key; a peer of this build answers with its link at once, an
    /// older peer reads an ending and nothing more. [P2P-COMPAT] unknown JSON keys are invisible.
    func askLinkWord(from peer: String) {
        guard MontanaConv.holds(peer) else { return }
        sendDraftWord(to: peer, text: E2E.saidText[peer] ?? "", caret: -1, replyMid: "", carrying: ["rq": 1])
        MontanaP2PTrace.mark("link_ask", "to=\(String(peer.prefix(10)))")
    }
    func sendLinkWord(to peer: String, force: Bool = false) {
        guard MontanaConv.holds(peer), let (link, born) = MontanaCard.currentShortWithBorn() else { return }
        if !force, let at = E2E.linkSaidAt[peer], Date().timeIntervalSince(at) < 6 * 3600 { return }
        E2E.linkSaidAt[peer] = Date()
        // The word repeats whatever of ours already stands on their screen — an empty text
        // would be an ending and could wipe a draft the field is about to speak again.
        sendDraftWord(to: peer, text: E2E.saidText[peer] ?? "", caret: -1, replyMid: "", carrying: ["rl": link, "rb": born])   // ONE builder of the word (P-92)
        MontanaP2PTrace.mark("link_tx", "to=\(String(peer.prefix(10)))")
    }

    /// The presence word of the live chat: «this chat is on my screen» / «I left». Both roads,
    /// like the draft — the beacon is what turns the peer's «in chat» on and their drafts loose.
    private func faceTail(_ peer: String) -> String {
        // «I hold no face of you» is said of a book that was READ (24.09): before the store's light half is read every
        // face is unknown, not absent — and the app's greeting, spoken at the first activation, would ask every
        // correspondent for a face it already holds.
        guard store?.lightRead == true else { return "" }
        // THE ASK STANDS WHILE THE FACE IS MISSING (the author's word 03.10.2026 16:45 MSK: «why T1 does not show every
        // avatar though Mom has one»). Asked once a life (24.09), the ask rode a word the node keeps as the correspondent's
        // LAST: the next word, without it, overwrote it before a phone with no live road swept the node, and the face never
        // came again -- T1 03.10 received one face in a whole day and never held_differs once (heardHeld reads only words
        // said now). Every build answers «f» by sending its name, bio and face again (resendProfileOnReconnect), at most once
        // in five minutes; so the ask now stands in every word until the face lands, or until the correspondent says it has
        // none (faceNone). A face whose file is gone is no face either.
        guard !(store?.holdsFace(of: peer) ?? true), !E2E.faceNone.contains(peer) else { return "" }
        if !E2E.faceAsked.contains(peer) {
            E2E.faceAsked.insert(peer)
            MontanaP2PTrace.mark("face_ask", "to=\(String(peer.prefix(10)))")
        }
        return "f"   // "I hold no face of you" (every build reads it)
    }
    private static var faceAsked = Set<String>()   // the ask is named in the diary once a life; it is said in every word
    /// The correspondents who answered an ask with «no face» (an empty face word): asked no more in this life.
    static var faceNone = Set<String>()
    /// WHAT I HOLD OF YOU, in every presence word (the author's word 20.09): «F» + the tag of the
    /// face of yours on my screen, «N» + the tag of your name — digits only, after the moment.
    /// «f» alone asked only when I held NOTHING; a stale face is not nothing, and no word ever
    /// asked for a fresher one. Now the peer compares and answers by itself (heardHeld).
    private static var heldFaceTags: [String: String] = [:]   // avatar file -> tag; a file is new every update
    private func heldTail(_ peer: String) -> String {
        // Nothing is named before the book is read (24.09): «F0N…» from an unread book said «I hold nothing of you», and
        // every correspondent answered with its face and its name again (heardHeld). A word naming nothing asks nothing.
        guard store?.lightRead == true else { return "" }
        var face = "0"
        if let file = store?.peerAvatars[peer] {
            if let t = Self.heldFaceTags[file] { face = t }
            else if let d = try? Data(contentsOf: avatarsDirURL().appendingPathComponent(file)) {
                face = MontanaDeliveryEngine.Announced.wireTag(d); Self.heldFaceTags[file] = face
            }
        }
        let name = MontanaDeliveryEngine.Announced.nameWireTag(store?.peerNames[peer] ?? "")
        // «A» + the tag of the peer's bio and link on my screen (24.09), right after the name's digits: uppercase and
        // digits, invisible to every frozen build like «F» and «N» ([P2P-COMPAT]).
        // «W» + my wall's version (24.09): the visitor fetches my page when it changes — never when they look at it.
        // «G» + the tag of the peer's page ground on my screen (25.09), right after the wall's digits: uppercase and digits,
        // unread by every older build — they stop at the first letter after the digits they read ([P2P-COMPAT]).
        // «C» + my balance (04.10), right after the ground's digits: the same uppercase and digits, unread by every older build.
        return "F" + face + "N" + name + "A" + MTPeerAbout.heldTag(peer) + "W" + MTBoard.spokenVersion(for: peer)
            + "G" + MTPageGround.heldTag(peer) + E2E.coinTail()
    }
    /// The bio's tag stands right after the name's digits; a build before 24.09 names nothing of it.
    static func aboutHeld(in payload: Substring) -> String? {
        guard let i = payload.firstIndex(of: "N") else { return nil }
        let rest = payload[payload.index(after: i)...].drop { $0.isNumber }
        guard rest.first == "A" else { return nil }
        let d = rest.dropFirst().prefix { $0.isNumber }
        return d.isEmpty ? nil : String(d)
    }
    /// The tag of my page's ground on their screen stands after the wall's version; a build before it names nothing.
    static func groundHeld(in payload: Substring) -> String? {
        guard let i = payload.firstIndex(of: "N") else { return nil }
        var rest = payload[payload.index(after: i)...].drop { $0.isNumber }
        if rest.first == "A" { rest = rest.dropFirst().drop { $0.isNumber } }
        guard rest.first == "W" else { return nil }
        rest = rest.dropFirst().drop { $0.isNumber }
        guard rest.first == "G" else { return nil }
        let d = rest.dropFirst().prefix { $0.isNumber }
        return d.isEmpty ? nil : String(d)
    }
    /// THE BALANCE RIDES THE PRESENCE WORD (the author's words 04.10.2026 03:03 and 04:19 MSK: «the top is a tunnel, a live set as by
    /// a web socket, the update instant from the nodes»; «on T2 135, and on T1 the top did not move at 04:19 -- it must, at the moment
    /// of the update»). The balance rode the word about oneself alone: said at its occasions, once in ten minutes at most, by the bell's
    /// ramp -- T2's word of 04:21:06 reached T1 at 04:22:02. Every presence word now carries it, so the live channel hands it over at
    /// once and the node keeps it as the pair's last word, which an open wallet asks for every few seconds (sweepPresence).
    /// The owner who hid the coins (MTCoinShow) says none: the word about oneself carries the withdrawal.
    static func coinTail() -> String {
        guard MTCoinShow.on, let coins = MTCoinBalance.now else { return "" }
        return "C" + String(coins)
    }
    /// The balance a peer's word tells stands after the ground's digits; a build before it names nothing.
    static func coinsSaid(in payload: Substring) -> Int? {
        guard let i = payload.firstIndex(of: "N") else { return nil }
        var rest = payload[payload.index(after: i)...].drop { $0.isNumber }
        if rest.first == "A" { rest = rest.dropFirst().drop { $0.isNumber } }
        guard rest.first == "W" else { return nil }
        rest = rest.dropFirst().drop { $0.isNumber }
        guard rest.first == "G" else { return nil }
        rest = rest.dropFirst().drop { $0.isNumber }
        guard rest.first == "C" else { return nil }
        return Int(rest.dropFirst().prefix { $0.isNumber })
    }
    /// A word of the peer, live or swept from the node, told its balance: the people's book keeps the newest (MTCoinBoard).
    static func heardCoins(from peer: String, payload: Substring, at: Double) {
        guard let coins = coinsSaid(in: payload) else { return }
        Task { @MainActor in MTCoinBoard.shared.note(peer, coins: coins, at: at) }
    }
    /// WHAT A WORD PROVES OF ITS BUILD IS READ FROM EVERY WORD, LATE ONES TOO (25.09, the author's word «on T3 I still do not
    /// see the ground»): the age of a word says when it was said, not what its build reads. Between two phones without a live
    /// road the words arrive late or not at all -- after 1931 T1 heard no presence word of T3, and T3 heard T1 only as a
    /// stamp 54 s old -- and a proof read from fresh words alone was never read: neither phone learned that the other reads
    /// the ground's word, and neither ever sent it. What their screen holds NOW is still compared from a word said now only
    /// (heardHeld).
    static func heardCapable(from peer: String, payload: Substring) {
        if aboutHeld(in: payload) != nil { noteAboutCapable(peer) }     // their build speaks the «A» tag: it reads the word
        if groundHeld(in: payload) != nil { noteGroundCapable(peer) }   // their build speaks the «G» tag: it reads the word
    }
    /// The peer's word says what of mine stands on their screen. Compared with what I have now;
    /// a difference forgets the mark and announces anew — once a minute per peer at most, so a
    /// peer that cannot apply (a blob still downloading) is not flooded.
    private var heldAskedAt: [String: Double] = [:]
    func heardHeld(from peer: String, payload: Substring) {
        func digits(after mark: Character) -> String? {
            guard let i = payload.firstIndex(of: mark) else { return nil }
            let d = payload[payload.index(after: i)...].prefix { $0.isNumber }
            return d.isEmpty ? nil : String(d)
        }
        guard let f = digits(after: "F"), let n = digits(after: "N") else { return }   // SILENT-OK: a frozen build's word names nothing
        let myFace = MontanaDeliveryEngine.Announced.wireTag(E2E.myAvatarData())
        let myName = MontanaDeliveryEngine.Announced.nameWireTag(Self.myDisplayName())
        let myAbout = MontanaDeliveryEngine.Announced.aboutTag(bio: MTPeerAbout.myBio, link: MTPeerAbout.myLink)
        let faceOff = f != myFace, nameOff = n != myName
        let heldAbout = Self.aboutHeld(in: payload)
        // Their wall's version stands after the bio's tag; a build before the wall names nothing of it.
        func wallHeard() -> String? {
            guard let i = payload.firstIndex(of: "N") else { return nil }
            var rest = payload[payload.index(after: i)...].drop { $0.isNumber }
            if rest.first == "A" { rest = rest.dropFirst().drop { $0.isNumber } }
            guard rest.first == "W" else { return nil }
            let d = rest.dropFirst().prefix { $0.isNumber }
            return d.isEmpty ? nil : String(d)
        }
        if let wv = wallHeard() {
            if Thread.isMainThread { MTBoard.shared.heard(version: wv, from: peer) }
            else { DispatchQueue.main.async { MTBoard.shared.heard(version: wv, from: peer) } }
        }
        let heldGround = Self.groundHeld(in: payload)
        // A ground still being made compares with nothing: it goes to them when it is ready (MTPageGround.prepare).
        let groundOff = heldGround.map { h in MTPageGround.mine().map { $0.tag != h } ?? false } ?? false
        let aboutOff = heldAbout.map { $0 != myAbout } ?? false
        guard faceOff || nameOff || aboutOff || groundOff else { return }
        let now = Date().timeIntervalSince1970
        if let t = heldAskedAt[peer], now - t < 60 { return }
        heldAskedAt[peer] = now
        MontanaP2PTrace.mark("held_differs", "to=\(String(peer.prefix(10))) face=\(faceOff ? 1 : 0) name=\(nameOff ? 1 : 0) about=\(aboutOff ? 1 : 0) ground=\(groundOff ? 1 : 0)")
        if nameOff { MontanaDeliveryEngine.Announced.forgetName(to: peer); sendNameIfNeeded(to: peer) }
        if faceOff { MontanaDeliveryEngine.Announced.forgetFace(to: peer); sendAvatarIfNeeded(to: peer) }
        if aboutOff { MontanaDeliveryEngine.Announced.forgetAbout(to: peer); sendAboutIfNeeded(to: peer, force: true) }
        if groundOff { MontanaDeliveryEngine.Announced.forgetGround(to: peer); sendGroundIfNeeded(to: peer, force: true) }
    }
    /// «T» + the seconds: the word's own moment (ChatStore.presenceMoment reads it). UPPERCASE
    /// and digits — invisible to every frozen build ([P2P-COMPAT]), before the door's «@».
    /// THE MILLISECOND (24.09): a chat that closes says «left, entered, left» inside one second, and one word rides two
    /// roads; the reader orders the live words by the moment they were said (ChatStore.liveWordMoves), and a second is too
    /// coarse to order them. «T», the seconds, a dot and three digits — an older reader takes the digits before the dot
    /// and reads the seconds as it always did (every reader stops at the first character that is not a digit). One
    /// builder for every word that says its moment: the presence words, the block word and the typing word.
    /// THE NODE'S CLOCK, STRICTLY GROWING (24.09, the author's word): the phone's own clock put a phone set wrong out of
    /// every peer's «now» — its live words read as history everywhere. The node's clock is the one both ends learn; it is
    /// learned from the node's answers and starts each life where the last one left it (MontanaWakePush.skewKey), read to
    /// the second, and may step back — so the moment is the draft word's own counter (draftStamp), which never steps
    /// back: every word this phone says is ordered in one row.
    static func saidTail() -> String {
        let ms = E2E.draftStamp()
        return "T" + String(ms / 1000) + "." + String(String(1000 + ms % 1000).dropFirst())
    }
    private func momentTail() -> String { E2E.saidTail() }
    /// «@DOOR» — the door I ask for signals, in the beacon's tail. UPPERCASE on purpose: old
    /// readers scan the tail for the lowercase letters «h» and «f» and read nothing else, so a
    /// capital host name is invisible to every frozen build ([P2P-COMPAT]); DNS reads no case.
    private func doorTail() -> String {
        let d = MontanaWakePush.signalDoors().joined(separator: ",")
        return d.isEmpty ? "" : "@" + d.uppercased()
    }
    func chatBeacon(to peer: String, open: Bool, why: String) {
        guard MontanaPresencePrivacy.sharing else { return }   // 10-C.3: silence IS the hiding
        // The author's question named the rule: WHY log every second that a peer sits in a
        // chat? The measure is the CHANGE (entered/left — and presence_set on the receiver);
        // the keepalive beat is wire mechanics and writes nothing.
        if why != "heartbeat" {
            MontanaP2PTrace.mark("presence_tx", "kind=chat open=\(open ? 1 : 0) why=\(why) cap=\(E2E.presenceCapable(peer) ? 1 : 0) to=\(String(peer.prefix(10)))")
        }
        // «K…» — the peer's letters I hold whole (HeldLetters, 23.09): before the door, which every build reads to the end.
        speakPresence(to: peer, watchMark + (open ? "1" : "0") + faceTail(peer) + momentTail() + heldTail(peer) + MontanaDeliveryEngine.HeldLetters.tail(peer) + doorTail(), why: why, alsoNode: !open)
    }

    /// ONE ROAD PER PRESENCE WORD — the one decision point every beacon passes (15.3 meets D-1).
    /// The beat is what the draft stream and the door list stand on, so it must reach the peer on
    /// EVERY beat — by one road, chosen here and nowhere else. A standing channel carries it as
    /// wire mechanics, for free; with no channel the store carries it to the one door of the
    /// conversation (15.2: one post, not the three D-1 measured — 37% of the diary). The beat
    /// never dials: looking for a road is a letter's job (16.1.5: a beat every 20 s dialled a dead
    /// IPv6 door, four lines a beat). [P2P-COMPAT] a peer who has not spoken presence gets the
    /// store word once a minute as an introduction and no mesh letter at all — an old build
    /// shows an unknown word as a message (the 1013 flood).
    /// A blocked person hears nothing of me (the author's word 15.09, the reference's rule): no
    /// presence, no typing, no draft, no name, no face — the one gate every road asks.
    func silenced(_ peer: String) -> Bool { store?.blockedChats.contains(peer) ?? false }
    private func speakPresence(to peer: String, _ text: String, why: String, alsoNode: Bool = false) {
        if silenced(peer) { return }   // SILENT-OK: the block is the silence
        if E2E.presenceCapable(peer) {
            if MontanaP2PNode.shared.hasLiveChannel(peer) { Task { _ = await signalNow(to: peer, text) } }
            // A DEPARTURE REACHES THE NODE TOO (13.09 15:14): the pipe copy told the peer in the
            // app, the node's «last word» stayed «1», and a phone sweeping it twelve seconds later
            // showed a locked phone «in chat». The node keeps the last word for the sweep — a
            // departure must be the word it keeps. A greeting still rides ONE road (P-109).
            if alsoNode || !MontanaP2PNode.shared.hasLiveChannel(peer) { MontanaWakePush.postChatSignal(peer, text: text) }
        } else if E2E.presenceIntroDue(peer) {
            MontanaP2PTrace.mark("presence_intro", "why=\(why) to=\(String(peer.prefix(10)))")
            MontanaWakePush.postChatSignal(peer, text: text)
        }
    }

    /// App-level presence for one correspondence — both roads, like the chat beacon.
    func appBeacon(to peer: String, open: Bool, why: String) {
        guard MontanaPresencePrivacy.sharing else { return }   // 10-C.3: silence IS the hiding
        // A balance's word comes every two seconds while coins are minted (coinBeacon): folded, not a line each.
        if why == "coins" { MontanaP2PTrace.markFolded("presence_tx", "kind=app open=1 why=coins", window: 60) }
        else { MontanaP2PTrace.mark("presence_tx", "kind=app open=\(open ? 1 : 0) why=\(why) cap=\(E2E.presenceCapable(peer) ? 1 : 0) to=\(String(peer.prefix(10)))") }
        speakPresence(to: peer, appMark + (open ? "1" : "0") + faceTail(peer) + momentTail() + heldTail(peer) + MontanaDeliveryEngine.HeldLetters.tail(peer), why: why, alsoNode: !open)
    }

    /// The balance moved while the person is in the app: the people in the app now hear it in the app word itself (coinTail),
    /// paced by MTCoinTell -- never from the background, where «in the app» would be a lie.
    func coinBeacon(to peer: String) {
        guard E2E.presenceCapable(peer), UIApplication.shared.applicationState == .active else { return }
        appBeacon(to: peer, open: true, why: "coins")
    }

    /// D-1: the store-lane introduction pace — one word a minute per peer, only while the
    /// peer has not yet proven the vocabulary. The mesh road needs no pacing: it opens on proof.
    private static var presenceIntroAt: [String: Date] = [:]
    static func presenceIntroDue(_ peer: String) -> Bool {
        let now = Date()
        if let t = presenceIntroAt[peer], now.timeIntervalSince(t) < 60 { return false }
        presenceIntroAt[peer] = now
        return true
    }

    /// [P2P-COMPAT] The presence notebook: a peer is capable when WE have RECEIVED a presence
    /// word from them — the only proof their build knows the vocabulary. Never inferred.
    static func presenceCapable(_ ref: String) -> Bool {
        UserDefaults.standard.bool(forKey: "pcap_" + ref)
    }
    static func notePresenceCapable(_ ref: String) {
        guard !UserDefaults.standard.bool(forKey: "pcap_" + ref) else { return }
        UserDefaults.standard.set(true, forKey: "pcap_" + ref)
        MontanaP2PTrace.mark("presence_capable", "peer=\(String(ref.prefix(10)))")
    }
    /// [P2P-COMPAT] The «about» notebook (the critic 24.09): a peer reads the «about» word when WE have heard its build
    /// speak of it — the «A» tag in its presence word, or an «about» word of its own. Never inferred: an older build
    /// buries the word without a receipt, and a state letter would knock at it hour after hour, a silent push each time.
    /// Until the proof the old road serves them (the draft word's keys, once per value).
    static func aboutCapable(_ ref: String) -> Bool {
        UserDefaults.standard.bool(forKey: "abcap_" + ref)
    }
    static func noteAboutCapable(_ ref: String) {
        guard !UserDefaults.standard.bool(forKey: "abcap_" + ref) else { return }
        UserDefaults.standard.set(true, forKey: "abcap_" + ref)
        MontanaP2PTrace.mark("about_capable", "peer=\(String(ref.prefix(10)))")
    }
    /// [P2P-COMPAT] The page's ground notebook (25.09): a peer reads the «ground» word when its build has spoken of it —
    /// the «G» tag in its presence word, or a «ground» word of its own. Never inferred, for the reason of «about».
    static func groundCapable(_ ref: String) -> Bool {
        UserDefaults.standard.bool(forKey: "pgcap_" + ref)
    }
    static func noteGroundCapable(_ ref: String) {
        guard !UserDefaults.standard.bool(forKey: "pgcap_" + ref) else { return }
        UserDefaults.standard.set(true, forKey: "pgcap_" + ref)
        MontanaP2PTrace.mark("ground_capable", "peer=\(String(ref.prefix(10)))")
        // THE FIRST PROOF IS ANSWERED WITH MINE (25.09): a build's proof rides presence words, and between two phones without a
        // live road those arrive late or never. My ground word -- «none» too -- rides the one queue of letters, which reaches
        // them, and it IS my proof to them: their build answers it with its own ground (this very line, on their side).
        DispatchQueue.main.async { E2E.shared.sendGroundIfNeeded(to: ref, force: true) }
    }

    /// [P2P-COMPAT] The «played» notebook (25.09): a peer's build says «played» — proven by its first «played» word; until then
    /// my voices and round notes to them keep the old ladder, «Read».
    static func playedCapable(_ ref: String) -> Bool { UserDefaults.standard.bool(forKey: "plcap_" + ref) }
    static func notePlayedCapable(_ ref: String) {
        guard !UserDefaults.standard.bool(forKey: "plcap_" + ref) else { return }
        UserDefaults.standard.set(true, forKey: "plcap_" + ref)
        MontanaP2PTrace.mark("played_capable", "peer=\(String(ref.prefix(10)))")
    }
    /// The screen's chat changed — the ONE executor behind openConv.didSet. Farewell to the
    /// old, greeting and a 20s heartbeat to the new, the node signal lane follows along.
    private static var chatHeartbeat: DispatchSourceTimer?
    func chatPresenceMoved(from old: String?, to new: String?) {
        E2E.chatHeartbeat?.cancel(); E2E.chatHeartbeat = nil
        if let old, MontanaConv.holds(old) {
            chatBeacon(to: old, open: false, why: "left")
            MontanaWakePush.stopChatPolling(old)
        }
        guard let new, MontanaConv.holds(new) else { return }
        MontanaWakePush.startChatPolling(new)
        chatBeacon(to: new, open: true, why: "entered")
        sendLinkWord(to: new)   // 15.11: the correspondent may hand our code on
        let t = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        // D-1: a beat every second fed three roads at once and was the single largest source
        // of both diary lines and radio wake-ups. Entry and exit speak instantly; between
        // them a 20s keepalive holds the word against the 45s receiver TTL.
        t.schedule(deadline: .now() + 20, repeating: 20)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            // The tick re-reads the truth instead of trusting its own lifecycle: if any exit
            // road missed the cancel, the beat says farewell once and stops itself.
            DispatchQueue.main.async {
                if self.store?.openConv == new {
                    // THE BEAT SPEAKS ONLY WHILE THE APP IS ON THE SCREEN (24.09): a chat left open behind a locked phone
                    // kept its place in openConv, and a beat inside the background window said «in chat» after the app's
                    // own farewell. The shade and a system sheet leave the chat on the screen (the critic's pass: a spell
                    // longer than a life under them lost «in chat» until the next beat) — only the background silences it.
                    if UIApplication.shared.applicationState != .background { self.chatBeacon(to: new, open: true, why: "heartbeat") }
                }
                else { self.chatPresenceMoved(from: new, to: self.store?.openConv) }
            }
        }
        E2E.chatHeartbeat = t
        t.resume()
    }

    /// 10-C.3 One farewell word when the person hides: "0h" — old parsers read the digit
    /// (the word dies), new ones read the tail (the stamp coarsens at once).
    func presenceFarewell() {
        let text = appMark + "0h"
        for p in E2E.presencePeers() { speakPresence(to: p, text, why: "farewell") }
        MontanaP2PTrace.mark("presence_tx", "kind=app open=0 why=farewell-hidden")
    }
    /// «I am in the app» / «I left it» — one instant broadcast to every held correspondence
    /// (capped, so a huge book cannot turn one foreground into a storm). No timer: between
    /// the broadcasts the «online» word lives on echo answers to the watcher's 20 s beat, so
    /// it is sustained exactly for those who actually look, and for no one else.
    /// THE SAME PEOPLE HEAR THE GREETING AND THE FAREWELL (24.09): the thirty-two were taken from a Set, whose order is
    /// new in every process — past thirty-two correspondents one run greeted some and bade farewell to others, and each
    /// phone kept a different moment. The freshest conversations first, by the list's own order (orderSeq).
    private static func presencePeers() -> [String] {
        let order = E2E.shared.store?.orderSeq ?? [:]
        let held = Set(MTPipeBook.all()).filter { MontanaConv.holds($0) && MTSamePair.merged($0) == nil }   // a folded pipe only forwards
        // WIDENED TO 128 (25.09): the word that says «my build speaks the wall» and names its version rides here, and the owner
        // carries the wall to whoever spoke it — past thirty-two correspondents the rest never heard of a wall at all.
        return Array(held.sorted { (order[$0] ?? 0, $0) > (order[$1] ?? 0, $1) }.prefix(128))
    }
    /// Those greeted in this life: the farewell reaches them whatever the list's order has become since (24.09, the
    /// critic's pass: a correspondent pushed out of the thirty-two by new letters heard «here» and never «gone»).
    private static var greeted: [String] = []
    private static var awayHold: UIBackgroundTaskIdentifier = .invalid
    /// A HOLD ENDS ITSELF, NOT ITS SUCCESSOR (24.09, the critic's pass): away, back and away again inside the first hold's
    /// seconds, and the first hold's timer ended the second one — the second farewell was cut in flight.
    private static func endAwayHold(_ id: UIBackgroundTaskIdentifier? = nil) {
        guard Thread.isMainThread else { DispatchQueue.main.async { endAwayHold(id) }; return }
        if let id, id != awayHold { return }   // SILENT-OK: that hold already ended when its successor began
        if awayHold != .invalid { UIApplication.shared.endBackgroundTask(awayHold); awayHold = .invalid }
    }
    /// THE GREETING WAITS FOR THE BOOK (24.09, the critic's pass): at a cold launch the application is active before the
    /// vault's key is at hand — the pipe book reads empty, the greeting went to nobody, and «said» stood for the whole
    /// session. A greeting asked for before the store's light half is read is owed, and leaves when it is (bookRead).
    private static var greetingOwed = false
    /// The store's light half is read (ChatStore, at launch): the greeting owed since the activation leaves now, while the
    /// application is still before the person.
    func bookRead() {
        guard E2E.greetingOwed else { return }   // SILENT-OK: nothing is owed
        E2E.greetingOwed = false
        if UIApplication.shared.applicationState != .background { appPresence(open: true) }
    }
    /// MY «NOW» MOVED (MontanaWakePush.learnSkew, 24.09, the second critic's pass): the greeting said before the node's
    /// clock was known wore the wrong time — every peer read a clock behind as history, and the person stood away for the
    /// whole session. It is said again by the right clock: only while the application stands before the person having
    /// greeted, and once in ten minutes at most — two doors whose clocks disagree may not make a beacon of it.
    private static var clockSaidAt = Date.distantPast
    func clockCorrected() {
        guard E2E.appSaid == true, UIApplication.shared.applicationState != .background,
              Date().timeIntervalSince(E2E.clockSaidAt) > 600 else { return }   // SILENT-OK: nobody greeted, or said just now
        E2E.clockSaidAt = Date()
        appPresence(open: true, again: true)
    }
    /// THE APP'S WORD IS SAID ONCE PER STATE (24.09). The application comes back «active» without leaving (the notification
    /// shade, a system sheet, Face ID), and a state already said is not said again to every correspondent.
    /// A farewell is owed only to those greeted in THIS life: a run woken in the background has greeted nobody (29 of the
    /// fleet's 757 background phases, 22-24.09, came with no active one before them), and its «left» would stamp a
    /// moment the person was never there. `again` is the privacy switch's: the light returns though the state stood.
    private static var appSaid: Bool?
    /// THE FAREWELL WAITS A BREATH (29.09). A leaving said the instant the application left the screen, and a return said
    /// «here» again: a person posting to the wall from the photos, locking and unlocking, switching apps, said «gone» and
    /// «here» to every correspondence at each turn -- twenty-four peers, two doors each, 96 posts a turn, up to 228 signal
    /// posts a minute on T1 (23:26-23:31Z, 28.09), every one a connection through the tunnel. The farewell now leaves
    /// awayGraceS after the door closes, inside the same hold that keeps the process alive; a return within the grace
    /// cancels it and says nothing -- the state «here» never stopped standing. The peers' word about me lives 45 s
    /// (presenceLife), so the breath is invisible to them; a «last seen» is later by the breath, and only when the
    /// person truly left. The hold's expiry says the farewell at once, whatever is left of the grace.
    private static let awayGraceS: TimeInterval = 8
    private static var awayPending: DispatchWorkItem?
    func appPresence(open: Bool, again: Bool = false) {
        if open, store?.lightRead != true { E2E.greetingOwed = true; return }   // SILENT-OK: owed until the book is read (bookRead)
        if !open { E2E.greetingOwed = false }
        if open, let pending = E2E.awayPending {
            // Back within the breath: the farewell never leaves, and «here» stands as it was said (a re-greeting adds nothing).
            pending.cancel(); E2E.awayPending = nil; E2E.endAwayHold()
            MontanaP2PTrace.mark("presence_hold", "back within the grace -- the farewell is cancelled, «here» stands")
            if !again { return }
        }
        if !again, E2E.appSaid == open { return }   // SILENT-OK: this very state is already said to everyone
        if !open, E2E.appSaid == nil { return }     // SILENT-OK: nobody was greeted in this life, nobody is owed a farewell
        guard open else {
            // THE FAREWELL FINISHES (13.09 15:14): a lock suspends the app within milliseconds and the
            // departure posts died in flight. The task assertion keeps the process alive for the posts'
            // own deadline, so the word «0» reaches the peer and the node before the sleep.
            E2E.endAwayHold()
            var hold: UIBackgroundTaskIdentifier = .invalid
            hold = UIApplication.shared.beginBackgroundTask(withName: "presence-away") { [weak self] in
                // The system's time is up before the breath ended: the farewell leaves now, then the hold.
                if let pending = E2E.awayPending { E2E.awayPending = nil; pending.cancel(); self?.sayAway(hold: hold, why: "app-away-expiry") }
                E2E.endAwayHold(hold)
            }
            E2E.awayHold = hold
            let work = DispatchWorkItem { [weak self] in
                guard E2E.awayPending != nil else { return }
                E2E.awayPending = nil
                self?.sayAway(hold: hold, why: "app-away")
            }
            E2E.awayPending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + E2E.awayGraceS, execute: work)
            return
        }
        E2E.appSaid = true
        let now = E2E.presencePeers()
        // A GREETING SAID AGAIN ADDS, IT DOES NOT FORGET (24.09, the second critic's pass): the privacy switch and the
        // clock's correction say «here» once more to the list of this moment, and those greeted before who had left the
        // thirty-two lost their farewell — their «last seen» stood at the greeting.
        E2E.greeted = again ? E2E.greeted + now.filter { !E2E.greeted.contains($0) } : now
        for p in now { appBeacon(to: p, open: true, why: "app-front") }
        if let oc = store?.openConv, MontanaConv.holds(oc) {
            chatBeacon(to: oc, open: true, why: "app-return")   // the chat on screen greets again at once
        }
    }
    /// The farewell itself: to everyone greeted in this life and to the list of this moment; the hold ends after the posts' deadline.
    private func sayAway(hold: UIBackgroundTaskIdentifier, why: String) {
        E2E.appSaid = false
        let now = E2E.presencePeers()
        let peers = E2E.greeted + now.filter { !E2E.greeted.contains($0) }
        for p in peers { appBeacon(to: p, open: false, why: why) }
        DispatchQueue.main.asyncAfter(deadline: .now() + MTNodeWire.postTimeoutS + 2) { E2E.endAwayHold(hold) }
    }

    /// The peer's beat says «my chat with you is open» — answer with my state at once: that
    /// answer IS what keeps their word about me alive (one presenceLife, fed every beat). The 0.8s
    /// throttle collapses the multi-road copies of one beat into one answer and still kills
    /// echo-on-echo chains: an answer provoked by an answer lands inside the window and dies.
    private static var echoAt: [String: Date] = [:]
    func presenceEcho(to peer: String) {
        let now = Date()
        if now.timeIntervalSince(E2E.echoAt[peer] ?? .distantPast) < 0.8 { return }
        E2E.echoAt[peer] = now
        if store?.openConv == peer { return }   // my own 20 s beat already answers — no second road
        // THE ECHO SPEAKS AS THE BEAT DOES (24.09, the second critic's pass): under the shade or a system sheet my beat went
        // on and my echo fell silent — one peer read me here, another away. Only the background silences both.
        if UIApplication.shared.applicationState != .background { appBeacon(to: peer, open: true, why: "echo") }
    }

    /// THE CHECKPOINT IS NOT TYPING (24.09, the author's word: «sometimes it shows typing when nobody types»). A chat that
    /// closes or sleeps speaks the words standing in its field, AFTER its farewell (onDisappear: openConv, then this) — and
    /// the reader took the words for a keystroke: «typing…» for five seconds and «in chat» for a whole life, for a person
    /// who had just left. The word says what it is (ck); what it carries is the bubble, frozen.
    func sendDraftCheckpoint(to peer: String, text: String, caret: Int = -1) {
        sendDraftWord(to: peer, text: text, caret: caret, replyMid: "", checkpoint: true)
        ChatStore.setCkptSent(peer, text)
    }

    /// WHERE THE PHANTOM CAME FROM, AND WHY IT CANNOT COME AGAIN.
    ///
    /// The clear was sent as one more draft snapshot — and snapshots are rationed. The push road
    /// opens no more than four times a second, so a clear that followed the last letters within a
    /// quarter of a second rode the DIRECT road only; to a peer reachable through the node alone
    /// it never left, and his screen kept the words that had already become a letter. Two more
    /// gates could swallow it just as quietly: live typing switched off, and a screen recording in
    /// progress — both meant to stop words from streaming, both stopping the word that ends the
    /// streaming.
    ///
    /// The word that ENDS a state is not a word like the others. It carries nothing to leak, it
    /// cannot flood anything — there is exactly one of it per draft — and it is the only word whose
    /// loss leaves a ghost. So it goes on both roads, unrationed, through every gate.
    func sendDraftClear(to peer: String) {
        sendDraftWord(to: peer, text: "", caret: 0, replyMid: "")
    }

    /// THE MOMENT A DRAFT WORD WAS SAID — the node's clock, which both ends already share.
    /// A word of the draft travels two roads at once, and the two do not arrive in the order they
    /// left: a snapshot said BEFORE the clear can land AFTER it, and the words that already became
    /// a letter come back for a blink. Arrival cannot decide what is newer; only the moment of
    /// speaking can, and it rides with the word.
    /// Strictly growing, always: two words inside one millisecond, or a node-clock correction that
    /// steps backwards, would otherwise make a later word «not newer» — and the receiver, obeying
    /// its own ordering rule, would drop the ENDING and keep the last frame forever.
    /// Every word that says its moment takes it here (24.09): the draft word, the presence words, the typing word.
    private static var lastStamp = 0
    static func draftStamp() -> Int {
        E2E.lastStamp = max(Int(MontanaWakePush.nodeNow() * 1000), E2E.lastStamp + 1)
        return E2E.lastStamp
    }

    /// The keys of a draft word that make it a word of STATE, not a keystroke (24.09): the checkpoint of a closing chat
    /// (ck), the daily link (rl, rb), the bio (ab, al, at) and the ask for a link (rq).
    static let draftStateKeys = ["ck", "rl", "rb", "ab", "al", "at", "rq"]
    /// nil = this word is not news. It must move NOTHING: an echo of the road once answered
    /// «active» for the very word it had just rejected, and that answer relit «typing…» for
    /// another five seconds while the person was typing nothing at all.
    /// «active» IS A KEYSTROKE (24.09): a word of state (draftStateKeys) moves the bubble and the keys it carries — never
    /// «typing…», and never «in chat» through it.
    @discardableResult
    func handleMeshDraft(from peer: String, payload: String) -> (active: Bool, reply: Bool)? {
        guard let d = Data(base64Encoded: payload),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        let text = (j["t"] as? String) ?? ""
        let caret = (j["c"] as? Int) ?? -1
        let rm = (j["rm"] as? String) ?? ""
        if let d = j["d"] as? String { MontanaWakePush.notePeerDoor(peer, host: d) }   // the door they ask
        // 15.11: THEIR DAILY LINK, handed to us to hand on. [P2P-COMPAT] an unknown JSON key is
        // invisible to old readers; the word carries an empty draft, which old builds treat as
        // «the draft ended»: harmless, nothing of theirs stands on our screen when we open a chat.
        if let rl = j["rl"] as? String, MontanaCard.isShort(rl) {
            MTPeerLinks.note(peer, link: rl, born: (j["rb"] as? Double) ?? Date().timeIntervalSince1970)
        }
        // 24.09: THEIR BIO AND THEIR LINK, as they gave them -- the same road, two keys more. [P2P-COMPAT] an
        // unknown JSON key is invisible to old readers, and the word itself is one every living build knows.
        if j["ab"] != nil || j["al"] != nil {
            MTPeerAbout.note(peer, bio: (j["ab"] as? String) ?? "", link: (j["al"] as? String) ?? "",
                             at: (j["at"] as? Double) ?? Date().timeIntervalSince1970)
        }
        // They ask for our link (share contact on their side): answered at once, throttle aside.
        if (j["rq"] as? Int) == 1 { DispatchQueue.main.async { self.sendLinkWord(to: peer, force: true) } }
        // A word older than the one already shown is not news, it is an echo of the road.
        // [P2P-COMPAT] a build that says no moment is believed as before — it makes no claim.
        if let said = j["n"] as? Int {
            if said <= LiveDraftState.shared.saidAt[peer] ?? 0 {
                MontanaP2PTrace.mark("draft_echo", "dropped an older word from \(String(peer.prefix(10)))")
                return nil
            }
            LiveDraftState.shared.saidAt[peer] = said
        }
        // MY MONEY FLOW IS OFF: their door and their link above are still noted — those are not
        // live chat — but their words show nothing and move nothing here: no bubble, no
        // «typing…». The peer's own coin decides whether they speak at all.
        guard MTMoneyFlow.isOn(peer) else {
            // THE REFUSAL IS NAMED (22.09). "The live typing broke" could not be answered from the record:
            // the word arriving was written down, the word SHOWN was not, and neither was the reason a
            // word showed nothing. Now both are, folded so typing cannot flood the diary.
            MontanaP2PTrace.markFolded("draft_gate", "flow=off from=\(String(peer.prefix(10)))", window: 60, key: peer)
            return nil
        }
        // WORDS THAT ALREADY BECAME A LETTER ARE NOT A DRAFT (21.09, the author's screen): the
        // sender of an older build spoke the whole text once more 1.7 s AFTER the letter and its
        // ending (T1 13:45:31Z), with a moment newer than both — so the moment rule let it
        // through and the letter stood twice, once as a bubble and once as a ghost with a caret.
        // The letter on screen is the knowledge: a word equal to a letter the peer already
        // landed is buried, whatever its moment says. [P2P-COMPAT] receiver-side only.
        DispatchQueue.main.async {
            if !text.isEmpty, ChatStore.live?.peerLetterStands(peer, text: text) == true {
                MontanaP2PTrace.mark("draft_ghost", "buried a word equal to a landed letter from \(String(peer.prefix(10)))")
                LiveDraftState.shared.applyLive(peer, "")
                ChatStore.live?.typingChats.remove(peer)
                return
            }
            LiveDraftState.shared.applyLive(peer, text)
            MontanaP2PTrace.markFolded("draft_shown", "len=\(text.count) from=\(String(peer.prefix(10)))", window: 5, key: peer)
            LiveDraftState.shared.setCaret(peer, caret)
            LiveDraftState.shared.setReplyMid(peer, rm)
        }
        // A keystroke is a word with text and without a key of state (draftStateKeys), said now by its own moment — the
        // lane hands a minute of old words over when a chat opens — and not from before the peer's departure: a word of
        // the other road landing after the «left» is older than it (24.09). A build that says no moment is believed as before.
        let saidNow = (j["n"] as? Int).map { MontanaWakePush.nodeNow() - Double($0) / 1000 <= ChatStore.typingWordLife } ?? true
        let keystroke = !text.isEmpty && !E2E.draftStateKeys.contains { j[$0] != nil } && saidNow && store?.peerLeftLive(peer) != true
        return (keystroke, !rm.isEmpty)
    }

    /// An INSTANT signal: one throw into the wire and no promises ([C-1] — the road for what
    /// must arrive is exactly one, and it is the delivery queue).
    ///
    /// The name `sendText` used to stand here, and it lied: beside the queue it looked like an
    /// ordinary send, while in fact it threw the letter into the mesh exactly once. A peer with
    /// a sleeping socket received nothing, and nobody learned of it — that is how the «delete
    /// for both» tombstone vanished, and likewise delete-for-everyone, reactions and banner
    /// replies. The name itself closes the possibility of picking the wrong place: only
    /// signals that live for an instant go here — «typing» and the live draft — for which
    /// non-delivery is a normal state, not a loss.
    func signalNow(to: String, _ text: String, mid: String = UUID().uuidString) async -> String? {
        guard MontanaP2PNode.stageGate else { return nil }
        let p = to; let m = mid; let tx = text; let st = self.store
        let tr: MontanaTransport? = await withCheckedContinuation { cont in
            DispatchQueue.global().async { cont.resume(returning: MontanaP2PNode.shared.sendP2P(to: p, mid: m, text: tx)) }
        }
        if let tr { await MainActor.run { st?.setTransport(chat: p, mid: m, transport: tr.rawValue) } }
        return tr != nil ? "mesh:" + m : nil
    }

    // ── send (fan-out to the peer's devices and my other ones) ──
    // re-establish the peer channel (e.g., when the app returns from background)
    // Seal one message for one device — shared logic for send and resend (SSOT).
    // Shared sealing finale: encrypts arbitrary plaintext over the session/handshake.
    // The recipient could not decrypt (chain desync) → we ask the sender to recreate the session.
    // The sender received a rekey → reset the session and resend recent messages to this device.
    // ── device linking (Signal model) ──
    // New device: prepare an offer for the QR and start waiting for the grant.
    func beginLinkOnNewDevice() -> LinkOffer? {
        guard let dev = currentDeviceId, let (priv, offer) = MontanaLink.makeOffer(deviceId: dev) else { return nil }
        pendingLink = (priv, offer.nonce)
        return offer
    }
    func cancelLink() { pendingLink = nil }
    // The seed left the device: the tag derived from it is no longer this device's tag.
    static func forgetDeviceTag() { deviceTagLock.lock(); deviceTagCache = nil; deviceTagLock.unlock() }

    // "Delete for both": a signal to the peer (conv = my address on their side) and
    // to my own devices (conv = the peer) to delete the dialog.
    // ── Avatar over E2E ──
    // A picture of 640 by 640 at quality 0.8. Such a file does not fit the bound of a message, so
    // it travels as an attachment through the common pipeline of pieces, and the message carries
    // only the manifest.
    static func myAvatarData() -> Data? {
        // THE FACE OF THE PERSON OF THIS WALLET (MTWalletPerson, the author's word 10.10.2026): the bytes their app keeps, as its
        // copy carries them -- already in the wire shape their app writes back once -- so the tag is the same every sweep.
        let d = MTWalletPerson.face
        return d.isEmpty ? nil : d
    }
    // Retrying pictures that did not finish downloading: the manifest was kept when the download
    // failed, and it is tried again once the network is back.

    // One walk over the correspondents; what is offered to each of them is the argument.
    /// To whom the name and face are announced: EVERY correspondence this device answers for.
    ///
    /// Feed keys used to stand here — conversations already holding at least one message. Until
    /// two people have written a single word, no such conversation exists in the feed, and the
    /// announcement went into the void: a person took a callsign, changed the name, and the
    /// peer saw the old one — forever, because a second occasion to announce never came. The
    /// measurement showed exactly that: the last «NAME → queued» in the journal was over an
    /// hour older than the name itself, with a live node and working delivery.
    ///
    /// A correspondence exists where a pipe secret exists, and the pipe book is the only place
    /// that knows. The feed knows only what has already been said.
    func broadcastToPeers(_ sendIfNeeded: (String) -> Void) {
        for peer in Set(MTPipeBook.all()) where MontanaConv.holds(peer) { sendIfNeeded(peer) }
    }
    func broadcastAvatar() { sendFace(to: Array(Set(MTPipeBook.all()))) }   // one preparation, one upload, N letters
    // SSOT: a chunked manifest (media/avatar/voice) sent over the mesh MUST be accompanied by its
    // sealed blobs — the recipient reconstructs from its LOCAL blob store, so the bytes have to be
    // there. Streamed fire-and-forget BEFORE the manifest so the peer already holds them.
    @discardableResult
    static func streamManifestChunksOverMesh(_ ref: [String: Any], to peer: String) -> Bool {
        var allOk = true
        for c in (ref["chunks"] as? [[String: Any]] ?? []) {
            guard let bid = c["bid"] as? String, let sealed = MontanaBlobStore.get(bid) else { allOk = false; continue }
            MontanaP2PTrace.mark("blob_tx", "id=\(String(bid.prefix(8))) bytes=\(sealed.count)")
            if !MontanaP2PNode.shared.sendBlobP2P(to: peer, blobId: bid, sealed: sealed) { allOk = false }
        }
        return allOk
    }

    // ── Display name over E2E — the same pipeline as the avatar (send-once flag per peer,
    // keyed by MY address so an account switch re-sends; resend on change; reciprocity on receive).
    /// THE WALLET KEEPS NO PERSON OF ITS OWN (the author's word 10.10.2026 12:4x MSK): the name is the one the person gave in
    /// their app, else the public name they hold there -- Montana first, then Business (MTWalletPerson) -- never a field of the
    /// wallet's own; no account of these words, no name.
    // AIR-CHECKED: the name leaves only inside the E2E seal of an established channel.
    static func myDisplayName() -> String {
        MTCrown.plain(MTWalletPerson.name.trimmingCharacters(in: .whitespaces))
    }
    func displayName(for ref: String) -> String {
        // Cold start (voip push): the store is not up yet — the BOOK provides the name directly
        // (it lives in the device vault without the store). Short-form digits only when nobody
        // has named themselves.
        if let s = store { return s.displayName(for: ref) }
        return MTNameBook.known(ref) ?? MontanaConv.short(ref)
    }
    /// The glyph of ONE'S OWN face — the same computation as the profile circle: the callsign
    /// emoji, else the name's letter. Rides in every letter and call envelope — the peer sees
    /// the profile avatar.
    static func myFaceGlyph() -> String {
        MontanaAvatar.initial(title: myDisplayName(), name: "")   // no name: the round face with nothing on it, as a nameless row's
    }
    func broadcastName() {
        broadcastToPeers { sendNameIfNeeded(to: $0) }
        MontanaCard.refreshCards()   // the cards on the node wear the new name too (21.09)
    }
    private var lastProfilePush: [String: Date] = [:]
    // Peer reachable again: FORCE a fresh
    // name+avatar push, clearing the send-once flags so a value that never applied on the peer (lost
    // delivery, or an old build that showed it as text) is re-sent — exactly once per reconnect
    // (throttled 5 min/peer). Fired only on peer discovery, never per message, so there is no loop.
    func resendProfileOnReconnect(to ref: String) {
        guard MontanaConv.holds(ref) else { return }
        if let t = lastProfilePush[ref], Date().timeIntervalSince(t) < 300 { return }
        lastProfilePush[ref] = Date()
        MontanaDeliveryEngine.Announced.forgetName(to: ref)
        MontanaDeliveryEngine.Announced.forgetFace(to: ref)
        MontanaDeliveryEngine.Announced.forgetAbout(to: ref)
        MontanaDeliveryEngine.Announced.forgetGround(to: ref)   // the page's ground rides with the bio (sendAboutIfNeeded)
        sendNameIfNeeded(to: ref)
        sendAvatarIfNeeded(to: ref)
        sendAboutIfNeeded(to: ref)
        MontanaWakePush.reannounce(to: ref)   // the wake handle catches up by the same road as the name
    }
    /// My name to this peer anew, whatever the receipt mark says — the mark is forgotten first.
    func renewName(to ref: String) {
        MontanaDeliveryEngine.Announced.forgetName(to: ref)
        sendNameIfNeeded(to: ref)
    }
    /// BLOCKED: what the blocked person's phone is told (the author's word 15.09, the
    /// reference's picture): my face is taken back, and one presence word says «gone» — the
    /// tail letter «B», uppercase, which every frozen build reads as nothing (they scan the tail
    /// for lowercase «h» and «f» alone, [P2P-COMPAT]) and this build reads as «seen long ago,
    /// no face». The word rides the ONE durable queue like the face (measured 15.09 13:14: on
    /// the lane it lived sixty seconds, the phone in the pocket never read it) — settled by the
    /// node's acceptance like every silent letter, kept in the box a day. Only a peer that has
    /// spoken presence words is told (their door knows the word, [P2P-COMPAT]).
    func announceBlocked(to peer: String) {
        guard MontanaConv.holds(peer) else { return }
        MontanaDeliveryEngine.Announced.forgetFace(to: peer)
        MontanaDeliveryEngine.shared.enqueue(to: peer, chat: peer, mid: ChatStore.mintMid().mid,
                                             text: avatarMark, silent: true, kind: .picture)   // the face taken back
        if E2E.presenceCapable(peer) {
            MontanaDeliveryEngine.shared.enqueue(to: peer, chat: peer, mid: ChatStore.mintMid().mid,
                                                 text: appMark + "0B" + momentTail(), silent: true)
        }
        // My page's ground is taken back too, where the word is read (25.09): a blocked person keeps no picture of mine.
        if E2E.groundCapable(peer), let body = MTPageGround.word("") {
            MontanaDeliveryEngine.Announced.forgetGround(to: peer)
            MontanaDeliveryEngine.shared.enqueue(to: peer, chat: peer, mid: ChatStore.mintMid().mid,
                                                 text: groundMark + body, silent: true, kind: .ground)
        }
        MontanaP2PTrace.mark("block_tx", "to=\(String(peer.prefix(10))) gone=\(E2E.presenceCapable(peer) ? 1 : 0)")
    }
    /// UNBLOCKED: the person is told I am here again — my name, my face, my presence.
    func announceUnblocked(to peer: String) {
        guard MontanaConv.holds(peer) else { return }
        lastProfilePush[peer] = nil
        resendProfileOnReconnect(to: peer)
        appBeacon(to: peer, open: MTForeground.active, why: "unblocked")
        sendLinkIfNeeded(to: peer)
        sendAboutIfNeeded(to: peer)   // my bio and my link, if they never had them (24.09)
    }
    /// THE DAILY LINK, PRELOADED (the author's word 15.09: share contact must not wait): my
    /// current short link rides to every correspondent as a silent durable letter — the draft
    /// word's shape, which every build parses as a dictionary (an old build reads an ending and
    /// nothing else, [P2P-COMPAT]) — once per link per peer; the receiver keeps it for a day.
    func sendLinkIfNeeded(to peer: String) {
        guard MontanaConv.holds(peer), !silenced(peer), let (link, born) = MontanaCard.currentShortWithBorn() else { return }
        let key = "linkSent." + peer
        if UserDefaults.standard.string(forKey: key) == link { return }
        UserDefaults.standard.set(link, forKey: key)
        sendDraftWord(to: peer, text: E2E.saidText[peer] ?? "", caret: -1, replyMid: "", carrying: ["rl": link, "rb": born], durable: true)   // ONE builder of the word (P-92)
        MontanaP2PTrace.mark("link_tx", "durable to=\(String(peer.prefix(10)))")
    }
    /// Every correspondent gets the current link (launch, foreground, rotation) — nothing if they have it.
    func sendLinkToAll() {
        for peer in MTPipeBook.all() { sendLinkIfNeeded(to: peer) }
    }
    /// MY BIO AND MY LINK, AS STATE (the author's word 24.09: «my profile did not show to others, even after the update,
    /// until I edited it»). The words rode one draft word whose mark was written before the send, with no receipt back:
    /// a peer that missed that one word — offline past the box's day, or on a build that did not read the keys yet —
    /// never received them again until they changed. They ride now exactly like the name: one silent letter of kind
    /// «about» in the one queue, repeated until the peer's receipt, and ONLY the receipt writes the mark
    /// (Announced.recordDelivered). Every occasion that heals the name heals them: the peer's letter, the chat opened,
    /// the peer's return, a presence word naming other words than mine, the launch and the return to the app.
    func sendAboutIfNeeded(to peer: String, force: Bool = false) {
        // THE PAGE'S GROUND RIDES EVERY OCCASION OF THE BIO (25.09): one list of occasions heals my words and my ground.
        defer { sendGroundIfNeeded(to: peer) }
        guard MontanaConv.holds(peer), !silenced(peer) else { return }
        guard MTWalletPerson.card != nil else { return }   // words of a person not yet read are silence, not «no words»
        let bio = MTPeerAbout.myBio, link = MTPeerAbout.myLink
        sendAboutByDraft(to: peer, bio: bio, link: link)   // the builds 1919-1921 read only the draft word's keys
        guard Self.aboutCapable(peer) else { return }      // [P2P-COMPAT]: the new word only to a proven reader
        let tag = MontanaDeliveryEngine.Announced.aboutTag(bio: bio, link: link)
        let key = MontanaDeliveryEngine.Announced.about(to: peer)   // sentAb1_ -- this device's own (SeedScope)
        let held = UserDefaults.standard.string(forKey: key)
        // THE BALANCE RIDES THE SAME WORD (03.10, MTCoinBoard): told again when it changed, once in ten minutes at most -- a
        // minting pair's balance moves every second, and a word on every coin would be the flow's storm again.
        // HIDDEN IS SAID, NOT LEFT UNSAID (04.10, MTCoinShow): an owner who hid the coins tells -1 once, and the pair's rating
        // drops the row; silence would leave the last balance standing on their screen.
        let coins = MTCoinShow.on ? MTCoinBalance.now : -1, now = Date().timeIntervalSince1970
        let coinsKey = "aboutCoins." + peer
        let said = UserDefaults.standard.dictionary(forKey: coinsKey)
        let coinsDue = coins.map { c in (said?["c"] as? Int) != c && 600 <= now - ((said?["at"] as? Double) ?? 0) } ?? false
        if held == tag, !coinsDue { return }                          // RECEIPTED with these words and this balance
        if held == nil, tag == "0", !force, !coinsDue { return }      // nothing was ever said, and nothing is said now
        if MontanaDeliveryEngine.shared.pendingStateTag(kind: .about, to: peer) == tag, !coinsDue { return }   // on their way
        var word: [String: Any] = ["b": bio, "l": link, "at": now]
        if let coins { word["c"] = coins }
        if let own = MTOwnWords.tag(for: peer) { word["o"] = own }   // a tag only my words make: a pair of my words knows itself (06.10)
        guard let d = try? JSONSerialization.data(withJSONObject: word),
              let body = String(data: d, encoding: .utf8) else { return }
        // A newer value takes the place of an older one still in the queue (LAW S-1, one state — one record).
        MontanaDeliveryEngine.shared.enqueue(to: peer, chat: peer, mid: ChatStore.mintMid().mid,
                                             text: aboutMark + body, silent: true, kind: .about)
        if let coins { UserDefaults.standard.set(["c": coins, "at": now] as [String: Any], forKey: coinsKey) }
        MontanaP2PTrace.mark("about_tx", "to=\(String(peer.prefix(10))) bio=\(bio.isEmpty ? 0 : 1) link=\(link.isEmpty ? 0 : 1) tag=\(tag)")
    }
    /// The balance told now, past the word's ten minutes (MTWalletPull): the pace's mark is let go and the word goes.
    func tellBalance(to peer: String) {
        UserDefaults.standard.removeObject(forKey: "aboutCoins." + peer)
        sendAboutIfNeeded(to: peer)
    }
    /// THE OLD ROAD, SERVED UNTIL IT DIES OUT ([P2P-COMPAT], clause d): builds 1919-1921 read the bio only from the draft
    /// word's «ab/al» keys and bury the new word. Once per value per correspondent, as they always had it.
    private func sendAboutByDraft(to peer: String, bio: String, link: String) {
        let key = "aboutSent." + peer
        let now = bio + "\n" + link
        let said = UserDefaults.standard.string(forKey: key)
        if said == now { return }
        if said == nil, bio.isEmpty, link.isEmpty {   // nothing was ever said, and nothing is said now
            UserDefaults.standard.set(now, forKey: key); return
        }
        // The word rides as an ENDING, and an ending passes every gate of the one builder, so the mark set
        // here is true by construction. While a live word of mine stands on their screen, the bio waits for
        // the next pass, unmarked, rather than end or repeat what the person is typing.
        guard (E2E.saidText[peer] ?? "").isEmpty else {
            MontanaP2PTrace.mark("about_tx", "held to=\(String(peer.prefix(10))): a live word of mine stands there")
            return
        }
        UserDefaults.standard.set(now, forKey: key)
        sendDraftWord(to: peer, text: "", caret: -1, replyMid: "",
                      carrying: ["ab": bio, "al": link, "at": Date().timeIntervalSince1970], durable: true)   // ONE builder of the word (P-92)
        MontanaP2PTrace.mark("about_tx", "draft to=\(String(peer.prefix(10))) bio=\(bio.isEmpty ? 0 : 1) link=\(link.isEmpty ? 0 : 1)")
    }
    /// My bio and my link to every correspondent -- nothing to one who already has them.
    func broadcastAbout() {
        for peer in MTPipeBook.all() { sendAboutIfNeeded(to: peer) }
    }
    /// MY PAGE'S GROUND, AS STATE (the author's word 25.09: «from T3 I opened T1's page and see no background»): exactly
    /// like my words about myself — one silent letter of kind «ground» in the one queue, repeated until the peer's
    /// receipt, and only the receipt writes the mark (Announced.recordDelivered); only to a peer whose build reads the
    /// word, never to a blocked one. A picture still being made goes when it is ready (MTPageGround.prepare).
    func sendGroundIfNeeded(to peer: String, force: Bool = false) {
        guard MontanaConv.holds(peer), !silenced(peer), Self.groundCapable(peer) else { return }   // COMPAT-GATED
        guard let now = MTPageGround.mine() else { return }
        let key = MontanaDeliveryEngine.Announced.ground(to: peer)   // sentPg1_ -- this device's own (SeedScope)
        let held = UserDefaults.standard.string(forKey: key)
        if held == now.tag { return }                          // RECEIPTED with this ground
        if held == nil, now.tag == "0", !force { return }      // nothing was ever shown, and nothing is shown now
        if MontanaDeliveryEngine.shared.pendingStateTag(kind: .ground, to: peer) == now.tag { return }   // on its way
        guard let body = MTPageGround.word(now.g) else { return }
        MontanaDeliveryEngine.shared.enqueue(to: peer, chat: peer, mid: ChatStore.mintMid().mid,
                                             text: groundMark + body, silent: true, kind: .ground)
        MontanaP2PTrace.mark("ground_tx", "to=\(String(peer.prefix(10))) tag=\(now.tag) bytes=\(now.g.utf8.count)")
    }
    /// My page's ground to every correspondent -- nothing to one who already has it.
    func broadcastGround() {
        for peer in MTPipeBook.all() { sendGroundIfNeeded(to: peer) }
    }
    func sendNameIfNeeded(to ref: String) {
        guard MontanaConv.holds(ref), !silenced(ref) else { return }
        let nm = Self.myDisplayName()
        guard !nm.isEmpty else { return }
        let key = MontanaDeliveryEngine.Announced.name(to: ref)
        if UserDefaults.standard.string(forKey: key) == nm { return }   // RECEIPTED with this name (15.21)
        if MontanaDeliveryEngine.shared.hasPendingState(kind: .profile, to: ref) { return }   // already on its way
        // The name rides the ONE queue, like a letter: the engine repeats it when the correspondent
        // becomes reachable; the mark is written by the receipt, never here.
        MontanaDeliveryEngine.shared.enqueue(to: ref, chat: ref, mid: ChatStore.mintMid().mid,
                                             text: nameMark + nm, silent: true, kind: .profile)
        MontanaLog.event("NAME → \(ref.prefix(10)) queued")
    }

    /// The face rides EXACTLY like the name ([C-1], the author's word 27.08): one letter in
    /// the ONE delivery queue, the picture inline in the letter's body. A long letter's body
    /// already travels as a sealed blob inside the same road — no separate manifest, no
    /// separate chunk upload, no second cargo path ever again. The tag comes from the STORED
    /// bytes, so it is the same value every sweep by construction.
    /// `requireFeed` — the sweep over EVERY pipe of the book sends only where a conversation
    /// already has letters (a dead trial pipe deserves no picture); a face asked for ONE
    /// correspondent — the chat the person just opened, the sender of the letter that just
    /// landed — goes regardless. The gate stood on both roads and a chat born from a link, empty
    /// by definition, never received a face: T2 saw T1's name and a letter, never the picture
    /// (the author, 07.09 08:16).
    func sendFace(to refs: [String], requireFeed: Bool = true) {
        let refs = refs.filter { !silenced($0) }   // a blocked person is shown no face
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let feed = await MainActor.run { Set(self.store?.messages.keys.map { String($0) } ?? []) }
            let held = refs.filter { MontanaConv.holds($0) && (!requireFeed || feed.contains($0)) }
            guard !held.isEmpty else { return }
            guard MTWalletPerson.card != nil else { return }   // the face of a person not yet read is silence, not «no face»
            guard let img = E2E.myAvatarData() else {
                // The photo is gone — that is SAID, not kept silent, once per correspondent.
                // An empty mark IS «no face» — the same shape a name letter would have.
                await MainActor.run {
                    for ref in held {
                        let key = MontanaDeliveryEngine.Announced.faceMissing(to: ref)
                        if UserDefaults.standard.string(forKey: key) == "1" { continue }   // SILENT-OK: receipted «no face»
                        if MontanaDeliveryEngine.shared.pendingStateTag(kind: .picture, to: ref) == "0" { continue }   // on its way
                        MontanaDeliveryEngine.shared.enqueue(to: ref, chat: ref, mid: ChatStore.mintMid().mid,
                                                             text: avatarMark, silent: true, kind: .picture)
                    }
                }
                return
            }
            let tag = MontanaDeliveryEngine.Announced.faceTag(img)
            // Needy = not receipted with THIS face and not already on its way (15.21).
            let needy = held.filter {
                UserDefaults.standard.string(forKey: MontanaDeliveryEngine.Announced.face(to: $0)) != tag
                    && MontanaDeliveryEngine.shared.pendingStateTag(kind: .picture, to: $0) != tag
            }
            // A STATE, NOT A PAGE (23.09, the critic): the sweep wrote this line dozens of times a minute and
            // pushed the evidence of 13:21 off the phone. It speaks when the numbers change, and once in a
            // quarter hour to prove it still runs.
            MontanaP2PTrace.markChanged("avatar_sweep", "held=\(held.count) needy=\(needy.count)", every: 900)
            guard !needy.isEmpty else { return }
            let body = avatarMark + img.base64EncodedString()
            await MainActor.run {
                for ref in needy {
                    MontanaDeliveryEngine.shared.enqueue(to: ref, chat: ref, mid: ChatStore.mintMid().mid,
                                                         text: body, silent: true, kind: .picture)
                }
                MontanaLog.event("AVATAR queued to \(needy.count) correspondents")
                MontanaP2PTrace.mark("face_tx", "queued=\(needy.count) tag=\(tag)")
            }
        }
    }
    func sendAvatarIfNeeded(to ref: String) { sendFace(to: [ref], requireFeed: false) }
    // ── receive ──
    // Call diagnostics: a line about the selected ICE pair → into the local trace.
    // Wake-up (foreground): re-establish the peer channel. The ratchet state is owned ONLY by
    // the app: nothing else advances a session, so nothing else can tear one.
    /// Attaching the store. The one place where the core learns where to put things and whom
    /// to ask; the absence of this call was the cause of the mute family below.
    func attach(store s: ChatStore) {
        store = s
        MontanaP2PTrace.mark("store_attached")
    }

    func persistHistory() { DispatchQueue.main.async { self.store?.save() } }   // force-save when going to background
    func recalcBadge() { DispatchQueue.main.async { self.store?.recalcBadge() } }
    func purgeNameArtefacts() { DispatchQueue.main.async { self.store?.purgeNameArtefacts() } }
    func remirrorShareStore() { DispatchQueue.main.async { self.store?.remirrorShareFromStore() } }
    // Lists are built on the main thread (feeds live there), while the disk is walked aside:
    // walking thousands of files on the main thread is the very delay a person sees.
    func sweepBlobs() { DispatchQueue.main.async { self.store?.sweepBlobs() } }
    /// The pipe book cannot COLLECT garbage by construction ([I-14] lifecycle): a pipe lives
    /// while its conversation lives in the feed, or while it is fresh (a trial introduction
    /// gets three days to become a conversation). A pipe with no conversation and no sign of
    /// life beyond that dies here, taking its wake registration, first-contact card and
    /// meeting memory with it (forget buries all of them). The 214 dead test pipes that
    /// turned every profile sweep into a letter storm were exactly this garbage.
    func sweepOrphanPipes() {
        DispatchQueue.main.async { [weak self] in
            let feed = Set(self?.store?.messages.keys.map { String($0) } ?? [])
            guard !feed.isEmpty else { return }   // the store is not up yet — judging by an empty feed would bury the living
            DispatchQueue.global(qos: .utility).async {
                let now = Date().timeIntervalSince1970
                let grace: Double = 3 * 24 * 3600
                // THE PIPE DIES WITH A WORD AND WITH ITS FOLDER (24.09, the author's word «do it»): the other side is told
                // over the pipe itself (pipeClosedMark) — its history stays, its composer gives way to a note — and the
                // pipe dies by that word's receipt or term, as by a tombstone's. The archive folder goes at once: its head
                // carries the secret, and every cold start's restore re-established a pipe buried here silently; a folder
                // without a usable head came back as a nameless transcript.
                let dying = Set(MTPipeBook.dyingAll())
                var closed = 0
                for conv in MTPipeBook.all() where !feed.contains(conv) && !dying.contains(conv) {
                    let alive = MTPipeBook.aliveAt(conv) ?? 0
                    guard now - alive > grace else { continue }
                    MTPipeBook.markDying(conv)
                    MontanaArchive.deleteChatFolder(convRef: conv)
                    MontanaDeliveryEngine.shared.enqueue(to: conv, chat: conv, mid: UUID().uuidString, text: pipeClosedMark, silent: true)
                    closed += 1
                }
                if closed > 0 { MontanaP2PTrace.mark("pipes_swept", "closed=\(closed) feed=\(feed.count)") }
            }
        }
    }
    func sweepMediaFiles() { DispatchQueue.main.async { self.store?.sweepMediaFiles() } }
    func sealArchiveFolderNames() { DispatchQueue.main.async { self.store?.sealArchiveFolderNames() } }
    /// Fresh name/avatar mirrors for the extension — on demand (app activation).
    /// The chat list lives in the View — it mirrors, on signal.
    func remirrorChats() { DispatchQueue.main.async { NotificationCenter.default.post(name: .montanaRemirror, object: nil) } }
    // Idempotency: the mesh delivers at-least-once — the same letter may arrive over any
    // transport, any number of times — so one id reaches ingest several times. WITHOUT a barrier, a repeat of an already
    // consumed message causes a ratchet decryption error -> the code nulled the live session
    // -> the next real message cannot be decrypted. The barrier filters the duplicate BEFORE decrypt.
    // Handshake anti-replay: the same init handshake, delivered again
    // with a new relay-id, must NOT re-establish (reset) a live session. A cache of hashes
    // of already-processed handshakes. A legitimate rekey carries a fresh ephemeral key -> a different
    // hash -> not blocked. The dedup key is the SHA-256 of the handshake's public bytes (not a secret).
    // Check (read-only): whether this handshake hash is already seen. Eviction by AGE
    // 2·ACCEPT_SKEW (spec Stage 5), not by count — an init replay within the delivery window is rejected.
    // Marked ONLY after successful processing (spec Stage 5, step 9): the cache receives the hash
    // of an established session, not any received byte stream → invalid/garbage does not pollute the cache.
    // [SSOT] unified routing of the call signal → MontanaCall (shared by ingest and push,
    // so the handleSignal signature lives in one place — [C-1]).
    // Processing of one incoming item. ack — the transport acknowledgment.
}

// ── E2E backend: the same MessagingChannel contract, but over the encrypted relay ──
final class MeshChannel: MessagingChannel {
    func fetchChats() async throws -> [Chat] { [] }         // history and list — local
    func fetchMessages(chatId: String) async throws -> [Message] { [] }
    func send(text: String, chatId: String, mid: String, silent: Bool) async throws -> Message {
        MontanaDeliveryEngine.shared.enqueue(to: chatId, chat: chatId, mid: mid, text: text, silent: silent)
        let sentId = mid
        // Do not mark .sent if nothing was sent (bundle check failure/no target): [C-2.1] — no silent failure.
        return Message(text: text, isFromMe: true, time: nowHHMM(), deliveryStatus: .sending,
                       msgId: sentId, senderRef: nil)
    }
    func subscribe(chatId: String, onNew: @escaping (Message) -> Void) {}
}



// Thumbnail for MediaRef (inline preview in the ratchet, ≤ THUMB_MAX 16 KiB).
extension UIImage {
    func mediaThumbnail(maxDim: CGFloat = 96, maxBytes: Int = 1_200) -> Data? {   // mini-thumb (blur-up placeholder); full preview loads from the blob
        let scale = min(maxDim / max(size.width, 1), maxDim / max(size.height, 1), 1)
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let small = UIGraphicsImageRenderer(size: target, format: fmt).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
        // A SEE-THROUGH PICTURE IS NOT FLATTENED ONTO WHITE (the author's word 22.09: «the sticker
        // loads as a photo on a white ground»). This mini-frame stands in the receiver's row while
        // the file is still on its way, and JPEG has no transparency -- so a sticker arrived as a
        // white square. A picture with an alpha channel rides as a small PNG instead; it keeps its
        // own ground, and its size is held down by the side, not by a quality it does not have.
        if case .some(let info) = small.cgImage?.alphaInfo,
           [CGImageAlphaInfo.first, .last, .premultipliedFirst, .premultipliedLast].contains(info) {
            var side = maxDim
            while side >= 32 {
                let fmt2 = UIGraphicsImageRendererFormat(); fmt2.scale = 1
                let k = min(side / max(size.width, 1), side / max(size.height, 1), 1)
                let box = CGSize(width: size.width * k, height: size.height * k)
                let shot = UIGraphicsImageRenderer(size: box, format: fmt2).image { _ in
                    draw(in: CGRect(origin: .zero, size: box))
                }
                if let d = shot.pngData(), d.count <= max(maxBytes, 4096) { return d }
                side = floor(side * 0.7)
            }
            return nil   // nothing honest to show: better an empty place than a white square
        }
        var q: CGFloat = 0.6
        while q > 0.1 {
            if let d = small.jpegData(compressionQuality: q), d.count <= maxBytes { return d }
            q -= 0.15
        }
        return small.jpegData(compressionQuality: 0.1)
    }
}
